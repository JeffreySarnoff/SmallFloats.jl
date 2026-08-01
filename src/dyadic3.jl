# ===== Dyadic3.jl
# Performance-oriented exact dyadic carrier for Julia 1.12+.
#
# Design priorities:
#   1. Keep the 32-byte isbits layout: Int128, Int64, UInt8.
#   2. Make the overwhelmingly common finite path one tag test.
#   3. Keep non-finite algebra and exception construction out of line.
#   4. Distinguish unchecked engine kernels from checked entry points.
#   5. Keep exact conversions exact; allocation is confined to BigFloat/BigInt paths.

module DyadicNumbers

export Dyadic, DY_FINITE, DY_POSINF, DY_NEGINF, DY_NAN,
       dyadic_to_rational, rational_to_dyadic, isdyadic

const DY_FINITE = UInt8(0x00)
const DY_POSINF = UInt8(0x01)
const DY_NEGINF = UInt8(0x02)
const DY_NAN    = UInt8(0x03)

"""
    Dyadic(S::Integer, Q::Integer)
    Dyadic(kind::UInt8)

The exact value `S * 2^Q`, or one of the three non-finite rows.

`S` is deliberately not normalized. Equal values may therefore have different
field representations; comparison is by value.
"""
struct Dyadic <: Real
    # Descending alignment keeps this isbits value at 32 bytes on supported
    # 64-bit Julia 1.12 targets. `kind` occupies otherwise unused tail padding.
    S::Int128
    Q::Int64
    kind::UInt8
end

@inline _finite(S::Int128, Q::Int64) = Dyadic(S, Q, DY_FINITE)
@inline _special(kind::UInt8) = Dyadic(Int128(0), Int64(0), kind)

Dyadic(S::Integer, Q::Integer) = _finite(Int128(S), Int64(Q))
function Dyadic(kind::UInt8)
    kind <= DY_NAN || throw(ArgumentError("invalid Dyadic kind: $kind"))
    _special(kind)
end

const DYADIC_ZERO   = _finite(Int128(0), Int64(0))
const DYADIC_ONE    = _finite(Int128(1), Int64(0))
const DYADIC_POSINF = _special(DY_POSINF)
const DYADIC_NEGINF = _special(DY_NEGINF)
const DYADIC_NAN    = _special(DY_NAN)

# -----------------------------------------------------------------------------
# Classification and small integer helpers
# -----------------------------------------------------------------------------

@inline isfinite_dy(x::Dyadic) = x.kind == DY_FINITE
@inline isnan_dy(x::Dyadic)    = x.kind == DY_NAN
@inline isinf_dy(x::Dyadic)    = x.kind == DY_POSINF || x.kind == DY_NEGINF
@inline iszero_dy(x::Dyadic)   = x.kind == DY_FINITE && iszero(x.S)
@inline _both_finite(x::Dyadic, y::Dyadic) = (x.kind | y.kind) == DY_FINITE

Base.isfinite(x::Dyadic) = isfinite_dy(x)
Base.isnan(x::Dyadic)    = isnan_dy(x)
Base.isinf(x::Dyadic)    = isinf_dy(x)
Base.iszero(x::Dyadic)   = iszero_dy(x)
Base.zero(::Type{Dyadic}) = DYADIC_ZERO
Base.zero(::Dyadic)       = DYADIC_ZERO
Base.one(::Type{Dyadic})  = DYADIC_ONE
Base.one(::Dyadic)        = DYADIC_ONE

"""Sign in `{-1, 0, 1}`. NaN returns zero; callers must classify NaN first."""
@inline function sign_dy(x::Dyadic)
    if isfinite_dy(x)
        s = x.S
        return s > 0 ? 1 : (s < 0 ? -1 : 0)
    end
    x.kind == DY_POSINF && return 1
    x.kind == DY_NEGINF && return -1
    return 0
end

Base.sign(x::Dyadic) = sign_dy(x)
Base.signbit(x::Dyadic) = sign_dy(x) < 0

"""Unsigned magnitude, including the exact magnitude of `typemin(Int128)`."""
@inline mag_dy(S::Int128) = unsigned(abs(S))

"""Number of significant bits in `abs(S)`; zero has width zero."""
@inline nbits_dy(S::Int128) = 128 - leading_zeros(mag_dy(S))

