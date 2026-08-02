# Examples by Domain

A map of the worked examples, grouped by domain rather than by source
document. Each card names the example, what it shows in one line, and where
the full walkthrough now lives.

## General AI

**Log-odds belief updating.** Accumulating log-likelihood ratios in an 8-bit
format: the running belief can drift far from the exact value while the
threshold decision it drives stays correct — order survives quantization even
when magnitude does not. See: User Examples, General AI.

**Fuzzy inference in unsigned formats.** Membership degrees on `[0, 1]`
evaluated with an unsigned finite format; the classic fuzzy connectives
(Gödel t-norm, s-norm, product t-norm) are bit-exact registry operations, so
a fuzzy rule base reproduces to the code point across machines. See: User
Examples, General AI.

**Search-heuristic ordering and a monotonicity audit.** Quantizing 200
heuristic scores to 8 bits collapses many distinct scores onto shared code
points, yet argmax and top-k survive; a companion exhaustive walk proves a
format conversion never inverts the total order. See: User Examples, General
AI; Technical Examples, General AI.

**κ-safe decision margins for approximate evaluators.** Turning a measured κ
bound into a provable rule — two evaluations more than 2κ code points apart
cannot have their comparison inverted by a κ-bounded approximate evaluator —
and verifying the rule exhaustively. See: Technical Examples, General AI.

## Machine Learning

**Quantizing a weight tensor and measuring the damage.** Projecting a
Gaussian weight tensor into an 8-bit format and reporting MSE, max error, and
overflow fraction as the three-number check for any quantization. See: User
Examples, Machine Learning.

**Picking a format: precision vs range.** A table of RMSE and MaxFinite
across four `K = 8` formats trading significand bits for exponent range on
the same data. See: User Examples, Machine Learning.

**Stochastic unbiasedness.** Nearest rounding is systematically biased on a
fixed input; stochastic rounding is unbiased on average — the property that
matters for accumulating many small contributions in low precision. See:
User Examples, Machine Learning.

**Exhaustive quantizer verification.** Checking every in-range code point of
a quantizer against an independent 256-bit reference computation, rather
than spot-checking. See: Technical Examples, Machine Learning.

**κ workflow with rejection.** Registering an approximate kernel, measuring
its κ by exhaustive enumeration, and watching the registry refuse an
understated κ declaration. See: Technical Examples, Machine Learning.

**Conformance export.** Producing a machine-readable conformance dictionary
suitable for attaching to experiment artifacts. See: Technical Examples,
Machine Learning.

## Deep Learning

**MX block quantization and the staging pitfall.** Per-row block scales
tracking dynamic range a bare element format cannot, plus the specific case
of staging through the narrow element format before block-quantizing — which
silently discards the benefit. See: User Examples, Deep Learning.

**One-rounding dot products.** `BlockDotProduct` computing every lane product
and the accumulation exactly, then rounding exactly once. See: User Examples,
Deep Learning.

**Swamping and stall demo.** Accumulating many small gradient steps under
nearest rounding stalls completely once the accumulator dwarfs the
increment; stochastic rounding keeps absorbing the increments in
expectation. See: User Examples, Deep Learning.

**Activation LUT audit.** An 8-bit unary activation is a 256-byte lookup
table; auditing saturation fraction and distinct output codes is cheap
enough to run for every candidate nonlinearity. See: User Examples, Deep
Learning.

**Hard-tanh κ measurement.** Measuring the worst-case code-point deviation of
a piecewise hardware-style activation against the defined activation,
exhaustively, and registering it under the measured bound. See: Technical
Examples, Deep Learning.

**Packing a quantized model.** Storing a million-element quantized model in
a `PackedVector` at the format's true bitwidth instead of a full byte per
element. See: User Examples, Deep Learning.

**BlockDotProduct 512-bit verification.** Proving a fused block dot-product
kernel exact against 512-bit big-float truth over random blocks with mixed
scales and a special-value mix — the pattern to reuse for any custom fused
kernel. See: Technical Examples, Deep Learning.

Where next: [How-To Guides](howto_choose_format.md),
[Architecture Overview](under_architecture.md), and [Cheat Sheet](cheatsheet.md).
