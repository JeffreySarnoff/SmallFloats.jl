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
    Dyadic(S::Int128, Q::Int64)          -> the exact value S · 2^Q
    Dyadic(kind::UInt8)                  -> one of the three non-finite rows
    Dyadic(S::Int128, Q::Int64, kind)    -> the inner constructor

An exact dyadic rational, the rung-3 evaluation carrier.

`S` is a *signed* significand and is deliberately not normalized: normalizing
after every operation costs a `trailing_zeros` and a shift for no benefit, since
the only consumer is `round_to_precision`, which realigns anyway. Two `Dyadic`s
may therefore represent the same value with different `(S, Q)`; `==` compares
values, not fields.

**`kind` is the LAST field, and the order is load-bearing.** `S` needs 16-byte
alignment, so a leading `UInt8` tag buys 15 bytes of padding and a 40-byte
struct; trailing, the tag lands in `Q`'s slack and the struct is 32 bytes. That
is a quarter off every carrier value the rung-3 path copies, and it costs
nothing. Anything constructing a `Dyadic` positionally passes `(S, Q, kind)` —
the two-argument spellings above exist so that most code never has to.
"""
struct Dyadic <: Real
    S::Int128
    Q::Int64
    kind::UInt8
end
Dyadic(S::Integer, Q::Integer) = Dyadic(Int128(S), Int64(Q), DY_FINITE)

# The tag is RANGE-CHECKED. `Dyadic(0x7f)` used to construct, and the result was
# in none of the four rows: `isfinite`, `isnan` and `isinf` all answered false,
# so every kernel's classification fell through to a branch written for a case
# that cannot occur. This is the representation invariant for the tag field, and
# invariant 3's rule applies — constructors check it, kernels assume it. The
# check is free: this constructor runs five times, at load, for the `const` rows.
function Dyadic(kind::UInt8)
    kind <= DY_NAN || throw(ArgumentError(
        "invalid Dyadic kind $kind: expected one of DY_FINITE, DY_POSINF, " *
        "DY_NEGINF, DY_NAN (0x00 through 0x03)"))
    Dyadic(Int128(0), Int64(0), kind)
end

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

"""Whether both operands are finite, in one OR and one compare.

Sound only because `DY_FINITE == 0x00`. This gates the addition kernels; whether
it is *worth* gating with depends on what the cold rows cost to inline beside the
hot body, which is measured per site — see the note above `_add_special`."""
@inline bothfinite_dy(x::Dyadic, y::Dyadic) = (x.kind | y.kind) == DY_FINITE

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
    # Finite first: `cmp_dy` calls this twice per comparison and the finite row is
    # the overwhelming case, so it costs one predicate rather than three.
    isfinite_dy(x) && return x.S > 0 ? 1 : (x.S < 0 ? -1 : 0)
    x.kind == DY_POSINF && return 1
    x.kind == DY_NEGINF && return -1
    0                                                  # NaN
end
"""Sign as an `Int` in `{-1, 0, 1}`; `NaN` answers 0, matching no float and
deliberately so — callers must test `isnan` first, and a sign of 0 for NaN makes
a missing test show up as a wrong answer rather than as a plausible one."""
Base.sign(x::Dyadic) = sign_dy(x)
Base.signbit(x::Dyadic) = sign_dy(x) < 0

# `typemin(Int128)` is the one significand that cannot be negated in place:
# `-typemin` and `abs(typemin)` both wrap to `typemin`, so `abs` returned a
# NEGATIVE value and `abs(x) > 0` was false. Silent, and it propagates —
# `Base.:-(x, y)` is `x + (-y)`.
#
# The carrier has the room the integer does not: `|typemin(Int128)|` is exactly
# `2^127`, so the value is respelled as `1 · 2^(Q+127)`. Exact, not a saturation.
# `@noinline` because this is one input out of 2^128 and the callers are hot.
@noinline function _negate_typemin(Q::Int64)
    Q <= typemax(Int64) - 127 || throw(OverflowError(
        "Dyadic: negating a typemin(Int128) significand needs exponent " *
        "$Q + 127, which exceeds Int64"))
    Dyadic(one(Int128), Q + 127, DY_FINITE)
end

@inline function Base.abs(x::Dyadic)
    if isfinite_dy(x)
        s = x.S
        s >= 0 && return x
        s == typemin(Int128) && return _negate_typemin(x.Q)
        return Dyadic(-s, x.Q, DY_FINITE)
    end
    x.kind == DY_NEGINF ? DYADIC_POSINF : x
end
@inline function Base.:-(x::Dyadic)
    if isfinite_dy(x)
        s = x.S
        s == typemin(Int128) && return _negate_typemin(x.Q)
        return Dyadic(-s, x.Q, DY_FINITE)
    end
    x.kind == DY_POSINF && return DYADIC_NEGINF
    x.kind == DY_NEGINF && return DYADIC_POSINF
    x
end

"""`|S|` as a `UInt128`.

