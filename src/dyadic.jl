# ===== dyadic.jl — the rung-3 exact carrier (§3.1, §4 Stage 7)
#
# An exact dyadic rational `S · 2^Q`, plus the three non-finite rows. It is the
# carrier `HeadExact` computes on once Stage 7 lands; `BigFloat` filled that role
# through Stage 6 and remains the differential oracle (gate G7 asserts the two
# produce identical code points across the whole Group C surface).
#
# WHY A CARRIER RATHER THAN MPFR. Every datum of every P3109 format is exactly
# `S · 2^Q` with `|S| < 2^16` — the values are dyadic by construction, and MPFR's
# machinery (allocation, ambient precision, rounding modes) buys nothing for
# arithmetic that is closed and exact. `Dyadic` makes the rung-3 hot path
# allocation-free; the transcendental fallback still goes to MPFR, and that
# allocation is a recorded property of the tier rather than a suite failure.
#
# THIS FILE HAS NO SmallFloats DEPENDENCIES and loads first. That is deliberate:
# the type must be checkable on its own terms, and nothing here may reach for a
# format, a trait, or a projection. Every function is total over the four kinds.
#
# `<: Real` and NOT `<: AbstractFloat`. The distinction is load-bearing: methods
# throughout the package are written `::AbstractFloat` for "a float carrier", and
# `Dyadic` implements roughly ten operations rather than the full `AbstractFloat`
# obligation (no `precision`, no `eps`, no `nextfloat`, no `signbit`-driven
# generic fallbacks that would silently do the wrong thing). Subtyping `Real` is
# what keeps `promote_rule` honest: `promotecarrier` targets `BigFloat`, never
# this, precisely so a value escaping to a caller carries a complete interface.

module DyadicNumbers

export Dyadic, DY_FINITE, DY_POSINF, DY_NEGINF, DY_NAN,
       dyadic_to_rational, rational_to_dyadic, isdyadic

# The kind tag exists because a dyadic rational cannot represent ±Inf or NaN, and
# the ω-semantics catalog produces all three. Encoding them in `S`/`Q` sentinels
# (the predecessor's first sketch) makes every arithmetic method carry a special
# case in its fast path; a separate field keeps the finite path branch-free after
# one check.
const DY_FINITE = 0x00
const DY_POSINF = 0x01
const DY_NEGINF = 0x02
const DY_NAN    = 0x03

"""
    Dyadic(S::Int128, Q::Int64)      -> the exact value S · 2^Q
    Dyadic(kind::UInt8)              -> one of the three non-finite rows

An exact dyadic rational, the rung-3 evaluation carrier.

`S` is a *signed* significand and is deliberately not normalized: normalizing
after every operation costs a `trailing_zeros` and a shift for no benefit, since
the only consumer is `round_to_precision`, which realigns anyway. Two `Dyadic`s
may therefore represent the same value with different `(S, Q)`; `==` compares
values, not fields.
"""
struct Dyadic <: Real
    kind::UInt8
    S::Int128
    Q::Int64
end
Dyadic(S::Integer, Q::Integer) = Dyadic(DY_FINITE, Int128(S), Int64(Q))
Dyadic(kind::UInt8) = Dyadic(kind, Int128(0), Int64(0))

const DYADIC_ZERO   = Dyadic(Int128(0), Int64(0))
const DYADIC_ONE    = Dyadic(Int128(1), Int64(0))
const DYADIC_POSINF = Dyadic(DY_POSINF)
const DYADIC_NEGINF = Dyadic(DY_NEGINF)
const DYADIC_NAN    = Dyadic(DY_NAN)

# ---- predicates. Total over the four kinds; none of them can throw.
@inline isfinite_dy(x::Dyadic) = x.kind == DY_FINITE
@inline isnan_dy(x::Dyadic)    = x.kind == DY_NAN
@inline isinf_dy(x::Dyadic)    = x.kind == DY_POSINF || x.kind == DY_NEGINF
@inline iszero_dy(x::Dyadic)   = x.kind == DY_FINITE && iszero(x.S)

