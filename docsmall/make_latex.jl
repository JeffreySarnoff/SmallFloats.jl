# ===== docsmall/make_latex.jl — LaTeX resolution pass for the compact PDF
#
# The LaTeX counterpart of docsmall/make.jl: same page map from pages.jl,
# only the output writer and build directory change.

using Documenter
using TOML
using SmallFloats

include(joinpath(@__DIR__, "pages.jl"))

makedocs(;
    sitename = "SmallFloats.jl Compact Guide",
    modules = [SmallFloats],
    authors = "Jeffrey Sarnoff",
    build = "build_latex",
    format = Documenter.LaTeX(platform = "none",
                              version = VersionNumber(
                                  TOML.parsefile(joinpath(@__DIR__, "..",
                                                          "Project.toml"))["version"])),
    remotes = nothing,
    pages = DOC_PAGES,
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)