`abs(typemin(Int128))` wraps to itself; reading those bits as unsigned gives
`2^127`, which is the true magnitude. That is why the magnitude of a significand
is taken here rather than with a bare `abs` — `typemin` is a representable `S`,
and `abs` alone is wrong on exactly that one input."""
@inline mag_dy(S::Int128) = unsigned(abs(S))

"""Number of significant bits in `|S|` — the head width the add band is stated
against. Zero answers 0, since `leading_zeros(zero(UInt128))` is 128."""
@inline nbits_dy(S::Int128) = 128 - leading_zeros(mag_dy(S))

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
    bothfinite_dy(x, y) || return _add_special(x, y)
    iszero(x.S) && return y
    iszero(y.S) && return x
    if x.Q >= y.Q
        d = x.Q - y.Q
        d > DYADIC_ALIGN_MAX && return _add_wide(x, y, d)
        return _add_aligned(x, y, d)
    else
        d = y.Q - x.Q
        d > DYADIC_ALIGN_MAX && return _add_wide(y, x, d)
        return _add_aligned(y, x, d)
    end
end

# MEASUREMENT HISTORY, and the reason the shape above is not obvious.
#
# The `(x.kind | y.kind) == DY_FINITE` gate is sound only because `DY_FINITE` is
# zero, and its worth depends entirely on whether `_add_special` may be inlined:
#
#   gate + inlinable `_add_special`        5.96 us   <- this
#   inline predicate chain, no helper      7.51 us   +26%
#   gate + `@noinline _add_special`        7.13 us   +20%
#
# 4096-element reduction loop, minimum of 4000 reps over six alternating
# single-variant processes. An earlier note here recorded the gate as "31%
# slower" and rejected it — that measurement was real but its conclusion was
# conditional on the `@noinline` it was paired with, which the note did not say.
# Pairing the gate with an inlinable helper reverses it. A call in the hot block
# cannot be if-converted, so the finite path pays for cold rows it never takes;
# this helper is four tag compares returning an operand, so inlining it is nearly
# free and removes that barrier.
#
# The same change at `_cmp_special` would be governed by the size of the body it
# sits beside, not by the helper — do not generalize this to `cmp_dy` without
# measuring it there.
#
# Before that, the gate was "confirmed" at 1.87x by a harness that compiled every
# variant in one process. Same-process variant comparison is not a measurement
# here: one variant per process, alternating, or nothing.
@inline function _add_special(x::Dyadic, y::Dyadic)
    kx, ky = x.kind, y.kind
    (kx == DY_NAN) | (ky == DY_NAN) && return DYADIC_NAN
    kx == DY_FINITE && return y                    # y is the infinity
    ky == DY_FINITE && return x                    # x is the infinity
    kx == ky ? x : DYADIC_NAN                      # ∞ + (−∞)
end

# The aligned exact sum, shared by `add_dy` and `add_sticky_dy` so the one
# expression that has to stay inside the C7 band is written once. Both callers
# arrive having discharged the NaN/∞/zero rows and having checked `d` against
# `DYADIC_ALIGN_MAX`, which is why this takes the ordered pair and the gap rather
# than re-deriving them: `add_sticky_dy` is the ω-arithmetic hot path and must
# not re-enter `add_dy` to re-run the tests it has already answered.
#
# `big`/`small` are ordered by EXPONENT, not magnitude — the small operand is the
# one whose bits fall off the bottom after alignment.
@inline _add_aligned(big::Dyadic, small::Dyadic, d::Integer) =
    Dyadic((big.S << d) + small.S, small.Q, DY_FINITE)

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

@noinline _throw_add_wide(nb::Int, d::Int) = throw(ArgumentError(
    "Dyadic add would overflow Int128: the larger operand carries $nb " *
    "significand bits and the alignment shift is $d, totalling $(nb + d) > 126. " *
    "`DYADIC_ALIGN_MAX = $DYADIC_ALIGN_MAX` is derived from a head of at most " *
    "`DYADIC_HEAD_BITS = $DYADIC_HEAD_BITS` bits, which every operand the engine " *
    "forms satisfies — a datum's significand is ≤ 16 bits and `mul_dy` of two is " *
    "≤ 32"))

"""
    add_dy_checked(x, y) -> Dyadic