Base.isfinite(x::Dyadic) = isfinite_dy(x)
Base.isnan(x::Dyadic)    = isnan_dy(x)
Base.isinf(x::Dyadic)    = isinf_dy(x)
Base.iszero(x::Dyadic)   = iszero_dy(x)
Base.zero(::Type{Dyadic}) = DYADIC_ZERO
Base.zero(::Dyadic)       = DYADIC_ZERO
Base.one(::Type{Dyadic})  = DYADIC_ONE
Base.one(::Dyadic)        = DYADIC_ONE

"""Sign as an `Int` in `{-1, 0, 1}`; `NaN` answers 0, matching no float and
deliberately so — callers must test `isnan` first, and a sign of 0 for NaN makes
a missing test show up as a wrong answer rather than as a plausible one."""
@inline function sign_dy(x::Dyadic)
    x.kind == DY_POSINF && return 1
    x.kind == DY_NEGINF && return -1
    x.kind == DY_NAN    && return 0
    x.S > 0 ? 1 : (x.S < 0 ? -1 : 0)
end
"""Sign as an `Int` in `{-1, 0, 1}`; `NaN` answers 0, matching no float and
deliberately so — callers must test `isnan` first, and a sign of 0 for NaN makes
a missing test show up as a wrong answer rather than as a plausible one."""
Base.sign(x::Dyadic) = sign_dy(x)
Base.signbit(x::Dyadic) = sign_dy(x) < 0

@inline function Base.abs(x::Dyadic)
    x.kind == DY_NEGINF && return DYADIC_POSINF
    isfinite_dy(x) || return x
    Dyadic(DY_FINITE, abs(x.S), x.Q)
end
@inline function Base.:-(x::Dyadic)
    x.kind == DY_POSINF && return DYADIC_NEGINF
    x.kind == DY_NEGINF && return DYADIC_POSINF
    isfinite_dy(x) || return x
    Dyadic(DY_FINITE, -x.S, x.Q)
end

"""Number of significant bits in `|S|` — the head width the add band is stated
against. Zero answers 0."""
@inline nbits_dy(S::Int128) = iszero(S) ? 0 : (128 - leading_zeros(unsigned(abs(S))))

# ---- addition, with the C7 bands.
#
#   exact Int128 alignment      :  ΔQ ≤ 94                (32-bit head + carry)
#   sticky (tail is sign only)  :  ΔQ > P + N + 2
#   total coverage              ⟺  P + N ≤ 92
#   current worst case          :  P = 16, N = 60  ⇒  76 ≤ 92, margin 16
#   overlap band                :  ΔQ ∈ [79, 94]
#
# The inherited plan stated `ΔQ ≤ 95` and a ceiling of `P ≤ 45`. Both are wrong:
# 95 omits the carry bit the sum needs, and 45 corresponds to a 20-bit head, not
# the 32-bit head the same document assumes. The conclusion — the bands overlap
# with room to spare — survives; the *margin* does not, and the margin is the
# number a future widening gets checked against (§1 C7).
#
# **`DYADIC_ADD_COVERAGE` is asserted by the suite, not merely commented.** This
# is the one place where raising `P` past 16 or `N` past 60 would silently open a
# gap between the two bands — silently, because a ΔQ falling into the gap would
# be handled by neither the exact path nor the sticky one, and the fallback is
# what would answer.
const DYADIC_HEAD_BITS    = 32
const DYADIC_ALIGN_MAX    = 127 - DYADIC_HEAD_BITS - 1     # 94
const DYADIC_ADD_COVERAGE = 92                             # P + N must not exceed

"""
    add_dy(x, y) -> Dyadic

Exact sum when the operands align within `DYADIC_ALIGN_MAX`; otherwise the
caller is past the sticky threshold and `add_sticky_dy` applies. Returns a
`Dyadic` whose `kind` carries the IEEE ∞/NaN algebra.
"""
@inline function add_dy(x::Dyadic, y::Dyadic)
    (isnan_dy(x) | isnan_dy(y)) && return DYADIC_NAN
    if isinf_dy(x) || isinf_dy(y)
        (isinf_dy(x) && isinf_dy(y) && x.kind != y.kind) && return DYADIC_NAN
        return isinf_dy(x) ? x : y
    end
    iszero(x.S) && return y
    iszero(y.S) && return x
    # align on the lower exponent; the shift is exact while it fits Int128
    if x.Q >= y.Q
        d = x.Q - y.Q
        d > DYADIC_ALIGN_MAX && return _add_wide(x, y, d)
        Dyadic(DY_FINITE, (x.S << d) + y.S, y.Q)
    else
        d = y.Q - x.Q
        d > DYADIC_ALIGN_MAX && return _add_wide(y, x, d)
        Dyadic(DY_FINITE, (y.S << d) + x.S, x.Q)
    end
