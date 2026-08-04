# ===== blocks.jl — blocks, scaled operations, reductions (design §6, architecture §8)
#
# A block is (scale, elements): draft §5. The elementwise §5.4 schema is
# implemented ONCE (decode all operand blocks → ω-op lanewise → BlockProject
# against the supplied result scale), and Block*/Scaled* variants for every
# registry operation are generated from it — the non-divergence mechanism.
#
# Correctness of the division-by-result-scale composition, per result kind:
#   Float64 exact V   : one correctly rounded directed division IS the enclosure
#                       (collapses to exact when V/S is representable, e.g. every
#                       P=1 power-of-two scale — the draft's own NOTE — for free)
#   Float128 exact V  : exact BigFloat conversion (≥128 bits), then one directed division
#   BigExactF         : evaluated exactly (see `bigprec`); dividing at ≥ that precision
#                       makes the conversion exact, so again one directed division
#   EncloseF (d,u)    : interval-divided by the exact scale, sign-aware
#   Enclose128F       : its MPFR fallback `f` is an EncloseF-shaped ladder — reuse it
# Reductions use an exact wide-precision accumulator (precision chosen from the
# operand structure ⇒ provably exact); the register-resident superaccumulator is
# the tracked Phase-3 optimization (checkpoint.md).

"""
    Block{B, FS<:Binary, FE<:Binary}

A P3109 block `(s, [x₁ … x_B])`: scale factor in format `FS`, `B ≥ 1` elements in
format `FE` (draft §5). `isbits`; blocks live in registers/stack.
"""
struct Block{B,FS<:Binary,FE<:Binary}
    s::FS
    x::NTuple{B,FE}
    # The element type is spelled out on the first lane rather than as
    # `NTuple{B,FE}`: an empty tuple would leave FE unbound (Aqua's unbound-type-
    # parameter gate). B ≥ 1 is therefore a signature property, and the empty
    # case falls to the explicit method below.
    function Block(s::FS, x::Tuple{FE,Vararg{FE,Bm1}}) where {Bm1,FS<:Binary,FE<:Binary}
        new{Bm1 + 1,FS,FE}(s, x)
    end
end
Block(::Binary, ::Tuple{}) = throw(ArgumentError("block size B must be ≥ 1"))
Block(s::Binary, xs::Binary...) = Block(s, xs)
blocksize(::Block{B}) where {B} = B
scaleformat(::Block{B,FS,FE}) where {B,FS,FE} = FS
elemformat(::Block{B,FS,FE}) where {B,FS,FE} = FE

"""ωBlockDecode (draft §5.1.1): per lane ωMultiply(decode(s), decode(xᵢ)), exact on
the carrier the block's two formats jointly require.

The carrier is keyed on `rung(Val(:Multiply), FS, FE)` — **not** on either
format's own rung, and that distinction is the whole content of this method. A
block's scale and element formats are independent, and what has to fit is their
*product*: `carriers.jl`'s rule is `ΣBᵢ ≤ emax`, so two formats that are each
rung 1 at `2B ≤ 1024` can compose into a lane product needing `B_S + B_E` well
past it. Asserting `carriertype(rung(FE))` would be wrong in the worst way
available here — the overflow produces `±Inf`, a plausible special value, rather
than an error.

The assertion stays because it is load-bearing for more than documentation: it
is what keeps the returned `NTuple` concretely typed, and with it the reductions
downstream allocation-free. It now names a carrier computed from both formats
instead of a constant."""
@inline blockdecode(b::Block{B,FS,FE}) where {B,FS,FE} =
    _blockdecode(Val(precision(FS) == 1), b)

@inline function _blockdecode(::Val{false}, b::Block{B,FS,FE}) where {B,FS,FE}
    h = rung(Val(:Multiply), FS, FE)
    C = carriertype(h)
    S = lift(h, decode(b.s))
    ntuple(i -> ωeval(h, Val(:Multiply), S, lift(h, decode(b.x[i])))::C, Val(B))
end

