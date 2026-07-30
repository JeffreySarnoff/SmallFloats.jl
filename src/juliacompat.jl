# ===== juliacompat.jl — the Base register (design §10.2)
#
# Base-function veneers for every draft operation that has a Base counterpart.
# Every method here is exactly one same-format spec-register call under the
# session default projection; there is no third semantics.
#
# The mapping is a declarative table partitioned over the op lists in
# ops_scalar.jl (_UNARY_OPS / _BINARY_OPS / _TERNARY_OPS): each op is either
# mapped below or listed in _NO_BASE_COUNTERPART with the reason class. The
# suite asserts that partition is exhaustive, so adding an op to a list forces
# a decision here — the same non-divergence mechanism as the registry.
#
# Scope decisions:
#   · Same-format operands only. Promotion between distinct Binary formats is
#     deliberately absent (design §2.4) — mixing formats is an explicit
#     `Convert`, not a silent widening. Binary ⋄ Float64/32/16/Integer promotes
#     to Float64 through the rules in formats.jl, as before.
#   · The extremum veneers map Base's IEEE semantics: `min`/`max` propagate NaN,
#     which is exactly draft Minimum/Maximum. The NaN-ignoring (Number),
#     magnitude, and finite families have no Base spelling — call them by their
#     draft names.

# ---- unary: plain Base name ⇒ draft op
const _BASE_UNARY = (
    :Abs => :abs,   :Recip => :inv,  :Sqrt => :sqrt,
    :Exp => :exp,   :Exp2 => :exp2,  :ExpMinusOne => :expm1,
    :Log => :log,   :Log2 => :log2,  :LogOnePlus => :log1p,
    :Sin => :sin,   :Cos => :cos,    :Tan => :tan,
    :ArcSin => :asin, :ArcCos => :acos, :ArcTan => :atan,
    :Sinh => :sinh, :Cosh => :cosh,  :Tanh => :tanh,
    :ArcSinh => :asinh, :ArcCosh => :acosh, :ArcTanh => :atanh,
    :SinPi => :sinpi, :CosPi => :cospi, :TanPi => :tanpi,
)
for (op, bf) in _BASE_UNARY
    @eval Base.$bf(x::Binary) = $op(x)
end

# ---- operators and irregular spellings (arity or argument order differs)
Base.:-(x::Binary) = Negate(x)                                  # unary minus
Base.:+(x::T, y::T) where {T<:Binary} = Add(x, y)
Base.:-(x::T, y::T) where {T<:Binary} = Subtract(x, y)
Base.:*(x::T, y::T) where {T<:Binary} = Multiply(x, y)
Base.:/(x::T, y::T) where {T<:Binary} = Divide(x, y)
Base.atan(y::T, x::T) where {T<:Binary} = ArcTan2(y, x)         # Base's (y, x) order
const _BASE_OPERATOR = (:Negate, :Add, :Subtract, :Multiply, :Divide, :ArcTan2)

# ---- binary: plain Base name ⇒ draft op, same format
const _BASE_BINARY = (
    :CopySign => :copysign, :Hypot => :hypot,
    :Maximum => :max, :Minimum => :min,
)
for (op, bf) in _BASE_BINARY
    @eval Base.$bf(x::T, y::T) where {T<:Binary} = $op(x, y)
end

# ---- ternary
Base.fma(x::T, y::T, z::T) where {T<:Binary} = FMA(x, y, z)
Base.muladd(x::T, y::T, z::T) where {T<:Binary} = FMA(x, y, z)  # one rounding, like fma
Base.clamp(x::T, lo::T, hi::T) where {T<:Binary} = Clamp(x, lo, hi)
const _BASE_TERNARY = (:FMA, :Clamp)

# ---- composites: Base functions with no single draft op, defined componentwise
# from draft ops so each component carries its defined result
Base.sincos(x::Binary) = (Sin(x), Cos(x))
Base.sincospi(x::Binary) = (SinPi(x), CosPi(x))
Base.minmax(x::T, y::T) where {T<:Binary} = (Minimum(x, y), Maximum(x, y))

