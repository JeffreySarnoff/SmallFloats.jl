# ===== test/tier_rho.jl — every ρ family at every rung, BY CONSTRUCTION
#
# Stage 8 step 4. The plan's wording is the specification: "**Every ρ family at
# every rung**, explicitly — stochastic × Group B and stochastic × Group C
# present by construction, not by random draw, because carrier-precision
# differences manifest on the stochastic sub-grid first."
#
# ---- why the stochastic sub-grid is where a carrier defect shows up first.
#
# A deterministic mode decides on ν against a constant in {0, ½, 1}. To get the
# answer wrong you need the carrier to be wrong about which side of one of three
# points ν falls on — and ν is usually nowhere near any of them, so a
# slightly-too-narrow carrier usually still produces the right code point. The
# defect hides.
#
# A stochastic mode decides on ⌊ν·2^N⌋ against R. That is 2^N decision points
# instead of three, spread uniformly across the interval, and ν is *always* near
# one of them. A carrier that is a few bits short changes ⌊ν·2^N⌋ and changes the
# answer. So the stochastic sub-grid is the sensitive instrument, and Group C —
# the enclosure ladder, where the value is transcendental and the carrier question
# is genuinely open — is where it should be pointed.
#
# ---- the oracle problem, and why this file needs no oracle.
#
# `refimpl` cannot serve here: a Group C result is not a rational, so there is no
# exact reference to compare against, and an MPFR reference at a derived precision
# is the very thing whose sufficiency is in question. Comparing against it would
# assume what we want to test.
#
# What is checkable *without* any oracle is the structure the draft's §4.7.4 gives
# the stochastic modes as functions of R:
#
#   1. **R = 0 collapses to truncation.** For StochasticA, RoundAway ⟺
#      ⌊ν·2^N⌋ + R ≥ 2^N. With R = 0 and ν < 1 this is ⌊ν·2^N⌋ ≥ 2^N, which is
#      never true. So StochasticA at R = 0 is *exactly* TowardZero, at every
#      format, for every operation, on every carrier — an identity between two
#      independently-implemented paths, with no reference value involved.
#
#   2. **Monotonicity in R.** RoundAway is monotone in R by inspection of all
#      three variants, so the projected magnitude is non-decreasing in R. A
#      carrier that mis-decides one R breaks the chain, and the break is visible
#      without knowing which answer was right.
#
#   3. **R at its maximum agrees with the away-rounding it implies.** For
#      StochasticA at R = 2^N − 1 the condition is ⌊ν·2^N⌋ ≥ 1, i.e. ν ≥ 2^−N.
#      That is not "any ν > 0", so this is asserted as an *implication* — if the
#      result differs from truncation then it is the away neighbour — rather than
#      as an equality with a named mode.
#
# These are exact, cheap, and — crucially — they are properties of the whole
# `decode → ωeval → project` pipeline, so they hold Group C's carrier to account
# at rung 2 and rung 3 where nothing else in the suite does.
#
# ---- and the cells are asserted non-empty.
#
# "By construction, not by random draw" is a claim about coverage, so the grid is
# enumerated and every cell is checked to have been visited. A cell that silently
# stops being realized changes the reported count.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: _NAMED, OP_REGISTRY, opinfo, rung, rungindex, _rungindex,
                   precision, expbias, bitwidth, codeunit_type, rawvalue,
                   codepoint, nrandbits, _EXACT_SELECTION, _EXACT_ARITH,
                   _LADDER_OPS, Binary

isdefined(@__MODULE__, :REPRESENTATIVE) || include("formatsel.jl")
isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

_ρF(nm) = _NAMED[nm]::Type{<:Binary}    # the registry, not the export surface

# The registry's own grouping, plus the classification this suite uses. Group C
# is the one this file exists for; `_LADDER_OPS` is the derived list, so a new
# transcendental joins the sweep without an edit here (invariant 7).
_opclass(nm) = nm in _EXACT_SELECTION ? :selection :
               nm in _EXACT_ARITH     ? :arith :
               nm === :Convert        ? :conv : :ladder

# One format per (rung, P-class) cell, taken from the DERIVED representative set
# rather than hand-listed, and reduced to the smallest set that still covers
# every rung — this file's cost is 52 operations × 8 ρ per format, so the format
# axis has to be narrow and the narrowing has to be principled.
function _rho_formats()
    seen = Set(); out = Symbol[]
    for nm in REPRESENTATIVE
        T = _ρF(nm)
        c = (_rungindex(T), precision(T) == 1)
        c in seen && continue
        push!(seen, c); push!(out, nm)
    end
    sort!(out)
end
const _RHO_FMTS = _rho_formats()

const _STOCH = (StochasticA{4}(), StochasticB{4}(), StochasticC{4}())
const _RHO_SATS = (SatNone(), SatFinite())

