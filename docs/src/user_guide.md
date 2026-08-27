# User Guide

Everything needed to use SmallFloats.jl, in the order it becomes useful. The
public model is deliberately small — a format is a finite datum set; a value
names one datum by a code point; an operation evaluates exactly and then
projects once under an explicit policy — and each page of this guide answers
one question that model raises.

Read [First Session](first_session.md) first if you have not constructed a
`Binary` value yet. This guide routes; the pages carry the examples and the
boundary conditions.

## What the standard says, and what a format is

*Where do these rules come from?* [P3109 in One Chapter](concept_p3109.md) is
the draft in fifteen minutes: the decode → compute exactly → project once law,
the four format parameters, the single NaN and absent negative zero, and the
bias formula that makes `Binary16p11se` differ from `Float16` at every code
point.

*What exactly is `Binary8p4se`?* [Format Anatomy](concept_format_anatomy.md)
answers with the four-parameter space `Binary{K,P,SGN,EXT}`, the line between
the abstract format and the concrete representation your arrays must use, and
the three routes to all 504 formats when the 120 exported aliases are not
enough.

## Values and computation

*How does a value name a datum?* [Values, Code Points, and
Conversion](concept_values_codepoints.md). The rule worth retaining: an
`Unsigned` constructor argument is a code point, every other `Real` is a value
to project — and `decode` is always exact, on the format's own carrier.

*What does an operation promise?* [The Exact-Then-Project
Contract](concept_exact_then_project.md): exact math first, one projection at
the end, no second write path — plus what "exact" means at each carrier width
and why `Rational` input is refused rather than double-rounded.

*Who decides where an exact result lands?* [Rounding and
Saturation](concept_rounding_saturation.md) develops the two independent
policy axes a `ProjSpec` names. Use [Control Rounding and
Overflow](workflow_rounding_overflow.md) when you want a short procedure for
choosing and testing one.

## Living inside Julia

*What happens when `Binary` meets ordinary numbers?* [Julia's Numeric
Model](concept_julia_numeric.md): mixed formats fail loudly, ordinary numbers
promote to the format's carrier, and no automatic format-widening rule can be
built soundly — the page explains why.

*What does session state control?* [Session State and
Reproducibility](concept_session_state.md): the five process-global defaults
behind `T(x)`, `x + y`, and friends — and why reusable code names its policy
instead of relying on them.

## Results and their provenance

*Why did two runs differ?* [Defined, Stochastic, and Approximate
Results](concept_defined_stochastic_approximate.md) keeps the three legitimate
reasons apart and gives the four-question provenance test that separates all
of them from a defect.

*What is underneath it all?* [Code-Point Algebra](concept_codepoint_algebra.md)
states the package as integer identities — where NaN sits, how a code decodes,
how ordering is recovered — verified against all 504 formats.

## Working with data

The Workflows chapter applies the model. [Choose a
Format](workflow_choose_format.md) turns precision, range, domain, and storage
requirements into a reproducible choice; [Quantize and Measure a
Tensor](workflow_quantize_measure.md) compares such choices under one fixed
projection rather than changing data and policy at once. For bulk work,
continue to [Run Operations over Arrays](workflow_arrays.md), [Use Blocks for
Dynamic Range](workflow_blocks.md), and [Pack Values for
Storage](workflow_packed_storage.md). One rule holds throughout: acceleration
may change how work is scheduled, never which projected code point is
returned.

For interoperability and evidence: [Interoperate with Float16 and
BFloat16](workflow_float16.md), [Make Stochastic Work
Reproducible](workflow_stochastic.md), [Produce a Conformance
Declaration](workflow_conformance.md), and [Register and Measure an
Approximation](workflow_approximation.md).

## See also

[Cheat Sheet](help_cheat_sheet.md) for syntax at a glance,
[Example Gallery](examples_gallery.md) for runnable end-to-end sessions, and
[Technical Guide](technical_guide.md) for the implementation and verification
arguments behind these guarantees.