# ---- draft ops with no Base counterpart — call these by their draft names.
# Kept as one auditable set; the suite asserts mapped ∪ this == every op list.
const _NO_BASE_COUNTERPART = (
    :RSqrt, :Softplus,                                   # no Base function
    :ArcSinPi, :ArcCosPi, :ArcTanPi, :ArcTan2Pi,         # Base has sinpi-family only
    :MaximumNumber, :MinimumNumber,                      # Base has no NaN-ignoring pair
    :MaximumMagnitude, :MinimumMagnitude,
    :MaximumMagnitudeNumber, :MinimumMagnitudeNumber,
    :MinimumFinite, :MaximumFinite,
    :FAA,                                                # no Base fused add-add
)

# ---- projection-first unary convenience: Op(ρ, x) ⇒ Op(typeof(x), ρ, x)
# The result format defaults to the operand's format; keywords (rng, R) pass
# through unchanged. Generated from the registry's unary list (the
# non-divergence mechanism), scalar and array forms alike. The remaining
# convenience form, Op(x), already exists in ops_scalar.jl — the same-format
# method under the session default projection — and is deliberately not
# redefined here.
for op in _UNARY_OPS
    @eval begin
        @inline $op(ρ::ProjSpec, x::Binary; kw...) = $op(typeof(x), ρ, x; kw...)
        $op(ρ::ProjSpec, A::AbstractArray{T}; kw...) where {T<:Binary} =
            $op(T, ρ, A; kw...)
    end
end

# ===========================================================================
# The `AbstractFloat` contract (docs/other/morejulian.md, Tier 1)
# ===========================================================================
#
# `Binary <: AbstractFloat` is a promise. Generic Julia code reaches for that
# interface without asking, and several pieces of it were simply absent — failing
# at a *user's* call site with a bare `MethodError` indistinguishable from a
# defect.
#
# Two rules govern everything below.
#
# **No method here may round outside `project`.** Where a Base verb's contract
# would force a rounding the engine did not perform, the method refuses rather
# than inventing one (invariant 1).
#
# **A refusal says so.** The package had no deliberate-refusal mechanism at all:
# `frexp`, `significand` and `exponent` gave bare `MethodError`s, and `rem`'s
# apparently-clear message came from Base's promotion machinery rather than from
# here. `_unsupported` makes "absent" and "refused" visibly different — §11 M44's
# lesson pointed at users instead of at the suite.

"""Refuse a Base verb with a reason. Absence and refusal must not look alike."""
@noinline _unsupported(f, ::Type{T}, why::AbstractString) where {T<:Binary} =
    throw(ArgumentError("$(f) is not defined for $(T): $why"))

# ---- decompose ⇒ hash ⇒ Dict keys and Set elements
#
# `Base.hash(::Real, ::UInt)` is written in terms of `Base.decompose`, so its
# absence meant `hash` threw and no `Binary` value could be a dictionary key —
# the first thing a code-point histogram needs. The method existed for the
# INTERNAL `Dyadic` carrier and never for the public type.
#
# A P3109 datum IS `S · 2^Q`, and the engine already computes that split:
# `round_to_precision` on an exact datum is pure extraction, not rounding — the
# identity T1 asserts over all 7 602 160 code points. Reusing it means the triple
# cannot drift from the engine's own normalization.
#
# `hash`/`isequal` consistency comes free and is easier here than in Base: P3109
# has a single NaN and no negative zero, so neither of the two hazards that make
# float hashing subtle exists.
function Base.decompose(v::Binary)
    d = decode(v)
    isnan(d) && return (0, 0, 0)
    isinf(d) && return (signbit(d) ? -1 : 1, 0, 0)
    T = typeof(v)
    r = round_to_precision(precision(T), expbias(T), NearestTiesToEven(), d, 0, 0)
    (Int(r.sign) * Int(r.S), Int(r.Q), 1)
end

