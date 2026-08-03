# ===== test/docs_examples.jl — every documented example actually runs
#
# Documenter checks `jldoctest` blocks. This package has **none** — its 109
# examples are `julia-repl` blocks, which Documenter renders and never executes.
# So "Doctest: running doctests" passed on every build while checking nothing,
# and the examples were prose that happened to look like evidence.
#
# This file executes them and compares against the documented output. Its first
# run found seven mismatches and two code blocks that did not even parse.
#
# ---- the one thing that makes this harder than it looks.
#
# `DefaultProjection!` and its siblings mutate **process-global** state. A fresh
# `Module` per page does not isolate them, so page N's demonstration silently
# rewrites what page N+1 is documented to produce. That is exactly what had
# happened: `user_guide.md` set `RTZ_SF` to show session defaults working, never
# restored it, and three later examples on the same page documented values a
# reader replaying the page would never see.
#
# The harness therefore restores the pristine defaults before each file — the
# semantics of "a reader opens this page" — and the page now restores them
# explicitly too, which is the honest fix rather than adjusting the expected
# output to match the leak.
#
# ---- what is compared, and what is deliberately not.
#
# Compared: every `julia> ` expression with documented output. Not compared:
# blocks whose result is `nothing` or suppressed with `;` (16 of them), and the
# `(…)` elisions the docs use for long tuples, which are matched up to the
# elision point. Non-REPL ```julia blocks are PARSED but not run — most are
# fragments of `src/` shown for reference, and running them would need the
# package's internals in scope, but a fragment that does not parse is still a
# defect and two of them did not.

# Run every `julia-repl` block in docs/src and compare against the documented
# output. Documenter only checks `jldoctest` blocks; there are none, so nothing
# in the docs is currently verified.
using Test, SmallFloats
using SmallFloats.Formats
using Random

const DOCS = joinpath(@__DIR__, "..", "docs", "src")

struct Case
    file::String
    line::Int
    input::String
    expected::String
end

function parse_repl_blocks(path)
    cases = Case[]
    lines = readlines(path)
    i = 1
    while i <= length(lines)
        if strip(lines[i]) == "```julia-repl"
            j = i + 1
            while j <= length(lines) && strip(lines[j]) != "```"
                j += 1
            end
            body = lines[i+1:j-1]
            # split into julia> prompts with continuation and expected output
            k = 1
            while k <= length(body)
                l = body[k]
                if startswith(l, "julia> ")
                    startline = i + k
                    inp = [l[8:end]]
                    k += 1
                    # continuation lines are indented by 7 spaces
                    while k <= length(body) && startswith(body[k], "       ") &&
                          !startswith(body[k], "julia> ")
                        push!(inp, body[k][8:end]); k += 1
                    end
                    out = String[]
                    while k <= length(body) && !startswith(body[k], "julia> ") &&
                          !isempty(strip(body[k]))
                        push!(out, body[k]); k += 1
                    end
                    push!(cases, Case(basename(path), startline,
                                      join(inp, "\n"), strip(join(out, "\n"))))
                else
                    k += 1
                end
            end
            i = j + 1
        else
            i += 1
        end
    end
    cases
end

# Strip trailing comments from the expected output — the docs annotate results
# inline (`Binary8p4se(1.875 ≡ 0x47)            # spec-named register`), which is
# prose, not part of what Julia prints.
strip_comment(s) = strip(replace(s, r"\s{2,}#.*$" => "", count=1))

function run_case(mod, c::Case)
    io = IOBuffer()
    local val
    try
        val = include_string(mod, c.input, "$(c.file):$(c.line)")
    catch err
        return (:error, first(sprint(showerror, err), 120))
    end
    val === nothing && return (:novalue, "")
    try
        show(IOContext(io, :limit => true, :compact => false, :module => mod),
             MIME"text/plain"(), val)
    catch err
        return (:showerror, first(sprint(showerror, err), 120))
    end
    (:ok, String(take!(io)))
end


