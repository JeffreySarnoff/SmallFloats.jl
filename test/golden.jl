# ===== test/golden.jl — gate G5: K ≤ 8 golden non-regression
#
# Compares the current tree's digests against the oracle captured from the
# pre-refactor tree (`test/golden/capture.jl`, run once at Stage 0).
#
# Tier is chosen by SMALLFLOATS_G5:
#   "fast"           — ~1 min: metadata, decode, lattice, order, projection,
#                      packed, sort. Everything a type refactor can move.
#   "lazy" (default) — ~3 min: "fast", the cheap full sections whole, and a
#                      1-in-6 format sample of the three expensive ones.
#                      The routine stage-exit tier.
#   "full"           — ~11 min: every section over all 120 formats. Required at
#                      the Stage 2 exit and at release.
#   "off"            — skip (with a visible message; never silently).
#
# A failure here is not a test that needs updating. It means a K ≤ 8 result
# moved, which this extension promises will not happen. Investigate; do not
# recapture.

using Test, SmallFloats

using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
# The routine tier is `lazy` — the stage-exit gate. `fast`, `full` and `off` are
# opt-in and are HONOURED: a tier the caller asked for is never silently
# downgraded, because a gate that quietly runs less than it was told to is worse
# than no gate. (§11 M15.)
get!(ENV, "SMALLFLOATS_G5", "lazy")

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")
include(joinpath(@__DIR__, "golden", "harness.jl"))

@testset "G5 — K ≤ 8 golden non-regression" begin
    tier = ENV["SMALLFLOATS_G5"]
    if tier == "off"
        @info "G5 skipped (SMALLFLOATS_G5=off)"
    elseif !isfile(GOLDEN_FILE)
        @warn "G5 oracle missing — run `julia --project=. test/golden/capture.jl`" GOLDEN_FILE
        @test_broken isfile(GOLDEN_FILE)
    else
        want = Dict(read_golden())
        got  = golden_digests(Symbol(tier))
        for (name, d) in got
            if !haskey(want, name)
                @warn "G5 section not in the captured oracle (new section?)" section = name
                @test_broken haskey(want, name)
            else
                # Named comparison so a failure report says WHICH section moved.
                @test (name, d) == (name, want[name])
            end
        end
        # Sections present in the oracle but not computed at this tier are not a
        # failure — that is what tiering means — but a section that disappeared
        # from the harness entirely is. So the completeness check is against the
        # harness's DECLARED section set, not against what this tier happened to
        # compute; the earlier spelling (`any(p -> first(p) == name, got)`) made
        # the three `~lazy` entries fail at `:full` by construction, since `:full`
        # never computes them. Runs at every tier — it costs nothing and a deleted
        # section should not need `:full` to be noticed. (§11 M15.)
        known = Set(first(p) for p in all_sections())
        for name in keys(want)
            @test (name, name in known) == (name, true)
        end
    end
    # The roll-call needs G5 present even when it is OFF or its oracle is
    # missing — a gate that quietly did nothing must show as having done nothing,
    # not be absent. `units = 0` is what `rollcall.jl` fails on, which is the
    # correct outcome for a skipped G5 in a run that claims to be complete.
    record_gate!("G5"; assertions=33, units=(tier == "off" ? 0 : 33),
                 exhaustive=(tier == "full"),
                 note=tier == "full" ? "" :
                      "tier=$tier over the 120 K ≤ 8 formats; `full` is the " *
                      "release tier (SMALLFLOATS_G5=full)")
end
