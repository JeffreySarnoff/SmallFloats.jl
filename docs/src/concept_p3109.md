# P3109 in One Chapter

The IEEE P3109 draft — *Arithmetic Formats for Machine Learning* — as this
package sees it. Fifteen minutes here buys you the vocabulary every other page
assumes. Claims are tagged with the draft clause they come from; the full
transliteration is in the repository at `docs/other/IEEE_D1.md` for when you
want the normative text itself.

## The one law everything hangs on

Every numeric operation in the draft is three steps (§4.3.2):

```
decode the operands  →  compute exactly over the extended reals  →  project once
```

There is no arithmetic "in the format." Operands are decoded to exact values,
the operation is performed exactly, and a single projection — rounding plus
saturation — writes the result back to a code point. The comparisons and
predicates stop after decoding (they return Booleans); everything else follows
the law. SmallFloats.jl is built as a direct implementation of this sentence.

## Formats: four parameters, 504 instances

A format is `Binary{K, P, Σ, Δ}` (§3.1):

| parameter | meaning | range |
|:---|---|---|
| `K` | total bitwidth | 3 – 16 |
| `P` | significand precision, implicit bit included | signed: `0 < P < K`; unsigned: `0 < P ≤ K` |
| `Σ` | signedness: signed or unsigned | |
| `Δ` | domain: **extended** (has ±Inf) or **finite** | |

The short name reads off the parameters: `Binary8p4se` = K 8, p 4, **s**igned,
**e**xtended. The draft's exponent bias is *derived*, not chosen (§3.1, §4.14):

```
B = 2^(K−P−1)   (signed)        B = 2^(K−P)   (unsigned)
```

This symmetric-about-the-midpoint bias is the single most consequential formula
in the draft — see "Differences from IEEE 754" below.

## Datums and code points

A format's *datum set* is a finite subset of the closed extended reals
(ℝ plus ±Inf and NaN), in bijection with the code points `0 … 2^K − 1` (§3,
Annex B). Every finite datum has a canonical form

```
(−1)^sign · S · 2^(1−P) · 2^E        E > −B
```

with significand `S` classifying it as normal (`2^(P−1) ≤ S < 2^P`) or
subnormal (`0 < S < 2^(P−1)`).

The specials are where the draft parts company with IEEE-754 (Annex B, Table 3):

- **Exactly one zero.** There is no `−0`; a signed format has an odd number of
  finite datums.
- **Exactly one NaN**, sitting at the code point IEEE-754 gives to `−0` in
  signed formats. No payloads, no quiet/signalling distinction — the thousands
  of code points IEEE spends on NaN encodings are datums here.
- **±Inf only in extended formats**, adjacent to the finite extremes. A finite
  format spends those code points on more finite values.

## Projection: rounding × saturation

A projection specification ρ is the pair *(rounding mode, saturation mode)*
(§4.2, §4.7.3–4.7.5).

Six deterministic rounding modes — `NearestTiesToEven`, `NearestTiesToAway`,
`TowardPositive`, `TowardNegative`, `TowardZero`, `ToOdd` — plus three
stochastic families `StochasticA/B/C`, which consume `N` random bits as an
unsigned draw `R ∈ 0 … 2^N − 1` (§4.7.4; the draft deliberately leaves the
bit source unspecified).

Three saturation modes decide what out-of-range results become (§4.7.5):

| mode | finite overflow | ±Inf input |
|:---|---|---|
| `SatFinite` | clamp to the finite extremes | clamp |
| `SatPropagate` | clamp | preserve representable infinities, else clamp |
| `SatNone` | the draft's rows: to ±Inf, finite extreme, or NaN depending on rounding direction, signedness, and domain | preserve, else NaN |

One ordering fact the whole clause turns on (§4.7.3 NOTE 1): **rounding
precedes saturation**, but the rounding mode is passed *into* saturation so a
directed mode can force a finite result. Saturation itself never rounds.

## The operation catalog

§4.9–§4.16 define the catalog: `Convert`; sign and basic arithmetic (`Abs`
through `Divide`, fused `FMA` and `FAA`); the elementary functions (roots,
exp/log families, trig, hyperbolic, π-scaled trig, `Softplus`, `Hypot`,
`ArcTan2`); the extrema families (`Minimum`/`Maximum` and their NaN-quieting,
magnitude, and finite variants, plus `Clamp`); comparisons, predicates, and
`TotalOrder`; format-level queries (`BitwidthOf`, `MaxFiniteOf`, …); and the
neighbour operations `NextGreaterThan`/`NextLessThan`.

Some results are visible only in the pattern tables, and they surprise:

- `Divide(x, 0) = NaN` for every `x` — including ±Inf (§4.10.5 NOTE 2). There
  is no IEEE-style ±Inf quotient.
- `Recip(±Inf) = 0` and `Recip(0) = NaN` (§4.10.8).
- `TotalOrder` puts NaN first, below −Inf — deterministic tie-breaking for
  search and sort (§4.12.1), and the opposite end from Julia's float-sorting
  convention.
- `NextGreaterThan(+Inf) = NaN`, unlike IEEE-754 `nextUp` (§4.16 NOTE 2).
- `FAA` is associative by construction: `Add(Add(X,Y),Z) = Add(X,Add(Y,Z))`
  computed exactly (§4.10.7).

## Blocks and scaled operations

Clause 5 adds the MX-style scheme: a *block* is a scale factor in one format
plus `B` elements in another, representing `scale × element` per lane. Block
operations decode lanes exactly, apply the operation, and project against a
result scale; the reductions (`BlockReduceAdd`, `BlockDotProduct`) accumulate
exactly and project once. `ScaledOp` is the block-size-1 form. This is how the
draft tracks dynamic range that a bare element format cannot hold.

## Conformance and κ

The draft's conformance machinery (§4.4–4.6) has two levels. A *conforming
implementation* produces the defined result for every operation, format, and
mode. A *κ-approximate implementation* may deviate, but must declare its
maximum code-point distance κ from the defined result — measured along the
total order, over inputs with finite defined results. Approximation is thus
quantified and declared, never silent; SmallFloats implements both levels and
measures κ by exhaustive enumeration at registration.

## Differences from IEEE 754

`Binary16p11se` looks like `Float16`; `Binary16p8se` looks like `BFloat16`.
They are not (Annex F compares them explicitly):

| | `Binary16p11se` | `Float16` | `Binary16p8se` | `BFloat16` |
|:---|---|---|---|---|
| exponent bias | **16** | **15** | **128** | **127** |
| largest finite | **65472** | **65504** | **3.3762e38** | **3.3895e38** |
| NaN encodings | **1** | **2046** | **1** | **2046** |
| negative zero | **no** | yes | **no** | yes |

P3109's bias formula makes the exponent range symmetric about the midpoint;
IEEE-754's is `2^(E−1) − 1`. The two differ by one, so **every code point
denotes a value a factor of two away from its IEEE look-alike**. The same bits
read as the other type silently halve or double every value. Converting
between them is a conversion, never a reinterpretation.

## Continue

[Core Model](core_model.md),
[The Standard and this Design](help_standard_design.md),
[First Session](first_session.md).
