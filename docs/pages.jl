# Shared navigation for the HTML and PDF builds. Keep every authored page here:
# Documenter uses this list both to order the manual and to report orphaned pages.
const DOC_PAGES = [
    "Home" => "index.md",

    "Start Here" => [
        "Installation" => "install_and_verify.md",
        "First Session" => "first_session.md",
        "Core Model" => "core_model.md",
    ],

    "Workflows" => [
        "Choose a Format" => "workflow_choose_format.md",
        "Quantize and Measure a Tensor" => "workflow_quantize_measure.md",
        "Control Rounding and Overflow" => "workflow_rounding_overflow.md",
        "Run Operations over Arrays" => "workflow_arrays.md",
        "Use Blocks for Dynamic Range" => "workflow_blocks.md",
        "Make Stochastic Work Reproducible" => "workflow_stochastic.md",
        "Pack Values for Storage" => "workflow_packed_storage.md",
        "Interoperate with Float16 and BFloat16" => "workflow_float16.md",
        "Produce a Conformance Declaration" => "workflow_conformance.md",
        "Register and Measure an Approximation" => "workflow_approximation.md",
    ],

    "Concepts" => [
        "P3109 in One Chapter" => "concept_p3109.md",
        "Format Anatomy" => "concept_format_anatomy.md",
        "Values, Code Points, and Conversion" => "concept_values_codepoints.md",
        "The Exact-Then-Project Contract" => "concept_exact_then_project.md",
        "Rounding and Saturation" => "concept_rounding_saturation.md",
        "Julia's Numeric Model" => "concept_julia_numeric.md",
        "Session State and Reproducibility" => "concept_session_state.md",
        "Performance Model" => "concept_performance.md",
        "Defined, Stochastic, and Approximate Results" => "concept_defined_stochastic_approximate.md",
        "Code-Point Algebra" => "concept_codepoint_algebra.md",
    ],

    "Reference" => [
        "Formats and Values" => "reference_formats_values.md",
        "Projection Specifications" => "reference_projections.md",
        "Operation Catalog" => "reference_operations.md",
        "Arrays, Blocks, and Packed Storage" => "reference_arrays_blocks_storage.md",
        "Defaults, Randomness, and Display" => "reference_defaults_random_display.md",
        "Julia Compatibility" => "reference_julia_compat.md",
        "Conformance and Approximation" => "reference_conformance.md",
        "Public API Index" => "reference_public_api.md",
        "Internal API Index" => "reference_internal_api.md",
    ],

    "Examples and Evidence" => [
        "Gallery" => "examples_gallery.md",
        "Applied Sessions" => "examples_applied.md",
        "Verification Sessions" => "examples_verification.md",
        "Performance Sessions" => "examples_performance.md",
    ],

    "Implementation" => [
        "Architecture and Invariants" => "internals_architecture.md",
        "Encoding and Decoding" => "internals_encoding_decoding.md",
        "Projection Engine" => "internals_projection_engine.md",
        "Oracle and Rigor Classes" => "internals_oracle.md",
        "Function Tables and Array Kernels" => "internals_tables.md",
        "Exact Block Reductions" => "internals_blocks.md",
        "Verification Strategy" => "internals_verification.md",
        "Add an Operation" => "internals_add_operation.md",
        "Verify Custom Code" => "internals_verify_custom.md",
        "Benchmark Correctly" => "internals_benchmark.md",
    ],

    "Help" => [
        "Troubleshooting" => "help_troubleshooting.md",
        "Cheat Sheet" => "help_cheat_sheet.md",
        "Glossary" => "help_glossary.md",
        "Standard and Design Notes" => "help_standard_design.md",
    ],
]
