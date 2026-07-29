# ===== formats.jl — the Binary{K,P,SGN,EXT} type, Group M, naming, Base API (design §2, §3.1)

"""
    Binary{K,P,SGN,EXT} <: AbstractFloat

A P3109 floating-point value: a code point in the format with bitwidth `K ∈ 3:8`,
precision `P`, signedness `SGN::Bool` (`true` = Signed), domain `EXT::Bool`
(`true` = Extended, i.e. the datum set includes infinities).

The code point occupies the low `K` bits of the payload byte; the high `8-K` bits
are maintained zero as a representation invariant. Construct raw code points with
`T(c::UInt8)` (validated code-point construction), `rawvalue(T, c)` (unchecked
kernel route), or `Binary{...}(Val(:code), x::UInt8)`; construct from numeric
values with `T(x::Real)` (default projection spec) or `Convert`. UInt8 is
the one argument type meaning *code point*; all other Reals mean *value*.
"""
struct Binary{K,P,SGN,EXT} <: AbstractFloat
    x::UInt8
    @inline function Binary{K,P,SGN,EXT}(::Val{:code}, x::UInt8) where {K,P,SGN,EXT}
        @boundscheck begin
            checkformat(K, P, SGN, EXT)
            Int(x) < (1 << K) || throw(ArgumentError("code point $x out of range for K=$K"))
        end
        new{K,P,SGN,EXT}(x)
    end
end

function checkformat(K, P, SGN, EXT)
    (K isa Int && P isa Int && SGN isa Bool && EXT isa Bool) ||
        throw(ArgumentError("Binary parameters must be (K::Int, P::Int, SGN::Bool, EXT::Bool)"))
    3 <= K <= 8 || throw(ArgumentError("bitwidth K=$K outside supported range 3:8"))
    if SGN
        0 < P < K || throw(ArgumentError("signed format requires 0 < P < K (got P=$P, K=$K)"))
    else
        0 < P <= K || throw(ArgumentError("unsigned format requires 0 < P ≤ K (got P=$P, K=$K)"))
    end
    nothing
end

# ---- representation traits (implementextensions §2 R-A, §3.2)
#
# These answer "how is a code point stored, and how is it decoded" — the axis
# that is a function of K alone. They are separate from the *carrier* traits in
# carriers.jl, which answer "what holds a datum in flight" and are a function of
# the exponent bias B.
#
# Every one is reached by DISPATCH and has a single concrete return type
# (invariant 9). Today there is one representation, so each is one method; when
# `Code16` arrives they become two methods dispatching on the representation,
# NOT a branch on K. Gate G9 pins that each folds to a literal per format.

"""Decode strategy for a format: a `2^K`-entry constant tuple, or computed."""
abstract type DecodePolicy end
"""`2^K ≤ 256`: the generated constant tuple folds and costs one load."""
struct TableDecode <: DecodePolicy end
"""`2^K > 256`: compute from the code point; a 65 536-element tuple literal is
not a table, it is a compile-time hazard (invariant 10)."""
struct ComputeDecode <: DecodePolicy end

"""
    _unitmask(U, K) -> U

The low-`K`-bits mask of storage unit `U`, built by **complement** — shift down
from `typemax`, never up from `one`.

Julia defines a shift at or beyond a type's width as zero, so `UInt8(1) << 8`
and `UInt16(1) << 16` are both `0`, and `2^K` computed in a unit of width `K`
is `0`. The format grid **always contains a format whose K equals its storage
width** (K = 8 on `UInt8`, K = 16 on `UInt16`), so that case is structural, not
an edge. Here the shift amount is `width − K ∈ [0, width−1]`, in which the
pathological amount is unreachable *by construction*, at every K, for every
unit — including a future `Code32`.
"""
@inline _unitmask(::Type{U}, K::Int) where {U<:Unsigned} = typemax(U) >> (8 * sizeof(U) - K)

"""The storage unit of a format's code point: `UInt8` for K ≤ 8."""
@inline codeunit_type(::Type{<:Binary}) = UInt8
"""Decode strategy for a format (`TableDecode` while every K ≤ 8)."""
@inline decodepolicy(::Type{<:Binary}) = TableDecode()
"""Unsigned type wide enough for a format's `2^K + 1` total-order keys."""
@inline orderkeytype(::Type{<:Binary}) = UInt16
"""The concrete representation type of a format — the identity while `Binary`
is itself concrete; the abstract-format → `Code8`/`Code16` map afterwards."""
@inline reptype(::Type{F}) where {F<:Binary} = F
# `codemask` needs `bitwidth`, so it is defined with the Group M block below.

