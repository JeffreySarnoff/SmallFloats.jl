# ===== oracle.jl — the ω-semantics catalog (design §9.2, architecture §5,
#                   Float128 revision plan Sites B/C/D)
#
# Rigorous evaluation of every operation's defined result. Never on the hot path.
#
# Result protocol (consumed by ops_scalar.jl's _finish):
#   Float64      exact result: draft-tabled specials and exactly representable finites
#   Float128     exact result by width analysis (Class R: sums of decoded datums whose
#                required significand width fits 113 bits — see the _DE_* thresholds)
#   BigExactF    f() → BigFloat, exact at `bigprec`/`bigprec_prod` of the
#                operands (the wide-spread tail); see carriers.jl and gate G2
#   Enclose128F  correctly-rounded Float128 bracket (Class R: IEEE-CR sqrt/rsqrt;
#                Divide/Recip now resolve via EncloseF's yd — see below) with the
#                MPFR closure as grid-straddle fallback
#   EncloseF     f(prec) → MPFR directed (lo, hi); optional fq Float128 pre-filter
#                (Class E: |truth − fq()| ≤ |fq()|·2^-90, ≥2^18 slack over published
#                libquadmath bounds, discharged by the differential-build tests);
#                optional yd eager Float64 estimate (faithful libm or IEEE-CR
#                quotient: |truth − yd| ≤ |yd|·2^-45) tried before fq
#
# Special-value rows are written out explicitly even where the substrate coincides:
# the rows are the spec, not an optimization. Interpretations beyond the readable
# draft text are marked [interp] and tracked in checkpoint.md.

# Exact-arithmetic precision comes from `bigprec`/`bigprec_prod` (carriers.jl),
# derived per call from the operands. It replaced `_BIGP = 2200`, which was
# sufficient for Float64 operands by 49 bits and silently truncated the moment a
# datum from a B > 1024 format reached these closures — 50 of the 504 formats.
# Gate G2 recorded the red (§11 M31) before this landed.

# ---- error-free transforms (Class-1 arithmetic, design §5.1)
@inline function _twosum(a::Float64, b::Float64)
    s = a + b
    bb = s - a
    (s, (a - (s - bb)) + (b - bb))
end

# ---- Float128 exactness-by-width thresholds (plan Site B, Class R; §1 C1/C2).
#
# A sum is exactly representable in Float128 (113 bits) when the operands'
# significand bits plus the exponent spread plus a carry fit. These were the
# constants `(100, 92, 98)`, correct for the ≤8-bit datums of a K ≤ 8 format and
# **wrong the moment a P = 16 datum appears** — and wrong in the one direction no
# other test can see: a widened threshold accepts an *inexact* Float128 sum as
# exact. Nothing downstream re-checks it.
#
# The widths come from the DATUMS, not from a format parameter, because `ωeval`
# receives values. That also keeps K ≤ 8 bit-identical for a reason rather than
# by adjustment: a datum of a P-bit format carries at most P significant bits, so
# `_sigwidth ≤ 8` reproduces `(100, 92, 98)` exactly — the fixed point gate G1(i)
# asserts. Nothing is consulted until the Float64 residual is already nonzero, so
# this is off the common path.
#
# C1's correction is in `_de_fma`: the accounting is `P₁ + P₂ + 2` (product plus
# carry), which the source comment always stated ("18 + ΔE ≤ 113") while the
# inherited generalization wrote `P₁ + P₂ + 1`.
@inline function _sigwidth(x::Float64)
    (isfinite(x) & !iszero(x)) || return 1
    u = reinterpret(UInt64, x)
    m = u & 0x000f_ffff_ffff_ffff
    if (u & 0x7ff0_0000_0000_0000) == 0                  # subnormal: no implicit bit
        return (64 - leading_zeros(m)) - trailing_zeros(m)
    end
    m == 0 ? 1 : 53 - trailing_zeros(m)
end
@inline _de_add(x::Float64, y::Float64) =
    113 - (max(_sigwidth(x), _sigwidth(y)) + 1) - 4
# `z` is unused and the signature keeps it anyway: the FMA bound is set by the
# exact product's width, and spelling the addend at the definition makes the
# asymmetry with `_de_add`/`_de_faa` visible where it is decided rather than
# inferable only from the call site.
@inline _de_fma(x::Float64, y::Float64, ::Float64) =
    113 - (_sigwidth(x) + _sigwidth(y) + 2) - 3
@inline _de_faa(x::Float64, y::Float64, z::Float64) =
    113 - (max(_sigwidth(x), _sigwidth(y), _sigwidth(z)) + 3) - 4

# C2 — the sticky-head shortcut has a SECOND premise, independent of width.
#
# `StickyF` neglects a tail, and soundness needs that tail below both (a) the
# head's distance to any off-grid rounding threshold and (b) the finest
# stochastic sub-grid unit, `2^(e_head − (P−1) − N)`. Only (a) is a width bound;
# (b) requires `ΔE > (P − 1) + N + 2`. At P ≤ 8 the width bound is stricter, so
# the collision is invisible today — and at P = 16 with N > 15 it inverts:
# `_de_fma = 76 < 77`.
#
# Neither `P` (the RESULT format's) nor `N` (the rounding mode's) is visible to
# `ωeval`, and threading ρ down to it would be worse than the maximum: both are
# bounded by the grid, so `(16 − 1) + 60 + 2` covers every cell. The band between
# the two bounds falls to the exact MPFR path and is empty for every P ≤ 15,
# which is what makes this a generalization with a fixed point rather than a
# behaviour change. Gate G1 asserts band contiguity — that no ΔE is uncovered.
const _STICKY_MIN = 77     # (P_max − 1) + N_max + 2 = 15 + 60 + 2

@inline _expdiff(a::Float64, b::Float64) = abs(exponent(a) - exponent(b))
@inline function _span3(x::Float64, y::Float64, z::Float64)
    lo = typemax(Int); hi = typemin(Int)
    for v in (x, y, z)
        iszero(v) && continue
        e = exponent(v)
        lo = min(lo, e); hi = max(hi, e)
    end
    hi - lo
end

# Float128 twin of _twosum (IEEE-CR Float128 add/sub, so the Knuth transform is exact)
@inline function _twosum128(a::Float128, b::Float128)
    s = a + b
    bb = s - a
    (s, (a - (s - bb)) + (b - bb))
end

# ---- wide-spread sticky escalations (non-allocating replacements for the
# BigFloat tail; see StickyF's soundness note in ops_scalar.jl).
#
# FMA, ΔE(p, z) past BOTH bands (`_de_fma` for width, `_STICKY_MIN` for the
# stochastic sub-grid — see C2 above): the exact product p and the addend z
# are bit-disjoint by > 75 binades, so the larger term is the head and the smaller
# contributes only its sign. Threshold-grid bound (head h, tail w): h is a multiple
# of 2^(e_h−16) while |w| < |h|·2^-92, far below both the finest stochastic
# sub-grid unit (≥ 2^(e_h−7−61)) and h's distance to any off-grid threshold
# (≥ 2^(e_h−16)).
@inline function _fma_wide(p::Float64, z::Float64)
    abs(p) >= abs(z) ? StickyF(p, signbit(z) ? -1 : 1) :
                       StickyF(z, signbit(p) ? -1 : 1)
end