end

# Past the alignment band the small operand cannot reach the head's significant
# bits at all, so its only contribution is a sticky sign. Returning the head with
# its significand nudged by one unit in the tail direction would be wrong (it
# would move the value); the caller's `round_to_precision` takes the sticky sign
# separately, so this path is reached only through `add_sticky_dy`, and `_add_wide`
# exists to make the unreachable case loud rather than silently truncating.
@noinline _add_wide(::Dyadic, ::Dyadic, d::Int) = throw(ArgumentError(
    "Dyadic add with ΔQ = $d exceeds the exact alignment band " *
    "(DYADIC_ALIGN_MAX = $DYADIC_ALIGN_MAX); the caller must take the sticky " *
    "path, which is only sound for ΔQ > P + N + 2 — see the C7 bands in dyadic.jl"))

"""
    add_sticky_dy(x, y) -> (Dyadic, Int)

The sum together with a sticky sign in `{-1, 0, +1}` describing a tail below the
returned value's last bit. Chooses the exact band when the operands align and the
sign-only band otherwise, which is exactly the C7 overlap argument in code."""
@inline function add_sticky_dy(x::Dyadic, y::Dyadic)
    (isnan_dy(x) | isnan_dy(y)) && return (DYADIC_NAN, 0)
    if isinf_dy(x) || isinf_dy(y)
        (isinf_dy(x) && isinf_dy(y) && x.kind != y.kind) && return (DYADIC_NAN, 0)
        return (isinf_dy(x) ? x : y, 0)
    end
    iszero(x.S) && return (y, 0)
    iszero(y.S) && return (x, 0)
    big, small = x.Q >= y.Q ? (x, y) : (y, x)
    d = big.Q - small.Q
    d <= DYADIC_ALIGN_MAX && return (add_dy(x, y), 0)
    (big, small.S > 0 ? 1 : -1)
end

"""
    mul_dy(x, y) -> Dyadic

Exact product. **Precondition:** `nbits(x.S) + nbits(y.S) ≤ 96`, checked under
`@boundscheck` rather than always, because every operand the engine produces
satisfies it by a wide margin (a datum's significand is ≤ 16 bits, so a product
of four is ≤ 64) and the check is pure overhead on the path that matters."""
@inline function mul_dy(x::Dyadic, y::Dyadic)
    (isnan_dy(x) | isnan_dy(y)) && return DYADIC_NAN
    if isinf_dy(x) || isinf_dy(y)
        (iszero_dy(x) | iszero_dy(y)) && return DYADIC_NAN          # 0 · ∞
        return sign_dy(x) * sign_dy(y) > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    end
    @boundscheck nbits_dy(x.S) + nbits_dy(y.S) <= 96 ||
        throw(ArgumentError("Dyadic multiply would overflow Int128: " *
                            "$(nbits_dy(x.S)) + $(nbits_dy(y.S)) significand bits > 96"))
    Dyadic(DY_FINITE, x.S * y.S, x.Q + y.Q)
end