[`add_dy`](@ref) with its width precondition enforced: throws `ArgumentError`
rather than wrapping when the aligned significand would leave `Int128`.

`add_dy` is **unchecked**, exactly as [`mul_dy`](@ref) is, and for the same
reason: `DYADIC_ALIGN_MAX = 127 − DYADIC_HEAD_BITS − 1` is derived from a head
of at most 32 significand bits, which every operand the engine forms satisfies
by construction (a datum carries ≤ 16 bits, so a `mul_dy` product carries ≤ 32).
Inside the engine the check is dead weight on the rung-3 hot path.

It is a *separate function* rather than a `@boundscheck` block, and that is the
lesson `mul_dy`'s docstring records at length: `@boundscheck` elides only under
an `@inbounds` caller, and no call site in `oracle.jl` is one — so the guard ran
in production at 3.3× the cost of the operation it guarded. Two names put the
contract at the call site instead of in an annotation nobody wrote.
"""
@inline function add_dy_checked(x::Dyadic, y::Dyadic)
    bothfinite_dy(x, y) || return _add_special(x, y)
    iszero(x.S) && return y
    iszero(y.S) && return x
    # ordered by EXPONENT, not magnitude, matching `_add_aligned`'s contract.
    # Named `hi`/`lo` rather than `big`/`small`: `big` is `Base.big`, which this
    # module defines a method for.
    hi, lo, d = x.Q >= y.Q ? (x, y, Int(x.Q - y.Q)) : (y, x, Int(y.Q - x.Q))
    d > DYADIC_ALIGN_MAX && return _add_wide(hi, lo, d)
    nb = nbits_dy(hi.S)
    nb + d <= 126 || _throw_add_wide(nb, d)
    _add_aligned(hi, lo, d)
end

"""
    add_sticky_dy(x, y) -> (Dyadic, Int)

The sum together with a sticky sign in `{-1, 0, +1}` describing a tail below the
returned value's last bit. Chooses the exact band when the operands align and the
sign-only band otherwise, which is exactly the C7 overlap argument in code."""
@inline function add_sticky_dy(x::Dyadic, y::Dyadic)
    # A special row has no tail below its last bit, so the sticky sign is 0.
    bothfinite_dy(x, y) || return (_add_special(x, y), 0)
    iszero(x.S) && return (y, 0)
    iszero(y.S) && return (x, 0)
    if x.Q >= y.Q
        d = x.Q - y.Q
        d <= DYADIC_ALIGN_MAX && return (_add_aligned(x, y, d), 0)
        return (x, y.S > 0 ? 1 : -1)
    else
        d = y.Q - x.Q
        d <= DYADIC_ALIGN_MAX && return (_add_aligned(y, x, d), 0)
        return (y, x.S > 0 ? 1 : -1)
    end
end

"""
    mul_dy(x, y) -> Dyadic

Exact product, **unchecked**. Precondition: `nbits(x.S) + nbits(y.S) ≤ 96`, which
every operand the engine produces satisfies by a wide margin — a datum's
significand is ≤ 16 bits, so a product of four is ≤ 64.

