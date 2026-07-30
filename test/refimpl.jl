# Independent reference implementation of ωRoundToPrecision/ωSaturate/ωEncode using
# Rational{BigInt} arithmetic — shares no code with the engine under test.
#
# ---- why this file is the oracle wide K makes non-optional (Stage 8 step 2).
#
# Every other oracle in the repository is a *wider float*: MPFR at a derived
# precision, `Float128` behind a width filter, the retired `BigFloat` carrier
# behind G7. Each is valid only while its carrier is wide enough for the case at
# hand, and "wide enough" is exactly the thing the extension put in question —
# gate G2 exists because `_BIGP = 2200` was insufficient for 50 of the 504
# formats and said so by returning a plausible wrong number.
#
# `Rational{BigInt}` has no precision to be insufficient. A P3109 datum IS a
# dyadic rational, so every value here is represented exactly by construction and
# every comparison is a decision, not an estimate. That makes this the only
# reference whose validity does not have to be re-argued per format, and it is
# why promoting it out of manual-only status is a Stage 8 requirement rather than
# a nicety.
#
# It is also, necessarily, slow: rounding one value costs a `BigInt` division and
# `refproject`'s encode step is a search over the datum set. The tier that uses
# it (`test/tier_t2.jl`) is sized accordingly — small parameter grids, exhaustive
# within them — rather than by sampling a large one.
using SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: nan_code, posinf_code, neginf_code, rawvalue, codepoint,
                   codeunit_type, bitwidth

const RQ = Rational{BigInt}

function ilog2rat(x::RQ)
    @assert x > 0
    e = ndigits(numerator(x); base=2) - ndigits(denominator(x); base=2)
    p = big(2)^abs(e); v = e >= 0 ? RQ(p) : RQ(1, p)
    while v > x
        e -= 1; v //= 2
    end
    while 2v <= x
        e += 1; v *= 2
    end
    e
end
pow2r(q::Integer) = q >= 0 ? RQ(big(2)^q) : RQ(1, big(2)^(-q))

# margin: for approximate inputs assert ν is far from every decision constant
function refround(P::Int, B::Int, mode, R::Int, X::RQ; approx::Bool=false)
    X == 0 && return (0, big(0), 0)
    sgn = X > 0 ? 1 : -1
    a = abs(X)
    e = ilog2rat(a)
    Q = max(e, 1 - B) - P + 1
    S̃ = a / pow2r(Q)
    fl = floor(BigInt, S̃)
    ν = S̃ - fl
    if approx
        for c in (RQ(0), RQ(1, 2), RQ(1))
            @assert ν == c || abs(ν - c) > RQ(1, big(2)^2500) "ν too close to a decision boundary"
        end
    end
    codeiseven = P > 1 ? iseven(fl) : (fl == 0 || iseven(Q + B))
    away = if mode isa TowardZero
        false
    elseif mode isa TowardPositive
        ν > 0 && sgn > 0
    elseif mode isa TowardNegative
        ν > 0 && sgn < 0
    elseif mode isa NearestTiesToAway
        ν >= RQ(1, 2)
    elseif mode isa NearestTiesToEven
        ν > RQ(1, 2) || (ν == RQ(1, 2) && !codeiseven)
    elseif mode isa ToOdd
        ν > 0 && codeiseven
    elseif mode isa StochasticA
        N = SmallFloats.nrandbits(mode)
        floor(BigInt, ν * big(2)^N) + R >= big(2)^N
    elseif mode isa StochasticB
        N = SmallFloats.nrandbits(mode)
        floor(BigInt, ν * big(2)^(N + 1)) + (2R + 1) >= big(2)^(N + 1)
    elseif mode isa StochasticC
        N = SmallFloats.nrandbits(mode)
        t = ν * big(2)^N; ft = floor(BigInt, t); fr = t - ft
        rnite = (fr < RQ(1, 2) || (fr == RQ(1, 2) && iseven(ft))) ? ft : ft + 1
        rnite + R >= big(2)^N
    else
        error("mode $mode")
    end
    S = fl + (away ? 1 : 0)
    # Rounding away can CARRY out of the significand: `S̃ < 2^P` always, but
    # `⌊S̃⌋ + 1` reaches `2^P` exactly when `S̃` was in the top ulp of the binade.
    # The canonical `Rounded` form keeps `S < 2^P` — the significand is P bits —
    # so the carry moves into the exponent. Same datum either way, which is
    # precisely why this went unnoticed until T2a: `refround`'s only consumer
    # before Stage 8 was G2, which compares `sgn·S·2^Q` as a VALUE, and
    # `2^P · 2^Q == 2^(P-1) · 2^(Q+1)`. Comparing the triple is the stronger
    # check, and it is the one that found the reference out of normal form.
    if S == big(1) << P
        S >>= 1; Q += 1
    end
    (sgn, S, Q)