# ---- ordering and equality, by VALUE rather than by field, since `(S, Q)` is
# not normalized. Comparison aligns the same way addition does.
# Comparison is TOTAL and does not go through `add_dy`. The first version did,
# and `add_dy` is only exact inside the alignment band — so comparing a tiny
# value against a huge one, which is perfectly well defined, threw. Ordering has
# no band: sign, then binade, then aligned significands, and the alignment here
# is bounded by the *difference in significand widths* (the exponents are already
# equal at that point), never by ΔQ.
@inline function cmp_dy(x::Dyadic, y::Dyadic)
    (isnan_dy(x) | isnan_dy(y)) && return 2            # unordered, distinct from -1/0/1
    sx, sy = sign_dy(x), sign_dy(y)
    sx != sy && return sx < sy ? -1 : 1
    isinf_dy(x) && isinf_dy(y) && return 0
    isinf_dy(x) && return sx > 0 ? 1 : -1              # x infinite, y finite, same sign
    isinf_dy(y) && return sy > 0 ? -1 : 1
    sx == 0 && return 0                                # both zero
    ex, ey = exponent_dy(x), exponent_dy(y)
    if ex != ey
        m = ex < ey ? -1 : 1
        return sx > 0 ? m : -m
    end
    ax, ay = abs(x.S), abs(y.S)
    if x.Q >= y.Q
        ax <<= (x.Q - y.Q)
    else
        ay <<= (y.Q - x.Q)
    end
    m = ax == ay ? 0 : (ax < ay ? -1 : 1)
    sx > 0 ? m : -m
end
Base.:(==)(x::Dyadic, y::Dyadic) = cmp_dy(x, y) == 0
Base.:(<)(x::Dyadic, y::Dyadic)  = cmp_dy(x, y) == -1
Base.:(<=)(x::Dyadic, y::Dyadic) = (c = cmp_dy(x, y); c == -1 || c == 0)
# ---- Base arithmetic: TOTAL, and therefore not `add_dy`/`mul_dy`.
#
# `add_dy` and `mul_dy` are the engine's kernels and they are deliberately
# **partial**: outside the C7 bands they throw, because inside the engine the
# caller is required to have taken the sticky path instead, and a kernel that
# quietly did something else would hide that. That contract is right for a
# kernel and wrong for `+`.
#
# `Dyadic` is a `Real` that reaches users — `decode` returns it for the eight
# rung-3 formats — so `x + y` must answer for every pair of values, not for the
# 94-binade window the kernel accepts. `Binary16p1uf` spans 65 533 binades, so
# "outside the band" is the *common* case there, not an edge: summing a decoded
# vector threw (§11 M44).
#
# The total form returns `BigFloat`, which is the format's `promotecarrier` and
# therefore the type mixed arithmetic already lands on — `Dyadic` stays the
# storage and evaluation form, and ordinary arithmetic on escaped values leaves
# it, exactly once, into the carrier the promotion lattice already names. The
# precision is computed from the operands so the result is exact, never rounded
# at the ambient setting.
#
# Nothing on the hot path calls these: `_ωdyadic` uses `add_sticky_dy` and
# `mul_dy` by name, which is the point — the engine keeps the partial kernel and
# its obligation to check, and everyone else gets a total operation.
@inline function _bigspan(x::Dyadic, y::Dyadic)
    lo = min(x.Q, y.Q)
    hi = max(x.Q + nbits_dy(x.S), y.Q + nbits_dy(y.S))
    max(Int(hi - lo) + 1, 2)
end
function Base.:+(x::Dyadic, y::Dyadic)
    (isfinite_dy(x) & isfinite_dy(y)) || return BigFloat(x) + BigFloat(y)
    setprecision(() -> BigFloat(x) + BigFloat(y), BigFloat, _bigspan(x, y))
end
Base.:-(x::Dyadic, y::Dyadic) = x + (-y)
function Base.:*(x::Dyadic, y::Dyadic)
    (isfinite_dy(x) & isfinite_dy(y)) || return BigFloat(x) * BigFloat(y)
    p = max(nbits_dy(x.S) + nbits_dy(y.S), 2)
    setprecision(() -> BigFloat(x) * BigFloat(y), BigFloat, p)
end

"""
    ldexp(x::Dyadic, n) -> Dyadic

`x · 2^n`, exactly and unconditionally — it adds `n` to the exponent field and
touches nothing else. On `Float64` or `Float128` the same call can overflow to
±Inf or flush to zero; here there is no range to leave, which is the property the
P = 1 block-scale path in `blocks.jl` is built on and the reason `decode`'s
generic finite path needs no carrier-specific guard at rung 3.
"""
@inline function Base.ldexp(x::Dyadic, n::Integer)
    isfinite_dy(x) || return x
    Dyadic(DY_FINITE, x.S, x.Q + Int64(n))
