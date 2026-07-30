# ===== test/tier_t2.jl — T2: the projection engine against an exact-rational oracle
#
# The verification doctrine's tier T2 (§6.2 of the plan), with the domains the
# plan corrects: **T2 splits**, because rounding and saturation have different
# natural parameter spaces and folding them together loses that.
#
#   T2a — `round_to_precision` is a function of `(P, B, μ, X, R)` and of nothing
#         else. It never sees a format. Its parameter space is therefore the
#         **135 realized `(P, B)` cells**, not the 504 formats: `Binary16p6se`
#         and `Binary16p6uf` differ in Σ and Δ, which rounding does not consult.
#         Sweeping formats here would run every cell up to four times and call it
#         four times the coverage.
#
#   T2b — `saturate` is where Σ and Δ enter, so its parameter space IS the
#         **504 `(P, B, Σ, Δ)` tuples**. Whether an overflow becomes `Inf`, the
#         largest finite, or NaN is a question about the format's domain and
#         signedness, and it is the only question in the pipeline that is.
#
# ---- why the oracle is `Rational{BigInt}` and not a wider float.
#
# Every other oracle in this suite is a wider carrier: MPFR at a derived
# precision, `Float128` behind a width filter, the retired `BigFloat` behind G7.
# Each is valid only while its carrier is wide enough, and G2 exists because a
# 2 200-bit accumulator was NOT wide enough for 50 of the 504 formats — and did
# not say so, it returned a plausible wrong number.
#
# `refimpl` has no precision to be insufficient. A P3109 datum is a dyadic
# rational; every value here is exact by construction and every comparison is a
# decision rather than an estimate. That is what makes it the right oracle for
# the tier that decides whether the engine rounds correctly, and it is why the
# plan makes promoting it out of manual-only status a Stage 8 requirement.
#
# ---- what the comparison is, on each side.
#
# T2a compares the `Rounded` triple `(sign, S, Q)` — the engine's own
# intermediate, before any format is involved. T2b compares the **value** a code
# point carries, not the code point: `encode` is already exhaustive at every K in
# the T1 lattice sweep, so folding it in here would test it twice and would let
# an `encode` defect present as a saturation failure.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: _NAMED, precision, expbias, bitwidth, issigned, isextended,
                   round_to_precision, project, codepoint, rawvalue,
                   codeunit_type, nan_code, KIND_FIN, KIND_NAN, KIND_PINF,
                   KIND_NINF, nrandbits, MaxFiniteOf, MinFiniteOf, Dyadic

isdefined(@__MODULE__, :refround) || include("refimpl.jl")
isdefined(@__MODULE__, :REPRESENTATIVE) || include("formatsel.jl")
isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

_F(nm) = _NAMED[nm]::Type{<:Binary}     # the registry, not the export surface
const _ALL_T2 = sort!(collect(keys(_NAMED)))

# The nine rounding modes and the three saturation modes, named once. The `27 ρ`
# the plan quotes is their product; T2a needs only the first list, because
# saturation cannot reach `round_to_precision`.
const _MODES = (NearestTiesToEven(), NearestTiesToAway(), TowardPositive(),
                TowardNegative(), TowardZero(), ToOdd(),
                StochasticA{4}(), StochasticB{4}(), StochasticC{4}())
const _SATS = (SatNone(), SatFinite(), SatPropagate())

# `is_stochastic` is spelled here rather than imported: the package has no single
# abstract type for the three variants (they are separate structs under
# `RoundingMode3109`), and inventing one in `src/` to make a test read better
# would be the test dictating the design.
_is_stochastic(μ) = μ isa StochasticA || μ isa StochasticB || μ isa StochasticC

# ---------------------------------------------------------------------------
# T2a — round_to_precision over the 135 (P, B) cells
# ---------------------------------------------------------------------------
#
# The value set is built from the DECISION STRUCTURE rather than sampled: for a
# lattice point `S · 2^Q`, `refround` decides on `ν = X/2^Q − ⌊X/2^Q⌋` against
# the constants {0, ½, 1}. So the offsets below are chosen to land exactly on
# each of those and just off them on both sides, which is where every mode's
# behaviour differs from every other's. A random value set would hit the ties —
# the only place `NearestTiesToEven` and `NearestTiesToAway` disagree — with
# probability zero.
#
# `HALFISH` steps off a tie by one part in 2^20, far enough that no carrier
# rounds it back onto the tie and close enough that nothing else changes.
const _EIGHTH = RQ(1, 8)
const _OFFSETS = (RQ(0),                       # exact datum: no rounding at all
                  RQ(1, 4),                    # below the tie
                  RQ(1, 2) - RQ(1, 1 << 20),   # just below the tie
                  RQ(1, 2),                    # the tie itself
                  RQ(1, 2) + RQ(1, 1 << 20),   # just above the tie
                  RQ(3, 4),                    # above the tie
                  RQ(1) - RQ(1, 1 << 20))      # just below the next datum

