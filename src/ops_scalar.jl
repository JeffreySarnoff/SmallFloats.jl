# ===== ops_scalar.jl — operation registry and scalar API (design §7.1/§10.2, architecture §6)
#
# The registry is the single source from which the package generates the
# spec-register functions (draft names, draft parameter order), the same-format
# convenience methods, and the Base-register veneers. Block/scaled variants,
# table enumeration, exhaustive test sets, and conformance() are generated from
# the same rows (blocks.jl, tables.jl, approx.jl).
#
# Evaluation contract (architecture §5.1): oracle.jl supplies
#     ωeval(::Val{op}, xs::Float64...)
#         ::Union{Float64, Float128, BigExactF, EncloseF, Enclose128F}
# and this file supplies `apply_op`, which finishes each result kind through the
# projection engine. `Float64`/`Float128` results are *exact* by construction;
# `BigExactF.f()` returns an exact BigFloat; `EncloseF` resolves through up to
# three stages (eager Float64 estimate → Float128 pre-filter → MPFR ladder);
# `Enclose128F` carries a correctly-rounded Float128 bracket with an MPFR fallback.

using Random: AbstractRNG, default_rng

# Runtime switch (Float128 revision plan §5): every Float128 path fronts a complete
# MPFR path with identical semantics, so disabling costs speed, never correctness.
# Set ENV["SmallFloats_Float128"] = "disable" before loading (read in __init__).
const _USE_FLOAT128 = Ref(true)
@inline _f128() = _USE_FLOAT128[]

"""Deferred exact result: `f()` returns the value as an exact `BigFloat`."""
struct BigExactF{F}
    f::F
end
"""
Sticky-head exact result (wide-spread tail, Float128 revision follow-on): the true
value is `v + sgn·ε` for an infinitesimal `ε > 0` — `v` carries every bit the
projection can consume and `sgn ∈ {-1,+1}` the direction of the neglected tail.
Sound because `v` is either exactly on a rounding threshold of the target grid
(where `sticky` decides, for every mode including stochastic sub-grids) or
strictly farther from the nearest threshold than the tail magnitude; the emitting
sites in oracle.jl discharge that bound (operand significands ≤ 17 bits, target
grids ≤ P−1+N ≤ 67 fractional bits, spreads > the _DE_* thresholds). Non-allocating:
replaces the BigFloat escalation for FMA/FAA."""
struct StickyF{T<:Union{Float64,Float128,Dyadic}}
    v::T
    sgn::Int
end
"""
Deferred enclosure, resolved by `_finish` through up to three stages, cheapest first:

1. `yd` — an *eager* Float64 estimate (NaN ⇒ absent) whose libm evaluation is
   faithful (≤ 1 ulp); the true value is taken to lie within `|yd|·2^-45`
   (`_F64_RELEXP`), ≥ 2^7 slacker than any faithful-libm error.
2. `fq` — a zero-argument Float128 estimator (plan Site D, Class E; `nothing` ⇒
   absent): true value within `|y|·2^-90` of `y = fq()` (`_F128_RELEXP`), a bound
   ≥ 2^18 slacker than any published libquadmath transcendental error, discharged
   empirically by the differential-build tests.
3. `f(prec)` — the rigorous MPFR ladder: directed `(lo, hi)::NTuple{2,BigFloat}`
   strictly bracketing the true value.

Each estimate stage returns only when the two-sided sticky projection of its
envelope agrees on a single code point; any disagreement (or an absent/degenerate
estimate) falls through to the next stage. Stage 3 always decides.
"""
struct EncloseF{F,G}
    f::F
    fq::G
    yd::Float64
end
EncloseF(f) = EncloseF(f, nothing, NaN)
EncloseF(f, fq) = EncloseF(f, fq, NaN)
"""
Correctly-rounded Float128 bracket (plan Site C, Class R): IEEE mandates correct
rounding for Float128 `/`, `sqrt`, `fma`, so a nearest-CR result of a value known
inexact brackets the truth in the *open* interval `(lo, hi) = (prevfloat(q), nextfloat(q))`
with no envelope assumption. `f` is the MPFR fallback for (near-impossible at P ≤ 8)
grid-straddling brackets.
"""
struct Enclose128F{F}
    lo::Float128
    hi::Float128
    f::F