end

"""Binary exponent of `|x|`, i.e. `⌊log₂|x|⌋`. Undefined for zero and the
non-finite rows, which is why it asserts rather than returning a sentinel."""
@inline function exponent_dy(x::Dyadic)
    isfinite_dy(x) && !iszero(x.S) ||
        throw(DomainError(x, "Dyadic exponent is defined only for finite nonzero values"))
    x.Q + nbits_dy(x.S) - 1
end
"""Binary exponent of `|x|`, i.e. `⌊log₂|x|⌋`. Undefined for zero and the
non-finite rows, which is why it asserts rather than returning a sentinel."""
Base.exponent(x::Dyadic) = exponent_dy(x)

# ---- integer rounding, exactly and without allocating.
#
# `trunc`/`floor`/`ceil`/`round` on a `Dyadic` are pure integer arithmetic: the
# value is `S · 2^Q`, so `Q ≥ 0` is already an integer and `Q < 0` means the low
# `-Q` bits of `S` are the fraction. Routing through `BigFloat` would be exact
# too — and would allocate on every call, at the one rung where the carrier was
# chosen specifically to avoid MPFR on the ordinary path.
#
# `-Q ≥ 128` cannot be a shift: the whole significand is below the binary point,
# so the value is strictly inside `(-1, 1)` and the answer is decided by sign
# alone. Julia's `>>` on `Int128` saturates rather than wrapping, but relying on
# that would be relying on a detail; the branch says what it means.
@inline function _split_dy(x::Dyadic)
    x.Q >= 0 && return (x.S << x.Q, zero(Int128), 0)      # already an integer
    sh = -Int(x.Q)
    sh >= 128 && return (zero(Int128), x.S, sh)           # |x| < 1
    q = x.S >> sh                                          # arithmetic shift: floors
    (q, x.S - (q << sh), sh)                               # (floor, remainder ≥ 0, shift)
end

@inline _int_dy(q::Int128) = Dyadic(DY_FINITE, q, 0)

function Base.floor(x::Dyadic)
    isfinite_dy(x) || return x
    q, _, _ = _split_dy(x)
    _int_dy(q)                       # `>>` already floors toward −∞
end

function Base.ceil(x::Dyadic)
    isfinite_dy(x) || return x
    q, r, _ = _split_dy(x)
    _int_dy(iszero(r) ? q : q + one(Int128))
end

Base.trunc(x::Dyadic) = isfinite_dy(x) ? (sign_dy(x) < 0 ? ceil(x) : floor(x)) : x

"""Round half to even, matching `Base.round(::AbstractFloat)`."""
function Base.round(x::Dyadic)
    isfinite_dy(x) || return x
    q, r, sh = _split_dy(x)
    iszero(r) && return _int_dy(q)
    # compare the fraction against ½ without forming it: 2r vs 2^sh
    twice = r << 1
    half = sh >= 128 ? nothing : (one(Int128) << sh)
    up = half === nothing ? false :
         twice > half ? true : twice < half ? false : !iseven(q)   # tie → even
    _int_dy(up ? q + one(Int128) : q)
end

Base.round(x::Dyadic, ::RoundingMode{:Down})    = floor(x)
Base.round(x::Dyadic, ::RoundingMode{:Up})      = ceil(x)
Base.round(x::Dyadic, ::RoundingMode{:ToZero})  = trunc(x)
Base.round(x::Dyadic, ::RoundingMode{:Nearest}) = round(x)

# ---- conversions. Exact in both directions for every value the engine forms.
#
# `BigFloat(::Dyadic)` is what gate G7 compares against, so it must be exact
# rather than merely close: the precision is taken from the significand's own
# width, never from the ambient setting, so a low ambient precision cannot
# silently round the oracle's own input.
function Base.BigFloat(x::Dyadic)
    x.kind == DY_NAN    && return BigFloat(NaN)
    x.kind == DY_POSINF && return BigFloat(Inf)
    x.kind == DY_NEGINF && return BigFloat(-Inf)
    iszero(x.S) && return BigFloat(0)
    p = max(nbits_dy(x.S) + 1, 2)
    setprecision(BigFloat, p) do
        ldexp(BigFloat(x.S), x.Q)
    end
