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

        "Getting Started" => [
            "installation.md",
            "quickstart.md",
            "mentalmodel.md",
            "fifteenminutes.md",
        ],

        "Using SmallFloats" => [
            "Tutorials" => [
                "tutorial1_values.md",
                "tutorial2_projection.md",
                "tutorial3_arrays.md",
                "tutorial4_blocks.md",
                "tutorial5_stochastic.md",
            ],
            "How-To Guides" => [
                "howto_choose_format.md",
                "howto_quantize_tensor.md",
                "howto_blocks_dynamic_range.md",
                "howto_reproducible_stochastic.md",
                "howto_packed_storage.md",
                "howto_register_approx.md",
                "howto_float16_interop.md",
                "howto_conformance.md",
            ],
            "Explanation" => [
                "explain_formats.md",
                "explain_projection_contract.md",
                "explain_session_defaults.md",
                "explain_float16.md",
                "explain_random.md",
                "explain_no_promotion.md",
                "explain_performance.md",
            ],
            "Reference" => [
                "ref_formats.md",
                "ref_projections.md",
                "ref_operations.md",
                "ref_defaults.md",
                "ref_arrays_blocks.md",
                "ref_conformance.md",
                "ref_external.md",
                "ref_internal.md",
            ],
        ],

        "Insights" => [
            "under_architecture.md",
            "under_engine.md",
            "under_oracle.md",
            "under_tables.md",
            "under_blocks.md",
            "under_verification.md",
            "howto_add_operation.md",
            "howto_verify_custom.md",
            "howto_benchmark.md",
            "under_recipes.md",
        ],

        "Support" => [
            "troubleshooting.md",
            "glossary.md",
            "examples_index.md",
            "cheatsheet.md",
            "benchmarks.md",
        ],

        "Standard & Design Papers" => [
            "papers_index.md",
        ],
    ],
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)