# ---- widen: the format's promotion carrier
#
# Base uses `widen` for accumulation. The honest widening of a format is not
# another format — docs/other/promoterules.md shows the grid is not a join
# semilattice, and 40.3% of format pairs have no common format at all — but the
# carrier promotion already targets.
Base.widen(::Type{T}) where {T<:Binary} = promotecarrier(T)

# ---- exponent, significand, frexp
#
# `exponent` is exact and defined for every finite nonzero datum.
function Base.exponent(v::Binary)
    d = decode(v)
    (isfinite(d) && !iszero(d)) ||
        throw(DomainError(v, "exponent is defined only for finite nonzero values"))
    Int(exponent(d))
end

# `significand` must return the SAME type (Base's contract), and the significand
# of a datum is not always a datum of its own format.
#
# **Whether it can be is a property of the FORMAT, not of the value**, so it is
# decided once, statically, rather than by round-tripping each call through
# `project` and `decode`. `significand(x) ∈ [1, 2)` needs the binade `e = 0` fully
# populated: `2^(P-1)` code points at exponent 0. An extended format spends its
# top magnitude code on `Inf`, so that binade is complete unless it IS the top
# binade — which happens only when the exponent range has nothing above it.
#
# `_binade0_complete` is a pure function of the type parameters and constant-folds
# to a literal `true` for all but a handful of degenerate formats, so the check
# costs nothing on the path that succeeds.
@inline _binade0_complete(::Type{T}) where {T<:Binary} =
    !isextended(T) || expbias(T) > 1

function Base.significand(v::T) where {T<:Binary}
    d = decode(v)
    (isfinite(d) && !iszero(d)) ||
        throw(DomainError(v, "significand is defined only for finite nonzero values"))
    _binade0_complete(T) || _unsupported("significand", T,
        "the binade [1, 2) of this format is truncated by its Inf encoding, so a " *
        "significand is not always a datum of it, and rounding one here would " *
        "round outside `project`. Use `significand(decode(x))`.")
    # exact: scaling by a power of two moves the exponent field and nothing else
    project(T, ProjSpec(NearestTiesToEven(), SatNone()), ldexp(d, -Int(exponent(d))))
end

Base.frexp(v::T) where {T<:Binary} = (significand(v) / T(2), exponent(v) + 1)

# ---- round / floor / ceil / trunc
#
# One rounding, not two: the integer-valued result is formed **exactly on the
# carrier** and projected once. Every carrier implements these natively —
# `Dyadic`'s were added in `dyadic.jl` as integer shifts precisely so this path
# does not route through `BigFloat` and allocate at rung 3.
#
# The saturation mode is the session default's, so these agree with the other
# Base verbs about what happens at the top of the range; the ROUNDING is the one
# the verb names, which is the whole point of calling `floor` rather than `round`.
for (verb, mode) in ((:trunc, :(TowardZero())), (:floor, :(TowardNegative())),
                     (:ceil, :(TowardPositive())), (:round, :(NearestTiesToEven())))
    @eval function Base.$verb(v::T) where {T<:Binary}
        d = decode(v)
        isfinite(d) || return v                      # NaN and ±Inf are fixed points
        project(T, ProjSpec($mode, saturationmode(default_projspec(T))), $verb(d))
    end
end

# `RoundingMode` arguments route through the existing `projmode` shim, so
# `round(x, RoundUp)` means what it means everywhere else in Julia.
#
# **One method per mode, not one generic `::RoundingMode`.** Base specializes
# `round` on individual `RoundingMode` singletons for `AbstractFloat`, so a
# method generic in the mode and specific in the type is *ambiguous* with three
# of them — `detect_ambiguities` said so immediately. Enumerating the modes fixes
# that and buys something better: the list below IS the statement of which Julia
# rounding modes have a P3109 counterpart, checked by the compiler rather than
# asserted in a comment.
for R in (:Nearest, :NearestTiesAway, :Up, :Down, :ToZero)
    @eval function Base.round(v::T, r::RoundingMode{$(QuoteNode(R))}) where {T<:Binary}
        d = decode(v)
        isfinite(d) || return v
        project(T, ProjSpec(projmode(r), saturationmode(default_projspec(T))),
                round(d, r))
    end