end
# Conversion OUT to an ordinary binary float, for every width the package meets.
#
# Routed through `BigFloat`, which is exact, so the narrowing is a **single**
# rounding. The direct `ldexp(Float64(x.S), x.Q)` is a double rounding whenever
# `|S| > 2^53` — reachable after a multiply, since `mul_dy` permits 96 significand
# bits — and double rounding can land a tie on the wrong side. Rare, silent, and
# exactly the class of defect this carrier exists to remove, so it is not worth
# the cycles saved on a boundary conversion.
function _dyadic_to(::Type{T}, x::Dyadic) where {T<:AbstractFloat}
    x.kind == DY_NAN    && return T(NaN)
    x.kind == DY_POSINF && return T(Inf)
    x.kind == DY_NEGINF && return T(-Inf)
    iszero(x.S) && return zero(T)
    T(BigFloat(x))
end
Base.Float64(x::Dyadic) = _dyadic_to(Float64, x)
# `big` is the standard "widen to arbitrary precision" verb, and for this carrier
# it is exactly the exact form. Note what is deliberately NOT defined: `float`.
# `_rtp_core`'s zero row builds `zero(float(typeof(X)))`, so defining
# `float(::Dyadic)` would silently re-open a path this carrier must not take —
# the absence is load-bearing, not an omission (§4 Stage 7 item 3).
Base.big(x::Dyadic) = BigFloat(x)

"""
    decompose(x::Dyadic) -> (num, pow, den)

Base's contract is `x == num * 2^pow / den`, and for this carrier that is the
representation itself: `(S, Q, 1)`.

Two conventions of Base's have to be honoured, and the second is the one that
bit: **`den == 0` signals non-finite** — `(0, 0, 0)` for NaN and `(±1, 0, 0)` for
±Inf — which is how every consumer distinguishes them. Returning a finite-looking
`den = 1` for a non-finite value makes NaN and ±Inf read as *finite zero*, which
is what G6 caught.

The sign lives in the **numerator** here, where a binary float puts it in the
denominator — the other trap G6 recorded, where reading `den == 1` as "positive
and finite" misclassified every negative datum. A positive `den` is correct for
this carrier and is what a reader would assume, so consumers written against the
float behaviour keep working.
"""
function Base.decompose(x::Dyadic)
    x.kind == DY_NAN    && return (Int128(0), 0, Int128(0))
    x.kind == DY_POSINF && return (Int128(1), 0, Int128(0))
    x.kind == DY_NEGINF && return (Int128(-1), 0, Int128(0))
    (x.S, Int(x.Q), Int128(1))
end

# ---- Dyadic ↔ Rational (docs/other/dyadic_rational.md)
#
# The exact bridge in both directions. A `Dyadic` already IS `S · 2^Q`, so the
# rational conversion is the definition rather than a decomposition — which is
# what makes it the right comparison against `test/refimpl.jl`'s
# `Rational{BigInt}` oracle: the value never routes through a carrier whose
# exactness is part of what is being tested.

"""Fit a `BigInt` into `T`, or say which side overflowed and by how much.

Two-sided bounds, not `abs(n) <= typemax(T)`: `abs(typemin(Int128))` wraps to
itself, so the `abs` form is wrong on exactly one input — and that input is a
legitimate significand."""
_fit_rat(::Type{BigInt}, n::BigInt, _) = n
_fit_rat(::Type{T}, n::BigInt, what) where {T<:Integer} =
    typemin(T) <= n <= typemax(T) ? T(n) :
        throw(OverflowError("dyadic_to_rational: the $what needs " *
                            "$(ndigits(n; base=2)) bits, which Rational{$T} " *
                            "cannot hold; use Rational{BigInt}"))

