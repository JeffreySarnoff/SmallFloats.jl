# ===== test/rollcall.jl — the coverage roll-call (Stage 8 step 6, and its exit)
#
# Runs last. Asserts that every gate and tier the doctrine names actually
# registered, prints what each one covered, and prints — in one place — the list
# of things this suite knowingly does not cover.
#
# The last part is the one that matters most and is the easiest to skip. §6.4 of
# the plan says the knowingly-uncovered areas must be "stated once, plainly, so
# it is not rediscovered as a surprise". A list in a document is not stated where
# anyone will see it; a list printed at the end of every green run is.

using Test

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")
isdefined(@__MODULE__, :SUITE_TIER) || include("formatsel.jl")

@testset "roll-call — every gate standing, coverage stated" begin
    missing_gates = [g for g in REQUIRED_GATES if !haskey(GATE_LOG, g)]
    @test missing_gates == String[]

    # A gate that registers zero units did not run, whatever its assertion count
    # says — an empty loop and a passing loop look identical in a summary line.
    for (name, e) in sort!(collect(GATE_LOG), by=first)
        @test (name, e.units > 0) == (name, true)
    end

    total_units = sum(e.units for e in values(GATE_LOG); init=0)
    n_exh = count(e -> e.exhaustive, values(GATE_LOG))

    io = IOBuffer()
    println(io, "\n", "="^78)
    println(io, "COVERAGE ROLL-CALL — tier=", SUITE_TIER, " — ",
                length(GATE_LOG), " gates and tiers, ",
                n_exh, " exhaustive, ", length(GATE_LOG) - n_exh, " sampled")
    println(io, "="^78)
    # The tier belongs at the top, not in a footnote. A reader who sees
    # "9 exhaustive" without knowing which tier produced it has been told a
    # number, not a coverage claim.
    println(io, SUITE_TIER == "release" ?
        "  Release tier: every format axis exhaustive, G5 and G10 at `full`." :
        SUITE_TIER == "quick" ?
        "  QUICK tier — the edit-compile-test loop. Format axes are at their\n" *
        "  narrowest (one per rung) and G5 is at `fast`. NOT a release gate:\n" *
        "  run SMALLFLOATS_TIER=release before shipping." :
        "  Default tier. Format axes are sampled per the derived representative\n" *
        "  set; SMALLFLOATS_TIER=release sweeps all 504 formats.")
    println(io, "="^78)
    for (name, e) in sort!(collect(GATE_LOG), by=first)
        println(io, rpad(name, 6), rpad(e.exhaustive ? "exhaustive" : "SAMPLED", 12),
                    lpad(string(e.units), 12), " units  ",
                    lpad(string(e.assertions), 8), " assertions")
        isempty(e.note) || println(io, " "^18, e.note)
    end
    println(io, "-"^78)
    println(io, "total compared: ", total_units)
    println(io, """
    -"""^0)
    println(io, """
KNOWINGLY NOT COVERED (plan §6.4) — stated here so it is not rediscovered:

  * The full ordered-pair cross-product for `TotalOrder` above K = 8. `2^2K`
    pairs is 4.3e9 for one K = 16 format. Exhaustive at K <= 8 (runtests §3);
    above it, T1 checks consecutive pairs plus the specials x lattice slice,
    which imply it by transitivity. Weaker, and not sampled.

  * Multi-operand input cross-products above 2^22 points for K >= 12. Covered by
    threshold-derived edges (`formatsel.jl`'s `THRESHOLD_EDGES`) and by the
    representative format set, both REPORTED as sampled.

  * kappa for binary and ternary specializations at K >= 12. `measure_kappa`
    already reports `exhaustive = false` and `conformance_report` already prints
    "(kappa sampled - not exhaustive)". No mechanism change: invariant 5 holds
    under wide K because kappa was designed as a measurement, not an assertion.

  * `f32_exact`'s enumeration at K >= 12, per its section 9 disposition.

  * G8 (the representation invariant) has no file: it is asserted in every
    constructor and swept by T1's encode round-trip at every K. Absent from
    REQUIRED_GATES for that reason, not by oversight.

  * The format axis of T2b, G10 and the rho tier is SAMPLED by default -- one
    representative per realized (rung, rung-boundary, code unit, P-class, Sigma,
    Delta) cell. `SmallFloats_EXHAUSTIVE=1` widens it to all 504.
""")
    println(io, "="^78)
    print(String(take!(io)))

    @test total_units > 0

    # A `quick` run must never be able to masquerade as a release gate: at that
    # tier some axis IS narrowed, by construction, so a run reporting everything
    # exhaustive would mean the dial did not reach a tier that should have
    # narrowed — the same "quietly ran something other than what was asked"
    # failure the dial exists to remove, pointing the other way.
    if SUITE_TIER == "quick"
        @test n_exh < length(GATE_LOG)
    elseif SUITE_TIER == "release"
        # Conversely, at `release` every tier that CAN be exhaustive must be.
        # G2, G4 and G7 are boundary-targeted by design and are named here so
        # the exception is a list rather than a shrug.
        # Cell-complete rather than format-exhaustive, each for a stated reason:
        # G2, G4 and G7 are boundary-targeted (their format lists sit either side
        # of a rung boundary, and sweeping the grid dilutes that); Tρ enumerates
        # 36 (rung, op-class, variant) cells that one format per (rung, P == 1)
        # already reaches, so its axis is capped at the representative set.
        by_design = Set(["G2", "G4", "G7", "Tρ"])
        not_exhaustive = sort!([k for (k, e) in GATE_LOG
                                if !e.exhaustive && !(k in by_design)])
        @test not_exhaustive == String[]
    end
end
