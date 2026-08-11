# ===== docs/make.jl — Documenter build definition
#
# Invoked by docs/builddocs.jl for local builds, or directly on CI with the docs
# environment already instantiated:  julia --project=docs docs/make.jl
#
# Source of truth for both site and PDF is docs/src/. Navigation is shared with
# make_latex.jl through pages.jl so the two artifacts always cover the same set.

using Documenter
using SmallFloats

include(joinpath(@__DIR__, "pages.jl"))

makedocs(;
    sitename = "SmallFloats.jl",
    modules = [SmallFloats],
    authors = "Jeffrey Sarnoff",
    source = "src",
    build = get(ENV, "DOCS_BUILD_DIR", "build"),
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://JeffreySarnoff.github.io/SmallFloats.jl",
        edit_link = "main",
        assets = String[],
    ),
    repo = Documenter.Remotes.GitHub("JeffreySarnoff", "SmallFloats.jl"),
    pages = DOC_PAGES,
    # The guides intentionally reference some names that carry no docstrings yet
    # (docstring coverage is tracked work); keep those as warnings, not failures.
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)

# Validate the rendered site rather than only the Markdown source.  In
# particular, this checks flat ``.html`` links for ``file://`` browsing and
# directory/index links emitted when CI enables pretty URLs.
function _check_html_links(docsdir::String)
    python = something(Sys.which("python"), Sys.which("python3"), nothing)
    python === nothing && error("Cannot validate documentation links: Python 3 was not found.")
    builddir = joinpath(docsdir, get(ENV, "DOCS_BUILD_DIR", "build"))
    @info "Checking rendered documentation links" builddir
    run(`$python $(joinpath(docsdir, "check_links.py")) $builddir`)
end

_check_html_links(@__DIR__)

# ---- PDF stage: every docs build regenerates the PDF from these same sources.
#
# It lives HERE rather than only in builddocs.jl because make.jl is what CI and
# every scripted rebuild actually invoke. With the stage in the wrapper only,
# `julia --project=docs docs/make.jl` refreshed the HTML and silently left
# a stale tracked PDF behind — the two artifacts describing different trees, with
# nothing saying so.
#
# Ordered BEFORE deploydocs so a PDF failure stops the build rather than
# publishing a site whose companion PDF never compiled.
#
# `DOCS_PDF=skip` opts out, for iterating on prose without the LaTeX round trip.
# `docs/pdf/buildpdf.sh` runs make_latex.jl, not this file, so there is no
# recursion; `SMALLFLOATS_IN_PDF_BUILD` guards that invariant anyway, since a
# future edit to the shell script is exactly how it would be broken.
function _build_pdf(docsdir::String)
    get(ENV, "DOCS_PDF", "") == "skip" &&
        return @info "PDF stage skipped (DOCS_PDF=skip)"
    get(ENV, "SMALLFLOATS_IN_PDF_BUILD", "") == "1" &&
        return @info "PDF stage skipped (already inside a PDF build)"

    missing_tools = filter(t -> Sys.which(t) === nothing,
                           ["xelatex", "latexmk", "pygmentize", "pdftoppm", "qpdf"])
    isempty(missing_tools) || error(
        "PDF toolchain incomplete; missing: $(join(missing_tools, ", ")). " *
        "Install them, or set DOCS_PDF=skip to build the HTML only.")

    @info "Building PDF from docs/src (docs/pdf/buildpdf.sh)"
    withenv("SMALLFLOATS_IN_PDF_BUILD" => "1") do
        run(`bash $(joinpath(docsdir, "pdf", "buildpdf.sh"))`)
    end
    pdf = joinpath(docsdir, "pdf", "SmallFloats.pdf")
    isfile(pdf) || error("buildpdf.sh completed without producing $pdf")
    @info "PDF built" pdf = pdf size_kb = round(Int, filesize(pdf) / 1024)
end

_build_pdf(@__DIR__)

# Publishes to the gh-pages branch from CI (no-ops on local builds, which lack
# the deploy credentials). Requires GitHub Pages to serve from gh-pages.
deploydocs(;
    repo = "github.com/JeffreySarnoff/SmallFloats.jl",
    devbranch = "main",
    push_preview = true,
)
