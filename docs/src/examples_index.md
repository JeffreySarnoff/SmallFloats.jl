# Examples from AI

A map of the worked examples. Each is identified in boldface and briefly described. The source for each example is linkded.

## General AI

**Log-odds belief updating.** Accumulating log-likelihood ratios in an 8-bit
format: the running belief can drift far from the exact value while the
threshold decision it drives stays correct — order survives quantization even
when magnitude does not. Source: [User Examples — General AI](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L119).

**Fuzzy inference in unsigned formats.** Membership degrees on `[0, 1]`
evaluated with an unsigned finite format; the classic fuzzy connectives
(Gödel t-norm, s-norm, product t-norm) are bit-exact registry operations, so
a fuzzy rule base reproduces to the code point across machines. Source:
[User Examples — General AI](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L156).

**Search-heuristic ordering and a monotonicity audit.** Quantizing 200
heuristic scores to 8 bits collapses many distinct scores onto shared code
points, yet argmax and top-k survive; a companion exhaustive walk proves a
format conversion never inverts the total order. Sources:
[User Examples — General AI](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L183),
[Technical Examples — General AI](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L75).

**κ-safe decision margins for approximate evaluators.** Turning a measured κ
bound into a provable rule — two evaluations more than 2κ code points apart
cannot have their comparison inverted by a κ-bounded approximate evaluator —
and verifying the rule exhaustively. Source:
[Technical Examples — General AI](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L112).

## Machine Learning

**Quantizing a weight tensor and measuring the damage.** Projecting a
Gaussian weight tensor into an 8-bit format and reporting MSE, max error, and
overflow fraction as the three-number check for any quantization. Source:
[User Examples — Machine Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L211).

**Picking a format: precision vs range.** A table of RMSE and MaxFinite
across four `K = 8` formats trading significand bits for exponent range on
the same data. Source: [User Examples — Machine Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L231).

**Stochastic unbiasedness.** Nearest rounding is systematically biased on a
fixed input; stochastic rounding is unbiased on average — the property that
matters for accumulating many small contributions in low precision. Source:
[User Examples — Machine Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L255).

**Exhaustive quantizer verification.** Checking every in-range code point of
a quantizer against an independent 256-bit reference computation, rather
than spot-checking. Source: [Technical Examples — Machine Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L157).

**κ workflow with rejection.** Registering an approximate kernel, measuring
its κ by exhaustive enumeration, and watching the registry refuse an
understated κ declaration. Source: [Technical Examples — Machine Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L197).

**Conformance export.** Producing a machine-readable conformance dictionary
suitable for attaching to experiment artifacts. Source:
[Technical Examples — Machine Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L221).

## Deep Learning

**MX block quantization and the staging pitfall.** Per-row block scales
tracking dynamic range a bare element format cannot, plus the specific case
of staging through the narrow element format before block-quantizing — which
silently discards the benefit. Source: [User Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L277).

**One-rounding dot products.** `BlockDotProduct` computing every lane product
and the accumulation exactly, then rounding exactly once. Source:
[User Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L322).

**Swamping and stall demo.** Accumulating many small gradient steps under
nearest rounding stalls completely once the accumulator dwarfs the
increment; stochastic rounding keeps absorbing the increments in
expectation. Source: [User Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L340).

**Activation LUT audit.** An 8-bit unary activation is a 256-byte lookup
table; auditing saturation fraction and distinct output codes is cheap
enough to run for every candidate nonlinearity. Source:
[User Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L369).

**Hard-tanh κ measurement.** Measuring the worst-case code-point deviation of
a piecewise hardware-style activation against the defined activation,
exhaustively, and registering it under the measured bound. Source:
[Technical Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L291).

**Packing a quantized model.** Storing a million-element quantized model in
a `PackedVector` at the format's true bitwidth instead of a full byte per
element. Source: [User Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/user_examples.md#L415).

**BlockDotProduct 512-bit verification.** Proving a fused block dot-product
kernel exact against 512-bit big-float truth over random blocks with mixed
scales and a special-value mix — the pattern to reuse for any custom fused
kernel. Source: [Technical Examples — Deep Learning](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/oldsrc/technical_examples.md#L234).

## see also

[How-Tos](howto_choose_format.md),
[Architecture Overview](under_architecture.md),
[Cheat Sheet](cheatsheet.md).
