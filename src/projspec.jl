# ===== projspec.jl — projection specifications as types (design §4, architecture §2)
#
# A projection specification ρ = (rounding mode, saturation mode) is a zero-size
# value whose *type* carries both modes, so kernels specialize on ρ exactly as
# they specialize on formats. The stochastic modes carry the random-bit budget N
# in the type: a kernel's randomness consumption is a compile-time fact, and
# pure-vs-stochastic dispatch is static (pure ⇒ tabulable, stochastic ⇒ never).

abstract type RoundingMode3109 end
abstract type StochasticRoundingMode    <: RoundingMode3109 end
abstract type DeterministicRoundingMode <: RoundingMode3109 end
abstract type NearestRoundingMode       <: DeterministicRoundingMode end
abstract type DirectedRoundingMode      <: DeterministicRoundingMode end
abstract type FaithfulRoundingMode      <: DeterministicRoundingMode end

"Round to nearest; ties to the even code point (IEEE default; draft §4.7.1)."
struct NearestTiesToEven <: NearestRoundingMode end
"Round to nearest; ties away from zero (draft §4.7.1)."
struct NearestTiesToAway <: NearestRoundingMode end
"Directed rounding toward +∞ (draft §4.7.2)."
struct TowardPositive    <: DirectedRoundingMode end
"Directed rounding toward −∞ (draft §4.7.2)."
struct TowardNegative    <: DirectedRoundingMode end
"Directed rounding toward zero — truncation (draft §4.7.2)."
struct TowardZero        <: DirectedRoundingMode end
"Round inexact results to the nearest *odd* code point (draft §4.7.3; sticky-friendly)."
struct ToOdd             <: FaithfulRoundingMode end

# Stochastic variants (draft §4.7.4): R random bits with 0 ≤ R < 2^N are supplied
# per projected element. N is capped at 60 so every predicate stays in Int64
# arithmetic (StochasticB shifts by N+1; see project.jl).
@inline function _check_nrandbits(N)
    (N isa Int && 1 <= N <= 60) ||
        throw(ArgumentError("stochastic rounding requires an Int random-bit budget N with 1 ≤ N ≤ 60 (got $N)"))
    nothing
end
"""Stochastic rounding, variant A of draft §4.7.4: RoundAway ⟺ ⌊ν·2^N⌋ + R ≥ 2^N."""
struct StochasticA{N} <: StochasticRoundingMode
    StochasticA{N}() where {N} = (_check_nrandbits(N); new{N}())
end
"""Stochastic rounding, variant B: RoundAway ⟺ ⌊ν·2^(N+1)⌋ + (2R+1) ≥ 2^(N+1)."""
struct StochasticB{N} <: StochasticRoundingMode
    StochasticB{N}() where {N} = (_check_nrandbits(N); new{N}())
end
"""Stochastic rounding, variant C: RoundAway ⟺ RNITE(ν·2^N) + R ≥ 2^N."""
struct StochasticC{N} <: StochasticRoundingMode
    StochasticC{N}() where {N} = (_check_nrandbits(N); new{N}())
end

# The supported vocabulary, declared once for conformance reporting. The type
# hierarchy owns classification; this descriptor owns stable external names.
# Do not discover these with `subtypes`: loaded third-party subtypes are not
# supported modes and must not silently enter the package's conformance claim.
const _ROUNDING_MODE_DECLARATIONS = (
    NearestTiesToEven => "NearestTiesToEven",
    NearestTiesToAway => "NearestTiesToAway",
    TowardPositive => "TowardPositive",
    TowardNegative => "TowardNegative",
    TowardZero => "TowardZero",
    ToOdd => "ToOdd",
    StochasticA => "StochasticA[N], 1 ≤ N ≤ 60",
    StochasticB => "StochasticB[N]",
    StochasticC => "StochasticC[N]",
)

abstract type SaturationMode end

struct SatFinite    <: SaturationMode end   # clamp everything to the finite range
struct SatPropagate <: SaturationMode end   # keep representable infinities, clamp the rest
struct SatNone      <: SaturationMode end   # draft's direction/signedness/domain-governed rows

const SaturationModes_NonSaturating = Union{SatNone}
const SaturationModes_Saturating = Union{SatFinite,SatPropagate}

const SaturationModes = Union{SatFinite,SatPropagate,SatNone}

"""
    ProjSpec{R<:RoundingMode3109, S<:SaturationMode}

A projection specification ρ = (rounding mode, saturation mode), draft §4.2.
Zero-size; construct as `ProjSpec(NearestTiesToEven(), SatNone())` or via the
exported constants. Kernels specialize on its type.
"""
struct ProjSpec{R<:RoundingMode3109,S<:SaturationMode} end

ProjSpec(::R, ::S) where {R<:RoundingMode3109,S<:SaturationMode} = ProjSpec{R,S}()

roundingmode(::ProjSpec{R,S}) where {R,S} = R()

saturationmode(::ProjSpec{R,S}) where {R,S} = S()

"""Draft-named accessor: RoundOf(ρ) — the rounding mode of ρ (§4.2)."""
const RoundOf = roundingmode
"""Draft-named accessor: SatOf(ρ) — the saturation mode of ρ (§4.2)."""
const SatOf = saturationmode

# ---- queries
isstochastic(::Type{<:RoundingMode3109}) = false
isstochastic(::Type{<:StochasticRoundingMode}) = true
isstochastic(m::RoundingMode3109) = isstochastic(typeof(m))
isstochastic(::ProjSpec{R,S}) where {R,S} = isstochastic(R)