@testset "ρ × group × rung — every cell by construction" begin

    # ---- the grid, and the assertion that it is fully realized.
    cells = Set()
    for nm in _RHO_FMTS, o in OP_REGISTRY, μ in _STOCH
        push!(cells, (_rungindex(_ρF(nm)), _opclass(o.name), nameof(typeof(μ))))
    end
    # three rungs × four operation classes × three stochastic variants
    @test length(cells) == 3 * 4 * 3
    @test length(unique(_rungindex(_ρF(nm)) for nm in _RHO_FMTS)) == 3
    @test :ladder in Set(_opclass(o.name) for o in OP_REGISTRY)

    visited = Set()
    n_trunc = Ref(0); n_mono = Ref(0); n_away = Ref(0)

    for nm in _RHO_FMTS
        T = _ρF(nm); U = codeunit_type(T); n = 1 << bitwidth(T)
        r = _rungindex(T)
        # operands mid-lattice and at both ends, as code points so no format is
        # skipped for lacking a particular value
        vs = [rawvalue(T, U(c)) for c in unique(UInt64[1, 2, n ÷ 4, n ÷ 2 + 1, n - 2])]
        bad = Tuple{Symbol,Symbol,Symbol,Symbol,Any}[]
        for o in OP_REGISTRY
            f = getfield(SmallFloats, o.name); ar = o.arity
            cls = _opclass(o.name)
            for μ in _STOCH, sat in _RHO_SATS
                N = nrandbits(μ)
                ρs = ProjSpec(μ, sat)
                ρz = ProjSpec(TowardZero(), sat)
                push!(visited, (r, cls, nameof(typeof(μ))))
                # Magnitude as an exact ordinal: the order key of |x|, which is a
                # total order at every carrier and needs no decode-to-float. NaN
                # has no magnitude to compare — in an UNSIGNED format every
                # operation that produces a negative lands there, so it is a
                # normal outcome here and not a failure — and `nothing` is how
                # each check below declines rather than guesses.
                mag(c) = isnan(c) ? nothing :
                         SmallFloats.order_key(Abs(T, ProjSpec(TowardZero(), sat), c))

                for i in 1:min(length(vs), 3)
                    args = ar == 1 ? (vs[i],) :
                           ar == 2 ? (vs[i], vs[i + 1]) : (vs[i], vs[i + 1], vs[end])

                    # (1) R = 0 ⇒ truncation, for StochasticA under SatFinite.
                    #
                    # Both restrictions are the draft's, not convenience:
                    #
                    #   * StochasticB's condition is ⌊ν·2^(N+1)⌋ + (2R+1) ≥ 2^(N+1),
                    #     so R = 0 gives ν ≥ ½ − 2^−(N+1) — a nearest-like rule.
                    #     StochasticC's is RNITE(ν·2^N) + R ≥ 2^N, and RNITE can
                    #     carry to 2^N when ν > 1 − 2^−(N+1), so R = 0 rounds away
                    #     in the top sliver of the interval. Only variant A is
                    #     truncation at R = 0, and asserting it of the other two
                    #     would be asserting something false about §4.7.4.
                    #
                    #   * `SatNone` is the one saturation mode whose rows CONSULT
                    #     the rounding mode: an overflow saturates to the largest
                    #     finite under `TowardZero`/`TowardNegative` and becomes
                    #     ±Inf otherwise. So the two sides of this identity
                    #     legitimately differ on any operand that overflows, and
                    #     the identity is a statement about rounding, not about
                    #     saturation. `SatFinite`'s rows do not consult μ.
                    if μ isa StochasticA && sat isa SatFinite
                        a = f(T, ρs, args...; R=0)
                        b = f(T, ρz, args...)
                        n_trunc[] += 1
                        codepoint(a) == codepoint(b) ||
                            push!(bad, (nm, o.name, nameof(typeof(μ)), :R0_not_trunc,
                                        (UInt(codepoint(a)), UInt(codepoint(b)))))
                    end

                    # (2) monotone in R: |result| never decreases as R grows.
                    # Both sides carry the SAME ρ, so SatNone's μ-branch cannot
                    # split them and this holds at every saturation mode.
                    prev = nothing
                    for R in 0:(1 << N - 1)
                        m = mag(f(T, ρs, args...; R))
                        if prev !== nothing && m !== nothing
                            n_mono[] += 1
                            m >= prev ||
                                push!(bad, (nm, o.name, nameof(typeof(μ)), :not_monotone_in_R,
                                            (R, prev, m)))
                        end
                        m === nothing || (prev = m)
                    end

                    # (3) at R = 2^N − 1 the result is truncation or its away
                    # neighbour — never further, and never back toward zero.
                    # Restricted to SatFinite for (1)'s second reason.
                    if sat isa SatFinite
                        khi = mag(f(T, ρs, args...; R=(1 << N - 1)))
                        ktz = mag(f(T, ρz, args...))
                        if khi !== nothing && ktz !== nothing
                            n_away[] += 1
                            (khi == ktz || khi == ktz + 1) ||
                                push!(bad, (nm, o.name, nameof(typeof(μ)), :away_overshoot,
                                            (ktz, khi)))
                        end
                    end
                end
            end
        end
        @test (nm, bad) == (nm, eltype(bad)[])
    end

    # every cell the grid names was actually reached
    @test sort!(collect(visited)) == sort!(collect(cells))

    record_gate!("Tρ"; assertions=length(_RHO_FMTS) + 4,
                 units=n_trunc[] + n_mono[] + n_away[], exhaustive=false,
                 note="format axis sampled: $(length(_RHO_FMTS)) formats, one " *
                      "per (rung, P==1) cell, from the derived representative set")
    @info "ρ×rung: $(length(cells)) (rung, op-class, stochastic variant) cells, " *
          "all reached; $(n_trunc[]) R=0≡TowardZero identities, $(n_mono[]) " *
          "monotone-in-R steps, $(n_away[]) away-bound checks, over " *
          "$(length(_RHO_FMTS)) formats × $(length(OP_REGISTRY)) operations × " *
          "$(length(_STOCH) * length(_RHO_SATS)) stochastic ρ. No oracle: every " *
          "assertion is an identity or a monotonicity, which is why Group C at " *
          "rungs 2 and 3 is covered here and nowhere else."
end
