# ===== formats.jl — the Binary{K,P,SGN,EXT} type, Group M, naming, Base API (design §2, §3.1)

# ---- the supported bitwidth range, and the representation seam within it.
#
# Three constants, spelled once, because three different things were all being
# written as the literal `8` and they do not move together: the low end of the
# draft's range, the high end this package implements, and the width at which
# the storage unit changes from one byte to two. `KSPLIT` is a REPRESENTATION
# fact — it is `8 * sizeof(UInt8)` and nothing else — while `KMIN`/`KMAX` are a
# scope claim about the package. Conflating them is how `K <= 8` ends up
# meaning "narrow enough for a byte" in one place and "supported" in another.
"""Lowest bitwidth the draft defines (`K = 3`: sign, one exponent bit, one significand bit)."""
const KMIN = 3
"""Highest bitwidth this package implements."""
const KMAX = 16
"""Largest `K` whose code point fits a `UInt8` — the `Code8`/`Code16` seam."""
const KSPLIT = 8

"""
    Binary{K,P,SGN,EXT} <: AbstractFloat

A P3109 **format**: bitwidth `K ∈ 3:16`, precision `P`, signedness `SGN::Bool`
(`true` = Signed), domain `EXT::Bool` (`true` = Extended, i.e. the datum set
includes infinities).

`Binary` is **abstract**, and that is the draft's own distinction: a format is
"a datum set and an encoding" (D1 §3.1), while the width of the machine word
carrying a code point is a representation choice below the standard's level of
description. `Code8` is that representation. The parameterized name is the
*format*; the draft-named alias is its *representation*:

    Binary{8,4,true,true}   # the format  — abstract
    Binary8p4se             # Code8{8,4,true,true}, its representation — concrete

Consequently `Binary8p4se === Binary{8,4,true,true}` is **`false`** and
`Binary8p4se <: Binary{8,4,true,true}` is **`true`**. Use the alias, or
`format(K, P, Σ, Δ)`, wherever a concrete type is needed — an array element
type, a `similar`, a constructor target.

The code point occupies the low `K` bits of the storage unit; the high bits are
maintained zero as a representation invariant. Construct code points with
`T(c::Unsigned)` (validated code-point construction); the implementation uses
an unexported unchecked primitive only after establishing the invariant.
Construct from numeric values with `T(x::Real)` (default projection spec) or `Convert`. `Unsigned` is
the one argument-type class meaning *code point*, at **every** width — `T(0x02)`
is code point 2 whether `T`'s unit is a `UInt8` or a `UInt16`; all other `Real`s
mean *value*.

There are `4K − 2` formats at each `K` (`P ∈ 1:K` × signed/unsigned ×
finite/extended, less the two `P == K` signed combinations, which have no
exponent bits), so `KMIN:KMAX` = 504 in total.
"""
abstract type Binary{K,P,SGN,EXT} <: AbstractFloat end

"""
    Code8{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}

The one-byte representation of a P3109 format — every format with `K ≤ 8`.
Differs from its `Code16` sibling only in the width of the word carrying the
code point; all semantics live in the `Binary` parameters.
"""
struct Code8{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}
    x::UInt8
    @inline function Code8{K,P,SGN,EXT}(::Val{:code}, x::UInt8) where {K,P,SGN,EXT}
        @boundscheck begin
            checkformat(K, P, SGN, EXT)
            K <= KSPLIT || throw(ArgumentError("Code8 requires K ≤ $KSPLIT, got K=$K"))
            # A MASK test, not a comparison against 2^K: it states representation
            # invariant 3 directly (the high bits are zero) rather than a numeric
            # range that merely implies it, and `codemask` is built by complement
            # so it is correct at K = 8, where `1 << K` in the unit is 0.
            x & _unitmask(UInt8, K) == x ||
                throw(ArgumentError("code point $x out of range for K=$K"))
        end
        new{K,P,SGN,EXT}(x)
    end
end