end

const _F128_RELEXP = -90        # envelope exponent: E = |y|·2^-90
const _F64_RELEXP  = -45        # Float64 pre-filter envelope: E = |y|·2^-45
# The Float64 stage is sound for ops whose Float64 libm evaluation is faithful
# (error ≤ 1 ulp ≈ 2^-52 relative on normal results): 2^-45 gives ≥ 2^7 slack.
# Estimates that are non-finite, zero, or too near the subnormal range (where
# the relative-error model breaks) skip the stage; disagreement at the sticky
# gate falls through to the Float128 filter and the rigorous ladder unchanged.
const _F64_MINNORMISH = 6.7e-290   # ≈ 2^-960: comfortably clear of subnormals

@inline _finish(::Type{fr}, ρ::ProjSpec, R::Int, v::Float64) where {fr<:Binary} =
    project(fr, ρ, v; R)
@inline _finish(::Type{fr}, ρ::ProjSpec, R::Int, v::Float128) where {fr<:Binary} =
    project(fr, ρ, v; R)
@inline _finish(::Type{fr}, ρ::ProjSpec, R::Int, v::BigFloat) where {fr<:Binary} =
    project(fr, ρ, v; R)
@inline _finish(::Type{fr}, ρ::ProjSpec, R::Int, v::Dyadic) where {fr<:Binary} =
    project(fr, ρ, v; R)
@inline _finish(::Type{fr}, ρ::ProjSpec, R::Int, b::BigExactF) where {fr<:Binary} =
    project(fr, ρ, b.f(); R)
@inline _finish(::Type{fr}, ρ::ProjSpec, R::Int, s::StickyF) where {fr<:Binary} =
    project(fr, ρ, s.v; R, sticky=s.sgn)
function _finish(::Type{fr}, ρ::ProjSpec, R::Int, e::EncloseF) where {fr<:Binary}
    yd = e.yd
    if yd == yd && isfinite(yd) && abs(yd) >= _F64_MINNORMISH   # yd==yd: not NaN
        Ed = ldexp(abs(yd), _F64_RELEXP)
        dd = project(fr, ρ, yd - Ed; R, sticky=+1)
        du = project(fr, ρ, yd + Ed; R, sticky=-1)
        codepoint(dd) == codepoint(du) && return dd
    end
    if e.fq !== nothing && _f128()
        y = e.fq()::Float128
        if isfinite(y) && !iszero(y)
            E = ldexp(abs(y), _F128_RELEXP)
            d = y - E
            u = y + E
            cd = project(fr, ρ, d; R, sticky=+1)
            cu = project(fr, ρ, u; R, sticky=-1)
            codepoint(cd) == codepoint(cu) && return cd
        end
        # non-finite/zero estimate or filter disagreement: rigorous ladder decides
    end
    project_interval(fr, ρ, e.f; R)
end
function _finish(::Type{fr}, ρ::ProjSpec, R::Int, z::Enclose128F) where {fr<:Binary}
    isequal(z.lo, z.hi) && return project(fr, ρ, z.lo; R)
    cd = project(fr, ρ, z.lo; R, sticky=+1)
    cu = project(fr, ρ, z.hi; R, sticky=-1)
    codepoint(cd) == codepoint(cu) && return cd
    project_interval(fr, ρ, z.f; R)
end