# ---- the P = 1 scale fast path (§4 Stage 7 item 5).
#
# A P = 1 datum is exactly `±2^e`, i.e. `Dyadic(±1, e)`. So scaling an element by
# it is `Dyadic(S_elem, Q_elem + e_scale)` — a change to the exponent FIELD, with
# no multiply, no significand growth, and no overflow question to answer. On
# `Float64` or `Float128` the same operation is an `ldexp` that can leave the
# carrier's range entirely.
#
# The hardest corner of the grid is therefore the cheapest one, and Annex F makes
# it the COMMON one rather than a curiosity: `Binary8p1uf` is OCP's **E8M0**, the
# scale format of MX-style block arithmetic, and `Binary16p1uf` is its 16-bit
# analogue. This is the block hot path, not an edge case.
#
# Guarded by `precision(FS) == 1` at the type level, so the branch is resolved at
# compile time and the general path above is untouched for every other format.
# Written against `ldexp` rather than against `Dyadic` directly, so it is one
# implementation across all three carriers: on `Dyadic` it is the exponent-field
# add above, on `Float64`/`Float128` the hardware scaling instruction. Neither can
# overflow here, because the carrier was chosen by `rung(Val(:Multiply), FS, FE)`
# — the ΣB rule already reserved room for the product this replaces.
#
# The scale's SIGN is applied separately: a P = 1 datum is `±2^e`, and `exponent`
# discards the sign, so `signbit` carries it. For the unsigned P = 1 formats —
# E8M0 and its 16-bit analogue, the ones this path exists for — that branch is
# statically false.
@inline function _blockdecode(::Val{true}, b::Block{B,FS,FE}) where {B,FS,FE}
    h = rung(Val(:Multiply), FS, FE)
    C = carriertype(h)
    s = decode(b.s)
    # ±0, ±Inf and NaN scales carry the draft's fold algebra, not an exponent;
    # they are rare and go through the general path rather than duplicating it.
    (isfinite(s) & !iszero(s)) || return _blockdecode(Val(false), b)
    e = Int(exponent(s))
    neg = signbit(s)
    ntuple(Val(B)) do i
        d = lift(h, decode(b.x[i]))
        r = isfinite(d) ? ldexp(d, e) : d
        (neg ? -r : r)::C
    end
end

# ---- ωBlockProject element pipeline (draft §5.1.2)
_res_sign(v::CarrierValue) = Float64(sign(v))
_res_sign(b::BigExactF) = Float64(sign(b.f()))
function _res_sign(e::EncloseF)
    d, u = e.f(256)
    s = sign(d)
    iszero(s) ? sign(u) : s
end
function _res_sign(z::Enclose128F)
    s = Float64(sign(z.lo))
    iszero(s) ? Float64(sign(z.hi)) : s
end
_res_isnan(v::CarrierValue) = isnan(v)
_res_isnan(::BigExactF) = false      # exact-arithmetic escalations are finite by construction
_res_isnan(::EncloseF) = false
_res_isnan(::Enclose128F) = false

# ---- enclosure of (value of res)/S for finite nonzero exact S.
#
# Both arguments range over the carriers now, not just `Float64`. The scale is
# `decode(sr)`, so a rung-2 block already hands this a `Float128` and a rung-3
# block a `Dyadic`; the `S::Float64` signatures these carried through Stage 6
# were a `MethodError` waiting for the first wide block, not a narrowing (§11 M44).
#
# The divisor enters as an EXACT `BigFloat` formed at its own width — never by
# letting `BigFloat(res) / S` promote `S` at the ambient precision, which rounds
# the divisor and encloses the wrong quotient. That is §11 M35's `_ladderprec`
# defect in a second place, so it is written the same way here: `_sigbits` names
# the width, and the working precision is floored above it.
@inline _exactbig(S::CarrierValue) = setprecision(() -> BigFloat(S), BigFloat, _sigbits(S) + 1)
@inline _divprec(prec::Int, S::CarrierValue, extra::Int=0) = max(prec, _sigbits(S) + extra + 8)

function _encl_div_scale(res::CarrierValue, S::CarrierValue)
    EncloseF(prec -> begin
        p = _divprec(prec, S, _sigbits(res))
        setprecision(BigFloat, p) do
            b = BigFloat(res); s = _exactbig(S)               # both exact ⇒ one rounded op
            (setrounding(() -> b / s, BigFloat, RoundDown),
             setrounding(() -> b / s, BigFloat, RoundUp))
        end
    end)
