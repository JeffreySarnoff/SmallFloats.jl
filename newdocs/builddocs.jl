#!/usr/bin/env julia
# ===== docs/builddocs.jl — one-command local documentation build
#
#   julia docs/builddocs.jl          (from the repository root)
#   julia builddocs.jl               (from docs/)
#
# Activates the docs environment, dev's the package from the parent directory,
# instantiates, runs make.jl (which builds from docs/src/), and reports where
# the site landed. CI should skip this file and run
# `julia --project=docs docs/make.jl` after its own Pkg setup.

import Pkg

const DOCS = @__DIR__
const PKG  = dirname(DOCS)

Pkg.activate(DOCS)
Pkg.develop(Pkg.PackageSpec(path = PKG))
Pkg.instantiate()

include(joinpath(DOCS, "make.jl"))

const BUILD = get(ENV, "DOCS_BUILD_DIR", "build")
const INDEX = joinpath(DOCS, BUILD, "index.html")
if isfile(INDEX)
    @info "Documentation built successfully" site = INDEX
else
    @warn "make.jl completed but no index.html found — check the build log" dir = joinpath(DOCS, BUILD)
end

# ---- PDF stage (mandatory): every complete docs build regenerates the PDF
# from the same docs/src sources as the HTML site. Missing tools are a build
# failure, not permission to leave a stale tracked artifact behind.
missing_tools = filter(t -> Sys.which(t) === nothing,
                       ["xelatex", "latexmk", "pygmentize", "pdftoppm", "qpdf"])
isempty(missing_tools) ||
    error("PDF toolchain incomplete; missing: $(join(missing_tools, ", "))")

@info "Building PDF from docs/src (docs/pdf/buildpdf.sh)"
run(`bash $(joinpath(DOCS, "pdf", "buildpdf.sh"))`)

const PDF = joinpath(DOCS, "pdf", "SmallFloats.pdf")
isfile(PDF) || error("PDF build completed without producing $PDF")
@info "PDF built successfully" pdf = PDF