"""
    Code16{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}

The two-byte representation — every format with `KSPLIT < K ≤ KMAX`. Differs
from its `Code8` sibling only in the width of the word carrying the code point;
all semantics live in the `Binary` parameters.
"""
struct Code16{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}
    x::UInt16
    @inline function Code16{K,P,SGN,EXT}(::Val{:code}, x::UInt16) where {K,P,SGN,EXT}
        @boundscheck begin
            checkformat(K, P, SGN, EXT)
            KSPLIT < K <= KMAX ||
                throw(ArgumentError("Code16 requires $(KSPLIT+1) ≤ K ≤ $KMAX, got K=$K"))
            x & _unitmask(UInt16, K) == x ||
                throw(ArgumentError("code point $x out of range for K=$K"))
        end
        new{K,P,SGN,EXT}(x)
    end
end

function checkformat(K, P, SGN, EXT)
    (K isa Int && P isa Int && SGN isa Bool && EXT isa Bool) ||
        throw(ArgumentError("Binary parameters must be (K::Int, P::Int, SGN::Bool, EXT::Bool)"))
    KMIN <= K <= KMAX ||
        throw(ArgumentError("bitwidth K=$K outside supported range $KMIN:$KMAX"))
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

# Each representation trait gets THREE methods: one per representation, plus a
# forwarder from the abstract format through `reptype`.
#
# The forwarder is not optional. Group M and the extremal queries are bounded by
# `::Type{<:Binary{K,P,S,E}}`, which admits the abstract format itself, and
# asking a *format* for its extremal code point is legitimate usage that the
# suite and the docs both do: `MaxFiniteOf(Binary{5,2,true,true})`. Without the
# forwarder those calls reach `codeunit_type` with an abstract argument and die.
# The exact `::Type{Binary{K,P,S,E}}` signature matches only the abstract type,
# so it cannot be ambiguous with the `<:Code8` / `<:Code16` methods.

