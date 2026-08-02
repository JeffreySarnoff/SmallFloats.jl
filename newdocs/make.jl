# ===== docs/make.jl — Documenter build definition
#
# Invoked by docs/builddocs.jl for local builds, or directly on CI with the docs
# environment already instantiated:  julia --project=docs docs/make.jl
#
# Source of truth for the site is docs/src/ (the restructured documentation).
# Builds the merged documentation set in newdocs/src.
#
# Organization: Diátaxis (tutorial / how-to / explanation / reference) as the
# backbone, plus three sections that axis does not cover — Foundations (the
# code-point algebra), Examples (complete runnable sessions), and Insights
# (internals and extension). See newdocs/src/index.md for what each is for.

using Documenter
using SmallFloats

# The Benchmarks page is the generated report from benchmarking/, copied into the
# src source tree at build time so the site always ships the numbers currently
# recorded there. Regenerate with:  julia --project=benchmarking \
#     benchmarking/benchmarking.jl benchmarking/benchmark_report.md
cp(joinpath(@__DIR__, "..", "benchmarking", "benchmark_report.md"),
   joinpath(@__DIR__, "src", "benchmarks.md"); force = true)

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
    pages = [
        "Home" => "index.md",

        "Getting Started" => [
            "installation.md",
            "quickstart.md",
            "mentalmodel.md",
            "fifteenminutes.md",
        ],

        "Tutorials" => [
            "tutorial1_values.md",
            "tutorial2_projection.md",
            "tutorial3_arrays.md",
            "tutorial4_blocks.md",
            "tutorial5_stochastic.md",
        ],

        "How-To" => [
            "howto_choose_format.md",
            "howto_quantize_tensor.md",
            "howto_blocks_dynamic_range.md",
            "howto_reproducible_stochastic.md",
            "howto_packed_storage.md",
            "howto_float16_interop.md",
            "howto_register_approx.md",
            "howto_conformance.md",
        ],

        "Explanations" => [
            "explain_formats.md",
            "explain_projection_contract.md",
            "explain_session_defaults.md",
            "explain_float16.md",
            "explain_no_promotion.md",
            "explain_random.md",
            "explain_performance.md",
        ],

        "Reference" => [
            "ref_formats.md",
            "ref_projections.md",
            "ref_operations.md",
            "ref_defaults.md",
            "ref_arrays_blocks.md",
            "ref_julia_compat.md",
            "ref_conformance.md",
            "ref_external.md",
            "ref_internal.md",
        ],

        "Foundations" => [
            "formal_codepoints.md",
        ],

        "Examples" => [
            "examples_index.md",
            "examples_applied.md",
            "examples_internals.md",
        ],

        "Insights" => [
            "under_architecture.md",
            "under_engine.md",
            "under_oracle.md",
            "under_tables.md",
            "under_blocks.md",
            "under_verification.md",
            "under_recipes.md",
            "howto_add_operation.md",
            "howto_verify_custom.md",
            "howto_benchmark.md",
        ],

        "Support" => [
            "cheatsheet.md",
            "benchmarks.md",
            "troubleshooting.md",
            "papers_index.md",
            "glossary.md",
        ],
    ],
    # The guides intentionally reference some names that carry no docstrings yet
    # (docstring coverage is tracked work); keep those as warnings, not failures.
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)

# Publishes to the gh-pages branch from CI (no-ops on local builds, which lack
# the deploy credentials). Requires GitHub Pages to serve from gh-pages.
deploydocs(;
    repo = "github.com/JeffreySarnoff/SmallFloats.jl",
    devbranch = "main",
    push_preview = true,
)
