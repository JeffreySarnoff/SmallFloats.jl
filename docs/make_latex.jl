# ===== docs/make_latex.jl — LaTeX resolution pass for the PDF pipeline
#
# A copy of make.jl per docs/pdf/generate_pdf.md Stage 1: format swapped to the
# LaTeX writer with platform = "none" (emit resolved .tex, don't compile),
# build directory build_latex, remotes = nothing (local build), deploydocs and
# HTML-only options dropped. pages / modules / checkdocs / warnonly kept
# exactly as make.jl defines them.

using Documenter
using TOML
using SmallFloats

# Benchmarks page: generated report copied in at build time (mirrors make.jl).
cp(joinpath(@__DIR__, "..", "benchmarking", "benchmark_report.md"),
   joinpath(@__DIR__, "src", "benchmarks.md"); force = true)

makedocs(;
    sitename = "SmallFloats.jl",
    modules = [SmallFloats],
    authors = "Jeffrey Sarnoff",
    build = "build_latex",
    # The version is READ from Project.toml, never spelled here. It was
    # hardcoded `v"0.1.0"`, so the resolved `.tex`, the cover page and the PDF
    # metadata all reported 0.1.0 after the package moved to 0.2.0 — a stale
    # number in the one artifact nobody re-reads.
    format = Documenter.LaTeX(platform = "none",
                              version = VersionNumber(
                                  TOML.parsefile(joinpath(@__DIR__, "..",
                                                          "Project.toml"))["version"])),
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Introduction" => "introduction.md",
        "Cheat Sheet" => "cheat_sheet.md",
        "User Guide" => "user_guide.md",
        "User Examples" => "user_examples.md",
        "Julia Compatibility" => "julia_compatibility.md",
        "Technical Guide" => "technical_guide.md",
        "Technical Examples" => "technical_examples.md",
        "Benchmarks" => "benchmarks.md",
        "Adding Operations" => "new_operations.md",
        "External Reference" => "external_reference.md",
        "Internal Reference" => "internal_reference.md",
    ],
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)