@noinline function _positive_typemin(Q::Int64)
    Q <= typemax(Int64) - 127 ||
        throw(OverflowError("Dyadic exponent overflow while representing abs/negate of typemin(Int128)"))
    _finite(one(Int128), Q + 127)
end

@inline function Base.abs(x::Dyadic)
    if isfinite_dy(x)
        s = x.S
        s >= 0 && return x
        s == typemin(Int128) && return _positive_typemin(x.Q)
        return _finite(-s, x.Q)
    end
    x.kind == DY_NEGINF ? DYADIC_POSINF : x
end

@inline function Base.:-(x::Dyadic)
    if isfinite_dy(x)
        s = x.S
        s == typemin(Int128) && return _positive_typemin(x.Q)
        return _finite(-s, x.Q)
    end
    x.kind == DY_POSINF && return DYADIC_NEGINF
    x.kind == DY_NEGINF && return DYADIC_POSINF
    return x
end

# -----------------------------------------------------------------------------
# Exact/sticky engine kernels
# -----------------------------------------------------------------------------

const DYADIC_HEAD_BITS    = 32
const DYADIC_ALIGN_MAX    = 127 - DYADIC_HEAD_BITS - 1  # 94
const DYADIC_ADD_COVERAGE = 92                           # require P + N <= 92

@noinline function _throw_add_wide(d::Int64)
    throw(ArgumentError(
        "Dyadic add with delta-Q = $d exceeds DYADIC_ALIGN_MAX = " *
        "$DYADIC_ALIGN_MAX; use add_sticky_dy after establishing its sticky threshold"))
end

@inline function _add_aligned_xy(x::Dyadic, y::Dyadic, d::Int64)
    # Precondition: x.Q >= y.Q, d == x.Q-y.Q, d <= DYADIC_ALIGN_MAX,
    # and the engine head-width invariant holds.
    _finite((x.S << Int(d)) + y.S, y.Q)
end

@noinline function _add_special(x::Dyadic, y::Dyadic)
    kx, ky = x.kind, y.kind
    (kx == DY_NAN || ky == DY_NAN) && return DYADIC_NAN
    kx == DY_FINITE && return y
    ky == DY_FINITE && return x
    return kx == ky ? x : DYADIC_NAN
end