"""apply_op(Val(op), fr, ρ, R, xs...) — evaluate `op`'s ω-semantics on decoded
operands and project the result into `fr` under ρ (with random bits R).

The evaluation carrier comes from the **operands**, not from `fr`. That is
`carriers.jl`'s stated rule — the carrier constrains what `ωeval` may form, never
what may be projected into a format, because `round_to_precision` works in
`(P, B)` integer space and is exact for any exact input. Stage 3 selected on
`rung(fr)` instead, as a deliberate stand-in while `decode` still refused K ≥ 9;
keeping that would have refused `Add(Binary16p2se, ρ, x8, y8)`, whose operands
are ordinary `Float64` datums and whose exact sum needs no wide carrier at all.

Completeness of the operand-only rule rests on one premise, stated because
Stage 3's version of it is what M28 was: the spec register's maximum factor
count is **2**, and the rung boundaries are stated on `2B` precisely so that a
datum on carrier `C` guarantees its square is also on `C`. Beyond two factors —
`ScaledMultiply`'s four — the monomial bound stops following from the operand
types and `rung(op, Fs...)` must be used with the formats in hand. That is why
`blocks.jl` calls the join and this does not.
"""
@inline function apply_op(op::Val, ::Type{fr}, ρ::ProjSpec, R::Int,
                          x::Float64, xs::Vararg{Float64,N}) where {fr<:Binary,N}
    res = ωeval(HeadF64(), op, x, xs...)
    # bitops plan Phase 0(a): explicit fast split — Class-1/selection results are
    # Float64 for every ordinary input; keep the widened union off the hot path.
    # Justification: like-for-like measurement (both variants under identical
    # harness conditions) showed the split alone recovering 399 → 269 ns/elem;
    # see checkpoint.md "Resolution of the two flagged measurements".
    res isa Float64 && return project(fr, ρ, res; R)
    _finish_slow(fr, ρ, R, res)
end

# The head of a value in flight, total over `CarrierValue` — all four members,
# which is the point of having named that union. Both rung-3 carriers appear:
# `Dyadic` is what `decode` produces there now, and `BigFloat` is what the
# enclosure ladder hands back for the transcendentals, so a single evaluation can
# see both.
#
# The comment here previously said "total over the carriers the ladder defines"
# while listing three of them. Adding `Dyadic` made that false, and a `MethodError`
# in G2 said so — a reminder that a totality claim in a comment is worth exactly
# as much as the dispatch under it.
@inline _headof(::Float64)  = HeadF64()
@inline _headof(::Float128) = HeadF128()
@inline _headof(::BigFloat) = HeadExact()
@inline _headof(::Dyadic)   = HeadExact()
@inline _joinheads(x) = _headof(x)
@inline _joinheads(x, ys...) = joinhead(_headof(x), _joinheads(ys...))
@noinline _finish_slow(::Type{fr}, ρ::ProjSpec, R::Int, res) where {fr<:Binary} =
    _finish(fr, ρ, R, res)

# Operands on a carrier wider than Float64 — the rung-2/3 case, refused by method
# until Stage 6 builds the carrier lattice.
#
# This method is NOT redundant with the `ωeval(::HeadF128, …)` refusal Stage 3
# added, and the gap between them is worth stating because it stayed open for a
# whole stage. Stage 3's gate is reached through `ωeval(rung(fr), op, xs...)`
# *inside* this function, so it only ever fires once `apply_op` has been entered
# — which requires the operands to be `Float64`. While `decode` refused K ≥ 9 that
# was every reachable call. Stage 4 gave `decode` the wide carriers, and from that
# moment `Exp(Binary16p5se, ρ, v)` decoded to `Float128` and missed the
# `xs::Float64...` signature entirely: a `MethodError` naming `apply_op`, not the
# stage-naming `ArgumentError` the discipline promises. Found by a table build,
# not by a test — the scalar path had the same hole.
#
# The `Float64` method above is strictly more specific, so this costs the working
# path nothing.
#
# Stage 6 turned this from a refusal into a route: it joins the operands' heads,
# lifts every operand onto the winner, and hands off. What stays refused is
# refused one layer down, by `oracle.jl`'s per-head catch-alls — the better place
# for it, because the thing that is missing IS an `ωeval` row. A head with no row
# for the carrier it was handed throws an `ArgumentError` naming the operation and
# the rung; a head with one evaluates. Neither outcome is decided here.
#
# The `lift` step is why mixed-format wide arithmetic works at all: operands of
# different formats decode to different carriers, and no `ωeval` row is written
# for a mixed pair. `lift` has no narrowing method by design, and the join is
# what makes that absence unreachable rather than a hazard — the head dominates
# every operand's own carrier, so every lift widens or is the identity.
# The vararg carries a LENGTH parameter, and that is a performance property, not
# a style choice. Written `xs...`, the two splat calls in the body compile to
# `Core._apply_iterate` — a dynamic apply — and every carrier value crossing them
# is boxed: measured at 304 bytes per warm binary call on `Float128` and 592 on
# `Dyadic`, against zero for the arity-1 case, which Julia's splat optimizer
# handles. Every *component* measured zero (`_joinheads`, `ωeval`, `lift`,
# `_finish_slow`); only the composition allocated, which is why the profile had
# to be taken at the entry point rather than assembled from the parts.
#
# `Vararg{Any,N}` specializes the method per arity, the splats become static
# calls, and the warm path returns to zero allocation at every rung — the
# property the performance rules require and that Stage 6 quietly lost when this
# method stopped being a refusal and started being a route.
@noinline function apply_op(op::Val, ::Type{fr}, ρ::ProjSpec, R::Int,
                            x, xs::Vararg{Any,N}) where {fr<:Binary,N}
    h = _joinheads(x, xs...)
    res = ωeval(h, op, lift(h, x), map(v -> lift(h, v), xs)...)
    _finish_slow(fr, ρ, R, res)