end

# A datum as an exact rational, at every carrier. `decode` now returns Float64,
# Float128 or BigFloat depending on the format's rung, and Base's
# `Rational{BigInt}(::Float128)` routes through `precision(::Float128)`, which
# Quadmath does not define — so the Float128 case goes via BigFloat, which is
# exact (the ambient precision is ≥ 256 ≫ 113). Every conversion here is exact;
# none of them rounds.
exact_rq(x::Real) = RQ(x)
exact_rq(x::Float128) = RQ(BigFloat(x))
datum_rq(v) = exact_rq(decode(v))

# ---- the datum set of a format, as exact rationals, memoized.
#
# `refproject` finishes by finding which code point carries a given value, and it
# does so by SEARCHING the datum set rather than by calling `encode` — that
# independence is the whole point of the file. Through Stage 7 the search was an
# inline `for c in 0x00:UInt8((1 << K) - 1)` loop, which pinned this reference to
# K ≤ 8 twice over: the `UInt8` is wrong for a `Code16` format, and an O(2^K)
# rebuild of every datum per projected value is 65 536 `Rational{BigInt}`
# constructions per call at K = 16.
#
# Building the map once per format fixes both. It stays a search over the datum
# set — the map is built from `decode` and nothing else, so no `encode` logic
# leaks in — but the cost moves from per-call to per-format, which is what makes
# the reference affordable in the shipped suite.
#
# The cache is a plain `Dict` keyed by the format type. Test-local, single
# threaded, and deliberately not the package's own table machinery: an oracle
# that shared the cache under test would not be an independent one.
const _DATUM_CODE = Dict{DataType,Dict{RQ,UInt}}()

function datum_codes(::Type{T}) where {T<:Binary}
    get!(_DATUM_CODE, T) do
        U = codeunit_type(T); K = bitwidth(T); nanc = nan_code(T)
        m = Dict{RQ,UInt}()
        for c in 0:(1 << K - 1)
            u = U(c)
            u == nanc && continue
            v = rawvalue(T, u)
            isfinite(v) || continue
            # The draft's single zero and the P3109 encodings are one-to-one on
            # the finite datums, so a repeated key would be a defect in `decode`
            # rather than an expected collision — assert it instead of letting
            # the later insert win silently.
            q = datum_rq(v)
            @assert !haskey(m, q) "duplicate finite datum $q in $(T) at codes $(m[q]) and $u"
            m[q] = UInt(u)
        end
        m
    end
end

# A datum on ANY carrier, normalized to the two things `refproject` reasons
# about: an exact rational for the finite values, and a `Float64` NaN or ±Inf for
# the specials. `Rational{BigInt}` cannot represent a special, so the union is not
# a convenience — it is the reason the reference has no precision to be
# insufficient in the first place.
#
# This is what lets the T2 tier hand `refproject` a `Float128` or a `Dyadic`
# straight from `decode` without each call site restating the conversion, and
# without any of those conversions rounding: `exact_rq` is exact at every carrier.
carrier_arg(x::Float64) = x
function carrier_arg(x::Real)
    isnan(x) && return NaN
    isinf(x) && return x > 0 ? Inf : -Inf
    exact_rq(x)
end

refproject(::Type{T}, ρ::ProjSpec, X::Real; R::Int=0, approx::Bool=false) where {T<:Binary} =
    refproject(T, ρ, carrier_arg(X); R, approx)

