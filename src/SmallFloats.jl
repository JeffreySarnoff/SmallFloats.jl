# ===== SmallFloats.jl — module root (design §10.1, architecture §11)
"""
    SmallFloats

A conforming, performance-oriented Julia implementation of the IEEE P3109 draft
standard for arithmetic formats for machine learning (bitwidths 3–16).

Bit-exact defined results on every default path; the projection engine
(`RoundToPrecision → Saturate → Encode`) is the single write path into a code
point; approximate fast paths exist only behind the explicit κ registry
(`register_approx!` / `approx`), never substituted silently. See
`conformance()` for the live declaration and `SmallFloats.draft_revision()` for
the implemented draft.

# Performance note
Pass format types through `const` bindings, type parameters, or function
arguments. All exported entry points fully specialize when the format type is
statically known; the checked-in benchmark report records current timings and
allocations. Calling through a **non-`const` global** format type forces
dynamic dispatch on every call; this is Julia semantics, not package overhead.
A single function barrier
(`f(::Type{T}, args...) where {T}`) restores full speed. The test suite pins
the specialization properties (concrete return types, zero warm-path
allocation) as deterministic regressions.
"""
module SmallFloats

const binary16 = Float16
const binary32 = Float32
const binary64 = Float64

using Random: Random, AbstractRNG, default_rng
using PrecompileTools: @setup_workload, @compile_workload
using Quadmath: Float128
using BFloat16s: BFloat16

# `dyadic.jl` loads FIRST and has zero SmallFloats dependencies (§4 Stage 7): the
# rung-3 exact carrier must be checkable on its own terms, with no reach into a
# format, a trait, or a projection.
include("dyadic.jl")
using .DyadicNumbers: Dyadic, DyadicNumbers

include("fma128.jl")
using .Float128FMA          # on Windows this installs Base.fma

include("faa128.jl")
using .Float128FAA

# Include order: formats → show → carriers → projspec → defaults →
# decode_encode → project → ops_scalar → juliacompat → oracle → tables →
# kernels → blocks → packed → approx → rand.
#
# `show.jl` sits directly after `formats.jl` because it needs `formatname`,
# `codeunit_type` and `_shortdatum` and nothing later; putting the display layer
# early also keeps it available to every subsequent file's error paths, which is
# the property `stage_gates.jl` pins ("`show` must never be the thing that
# throws").
# (One deliberate delta from the architecture §11 listing: the evaluation-protocol
# structs BigExactF/EncloseF live in ops_scalar.jl per §6, so ops_scalar precedes
# oracle; oracle's references to them are function-body-late-bound either way, but
# this is the order the harnesses verified.)
#
# `carriers.jl` follows `formats.jl` because its trait signatures are bounded by
# `Binary`, which a `where` clause resolves at method-definition time. It owns
# the second of the two axes: `formats.jl` decides how a code point is *stored*
# (a function of K), `carriers.jl` decides what holds a datum in *flight* (a
# function of the exponent bias B). Keeping them in separate files is what makes
# "the carrier is a property of values in flight, not of formats at rest"
# checkable rather than merely stated.
include("formats.jl")
include("show.jl")
include("carriers.jl")
include("projspec.jl")
include("defaults.jl")
include("decode_encode.jl")
include("project.jl")
include("ops_scalar.jl")
include("juliacompat.jl")
include("oracle.jl")
include("tables.jl")
include("kernels.jl")
include("blocks.jl")
include("packed.jl")
include("approx.jl")
include("rand.jl")

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
# ---- the format aliases: 504 defined, 120 exported, all 504 opt-in.
#
# **Decision (Stage 9 item 1, open item O3), settled by asymmetric
# reversibility: exporting more later is non-breaking, un-exporting is not.**
#
# Every one of the 504 aliases is DEFINED in `SmallFloats` and reachable as
# `SmallFloats.Binary16p6se`. What `using SmallFloats` puts in `Main` is the
# **120 names at K ≤ 8** — exactly what it put there before the extension, so no
# existing program changes meaning. The other 384 arrive only if asked for:
#
#     using SmallFloats.Formats      # all 504 names in Main
#
# Three reasons this is the narrow default rather than the wide one.
#
# *It is the only direction that stays open.* Exporting the remaining 384 later
# is a non-breaking minor change. Un-exporting them after a release is breaking,
# and the window to choose closes at that release rather than at this commit.
#
# *384 new names in `Main` is a name-collision surface, not a convenience.*
# `Binary10p5se` is unlikely to clash; the point is that a user cannot opt out of
# a package's exports, only avoid the package.
#
# *The programmatic route is better anyway for the wide grid.* `format(K,P,Σ,Δ)`
# is a `Dict` lookup returning the concrete type, and code that walks a grid of
# 504 formats wants that, not 504 spelled names. It is exported below for the
# first time — its own docstring already called it "the supported replacement for
# spelling `Binary{K,P,Σ,Δ}`", which an unexported binding could not be.
export Binary
for n in sort!(collect(keys(_NAMED)))
    bitwidth(_NAMED[n]) <= KSPLIT && @eval export $n