end

# ---- stochastic draw plumbing (design §5.5)
# bitops plan Phase 0(b): the rng default is `nothing`, resolved to the task-local
# default only when a stochastic draw is actually taken.
# Justification is SEMANTIC only — pure-ρ calls never touch RNG state, and array
# kernels resolve the rng once per call instead of per element. The original
# performance justification is withdrawn: controlled A/B (checkpoint.md,
# "Resolution of the two flagged measurements") showed the previous eager
# `default_rng()` kwarg default cost ≈ nothing in specialized code (25.4 vs
# 26.5 ns/elem); the 1,347 ns reading that motivated it was dynamic keyword
# dispatch through a non-const global in the measurement harness, not this code.
const MaybeRNG = Union{Nothing,AbstractRNG}
"""An explicit stochastic draw `R`, or `nothing` to draw one from the rng."""
const MaybeR = Union{Nothing,Int}

"""Resolve a caller-supplied rng, falling back to the task-local default. Call
sites hoist this out of loops so array kernels resolve once per call, not per
element."""
@inline _resolve_rng(rng::MaybeRNG) = rng === nothing ? default_rng() : rng
"""The rng an operation under ρ will actually draw from — `nothing` for pure ρ,
which must never touch RNG state."""
@inline _rng_for(ρ::ProjSpec, rng::MaybeRNG) = isstochastic(ρ) ? _resolve_rng(rng) : nothing
@inline function _drawR(ρ::ProjSpec, rng::MaybeRNG, R::MaybeR)
    isstochastic(ρ) || return 0
    N = nrandbits(ρ)
    if R === nothing
        r = _resolve_rng(rng)
        return Int(rand(r, UInt64) & ((UInt64(1) << N) - 1))
    end
    0 <= R < (1 << N) || throw(ArgumentError("explicit R=$R outside 0:$(2^N - 1) for N=$N random bits"))
    return R
end

# ---- the operation registry (draft §5.4 substitution lists)
struct OpInfo
    name::Symbol
    arity::Int
    group::Symbol   # :A arithmetic, :B elementary, :C extremum/misc, :conv
    # Maximum number of datum factors in any monomial of the exact result. It is
    # the carrier-width driver, not the arity: `FAA` takes three operands and
    # forms `x + y + z`, whose monomials are single factors, while `Multiply`
    # takes two and forms `x·y`. The carrier join reads this and nothing else
    # about the operation.
    #
    # It lives here rather than in a table beside `blocks.jl` because the
    # `Block*`/`Scaled*` variants are GENERATED from these rows and derive their
    # own counts by adding scale factors (invariant 7). A hand-maintained second
    # list is exactly the divergence the registry exists to prevent — and this
    # column is the one whose staleness would be silent, since a factor count
    # that is too low picks a carrier that overflows rather than one that errors.
    factors::Int
end
const OP_REGISTRY = OpInfo[]
register_op!(name::Symbol, arity::Int, group::Symbol, factors::Int=1) =
    push!(OP_REGISTRY, OpInfo(name, arity, group, factors))
opinfo(name::Symbol) = OP_REGISTRY[findfirst(o -> o.name === name, OP_REGISTRY)]

