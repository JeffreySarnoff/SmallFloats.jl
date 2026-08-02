# ===== docs/make_latex.jl — LaTeX resolution pass for the PDF pipeline
#
# The LaTeX counterpart of make.jl: it shares the authored page map from
# pages.jl and changes only the output writer and build directory.

using Documenter
using TOML
using SmallFloats

include(joinpath(@__DIR__, "pages.jl"))

makedocs(;
    sitename = "SmallFloats.jl",
    modules = [SmallFloats],
    authors = "Jeffrey Sarnoff",
    build = "build_latex",
    # Read the package version from the root project so the resolved `.tex`,
    # cover page, and PDF metadata advance with every release.
    format = Documenter.LaTeX(platform = "none",
                              version = VersionNumber(
                                  TOML.parsefile(joinpath(@__DIR__, "..",
                                                          "Project.toml"))["version"])),
    remotes = nothing,
    pages = DOC_PAGES,
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)