# FAA, span past BOTH bands (`_de_faa` and `_STICKY_MIN`; cancellation among
# x, y, z is possible here, which is why the span rather than a pairwise ΔE
# governs): distill the three
# exact Float128 terms into (v1, v2, v3) with v1+v2+v3 invariant (each 2sum pass is
# an exact transform) until v1 = fl128(Σ) up to its own lsb and the residual
# v2 + v3 has a determinable sign strictly below lsb(v1) = 2^(e₁−112):
#   · 2sum guarantees |v2| ≤ ulp(v1)/2 = 2^(e₁−113);
#   · accepting requires |v3| < |v2| (sign = sign(v2), |v2+v3| < 2^(e₁−112))
#     or v3 = 0 (sign = sign(v2)) or v2 = 0 with |v3| < 2^(e₁−112) (sign = sign(v3)).
# Priest-style distillation on 3 sorted terms converges in ≤ 3 sweeps; 6 is margin,
# with the (unreachable in testing) MPFR fallback preserving semantics regardless.
function _faa_wide(x::Float64, y::Float64, z::Float64)
    v1, v2, v3 = Float128(x), Float128(y), Float128(z)
    for _ in 1:6
        # sort descending by magnitude (convergence, not exactness, needs this)
        if abs(v2) < abs(v3); v2, v3 = v3, v2; end
        if abs(v1) < abs(v2); v1, v2 = v2, v1; end
        if abs(v2) < abs(v3); v2, v3 = v3, v2; end
        t, tt = _twosum128(v2, v3)
        s, e  = _twosum128(v1, t)
        v1, v2, v3 = s, e, tt
        if iszero(v2) && iszero(v3)
            return v1                                        # exact (covers Σ = 0)
        end
        iszero(v1) && continue                               # total hiding in v2+v3; resort
        if iszero(v3)
            return StickyF(v1, signbit(v2) ? -1 : 1)
        elseif iszero(v2)
            abs(v3) < ldexp(one(Float128), Base.exponent(v1) - 112) &&
                return StickyF(v1, signbit(v3) ? -1 : 1)
        elseif abs(v3) < abs(v2)
            return StickyF(v1, signbit(v2) ? -1 : 1)
        end
    end
    _bigsum3(x, y, z)
end

# Signatures are `AbstractFloat`, not `Float64`: rung 2 escalates into these too.
# Conversion into BigFloat is exact from either carrier (`bigprec` is ≥ 113 by its
# own `+64` term), so the escalation is one exact conversion plus one exact
# operation at a derived precision, exactly as at rung 1.
_bigsum2(x::AbstractFloat, y::AbstractFloat) =
    BigExactF(() -> setprecision(() -> BigFloat(x) + BigFloat(y), BigFloat, bigprec(x, y)))
_bigfma(x::AbstractFloat, y::AbstractFloat, z::AbstractFloat) =
    BigExactF(() -> setprecision(() -> BigFloat(x) * BigFloat(y) + BigFloat(z),
                                 BigFloat, bigprec_prod(x, y, z)))
_bigsum3(x::AbstractFloat, y::AbstractFloat, z::AbstractFloat) =
    BigExactF(() -> setprecision(() -> (BigFloat(x) + BigFloat(y)) + BigFloat(z),
                                 BigFloat, bigprec(x, y, z)))

# ---- MPFR directed-enclosure closures (the rigorous ladder).
#
# `_ladderprec` is the floor the ladder must start at: converting the operand
# into BigFloat has to be EXACT, or the bracket encloses the wrong value. For
# Float64/Float128 any working precision does; for a BigFloat operand the ambient
# precision must not be below the operand's own, which the ladder's own schedule
# does not guarantee at its first rungs. Same shape as `_encl_div_scale`'s guard
# in blocks.jl.
@inline _ladderprec(prec::Int, xs::AbstractFloat...) = max(prec, _sigfloor(xs...) + 8)
@inline _sigfloor(x::AbstractFloat) = _sigbits(x)
@inline _sigfloor(x::AbstractFloat, ys::AbstractFloat...) = max(_sigbits(x), _sigfloor(ys...))

_mpfr1(f::F, x::AbstractFloat) where {F} = prec -> setprecision(BigFloat, _ladderprec(prec, x)) do
    (setrounding(() -> f(BigFloat(x)), BigFloat, RoundDown),
     setrounding(() -> f(BigFloat(x)), BigFloat, RoundUp))
end
_mpfr2(f::F, x::AbstractFloat, y::AbstractFloat) where {F} =
    prec -> setprecision(BigFloat, _ladderprec(prec, x, y)) do
        (setrounding(() -> f(BigFloat(x), BigFloat(y)), BigFloat, RoundDown),
         setrounding(() -> f(BigFloat(x), BigFloat(y)), BigFloat, RoundUp))
    end
# enclosure builders: MPFR ladder (f) + optional Float128 pre-filter (fq) +
# optional eager Float64 estimate (yd); see EncloseF's docstring for the
# three-stage resolution each of these feeds
_encl1(f::F, x::AbstractFloat; fq=nothing, yd=NaN) where {F} = EncloseF(_mpfr1(f, x), fq, yd)
_encl2(f::F, x::AbstractFloat, y::AbstractFloat; fq=nothing, yd=NaN) where {F} =
    EncloseF(_mpfr2(f, x, y), fq, yd)

# The ordinary single-argument case: all three stages come from the *same* Base
# function — MPFR ladder, Float128 pre-filter, eager Float64 estimate. Rows that
# deviate (ArcCos's synthesized `_acos128`, the trig argument window, the
# ladder-only fallbacks) keep calling `_encl1` directly, so a deviation from the
# standard shape is visible at the call site instead of hidden in boilerplate.
#
# **Both filters are Float64-only, by dispatch.** `yd` is a `Float64` field, and
# `fq` narrows to `Float128` — for a rung-3 operand either conversion can lose
# the value outright (a B = 32 768 datum has no Float128, let alone Float64,
# representation). The wide method drops both and hands the ladder the whole job.
# That is slower and it is the recorded property of those tiers, not a defect:
# the plan's benchmark doctrine already says `HeadExact`'s MPFR transcendental
# fallback allocating is a property of the tier rather than a suite failure.
_encl1_libm(f::F, x::Float64) where {F} = _encl1(f, x; fq=() -> f(Float128(x)), yd=f(x))
_encl1_libm(f::F, x::AbstractFloat) where {F} = _encl1(f, x)

# Whether an `fma`-based exactness PROOF is valid on this carrier.
#
# The quotient rows accept a candidate `q` when `fma(q, y, -x) == 0`. That is a
# proof only where `fma` is exact — IEEE requires it for Float64 and Float128, so
# both qualify. MPFR's `fma` rounds to the ambient precision, where `q*y` needs
# twice the operand width, so the same test yields **false positives**: an
# inexact quotient declared exact, projected, and returned. Nothing downstream
# re-checks it, which puts it in the same class as a widened `_DE_*` threshold.
#
# So the shortcut is guarded rather than widened, and rung 3 goes straight to the
# rigorous ladder — which was always the correct answer, merely the slower one.
@inline _fma_is_exact(::Float64)  = true
@inline _fma_is_exact(::Float128) = true
@inline _fma_is_exact(::BigFloat) = false

# Rows that build their own filters (the quotient family, whose eager estimate is
# an IEEE-CR quotient rather than a libm call) go through these instead of
# `_encl1`/`_encl2` directly. `EncloseF.yd` is a **`Float64` field** and `fq`
# narrows to `Float128`, so both are structurally Float64-tier: on any wider
# carrier they are dropped and the ladder decides alone. Passing them anyway and
# discarding here keeps the decision in one place rather than repeated at four
# call sites with four chances to differ.
#
# The Float64 methods require `yd::Float64` as well as a Float64 operand. That is
# not belt-and-braces: `EncloseF.yd` IS a `Float64` field, so "there is an eager
# estimate" and "the estimate is a Float64" are the same condition, and saying so
# in the signature means the wide method catches every case the narrow one cannot
# construct. JET found this by analysing the widened rows abstractly, where a
# Float64 operand and a Float128 estimate can appear together in a combination no
# concrete call produces — and the right answer to that report was a more honest
# precondition, not a filter.
@inline _encl1f(f::F, x::Float64, fq, yd::Float64) where {F} = _encl1(f, x; fq, yd)
@inline _encl1f(f::F, x::AbstractFloat, _fq, _yd) where {F} = _encl1(f, x)
@inline _encl2f(f::F, x::Float64, y::Float64, fq, yd::Float64) where {F} = _encl2(f, x, y; fq, yd)
@inline _encl2f(f::F, x::AbstractFloat, y::AbstractFloat, _fq, _yd) where {F} =
    _encl2(f, x, y)

# RSqrt composes two CR operations for its eager estimate, so it builds `EncloseF`
# directly rather than through `_encl1`; the same Float64-tier rule applies.
@inline _encl1f_rsqrt(x::Float64, s::Float64) =
    EncloseF(_mpfr_rsqrt(x), () -> inv(sqrt(Float128(x))), 1.0 / s)