const _UNARY_OPS = (:Abs, :Negate, :Sqrt, :RSqrt, :Recip, :Exp, :Log, :ExpMinusOne,
    :LogOnePlus, :Exp2, :Log2, :Sin, :Cos, :Tan, :ArcSin, :ArcCos, :ArcTan,
    :Sinh, :Cosh, :Tanh, :ArcSinh, :ArcCosh, :ArcTanh,
    :SinPi, :CosPi, :TanPi, :ArcSinPi, :ArcCosPi, :ArcTanPi, :Softplus)
const _BINARY_OPS = (:CopySign, :Add, :Subtract, :Multiply, :Divide, :Hypot,
    :ArcTan2, :ArcTan2Pi, :Maximum, :Minimum, :MaximumNumber, :MinimumNumber,
    :MaximumMagnitude, :MinimumMagnitude, :MaximumMagnitudeNumber,
    :MinimumMagnitudeNumber, :MinimumFinite, :MaximumFinite)
const _TERNARY_OPS = (:FMA, :FAA, :Clamp)

# The two-factor operations, named once. Everything else forms sums or selections
# of single datums. `Divide`'s exact result spans `e_x − e_y`, which is the same
# width as a product's `e_x + e_y`; `Hypot` forms `x² + y²`; `FMA` forms `x·y + z`.
# `RSqrt`/`Recip` are one factor: `1/x` spans `−e_x`, no wider than `x` itself.
const _TWO_FACTOR_OPS = (:Multiply, :Divide, :Hypot, :FMA)
_nfactors(n::Symbol) = n in _TWO_FACTOR_OPS ? 2 : 1

for n in _UNARY_OPS;   register_op!(n, 1, n in (:Abs, :Negate) ? :A : :B, _nfactors(n)); end
for n in _BINARY_OPS;  register_op!(n, 2, n in (:Add, :Subtract, :Multiply, :Divide, :CopySign) ? :A : :C, _nfactors(n)); end
for n in _TERNARY_OPS; register_op!(n, 3, :A, _nfactors(n)); end
register_op!(:Convert, 1, :conv, 1)

# Registry-driven, so the carrier join reads the same rows that generate the
# operations (invariant 7). Dispatched on `Val` so `opfactors(op)` folds to a
# literal wherever the operation is statically known — which is what lets
# `rung(op, Fs...)` fold, and G9 pins that.
for op in OP_REGISTRY
    @eval @inline opfactors(::Val{$(QuoteNode(op.name))}) = $(op.factors)
end
@noinline opfactors(::Val{OP}) where {OP} = throw(ArgumentError(
    "$OP is not in OP_REGISTRY, so its factor count — and therefore its " *
    "evaluation carrier — is undefined"))

# ---- generated spec register + same-format convenience methods
# Spec form follows the draft's parameterization order: Op(f_r, ρ, operands...).
# One shape, generated at every arity: the three hand-written branches were the
# same two methods with one, two, or three operands spelled out. Arity now comes
# from the registry row, so a change to the calling convention — the keyword set,
# the draw, the decode step — cannot land unevenly across arities.
for op in OP_REGISTRY
    op.name === :Convert && continue
    name = op.name; V = Val{name}
    xs = [Symbol(:x, i) for i in 1:op.arity]
    spec_args = [:($x::Binary) for x in xs]               # spec form: any formats
    same_args = [:($x::T) for x in xs]                    # convenience form: one format
    decoded = [:(decode($x)) for x in xs]
    @eval begin
        @inline function $name(fr::Type{<:Binary}, ρ::ProjSpec, $(spec_args...);
                               rng::MaybeRNG=nothing, R::MaybeR=nothing)
            apply_op($V(), fr, ρ, _drawR(ρ, rng, R), $(decoded...))
        end
        # The convenience form follows the session default, consumed through the
        # same speculation guard `with_default_projection` uses: while the default
        # holds its initial value the call is compiled against that constant and
        # is allocation-free, exactly like naming ρ explicitly. The guard is
        # spelled out here rather than passed as a closure because a closure
        # defeats `apply_op`'s Float64/escalation union split — the ops whose
        # ωeval can escalate (Add, Subtract, Divide, Hypot) then box their result.
        @inline function $name($(same_args...); kw...) where {T<:Binary}
            ρ = DefaultProjection()
            ρ === _GUARD_PROJECTION && return $name(T, _GUARD_PROJECTION, $(xs...); kw...)
            $name(T, ρ, $(xs...); kw...)
        end
    end