Use [`mul_dy_checked`](@ref) at any boundary where that precondition is not
already established. That is a *separate function*, not a `@boundscheck` block,
and the difference is not stylistic: `@boundscheck` elides only when the caller
is `@inbounds`, and **no call site in `oracle.jl` is** — `grep -n inbounds
src/oracle.jl` returns nothing. The check therefore ran on every rung-3
multiply in production, two `nbits_dy` calls deep, at **3.3×** the cost of the
multiply itself (5.166 vs 1.546 µs over 4096 pairs). The previous docstring's
claim that it was "pure overhead on the path that matters" had it exactly
backwards: it was overhead *on* that path, and free everywhere else.

Making the two paths two names means the contract is visible at the call site
instead of depending on an `@inbounds` annotation nobody wrote."""
@inline function mul_dy(x::Dyadic, y::Dyadic)
    (isnan_dy(x) | isnan_dy(y)) && return DYADIC_NAN
    if isinf_dy(x) || isinf_dy(y)
        (iszero_dy(x) | iszero_dy(y)) && return DYADIC_NAN          # 0 · ∞
        return sign_dy(x) * sign_dy(y) > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    end
    Dyadic(x.S * y.S, x.Q + y.Q, DY_FINITE)
end

@noinline _throw_mul_wide(nx::Int, ny::Int) = throw(ArgumentError(
    "Dyadic multiply would overflow Int128: $nx + $ny significand bits > 96"))

"""
    mul_dy_checked(x, y) -> Dyadic