end
function _encl_div_scale(res::BigExactF, S::CarrierValue)
    EncloseF(prec -> begin
        v = res.f()
        p = _divprec(prec, S, Base.precision(v))              # exact conversion ⇒ one rounded op
        setprecision(BigFloat, p) do
            s = _exactbig(S)
            (setrounding(() -> BigFloat(v) / s, BigFloat, RoundDown),
             setrounding(() -> BigFloat(v) / s, BigFloat, RoundUp))
        end
    end)
end
function _encl_div_scale(res::EncloseF, S::CarrierValue)
    EncloseF(prec -> begin
        p = _divprec(prec, S)
        d, u = res.f(p)
        setprecision(BigFloat, p) do
            s = _exactbig(S)
            if s > 0
                (setrounding(() -> d / s, BigFloat, RoundDown),
                 setrounding(() -> u / s, BigFloat, RoundUp))
            else
                (setrounding(() -> u / s, BigFloat, RoundDown),
                 setrounding(() -> d / s, BigFloat, RoundUp))
            end
        end
    end)
end
_encl_div_scale(res::Enclose128F, S::CarrierValue) = _encl_div_scale(EncloseF(res.f), S)

"""One element of ωBlockProject: the draft's S-special rows, then ωDivide + ωProject.

Fast-path cascade after the special rows, ordered cheapest-first by result kind:
exact Float64 quotient → CR Float128 quotient (exact or one-ulp bracket) →
CR-divided Enclose128F bracket → fq-composition envelope (2^-89) — each resolved
by the two-sided sticky gate; any miss falls through to the rigorous MPFR
interval at the bottom."""
function _bp_element(fr::Type{<:Binary}, ρ::ProjSpec, R::Int, res, Sdat::Float64)
    (isnan(Sdat) || _res_isnan(res)) && return rawvalue(fr, nan_code(fr))
    iszero(Sdat) && return project(fr, ρ, 0.0; R)
    if isinf(Sdat)
        return project(fr, ρ, _res_sign(res) * sign(Sdat); R)     # sgn(Xᵢ)·sgn(S) ∈ {−1,0,1}
    end
    if res isa Float64
        isinf(res) && return project(fr, ρ, sign(Sdat) * res; R)  # ωDivide(±∞, finite)
        iszero(res) && return project(fr, ρ, 0.0; R)
        q = res / Sdat
        (isfinite(q) && fma(q, Sdat, -res) == 0.0) && return project(fr, ρ, q; R)
        if _f128()                                                 # plan Site E, Class R:
            qr, qs = Float128(res), Float128(Sdat)                 # CR Float128 division
            q128 = qr / qs
            fma(q128, qs, -qr) == 0 && return project(fr, ρ, q128; R)
            return _finish(fr, ρ, R,
                           Enclose128F(prevfloat(q128), nextfloat(q128),
                                       _encl_div_scale(res, Sdat).f))
        end
    elseif res isa Float128 && _f128()
        q = res / Float128(Sdat)                              # CR division of an exact value
        fma(q, Float128(Sdat), -res) == 0 && return project(fr, ρ, q; R)
        return _finish(fr, ρ, R,
                       Enclose128F(prevfloat(q), nextfloat(q), _encl_div_scale(res, Sdat).f))
    elseif res isa Enclose128F && _f128()
        l128, h128 = Float128(Sdat) > 0 ? (res.lo, res.hi) : (res.hi, res.lo)
        lo = prevfloat(l128 / Float128(Sdat))                 # CR half-ulp each ⇒ one outward step
        hi = nextfloat(h128 / Float128(Sdat))
        cd = project(fr, ρ, lo; R, sticky=+1)
        cu = project(fr, ρ, hi; R, sticky=-1)
        codepoint(cd) == codepoint(cu) && return cd
    elseif res isa EncloseF && res.fq !== nothing && _f128()
        # Class E composition: op envelope 2^-90 + CR division half-ulp ⇒ 2^-89 covers
        y = res.fq()::Float128
        if isfinite(y) && !iszero(y)
            q = y / Float128(Sdat)
            E = ldexp(abs(q), _F128_RELEXP + 1)
            cd = project(fr, ρ, q - E; R, sticky=+1)
            cu = project(fr, ρ, q + E; R, sticky=-1)
            codepoint(cd) == codepoint(cu) && return cd
        end
    end
    project_interval(fr, ρ, _encl_div_scale(res, Sdat).f; R)