@inline _encl1f_rsqrt(x::AbstractFloat, _s) = EncloseF(_mpfr_rsqrt(x))

# The general form, for rows that build their own MPFR closure (`Softplus`'s
# monotone composition, `_encl_divpi`'s divide-by-π). Same Float64-tier rule.
@inline _enclf(ladder::F, ::Float64, fq, yd::Float64) where {F} = EncloseF(ladder, fq, yd)
@inline _enclf(ladder::F, ::AbstractFloat, _fq, _yd) where {F} = EncloseF(ladder)

# Quadmath omits acos(::Float128); π/2 − asin is exact well within the 2^-90 envelope
# (asin faithful + π half-ulp + one subtraction: ≲ 2^-108 relative).
@inline _acos128(x::Float128) = ldexp(Float128(π), -1) - asin(x)

# π · num / 2^k with exact power-of-two scaling; sign-aware directed bounds.
function _encl_piscale(num::Int, k::Int)
    fq = () -> ldexp(Float128(π) * num, -k)
    # eager Float64 estimate: π half-ulp + one multiply + exact ldexp ≤ ~1.5 ulp
    yd = ldexp(Float64(π) * num, -k)
    EncloseF(prec -> setprecision(BigFloat, prec) do
        lo = setrounding(BigFloat, RoundDown) do
            p = num > 0 ? BigFloat(π) : setrounding(() -> BigFloat(π), BigFloat, RoundUp)
            ldexp(p * num, -k)
        end
        hi = setrounding(BigFloat, RoundUp) do
            p = num > 0 ? BigFloat(π) : setrounding(() -> BigFloat(π), BigFloat, RoundDown)
            ldexp(p * num, -k)
        end
        (lo, hi)
    end, fq, yd)
end

# g(x…)/π for the arc-Pi variants: MPFR ladder with sign-aware denominator bounds;
# gq is the Float128 counterpart of g for the pre-filter (envelope covers the
# composed faithful-op + π-constant + CR-division errors with ≥2^16 slack).
function _encl_divpi(g::F, gq::G, xs::AbstractFloat...) where {F,G}
    fq = () -> gq(map(Float128, xs)...) / Float128(π)
    # eager Float64 estimate: faithful g + π half-ulp + CR division ≤ ~2 ulp; the
    # division by π ≈ 3.14 is well-conditioned, so no amplification anywhere
    yd = g(xs...) / Float64(π)
    _enclf(prec -> setprecision(BigFloat, _ladderprec(prec, xs...)) do
        lo = setrounding(BigFloat, RoundDown) do
            n = g(map(BigFloat, xs)...)
            p = n >= 0 ? setrounding(() -> BigFloat(π), BigFloat, RoundUp) : BigFloat(π)
            n / p
        end
        hi = setrounding(BigFloat, RoundUp) do
            n = g(map(BigFloat, xs)...)
            p = n >= 0 ? setrounding(() -> BigFloat(π), BigFloat, RoundDown) : BigFloat(π)
            n / p
        end
        (lo, hi)
    end, first(xs), fq, yd)
end

# f(π·r) for the *Pi trig family on the exactly reduced r ∈ (0,2) with the
# extremum/pole/Niven points already peeled: the tiny m-interval contains no interior
# extremum (an ≤8-bit-significand r is never within 2^-9 of one), so the 4-combo
# min/max of directed endpoint evaluations encloses. Pre-filter: one Float128 eval
# (π-constant half-ulp + CR product half-ulp + trig envelope ≪ 2^-90).
# The eager Float64 estimate is supplied by the CALLER as the Base.*pi native
# (sinpi/cospi/tanpi): those are relative-faithful in the *result* domain even
# adjacent to zeros/poles. Evaluating f(Float64(π)·r) instead would amplify the
# π-rounding argument error by |πr|/|f| near the zeros of sin — measured at only
# ~2× envelope slack for the closest format-reachable r — so it is NOT used.
function _encl_pitrig(f::F, r::AbstractFloat, yd) where {F}
    fq = () -> f(Float128(π) * Float128(r))
    _enclf(prec -> setprecision(BigFloat, _ladderprec(prec, r)) do
        ml = setrounding(() -> BigFloat(π) * BigFloat(r), BigFloat, RoundDown)
        mh = setrounding(() -> BigFloat(π) * BigFloat(r), BigFloat, RoundUp)
        a = setrounding(() -> (f(ml), f(mh)), BigFloat, RoundDown)
        b = setrounding(() -> (f(ml), f(mh)), BigFloat, RoundUp)
        (min(a[1], a[2]), max(b[1], b[2]))
    end, r, fq, yd)
end

# exact mod-2 reduction for the *Pi family.
# Exact on every carrier: `rem` by a power of two is exact, so the π-scaled
# argument reduction loses nothing at any rung. `oftype` rather than a `2.0`
# literal keeps the result on the operand's carrier instead of silently widening
# the comparison to Float64.
@inline function _mod2(x::AbstractFloat)
    two = oftype(x, 2)
    r = rem(x, two)
    r < zero(x) ? r + two : r
end

# ============================================================================
# Carrier rung selection (§2 R-B, §4 Stage 3 item 5)
# ============================================================================
# `apply_op` reaches ω-semantics through the rung of the format being produced.
# Rung 1 forwards to the Float64 catalogue below — the only one that exists
# today — and the other two rungs are DELIBERATELY MISSING BODIES rather than a
# check inside `rung`.
#
# That placement is the point. `rung` is a trait: a total function of the format
# parameters, defined for all 504 formats, and a trait that throws over a third
# of its domain is not a trait — it is a branch wearing a trait's name
# (invariant 9). An incomplete implementation is precisely a set of unimplemented
# METHODS, and the method table is the one place that already reports exactly
# that. So `rung(F)` answers `HeadF128()` for a B = 4096 format at Stage 3 just
# as it will at Stage 6; what is absent is the evaluator for that answer.
#
# Gating on the RESULT format alone is complete at this stage, and only at this
# stage: operands arrive already decoded, `decode` refuses every K ≥ 9 format
# until Stage 4, and every K ≤ 8 format has B ≤ 128, hence rung 1. Stage 6
# replaces this with the `rung(op, Fs...)` join over result and argument formats,
# which is what makes mixed-format evaluation well-defined.
@inline ωeval(::HeadF64, op::Val, xs::Float64...) = ωeval(op, xs...)
# The mixed-carrier hole, closed by method rather than left to a MethodError.
# `apply_op` selects the head from the RESULT format, so a narrow result with
# wide operands selects HeadF64 and arrives here on a carrier it has no row for.
# The `rung(op, Fs...)` join is what makes that case well-defined; until it
# lands, this is the third route to a refusal (§11 M28's class) and it has to
# name the operation like the other two.
@noinline ωeval(::HeadF64, ::Val{OP}, xs...) where {OP} = throw(ArgumentError(
    "$OP selected the rung-1 (Float64) carrier from its result format but " *
    "received operands on $(join(unique(map(x -> string(typeof(x)), xs)), ", ")). " *
    "Mixed-carrier evaluation needs the rung(op, Fs...) join, which arrives in " *
    "Stage 6 of the K ≤ 16 extension"))
@noinline ωeval(::HeadF128, ::Val{OP}, xs...) where {OP} = throw(ArgumentError(
    "$OP on this format needs the rung-2 (Float128) carrier, which arrives in " *
    "Stage 6 of the K ≤ 16 extension"))

# ---- rung 2: the Float128 carrier (Group A).
#
# Structurally identical to the Float64 catalog one rung down, and deliberately
# so: an error-free transform decides exactness, and a nonzero residual escalates
# to the same MPFR closures (whose signatures are `AbstractFloat` for exactly this
# reason). What differs is only which transform and which threshold.
#
# The width argument that makes `Multiply` exact here: a rung-2 format has
# B ≤ 8192, so a datum's exponent is at most B − 1 and the product's at most
# 16 382 — inside Float128's 16 383 by one binade, which is the ΣB ≤ emax rule
# doing its job. The significands are ≤ 16 bits each, so 32 ≤ 113 covers the
# product exactly. The `isfinite` guard is defence on a cold path, not a
# correctness dependency.
@inline ωeval(h::HeadF128, op::Val, x::Float128, xs::Float128...) =
    _ωf128(h, op, x, xs...)