# ---- ωRoundToPrecision then ωSaturate, stopping at the VALUE.
#
# Split out of `refproject` at Stage 8 so the T2b saturation sweep can run over
# all 504 formats without materializing a datum map for each. Comparing values
# rather than code points is not a weaker check here, it is a different one and
# a cleaner split: `encode` is covered exhaustively at every K by the T1 lattice
# round-trip, so folding it into the saturation comparison would test it a second
# time and, worse, would let an `encode` defect present as a saturation failure.
#
# Returns an exact rational for a finite result, or one of `:pinf`/`:ninf`/`:nan`
# — the three things a rational cannot represent, which is exactly why the return
# is a union and not a number.
function refsaturate(::Type{T}, ρ::ProjSpec, X::Union{RQ,Float64};
                     R::Int=0, approx::Bool=false) where {T<:Binary}
    mode = SmallFloats.roundingmode(ρ); sat = SmallFloats.saturationmode(ρ)
    P = precision(T); B = SmallFloats.expbias(T)
    SGN = SmallFloats.issigned(T); EXT = SmallFloats.isextended(T)
    X isa Float64 && isnan(X) && return :nan
    if X isa Float64 && isinf(X)
        Z = X
    else
        Xr = X isa Float64 ? RQ(X) : X
        sgn, S, Q = refround(P, B, mode, R, Xr; approx)
        Z = S == 0 ? RQ(0) : sgn * RQ(S) * pow2r(Q)
        Z = Z::RQ
    end
    mhi = datum_rq(MaxFiniteOf(T)); mlo = datum_rq(MinFiniteOf(T))
    # ωSaturate rows, in draft order
    if Z isa RQ && mlo <= Z <= mhi
        Z
    elseif sat isa SatFinite
        Z isa Float64 ? (Z > 0 ? mhi : mlo) : (Z < mlo ? mlo : mhi)
    elseif sat isa SatPropagate
        if Z isa Float64            # ±Inf
            Z > 0 ? (EXT ? :pinf : mhi) : ((SGN && EXT) ? :ninf : mlo)
        else
            Z < mlo ? mlo : mhi
        end
    else # SatNone
        if Z isa RQ && Z > mhi && (mode isa TowardZero || mode isa TowardNegative)
            mhi
        elseif Z isa RQ && Z < mlo && (mode isa TowardZero || mode isa TowardPositive)
            mlo
        elseif EXT && ((Z isa Float64 && Z > 0) || (Z isa RQ && Z > mhi))
            :pinf
        elseif EXT && ((Z isa Float64 && Z < 0) || (Z isa RQ && Z < mlo))
            SGN ? :ninf : :nan
        else
            :nan
        end
    end
end

# The value a code point carries, in the same union `refsaturate` returns, so the
# two are directly comparable without either side converting.
function code_value(v::Binary)
    d = decode(v)
    isnan(d) && return :nan
    # `signbit`, not `d > 0`: at rung 3 `d` is a `Dyadic`, which has no promotion
    # to `Int` by design — the same defect §11 M44 records in `Class`, reproduced
    # here in the reference three days later. The engine-side lesson generalizes
    # to the oracle: a comparison against a literal is a conversion in disguise.
    isinf(d) && return signbit(d) ? :ninf : :pinf
    exact_rq(d)
end

function refproject(::Type{T}, ρ::ProjSpec, X::Union{RQ,Float64}; R::Int=0, approx::Bool=false) where {T<:Binary}
    out = refsaturate(T, ρ, X; R, approx)
    out === :pinf && return posinf_code(T)
    out === :ninf && return neginf_code(T)
    out === :nan && return nan_code(T)
    # encode by lookup in the datum set (independent of ωEncode) — see
    # `datum_codes` above for why this is a memoized map rather than a scan.
    c = get(datum_codes(T), out, nothing)
    c === nothing && error("refproject: value $out not in datum set of $(T)")
    codeunit_type(T)(c)
end

# reference ω semantics for Add/Multiply/Divide on datums (exact rational)
function refop2(name::Symbol, x, y)::Union{RQ,Float64}   # Float64 = special (NaN/±Inf)
    dx, dy = decode(x), decode(y)
    (isnan(dx) || isnan(dy)) && return NaN
    if name === :Add
        if isinf(dx) || isinf(dy)
            (isinf(dx) && isinf(dy) && sign(dx) != sign(dy)) && return NaN
            return isinf(dx) ? dx : dy
        end
        return RQ(dx) + RQ(dy)
    elseif name === :Multiply
        if isinf(dx) || isinf(dy)
            (dx == 0 || dy == 0) && return NaN
            return sign(dx) * sign(dy) > 0 ? Inf : -Inf
        end
        return RQ(dx) * RQ(dy)
    elseif name === :Divide
        dy == 0 && return NaN
        if isinf(dx)
            isinf(dy) && return NaN
            return sign(dx) * sign(dy) > 0 ? Inf : -Inf
        end
        isinf(dy) && return 0.0
        dx == 0 && return 0.0
        return RQ(dx) / RQ(dy)
    end
    error("refop2 $name")
end
