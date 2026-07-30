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

# ---- what is scanned, and why it is more than `docs/src/`.
#
# The first version of this gate scanned `docs/src/` only, which left **the
# most-read file in the repository uncovered**: `README.md` is what a reader
# meets first and what a package page renders. `docs/other/` holds the design and
# execution records — a stale range there misleads the next person to work on the
# package, which is a slower failure but not a smaller one.
#
# `docs/build/` and `docs/pdf/build/` are deliberately NOT scanned: they are
# generated, so a finding there is a finding about their source, reported twice.
const _DOC_ROOTS = [joinpath(@__DIR__, "..", "docs", "src"),
                    joinpath(@__DIR__, "..", "docs", "other")]
const _DOC_FILES = let fs = String[]
    for d in _DOC_ROOTS
        isdir(d) && append!(fs, filter(f -> endswith(f, ".md"), readdir(d; join=true)))
    end
    rm = joinpath(@__DIR__, "..", "README.md")
    isfile(rm) && push!(fs, rm)
    ch = joinpath(@__DIR__, "..", "CHANGELOG.md")
    isfile(ch) && push!(fs, ch)
    sort!(fs)
end

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
        # `Binary` became abstract at Stage 2, so an alias is `<:` its parametric
        # format and never `===` it. This appeared in TWO documentation files as
        # a REPL example printing `true`, which is worse than a stale number: a
        # reader who copies it gets `false` and concludes the package is broken.
        (r"Binary\d+p\d+[su][ef]\s*===\s*Binary\{", "alias `===` parametric format — it is `<:`, not `==="),
    ]
    # Exemptions: a line that states the stale claim in order to CORRECT it is
    # the documentation doing its job, not failing. Both of these were tripped by
    # the first run of this gate, which is the right shape of feedback — the
    # pattern is deliberately blunt and the exemption is where the nuance lives.
    _corrected(line) =
        occursin(r"120\s+(exported|at K)", line) ||          # "120 exported" is true
        occursin(r"FALSE|`false`|\bis false\b|not\s+`?===", line) ||  # "…is false" is true
        occursin(r"becomes\s+`?<:|→\s*`?<:|goes from", line)  # "X becomes <:" describes the change

    # RECORDS are exempt from the range and count patterns, because their whole
    # purpose is to state what a thing USED to be. `docs/other/` is the design and
    # execution record; `CHANGELOG.md` is the release record, and a changelog that
    # could not say "120 formats at K ∈ 3:8" would be unable to describe the
    # change it exists to describe. Rewriting either to match the present would
    # destroy the thing they are for.
    #
    # They are still scanned for the `===` claim, which is a statement about the
    # package as it is now wherever it appears — but a line saying the relation
    # *becomes* `<:` is describing the change and is exempted above.
    _is_record(f) = occursin(joinpath("docs", "other"), f) ||
                    basename(f) == "CHANGELOG.md"
    _always = [p for p in stale if occursin("===", p[2])]

    findings = String[]
    for f in _DOC_FILES
        pats = _is_record(f) ? _always : stale
        for (i, line) in enumerate(eachline(f)), (re, what) in pats
            occursin(re, line) || continue
            _corrected(line) && continue
            push!(findings, "$(relpath(f, joinpath(@__DIR__, ".."))):$i — $what\n      $(strip(line))")
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