[`mul_dy`](@ref) with its precondition enforced: throws `ArgumentError` rather
than wrapping when the significand product would leave `Int128`. For tests and
for any caller that has not established the width invariant itself."""
@inline function mul_dy_checked(x::Dyadic, y::Dyadic)
    (isnan_dy(x) | isnan_dy(y)) && return DYADIC_NAN
    if isinf_dy(x) || isinf_dy(y)
        (iszero_dy(x) | iszero_dy(y)) && return DYADIC_NAN
        return sign_dy(x) * sign_dy(y) > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    end
    nx, ny = nbits_dy(x.S), nbits_dy(y.S)
    nx + ny <= 96 || _throw_mul_wide(nx, ny)
    Dyadic(x.S * y.S, x.Q + y.Q, DY_FINITE)
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
    # `_exponent_raw`, not `exponent_dy`: finite and nonzero is established above,
    # so the checked form would re-test it on both operands every comparison.
    ex, ey = _exponent_raw(x), _exponent_raw(y)
    if ex != ey
        m = ex < ey ? -1 : 1
        return sx > 0 ? m : -m
    end
    # Equal exponents, so the widths differ by exactly `ΔQ` and the shift lands
    # inside 128 bits. UInt128 magnitudes, because `abs(typemin(Int128))` is
    # negative and would order that significand as the smallest rather than the
    # largest — see `mag_dy`.
    ax, ay = mag_dy(x.S), mag_dy(y.S)
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
# `<= 0` covers -1 and 0 and excludes the unordered 2, which is the only other
# value `cmp_dy` returns.
Base.:(<=)(x::Dyadic, y::Dyadic) = cmp_dy(x, y) <= 0

# ---- `isless` and `isequal`: the SORTING order, which is NOT the `<` order.
#
# Base's `Real` fallbacks are `isless(x, y) = x < y` and `isequal(x, y) = x == y`,
# and a type with a NaN row cannot accept either. `<` answers false in both
# directions for NaN, so `sort` is handed a non-order and shuffles rather than
# sorts: `[2, NaN, -Inf, 0, Inf]` came back in that order, unchanged and unsorted,
# where the `Float64` spelling gives `[-Inf, 0.0, 2.0, Inf, NaN]`. `sort`,
# `extrema`, `searchsorted`, `partialsort` and `maximum` all assume `isless` is a
# TOTAL order, which for every `AbstractFloat` means NaN sorts last.
#
# `cmp_dy`'s unordered answer is what makes both one line: 2 occurs exactly when a
# NaN is involved, and NaN is greater than everything except another NaN.
@inline function Base.isless(x::Dyadic, y::Dyadic)
    c = cmp_dy(x, y)
    c == 2 ? (!isnan_dy(x) & isnan_dy(y)) : c == -1
end

# `isequal` follows Base's contract — "the same as `==` except that NaN is equal
# to itself". There is no signed zero in this carrier, so the other half of that
# contract has nothing to say here.
#
# `Set` and `Dict` already answer correctly WITHOUT this method, which is why the
# gap is easy to miss: `Dyadic` is immutable and every NaN row is bit-identical,
# so the hash table's `===` short-circuit covers it. That is a property of the
# layout, not of the comparison — `unique`, `indexin`, `findfirst` and any direct
# `isequal` call read the false answer.
@inline Base.isequal(x::Dyadic, y::Dyadic) =
    isnan_dy(x) ? isnan_dy(y) : cmp_dy(x, y) == 0

# `isunordered` is the third member of that contract and the one easiest to miss,
# because Base's default is `false` for every type rather than an error. It is
# what `isgreater` is built on, and through it `argmin`/`argmax`, `findmin`/
# `findmax` and descending sorts — all of which placed a `Dyadic` NaN as an
# ordinary value while the `Float64` spelling places it last.
@inline Base.isunordered(x::Dyadic) = isnan_dy(x)

# `max`/`min`/`minmax` PROPAGATE NaN, as they do for every `AbstractFloat`.
# Base's `Real` fallback is `ifelse(isless(y, x), x, y)`, which returns the
# non-NaN operand — so `maximum`, `minimum` and `extrema` over a vector holding a
# NaN answered a finite value where the same reduction over `Float64` answers NaN.
# A carrier that disagrees with the float on a reduction is the disagreement gate
# G7 exists to catch, so it is settled here rather than left to the call sites.
#
# Note this is Julia's `max`, not IEEE `maxNum`: the registry's `Max`/`Min` ops
# carry the P3109 semantics and are unaffected by these methods.
@inline Base.max(x::Dyadic, y::Dyadic) =
    (isnan_dy(x) | isnan_dy(y)) ? DYADIC_NAN : (cmp_dy(x, y) == -1 ? y : x)
@inline Base.min(x::Dyadic, y::Dyadic) =
    (isnan_dy(x) | isnan_dy(y)) ? DYADIC_NAN : (cmp_dy(x, y) == 1 ? y : x)
@inline Base.minmax(x::Dyadic, y::Dyadic) =
    (isnan_dy(x) | isnan_dy(y)) ? (DYADIC_NAN, DYADIC_NAN) :
        (cmp_dy(x, y) == 1 ? (y, x) : (x, y))
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
    Dyadic(x.S, x.Q + Int64(n), DY_FINITE)
end

# The exponent arithmetic without the domain test, for callers that have already
# established finite-and-nonzero. `cmp_dy` is the one that matters: it reaches
# this twice per comparison, on operands it has just classified.
@inline _exponent_raw(x::Dyadic) = x.Q + nbits_dy(x.S) - 1

"""Binary exponent of `|x|`, i.e. `⌊log₂|x|⌋`. Undefined for zero and the
non-finite rows, which is why it asserts rather than returning a sentinel."""
@inline function exponent_dy(x::Dyadic)
    isfinite_dy(x) && !iszero(x.S) ||
        throw(DomainError(x, "Dyadic exponent is defined only for finite nonzero values"))
    _exponent_raw(x)
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
# `Q ≥ 0` returns the OPERAND, and does not re-form it at `Q = 0`. The value is
# already an integer, so all four functions are the identity there; re-forming it
# as `S << Q` was wrong twice over — `Int128` shifts yield 0 past the width, so
# `floor(Dyadic(1, 200))` answered 0, and there is no `(S′, 0)` for `2^200` to be
# re-formed into in the first place. That guard is spelled out at each of the four
# entry points rather than hidden in `_split_dy`, so `_split_dy` gets a clean
# precondition and its result needs no per-caller reinterpretation.
#
# `-Q ≥ 128` likewise cannot be a shift: the whole significand is below the binary
# point, so `0 < |x| < 2^-1`, and neither the fraction's numerator nor `2^sh` is
# an `Int128`. `_DY_TINY` reports that case with the floor still exact — `-1` for
# a negative value, not `0`. The previous encoding returned `(0, S, sh)`, which
# claims a floor of 0 and a remainder that is negative for negative `x`: it made
# `floor` of a tiny negative answer 0 instead of -1, and `ceil` answer 1 instead
# of 0.
const _DY_TINY = -1

"""Split a finite NON-INTEGER `x` as `x == q + r/2^sh` with `q == ⌊x⌋` and
`0 ≤ r < 2^sh`. **Precondition: `x.Q < 0` and `x.S ≠ 0`.**