end

"""
    SmallFloats.Formats

Opt-in namespace re-exporting **all 504** draft §3.2 format aliases.

`using SmallFloats` exports the 120 names at K ≤ 8, unchanged from before the
K ≤ 16 extension. `using SmallFloats.Formats` adds the other 384:

```julia
using SmallFloats            # Binary8p4se — exported
using SmallFloats.Formats    # Binary16p6se — now exported too
```

Every alias is defined in `SmallFloats` either way, so
`SmallFloats.Binary16p6se` works without this module. Prefer
[`format`](@ref)`(K, P, Σ, Δ)` when the parameters are runtime values.
"""
module Formats

import ..SmallFloats
for n in sort!(collect(keys(SmallFloats._NAMED)))
    @eval using ..SmallFloats: $n
    @eval export $n
end

end # module Formats

export binary64, binary32, binary16

# Group M and format introspection
export Binary,
       bitwidth, issigned, isextended, expbias, expbitwidth, trailingsigbits,
       BitwidthOf, PrecisionOf, SignednessOf, DomainOf, ExponentBiasOf,
       ExponentBitwidthOf, TrailingSignificandBitwidthOf,
       MaxFiniteOf, MinFiniteOf, MinPositiveOf, MaxSubnormalOf, MinNormalOf,
       maxfinite_datum, minfinite_datum, formatname, decode, decode!,  # codepoint extends Base
       format, reptype, codeunit_type

# control the display of Binary datum
export VALID_SHOW_STYLES, set_show_style!, get_show_style

# projection specifications
export RoundingMode3109, NearestTiesToEven, NearestTiesToAway, TowardPositive,
       TowardNegative, TowardZero, ToOdd, StochasticA, StochasticB, StochasticC,
       SaturationMode, SatFinite, SatPropagate, SatNone,
       ProjSpec, RoundOf, SatOf, roundingmode, saturationmode,
       isstochastic, nrandbits,
       RNE_SF, RNE_SP, RNE_SN,
       RNA_SF, RNA_SP, RNA_SN,
       RTP_SF, RTP_SP, RTP_SN,
       RTN_SF, RTN_SP, RTN_SN,
       RTZ_SF, RTZ_SP, RTZ_SN,
       RTO_SF, RTO_SP, RTO_SN,
       RSA_SF, RSA_SP, RSA_SN,
       RSB_SF, RSB_SP, RSB_SN,
       RSC_SF, RSC_SP, RSC_SN,
       default_projspec, projmode,
       DeterministicRoundingMode, DirectedRoundingMode, 
       NearestRoundingMode, StochasticRoundingMode, FaithfulRoundingMode,
       SaturationMode
       
# session defaults (defaults.jl)
export DefaultType, DefaultType!,
       DefaultReturnType, DefaultReturnType!,
       DefaultRoundingMode, DefaultRoundingMode!,
       DefaultSaturationMode, DefaultSaturationMode!,
       DefaultProjection, DefaultProjection!,
       with_default_type, with_default_returntype, with_default_projection

# comparison, classification, stepping (Groups D/M)
export TotalOrder, Class, FPClass,
       ClassNaN, ClassNegInf, ClassNegNormal, ClassNegSubnormal, ClassZero,
       ClassPosSubnormal, ClassPosNormal, ClassPosInf,
       NextGreaterThan, NextLessThan