end

# The same element pipeline for a scale that is NOT a `Float64` — i.e. any block
# whose scale format sits at rung 2 or 3, which is 72 of the 504 formats.
#
# The draft's S-special rows are carrier-generic and are repeated here verbatim;
# what is not repeated is the fast-path cascade, and that is the whole content of
# this method. Every rung of that cascade divides in `Float64` or `Float128` and
# certifies the quotient with an `fma` at the same width. For a rung-2 or rung-3
# scale the divisor does not fit either — `Float128(Binary16p1uf(1.0))` is `Inf`
# before a single operation — so there is nothing to certify and no cheaper
# answer than the rigorous one. It goes straight to the bottom of the same
# cascade, which is where the narrow path lands whenever its filters miss.
#
# Written as dispatch rather than as an `if` at the top of the narrow method
# (invariant 9): the carrier is a function of the scale's format, so the choice
# belongs to method selection, and the hot rung-1 path keeps a body with no test
# for a condition that is constant within it.
function _bp_element(fr::Type{<:Binary}, ρ::ProjSpec, R::Int, res,
                     Sdat::Union{Float128,BigFloat,Dyadic})
    (isnan(Sdat) || _res_isnan(res)) && return rawvalue(fr, nan_code(fr))
    iszero(Sdat) && return project(fr, ρ, 0.0; R)
    isinf(Sdat) && return project(fr, ρ, _res_sign(res) * Float64(sign(Sdat)); R)
    project_interval(fr, ρ, _encl_div_scale(res, Sdat).f; R)
end

"""ωBlockProject (draft §5.1.2) over a tuple of result kinds, scale supplied as a value."""
function blockproject(fr::Type{<:Binary}, ρ::ProjSpec, sr::Binary, Z::NTuple{B,Any};
                      rng::MaybeRNG=nothing) where {B}
    Sdat = decode(sr)
    rr = _rng_for(ρ, rng)
    elems = ntuple(i -> _bp_element(fr, ρ, _drawR(ρ, rr, nothing), Z[i], Sdat), Val(B))
    Block(sr, elems)
end