"""Unsafe raw constructor used by kernels after invariants are established."""
@inline rawvalue(::Type{Binary{K,P,SGN,EXT}}, x::UInt8) where {K,P,SGN,EXT} =
    @inbounds Binary{K,P,SGN,EXT}(Val(:code), x)

"""
    (T::Type{<:Binary})(c::UInt8) -> T

Construct a value from its **code point** (validated: for K < 8, `c` must be
`< 2^K` or an `ArgumentError` is thrown; the range check folds away at K = 8 and
for constant codes). `Binary5p3sf(0x08) == Binary5p3sf(1.0)`.

`UInt8` is the *only* argument type with code-point semantics — every other
`Real` (including other `Integer`s) constructs by projecting the numeric value,
and `Convert` is numeric for all integers: `Binary8p4se(0x02)` is code point 2
(the second-smallest subnormal), while `Binary8p4se(2)` is the number 2.0.
`rawvalue(T, c)` remains the unchecked kernel-internal route.
"""
@inline (::Type{Binary{K,P,SGN,EXT}})(c::UInt8) where {K,P,SGN,EXT} =
    Binary{K,P,SGN,EXT}(Val(:code), c)

@inline Base.codepoint(v::Binary) = v.x   # extends Base.codepoint (Char); avoids export clash