"""
    dyadic_to_rational([T=BigInt,] x::Dyadic) -> Rational{T}

The **exact** value as a rational.

`BigInt` is the default because it is the only target that cannot fail: `Q`
reaches ±32 768 at `Binary16p1uf`, so `2^-Q` needs ~32 768 bits. A narrow `T` is
accepted and **checked** — it throws `OverflowError` naming the side that did not
fit, rather than wrapping.

Non-finite rows follow **Base**, which is the correction this function carries:
`Rational` does represent infinities, so `+Inf` is `1//0` and `-Inf` is `-1//0`,
exactly as `Rational{BigInt}(Inf)` gives. Only NaN has no rational slot (`0//0`
is rejected by Base too) and throws. The predecessor threw on all three, from the
untested premise that "a rational cannot represent infinity".

The reduction is a **shift, not a gcd**. `Rational`'s invariant wants
`gcd(num, den) == 1`; here `den` is a power of two, so the common factor is
`2^min(trailing_zeros(S), -Q)` and one instruction establishes the invariant that
Euclid's algorithm would have found. `unsafe_rational` is then safe in the strict
sense — the invariant is established, not skipped.

See also [`rational_to_dyadic`](@ref), [`isdyadic`](@ref)."""
function dyadic_to_rational(::Type{T}, x::Dyadic) where {T<:Integer}
    x.kind == DY_NAN && throw(InexactError(:dyadic_to_rational, Rational{T}, x))
    x.kind == DY_POSINF && return Base.unsafe_rational(one(T), zero(T))
    x.kind == DY_NEGINF && return Base.unsafe_rational(-one(T), zero(T))
    iszero(x.S) && return Base.unsafe_rational(zero(T), one(T))
    n, q = BigInt(x.S), Int(x.Q)
    if q >= 0
        Base.unsafe_rational(_fit_rat(T, n << q, "numerator"), one(T))
    else
        k = min(trailing_zeros(n), -q)                 # cancel, do not gcd
        Base.unsafe_rational(_fit_rat(T, n >> k, "numerator"),
                             _fit_rat(T, BigInt(1) << (-q - k), "denominator"))
    end
end
dyadic_to_rational(x::Dyadic) = dyadic_to_rational(BigInt, x)

"""
    isdyadic(q::Rational) -> Bool

Whether `q` is exactly representable as a [`Dyadic`](@ref) — that is, whether its
denominator is a power of two (`±1//0` counts: the infinities are representable).

The honest counterpart to a partial conversion. `1//3` is not a dyadic rational
and no wider type fixes that, so `rational_to_dyadic` must refuse it; this is what
lets a caller branch without exception handling. Julia has no `tryconvert`, and a
predicate beside the throwing conversion is the idiomatic substitute."""
isdyadic(q::Rational) = iszero(denominator(q)) || ispow2(denominator(q))

"""
    rational_to_dyadic(q::Rational) -> Dyadic

The exact `Dyadic` for a dyadic rational.

**Refuses rather than rounds.** A `Rational` whose denominator is not a power of
two has no `Dyadic`, and rounding one here would be a rounding performed outside
`project` — which invariant 1 forbids. Test with [`isdyadic`](@ref) first if the
input may not qualify.

`±1//0` map to the infinities. `0//0` cannot arise: Base rejects it at
construction.

The algorithm never assumes `q` is reduced — the power-of-two test and the
trailing-zero strip are correct on a hand-built `unsafe_rational(2, 4)` — which
removes a premise rather than relying on one."""
function rational_to_dyadic(q::Rational)
    n, d = numerator(q), denominator(q)
    iszero(d) && return n > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    iszero(n) && return DYADIC_ZERO
    ispow2(d) || throw(InexactError(:rational_to_dyadic, Dyadic, q))
    k = trailing_zeros(d)                              # d == 2^k
    nb = BigInt(n)
    tz = trailing_zeros(nb)
    s = nb >> tz
    typemin(Int128) <= s <= typemax(Int128) || throw(InexactError(
        :rational_to_dyadic, Dyadic, q))
    Q = tz - k
    # Unreachable for any rational a machine can hold — it would need an integer
    # with ~9.2e18 bits — and checked anyway, so an impossible silent wrap is a
    # stated refusal instead (the trade §11 M48 made for `project_interval`).
    typemin(Int64) <= Q <= typemax(Int64) ||
        throw(OverflowError("rational_to_dyadic: exponent $Q exceeds Int64"))
    Dyadic(Int128(s), Int64(Q))