@noinline _ωf128(::HeadF128, ::Val{OP}, xs...) where {OP} = throw(ArgumentError(
    "$OP has no rung-2 (Float128) ω-semantics yet: Group A is implemented on " *
    "the Float128 carrier, Groups B and C arrive with the enclosure ladder " *
    "later in Stage 6 of the K ≤ 16 extension"))

function _ωf128(::HeadF128, ::Val{:Add}, x::Float128, y::Float128)
    (isnan(x) | isnan(y)) && return _cnan(Float128)
    if isinf(x) || isinf(y)
        (isinf(x) && isinf(y) && x != y) && return _cnan(Float128)      # ∞ + (−∞) → NaN
        return isinf(x) ? x : y
    end
    s, e = _twosum128(x, y)
    iszero(e) && return iszero(s) ? zero(Float128) : s      # exact in Float128
    _bigsum2(x, y)
end
_ωf128(h::HeadF128, ::Val{:Subtract}, x::Float128, y::Float128) =
    _ωf128(h, Val(:Add), x, isnan(y) ? y : (iszero(y) ? zero(y) : -y))
function _ωf128(::HeadF128, ::Val{:Multiply}, x::Float128, y::Float128)
    (isnan(x) | isnan(y)) && return _cnan(Float128)
    ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return _cnan(Float128)   # 0·∞ → NaN
    p = x * y
    isfinite(p) && return iszero(p) ? zero(Float128) : p
    isinf(x) || isinf(y) ? p : _bigmul2(x, y)              # true ∞ vs Float128 overflow
end
function _ωf128(::HeadF128, ::Val{:FMA}, x::Float128, y::Float128, z::Float128)
    (isnan(x) | isnan(y) | isnan(z)) && return _cnan(Float128)
    ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return _cnan(Float128)
    p = x * y
    if isinf(p) || isinf(z)
        (isinf(p) && isinf(z) && p != z) && return _cnan(Float128)
        return isinf(p) ? p : z
    end
    s, e = _twosum128(p, z)
    (iszero(e) && fma(x, y, -p) == 0) && return iszero(s) ? zero(Float128) : s
    _bigfma(x, y, z)                                        # p may itself be inexact
end
function _ωf128(::HeadF128, ::Val{:FAA}, x::Float128, y::Float128, z::Float128)
    (isnan(x) | isnan(y) | isnan(z)) && return _cnan(Float128)
    if isinf(x) || isinf(y) || isinf(z)
        hasp = (x == Inf) | (y == Inf) | (z == Inf)
        hasn = (x == -Inf) | (y == -Inf) | (z == -Inf)
        (hasp & hasn) && return _cnan(Float128)
        return hasp ? _cinf(Float128) : _cninf(Float128)
    end
    s1, e1 = _twosum128(x, y)
    s2, e2 = _twosum128(s1, z)
    (iszero(e1) && iszero(e2)) && return iszero(s2) ? zero(Float128) : s2
    _bigsum3(x, y, z)
end
_ωf128(::HeadF128, ::Val{:Convert}, x::Float128) = x

_bigmul2(x::AbstractFloat, y::AbstractFloat) =
    BigExactF(() -> setprecision(() -> BigFloat(x) * BigFloat(y),
                                 BigFloat, bigprec_prod(x, y)))
@noinline ωeval(::HeadExact, ::Val{OP}, xs...) where {OP} = throw(ArgumentError(
    "$OP on this format needs the rung-3 (exact) carrier, which arrives in " *
    "Stage 6/7 of the K ≤ 16 extension"))

# ---- rung 3: the exact carrier (Group A; Group C follows later in this stage).
#
# Specials are returned as Float64 rows, the same convention the Float64 catalog
# uses: `_finish` dispatches on the result's type and `project` has the special
# rows on Float64 already. The finite tail is one MPFR operation at a precision
# that must exceed the operand spread — which is the whole subject of gate G2.
# Both wide rows spell out a first operand. With bare `Vararg`s they are
# ambiguous at N = 0 — `ωeval(HeadExact(), op)` matches both — which
# `detect_ambiguities` catches. Requiring one operand also states the obvious:
# there is no ω-semantics to evaluate on no arguments.
@inline ωeval(h::HeadExact, op::Val, x::BigFloat, xs::BigFloat...) =
    _ωexact(h, op, x, xs...)

# Group A is implemented; Group B/C on the exact carrier is item 9 of this stage
# (the enclosure ladder retargeted at BigFloat). The row above accepts EVERY
# operation, so without this the unimplemented ones would surface as a
# `MethodError` naming `_ωexact` — an internal function, and a static-analysis
# defect rather than a decision. M17's rule, which I broke and JET caught:
# **refuse by method, and let the method throw.**
@noinline _ωexact(::HeadExact, ::Val{OP}, xs...) where {OP} = throw(ArgumentError(
    "$OP has no rung-3 (exact) ω-semantics yet: Group A is implemented on the " *
    "exact carrier, Groups B and C arrive with the enclosure ladder later in " *
    "Stage 6 of the K ≤ 16 extension"))

function _ωexact(::HeadExact, ::Val{:Add}, x::BigFloat, y::BigFloat)
    (isnan(x) | isnan(y)) && return _cnan(BigFloat)
    if isinf(x) || isinf(y)
        (isinf(x) && isinf(y) && x != y) && return _cnan(BigFloat)
        return (isinf(x) ? (sign(x) > 0 ? _cinf(BigFloat) : _cninf(BigFloat)) : (sign(y) > 0 ? _cinf(BigFloat) : _cninf(BigFloat)))
    end
    setprecision(() -> x + y, BigFloat, bigprec(x, y))
end
_ωexact(h::HeadExact, ::Val{:Subtract}, x::BigFloat, y::BigFloat) =
    _ωexact(h, Val(:Add), x, isnan(y) ? y : (iszero(y) ? zero(y) : -y))
function _ωexact(::HeadExact, ::Val{:Multiply}, x::BigFloat, y::BigFloat)
    (isnan(x) | isnan(y)) && return _cnan(BigFloat)
    ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return _cnan(BigFloat)
    (isinf(x) || isinf(y)) && return sign(x) * sign(y) > 0 ? _cinf(BigFloat) : _cninf(BigFloat)
    setprecision(() -> x * y, BigFloat, bigprec_prod(x, y))
end
function _ωexact(::HeadExact, ::Val{:FMA}, x::BigFloat, y::BigFloat, z::BigFloat)
    (isnan(x) | isnan(y) | isnan(z)) && return _cnan(BigFloat)
    ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return _cnan(BigFloat)
    if isinf(x) || isinf(y) || isinf(z)
        ps = Float64(sign(x)) * Float64(sign(y))
        (isinf(x) || isinf(y)) && isinf(z) && (ps * Inf != Float64(sign(z)) * Inf) && return _cnan(BigFloat)
        return (isinf(x) || isinf(y)) ? ps * Inf : Float64(sign(z)) * Inf
    end
    setprecision(() -> x * y + z, BigFloat, bigprec_prod(x, y, z))
end
function _ωexact(::HeadExact, ::Val{:FAA}, x::BigFloat, y::BigFloat, z::BigFloat)
    (isnan(x) | isnan(y) | isnan(z)) && return _cnan(BigFloat)
    if isinf(x) || isinf(y) || isinf(z)
        hasp = (x == Inf) | (y == Inf) | (z == Inf)
        hasn = (x == -Inf) | (y == -Inf) | (z == -Inf)
        (hasp & hasn) && return _cnan(BigFloat)
        return hasp ? _cinf(BigFloat) : _cninf(BigFloat)
    end
    setprecision(() -> (x + y) + z, BigFloat, bigprec(x, y, z))
end
_ωexact(::HeadExact, ::Val{:Convert}, x::BigFloat) = x

# ---- rung 3 on the Dyadic carrier (§4 Stage 7).
#
# Exact arithmetic is native: `Dyadic` closes under add and multiply, so these
# rows are the operations themselves rather than an escalation. The add uses the
# STICKY form, which is what makes the C7 bands load-bearing rather than
# decorative — past the alignment band the small operand contributes only a sign,
# and `StickyF` is the protocol that carries it to the projection.
@inline ωeval(h::HeadExact, op::Val, x::Dyadic, xs::Dyadic...) =
    _ωdyadic(h, op, x, xs...)