"""An exact `BigFloat` for a dyadic rational, at a precision derived from the
value rather than the ambient setting, with the exactness ASSERTED rather than
assumed.

Both T2 sweeps need it for the same reason: the engine takes a carrier value and
the oracle takes a rational, so a lossy conversion between them would show up as
an engine defect. Every value either sweep constructs is dyadic by design — a
lattice point, a power-of-two offset from one, or a power-of-two multiple — so
the conversion is exact and the assertion is a statement about the test's own
value set, not about the engine."""
function exact_bigfloat(q::RQ)
    n = numerator(q); d = denominator(q)
    @assert ispow2(d) "T2 value $q is not dyadic — no float carrier represents it exactly"
    prec = max(ndigits(abs(n); base=2) + 2, 64)
    b = setprecision(() -> BigFloat(n) / BigFloat(d), BigFloat, prec)
    @assert exact_rq(b) == q "T2 operand $q lost bits in the BigFloat carrier"
    b
end

"""Lattice points of the `(P, B)` cell that a rounding decision can turn on: the
subnormal floor, the subnormal/normal boundary, a mid-range normal, and the
largest finite. Returned as `(S, Q)` pairs in the engine's own normalization."""
function _cellpoints(P::Int, B::Int)
    Qmin = 1 - B - P + 1                       # the subnormal exponent
    Qmax = B - P + 1                           # the exponent of the largest finite
    Smin = big(1) << (P - 1)                   # smallest normal significand
    Smax = (big(1) << P) - 1                   # largest significand
    pts = Tuple{BigInt,Int}[]
    push!(pts, (big(1), Qmin))                 # smallest positive subnormal
    push!(pts, (big(3), Qmin))                 # a subnormal with room below it
    push!(pts, (Smax, Qmin))                   # largest subnormal
    push!(pts, (Smin, Qmin + 1))               # smallest normal
    P > 1 && push!(pts, (Smin + 1, (Qmin + Qmax) ÷ 2))   # a mid-range normal
    push!(pts, (Smax, (Qmin + Qmax) ÷ 2))
    push!(pts, (Smax, Qmax))                   # largest finite
    unique(pts)
end

@testset "T2a — round_to_precision ≡ Rational{BigInt} oracle (135 (P,B) cells)" begin
    cells = sort!(unique((precision(_F(nm)), expbias(_F(nm))) for nm in _ALL_T2))
    @test length(cells) == 135
    compared = Ref(0)
    for (P, B) in cells
        bad = Tuple{Int,Int,Symbol,String,Int,NTuple{3,Any},NTuple{3,Any}}[]
        for (S, Q) in _cellpoints(P, B), off in _OFFSETS, sgn in (1, -1)
            Xq = sgn * (RQ(S) + off) * pow2r(Q)
            # The engine takes a carrier value; the oracle takes the rational.
            # `BigFloat` at a precision derived from the value is EXACT for every
            # `Xq` here (each is a dyadic rational of at most P + 21 bits), so the
            # two sides receive the same number and the comparison is of the
            # rounding, not of a conversion.
            Xb = exact_bigfloat(Xq)
            for μ in _MODES
                Rs = _is_stochastic(μ) ?
                     (0, 1, (1 << nrandbits(μ)) ÷ 2, (1 << nrandbits(μ)) - 1) : (0,)
                for R in Rs
                    got = round_to_precision(P, B, μ, Xb, R, 0)
                    want = refround(P, B, μ, R, Xq)
                    compared[] += 1
                    gt = (Int(got.sign), BigInt(got.S), Int(got.Q))
                    # The oracle normalizes a zero result to (sgn, 0, Q); the
                    # engine normalizes it to (+1, 0, 0). Same datum — the draft
                    # has ONE zero — so compare on the datum, not the triple.
                    if want[2] == 0
                        (got.kind == KIND_FIN && got.S == 0) && continue
                    elseif gt == (want[1], want[2], want[3]) && got.kind == KIND_FIN
                        continue
                    end
                    push!(bad, (P, B, nameof(typeof(μ)), string(Xq), R,
                                gt, (want[1], want[2], want[3])))
                end
            end
        end
        @test (P, B, bad) == (P, B, eltype(bad)[])
    end
    record_gate!("T2a"; assertions=length(cells) + 1, units=compared[],
                 exhaustive=true)
    @info "T2a: $(compared[]) round_to_precision decisions over $(length(cells)) " *
          "(P, B) cells × $(length(_MODES)) rounding modes × $(length(_OFFSETS)) " *
          "structured offsets, against Rational{BigInt} — exhaustive over the " *
          "cells, and over the decision boundaries within each"
