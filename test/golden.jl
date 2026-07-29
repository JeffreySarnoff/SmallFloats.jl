# ===== test/golden.jl — gate G5: K ≤ 8 golden non-regression
#
# Compares the current tree's digests against the oracle captured from the
# pre-refactor tree (`test/golden/capture.jl`, run once at Stage 0).
#
# Tier is chosen by SMALLFLOATS_G5:
#   "fast" (default) — ~45 s: metadata, decode, lattice, order, projection,
#                      packed, sort. Everything a type refactor can move.
#   "lazy"           — ~2 min: "fast" and samples 15%-20% of the operation catalogue, blocks, kernels,
#                      Base veneers. Required at stage exit.
#   "full"           — ~5 min: adds the operation catalogue, blocks, kernels,
#                      Base veneers. Required at stage exit.
#   "off"            — skip (with a visible message; never silently).
#
# A failure here is not a test that needs updating. It means a K ≤ 8 result
# moved, which this extension promises will not happen. Investigate; do not
# recapture.

using Test, SmallFloats

if !haskey(ENV, "SMALLFLOAT_G5") || ENV["SMALLFLOAT_G5"] == "full"
    ENV["SMALLFLOAT_G5"] = "lazy"
end

include(joinpath(@__DIR__, "golden", "harness.jl"))

@testset "G5 — K ≤ 8 golden non-regression" begin
    tier = get(ENV, "SMALLFLOATS_G5", "fast")
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
        # from the harness entirely is.
        if tier == "full"
            for name in keys(want)
                @test any(p -> first(p) == name, got)
            end
        end
    end
end
