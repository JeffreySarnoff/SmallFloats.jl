# The Encoding & Projection Engine

## Encoding and decoding

A value is its code point (`UInt8`). The bit layout is the draft's: sign (signed
formats), biased exponent, trailing significand; one NaN at the negative-zero slot;
no −0; ±Inf adjacent to the extremes in extended formats.

`decode` has **two shapes, selected by `decodepolicy(T)`** — a representation
decision, not a semantic one.

At `K ≤ 8` it is a **`@generated` constant-tuple lookup**: per format, a
`2^K`-tuple of datums built once from the computational decode (so table and
computation are correct by construction and asserted equivalent exhaustively).
Constant inputs still fold — `maxfinite_datum(T)` is a compile-time constant —
while runtime decode is a single indexed load (≈ 0.7 ns). Above `K = 8` a
`2^16`-tuple is not a constant worth materializing, so the computational decode
runs directly.

The computational decode assembles the datum **by bits** (normalize with
`leading_zeros`, place exponent and mantissa fields, `reinterpret`) wherever the
carrier is `Float64`.

**Which carrier that is depends on the format's exponent bias, and is the second
of the package's two axes.** `Float64`'s normal range holds every datum of the
432 formats at rung 1 — the property the bit-assembly rests on. It does not hold
the other 72: `Binary16p1uf` reaches `2^32768`. Those decode to `Float128`
(rung 2) or to an exact dyadic carrier (rung 3), chosen by `datumcarrier(T)`,
and every one of them is exact for the datums it accepts. So the invariant is not
"`Float64` is the exact carrier for all datums" — that was true only while
`K ≤ 8` — but the stronger and still-checkable one:

> **every format's datum carrier is exact for that format's datums**, and the
> choice is a dispatch decision derived from the exponent bias, never a caller's.

The suite checks it against an independent big-float transliteration of the
draft (gate G6, exhaustively over the `(datum, head)` pairs), and gate G4 checks
the consequence that matters: forcing a *wider* carrier never changes a code
point, so the choice buys time and never an answer.

Ordering runs on **integer order keys**: a sign-magnitude fold into an unsigned
type wide enough for the format's `2^K + 1` keys (`UInt16` at K ≤ 8, wider above),
monotone with the total order. Key `0` is reserved for the single NaN, which
the draft orders below −Inf (§4.12.1); every datum key is therefore ≥ 1.
Same-format `TotalOrder`,
`isless`, and the numeric comparisons are key comparisons (~1 ns); since a format has
at most `2^K + 1` distinct keys, vectors sort with an **O(n) counting sort**
installed via `Base.Sort.defalg` (forward and reverse orderings; anything exotic
falls back to the stock algorithm).

## The projection engine

`project(fr, ρ, X; R, sticky)` is the single write path into a code point:

```
RoundToPrecision  →  Saturate  →  Encode
```

**RoundToPrecision** produces a `Rounded(kind, sign, S, Q)` — an exact scaled
significand `S` and exponent `Q` per the draft's `Q = max(⌊log₂|X|⌋, 1−B) − P + 1`.
Two implementations, proven equivalent exhaustively:

- the **generic core** (`_rtp_core`) works on any carrier (`Float64`, `Float128`,
  `BigFloat`) via exact power-of-two scaling and a fraction ν compared against the
  mode's decision points;
- the **mask-based Float64 core** (`_rtp_f64`) extracts sign/exponent/significand
  fields directly, represents ν as a 128-bit fixed-point integer with an OR-mask
  sticky for bits shifted out, and evaluates every mode — including the stochastic
  `⌊ν·2^N⌋` comparisons and `RNITE` ties — as integer field tests. Specials, zeros,
  and (Convert-only-reachable) subnormal Float64 inputs bail to the generic core.

**Symbolic sticky** is how enclosures talk to the engine: `sticky ∈ {−1, 0, +1}`
declares the true value to be the carried value plus an infinitesimal of that sign.
The engine folds it into every comparison; the delicate case — true value just
*below* a representable dyadic — decrements into the previous binade and sets
ν = 1⁻ (encoded in the mask core as an all-ones fixed-point fraction, which
reproduces every predicate including the RNITE tie behavior). This is what lets
directed modes land exactly on asymptotes: `tanh → 1⁻` under `TowardNegative`
projects to `NextLessThan(1)`, automatically.

**Saturate** classifies against the format's range with two integer comparisons per
side, then maps the classification through the draft's twenty saturation rows to
`as-is / MaxFinite / MinFinite / ±Inf / NaN`. The comparisons stay cheap because:

- the extremal magnitude in canonical `(S, Q)` form is a constant-folded function
  of the type parameters;
- the rounded value and the extremum share one lexicographic `(Q, S)` order
  (subnormals and the lowest normal binade share the same `Q`);
- signed formats use sign–magnitude symmetry, and unsigned underflow is just the
  sign bit;
- an internal `HUGEQ` sentinel represents "finite but astronomically large" (the
  ν = 1⁻ image of an infinite endpoint), so directed `SatNone` clamps it to
  MaxFinite correctly.

**Encode** is pure integer bit assembly, including the significand-carry
renormalization and the subnormal/normal field split.

## see also

[The Oracle & Rigor Classes](under_oracle.md),
[Tables, Kernels & Sorting](under_tables.md),
[Internals Recipes](under_recipes.md).