# ---- generated elementwise BlockOp / ScaledOp surface (draft §5.4 / §5.5)
# One shape per surface, generated at every arity — the §5.4 elementwise schema is
# implemented once (blockproject) and the Block*/Scaled* wrappers around it are
# now written once too, so no arity can drift from the others.
for op in OP_REGISTRY
    op.name === :Convert && continue
    name = op.name; bname = Symbol(:Block, name); sname = Symbol(:Scaled, name); V = Val{name}

    bs = [Symbol(:b, i) for i in 1:op.arity]                 # operand blocks
    Xs = [Symbol(:X, i) for i in 1:op.arity]                 # their decoded lanes
    block_params = [:($b::Block{B}) for b in bs]
    decode_lanes = [:($(Xs[i]) = blockdecode($(bs[i]))) for i in 1:op.arity]
    lane_i = [:($(Xs[i])[i]) for i in 1:op.arity]

    ss = [Symbol(:s, i) for i in 1:op.arity]                 # (scale, element) pairs
    xs = [Symbol(:x, i) for i in 1:op.arity]
    scaled_params = collect(Iterators.flatten((:($(ss[i])::Binary), :($(xs[i])::Binary))
                                              for i in 1:op.arity))
    Xa = [Symbol(:Xa, i) for i in 1:op.arity]
    # Each (scale, element) pair is a two-factor monomial and gets its OWN head
    # from the two formats — `rung(Val(:Multiply), …)`, the same rule
    # `blockdecode` applies to a block. The old form asserted `::Float64` on the
    # product, which is `blockdecode`'s Stage 6 defect in its second location:
    # true for the 432 rung-1 formats and an outright `TypeError` for the other
    # 72 (§11 M44).
    #
    # The assertion is KEPT, at the right type: `carriertype(h)`. `Multiply` is
    # closed on the carrier at every rung — G4 asserts exactly that — so the row
    # cannot escalate to a lazy `BigExactF` here, and saying so is what lets the
    # `_joinheads` below see carrier values only. JET found the missing statement
    # before any test could: `_headof` has no row for a deferred thunk, and the
    # unasserted form left one inferable.
    scale_products = [:($(Xa[i]) = let h = rung(Val(:Multiply), typeof($(ss[i])), typeof($(xs[i])))
                            ωeval(h, Val(:Multiply),
                                  lift(h, decode($(ss[i]))),
                                  lift(h, decode($(xs[i]))))::carriertype(h)
                        end) for i in 1:op.arity]

    @eval begin
        function $bname(fr::Type{<:Binary}, ρ::ProjSpec, $(block_params...), sr::Binary;
                        rng::MaybeRNG=nothing) where {B}
            $(decode_lanes...)
            # Operand blocks may decode at DIFFERENT heads — one rung-1 block and
            # one rung-3 block is a legal call — so the operation runs at their
            # join, with each lane lifted into it. This is `apply_op`'s slow-path
            # shape, and for the rung-1 case it is the identity: `_joinheads` of
            # `Float64` lanes is `HeadF64` and `lift` is a no-op.
            Z = ntuple(Val(B)) do i
                h = _joinheads($(lane_i...))
                ωeval(h, $V(), $((:(lift(h, $l)) for l in lane_i)...))
            end
            blockproject(fr, ρ, sr, Z; rng)
        end
        function $sname(fr::Type{<:Binary}, ρ::ProjSpec, $(scaled_params...);
                        rng::MaybeRNG=nothing)
            $(scale_products...)
            h = _joinheads($(Xa...))
            res = ωeval(h, $V(), $((:(lift(h, $a)) for a in Xa)...))
            _bp_element(fr, ρ, _drawR(ρ, rng, nothing), res, 1.0)
        end
    end
end

# ---- reductions (draft §5.3): specials by the fold algebra, then an exact sum/product
#
# The exact accumulator's precision is DERIVED from the block's two formats and
# its length, never a constant. It replaced `_REDPREC = 2400`, the sibling of
# `_BIGP = 2200`: ample through B ≈ 512 and silently truncating above it, with
# the same failure mode gate G2 records — a plausible wrong number (§11 M31).
#
# Two different quantities, because two different exactness analyses:
#
#   sums     — the lanes span `2(B_S + B_E)` binades and each carries
#              `P_S + P_E` significand bits, plus `⌈log₂ B⌉` for the carries.
#   products — the exponent only shifts (MPFR's range covers any B here), but
#              the significand is the SUM over lanes: `B · (P_S + P_E)`.
#
# The product form is what `16B + 128` always was: `16 = 8 + 8` is `P_S + P_E`
# with `P = 8` hardcoded, so at K ≤ 8 the two agree exactly and above it the
# constant understated by up to 2×. That is why it is written out in terms of
# the formats now — the coefficient was a K ≤ 8 premise wearing a magic number.
@inline _lane_sum_prec(::Type{FS}, ::Type{FE}, B::Int) where {FS<:Binary,FE<:Binary} =
    2 * (expbias(FS) + expbias(FE) + precision(FS) + precision(FE)) + 64 + _log2ceil(B)
@inline _lane_prod_prec(::Type{FS}, ::Type{FE}, B::Int) where {FS<:Binary,FE<:Binary} =
    B * (precision(FS) + precision(FE)) + 128

# Span filter (plan Site E, Class R): decoded lanes carry ≤17-bit significands; a
# B-term sum is exactly representable in Float128 when
#   17 + (exponent span) + ⌈log₂B⌉ + 1 ≤ 113.
# One integer pass decides; the BigFloat accumulator remains for the wide tail.
@inline function _expspan(X)
    lo = typemax(Int); hi = typemin(Int)
    for v in X
        iszero(v) && continue
        e = exponent(v)
        lo = min(lo, e); hi = max(hi, e)
    end
    lo > hi ? 0 : hi - lo