@inline function _ωdyadic(::HeadExact, ::Val{:Add}, x::Dyadic, y::Dyadic)
    v, sg = DyadicNumbers.add_sticky_dy(x, y)
    sg == 0 ? v : StickyF(v, sg)
end
@inline _ωdyadic(h::HeadExact, ::Val{:Subtract}, x::Dyadic, y::Dyadic) =
    _ωdyadic(h, Val(:Add), x, -y)
@inline _ωdyadic(::HeadExact, ::Val{:Multiply}, x::Dyadic, y::Dyadic) =
    DyadicNumbers.mul_dy(x, y)
@inline function _ωdyadic(h::HeadExact, ::Val{:FMA}, x::Dyadic, y::Dyadic, z::Dyadic)
    p = DyadicNumbers.mul_dy(x, y)
    _ωdyadic(h, Val(:Add), p, z)
end
# FAA is the one row where the sticky protocol does NOT compose.
#
# Written as two chained `Add`s, a sticky from the first add is dropped when the
# second one runs: the tail `ε·s₁` below `x + y` is real, and re-entering `Add`
# with only `v₁` discards it. Worse, two stickies can arrive from both adds and
# **cancel**, which no single sign can represent. `StickyF` carries one direction
# for one neglected tail; it is not an accumulator.
#
# So when either alignment falls outside the exact band, this drops to the exact
# MPFR sum rather than inventing a composition rule. That is slower on a path
# already at rung 3, and it is right. The pairwise `Add` and `FMA` rows above do
# compose, because each has exactly one add and therefore at most one tail.
@inline function _ωdyadic(::HeadExact, ::Val{:FAA}, x::Dyadic, y::Dyadic, z::Dyadic)
    (isnan(x) | isnan(y) | isnan(z)) && return _cnan(Dyadic)
    if isinf(x) || isinf(y) || isinf(z)
        hasp = (isinf(x) && sign(x) > 0) | (isinf(y) && sign(y) > 0) | (isinf(z) && sign(z) > 0)
        hasn = (isinf(x) && sign(x) < 0) | (isinf(y) && sign(y) < 0) | (isinf(z) && sign(z) < 0)
        (hasp & hasn) && return _cnan(Dyadic)
        return hasp ? _cinf(Dyadic) : _cninf(Dyadic)
    end
    v1, s1 = DyadicNumbers.add_sticky_dy(x, y)
    if s1 == 0
        v2, s2 = DyadicNumbers.add_sticky_dy(v1, z)
        s2 == 0 && return v2                    # both adds exact: the sum is exact
    end
    _bigsum3(BigFloat(x), BigFloat(y), BigFloat(z))
end
_ωdyadic(::HeadExact, ::Val{:Convert}, x::Dyadic) = x

@noinline _ωdyadic(::HeadExact, ::Val{OP}, xs...) where {OP} = throw(ArgumentError(
    "$OP has no rung-3 Dyadic ω-semantics: it is neither exact arithmetic, an " *
    "exact selection, nor an enclosure, so it is not in OP_REGISTRY"))

# ---- exact selections, at every rung, from ONE implementation.
#
# `Abs`, `Negate`, `CopySign`, the extremum family and `Clamp` have no width
# analysis and no escalation: their ω-semantics selects an operand or flips a
# sign, which is exact on any carrier. So the rows in the "exact selection"
# section below are written `::AbstractFloat` and every head delegates to them.
# Writing per-carrier copies would be three transcriptions of the draft's
# special-value tables that could drift from each other — the divergence
# invariant 7 exists to prevent, in the one part of the catalog where the rows
# ARE the spec.
#
# The list is explicit because it does not coincide with a registry group:
# `Abs`/`Negate`/`CopySign`/`Clamp` are group `:A` alongside the arithmetic, and
# group `:C` contains `Hypot`/`ArcTan2`/`ArcTan2Pi`, which are enclosures rather
# than selections. Being explicit is only safe if it is checked — `test/gates_g4.jl`
# asserts this set partitions `OP_REGISTRY` against the ops that have per-head
# rows, so an operation added to the registry cannot silently belong to neither.
const _EXACT_SELECTION = (:Abs, :Negate, :CopySign, :Clamp,
                          :Maximum, :Minimum, :MaximumNumber, :MinimumNumber,
                          :MaximumMagnitude, :MinimumMagnitude,
                          :MaximumMagnitudeNumber, :MinimumMagnitudeNumber,
                          :MinimumFinite, :MaximumFinite)
for nm in _EXACT_SELECTION
    @eval begin
        @inline _ωf128(::HeadF128, op::Val{$(QuoteNode(nm))}, xs::Float128...) =
            ωeval(op, xs...)
        @inline _ωexact(::HeadExact, op::Val{$(QuoteNode(nm))}, xs::BigFloat...) =
            ωeval(op, xs...)
    end
end

# ---- the enclosure ladder, at every rung.
#
# The rows for the quotient family and Group B are `::AbstractFloat` and the
# builders below them choose what each carrier can support: Float64 keeps the
# eager `yd` and the `fq` Float128 pre-filter, everything wider gets the rigorous
# MPFR ladder alone. That is not a reduced-quality path — the ladder is what
# decides in every case anyway; the filters only let it be skipped when they
# already agree on a code point.
#
# `_LADDER_OPS` is DERIVED, not listed: whatever is neither an exact selection,
# nor exact arithmetic, nor `Convert`, resolves through an enclosure. So adding
# an operation to `OP_REGISTRY` gives it wide-rung rows automatically, and
# mis-classifying one is caught by G4's partition assertion rather than by a
# `MethodError` at a call site far from the mistake (§11 M9's trap).
const _EXACT_ARITH = (:Add, :Subtract, :Multiply, :FMA, :FAA)
const _LADDER_OPS = Tuple(o.name for o in OP_REGISTRY
                          if !(o.name in _EXACT_SELECTION) &&
                             !(o.name in _EXACT_ARITH) && o.name !== :Convert)
for nm in _LADDER_OPS
    @eval begin
        @inline _ωf128(::HeadF128, op::Val{$(QuoteNode(nm))}, xs::Float128...) =
            ωeval(op, xs...)
        @inline _ωexact(::HeadExact, op::Val{$(QuoteNode(nm))}, xs::BigFloat...) =
            ωeval(op, xs...)
    end
end

# Exact selections need no Dyadic-specific code: the rows below are typed
# `::CarrierValue`, which names `Dyadic` explicitly. One implementation of the
# draft's special-value tables, four carriers.
for nm in _EXACT_SELECTION
    @eval @inline _ωdyadic(::HeadExact, op::Val{$(QuoteNode(nm))}, xs::Dyadic...) =
        ωeval(op, xs...)
end

# Everything else is an enclosure, and `Dyadic` has no transcendentals — nor
# should it. The ladder is MPFR's job; `Dyadic` converts exactly into it and the
# result is projected the same way. Exactness of that conversion is what makes
# this a routing decision rather than a precision one.
for nm in _LADDER_OPS
    @eval @inline _ωdyadic(::HeadExact, op::Val{$(QuoteNode(nm))}, xs::Dyadic...) =
        ωeval(op, map(BigFloat, xs)...)
end


# `Convert` is registry arity 1 but registry group `:conv`, and it is the one
# operation with no ω-semantics of its own: the conversion IS the projection into
# the target format, so on the datum it is the identity. Spelling that identity
# makes `ωeval` total over the registry.
#
# This is §11 M9's trap closed rather than routed around. Every consumer that
# filters the registry by arity alone — the golden harness did, and Stage 6's
# `factors` column will — walks into `Convert` and dies on a missing method
# somewhere far from the mistake. `tables.jl`'s `_scalar_code` keeps its explicit
# `:Convert` branch: that is not redundancy, it is the statement that a Convert
# table entry is a bare projection, and it must stay visible at the site where
# a table entry is defined to be the defined result (invariant 6).
ωeval(::Val{:Convert}, x::Float64) = x