"""The storage unit of a format's code point: `UInt8` for K ≤ 8, `UInt16` above."""
@inline codeunit_type(::Type{<:Code8})  = UInt8
@inline codeunit_type(::Type{<:Code16}) = UInt16
@inline codeunit_type(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    codeunit_type(reptype(Binary{K,P,S,E}))
"""Decode strategy: a `2^K ≤ 256` constant tuple, or computed from the code."""
@inline decodepolicy(::Type{<:Code8})  = TableDecode()
@inline decodepolicy(::Type{<:Code16}) = ComputeDecode()
@inline decodepolicy(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    decodepolicy(reptype(Binary{K,P,S,E}))
"""Unsigned type wide enough for a format's `2^K + 1` total-order keys."""
@inline orderkeytype(::Type{<:Code8})  = UInt16
@inline orderkeytype(::Type{<:Code16}) = UInt32
@inline orderkeytype(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    orderkeytype(reptype(Binary{K,P,S,E}))

"""
    reptype(F) -> Type

The concrete representation of a format. The identity on a concrete input, and
the `Binary{K,P,S,E} → Code8|Code16` map on an abstract one.

Julia will **not** exploit "this abstract type has exactly one subtype": there
are no sealed types, inference cannot narrow an abstract element type to its
unique subtype, and nothing stops a third party declaring another `<: Binary`.
So `reptype` carries real weight rather than being belt-and-braces — it is how
a method that holds only the format parameters reaches a constructible type.

The `Val` barrier is deliberate (invariant 9). The obvious spelling,
`K <= KSPLIT ? Code8{…} : Code16{…}`, returns a `Type`, so its inferred return type
is a small `Union` unless the compiler folds the comparison. It usually will;
"usually" cannot underwrite a correctness-critical selection that also gates a
zero-allocation guarantee. Behind a `Val`, each `_rep` method has exactly one
concrete return type and there is nothing to fold. Gate G9 checks it per format.
"""
@inline reptype(::Type{T}) where {T<:Code8}  = T
@inline reptype(::Type{T}) where {T<:Code16} = T
@inline reptype(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    _rep(Val(K <= KSPLIT), Binary{K,P,S,E})
@inline _rep(::Val{true},  ::Type{Binary{K,P,S,E}}) where {K,P,S,E} = Code8{K,P,S,E}
@inline _rep(::Val{false}, ::Type{Binary{K,P,S,E}}) where {K,P,S,E} = Code16{K,P,S,E}
# `codemask` needs `bitwidth`, so it is defined with the Group M block below.

"""
Unsafe raw constructor used by kernels after invariants are established.

Accepts an abstract format and normalizes through `reptype`; the type is passed
*as an argument* to `_rawvalue` rather than assigned to a local, so it becomes a
type parameter of the callee instead of a value the compiler has to fold
(technique T6). Kernel call sites pass concrete types and pay nothing.
"""
@inline rawvalue(::Type{F}, x) where {F<:Binary} = _rawvalue(reptype(F), x)
@inline _rawvalue(::Type{R}, x) where {R<:Code8}  = @inbounds R(Val(:code), UInt8(x))
@inline _rawvalue(::Type{R}, x) where {R<:Code16} = @inbounds R(Val(:code), UInt16(x))

"""
    (T::Type{<:Binary})(c::Unsigned) -> T

Construct a value from its **code point** (validated: `c` must satisfy the
representation invariant for the format's K, or an `ArgumentError` is thrown;
the check folds away when K equals the storage width and for constant codes).
`Binary5p3sf(0x08) == Binary5p3sf(1.0)`.

`Unsigned` is the argument-type *class* with code-point semantics, at every
width — every other `Real` (including signed `Integer`s) constructs by
projecting the numeric value. `Binary8p4se(0x02)` is code point 2 (the
second-smallest subnormal), while `Binary8p4se(2)` is the number 2.0. Widening
an `Unsigned` is lossless, so the only way a wrong-width argument can be wrong
is by being out of code range — which throws. `rawvalue(T, c)` remains the
unchecked kernel-internal route.
"""
@inline (::Type{R})(c::Unsigned) where {K,P,S,E,R<:Code8{K,P,S,E}} =
    (_checkcode(R, c); R(Val(:code), UInt8(c)))
@inline (::Type{R})(c::Unsigned) where {K,P,S,E,R<:Code16{K,P,S,E}} =
    (_checkcode(R, c); R(Val(:code), UInt16(c)))

# The range check must happen BEFORE the narrowing, or the argument's width
# decides the exception. `Binary5p2se(0x0100)` narrowed first raises
# `InexactError` about `UInt8`, which is a statement about the *representation* —
# but the caller's error is about the *format*: 256 is not a code point of a
# 5-bit format at any width. Checked first, every offered `Unsigned` width gets
# the same `ArgumentError` naming K, which is what invariant 2's "range-checked
# against 2^K regardless of its width" actually requires.
#
# The comparison promotes to the wider of the two unsigned types, so it is exact
# for `UInt128` arguments and folds to nothing for constant codes. The narrowing
# that follows is a *checked* conversion that the check has already made
# infallible — deliberately not `% UInt8`, so the "no unchecked conversion in a
# K-dependent layer" property (§1 C5) stays true by grep and not by argument.
@inline function _checkcode(::Type{F}, c::Unsigned) where {K,P,S,E,F<:Binary{K,P,S,E}}
    c <= codemask(F) ||
        throw(ArgumentError("code point $c out of range for K=$K (max $(codemask(F)))"))
    nothing
end

# Constructors on the ABSTRACT format still work and forward to the
# representation, so `Binary{8,4,true,true}(x)` keeps its meaning even though the
# type is no longer concrete. This is what keeps the break to `===`/`eltype`
# rather than to construction.
@inline (::Type{Binary{K,P,S,E}})(c::Unsigned) where {K,P,S,E} =
    reptype(Binary{K,P,S,E})(c)
@inline (::Type{Binary{K,P,S,E}})(x::Real) where {K,P,S,E} =
    reptype(Binary{K,P,S,E})(x)
# The `Val(:code)` route must narrow to the representation's unit before it can
# reach the inner constructor — otherwise a `UInt8` code aimed at a `Code16`
# format dies with a `MethodError` *before* `@boundscheck` can run
# `checkformat`, turning a parameter-validation error into a dispatch error.
# Deliberately NOT `@inbounds`: this is the checked route, and the check is the
# point.
@inline (::Type{Binary{K,P,S,E}})(::Val{:code}, x) where {K,P,S,E} =
    _codector(reptype(Binary{K,P,S,E}), x)
@inline _codector(::Type{R}, x) where {R<:Code8}  = R(Val(:code), UInt8(x))
@inline _codector(::Type{R}, x) where {R<:Code16} = R(Val(:code), UInt16(x))
# `Binary` and `Rational` are both `<: Real`, so the forwarder above is
# ambiguous with the cross-format constructor and with the `Rational` rejector
# unless each is disambiguated here. Both forward, so the abstract format
# inherits exactly the representation's behaviour — including the deliberate
# `Rational` rejection.
@inline (::Type{Binary{K,P,S,E}})(v::Binary) where {K,P,S,E} =
    reptype(Binary{K,P,S,E})(v)
(::Type{Binary{K,P,S,E}})(x::Rational{R}) where {K,P,S,E,R} =
    reptype(Binary{K,P,S,E})(x)

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
for K in KMIN:KMAX, P in 1:K, S in (true, false), E in (true, false)
    S && P >= K && continue
    name = _formatname(K, P, S, E)
    # The alias names the REPRESENTATION, not the format: it must be concrete to
    # serve as an array element type. Plain code, not an `@eval`, so the grid
    # costs 504 constant definitions rather than 504 macro expansions.
    T = (K <= KSPLIT ? Code8 : Code16){K,P,S,E}
    @eval const $name = $T
    _NAMED[name] = T
end

"""`formatname(T)` — the draft §3.2 name of a format type."""
formatname(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = _formatname(K, P, S, E)

"""
    format(K, P, Σ, Δ) -> Type

The concrete representation type for a format, from **runtime** parameters —
`format(8, 4, true, true) === Binary8p4se`. The programmatic route to a type
that can be an array element or a constructor target, and the supported
replacement for spelling `Binary{K,P,Σ,Δ}` where a concrete type is meant.

Deliberately a `Dict` lookup: this path is reflection, it is not
performance-sensitive, and it must not pretend to be. Where the parameters are
static, the aliases and `reptype` are the zero-cost routes.
"""
function format(K::Int, P::Int, S::Bool, E::Bool)
    T = get(_NAMED, _formatname(K, P, S, E), nothing)
    T === nothing && (checkformat(K, P, S, E);
                      throw(ArgumentError("no format Binary$(K)p$(P)$(S ? 's' : 'u')$(E ? 'e' : 'f')")))
    T
end

# An abstract format is not a valid array element type, so normalize the request
# at the array boundary. `Vector{Binary{…}}(undef, n)` cannot be intercepted and
# will still produce an abstract eltype — `format(K,P,Σ,Δ)` is the advertised
# route for that case.
#
# BOTH arities are needed, and the two-argument one is the one that matters:
# `Base.similar(a::AbstractArray, ::Type{T})` does NOT funnel through the
# three-argument method for every container — `Array` reaches
# `Array{S,N}(undef, size(a))` directly — so a three-argument-only normalization
# is silently bypassed for exactly the container people use. Found by test, not
# by reading.
# SCOPED TO THE `Array` FAMILY ON PURPOSE (§11 M13).
#
# The natural spelling — a method on `AbstractArray` — is more specific in the
# element-type slot and less specific in the container slot than every
# container-specialized `similar` in Base and the stdlibs, so it is ambiguous
# with all of them: `Diagonal`, `Hermitian`, `SymTridiagonal`, the triangulars,
# `Adjoint`/`Transpose`, `ReinterpretArray`, … That set is open-ended — any
# package defining `similar(::MyArray, ::Type{T})` adds another — so chasing it
# with more methods does not terminate, and Aqua's ambiguity gate is in the
# suite.
#
# `Array`, `Vector` and `Matrix` are what this package's own kernels and
# `similar(A, fr)` calls actually use, and shadowing exactly Base's three
# specializations there is closed and ambiguity-free. Anything else keeps stock
# Base behaviour, which fails loudly on an abstract element type — the correct
# outcome, since `format(K,P,Σ,Δ)` and the aliases are the supported route.
Base.similar(A::Vector{T}, ::Type{Binary{K,P,S,E}}) where {T,K,P,S,E} =
    similar(A, reptype(Binary{K,P,S,E}))
Base.similar(A::Matrix{T}, ::Type{Binary{K,P,S,E}}) where {T,K,P,S,E} =
    similar(A, reptype(Binary{K,P,S,E}))
Base.similar(A::Array, ::Type{Binary{K,P,S,E}}, dims::Base.Dims{N}) where {K,P,S,E,N} =
    similar(A, reptype(Binary{K,P,S,E}), dims)

# Print fully-instantiated formats by their draft name; 
#   anything else (UnionAlls, TypeVar-parameterized types
#   met during stacktrace printing) defers to Base —
# a parametric `::Type{Binary{K,P,S,E}}` method here can be
#   handed unbound static parameters by the printing machinery
#   and crash (found by test).

_fully_instantiated(T) =
    T isa DataType && length(T.parameters) == 4 &&
    T.parameters[1] isa Int && T.parameters[2] isa Int &&
    T.parameters[3] isa Bool && T.parameters[4] isa Bool

#=
function Base.show(io::IO, T::Type{<:Binary})
    if _fully_instantiated(T)
        print(io, formatname(T))
        # The format and its representation must not print identically:
        # the difference between them is exactly what an error about 
        # `similar`, `eltype` or a failed `===` needs to communicate.
        isabstracttype(T) && print(io, "{format}")
    else # this case was found in testing
        invoke(show, Tuple{IO,Type}, io, T)
    end
end
function Base.show(io::IO, v::Binary)
    T = typeof(v)
    d = decode(v)
    print(io, formatname(T), "(")
    isnan(d) ? print(io, "NaN") : print(io, _shortdatum(T, d))
    print(io, " ≡ 0x", string(codepoint(v); base=16, pad=2 * sizeof(codeunit_type(T))), ")")
end
=#

# A datum has at most `P ≤ 16` significant bits, but a `BigFloat` carries its own
# precision — and `ldexp` returns one at the MPFR *default*, 256 bits — so the
# eight Group C formats would otherwise print ~78 decimal digits to express a
# one-bit significand. Rebuilding at the format's precision is exact (the datum
# fits in `P` bits by construction) and is what makes the shortest-round-trip
# printer produce the short answer. Display only: `decode` keeps the wide
# precision, because a decoded datum goes on to be *computed with*.
@inline _shortdatum(::Type{F}, d) where {F<:Binary} = d
@inline _shortdatum(::Type{F}, d::BigFloat) where {F<:Binary} =
    BigFloat(d; precision = max(2, precision(F)))

# ---- Base numeric API on the type (defined via Group M / decode; see also ops_scalar.jl)
Base.zero(T::Type{<:Binary}) = rawvalue(T, 0x00)
Base.zero(::T) where {T<:Binary} = zero(T)
Base.iszero(v::Binary) = codepoint(v) == 0x00
Base.typemax(T::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} =
    E ? rawvalue(T, posinf_code(T)) : MaxFiniteOf(T)
Base.typemin(T::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} =
    S ? (E ? rawvalue(T, neginf_code(T)) : MinFiniteOf(T)) : zero(T)
Base.floatmax(T::Type{<:Binary}) = MaxFiniteOf(T)
Base.floatmin(T::Type{<:Binary}) = MinNormalOf(T)
Base.eps(T::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = T(2.0^(1 - P))

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

# Promotion (design §2.4; §2 R-E): `Binary ⋄ external` promotes to the format's
# **promotion carrier**, not to `Float64`; no automatic promotion between distinct
# Binary formats.
#
# `Float64` was right for every K ≤ 8 format and silently wrong above it: a
# B = 32 768 datum has no Float64 representation at all, so `x + 1.0` would have
# promoted to a carrier that cannot hold `x` and produced ±Inf or 0.0 from a
# perfectly ordinary value. The target is `promotecarrier(F)` — deliberately the
# PUBLIC carrier trait rather than `datumcarrier`, because the promoted type owes
# a caller the whole `Real` interface, which an internal carrier (`Dyadic`, from
# Stage 7) does not implement.
#
# `promote_rule` is inherently type-returning and is resolved by the compiler at
# the type level, so it is an explicit carve-out from the "no trait returns a
# Type from a branch" rule (invariant 9) — but it is still *derived from a
# trait*, never computed at a call site, which is what that rule is protecting.
#
# The signatures take `::Type{F} where {F<:Binary}` rather than `::Type{<:Binary}`
# because the carrier is a function of the format's parameters: the abstract form
# has none to read (invariant 8's concern, in the one place promotion touches it).
Base.promote_rule(::Type{F}, ::Type{Float64}) where {F<:Binary} = promotecarrier(F)
Base.promote_rule(::Type{F}, ::Type{Float32}) where {F<:Binary} = promotecarrier(F)
Base.promote_rule(::Type{F}, ::Type{Float16}) where {F<:Binary} = promotecarrier(F)
Base.promote_rule(::Type{F}, ::Type{BFloat16}) where {F<:Binary} = promotecarrier(F)
Base.promote_rule(::Type{F}, ::Type{<:Integer}) where {F<:Binary} = promotecarrier(F)
# The two wide carriers themselves: a narrow format meeting a `Float128` must not
# come back down to `Float64`. `joinfloat` takes the wider of the two, so the
# result holds both operands exactly.
Base.promote_rule(::Type{F}, ::Type{Float128}) where {F<:Binary} =
    _joinfloat(promotecarrier(F), Float128)
Base.promote_rule(::Type{F}, ::Type{BigFloat}) where {F<:Binary} = BigFloat
@inline _joinfloat(::Type{BigFloat}, ::Type{<:AbstractFloat}) = BigFloat
@inline _joinfloat(::Type{Float128}, ::Type{Float128}) = Float128
@inline _joinfloat(::Type{Float64}, ::Type{Float128}) = Float128
# The three external-float conversions are ROUNDING conversions, in the ordinary
# Julia sense: `Float32(x)` means "give me the nearest Float32". They were exact
# for every K ≤ 8 format and are still exact for every format where
# `datumsexact` holds — but that is now a property to be *queried*, not a promise
# the constructor makes. `decode(v)` is the exact route and returns the format's
# own carrier; `decode!` is the bulk route and refuses rather than rounds.
#
# Note `Float64(v)` in particular: it can no longer be `decode(v)`, because for
# 72 of the 504 formats that returns a `Float128` or a `BigFloat` and a method
# named `Float64` must return a `Float64`.
Base.Float64(v::Binary) = Float64(decode(v))
Base.Float32(v::Binary) = _tofloat32(decodepolicy(typeof(v)), v)
# K ≤ KSPLIT keeps the direct gather of the narrowed table — bit-identical to
# `Float32(decode(v))` and asserted so exhaustively.
@inline _tofloat32(::TableDecode, v::Binary) =
    @inbounds _decode_table32(typeof(v))[Int(codepoint(v)) + 1]
@inline _tofloat32(::ComputeDecode, v::Binary) = Float32(decode(v))
(::Type{BFloat16})(v::Binary) = BFloat16(Float64(v))
# `Float16` was the one external width with no outbound row, which is an omission
# and not a decision: `Convert` accepts it as an *input*, `ExactExternalFloat`
# names it, `promote_rule` targets `promotecarrier(F)` for it, and `binary16` is
# an alias for it at the top of the package. Gate G10 found it at every one of
# the 504 formats — it was never a wide-format defect, just an untested verb.
#
# Routed through `Float64` like `BFloat16` above rather than through `decode`:
# `Float64(v)` is exact for every format (P ≤ 16 significand bits), so the
# narrowing to `Float16` is a single rounding.
(::Type{Float16})(v::Binary) = Float16(Float64(v))
# The two wide carriers. `promote_rule` names them as targets, so promotion needs
# the conversions to exist — `x + 1.0` on a rung-2 or rung-3 format resolves to
# `+(::Float128, ::Float128)` or `+(::BigFloat, ::BigFloat)` and gets here.
#
# `BigFloat` is EXACT for every format at any ambient precision ≥ 16 bits (a
# datum's significand is at most P ≤ 16 bits, and MPFR's exponent range covers
# every B). `Float128` is a rounding conversion in the ordinary Julia sense, like
# `Float32(x)` above: exact wherever `datumsexact(Float128, F)` holds and
# overflowing to ±Inf beyond it. Only the first is reachable by promotion from a
# format that needs it, because `promotecarrier` never names `Float128` for a
# format whose datums exceed it.
(::Type{Float128})(v::Binary) = Float128(decode(v))
Base.BigFloat(v::Binary) = BigFloat(decode(v))
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