# ---- Group M (meta) operations: pure functions of the type parameters (design §2.3)
#
# Every signature here is `::Type{<:Binary{K,P,S,E}}`, not the exact
# `::Type{Binary{K,P,S,E}}`. Today those match the same single type, so this is
# a no-op verified by G5 — but once `Binary` is abstract the exact form stops
# matching the concrete `Code8`/`Code16` values that flow through it, and an
# exact-form method is then a `MethodError` waiting for its first wide caller.
# Widening here rather than in Stage 2 keeps the risky stage's diff to the type
# refactor alone (implementextensions §11 M7).
"Format bitwidth K (3–8)."
bitwidth(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = K
Base.precision(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = P
"Whether the format is Signed (has a sign bit and negative datums)."
issigned(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = S
"Whether the format's domain is Extended (datum set includes infinities)."
isextended(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = E
"Exponent bias: 2^(K−P−1) signed, 2^(K−P) unsigned."
expbias(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = S ? (1 << (K - P - 1)) : (1 << (K - P))
"Width of the exponent field in bits: (K − signbit) − (P − 1)."
expbitwidth(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = (S ? K - 1 : K) - (P - 1)
"Trailing-significand width P − 1 (the stored fraction bits)."
trailingsigbits(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = P - 1

"""The low-K-bits mask of a format's storage unit (representation invariant 3):
the code point occupies the low K bits, the high bits are maintained zero."""
@inline codemask(::Type{F}) where {F<:Binary} = _unitmask(codeunit_type(F), bitwidth(F))

const BitwidthOf = bitwidth
const PrecisionOf = precision
const SignednessOf = issigned
const DomainOf = isextended
const ExponentBiasOf = expbias
const ExponentBitwidthOf = expbitwidth
const TrailingSignificandBitwidthOf = trailingsigbits

# Special code points (literals after constant folding).
#
# Built from `signmask` and `codemask` rather than from `1 << K` (technique
# T11). The values are unchanged — G5 verifies that byte-for-byte — but the
# *reason* they are correct changes from "the shift happens to run in `Int`,
# and K ≤ 8 ≪ 63" to a structural one: every shift amount below is ≤ K−1, and
# `codemask` shifts DOWN from `typemax`, so the oversized-shift hazard
# (`UInt16(1) << 16 === 0x0000`, no error) is unreachable at every K for every
# storage unit. That property is what a 504-format grid needs to inherit for
# free; width-relative safety is an accident that holds until it does not.
@inline _cu(::Type{F}, x::Integer) where {F<:Binary} = codeunit_type(F)(x)

@inline signmask(::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}} = _cu(F, 1) << (K - 1)
@inline nan_code(::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}} =
    S ? signmask(F) : codemask(F)
@inline posinf_code(::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}} =   # meaningful only when E
    (S ? signmask(F) : codemask(F)) - _cu(F, 1)
@inline neginf_code(::Type{F}) where {F<:Binary} = codemask(F)        # signed+E only

# Extremal *code points* (draft Group M returns format values).
# Largest finite magnitude code: the greatest code below the NaN/Inf slots.
#   signed·extended  : +Inf at 2^(K-1)-1        → maxfinite = 2^(K-1)-2
#   signed·finite    : NaN  at 2^(K-1)          → maxfinite = 2^(K-1)-1
#   unsigned·extended: NaN 2^K-1, +Inf 2^K-2    → maxfinite = 2^K-3
#   unsigned·finite  : NaN  at 2^K-1            → maxfinite = 2^K-2
# The four rows collapse to one expression: the ceiling is the NaN slot's
# neighbourhood — `signmask` for signed formats, `codemask` for unsigned — and
# the Extended domain spends one more code on +Inf.
@inline function MaxFiniteOf(T::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}}
    ceiling = S ? signmask(F) : codemask(F)
    rawvalue(T, ceiling - _cu(F, E ? 2 : 1))
end
@inline function MinFiniteOf(T::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}}
    S || return rawvalue(T, _cu(F, 0))                         # unsigned: 0
    rawvalue(T, codepoint(MaxFiniteOf(T)) | signmask(T))       # most negative finite
end
@inline MinPositiveOf(T::Type{F}) where {F<:Binary} = rawvalue(T, _cu(F, 1))
@inline MaxSubnormalOf(T::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}} =
    rawvalue(T, (_cu(F, 1) << (P - 1)) - _cu(F, 1))  # P=1 formats have no subnormals ⇒ code 0
@inline MinNormalOf(T::Type{F}) where {K,P,S,E,F<:Binary{K,P,S,E}} =
    rawvalue(T, _cu(F, 1) << (P - 1))

# Datum-valued companions (design §2.3): Float64 is the universal exact carrier
maxfinite_datum(T::Type{<:Binary}) = decode(MaxFiniteOf(T))
minfinite_datum(T::Type{<:Binary}) = decode(MinFiniteOf(T))

# ---- Value-argument forwarders for Group M and the extremal queries.
# The answer is a pure function of the type parameters, so a value carries it:
# `BitwidthOf(x)` ≡ `BitwidthOf(typeof(x))`. Restricted to `Binary` — a `where {T}`
# signature would claim every type in the language. Constant-folds to the same
# literal as the type-argument form.
for f in (:bitwidth, :issigned, :isextended, :expbias, :expbitwidth, :trailingsigbits,
          :MaxFiniteOf, :MinFiniteOf, :MinPositiveOf, :MaxSubnormalOf, :MinNormalOf)
    @eval @inline $f(x::Binary) = $f(typeof(x))
end
# `PrecisionOf` aliases `Base.precision`, so its forwarder must be spelled out.
@inline Base.precision(x::Binary) = precision(typeof(x))

# ---- Naming grid, draft §3.2: BinaryKpP + s|u + e|f
# The name is spelled in exactly one place: the alias-generating loop and the
# public `formatname` both read it from here, so the grid cannot drift.
_formatname(K, P, S, E) = Symbol("Binary", K, "p", P, S ? "s" : "u", E ? "e" : "f")

const _NAMED = Dict{Symbol,DataType}()
for K in 3:8, P in 1:K, S in (true, false), E in (true, false)
    S && P >= K && continue
    name = _formatname(K, P, S, E)
    T = Binary{K,P,S,E}
    @eval const $name = $T
    _NAMED[name] = T
end
"""`formatname(T)` — the draft §3.2 name of a format type."""
formatname(::Type{Binary{K,P,S,E}}) where {K,P,S,E} = _formatname(K, P, S, E)

# Print fully-instantiated formats by their draft name; anything else (UnionAlls,
# TypeVar-parameterized types met during stacktrace printing) defers to Base —
# a parametric `::Type{Binary{K,P,S,E}}` method here can be handed unbound
# static parameters by the printing machinery and crash (found by test).
_fully_instantiated(T) =
    T isa DataType && length(T.parameters) == 4 &&
    T.parameters[1] isa Int && T.parameters[2] isa Int &&
    T.parameters[3] isa Bool && T.parameters[4] isa Bool

function Base.show(io::IO, T::Type{<:Binary})
    if _fully_instantiated(T)
        print(io, formatname(T))
    else
        invoke(show, Tuple{IO,Type}, io, T)
    end
end
function Base.show(io::IO, v::Binary)
    T = typeof(v)
    print(io, formatname(T), "(")
    d = decode(v)
    isnan(d) ? print(io, "NaN") : print(io, d)
    print(io, " ≡ 0x", string(codepoint(v); base=16, pad=2), ")")
end

# ---- Base numeric API on the type (defined via Group M / decode; see also ops_scalar.jl)
Base.zero(T::Type{<:Binary}) = rawvalue(T, 0x00)
Base.zero(::T) where {T<:Binary} = zero(T)
Base.iszero(v::Binary) = codepoint(v) == 0x00
Base.typemax(T::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    E ? rawvalue(T, posinf_code(T)) : MaxFiniteOf(T)
Base.typemin(T::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    S ? (E ? rawvalue(T, neginf_code(T)) : MinFiniteOf(T)) : zero(T)
Base.floatmax(T::Type{<:Binary}) = MaxFiniteOf(T)
Base.floatmin(T::Type{<:Binary}) = MinNormalOf(T)
Base.eps(T::Type{Binary{K,P,S,E}}) where {K,P,S,E} = T(2.0^(1 - P))

Base.isnan(v::Binary) = codepoint(v) == nan_code(typeof(v))
function Base.isinf(v::Binary{K,P,S,E}) where {K,P,S,E}
    E || return false
    c = codepoint(v)
    c == posinf_code(typeof(v)) && return true
    (S && c == neginf_code(typeof(v))) && return true
    false
end
Base.isfinite(v::Binary) = !isnan(v) & !isinf(v)
function Base.signbit(v::Binary{K,P,S,E}) where {K,P,S,E}
    S || return false
    isnan(v) && return false
    codepoint(v) >= signmask(typeof(v)) && codepoint(v) != nan_code(typeof(v))
end
function issubnormal_3109(v::Binary{K,P,S,E}) where {K,P,S,E}
    (isnan(v) | isinf(v) | iszero(v)) && return false
    T = typeof(v)
    m = S ? (codepoint(v) & ~signmask(T)) : codepoint(v)
    m < codepoint(MinNormalOf(T))          # subnormal ⟺ magnitude below the least normal
end
Base.issubnormal(v::Binary) = issubnormal_3109(v)

# `one` must be representable; it always is for these formats (biased exp fits by construction).
Base.one(T::Type{<:Binary}) = T(1.0)
Base.one(::T) where {T<:Binary} = one(T)

# Promotion (design §2.4): Binary ⋄ external float promotes to Float64 (the exact carrier);
# no automatic promotion between distinct Binary formats.
Base.promote_rule(::Type{<:Binary}, ::Type{Float64}) = Float64
Base.promote_rule(::Type{<:Binary}, ::Type{Float32}) = Float64
Base.promote_rule(::Type{<:Binary}, ::Type{Float16}) = Float64
Base.promote_rule(::Type{<:Binary}, ::Type{BFloat16}) = Float64
Base.promote_rule(::Type{<:Binary}, ::Type{<:Integer}) = Float64
Base.Float64(v::Binary) = decode(v)
# exact: all K≤8 datums fit Float32 — a direct gather of the narrowed decode
# table, bit-identical to Float32(decode(v)) (asserted exhaustively)
Base.Float32(v::Binary{K,P,SGN,EXT}) where {K,P,SGN,EXT} =
    @inbounds _decode_table32(Binary{K,P,SGN,EXT})[Int(codepoint(v)) + 1]
# exact: ≤8-bit significands ≤ BFloat16's 8-bit precision, exponents within its
# range (subnormals reach 2^-133 < 2^-127) — asserted exhaustively
(::Type{BFloat16})(v::Binary) = BFloat16(decode(v))
(::Type{T})(v::Binary) where {T<:Binary} = _convert_default(T, v)
(::Type{T})(x::Real) where {T<:Binary} = _convert_default(T, x)
# Disambiguates against Base's (::Type{T})(::Rational) where T<:AbstractFloat
# (found by Test.detect_ambiguities). Consistent with the Convert policy: inputs
# must be exactly projectable; Rationals are rejected rather than double-rounded.
(::Type{T})(x::Rational{S}) where {S,T<:Binary} =
    throw(ArgumentError("cannot exactly project a Rational; convert explicitly, e.g. $(T)(Float64(x)), and own the double rounding"))
Base.convert(::Type{T}, v::Binary) where {T<:Binary} = _convert_default(T, v)
Base.convert(::Type{T}, x::Real) where {T<:Binary} = _convert_default(T, x)
# _convert_default is defined in ops_scalar.jl (needs the projection engine).