"""
    add_dy(x, y) -> Dyadic

Exact engine sum inside the alignment band. Outside the band it throws, because
the caller must use `add_sticky_dy` after establishing the C7 coverage invariant.
"""
@inline function add_dy(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return _add_special(x, y)

    sx, sy = x.S, y.S
    iszero(sx) && return y
    iszero(sy) && return x

    if x.Q >= y.Q
        d = x.Q - y.Q
        d <= DYADIC_ALIGN_MAX || return _throw_add_wide(d)
        return _add_aligned_xy(x, y, d)
    else
        d = y.Q - x.Q
        d <= DYADIC_ALIGN_MAX || return _throw_add_wide(d)
        return _add_aligned_xy(y, x, d)
    end
end

"""
    add_sticky_dy(x, y) -> (head::Dyadic, sticky_sign::Int)

Returns an exact aligned sum inside the alignment band. Beyond it, returns the
larger-exponent operand plus the sign of the discarded tail.
"""
@inline function add_sticky_dy(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return (_add_special(x, y), 0)

    sx, sy = x.S, y.S
    iszero(sx) && return (y, 0)
    iszero(sy) && return (x, 0)

    if x.Q >= y.Q
        d = x.Q - y.Q
        d <= DYADIC_ALIGN_MAX && return (_add_aligned_xy(x, y, d), 0)
        return (x, sy > 0 ? 1 : -1)
    else
        d = y.Q - x.Q
        d <= DYADIC_ALIGN_MAX && return (_add_aligned_xy(y, x, d), 0)
        return (y, sx > 0 ? 1 : -1)
    end
end

@noinline function _mul_special(x::Dyadic, y::Dyadic)
    (isnan_dy(x) || isnan_dy(y)) && return DYADIC_NAN
    (iszero_dy(x) || iszero_dy(y)) && return DYADIC_NAN  # zero times infinity
    return sign_dy(x) * sign_dy(y) > 0 ? DYADIC_POSINF : DYADIC_NEGINF
end

@inline _mul_finite_unchecked(x::Dyadic, y::Dyadic) =
    _finite(x.S * y.S, x.Q + y.Q)

"""
    mul_dy(x, y) -> Dyadic

Hot engine product. Precondition for finite operands: the exact significand
product and exponent sum fit their fields. The current engine invariant
`nbits(x.S) + nbits(y.S) <= 96` is sufficient.

Use `mul_dy_checked` at untrusted boundaries.
"""
@inline function mul_dy(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return _mul_special(x, y)
    return _mul_finite_unchecked(x, y)
end

@noinline function _throw_mul_wide(nx::Int, ny::Int)
    throw(ArgumentError(
        "Dyadic multiply would overflow Int128: $nx + $ny significand bits > 96"))
end

"""Checked counterpart to `mul_dy` for tests and untrusted callers."""
@inline function mul_dy_checked(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return _mul_special(x, y)
    nx, ny = nbits_dy(x.S), nbits_dy(y.S)
    nx + ny <= 96 || return _throw_mul_wide(nx, ny)
    return _mul_finite_unchecked(x, y)
end

# -----------------------------------------------------------------------------
# Ordering and equality by value
# -----------------------------------------------------------------------------

@inline _exponent_raw(x::Dyadic) = x.Q + nbits_dy(x.S) - 1

@inline function _cmp_finite(x::Dyadic, y::Dyadic)
    xs, ys = x.S, y.S

    if iszero(xs)
        return iszero(ys) ? 0 : (ys > 0 ? -1 : 1)
    elseif iszero(ys)
        return xs > 0 ? 1 : -1
    end

    xneg, yneg = xs < 0, ys < 0
    xneg != yneg && return xneg ? -1 : 1

    ex, ey = _exponent_raw(x), _exponent_raw(y)
    if ex != ey
        m = ex < ey ? -1 : 1
        return xneg ? -m : m
    end

    ax, ay = mag_dy(xs), mag_dy(ys)
    if x.Q >= y.Q
        ax <<= Int(x.Q - y.Q)  # bounded by significand-width difference
    else
        ay <<= Int(y.Q - x.Q)
    end

    m = ax == ay ? 0 : (ax < ay ? -1 : 1)
    return xneg ? -m : m
end

@noinline function _cmp_special(x::Dyadic, y::Dyadic)
    kx, ky = x.kind, y.kind
    (kx == DY_NAN || ky == DY_NAN) && return 2  # unordered
    kx == ky && return 0
    kx == DY_POSINF && return 1
    ky == DY_POSINF && return -1
    kx == DY_NEGINF && return -1
    return 1  # y is -Inf and x is finite
end

@inline function cmp_dy(x::Dyadic, y::Dyadic)
    _both_finite(x, y) ? _cmp_finite(x, y) : _cmp_special(x, y)
end

Base.:(==)(x::Dyadic, y::Dyadic) = cmp_dy(x, y) == 0
Base.:(<)(x::Dyadic, y::Dyadic)  = cmp_dy(x, y) == -1
Base.:(<=)(x::Dyadic, y::Dyadic) = cmp_dy(x, y) <= 0

# `isequal` and `isless` jointly define the fixed total order used by sorting,
# hashing collections, `unique`, and index lookup.  Dyadic follows the
# floating-point convention: all NaNs are `isequal`, while NaN sorts after all
# finite values and infinities.  There is only one zero row, so no signed-zero
# distinction is needed.
@inline function Base.isequal(x::Dyadic, y::Dyadic)
    _both_finite(x, y) && return _cmp_finite(x, y) == 0
    return x.kind == y.kind
end

@inline function Base.isless(x::Dyadic, y::Dyadic)
    _both_finite(x, y) && return _cmp_finite(x, y) < 0

    kx, ky = x.kind, y.kind
    kx == DY_NAN && return false
    ky == DY_NAN && return true
    return _cmp_special(x, y) < 0
end

# `isgreater`, descending searches, and `argmin` use this predicate to give
# unordered values their documented floating-point placement.
@inline Base.isunordered(x::Dyadic) = isnan_dy(x)

# Dyadic is intentionally `<: Real`, so it does not inherit the NaN-propagating
# `AbstractFloat` methods.  Base's generic `min`/`max` use the total-order
# predicate `isless`; that ordering deliberately places NaN after ordinary
# values and therefore is not the pairwise NaN-propagation contract required by
# floating-point reductions.  These methods reproduce Julia's `AbstractFloat`
# behavior without signed-zero handling (Dyadic has only one zero): either NaN
# operand is propagated, and an equal pair returns the second operand.  The
# finite hot path performs one joint
# tag test; all NaN/infinity handling stays out of line.
@noinline function _min_special(x::Dyadic, y::Dyadic)
    isnan_dy(x) && return x
    isnan_dy(y) && return y
    return _cmp_special(x, y) < 0 ? x : y
end

@noinline function _max_special(x::Dyadic, y::Dyadic)
    isnan_dy(x) && return x
    isnan_dy(y) && return y
    return _cmp_special(x, y) > 0 ? x : y
end

@inline function Base.min(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return _min_special(x, y)
    return _cmp_finite(x, y) < 0 ? x : y
end

@inline function Base.max(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return _max_special(x, y)
    return _cmp_finite(x, y) > 0 ? x : y
end

@noinline function _minmax_special(x::Dyadic, y::Dyadic)
    isnan_dy(x) && return (x, x)
    isnan_dy(y) && return (y, y)
    c = _cmp_special(x, y)
    return c < 0 ? (x, y) : (c > 0 ? (y, x) : (y, y))
end

@inline function Base.minmax(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return _minmax_special(x, y)
    c = _cmp_finite(x, y)
    return c < 0 ? (x, y) : (c > 0 ? (y, x) : (y, y))
end

# -----------------------------------------------------------------------------
# Total Base arithmetic: exact escape to BigFloat
# -----------------------------------------------------------------------------

@inline function _bigspan(x::Dyadic, y::Dyadic)
    lo = min(x.Q, y.Q)
    hi = max(x.Q + nbits_dy(x.S), y.Q + nbits_dy(y.S))
    max(Int(hi - lo) + 1, 2)
end

function Base.:+(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return BigFloat(_add_special(x, y))
    setprecision(BigFloat, _bigspan(x, y)) do
        BigFloat(x) + BigFloat(y)
    end
end

Base.:-(x::Dyadic, y::Dyadic) = x + (-y)

function Base.:*(x::Dyadic, y::Dyadic)
    _both_finite(x, y) || return BigFloat(_mul_special(x, y))
    p = max(nbits_dy(x.S) + nbits_dy(y.S), 2)
    setprecision(BigFloat, p) do
        BigFloat(x) * BigFloat(y)
    end
end

# -----------------------------------------------------------------------------
# Exponent scaling and integer rounding
# -----------------------------------------------------------------------------

@inline function Base.ldexp(x::Dyadic, n::Integer)
    isfinite_dy(x) || return x
    return _finite(x.S, x.Q + Int64(n))
end

@inline function exponent_dy(x::Dyadic)
    isfinite_dy(x) && !iszero(x.S) ||
        throw(DomainError(x, "Dyadic exponent is defined only for finite nonzero values"))
    return _exponent_raw(x)
end

Base.exponent(x::Dyadic) = exponent_dy(x)

const _DY_TINY = -1

"""Split finite, nonzero `x` with `x.Q < 0` into floor, remainder, and shift."""
@inline function _split_dy(x::Dyadic)
    # Test before negation so typemin(Int64) cannot overflow.
    if x.Q <= -128
        q = x.S < 0 ? -one(Int128) : zero(Int128)
        return (q, one(Int128), _DY_TINY)
    end

    sh = Int(-x.Q)  # now in 1:127
    q = x.S >> sh
    return (q, x.S - (q << sh), sh)
end

@inline _int_dy(q::Int128) = _finite(q, Int64(0))
@inline _rounds_to_self(x::Dyadic) =
    !isfinite_dy(x) || x.Q >= 0 || iszero(x.S)

@inline function Base.floor(x::Dyadic)
    _rounds_to_self(x) && return x
    q, _, _ = _split_dy(x)
    return _int_dy(q)
end

@inline function Base.ceil(x::Dyadic)
    _rounds_to_self(x) && return x
    q, r, _ = _split_dy(x)
    return _int_dy(iszero(r) ? q : q + one(Int128))
end

@inline function Base.trunc(x::Dyadic)
    _rounds_to_self(x) && return x
    q, r, _ = _split_dy(x)
    return _int_dy((x.S < 0) & !iszero(r) ? q + one(Int128) : q)
end

@inline function Base.round(x::Dyadic)
    _rounds_to_self(x) && return x
    q, r, sh = _split_dy(x)
    sh == _DY_TINY && return DYADIC_ZERO  # includes the exact -1/2 typemin case
    iszero(r) && return _int_dy(q)
    half = one(Int128) << (sh - 1)
    up = r > half || (r == half && !iseven(q))
    return _int_dy(up ? q + one(Int128) : q)
end

Base.round(x::Dyadic, ::RoundingMode{:Down})    = floor(x)
Base.round(x::Dyadic, ::RoundingMode{:Up})      = ceil(x)
Base.round(x::Dyadic, ::RoundingMode{:ToZero})  = trunc(x)
Base.round(x::Dyadic, ::RoundingMode{:Nearest}) = round(x)

# -----------------------------------------------------------------------------
# BigFloat and fixed binary-float conversions
# -----------------------------------------------------------------------------

function Base.BigFloat(x::Dyadic)
    if isfinite_dy(x)
        iszero(x.S) && return BigFloat(0)
        p = max(nbits_dy(x.S), 2)
        return setprecision(BigFloat, p) do
            ldexp(BigFloat(x.S), x.Q)
        end
    end

    x.kind == DY_NAN    && return BigFloat(NaN)
    x.kind == DY_POSINF && return BigFloat(Inf)
    return BigFloat(-Inf)
end

@inline function _safe_ldexp_fastpath(::Type{T}, x::Dyadic) where {T<:AbstractFloat}
    nbits_dy(x.S) <= Base.precision(T) || return false
    e = _exponent_raw(x)
    return Base.exponent(floatmin(T)) <= e <= Base.exponent(floatmax(T))
end

function _dyadic_to(::Type{T}, x::Dyadic) where {T<:AbstractFloat}
    if isfinite_dy(x)
        iszero(x.S) && return zero(T)
        _safe_ldexp_fastpath(T, x) && return ldexp(T(x.S), x.Q)
        return T(BigFloat(x))
    end

    x.kind == DY_NAN    && return T(NaN)
    x.kind == DY_POSINF && return T(Inf)
    return T(-Inf)
end

Base.Float16(x::Dyadic) = _dyadic_to(Float16, x)
Base.Float32(x::Dyadic) = _dyadic_to(Float32, x)
Base.Float64(x::Dyadic) = _dyadic_to(Float64, x)
Base.big(x::Dyadic) = BigFloat(x)

# Base's rational-valued hashing protocol consumes this decomposition.
@inline function Base.decompose(x::Dyadic)
    if isfinite_dy(x)
        return (x.S, x.Q, one(Int128))
    end
    x.kind == DY_NAN    && return (Int128(0), Int64(0), Int128(0))
    x.kind == DY_POSINF && return (Int128(1), Int64(0), Int128(0))
    return (Int128(-1), Int64(0), Int128(0))
end

# -----------------------------------------------------------------------------
# Dyadic <-> Rational
# -----------------------------------------------------------------------------

_fit_rat(::Type{BigInt}, n::BigInt, _) = n
_fit_rat(::Type{T}, n::BigInt, what) where {T<:Integer} =
    typemin(T) <= n <= typemax(T) ? T(n) :
    throw(OverflowError(
        "dyadic_to_rational: the $what needs $(ndigits(n; base=2)) bits; " *
        "Rational{$T} cannot hold it; use Rational{BigInt}"))

@noinline function _dyadic_to_rational_special(::Type{T}, x::Dyadic) where {T<:Integer}
    x.kind == DY_NAN &&
        throw(InexactError(:dyadic_to_rational, Rational{T}, x))
    x.kind == DY_POSINF &&
        return Base.unsafe_rational(one(T), zero(T))

    # An unsigned numerator cannot encode negative infinity.
    (T <: Unsigned || T === Bool) &&
        throw(InexactError(:dyadic_to_rational, Rational{T}, x))
    return Base.unsafe_rational(-one(T), zero(T))
end

function dyadic_to_rational(::Type{T}, x::Dyadic) where {T<:Integer}
    isfinite_dy(x) || return _dyadic_to_rational_special(T, x)
    iszero(x.S) && return Base.unsafe_rational(zero(T), one(T))

    n, q = BigInt(x.S), x.Q
    if q >= 0
        return Base.unsafe_rational(_fit_rat(T, n << q, "numerator"), one(T))
    end

    k = min(Int64(trailing_zeros(n)), -q)
    return Base.unsafe_rational(
        _fit_rat(T, n >> k, "numerator"),
        _fit_rat(T, BigInt(1) << (-q - k), "denominator"))
end

dyadic_to_rational(x::Dyadic) = dyadic_to_rational(BigInt, x)

function isdyadic(q::Rational)
    d = denominator(q)
    return iszero(d) || ispow2(d)
end

function rational_to_dyadic(q::Rational)
    n0, d0 = numerator(q), denominator(q)

    if iszero(d0)
        iszero(n0) && throw(InexactError(:rational_to_dyadic, Dyadic, q))
        return n0 > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    end
    iszero(n0) && return DYADIC_ZERO

    n, d = BigInt(n0), BigInt(d0)
    if d < 0
        n = -n
        d = -d
    end
    ispow2(d) || throw(InexactError(:rational_to_dyadic, Dyadic, q))

    k = trailing_zeros(d)
    tz = trailing_zeros(n)
    s = n >> tz
    typemin(Int128) <= s <= typemax(Int128) ||
        throw(InexactError(:rational_to_dyadic, Dyadic, q))

    Q = BigInt(tz) - BigInt(k)
    typemin(Int64) <= Q <= typemax(Int64) ||
        throw(OverflowError("rational_to_dyadic: exponent $Q exceeds Int64"))
    return _finite(Int128(s), Int64(Q))
end

Base.Rational{T}(x::Dyadic) where {T<:Integer} = dyadic_to_rational(T, x)
Dyadic(q::Rational) = rational_to_dyadic(q)

# -----------------------------------------------------------------------------
# Exact conversion from binary floating-point carriers
# -----------------------------------------------------------------------------

@inline dyadic_from(x::Dyadic) = x

function dyadic_from(x::Base.IEEEFloat)
    if !isfinite(x)
        return isnan(x) ? DYADIC_NAN : (x > 0 ? DYADIC_POSINF : DYADIC_NEGINF)
    end
    iszero(x) && return DYADIC_ZERO

    num, pow, den = Base.decompose(x)
    n = Int128(num) * sign(den)
    tz = trailing_zeros(n)
    return _finite(n >> tz, Int64(pow) + tz)
end

function dyadic_from(x::AbstractFloat)
    if !isfinite(x)
        return isnan(x) ? DYADIC_NAN : (x > 0 ? DYADIC_POSINF : DYADIC_NEGINF)
    end
    iszero(x) && return DYADIC_ZERO

    num0, pow0, den0 = Base.decompose(x)
    n, d = BigInt(num0), BigInt(den0)
    if d < 0
        n = -n
        d = -d
    end
    ispow2(d) || throw(InexactError(:Dyadic, Dyadic, x))

    tz = trailing_zeros(n)
    n >>= tz
    q = BigInt(pow0) + tz - trailing_zeros(d)

    typemin(Int128) <= n <= typemax(Int128) ||
        throw(InexactError(:Dyadic, Dyadic,
            "significand needs $(ndigits(n; base=2)) bits after normalization; " *
            "Dyadic stores an Int128 significand"))
    typemin(Int64) <= q <= typemax(Int64) ||
        throw(OverflowError("Dyadic exponent $q exceeds Int64"))

    return _finite(Int128(n), Int64(q))
end

Dyadic(x::AbstractFloat) = dyadic_from(x)
Dyadic(x::Integer) = _finite(Int128(x), Int64(0))

function Base.show(io::IO, x::Dyadic)
    if isfinite_dy(x)
        return print(io, "Dyadic(", x.S, " * 2^", x.Q, ")")
    end
    x.kind == DY_NAN    && return print(io, "Dyadic(NaN)")
    x.kind == DY_POSINF && return print(io, "Dyadic(Inf)")
    return print(io, "Dyadic(-Inf)")
end

end # module DyadicNumbers
