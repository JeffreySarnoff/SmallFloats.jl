# Projection Engine

Projection is the only write path into a code point. Constructors, conversions,
operations, table construction, and block results all converge here.

```text
exact result → RoundToPrecision → Saturate → Encode
```

## Public promise

Given a result format, projection specification, and exact mathematical value,
the engine returns the P3109-defined code point. No faster path is allowed to
substitute a second rounding routine.

## RoundToPrecision

The rounding stage produces a canonical `Rounded(kind, sign, S, Q)`. `S` and
`Q` describe a scaled significand exactly; `kind` distinguishes finite and
special results.

Two implementations cover the supported carriers:

- the generic core scales an exact or enclosed carrier and compares the
  discarded fraction with the selected mode's decision points;
- the `Float64` mask core extracts sign, exponent, and significand fields and
  performs the same decisions with integer operations.

The mask core is an optimization only. Specials, subnormal carrier inputs, or
cases outside its proof obligations fall back to the generic core. Equivalence
tests establish that the two implementations choose the same rounded result.

## Symbolic sticky

An interval or asymptotic computation sometimes knows that the true value is
immediately above or below an exactly representable endpoint without possessing
a distinct carrier value for that infinitesimal displacement.

`sticky ∈ {-1,0,+1}` carries that relation into every rounding comparison. The
delicate “just below a datum” case crosses into the preceding binade and uses a
fraction of `1⁻`; treating it as the endpoint itself would give the wrong answer
for directed modes and ties.

## Saturate

The saturation stage classifies the rounded result against the result format's
range and applies the draft's saturation rows. A disposition can be:

- as-is;
- minimum or maximum finite;
- positive or negative infinity;
- NaN.

Classification uses canonical integer fields rather than an inexact carrier
comparison. Signed and unsigned formats, finite and extended domains, rounding
direction, and special operation results all participate in the row choice.

## Encode

Encoding assembles the final code point with integer operations. It handles
significand carry, normal/subnormal boundaries, exponent fields, special
encodings, and the single-zero rule. Encode does not make another numerical
decision; all policy has already been resolved.

## Source map

- projection orchestration and saturation: `src/project.jl`;
- rounding cores and rounded representation: the rounding implementation files
  under `src/`;
- operation-to-exact-result dispatch: `src/oracle.jl` and operation files;
- encoding and raw value construction: `src/decode_encode.jl`.

## Evidence

Required gates include deterministic and stochastic rounding predicates,
generic/mask equivalence, boundary saturation rows, carrier escalation,
symbolic-sticky cases, and exhaustive code-point results where the input space
is affordable. Array tables are compared entry-for-entry with this scalar path.

## Extension seam

An optimization may bypass work only after proving that it returns the same
canonical rounded form or final code point. A new rounding or saturation mode
belongs in the shared `ProjSpec` machinery and its exhaustive predicate tests,
not in an operation-specific shortcut.

## Next

[Oracle and Rigor Classes](internals_oracle.md).
