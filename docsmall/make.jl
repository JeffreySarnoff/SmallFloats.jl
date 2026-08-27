# ===== docsmall/make.jl — Documenter build for the COMPACT manual
#
# Mirror of docs/make.jl for the small documentation set:
#   julia --project=docsmall docsmall/make.jl
#
# Source of truth is docsmall/src/. Navigation is shared with make_latex.jl
# through pages.jl so the HTML site and the PDF always cover the same set.
#
# Differences from docs/make.jl, both deliberate:
#   * no deploydocs — the compact manual is a local/companion artifact; the
#     published site is the full manual in docs/.
#   * examples here are transcripts copied verbatim from docs/src pages that
#     test/docs_examples.jl verifies, so the main harness indirectly covers
#     their content; docsmall itself is not wired into the test suite.

using Documenter
using SmallFloats

include(joinpath(@__DIR__, "pages.jl"))

makedocs(;
    sitename = "SmallFloats.jl Compact Guide",
    modules = [SmallFloats],
    authors = "Jeffrey Sarnoff",
    source = "src",
    build = get(ENV, "DOCS_BUILD_DIR", "build"),
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        edit_link = "main",
        assets = String[],
    ),
    repo = Documenter.Remotes.GitHub("JeffreySarnoff", "SmallFloats.jl"),
    pages = DOC_PAGES,
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)

# Validate the rendered site (reuses the full manual's checker).
function _check_html_links(dsdir::String)
    python = something(Sys.which("python"), Sys.which("python3"), nothing)
    python === nothing && error("Cannot validate documentation links: Python 3 was not found.")
    builddir = joinpath(dsdir, get(ENV, "DOCS_BUILD_DIR", "build"))
    checker = joinpath(dsdir, "..", "docs", "check_links.py")
    @info "Checking rendered documentation links" builddir
    run(`$python $checker $builddir`)
end

_check_html_links(@__DIR__)

# ---- PDF stage: same contract as docs/make.jl — every build regenerates the
# PDF from these sources unless DOCS_PDF=skip opts out.
function _build_pdf(dsdir::String)
    get(ENV, "DOCS_PDF", "") == "skip" &&
        return @info "PDF stage skipped (DOCS_PDF=skip)"
    get(ENV, "SMALLFLOATS_IN_PDF_BUILD", "") == "1" &&
        return @info "PDF stage skipped (already inside a PDF build)"

    missing_tools = filter(t -> Sys.which(t) === nothing,
                           ["xelatex", "latexmk", "pygmentize", "pdftoppm", "qpdf"])
    isempty(missing_tools) || error(
        "PDF toolchain incomplete; missing: $(join(missing_tools, ", ")). " *
        "Install them, or set DOCS_PDF=skip to build the HTML only.")

    @info "Building compact PDF from docsmall/src (docsmall/pdf/buildpdf.sh)"
    withenv("SMALLFLOATS_IN_PDF_BUILD" => "1") do
        run(`bash $(joinpath(dsdir, "pdf", "buildpdf.sh"))`)
    end
    pdf = joinpath(dsdir, "pdf", "SmallFloatsCompact.pdf")
    isfile(pdf) || error("buildpdf.sh completed without producing $pdf")
    @info "Compact PDF built" pdf = pdf size_kb = round(Int, filesize(pdf) / 1024)
end

_build_pdf(@__DIR__)