end
@inline _log2ceil(B::Int) = 8 * sizeof(Int) - leading_zeros(B - 1 > 0 ? B - 1 : 1)

# Whether a `Float128` accumulator is a legal narrowing for lanes decoded at this
# head. At rungs 1 and 2 it is the carrier or wider, so the filters below decide
# only whether the sum *fits*; at rung 3 it is strictly narrower than the lanes
# themselves and no width filter can rescue it — a `Binary16p1uf` scale reaches
# 2^32768, which is `Inf` in `Float128` before any accumulation begins.
#
# The width filters are about the SIGNIFICAND (span plus lane bits plus carries);
# the rung is about the EXPONENT. Both must hold, and only one of them was
# checked. Selecting the accumulator by head makes the second condition part of
# the dispatch rather than a premise nobody stated (§11 M44).
@inline _f128acc(::HeadF64)   = _f128()
@inline _f128acc(::HeadF128)  = _f128()
@inline _f128acc(::HeadExact) = false

function _reduce_add_datum(h, X, prec::Int)
    any(isnan, X) && return NaN
    hasp = any(_isposinf, X); hasn = any(_isneginf, X)
    (hasp & hasn) && return NaN
    hasp && return Inf
    hasn && return -Inf
    all(iszero, X) && return 0.0
    B = length(X)
    if _f128acc(h) && _expspan(X) + _log2ceil(B) <= 92
        acc = Float128(0)
        for v in X
            acc += Float128(v)                               # every partial exact by width
        end
        return acc
    end
    BigExactF(() -> setprecision(() -> sum(BigFloat, X; init=BigFloat(0)), BigFloat, prec))
end

"""BlockReduceAdd (draft §5.3.1): project(reduce(ωAdd, [0, X…]))."""
function BlockReduceAdd(fr::Type{<:Binary}, ρ::ProjSpec, b::Block{B,FS,FE};
                        rng::MaybeRNG=nothing, R::MaybeR=nothing) where {B,FS,FE}
    _finish(fr, ρ, _drawR(ρ, rng, R),
            _reduce_add_datum(rung(Val(:Multiply), FS, FE), blockdecode(b),
                              _lane_sum_prec(FS, FE, B)))
end

"""BlockReduceMultiply (draft §5.3.1): project(reduce(ωMultiply, [1, X…]))."""
function BlockReduceMultiply(fr::Type{<:Binary}, ρ::ProjSpec, b::Block{B,FS,FE};
                             rng::MaybeRNG=nothing, R::MaybeR=nothing) where {B,FS,FE}
    X = blockdecode(b)
    lanebits = precision(FS) + precision(FE)                    # significand bits per lane
    res = if any(isnan, X) || (any(iszero, X) && any(isinf, X))
        NaN                                                     # 0·∞ arises in the fold → NaN
    elseif any(isinf, X)
        s = prod(sign, X)
        s > 0 ? Inf : -Inf
    elseif any(iszero, X)
        0.0
    # `B` is `Block{B}` — the BLOCKSIZE, not the exponent bias. A product's
    # significand width is the SUM of its factors' widths and its exponent only
    # shifts, so neither bound is bias-dependent. What IS K-dependent is the
    # per-lane width: the previous `16B` read `16 = 8 + 8`, i.e. `P_S + P_E` with
    # `P = 8` baked in, so it agreed exactly at K ≤ 8 and understated by up to 2×
    # above it. Written from the formats now (§11 M30, corrected).
    elseif _f128acc(rung(Val(:Multiply), FS, FE)) && lanebits * B + 8 <= 112  # exact by width AND in range
        acc = Float128(1)
        for v in X
            acc *= Float128(v)
        end
        acc
    else
        BigExactF(() -> setprecision(() -> prod(BigFloat, X; init=BigFloat(1)),
                                     BigFloat, _lane_prod_prec(FS, FE, B)))
    end
    _finish(fr, ρ, _drawR(ρ, rng, R), res)