# ============================================================================
# Group "exact selection": Abs, Negate, CopySign, extremum family, Clamp
# ============================================================================
# These rows are parametric in the carrier `C` and homogeneous in it, which is
# two statements, both load-bearing.
#
# *Parametric* because the special values they return must be the carrier's own.
# Written with bare `NaN` and `0.0` literals — as they were through Stage 6 —
# every one of these rows returns a `Float64` NaN from a `Dyadic` evaluation, so
# the declared return `carriertype(h)` is a lie and the method infers a `Union`.
# Nothing caught it: `project` accepts a `Float64` on every path, and a
# differential gate comparing two wide carriers sees the same wrong type on both
# sides. §11 M41 fixed the same defect in `_ωf128`/`_ωexact`'s special rows; this
# is where it had also been sitting, one dispatch layer below (§11 M44).
#
# *Homogeneous* because every caller lifts to a single head before evaluating, so
# a mixed-carrier call is a bug in the caller. Spelling the constraint makes that
# bug a `MethodError` at the mistake rather than a silent promotion far from it.
ωeval(::Val{:Abs}, x::C) where {C<:CarrierValue} = isnan(x) ? _cnan(C) : abs(x)
ωeval(::Val{:Negate}, x::C) where {C<:CarrierValue} =
    isnan(x) ? _cnan(C) : (iszero(x) ? _czero(C) : -x)
function ωeval(::Val{:CopySign}, x::C, y::C) where {C<:CarrierValue}
    (isnan(x) | isnan(y)) && return _cnan(C)                # D1 §4.9.2: NaN in either operand
    v = copysign(x, y)
    iszero(v) ? _czero(C) : v                               # single zero
end

ωeval(::Val{:Maximum}, x::C, y::C) where {C<:CarrierValue} =
    (isnan(x) | isnan(y)) ? _cnan(C) : max(x, y)
ωeval(::Val{:Minimum}, x::C, y::C) where {C<:CarrierValue} =
    (isnan(x) | isnan(y)) ? _cnan(C) : min(x, y)
ωeval(::Val{:MaximumNumber}, x::C, y::C) where {C<:CarrierValue} =
    isnan(x) ? (isnan(y) ? _cnan(C) : y) : (isnan(y) ? x : max(x, y))
ωeval(::Val{:MinimumNumber}, x::C, y::C) where {C<:CarrierValue} =
    isnan(x) ? (isnan(y) ? _cnan(C) : y) : (isnan(y) ? x : min(x, y))
function ωeval(::Val{:MaximumMagnitude}, x::C, y::C) where {C<:CarrierValue}
    (isnan(x) | isnan(y)) && return _cnan(C)
    abs(x) > abs(y) ? x : abs(y) > abs(x) ? y : max(x, y)
end
function ωeval(::Val{:MinimumMagnitude}, x::C, y::C) where {C<:CarrierValue}
    (isnan(x) | isnan(y)) && return _cnan(C)
    abs(x) < abs(y) ? x : abs(y) < abs(x) ? y : min(x, y)
end
function ωeval(::Val{:MaximumMagnitudeNumber}, x::C, y::C) where {C<:CarrierValue}
    isnan(x) && return isnan(y) ? _cnan(C) : y
    isnan(y) && return x
    abs(x) > abs(y) ? x : abs(y) > abs(x) ? y : max(x, y)
end
function ωeval(::Val{:MinimumMagnitudeNumber}, x::C, y::C) where {C<:CarrierValue}
    isnan(x) && return isnan(y) ? _cnan(C) : y
    isnan(y) && return x
    abs(x) < abs(y) ? x : abs(y) < abs(x) ? y : min(x, y)
end
# Finite variants (§4.11.3): prefer finite operands; then infinities beat NaN.
# These are the reduction semantics ConvertToBlockMaxAbsFinite's NaN seed relies on.
function ωeval(::Val{:MaximumFinite}, x::C, y::C) where {C<:CarrierValue}
    fx, fy = isfinite(x), isfinite(y)
    fx & fy && return max(x, y)
    fx && return x
    fy && return y
    isnan(x) && return isnan(y) ? _cnan(C) : y
    isnan(y) && return x
    max(x, y)
end
function ωeval(::Val{:MinimumFinite}, x::C, y::C) where {C<:CarrierValue}
    fx, fy = isfinite(x), isfinite(y)
    fx & fy && return min(x, y)
    fx && return x
    fy && return y
    isnan(x) && return isnan(y) ? _cnan(C) : y
    isnan(y) && return x
    min(x, y)
end
function ωeval(::Val{:Clamp}, x::C, lo::C, hi::C) where {C<:CarrierValue}
    (isnan(x) | isnan(lo) | isnan(hi)) && return _cnan(C)
    min(max(x, lo), hi)
end

# ============================================================================
# Group "exact arithmetic": Add, Subtract, Multiply, FMA, FAA
# ============================================================================
function ωeval(::Val{:Add}, x::Float64, y::Float64)
    (isnan(x) | isnan(y)) && return NaN
    if isinf(x) || isinf(y)
        (isinf(x) && isinf(y) && x != y) && return NaN      # ∞ + (−∞) → NaN
        return isinf(x) ? x : y
    end
    s, e = _twosum(x, y)
    e == 0.0 && return iszero(s) ? 0.0 : s
    (_f128() && _expdiff(x, y) <= _de_add(x, y)) && return Float128(x) + Float128(y)  # exact by width
    _bigsum2(x, y)
end
ωeval(::Val{:Subtract}, x::Float64, y::Float64) =
    ωeval(Val(:Add), x, isnan(y) ? y : (iszero(y) ? 0.0 : -y))
function ωeval(::Val{:Multiply}, x::Float64, y::Float64)
    (isnan(x) | isnan(y)) && return NaN
    ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return NaN   # 0·∞ → NaN
    p = x * y
    iszero(p) ? 0.0 : p                # exact: ≤16-bit significands, exponents in range
end
function ωeval(::Val{:FMA}, x::Float64, y::Float64, z::Float64)
    (isnan(x) | isnan(y) | isnan(z)) && return NaN
    ((iszero(x) && isinf(y)) || (isinf(x) && iszero(y))) && return NaN
    p = x * y                                                # exact when finite
    if isinf(p) || isinf(z)
        (isinf(p) && isinf(z) && p != z) && return NaN
        return isinf(p) ? p : z
    end
    s, e = _twosum(p, z)
    e == 0.0 && return iszero(s) ? 0.0 : s
    if _f128()                                               # e ≠ 0 ⇒ p, z both nonzero
        d = _expdiff(p, z)
        d <= _de_fma(x, y, z) && return Float128(p) + Float128(z)  # p exact ⇒ exact by width
        d > _STICKY_MIN && return _fma_wide(p, z)            # sticky head, no allocation
        # C2's middle band: too wide for Float128, too narrow for the sticky
        # argument's stochastic premise. Empty for every P ≤ 15.
    end
    _bigfma(x, y, z)
end
function ωeval(::Val{:FAA}, x::Float64, y::Float64, z::Float64)
    (isnan(x) | isnan(y) | isnan(z)) && return NaN
    if isinf(x) || isinf(y) || isinf(z)
        hasp = (x == Inf) | (y == Inf) | (z == Inf)
        hasn = (x == -Inf) | (y == -Inf) | (z == -Inf)
        (hasp & hasn) && return NaN
        return hasp ? Inf : -Inf
    end
    s1, e1 = _twosum(x, y)
    s2, e2 = _twosum(s1, z)
    (e1 == 0.0 && e2 == 0.0) && return iszero(s2) ? 0.0 : s2
    if _f128()
        sp = _span3(x, y, z)
        sp <= _de_faa(x, y, z) &&
            return (Float128(x) + Float128(y)) + Float128(z) # every partial exact by width
        sp > _STICKY_MIN && return _faa_wide(x, y, z)        # sticky head, no allocation
        # C2's middle band, as in FMA above. Empty for every P ≤ 15.
    end
    _bigsum3(x, y, z)
end