`sh == _DY_TINY` means `0 < |x| < 2^-1`, where the fraction is not an `Int128`
ratio: `q` is then the exact floor and `r` is a nonzero placeholder, which is all
`floor`/`ceil`/`trunc` read. `round` is the one caller that compares against ½
and it tests the tag."""
@inline function _split_dy(x::Dyadic)
    # Test the ORIGINAL `Q`, before negating it. `-Int(typemin(Int64))` wraps to
    # `typemin` — still negative — so `sh >= 128` was false and `x.S >> sh` became
    # a *left* shift on a negative count. `Dyadic(-3, typemin(Int64))` answered
    # `floor = 0` (should be −1), `ceil = 1` and `trunc = 1` (both should be 0).
    x.Q <= -128 && return (x.S < 0 ? -one(Int128) : zero(Int128), one(Int128), _DY_TINY)
    sh = -Int(x.Q)                                         # now in 1:127
    q = x.S >> sh                                          # arithmetic shift: floors
    (q, x.S - (q << sh), sh)                               # (floor, remainder ≥ 0, shift)
end

@inline _int_dy(q::Int128) = Dyadic(q, 0, DY_FINITE)

# Non-finite, or already an integer — the operand IS the answer. `iszero` belongs
# here and not in `_split_dy`: `(0, -400)` is a perfectly ordinary spelling of
# zero, and the `_DY_TINY` row would report a nonzero fraction for it, which made
# `ceil` answer 1.
@inline _rounds_to_self(x::Dyadic) = !isfinite_dy(x) || x.Q >= 0 || iszero(x.S)

function Base.floor(x::Dyadic)
    _rounds_to_self(x) && return x
    q, _, _ = _split_dy(x)
    _int_dy(q)                       # `>>` already floors toward −∞
end

function Base.ceil(x::Dyadic)
    _rounds_to_self(x) && return x
    q, r, _ = _split_dy(x)
    _int_dy(iszero(r) ? q : q + one(Int128))
end

# One split, rather than a dispatch into `ceil`/`floor` that repeats it: toward
# zero differs from toward −∞ only for a negative value with a fraction, and both
# facts are already in hand.
function Base.trunc(x::Dyadic)
    _rounds_to_self(x) && return x
    q, r, _ = _split_dy(x)
    _int_dy((x.S < 0) & !iszero(r) ? q + one(Int128) : q)
end

"""Round half to even, matching `Base.round(::AbstractFloat)`."""
function Base.round(x::Dyadic)
    _rounds_to_self(x) && return x
    q, r, sh = _split_dy(x)
    # `0 < |x| < ½`: nearest is zero from either side, and no tie is possible.
    sh == _DY_TINY && return DYADIC_ZERO
    iszero(r) && return _int_dy(q)
    # Compare the fraction against ½ as `r` vs `2^(sh-1)`, NOT as `2r` vs `2^sh`:
    # `r` reaches `2^sh - 1`, so at `sh = 127` the doubling wraps and the tie test
    # reads the wrong side. `sh ≥ 1` holds because `x.Q < 0`.
    half = one(Int128) << (sh - 1)
    up = r > half || (r == half && !iseven(q))                 # tie → even
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
# The wide route is through `BigFloat`, which is exact, so the narrowing is a
# **single** rounding. A direct `ldexp(Float64(x.S), x.Q)` is a *double* rounding
# whenever `|S| > 2^53` — reachable after a multiply, since `mul_dy` permits 96
# significand bits — and double rounding can land a tie on the wrong side. Rare,
# silent, and exactly the class of defect this carrier exists to remove.
#
# The fast path is taken only where NO rounding occurs on either route: the
# significand fits `T`'s precision, so `T(S)` is exact, and the value's binade is
# a normal one for `T`, so `ldexp` is a pure exponent-field add. `x` is then
# exactly representable and both routes return it unchanged — the fast path buys
# the MPFR allocation back without weakening anything.
#
# The normal-binade half of that guard is not decoration. `Base.ldexp` is NOT
# correctly rounded at the underflow boundary: it flushes to zero as soon as the
# scaled exponent passes `-significand_bits(T)`, so `ldexp(3.0, -1076)` — the
# value ¾ ulp above zero, which rounds to the smallest subnormal — answers `0.0`.
# Measured, not assumed; a fast path guarded only on the significand width was
# wrong on exactly that band, and the sweep in the suite is what said so.
#
# The common case is still the fast one by a wide margin: a datum carries ≤ 16
# significand bits, and this is the boundary every decoded value crosses.
function _dyadic_to(::Type{T}, x::Dyadic) where {T<:AbstractFloat}
    x.kind == DY_NAN    && return T(NaN)
    x.kind == DY_POSINF && return T(Inf)
    x.kind == DY_NEGINF && return T(-Inf)
    iszero(x.S) && return zero(T)
    _exact_in(T, x) && return ldexp(T(x.S), x.Q)
    T(BigFloat(x))
end

# Whether `x` is a value `T` holds exactly. Both bounds fold to constants for a
# concrete `T`; `BigFloat` is not a caller (it has its own method) and would read
# the ambient precision here.
@inline function _exact_in(::Type{T}, x::Dyadic) where {T<:AbstractFloat}
    nb = nbits_dy(x.S)                       # once: `_exponent_raw` would repeat it
    nb <= Base.precision(T) || return false
    e = x.Q + nb - 1
    Base.exponent(floatmin(T)) <= e <= Base.exponent(floatmax(T))
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

"""
Fit a `BigInt` into `T`, or say which side overflowed and by how much.