end

# The two Base modes with no draft counterpart. `RoundNearestTiesUp` breaks ties
# toward +∞ where the draft offers only ties-to-even and ties-away;
# `RoundFromZero` has no μ at all. Refusing by name beats inheriting Base's
# `AbstractFloat` fallback, which would compute on the carrier and project a
# result the draft never defined.
for R in (:NearestTiesUp, :FromZero)
    @eval Base.round(::T, ::RoundingMode{$(QuoteNode(R))}) where {T<:Binary} =
        _unsupported("round(x, Round" * $(string(R)) * ")", T,
            "the draft defines no such rounding mode. Its μ are " *
            "RoundNearest (ties to even), RoundNearestTiesAway, RoundUp, " *
            "RoundDown and RoundToZero, plus ToOdd and the three stochastic " *
            "families, which have no `RoundingMode` spelling — name a `ProjSpec` " *
            "instead.")
end

# ---- deliberate refusals, stated
#
# `rem`/`mod` have no draft counterpart and no unambiguous P3109 reading: the
# exact remainder is frequently not a datum, so every answer would be a rounding
# the draft does not define. Refused by name rather than by absence.
for f in (:rem, :mod)
    @eval Base.$f(::T, ::T) where {T<:Binary} = _unsupported($(QuoteNode(f)), T,
        "the draft defines no remainder; the exact result is generally not a " *
        "datum, so any answer would round outside `project`. Compute on " *
        "`decode(x)` and `Convert` back if that is what you want.")
end

# ===========================================================================
# `Op` — the operation register as a callable, so `map` and broadcast work
# ===========================================================================
#
# `vmap!(dest, Val(:Add), T, ρ, A, B)` exists for a real reason: `map` cannot
# express `(operation, result format, projection)`. The cost was that users had
# to learn a second word for something Julia already has two words for.
#
# `Op` carries all three in its TYPE, so it is a singleton and calls specialize
# exactly as the explicit register does. `vmap!` remains the in-place,
# table-aware kernel underneath and is still what you want with a destination to
# fill.
#
# The call methods are GENERATED FROM `OP_REGISTRY`, one per operation, and that
# is a performance decision rather than a stylistic one. A single method body
# reading `getfield(SmallFloats, name)` is a module lookup Julia will not always
# fold, so the operation would resolve at *run* time — turning a specialized call
# into a dynamic one on the array path this type exists to serve. Generating from
# the registry also means a new operation gains a callable with no edit here
# (invariant 7).
"""
    Op(name::Symbol, FR::Type{<:Binary}, ρ::ProjSpec) -> Op

A registry operation bound to a result format and a projection, as a **callable**
— so the idiomatic array verbs work directly:

```julia
map(Op(:Add, Binary8p4se, RNE_SN), A, B)
Op(:Exp, Binary8p4se, RNE_SN).(A)
```

`Op` is a singleton type: the operation, format and projection all live in the
type parameters, so calls specialize exactly as `Add(Binary8p4se, RNE_SN, x, y)`
does. Use [`vmap!`](@ref) when you have a destination array to fill — it is the
in-place, table-aware kernel and this type is a thin front for it.
"""
struct Op{name,FR,RHO}
    function Op{name,FR,RHO}() where {name,FR,RHO}
        name isa Symbol ||
            throw(ArgumentError("Op's operation parameter must be a Symbol, got $name"))
        FR <: Binary ||
            throw(ArgumentError("Op's result format must be a Binary format, got $FR"))
        any(o -> o.name === name, OP_REGISTRY) ||
            throw(ArgumentError("Op(:$name, …): :$name is not an operation in " *
                                "OP_REGISTRY. Registry names are the draft §3.2 " *
                                "spellings — :Add, :Multiply, :Exp, …"))
        new{name,FR,RHO}()
    end
end
Op(name::Symbol, ::Type{FR}, ρ::ProjSpec) where {FR<:Binary} =
    Op{name,FR,typeof(ρ)}()