end

# ---------------------------------------------------------------------------
# T2b — saturation over the 504 (P, B, Σ, Δ) tuples
# ---------------------------------------------------------------------------
#
# The value set here is chosen at the SATURATION boundaries rather than the
# rounding ones: inside the finite range, exactly on each end of it, just past
# each end, far past each end, and the three specials. Whether the answer is
# `Inf`, the largest finite, or NaN is decided by Σ and Δ together with the
# rounding mode's direction, and those interactions are the whole content of the
# ωSaturate rows.
@testset "T2b — saturate ≡ Rational{BigInt} oracle" begin
    @test length(_ALL_T2) == 504
    # The format axis is the expensive one and it is tiered, for the reason
    # `formatsel.jl` measures: 20 formats × 27 ρ cost 21.5 s cold and 0.0 s warm,
    # so all 504 is ≈ 9 minutes of pure specialization. The shipped run takes one
    # representative per realized cell and SAYS so; `SmallFloats_EXHAUSTIVE=1`
    # takes all of them.
    fmts, coverage = sweep_formats("T2b")
    compared = Ref(0)
    for nm in fmts
        T = _F(nm)
        P = precision(T); B = expbias(T)
        mhi = datum_rq(MaxFiniteOf(T)); mlo = datum_rq(MinFiniteOf(T))
        # Every probe is DYADIC, built from the top ulp `2^Qmax` rather than from
        # fractions of the range: the engine takes a carrier value, so a probe no
        # float represents exactly would test the conversion instead of the
        # saturation. `half` is the tie at the overflow boundary — the one place
        # `NearestTiesToEven` and `NearestTiesToAway` can disagree about whether
        # a value overflows at all, and therefore the probe that matters most.
        ulp = pow2r(B - P + 1)
        half = ulp / 2
        vals = Any[mhi, mlo,                        # exactly the ends
                   mhi + half, mlo - half,          # the overflow TIE, both signs
                   mhi + ulp, mlo - ulp,            # one ulp past both ends
                   mhi * 2, mlo * 2,                # comfortably past both
                   mhi * pow2r(40), mlo * pow2r(40),# far past
                   mhi / 2,                         # strictly inside: no saturation
                   RQ(0), Inf, -Inf, NaN]
        bad = Tuple{Symbol,String,String,Any,Any}[]
        # The carrier conversion is hoisted out of the ρ loop: it is a property of
        # the value, not of the projection spec, and `exact_bigfloat` is BigInt
        # work at a `B = 32 768` format. Recomputing it 27 times per probe was
        # most of this sweep's first measured runtime.
        for X in vals
            Xc = X isa Float64 ? X : exact_bigfloat(X::RQ)
            Xr = X isa Float64 ? X : X::RQ
            for μ in _MODES, sat in _SATS
                ρ = ProjSpec(μ, sat)
                Rs = _is_stochastic(μ) ? (0, (1 << nrandbits(μ)) - 1) : (0,)
                for R in Rs
                    got = code_value(project(T, ρ, Xc; R))
                    want = refsaturate(T, ρ, Xr; R)
                    compared[] += 1
                    got == want && continue
                    push!(bad, (nm, string(nameof(typeof(μ))) * "/" *
                                    string(nameof(typeof(sat))),
                                string(X), got, want))
                end
            end
        end
        @test (nm, bad) == (nm, eltype(bad)[])
    end
    record_gate!("T2b"; assertions=length(fmts) + 1, units=compared[],
                 exhaustive=exhaustive_requested(),
                 note="format axis: $coverage")
    @info "T2b: $(compared[]) saturation decisions over $(length(fmts)) " *
          "(P, B, Σ, Δ) tuples × $(length(_MODES) * length(_SATS)) ρ — every ρ at " *
          "every format, compared as VALUES against Rational{BigInt} (encode is " *
          "T1's, exhaustively). Format axis: $coverage"
end