end

# The Float128 accumulation lives in its OWN FUNCTION, and that is load-bearing.
#
# Inline in `BlockDotProduct`'s `if`/`else`, the accumulator sits inside an
# expression whose branches yield `Float64` (the NaN/∞ rows), `Float128`, and
# `BigExactF` — a union. `acc` could then not stay unboxed across the loop, and
# each iteration allocated: **32 bytes per lane, 2080 B for a 32-lane block**.
# The identical loop measured in isolation allocates ZERO, which is what pins the
# cause on the surrounding union rather than on `Float128` (a bitstype) or on
# `blockdecode` (which returns a concrete `NTuple{B,Float64}`).
#
# It is the same defect the table builders had, found the same day: a hot loop
# sharing a function body with something abstractly typed. CLAUDE.md's rule —
# "one function barrier restores full speed" — applies to a union-typed result
# just as it does to a format read from a global.
#
# `Val(B)` rather than a plain `B::Int`: the lane count becomes a type parameter,
# so the loop trip count is static and the tuple indexing needs no bounds logic.
@inline function _f128_dot(X::NTuple{B,Any}, Y::NTuple{B,Any}, ::Val{B}) where {B}
    acc = Float128(0)
    @inbounds for i in 1:B
        acc += Float128(X[i]) * Float128(Y[i])                  # exact products, exact sum
    end
    acc
end

"""BlockDotProduct (draft §5.3.2). Lane products can carry 64 significant bits, so the
products and their sum are formed in the exact accumulator, with the ∞/NaN fold algebra
resolved on the Float64 classifications first."""
function BlockDotProduct(fr::Type{<:Binary}, ρ::ProjSpec,
                         bx::Block{B,FS1,FE1}, by::Block{B,FS2,FE2};
                         rng::MaybeRNG=nothing, R::MaybeR=nothing) where {B,FS1,FE1,FS2,FE2}
    X = blockdecode(bx); Y = blockdecode(by)
    # Each term is a product of FOUR datums (two scales, two elements), so both
    # the span and the significand width double relative to the sum reduction.
    # `_lane_sum_prec` over the union of the four formats bounds the span; the
    # `+64` slack covers the widths, since 4·max Pᵢ ≤ 64 for every P ≤ 16.
    dotprec = _lane_sum_prec(FS1, FE1, B) + _lane_sum_prec(FS2, FE2, B)
    pcls = ntuple(Val(B)) do i
        x, y = X[i], Y[i]
        (isnan(x) | isnan(y)) && return NaN
        ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return NaN
        (isinf(x) || isinf(y)) && return (sign(x) * sign(y) > 0 ? Inf : -Inf)
        1.0                                                     # finite lane marker
    end
    res = if any(isnan, pcls)
        NaN
    elseif any(isinf, pcls)
        hasp = any(==(Inf), pcls); hasn = any(==(-Inf), pcls)
        (hasp & hasn) ? NaN : (hasp ? Inf : -Inf)
    else
        # product-span filter (plan Site E): lane products carry ≤33-bit significands;
        # the sum is exact in Float128 when 33 + span + ⌈log₂B⌉ + 2 ≤ 113
        spanlo = typemax(Int); spanhi = typemin(Int)
        for i in 1:B
            (iszero(X[i]) || iszero(Y[i])) && continue
            e = exponent(X[i]) + exponent(Y[i])
            spanlo = min(spanlo, e); spanhi = max(spanhi, e)
        end
        span = spanlo > spanhi ? 0 : (spanhi - spanlo) + 1
        hdot = joinhead(rung(Val(:Multiply), FS1, FE1), rung(Val(:Multiply), FS2, FE2))
        if _f128acc(hdot) && span + _log2ceil(B) <= 76
            _f128_dot(X, Y, Val(B))                             # barrier — see below
        else
            BigExactF(() -> setprecision(BigFloat, dotprec) do
                acc = BigFloat(0)
                for i in 1:B
                    acc += BigFloat(X[i]) * BigFloat(Y[i])      # exact products, exact sum
                end
                acc
            end)
        end
    end
    _finish(fr, ρ, _drawR(ρ, rng, R), res)
