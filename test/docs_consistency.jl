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
using SHA: sha256
using SmallFloats: KMIN, KMAX, KSPLIT, _NAMED, bitwidth

# ---- what is scanned, and why it is more than `docs/src/`.
#
# The first version of this gate scanned `docs/src/` only, which left **the
# most-read file in the repository uncovered**: `README.md` is what a reader
# meets first and what a package page renders. `docs/other/` holds the design and
# execution records — a stale range there misleads the next person to work on the
# package, which is a slower failure but not a smaller one.
#
# Generated trees are not part of the general fact scan. The tracked PDF source
# is, however, included in the interface-claim check below: it is a published
# artifact, and a stale regeneration must not reintroduce a nonexistent API.
# `doc/` AND `docs/` — the repository has both, and only the plural one was
# covered. That is how a design note added to `doc/other/` walked past a gate
# that had just been widened to catch exactly its defect: the hole was closed on
# one of two similarly-named trees. Scanning both is the cheap half of the fix;
# the ambiguity itself remains a trap for whoever adds the next file.
const _DOC_ROOTS = [joinpath(@__DIR__, "..", "docs", "src"),
                    joinpath(@__DIR__, "..", "docs", "other"),
                    joinpath(@__DIR__, "..", "doc", "other")]
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

# The four VENDORED documents under `docs/other/`: upstream copies of the Julia
# manual and the SciML style guide, whose backslashes are artifacts of an
# HTML-to-markdown conversion. They must keep matching their source, so the
# LaTeX-delimiter gate below names them rather than skipping the directory.
const _VENDORED_DOCS = ("Style Guide · The Julia Language.md",
                        "Performance Tips · The Julia Language.md",
                        "Optimizing your code.md",
                        "SciML Style Guide for Julia.md")

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
    # BOTH record trees. `doc/other/` holds the review and improvement guides,
    # whose entire subject is what the package used to claim — they quote the
    # stale range and count deliberately, in order to correct them. Extending
    # `_DOC_ROOTS` without extending this would turn every one of those guides
    # red for saying true things about the past, and the gate would become the
    # nuisance this file's header warns against.
    #
    # `"doc/other"` is NOT a substring of `"docs/other"` (the `s` intervenes), so
    # both must be tested; one `occursin` cannot cover the pair.
    _is_record(f) = occursin(joinpath("docs", "other"), f) ||
                    occursin(joinpath("doc", "other"), f) ||
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

    # Volatile package/draft identity is checked at the same seam that renders
    # it. The digest names the retained transliteration, not an unavailable
    # original document.
    @test Base.pkgversion(SmallFloats) == v"0.4.0"
    draft = draft_identity()
    retained = joinpath(@__DIR__, "..", draft.retained_source)
    @test isfile(retained)
    @test bytes2hex(sha256(read(retained))) == draft.transliteration_sha256

    # Implementation pages may name source files, but cannot keep links to a
    # layer that has been removed. Check every backticked src/*.jl reference.
    # RECORDS are excluded, for the reason they are excluded from the stale
    # literals: a review that says "`internals_oracle.md` points to the removed
    # `src/dyadic3.jl`" is doing its job, and a plan that says "reject removed
    # `src/dyadic3.jl` references" is describing this very check. Requiring those
    # paths to exist would forbid a record from naming what was removed — which
    # is most of what a record is for. The check exists to stop LIVE
    # documentation pointing at a deleted layer, and that is `docs/src/`.
    #
    # Globs are skipped everywhere: `` `src/*.jl` `` is prose describing a set of
    # files, not a link to one, and no `isfile` can be true of it.
    srcroot = normpath(joinpath(@__DIR__, ".."))
    source_refs = String[]
    for f in _DOC_FILES
        _is_record(f) && continue
        for m in eachmatch(r"`(src/[^`]+\.jl)`", read(f, String))
            occursin('*', m.captures[1]) && continue
            push!(source_refs, m.captures[1])
        end
    end
    @test !isempty(source_refs)
    @test all(p -> isfile(joinpath(srcroot, p)), source_refs)

    # Removed controls and nonexistent scoped-setter forms must not return to
    # either the live manual or its tracked PDF source. Historical records under
    # docs/other may discuss the old defect and are intentionally excluded.
    interface_files = filter(f -> occursin(joinpath("docs", "src"), f), _DOC_FILES)
    pdftex = joinpath(@__DIR__, "..", "docs", "pdf", "build", "main.tex")
    @test isfile(pdftex)
    push!(interface_files, pdftex)
    interface_text = join(read.(interface_files, String), "\n")
    @test !occursin(r"Default(RNG|Rbits)!?", interface_text)
    @test !occursin(r"with_default_(type|returntype|projection)\([^,\n]+\)\s+do",
                    interface_text)
    @test !occursin("restores on exit", interface_text)
    for false_claim in ("for a scoped region", "for scoped mutate-and-restore",
                        "scoped combinators", "scoped alternatives")
        @test !occursin(false_claim, lowercase(interface_text))
    end

    # ---- LaTeX math delimiters in documentation, and the one place they belong.
    #
    # A docstring is a Julia string literal before it is prose, so `\(`, `\)`,
    # `\[`, `\]` and `\text{…}` are **invalid escape sequences** — a syntax error
    # that stops the file parsing and the package loading. A `measure_kappa`
    # docstring written that way made `using SmallFloats` fail outright.
    #
    # **That case cannot be caught here, and this gate does not pretend to.** If
    # the package will not load, no test runs at all; the parse error announces
    # itself immediately and loudly. What this catches is the family that does
    # NOT announce itself:
    #
    #   * a `raw"""…"""` docstring, which parses happily and then renders as
    #     literal backslashes — Documenter's math is ```math and ``…``, never
    #     `\(…\)`;
    #   * an escaped `\\(` in an ordinary string, same outcome;
    #   * LaTeX in a `#` comment, written expecting it to render, which it never
    #     will because comments are not documentation;
    #   * the same in `docs/src/*.md`, where Documenter leaves it as literal text.
    #
    # A TEXTUAL gate, and that is the right strength — the defect *is* a
    # spelling, exactly as `stage_gates.jl` argues for its `Binary{K` scan.
    #
    # Lines carrying a regex literal are exempt, and the exemption is the whole
    # reason this is a gate rather than a find-and-replace. In a `Regex`, `\(` is
    # an escape for a LITERAL parenthesis: this very file matches
    # `r"with_default_(…)\([^,\n]+\)\s+do"` above, and rewriting that to `(`
    # would silently turn it into a capture group and stop the false-claim check
    # from catching anything. A blind sweep over the tree breaks working code.
    #
    # `docs/other/` IS scanned, minus four named files.
    #
    # The first version of this gate skipped the whole directory, and that was too
    # broad in the way an over-wide exclusion always is: a hand-written design
    # note added to `docs/other/` the same day went straight past it. The reason
    # for the exclusion was never the directory — it was four VENDORED files,
    # upstream copies of the Julia manual and the SciML style guide whose
    # backslashes are artifacts of an HTML-to-markdown conversion. Those must keep
    # matching their source, so they are named, and everything else is covered.
    #
    # `docs/other/` never renders through Documenter (`pages.jl` has no entry for
    # it), but it IS read on GitHub — whose math syntax is `$…$`, `$$…$$` and
    # ```math, not `\(…\)`. LaTeX delimiters there render as literal backslashes
    # for every reader, so the check earns its place on rendering grounds even
    # where no parser is involved.
    @testset "no LaTeX math delimiters in documentation" begin
        srcdir = joinpath(@__DIR__, "..", "src")
        docsrc = joinpath(@__DIR__, "..", "docs", "src")
        docoth = joinpath(@__DIR__, "..", "docs", "other")
        dsingl = joinpath(@__DIR__, "..", "doc", "other")     # the OTHER record tree
        scan = String[]
        append!(scan, filter(f -> endswith(f, ".jl"), readdir(srcdir; join=true)))
        isdir(docsrc) && append!(scan, filter(f -> endswith(f, ".md"), readdir(docsrc; join=true)))
        for d in (docoth, dsingl)
            isdir(d) && append!(scan,
                filter(f -> endswith(f, ".md") && !(basename(f) in _VENDORED_DOCS),
                       readdir(d; join=true)))
        end
        # The vendored list must not rot into a list of files that no longer
        # exist: a stale name silently stops excluding anything, and a renamed
        # upstream copy would start failing the gate for the wrong reason.
        for v in _VENDORED_DOCS
            @test isfile(joinpath(docoth, v))
        end
        offenders = String[]
        for f in sort!(scan), (i, line) in enumerate(eachline(f))
            occursin("r\"", line) && continue            # regex literal: `\(` is correct there
            occursin(r"\\[()\[\]]|\\text\{", line) &&
                push!(offenders, string(relpath(f, joinpath(@__DIR__, "..")), ":", i))
        end
        isempty(offenders) || @info "LaTeX delimiters found in: " * join(offenders, ", ")
        @test offenders == String[]
        @info "LaTeX-delimiter scan: $(length(scan)) source and documentation files clean"
    end

    @info "docs: $(length(_DOC_FILES)) files checked against the package — " *
          "$n_all formats ($n_exported exported at K ≤ $KSPLIT, $n_optin opt-in " *
          "via SmallFloats.Formats), K ∈ $KMIN:$KMAX"
end