# ============================================================================
# Group "quotient": Divide, Recip, Sqrt, RSqrt   (Annex A.3 zero/∞ semantics)
# All four rest on IEEE correct rounding (Class R, plan Site C), split two ways:
#   Divide/Recip — the *Float64* quotient is CR (≤ half an ulp), so it serves as
#     EncloseF's eager yd estimate directly; no Float128 arithmetic on this path.
#   Sqrt/RSqrt   — Float128 sqrt/inv are CR, so an inexact nearest-CR result q
#     brackets the truth in (prevfloat(q), nextfloat(q)) → Enclose128F.
# ============================================================================
function ωeval(::Val{:Divide}, x::AbstractFloat, y::AbstractFloat)
    (isnan(x) | isnan(y)) && return NaN
    iszero(y) && return NaN                                  # x/0 → NaN, all x (A.3)
    (isinf(x) && isinf(y)) && return NaN
    isinf(y) && return 0.0                                   # x/±∞ → 0 (single zero)
    isinf(x) && return y > 0 ? x : -x
    q = x / y
    (_fma_is_exact(q) && isfinite(q) && fma(q, y, -x) == 0) &&
        return (iszero(q) ? zero(q) : q)                     # exact quotient (proof needs exact fma)
    # IEEE-CR Float64 quotient as eager estimate; degenerate q ⇒ yd = NaN ⇒ the
    # Float128 filter / ladder decide. Single call site keeps the union narrow;
    # the former 113-bit-exact branch is dead (a dyadic x/y is exact at ≤ p_x ≤ 53
    # bits whenever it is finite and representable).
    yd = (isfinite(q) && !iszero(q)) ? q : NaN
    _encl2f(/, x, y, () -> Float128(x) / Float128(y), yd)
end
function ωeval(::Val{:Recip}, x::AbstractFloat)
    isnan(x) && return NaN
    iszero(x) && return NaN                                  # Recip(0) → NaN (A.3)
    isinf(x) && return 0.0                                   # Recip(±∞) → 0 (A.3)
    q = 1.0 / x
    (_fma_is_exact(q) && isfinite(q) && fma(q, x, -one(x)) == 0) && return q  # exact ⇔ x a power of two
    # IEEE-CR Float64 quotient (≤ half an ulp) is the ideal eager estimate; a
    # degenerate q (over/underflow) sends yd = NaN so _finish skips straight to
    # the Float128 filter / MPFR ladder. Single call site keeps the return union
    # to {Float64, EncloseF} — the former Float128/Enclose128F branch is dead for
    # Float64 inputs (1/x exact at 113 bits ⇔ x a power of two ⇔ exact at 53).
    yd = (isfinite(q) && !iszero(q)) ? q : NaN
    _encl1f(inv, x, () -> inv(Float128(x)), yd)
end
function ωeval(::Val{:Sqrt}, x::AbstractFloat)
    isnan(x) && return NaN
    x < 0.0 && return NaN
    iszero(x) && return 0.0
    isinf(x) && return Inf
    s = sqrt(x)
    (_fma_is_exact(s) && fma(s, s, -x) == 0) && return s      # exact square root
    # IEEE-CR hardware sqrt (≤ half an ulp, unconditional) is the ideal eager
    # estimate; s is always finite/nonzero/normal here (x positive finite), so no
    # degenerate guard is needed. Single call site keeps the return union to
    # {Float64, EncloseF} — the former Float128/Enclose128F branch is dead for
    # Float64 inputs: a dyadic √x has ≤ ⌈53/2⌉ = 27 significand bits, so any
    # 113-bit-exact root is already 53-bit-exact and caught by the fma test above.
    _encl1f(sqrt, x, () -> sqrt(Float128(x)), s)
end
_mpfr_rsqrt(x::AbstractFloat) = prec -> setprecision(BigFloat, _ladderprec(prec, x)) do
    lo = setrounding(BigFloat, RoundDown) do
        s = setrounding(() -> sqrt(BigFloat(x)), BigFloat, RoundUp)
        1 / s
    end
    hi = setrounding(BigFloat, RoundUp) do
        s = setrounding(() -> sqrt(BigFloat(x)), BigFloat, RoundDown)
        1 / s
    end
    (lo, hi)
end
function ωeval(::Val{:RSqrt}, x::AbstractFloat)
    isnan(x) && return NaN
    x < 0.0 && return NaN
    iszero(x) && return NaN                                   # 1/√0 = 1/0 → NaN
    isinf(x) && return 0.0
    s = sqrt(x)
    if _fma_is_exact(s) && fma(s, s, -x) == 0                 # √x exact on this carrier
        r = 1.0 / s
        fma(r, s, -one(r)) == 0 && return r                   # 1/√x exact too ⇔ x = 4^k
    end
    # Composition of two IEEE-CR ops (hardware sqrt, then divide, each ≤ half an
    # ulp) gives |truth − yd| ≤ ~1.5 ulp ≈ 2⁻⁵¹·⁴ — ≥ 2⁶ slack under the 2⁻⁴⁵
    # envelope. The fq stage composes the same two CR ops at 113 bits (≪ 2⁻⁹⁰).
    # The former Float128 branch is dead for Float64 inputs (1/√x dyadic ⇔ x a
    # power of 4, caught above); deleting it narrows the union to {Float64, EncloseF}.
    _encl1f_rsqrt(x, s)
end

# ============================================================================
# Group "exponential / logarithmic"
# ============================================================================
function ωeval(::Val{:Exp}, x::AbstractFloat)
    isnan(x) && return NaN
    isinf(x) && return x > 0.0 ? Inf : 0.0
    iszero(x) && return 1.0
    _encl1_libm(exp, x)
end
function ωeval(::Val{:Exp2}, x::AbstractFloat)
    isnan(x) && return NaN
    isinf(x) && return x > 0.0 ? Inf : 0.0
    iszero(x) && return 1.0
    _encl1_libm(exp2, x)
end
function ωeval(::Val{:ExpMinusOne}, x::AbstractFloat)
    isnan(x) && return NaN
    x == -Inf && return -1.0
    x == Inf && return Inf
    iszero(x) && return 0.0
    _encl1_libm(expm1, x)
end
function ωeval(::Val{:Log}, x::AbstractFloat)          # draft §4.11 Log rows
    isnan(x) && return NaN
    x == -Inf && return NaN
    x == Inf && return Inf
    x < 0.0 && return NaN
    iszero(x) && return -Inf
    x == 1.0 && return 0.0
    _encl1_libm(log, x)
end
function ωeval(::Val{:Log2}, x::AbstractFloat)
    isnan(x) && return NaN
    x == -Inf && return NaN
    x == Inf && return Inf
    x < 0.0 && return NaN
    iszero(x) && return -Inf
    # exact powers of two: the fq envelope would straddle the exact integer grid
    # value and defeat the filter; MPFR resolves them via lo == hi, but the dyadic
    # screen here is cheaper and exact (Class R).
    xe = exponent(x)
    x == ldexp(1.0, xe) && return Float64(xe)
    _encl1_libm(log2, x)
end
function ωeval(::Val{:LogOnePlus}, x::AbstractFloat)
    isnan(x) && return NaN
    x < -1.0 && return NaN
    x == -1.0 && return -Inf
    x == Inf && return Inf
    iszero(x) && return 0.0
    _encl1_libm(log1p, x)
end
function ωeval(::Val{:Softplus}, x::AbstractFloat)
    isnan(x) && return NaN
    x == -Inf && return 0.0
    x == Inf && return Inf
    fq = x > 0 ? (() -> (q = Float128(x); q + log1p(exp(-q)))) :
                   (() -> log1p(exp(Float128(x))))
    yd = x > 0 ? x + log1p(exp(-x)) : log1p(exp(x))
    _enclf(prec -> setprecision(BigFloat, _ladderprec(prec, x)) do
        # monotone-↑ composition: whole-expression directed rounding is an enclosure;
        # the x > 0 form keeps it tight (and exact-side correct) for large x
        f = x > 0 ? (b -> b + log1p(exp(-b))) : (b -> log1p(exp(b)))
        (setrounding(() -> f(BigFloat(x)), BigFloat, RoundDown),
         setrounding(() -> f(BigFloat(x)), BigFloat, RoundUp))
    end, x, fq, yd)
end

