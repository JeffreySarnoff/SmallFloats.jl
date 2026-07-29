# ===== carriers.jl — the evaluation-carrier lattice (implementextensions §2 R-A, §3.2)
#
# Two independent axes govern the K ≤ 16 grid. `formats.jl` owns the first —
# *storage unit*, a function of K. This file owns the second — *evaluation
# carrier*, a function of the exponent bias B, not of K. `Binary16p12se`
# (B = 8) is numerically tamer than `Binary8p1uf` (B = 128): K counts code
# points, B says how far apart they can be.
#
# The carrier ladder is not new. `Float64 → Float128 → MPFR` is already the
# package's escalation ladder; extending K does not add a rung, it makes the
# *starting* rung a per-format trait instead of the constant `Float64`.
#
# THE CARRIER IS A PROPERTY OF VALUES IN FLIGHT, NOT OF FORMATS AT REST
# (implementextensions §1 C10). A format's carrier constrains what `decode`
# returns and what `ωeval` may form. It never constrains what may be projected
# *into* the format: `round_to_precision` works in (P, B) integer space and is
# exact for any exact input, so `Convert`, `one`, `zero`, `eps` and the whole
# write path need no carrier work at any K.
#
# Every trait here is selected by DISPATCH, never by a branch that returns a
# type (invariant 9). Where the condition is a function of static parameters it
# goes behind a `Val` and dispatches on that; the barrier method then has ONE
# concrete return type, so there is no Union for inference to widen. Gate G9
# pins that per format.

# ---- rung tags ---------------------------------------------------------------

"""
    Head

Evaluation-carrier selector: a singleton tag, so carrier choice is a method
lookup rather than a value the compiler must fold. Rungs are ordered
`HeadF64 < HeadF128 < HeadExact` by carrier width.
"""
abstract type Head end

"""Rung 1 — `Float64` arithmetic. Every K ≤ 8 format and 432 of the 504."""
struct HeadF64 <: Head end
"""Rung 2 — `Float128` arithmetic (the existing escalation machinery, promoted
to entry point). Allocation-free: `Float128` is a bitstype."""
struct HeadF128 <: Head end
"""Rung 3 — unbounded exponent. `BigFloat` until Stage 7, `Dyadic` after; the
tag is the seam that makes that swap a one-line change (gate G7 pins that the
two agree)."""
struct HeadExact <: Head end

# BOTH forms are required and defining only one is the classic first-day error:
# the tag flows as a VALUE through `ωeval` dispatch but as a TYPE PARAMETER
# through `apply_op`'s result split, where `res isa carriertype(H)` must fold to
# a literal type in each specialization.
@inline carriertype(::HeadF64)   = Float64
@inline carriertype(::HeadF128)  = Float128
@inline carriertype(::HeadExact) = BigFloat        # → Dyadic at Stage 7
@inline carriertype(::Type{H}) where {H<:Head} = carriertype(H())

"""Rung index 1/2/3 of a head — for ordering and for the carrier join."""
@inline rungindex(::HeadF64)   = 1
@inline rungindex(::HeadF128)  = 2
@inline rungindex(::HeadExact) = 3

"""The wider of two heads. The carrier join is a max over this order, which is
what lets block and scaled operations compose without a second rule."""
@inline joinhead(a::Head, b::Head) = rungindex(a) >= rungindex(b) ? a : b

# ---- rung boundaries ---------------------------------------------------------
#
# A datum satisfies |X| < 2^B, and an operation's worst-case intermediate is a
# monomial in n datum factors, so the monomial fits a carrier with maximum
# exponent emax exactly when ΣBᵢ ≤ emax (and the under-range companion
# Σ(Bᵢ+Pᵢ) ≤ −emin + 2n, which is slacker at every K ≤ 16).
#
#     rung 1  Float64    emax  1024   −emin  1074
#     rung 2  Float128   emax 16384   −emin 16494
#     rung 3  unbounded
#
# For a scalar op the worst case is n = 2 (Multiply/Divide/Hypot), so the
# per-format boundaries below are stated on 2B and are equivalent to B ≤ 512 /
# B ≤ 8192 — verified to give the same 432/64/8 partition of the 504-format grid
# either way (implementextensions Appendix C).

