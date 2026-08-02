# Examples Index

Every worked example in the documentation, in one list. Each title links to the
example itself. All are runnable as shown; outputs were captured from real
sessions and seeds are fixed, so you can reproduce them exactly.

The examples live on two pages, split by the level they work at rather than by
subject:

- **[Applied](examples_applied.md)** — the public API only. Format choice,
  quantization, blocks, stochastic rounding, packing.
- **[Internals](examples_internals.md)** — unexported machinery. Pipeline
  introspection, exhaustive self-verification, κ measurement, benchmarking.
  Stable enough to learn from, not covered by semver.

---

## Basic

| example | what it shows |
|:---|:---|
| [One value, every rounding mode](tutorial2_projection.md#One-value,-every-rounding-mode) | the six deterministic μ side by side on one between-grid value |
| [Enumerating a whole format](tutorial1_values.md#Enumerating-a-whole-format) | a 16-point format printed in full, in total order |
| [Saturation in one line each](examples_applied.md#Saturation-in-one-line-each) | `SatNone` / `SatFinite` / `SatPropagate` on the same overflow |
| [Random values under a chosen projection](examples_applied.md#Random-values-under-a-chosen-projection) | `rand`/`randn` land on code points through the engine |
| [Watching RoundToPrecision work](examples_internals.md#Watching-RoundToPrecision-work) | the exact `(sign, S, Q)` decomposition before saturation sees it |
| [Symbolic sticky](examples_internals.md#Symbolic-sticky:-projecting-just-below-a-number) | how directed modes land exactly on asymptotes |
| [Tables are the scalar path, memoized](examples_internals.md#Tables-are-the-scalar-path,-memoized) | table entry ≡ scalar result, by construction |
| [Order keys](examples_internals.md#Order-keys) | the sign–magnitude fold that comparisons and the counting sort run on |

## General AI

| example | what it shows |
|:---|:---|
| [Log-odds belief updating](examples_applied.md#Log-odds-belief-updating-—-and-where-tiny-formats-bite-reasoning) | the running belief drifts far from exact while the threshold decision stays correct — order survives quantization when magnitude does not |
| [Fuzzy inference in an unsigned format](examples_applied.md#Fuzzy-inference-in-an-unsigned-format) | Gödel t-norm/s-norm and product t-norm as bit-exact registry ops, so a rule base reproduces to the code point across machines |
| [Search heuristics keep the ordering](examples_applied.md#Search-heuristics:-what-quantized-scores-keep-is-the-ordering) | 200 scores collapse onto 78 code points; argmax and top-k survive |
| [Exhaustive monotonicity audit](examples_internals.md#Ranking-safety:-an-exhaustive-monotonicity-audit-of-score-conversion) | proving by enumeration that a format conversion never inverts the total order |
| [κ-safe decision margins](examples_internals.md#κ-safe-decision-margins-for-approximate-evaluators) | two results more than 2κ code points apart cannot have their comparison inverted — and the exhaustive check of that rule |

## Machine Learning

| example | what it shows |
|:---|:---|
| [Quantizing a weight tensor](examples_applied.md#Quantizing-a-weight-tensor-and-measuring-the-damage) | MSE, max error, overflow fraction — the three-number check for any quantization |
| [Picking a format: precision vs range](examples_applied.md#Picking-a-format:-precision-vs-range) | RMSE and MaxFinite across four `K = 8` formats on the same data |
| [Stochastic rounding is unbiased](examples_applied.md#Stochastic-rounding-is-unbiased-where-nearest-is-not) | where nearest accumulates a systematic drift and stochastic does not |
| [Verifying a quantizer exhaustively](examples_internals.md#Verifying-a-quantizer-exhaustively-against-an-independent-reference) | your own code checked against an independent reference over every input |
| [The κ workflow, including the refusal](examples_internals.md#The-κ-workflow,-including-the-part-where-it-says-no) | registration rejecting an understated κ — the registry measures, it does not trust |
| [Exporting the conformance declaration](examples_internals.md#Exporting-the-conformance-declaration) | what you hand a reviewer |

## Deep Learning

| example | what it shows |
|:---|:---|
| [MX-style block quantization](examples_applied.md#MX-style-block-quantization-—-and-the-staging-pitfall) | shared-scale blocks, and the staging mistake that silently costs accuracy |
| [Quantized dot products, one rounding](examples_applied.md#Quantized-dot-products-with-one-final-rounding) | all lane products accumulated exactly, projected once at the end |
| [The swamping demo](examples_applied.md#Why-training-loops-like-stochastic-rounding:-the-swamping-demo) | why a training loop stalls under nearest and does not under stochastic |
| [Activations are 256-byte tables](examples_applied.md#Activation-functions-are-256-byte-lookup-tables) | a whole unary op *is* its table, at a fraction of a nanosecond per element |
| [Packing a quantized model](examples_applied.md#Packing-a-quantized-model) | bit-packed storage at K not a multiple of 8 |
| [Proving a fused kernel exact](examples_internals.md#Proving-your-fused-kernel-exact:-BlockDotProduct-vs-512-bit-truth) | `BlockDotProduct` against 512-bit truth |
| [Stochastic rounding, audited](examples_internals.md#Stochastic-rounding,-audited:-the-full-R-sweep) | the full-R sweep: every random draw, not a sample |
| [Hard-tanh κ measurement](examples_internals.md#An-accelerator-style-activation,-κ-measured:-hard-tanh-vs-Tanh) | an accelerator-style activation, measured rather than assumed |
| [Benchmarking without measuring the dispatcher](examples_internals.md#Benchmarking-without-measuring-the-dispatcher) | the two measurement post-mortems this package learned from |

## Verification

| example | what it shows |
|:---|:---|
| [Checking the code-point algebra](examples_internals.md#Checking-the-code-point-algebra-against-the-package) | every distinguished code of all 504 formats, and the decoding formula at every positive finite code point |

---

## See also

Task-shaped instructions, as opposed to worked demonstrations, are in the
How-To section — start at [Choosing a Format](howto_choose_format.md). The
difference: a how-to tells you what to do, an example shows a complete session
with its output and discusses what the output means.