# ============================================================================
# Group "trigonometric / hyperbolic"
# ============================================================================
for (name, bf) in ((:Sin, :sin), (:Cos, :cos), (:Tan, :tan))
    zval = name === :Cos ? 1.0 : 0.0
    @eval function ωeval(::Val{$(QuoteNode(name))}, x::AbstractFloat)
        isnan(x) && return NaN
        isinf(x) && return NaN                               # trig of ±∞ → NaN
        iszero(x) && return $zval
        # huge-argument reduction accuracy in libquadmath is undocumented; keep the
        # pre-filter inside a conservative window and let MPFR own the rest (§9.2:
        # "undocumented envelope ⇒ fall back")
        abs(x) <= 1.0e15 ? _encl1_libm($bf, x) : _encl1($bf, x)
    end
end
function ωeval(::Val{:ArcSin}, x::AbstractFloat)
    isnan(x) && return NaN
    abs(x) > 1.0 && return NaN
    iszero(x) && return 0.0
    x == 1.0 && return _encl_piscale(1, 1)                    #  π/2
    x == -1.0 && return _encl_piscale(-1, 1)                  # −π/2
    _encl1_libm(asin, x)
end
function ωeval(::Val{:ArcCos}, x::AbstractFloat)
    isnan(x) && return NaN
    abs(x) > 1.0 && return NaN
    x == 1.0 && return 0.0
    x == -1.0 && return _encl_piscale(1, 0)                   # π
    iszero(x) && return _encl_piscale(1, 1)                   # π/2
    _encl1f(acos, x, () -> _acos128(Float128(x)), acos(x))
end
function ωeval(::Val{:ArcTan}, x::AbstractFloat)
    isnan(x) && return NaN
    x == Inf && return _encl_piscale(1, 1)
    x == -Inf && return _encl_piscale(-1, 1)
    iszero(x) && return 0.0
    _encl1_libm(atan, x)
end
for (name, bf, inf2) in ((:Sinh, :sinh, :same), (:Cosh, :cosh, :pos), (:Tanh, :tanh, :one))
    @eval function ωeval(::Val{$(QuoteNode(name))}, x::AbstractFloat)
        isnan(x) && return NaN
        if isinf(x)
            $(inf2 === :same ? :(return x) :
              inf2 === :pos  ? :(return Inf) :
                               :(return x > 0 ? 1.0 : -1.0))
        end
        iszero(x) && return $(name === :Cosh ? 1.0 : 0.0)
        _encl1_libm($bf, x)
    end
end
function ωeval(::Val{:ArcSinh}, x::AbstractFloat)
    isnan(x) && return NaN
    isinf(x) && return x
    iszero(x) && return 0.0
    _encl1_libm(asinh, x)
end
function ωeval(::Val{:ArcCosh}, x::AbstractFloat)
    isnan(x) && return NaN
    x < 1.0 && return NaN
    x == 1.0 && return 0.0
    x == Inf && return Inf
    _encl1_libm(acosh, x)
end
function ωeval(::Val{:ArcTanh}, x::AbstractFloat)
    isnan(x) && return NaN
    abs(x) > 1.0 && return NaN
    x == 1.0 && return Inf
    x == -1.0 && return -Inf
    iszero(x) && return 0.0
    _encl1_libm(atanh, x)
end

# ============================================================================
# Group "π-scaled trigonometric" — exact mod-2 reduction, then enclosure
# ============================================================================
function ωeval(::Val{:SinPi}, x::AbstractFloat)
    isnan(x) && return NaN
    isinf(x) && return NaN
    r = _mod2(x)
    r == 0.0 && return 0.0
    r == 0.5 && return 1.0
    r == 1.0 && return 0.0
    r == 1.5 && return -1.0
    _encl_pitrig(sin, r, sinpi(r))
end
function ωeval(::Val{:CosPi}, x::AbstractFloat)
    isnan(x) && return NaN
    isinf(x) && return NaN
    r = _mod2(x)
    r == 0.0 && return 1.0
    r == 0.5 && return 0.0
    r == 1.0 && return -1.0
    r == 1.5 && return 0.0
    _encl_pitrig(cos, r, cospi(r))
end
function ωeval(::Val{:TanPi}, x::AbstractFloat)
    isnan(x) && return NaN
    isinf(x) && return NaN
    r = _mod2(x)
    r == 0.0 && return 0.0
    r == 0.5 && return Inf                                    # 754-2019 parity convention
    r == 1.0 && return 0.0
    r == 1.5 && return -Inf
    # Niven: for dyadic r the only remaining rational (hence dyadic, hence
    # grid-hittable) values of tan(πr) are ±1 at the quarter-integers — peel them,
    # or the enclosure protocol would chase an interior grid point forever.
    r == 0.25 && return 1.0
    r == 0.75 && return -1.0
    r == 1.25 && return 1.0
    r == 1.75 && return -1.0
    _encl_pitrig(tan, r, tanpi(r))
end
function ωeval(::Val{:ArcSinPi}, x::AbstractFloat)
    isnan(x) && return NaN
    abs(x) > 1.0 && return NaN
    iszero(x) && return 0.0
    x == 1.0 && return 0.5
    x == -1.0 && return -0.5
    _encl_divpi(asin, asin, x)
end
function ωeval(::Val{:ArcCosPi}, x::AbstractFloat)
    isnan(x) && return NaN
    abs(x) > 1.0 && return NaN
    x == 1.0 && return 0.0
    x == -1.0 && return 1.0
    iszero(x) && return 0.5
    _encl_divpi(acos, _acos128, x)
end
function ωeval(::Val{:ArcTanPi}, x::AbstractFloat)
    isnan(x) && return NaN
    x == Inf && return 0.5
    x == -Inf && return -0.5
    iszero(x) && return 0.0
    x == 1.0 && return 0.25
    x == -1.0 && return -0.25
    _encl_divpi(atan, atan, x)
end

# ============================================================================
# Hypot, ArcTan2, ArcTan2Pi   (operand order: (y, x), as IEEE atan2)
# ============================================================================
function ωeval(::Val{:Hypot}, x::AbstractFloat, y::AbstractFloat)
    (isinf(x) || isinf(y)) && return Inf                     # ∞ dominates even NaN
    (isnan(x) | isnan(y)) && return NaN
    iszero(y) && return abs(x)                               # exact
    iszero(x) && return abs(y)
    _encl2f(hypot, x, y, () -> hypot(Float128(x), Float128(y)), hypot(x, y))
end
function ωeval(::Val{:ArcTan2}, y::AbstractFloat, x::AbstractFloat)
    (isnan(y) | isnan(x)) && return NaN
    (iszero(y) & iszero(x)) && return NaN                    # D1 §4.10.15
    (isinf(y) & isinf(x)) && return NaN                      # D1: every (±∞, ±∞) pair
    if iszero(y)
        x > 0.0 && return 0.0                                # atan2(0, x>0) = 0
        return _encl_piscale(1, 0)                           # atan2(0, x<0 or −∞) = π
    end
    if isinf(y)
        return _encl_piscale(y > 0 ? 1 : -1, 1)                  # ±π/2
    end
    x == Inf && return 0.0
    x == -Inf && return _encl_piscale(y > 0 ? 1 : -1, 0)         # ±π
    iszero(x) && return _encl_piscale(y > 0 ? 1 : -1, 1)         # ±π/2
    _encl2f(atan, y, x, () -> atan(Float128(y), Float128(x)), atan(y, x))  # MPFR atan2, correct per mode
end
function ωeval(::Val{:ArcTan2Pi}, y::AbstractFloat, x::AbstractFloat)
    (isnan(y) | isnan(x)) && return NaN
    (iszero(y) & iszero(x)) && return NaN
    (isinf(y) & isinf(x)) && return NaN
    if iszero(y)
        x > 0.0 && return 0.0
        return 1.0
    end
    if isinf(y)
        return y > 0 ? 0.5 : -0.5
    end
    x == Inf && return 0.0
    x == -Inf && return y > 0 ? 1.0 : -1.0
    iszero(x) && return y > 0 ? 0.5 : -0.5
    # diagonals give exactly ±1/4, ±3/4 — dyadic, so peel (Niven-termination):
    y == x && return y > 0 ? 0.25 : -0.75
    y == -x && return y > 0 ? 0.75 : -0.25
    _encl_divpi(atan, atan, y, x)
end