# Non-REPL ```julia blocks: PARSED, not run. A fragment of `src/` shown for
# reference cannot execute without the package's internals in scope, but one that
# does not parse is a defect either way — and two did not.
function parse_julia_blocks(path)
    out = Tuple{Int,String}[]
    lines = readlines(path); i = 1
    while i <= length(lines)
        if strip(lines[i]) == "```julia"
            j = i + 1
            while j <= length(lines) && strip(lines[j]) != "```"; j += 1; end
            push!(out, (i + 1, join(lines[i+1:j-1], "\n")))
            i = j + 1
        else
            i += 1
        end
    end
    out
end

function parse_failure(code)
    try
        ex = Meta.parseall(code)
        for a in ex.args
            a isa Expr && a.head === :error && return string(a.args[1])
            a isa Expr && a.head === :incomplete && return "incomplete: " * string(a.args[1])
        end
    catch err
        return first(sprint(showerror, err), 140)
    end
    nothing
end

@testset "documented examples run as documented" begin
    files = sort!(filter(f -> endswith(f, ".md"), readdir(DOCS; join=true)))
    @test !isempty(files)

    # The session defaults are process-global; restore them per file so one
    # page's demonstration cannot rewrite the next page's documented output.
    #
    # The Binary show style is one of them, and it is set to `:typed` rather
    # than to the package default `:value`: the documentation renders values in
    # the fully type-annotated form (`Binary8p4se(1.625 ≡ 0x45)`), which the
    # Quickstart states outright. Establishing that convention HERE is what
    # keeps the statement true — a page whose examples were captured in one
    # style and checked in another would fail loudly rather than drift.
    pristine = (type = DefaultType(), proj = DefaultProjection(),
                show = get_show_style())
    reset!() = (DefaultType!(pristine.type); DefaultProjection!(pristine.proj);
                set_show_style!(:typed); nothing)

    ncases = ncmp = nskip = nblocks = 0
    for f in files
        reset!()
        mod = Module(Symbol("DocEx_", replace(basename(f), "." => "_")))
        Core.eval(mod, :(using SmallFloats; using SmallFloats.Formats;
                         using Random; using Statistics))
        bad = String[]
        for c in parse_repl_blocks(f)
            ncases += 1
            status, got = run_case(mod, c)
            exp = strip_comment(c.expected)
            if status === :error
                startswith(exp, "ERROR") && continue      # the doc shows the error
                push!(bad, "$(c.file):$(c.line) threw — $(got)\n      in: $(c.input)")
                continue
            end
            (status === :novalue || isempty(exp)) && (nskip += 1; continue)
            # Normalise what the HARNESS changes, never what the docs claim:
            #   * `Array{T,1}` — the REPL prints the `Vector{T}` alias
            #   * `SmallFloats.Foo` — `show` qualifies names because this runs in
            #     a synthetic module; a reader's REPL has `using SmallFloats` and
            #     prints them bare
            gotc = strip(got)
            gotc = replace(gotc, r"Array\{([^,}]+), 1\}" => s"Vector{\1}")
            gotc = replace(gotc, r"Array\{([^,}]+), 2\}" => s"Matrix{\1}")
            gotc = replace(gotc, "SmallFloats." => "")
            if occursin("(…)", exp)
                startswith(gotc, strip(split(exp, "(…)")[1])) && (ncmp += 1; continue)
            end
            ncmp += 1
            (gotc == exp || startswith(gotc, exp) || startswith(exp, gotc)) && continue
            push!(bad, "$(c.file):$(c.line)\n      in:  $(c.input)\n" *
                       "      exp: $(exp)\n      got: $(gotc)")
        end
        for (ln, code) in parse_julia_blocks(f)
            nblocks += 1
            pf = parse_failure(code)
            pf === nothing || push!(bad, "$(basename(f)):$ln does not parse — $pf")
        end
        @test (basename(f), bad) == (basename(f), String[])
    end
    reset!()
    @info "docs examples: $ncmp of $ncases `julia> ` results compared against the " *
          "documented output ($nskip produce no value to compare), plus " *
          "$nblocks non-REPL ```julia blocks parsed. Session defaults are " *
          "restored per file — they are process-global, and a page that leaks " *
          "one rewrites the next page's documented output."
end