"""Per-format rung index from the exponent bias. A pure `Int` function of the
type parameters, so `Val(_rungindex(F))` is a compile-time constant."""
@inline function _rungindex(::Type{F}) where {F<:Binary}
    B = expbias(F)
    B <= 512 ? 1 : B <= 8192 ? 2 : 3
end

"""
    rung(F) -> Head

The starting carrier for evaluating on datums of format `F` alone. For an
operation over several formats use `rung(op, Fs...)`, which additionally
accounts for the operation's factor count — a `ScaledMultiply` of two Group A
formats can need a wider carrier than either operand does.
"""
@inline rung(::Type{F}) where {F<:Binary} = _rung(Val(_rungindex(F)), F)
@inline _rung(::Val{1}, ::Type{<:Binary}) = HeadF64()
@inline _rung(::Val{2}, ::Type{<:Binary}) = HeadF128()
@inline _rung(::Val{3}, ::Type{<:Binary}) = HeadExact()
@inline rung(v::Binary) = rung(typeof(v))

# ---- the two carrier traits, deliberately distinct ---------------------------
#
# `datumcarrier` is INTERNAL: what `decode` returns and `ωeval` computes on. It
# may be `Dyadic`, which is not a Julia `AbstractFloat` and implements only the
# ~10 operations the engine needs.
#
# `promotecarrier` is PUBLIC: the target of `promote_rule` for `F ⋄ external`.
# It is always a real Julia float, so `x + 1.0` on a wide format promotes to
# something with a complete `Real` interface. Routing both through one trait
# (as an earlier draft did) would force the full `Real` surface onto an
# internal carrier — a large public obligation for no benefit.

"""The exact carrier for the *datums* of `F`: what `decode(v::F)` returns."""
@inline datumcarrier(::Type{F}) where {F<:Binary} = _datumcarrier(Val(_rungindex(F)), F)
@inline _datumcarrier(::Val{1}, ::Type{<:Binary}) = Float64
@inline _datumcarrier(::Val{2}, ::Type{<:Binary}) = Float128
@inline _datumcarrier(::Val{3}, ::Type{<:Binary}) = BigFloat     # → Dyadic at Stage 7
@inline datumcarrier(v::Binary) = datumcarrier(typeof(v))

"""The public promotion target for `F` against external numeric types. Always a
Julia `AbstractFloat`, never the internal exact carrier."""
@inline promotecarrier(::Type{F}) where {F<:Binary} = _promotecarrier(Val(_rungindex(F)), F)
@inline _promotecarrier(::Val{1}, ::Type{<:Binary}) = Float64
@inline _promotecarrier(::Val{2}, ::Type{<:Binary}) = Float128
@inline _promotecarrier(::Val{3}, ::Type{<:Binary}) = BigFloat

# ---- carrier-generic constants ----------------------------------------------
#
# `_decode_compute`'s special rows return NaN / ±Inf, which are `Float64`
# literals today. Under a wider carrier those are a silent narrow-then-widen,
# and under `Dyadic` they are simply wrong-typed. The four constants below are
# the carrier-generic replacement; `Dyadic` adds its own methods at Stage 7.

@inline _cnan(::Type{C})  where {C<:AbstractFloat} = C(NaN)
@inline _cinf(::Type{C})  where {C<:AbstractFloat} = C(Inf)
@inline _cninf(::Type{C}) where {C<:AbstractFloat} = C(-Inf)
@inline _czero(::Type{C}) where {C<:AbstractFloat} = zero(C)

# ---- MPFR precision ----------------------------------------------------------

"""
    bigprec(Fs...) -> Int

Exact-arithmetic precision for the MPFR escalations, derived from the operand
formats rather than fixed.

An exact sum of two datums needs `spread + max(Pᵢ) + 1` bits, and the spread
between the largest and smallest magnitudes of a format reaches `2B + P`. The
constant it replaces (`_BIGP = 2200`) is ample through B = 512 and **silently
truncates** above it — a truncated "exact" BigFloat is the worst failure mode
available, because it is indistinguishable from a correct one without a
reference. Gate G2 is written red against the `Binary16p1uf` witness before
this is wired in.
"""
@inline function bigprec(Fs::Vararg{Type{<:Binary},N}) where {N}
    maxB = 0; maxP = 0
    for F in Fs
        maxB = max(maxB, expbias(F))
        maxP = max(maxP, precision(F))
    end
    2 * (maxB + maxP) + 64
end