end

"""
    Rational{T}(x::Dyadic) -> Rational{T}

The **exact** value as a rational.

`BigInt` is the default because it is the only target that cannot fail: `Q`
reaches ±32 768 at `Binary16p1uf`, so `2^-Q` needs ~32 768 bits. A narrow `T` is
accepted and **checked** — it throws `OverflowError` naming the side that did not
fit, rather than wrapping.

Non-finite rows follow **Base**, which is the correction this function carries:
`Rational` does represent infinities, so `+Inf` is `1//0` and `-Inf` is `-1//0`,
exactly as `Rational{BigInt}(Inf)` gives. Only NaN has no rational slot (`0//0`
is rejected by Base too) and throws. The predecessor threw on all three, from the
untested premise that "a rational cannot represent infinity".

The reduction is a **shift, not a gcd**. `Rational`'s invariant wants
`gcd(num, den) == 1`; here `den` is a power of two, so the common factor is
`2^min(trailing_zeros(S), -Q)` and one instruction establishes the invariant that
Euclid's algorithm would have found. `unsafe_rational` is then safe in the strict
sense — the invariant is established, not skipped.

See also [`rational_to_dyadic`](@ref), [`isdyadic`](@ref)."""
Base.Rational{T}(x::Dyadic) where {T<:Integer} = dyadic_to_rational(T, x)
Dyadic(q::Rational) = rational_to_dyadic(q)
Base.Float32(x::Dyadic) = _dyadic_to(Float32, x)
Base.Float16(x::Dyadic) = _dyadic_to(Float16, x)

"""Exact conversion from a binary float. Returns the NaN/±Inf rows unchanged;
finite values decompose exactly because every binary float IS a dyadic rational.

`Base.decompose` returns `(num, pow, den)` with **the sign in the denominator**
and a carrier-specific exponent for zero — the trap gate G6 recorded (§11). Both
are handled here rather than at the call sites."""
# Idempotent: a `Dyadic` is already what `dyadic_from` produces. Without this row
# the function is total over the *float* carriers but not over `CarrierValue`,
# and rung 3 hands callers a `Dyadic` — so any generic "put this datum in the
# exact form" call has a hole at exactly the rung the carrier was built for.
dyadic_from(x::Dyadic) = x

function dyadic_from(x::AbstractFloat)
    isnan(x) && return DYADIC_NAN
    isinf(x) && return x > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    iszero(x) && return DYADIC_ZERO
    num, pow, den = Base.decompose(x)
    # `den` is ±1 for every binary float; its SIGN is the value's sign.
    n = BigInt(num) * sign(den)
    # NORMALIZE. `decompose(::BigFloat)` returns the numerator at the value's full
    # allocated precision, trailing zeros included — a 16-bit datum decoded at an
    # ambient 256 bits comes back as a 256-bit integer, which does not fit Int128
    # even though the value needs 16 bits. Those zeros are exponent, not
    # significand, so moving them into `pow` is exact and is what makes the
    # conversion total over every value the engine forms.
    tz = trailing_zeros(n)
    if tz > 0
        n >>= tz
        pow += tz
    end
    _fits_int128(n) || throw(InexactError(:Dyadic, Dyadic,
        "significand needs $(ndigits(n; base=2)) bits after normalization, " *
        "which exceeds Int128; Dyadic is the carrier for P3109 datums (≤ 16 " *
        "significand bits) and their exact combinations, not for arbitrary reals"))
    Dyadic(DY_FINITE, Int128(n), Int64(pow))
end
@inline _fits_int128(n::BigInt) = ndigits(n; base=2) <= 127
Dyadic(x::AbstractFloat) = dyadic_from(x)
Dyadic(x::Integer) = Dyadic(Int128(x), Int64(0))

Base.show(io::IO, x::Dyadic) =
    x.kind == DY_NAN    ? print(io, "Dyadic(NaN)") :
    x.kind == DY_POSINF ? print(io, "Dyadic(Inf)") :
    x.kind == DY_NEGINF ? print(io, "Dyadic(-Inf)") :
    print(io, "Dyadic(", x.S, " * 2^", x.Q, ")")

end # module DyadicNumbers