end

# ---- Convert (draft §4.9): the one op accepting external operands
"""
    Convert(fr, ρ, x) -> fr

Draft §4.9 Convert⟨f_x, f_r, ρ⟩. Accepts `Binary`, IEEE binary16/32/64
floats (widened exactly to the Float64 carrier), `Float128` (projected directly),
`Dyadic` (the rung-3 datum carrier — what `decode` returns for the eight rung-3
formats; projected directly and exactly), `Integer` (exact via a sufficiently
wide BigFloat), and `BigFloat` (projected directly; the caller warrants the
value is exact).
"""
@inline function Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::Binary;
                         rng::MaybeRNG=nothing, R::MaybeR=nothing)
    project(fr, ρ, decode(x); R=_drawR(ρ, rng, R))
end
@inline function Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::Union{Float64,Float32,Float16};
                         rng::MaybeRNG=nothing, R::MaybeR=nothing)
    project(fr, ρ, Float64(x); R=_drawR(ρ, rng, R))   # exact widening
end
@inline function Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::Float128;
                         rng::MaybeRNG=nothing, R::MaybeR=nothing)
    project(fr, ρ, x; R=_drawR(ρ, rng, R))            # preserve all 113 significand bits
end
function Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::Integer;
                 rng::MaybeRNG=nothing, R::MaybeR=nothing)
    b = BigFloat(x; precision=max(64, ndigits(x, base=2) + 8))       # exact
    project(fr, ρ, b; R=_drawR(ρ, rng, R))
end
function Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::BigFloat;
                 rng::MaybeRNG=nothing, R::MaybeR=nothing)
    project(fr, ρ, x; R=_drawR(ρ, rng, R))
end
# `Dyadic` is the rung-3 datum carrier — what `decode` RETURNS for the eight
# rung-3 formats — so this row is the inverse of the package's most basic query.
# Without it `T(decode(v))` was a `MethodError` on exactly those formats and
# worked on the other 496: `Dyadic <: Real`, so `(::Type{T})(x::Real)` in
# formats.jl dispatched happily and then failed two frames deeper, naming
# `Convert` — an internal function the caller never wrote. A signature that
# claims `Real` has to honour `Real`.
#
# Deliberately a method rather than an absent one *and* rather than a stated
# refusal. The package's "refuse by method" rule (decode_encode.jl, oracle.jl)
# earns its exception from JET: a missing method reached through an inferred
# `Union` is reported as a package defect. No `Union` reaches here — package
# code projects decoded datums through `project`, never through `Convert` — so
# that justification is absent, and a method existing only to throw would make
# `hasmethod` and `applicable` answer `true` for something that does not work.
#
# Accepting the internal carrier as an INPUT is not the obligation carriers.jl's
# two-trait split refuses. That split is about promotion TARGETS:
# `promotecarrier` never names `Dyadic`, so `x + 1.0` still lands on a type with
# a complete `Real` interface. Nothing here changes that.
#
# The body is the `Float128` row's, for the same reason: `project` is
# carrier-generic (§1 C10), so the projection is exact and there is nothing to
# widen or narrow first.
@inline function Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::Dyadic;
                         rng::MaybeRNG=nothing, R::MaybeR=nothing)
    project(fr, ρ, x; R=_drawR(ρ, rng, R))
end
Convert(fr::Type{<:Binary}, ρ::ProjSpec, x::AbstractFloat; kw...) = Convert(fr, ρ, Float64(x); kw...)

# closes the constructor loop declared in formats.jl
@inline _convert_default(::Type{T}, v::T) where {T<:Binary} = v
@inline _convert_default(::Type{T}, x) where {T<:Binary} =
    with_default_projection((ρ, v) -> Convert(T, ρ, v), x)

# The Base register (design §10.2) — the Base-function veneers over these
# spec-register calls — lives in juliacompat.jl, mapped declaratively from the
# op lists above.
