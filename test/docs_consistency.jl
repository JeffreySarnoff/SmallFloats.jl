# ===== test/docs_consistency.jl — the prose cannot disagree with the package
#
# Stage 9 item 2, and the reason it is a test rather than a proofreading pass.
#
# The K ≤ 16 extension found the bitwidth range `3–8` stated in five documentation
# files and the format count in two more. Every one of them was written correct
# and went stale the moment `KMAX` changed, and nothing in the repository could
# tell — a stale range in `docs/src/` propagates through Documenter into the
# released PDF, which is the one artifact nobody re-reads.
#
# Hand-editing seven sites fixes it once. This file fixes it permanently: the
# truth is read from the package (`KMIN`, `KMAX`, `_NAMED`, the export list) and
# the documentation is searched for anything that contradicts it. A future change
# to the grid turns a green suite red in the place that would otherwise ship a
# false claim.
#
# What this deliberately does NOT do is check prose for accuracy in general —
# that is not mechanizable and pretending otherwise would make the gate a
# nuisance. It checks the small set of facts that are (a) stated as literals,
# (b) derived from constants that change, and (c) load-bearing for a reader:
# the bitwidth range, the format count, and the size of the export surface.

using Test, SmallFloats
using SmallFloats: KMIN, KMAX, KSPLIT, _NAMED, bitwidth

const _DOCS_SRC = joinpath(@__DIR__, "..", "docs", "src")
const _DOC_FILES = isdir(_DOCS_SRC) ?
    sort!(filter(f -> endswith(f, ".md"), readdir(_DOCS_SRC; join=true))) : String[]

@testset "documentation agrees with the package" begin
    @test !isempty(_DOC_FILES)

    n_all = length(_NAMED)
    n_exported = count(nm -> bitwidth(_NAMED[nm]) <= KSPLIT, keys(_NAMED))
    n_optin = n_all - n_exported

    # The package's own numbers, so the test cannot drift from what it checks.
    @test n_all == 504
    @test n_exported == 120
    @test (KMIN, KMAX) == (3, 16)

    # `Main` after `using SmallFloats` holds exactly the K ≤ KSPLIT aliases —
    # the claim the prose makes, checked against the module rather than trusted.
    exported = Set(names(SmallFloats))
    wide = [nm for nm in keys(_NAMED) if bitwidth(_NAMED[nm]) > KSPLIT]
    narrow = [nm for nm in keys(_NAMED) if bitwidth(_NAMED[nm]) <= KSPLIT]
    @test all(nm -> nm in exported, narrow)
    @test !any(nm -> nm in exported, wide)
    # …and `SmallFloats.Formats` re-exports every one of the 504.
    fmt_exported = Set(names(SmallFloats.Formats))
    @test all(nm -> nm in fmt_exported, keys(_NAMED))

    # ---- the stale-literal search.
    #
    # Each pattern is a claim that WAS true at K ≤ 8 and is false now. Matching
    # one is the failure; the message names the file and line so the fix is
    # mechanical. Patterns are deliberately specific — a bare "8" would match
    # `Binary8p4se` and make the gate useless noise.
    stale = [
        (r"bitwidths?\s+3\s*[–\-]\s*8\b",       "bitwidth range stated as 3–8"),
        (r"bitwidths?\s+3\s+through\s+8\b",     "bitwidth range stated as 3 through 8"),
        (r"`?K\s*∈\s*3:8`?",                    "K ∈ 3:8"),
        (r"\b3\s*[–\-]\s*8\s+bitwidth\b",       "3–8 bitwidth range"),
        (r"\b120\s+formats\b",                  "format count stated as 120"),
        (r"\b120\s+draft\s+formats\b",          "format count stated as 120"),
        (r"\b120\s+named\s+aliases\b",          "alias count stated as 120"),
        (r"all\s+120\b",                        "\"all 120\" — 120 is now the EXPORTED count, not the total"),
    ]
    findings = String[]
    for f in _DOC_FILES, (i, line) in enumerate(eachline(f))
        for (re, what) in stale
            occursin(re, line) || continue
            # "120 exported" is the true statement and must not trip the gate.
            occursin(r"120\s+(exported|at K)", line) && continue
            push!(findings, "$(basename(f)):$i — $what\n      $(strip(line))")
        end
    end
    @test findings == String[]

    # The count that IS correct should appear somewhere, so a file that dropped
    # the statement entirely is as visible as one that kept a wrong one.
    alltext = join(read.(_DOC_FILES, String), "\n")
    @test occursin("504", alltext)
    @test occursin("SmallFloats.Formats", alltext)

    @info "docs: $(length(_DOC_FILES)) files checked against the package — " *
          "$n_all formats ($n_exported exported at K ≤ $KSPLIT, $n_optin opt-in " *
          "via SmallFloats.Formats), K ∈ $KMIN:$KMAX"
end