# the spec register: every draft operation (scalar + array methods)
for op in OP_REGISTRY
    @eval export $(op.name)
end
export vmap, vmap!, Op          # `Op` makes the register callable: map(Op(:Add,T,ρ), A, B)

# table cache introspection
export table_bytes, table_count, ternary_count, table_policy, empty_tables!

# Float32 carrier-exactness trait (tables.jl)
export f32_exact

# blocks and scaled operations
export Block, BlockVector, blocksize, scaleformat, elemformat, PackedVector
for op in OP_REGISTRY
    op.name === :Convert && continue
    @eval export $(Symbol(:Block, op.name))
    @eval export $(Symbol(:Scaled, op.name))
end
export BlockReduceAdd, BlockReduceMultiply, BlockDotProduct,
       ConvertFromBlock, ConvertToBlock, ConvertToBlockMaxAbsFinite

# conformance and κ-approximation
export conformance, conformance_dict, conformance_report, draft_revision, draft_identity,
       ConformanceDeclaration, ApproxImpl,
       measure_kappa, codedistance, register_approx!, unregister_approx!,
       approx, kappa, kappa_measured, list_approx, ftz_variant,
       f32_impl, register_f32!


# inclusions


# ---------------------------------------------------------------------------
# Tier-1 precompile workload (design §7.2): the standard profile's hot entries
# compile during precompilation; everything else specializes lazily on first use.
# ---------------------------------------------------------------------------
@setup_workload begin
    @compile_workload begin
        T = Binary8p4se; S = Binary8p3se
        a, b = T(1.5), T(0.25)
        Add(T, RNE_SN, a, b); Multiply(T, RNE_SF, a, b)
        Exp(T, RNE_SN, a); Convert(S, RNE_SN, a)
        a + b; exp(b); fma(a, b, a); min(a, b)
        get_table(:Exp, T, T, RNE_SN)
        A = [a, b, a, b]; B = [b, a, b, a]; d = similar(A)
        vmap!(d, Val(:Add), T, RNE_SN, A, B)
        vmap!(d, Val(:Exp), T, RNE_SN, A)
        ScaledAdd(T, RNE_SN, one(S), a, one(S), b)
        bx = Block(one(S), (a, b, a, b)); by = Block(one(S), (b, a, b, a))
        BlockDotProduct(T, RNE_SN, bx, by)
        BlockAdd(T, RNE_SN, bx, by, one(S))

        # ---- exactly one wide format per carrier, and no more.
        #
        # The image must not grow with the grid: 504 formats × the operation
        # register would be an enormous workload for paths most users never take.
        # But the wide carriers are *new code*, and leaving them entirely
        # uncompiled means the first wide call in a session pays for the whole
        # carrier lattice — measured at ≈ 1.8 s per format elsewhere in this
        # work, essentially all specialization.
        #
        # So: one representative at each rung above 1, one Group A operation and
        # one Group B, which is what forces `decode`'s wide path, `lift`, the
        # per-head `ωeval` rows, the enclosure ladder, and `project`'s generic
        # `_rab` family to exist. Adding a second format at the same rung
        # compiles the same methods again for a different type parameter and buys
        # nothing.
        W2 = Binary16p5se        # rung 2 — Float128 carrier
        W3 = Binary16p1uf        # rung 3 — Dyadic carrier (the MX scale shape)
        for WF in (W2, W3)
            w1 = WF(1.5); w2 = WF(0.25)
            Add(WF, RNE_SN, w1, w2)          # Group A, per-head ωeval
            Multiply(WF, RNE_SF, w1, w2)
            Exp(WF, RNE_SN, w1)              # Group B, the enclosure ladder
            Convert(T, RNE_SN, w1)           # wide → narrow, across the seam
            decode(w1); codepoint(w1); w1 < w2    # the veneers a user reaches first
        end

        empty_tables!()          # tables are cheap to rebuild; don't bloat the image
    end
end

function __init__()
    # Float128 revision plan §5: every Float128 path fronts a complete MPFR path
    # with identical semantics; the switch trades speed only, never results.
    if get(ENV, "SmallFloats_Float128", "") == "disable"
        _USE_FLOAT128[] = false
    end
    nothing
end

end # module