Two-sided bounds, not `abs(n) <= typemax(T)`: `abs(typemin(Int128))` wraps to
itself, so the `abs` form is wrong on exactly one input — and that input is a
legitimate significand.
"""
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
    # `-one(T)` WRAPS for an unsigned `T`, and the wrap is not detectable
    # afterwards: `dyadic_to_rational(UInt64, -Inf)` built
    # `0xffffffffffffffff//0x0`, a numerator of 1.8e19 over a zero denominator,
    # which every consumer reads as **+Inf**. A sign that the target cannot hold
    # has to be refused, not silently reinterpreted.
    x.kind == DY_NEGINF && return (T <: Unsigned || T === Bool) ?
        throw(InexactError(:dyadic_to_rational, Rational{T}, x)) :
        Base.unsafe_rational(-one(T), zero(T))
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

`±1//0` map to the infinities. `0//0` cannot arise through `//` — Base rejects it
at construction — but `unsafe_rational(0, 0)` builds it, and it throws
`InexactError` here rather than falling through the sign test to `-Inf`.

The algorithm never assumes `q` is reduced — the power-of-two test and the
trailing-zero strip are correct on a hand-built `unsafe_rational(2, 4)` — which
removes a premise rather than relying on one."""
function rational_to_dyadic(q::Rational)
    n, d = numerator(q), denominator(q)
    # `0//0` is unreachable through `//`, which is what the note below records —
    # but it IS reachable through `unsafe_rational`, and this function already
    # declines to assume `q` is reduced. Untested, it fell through the `n > 0`
    # test and answered `-Inf` for a value that has no sign at all.
    if iszero(d)
        iszero(n) && throw(InexactError(:rational_to_dyadic, Dyadic, q))
        return n > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    end
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

# `Float16`/`Float32`/`Float64` need no `BigInt` at all: `decompose` hands back a
# machine integer that fits `Int128` outright, so the generic route's arbitrary
# precision buys nothing and costs an allocation on every decoded value. The
# normalization below is the same one, done in `Int128`.
function dyadic_from(x::Base.IEEEFloat)
    isnan(x) && return DYADIC_NAN
    isinf(x) && return x > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    iszero(x) && return DYADIC_ZERO
    num, pow, den = Base.decompose(x)
    n = Int128(num) * sign(den)             # `den` is ±1; its SIGN is the value's
    tz = trailing_zeros(n)                  # `n ≠ 0`, so this terminates
    Dyadic(n >> tz, Int64(pow) + tz, DY_FINITE)
end

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
    Dyadic(Int128(n), Int64(pow), DY_FINITE)
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