# `Vararg{Binary,N}` rather than `Binary...`, defensively: §11 M46 measured the
# untyped form boxing 304 bytes per call in `apply_op`, and the length parameter
# costs nothing here.
#
# A note on how that was checked, because the first measurement was wrong. A
# probe reading 48 bytes per call looked like the same defect — and was the
# harness: the format entered through a non-`const` global, which is the ~1 µs
# dynamic-dispatch trap CLAUDE.md's performance rules name explicitly. Rebuilt
# with the format as a type parameter, `Op` allocates **zero**, and where the
# direct call allocates (a rung-2 or rung-3 `Exp` escalating into the MPFR
# ladder) `Op` allocates exactly the same amount. `Op` adds nothing.
for op in OP_REGISTRY
    @eval @inline (::Op{$(QuoteNode(op.name)),FR,RHO})(x::Binary,
                                                       xs::Vararg{Binary,N}) where {FR,RHO,N} =
        $(op.name)(FR, RHO(), x, xs...)
end

Base.show(io::IO, ::Op{name,FR,RHO}) where {name,FR,RHO} =
    print(io, "Op(:", name, ", ", formatname(FR), ", ", RHO(), ")")

# ---- similar: stop the abstract element type propagating
#
# `Vector{Binary{8,4,true,true}}` has a NON-isbits element type and boxes every
# element. Nothing errors — the package normalizes the abstract format at each
# entry point, so every answer is right and the entire performance story is gone,
# silently.
#
# The three signatures are not redundant, and the reason is a fact about Julia
# dispatch rather than about this package: **Base fixes the DIMENSION**
# (`similar(::Vector{T})`, `similar(::Matrix{T})`), and a fixed dimension outranks
# a bounded element type. A single `similar(a::Array{T,N}) where {T<:Binary,N}`
# loses to `Base.similar(::Vector{T})` and never fires for the containers users
# actually hold — a method that silently does not run, which is worse than none.
#
# This stops the abstraction PROPAGATING; it cannot stop it arising, because
# `Vector{Binary{8,4,true,true}}(undef, n)` is a constructor call with no hook.
# That entry is documented in the user guide's performance section instead.
@inline _concrete_elt(::Type{T}) where {T<:Binary} =
    isconcretetype(T) ? T : reptype(T)

Base.similar(a::AbstractArray{T}) where {T<:Binary} = similar(a, _concrete_elt(T))
Base.similar(a::Vector{T}) where {T<:Binary} = Vector{_concrete_elt(T)}(undef, length(a))
Base.similar(a::Matrix{T}) where {T<:Binary} = Matrix{_concrete_elt(T)}(undef, size(a))

# ---- reinterpret: it already worked; now it is stated and gated
#
# `Binary` is `isbits`, so Julia's generic `reinterpret` has always applied — and
# it is *the* idiomatic Julia spelling for "same bits, different type". It was
# neither documented nor tested, and it bypassed the representation invariant:
# nothing stopped `reinterpret(Binary3p1se, 0xFF)` producing a value with high
# bits set, which invariant 3 says cannot exist.
#
# This method is more specific than Base's, so it wins for the common route and
# checks what the unchecked path never could. `rawvalue` remains the deliberately
# unchecked kernel route; what changes is that the *idiomatic* spelling is now the
# safe one.
#
# The other direction needs no check: invariant 3 says the high bits are already
# zero, and T1 asserts it at every K over all 7 602 160 code points.
function Base.reinterpret(::Type{T}, u::U) where {T<:Binary,U<:Unsigned}
    sizeof(U) == sizeof(T) ||
        throw(ArgumentError("reinterpret($T, ::$U): sizes differ " *
                            "($(sizeof(T)) vs $(sizeof(U)) bytes)"))
    u <= codemask(T) ||
        throw(ArgumentError("reinterpret($T, $(repr(u))): the code point must " *
                            "occupy the low $(bitwidth(T)) bits (representation " *
                            "invariant 3); high bits are set. Use `T(u)` for a " *
                            "range-checked code point."))
    rawvalue(T, codeunit_type(T)(u))
end