end

# ---- conversion family (draft §5.2)
"""ConvertFromBlock (§5.2.1): blockdecode, then project each element (no scale division)."""
function ConvertFromBlock(fr::Type{<:Binary}, ρ::ProjSpec, b::Block{B};
                          rng::MaybeRNG=nothing) where {B}
    X = blockdecode(b)
    ntuple(i -> project(fr, ρ, X[i]; R=_drawR(ρ, rng, nothing)), Val(B))
end

"""ConvertToBlock (§5.2.2): decode elements, BlockProject against the supplied scale."""
function ConvertToBlock(fs::Type{<:Binary}, fr::Type{<:Binary}, ρ::ProjSpec,
                        xs::NTuple{B,<:Binary}, s::Binary;
                        rng::MaybeRNG=nothing) where {B}
    s isa fs || throw(ArgumentError("scale operand must be in format $fs"))
    blockproject(fr, ρ, s, map(decode, xs); rng)
end

"""ConvertToBlockMaxAbsFinite (§5.2.3): S = reduce(ωMaximumFinite, [NaN, |X₁|…]),
project S under ρs, then BlockProject the elements under ρ."""
function ConvertToBlockMaxAbsFinite(fs::Type{<:Binary}, fr::Type{<:Binary},
                                    ρs::ProjSpec, ρ::ProjSpec, xs::NTuple{B,<:Binary};
                                    rng::MaybeRNG=nothing) where {B}
    X = map(decode, xs)
    # The reduction runs at the join of the elements' own heads, and its seed is
    # that head's NaN rather than a `Float64` literal. The `::Float64` asserts
    # this carried were the same defect as `blockdecode`'s and the `Scaled*`
    # surface's, in a third place (§11 M44); the seed was the same defect in the
    # data. `MaximumFinite`'s whole contract is that a NaN seed loses to any
    # finite operand, which requires the seed to BE a NaN at the head it is
    # compared at, not merely at rung 1.
    h = _joinheads(X...)
    C = carriertype(h)
    M = map(x -> ωeval(h, Val(:Abs), lift(h, x))::C, X)
    S = foldl((a, m) -> ωeval(h, Val(:MaximumFinite), a, m)::C, M; init=_cnan(C))
    s = project(fs, ρs, S; R=_drawR(ρs, rng, nothing))
    blockproject(fr, ρ, s, X; rng)
end

# ---- SoA array-of-blocks container (design §6.3): scales and elements in planes
"""
    BlockVector{B,FS,FE} <: AbstractVector{Block{B,FS,FE}}

Structure-of-arrays storage: `scales::Vector{FS}`, `elems::Matrix{FE}` (B × n,
column-major so each block's elements are one contiguous column).
"""
struct BlockVector{B,FS<:Binary,FE<:Binary} <: AbstractVector{Block{B,FS,FE}}
    scales::Vector{FS}
    elems::Matrix{FE}
    function BlockVector{B}(scales::Vector{FS}, elems::Matrix{FE}) where {B,FS<:Binary,FE<:Binary}
        size(elems, 1) == B || throw(DimensionMismatch("elems must be $(B)×n"))
        size(elems, 2) == length(scales) || throw(DimensionMismatch("one scale per block"))
        new{B,FS,FE}(scales, elems)
    end
end
BlockVector(blocks::AbstractVector{Block{B,FS,FE}}) where {B,FS,FE} =
    BlockVector{B}([b.s for b in blocks],
                   FE[blocks[j].x[i] for i in 1:B, j in eachindex(blocks)])
Base.size(bv::BlockVector) = (length(bv.scales),)
Base.@propagate_inbounds function Base.getindex(bv::BlockVector{B,FS,FE}, j::Int) where {B,FS,FE}
    Block(bv.scales[j], ntuple(i -> bv.elems[i, j], Val(B)))
end
Base.@propagate_inbounds function Base.setindex!(bv::BlockVector{B}, b::Block{B}, j::Int) where {B}
    bv.scales[j] = b.s
    for i in 1:B
        bv.elems[i, j] = b.x[i]
    end
    bv
end