"""Number of random bits N consumed per projected element; 0 for pure modes."""
nrandbits(::Type{<:RoundingMode3109}) = 0
nrandbits(::Type{StochasticA{N}}) where {N} = N
nrandbits(::Type{StochasticB{N}}) where {N} = N
nrandbits(::Type{StochasticC{N}}) where {N} = N
nrandbits(m::RoundingMode3109) = nrandbits(typeof(m))
nrandbits(::ProjSpec{R,S}) where {R,S} = nrandbits(R)

# ---- predefined projections
"""(NearestTiesToEven, SatFinite)."""
const RNE_SF    = ProjSpec{NearestTiesToEven, SatFinite}()
"""(NearestTiesToEven, SatPropagate)."""
const RNE_SP = ProjSpec{NearestTiesToEven, SatPropagate}()
"""(NearestTiesToEven, SatNone) — the package-wide default ρ."""
const RNE_SN      = ProjSpec{NearestTiesToEven, SatNone}()

"""(NearestTiesToAway, SatFinite)."""
const RNA_SF    = ProjSpec{NearestTiesToAway, SatFinite}()
"""(NearestTiesToAway, SatPropagate)."""
const RNA_SP = ProjSpec{NearestTiesToAway, SatPropagate}()
"""(NearestTiesToAway, SatNone)."""
const RNA_SN      = ProjSpec{NearestTiesToAway, SatNone}()

"""(TowardPositive, SatFinite)."""
const RTP_SF    = ProjSpec{TowardPositive, SatFinite}()
"""(TowardPositive, SatPropagate)."""
const RTP_SP = ProjSpec{TowardPositive, SatPropagate}()
"""(TowardPositive, SatNone)."""
const RTP_SN      = ProjSpec{TowardPositive, SatNone}()

"""(TowardNegative, SatFinite)."""
const RTN_SF    = ProjSpec{TowardNegative, SatFinite}()
"""(TowardNegative, SatPropagate)."""
const RTN_SP = ProjSpec{TowardNegative, SatPropagate}()
"""(TowardNegative, SatNone)."""
const RTN_SN      = ProjSpec{TowardNegative, SatNone}()

"""(TowardZero, SatFinite)."""
const RTZ_SF    = ProjSpec{TowardZero, SatFinite}()
"""(TowardZero, SatPropagate)."""
const RTZ_SP = ProjSpec{TowardZero, SatPropagate}()
"""(TowardZero, SatNone)."""
const RTZ_SN      = ProjSpec{TowardZero, SatNone}()

"""(ToOdd, SatFinite)."""
const RTO_SF    = ProjSpec{ToOdd, SatFinite}()
"""(ToOdd, SatPropagate)."""
const RTO_SP = ProjSpec{ToOdd, SatPropagate}()
"""(ToOdd, SatNone)."""
const RTO_SN      = ProjSpec{ToOdd, SatNone}()

"""Default random-bit budget used by no-argument stochastic projection constructors."""
const DEFAULT_RBITS = 8

# The nine stochastic (variant × saturation) constructor families were 27 hand-
# written methods differing only in two names. Generated from the grid instead,
# so a change to the constructor protocol — validation, the no-argument budget,
# the Val route — happens once and cannot apply unevenly across the nine.
#
# The saturation tag is carried as an explicit `mode => suffix` pair rather than
# derived from the type name, and that is the whole reason this loop is worth a
# comment. The short-name rename (`RSA_SatNone` → `RSA_SN`) renamed every
# hand-written `const` above and the export list, and could not see these:
# `Symbol(tag, :_, sat)` built `RSA_SatNone` from the *type* symbol, so the nine
# stochastic constructors kept their old names while `export` and every call site
# used the new ones. Julia exports an undefined name without complaint, so
# `RSA_SN` was **exported but not defined** and the failure surfaced only at the
# first call. Naming the suffix explicitly makes the generator visible to the
# next rename.
const _SAT_TAGS = ((:SatFinite => :SF), (:SatPropagate => :SP), (:SatNone => :SN))

for (tag, mode) in ((:RSA, :StochasticA), (:RSB, :StochasticB), (:RSC, :StochasticC)),
    (sat, suffix) in _SAT_TAGS

    ctor  = Symbol(tag, :_, suffix)
    alias = Symbol(ctor, :Type)
    @eval begin
        const $alias = ProjSpec{$mode{N}, $sat} where {N}
        $ctor() = $ctor(Val(DEFAULT_RBITS))
        $ctor(::Val{N}) where {N} = (_check_nrandbits(N); $alias{N}())
        $ctor(N::Int) = $ctor(Val(N))
    end
end

default_projspec(::Type{<:Binary}) = DefaultProjection()

# ---- Base.RoundingMode compatibility shim (API boundaries only)
"""
Translate a `Base.RoundingMode` to its `RoundingMode3109` counterpart (identity on the latter).
Used only at API boundaries.
Internals always carry RoundingMode3109.
"""
projmode(::RoundingMode{:Nearest})         = NearestTiesToEven()
projmode(::RoundingMode{:NearestTiesAway}) = NearestTiesToAway()
projmode(::RoundingMode{:Up})              = TowardPositive()
projmode(::RoundingMode{:Down})            = TowardNegative()
projmode(::RoundingMode{:ToZero})          = TowardZero()
projmode(m::RoundingMode3109)              = m

# ---- draft-style printing: "(NearestTiesToEven, SatNone)"
_modename(m) = String(nameof(typeof(m)))
_modename(::StochasticA{N}) where {N} = "StochasticA[$N]"
_modename(::StochasticB{N}) where {N} = "StochasticB[$N]"
_modename(::StochasticC{N}) where {N} = "StochasticC[$N]"
Base.show(io::IO, ρ::ProjSpec) =
    print(io, "(", _modename(roundingmode(ρ)), ", ", _modename(saturationmode(ρ)), ")")
