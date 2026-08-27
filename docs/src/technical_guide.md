# Technical Guide

This is the maintainer's route through SmallFloats.jl. One semantic promise —
compute the defined result, then project it once — is preserved across two
code-unit representations, three carrier rungs, and every acceleration layer,
and each page of this guide answers one question that preservation raises.
Read the [User Guide](user_guide.md) first; this guide assumes its vocabulary.

## Two questions organize the implementation

[Architecture and Invariants](internals_architecture.md) is the entry point.
It separates two questions that must never be conflated:

1. **What carries an exact datum or intermediate?** The format selects a
   carrier rung — `Float64`, `Float128`, or the exact dyadic carrier — from
   its range requirements.
2. **Why is an operation result justified?** The oracle attaches a rigor
   class, from unconditional exactness through validated envelopes.

That separation is what lets `Code8` and `Code16` share public semantics while
using different storage, decode, table, and compute policies.

## Follow one datum through the package

*How does a code point become a value, and a value a code point?*
[Encoding and Decoding](internals_encoding_decoding.md) owns the
format-to-representation seam, `decodepolicy`, the exact carriers, encode's
code-unit-generic output, and the total-order keys.
[Projection Engine](internals_projection_engine.md) is the other direction:
`RoundToPrecision → Saturate → Encode`, the only route that writes a result
code point.

*Where does the exact result come from?* [Oracle and Rigor
Classes](internals_oracle.md): exact arithmetic, the Dyadic/Rational bridge,
interval agreement, and conservative fallback. The relationship is
directional — the oracle establishes a value or an enclosure; the projection
engine decides the code point. Neither is a second definition of the other.

## Performance layers are semantic layers first

*Why is caching sound?* [Function Tables and Array
Kernels](internals_tables.md): a table entry is the scalar path memoized, and
admission is a resource policy, never a semantic one. *Why are fused
reductions exact without a superaccumulator?* [Exact Block
Reductions](internals_blocks.md) makes that argument in full. [Performance
Model](concept_performance.md) and [Benchmark
Correctly](internals_benchmark.md) turn those internals into measurement
practice without promoting one machine's timings to a guarantee.

## Keep an extension honest

Use [Add an Operation](internals_add_operation.md) for the implementation
checklist and its worked examples, [Verify Custom
Code](internals_verify_custom.md) for an independent audit route, and
[Verification Strategy](internals_verification.md) for the package-wide
doctrine — enumerate rather than sample, and say "sampled" in so many words
where enumeration is unaffordable. The [Documentation Claim
Ledger](claim_ledger.md) tracks each implementation-sensitive claim in these
pages back to its source authority. An extension is complete only when its
semantics, projection, applicable table policy, evidence, documentation, and
benchmark scope agree.

## See also

[Technical Examples](examples_verification.md),
[Performance Evidence](examples_performance.md), and the
[Internal API Index](reference_internal_api.md).
