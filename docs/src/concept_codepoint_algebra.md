# Formal Code-Point Algebra

Everything the package does to a `Binary{K,P,S,D}` value is integer arithmetic
on its code point. This page states that arithmetic as identities — where the
distinguished code points are, how a code decodes to a value, how the two
directions invert each other, and how ordering is recovered.

It is the layer *below* [Formats, Aliases & Representations](concept_format_anatomy.md).
Read that page for what a format is and how to name one; read this page when you
need to compute with code points, prove something about them, or check the
package against an independent derivation.

!!! note "Verified, not transcribed"
    Every identity below was checked against the package over **all 504
    formats** — the distinguished codes for each, and the decoding formula at
    **every positive finite code point** of every format. The check is the
    script in [Verification Sessions](examples_verification.md); it is the
    same kind of exhaustive enumeration the test suite runs, and it reported no
    disagreement.

    Source for the derivations and proofs: *Code-point forms for
    `Binary{K,P,S,D}`* (IEEE P3109 working material). This page carries the
    results and the verification; the proofs are there.

---

## Parameters

A format is four numbers. The package writes signedness and domain as `Bool`;
the algebra writes them as `0`/`1`, which is what makes the identities
one-liners rather than case analyses.

| symbol | meaning | value | package spelling |
|:---|:---|:---|:---|
| `K` | bitwidth — bits in the code | given, `3 ≤ K ≤ 16` | `bitwidth(T)` |
| `P` | precision — significand digits *including* the hidden bit | given, `1 ≤ P ≤ K−S` | `precision(T)` |
| `S` | signedness | `0` unsigned, `1` signed | `issigned(T)` |
| `D` | domain | `0` finite, `1` extended | `isextended(T)` |

## Derived quantities

| symbol | meaning | formula | package spelling |
|:---|:---|:---|:---|
| `Q` | total code points | `2^K` | — |
| `H` | sign-bit weight; signed-region offset | `2^(K−1)` | `signmask(T)` |
| `L` | trailing-significand patterns per exponent block | `2^(P−1)` | — |
| `Ebits` | exponent-field bitwidth | `K−P+1−S` | `expbitwidth(T)` |
| `B` | exponent bias | `2^(K−P−S) = 2^(Ebits−1)` | `expbias(T)` |
| `η` | minimum positive datum; the universal value quantum | `2^(2−P−B)` | `MinPositiveOf(T)` |
| `ν` | minimum positive normal | `2^(1−B) = Lη` | `MinNormalOf(T)` |
| `σ` | maximum positive subnormal | `(L−1)η = ν−η` (when `P > 1`) | `MaxSubnormalOf(T)` |
| `δ(j)` | ulp of exponent block `j` | `2^(j−B−P+1) = 2^(j−1)η` | — |

!!! warning "The bias is not the IEEE-754 one"
    P3109 uses `B = 2^(Ebits−1)`, where IEEE-754 uses `2^(Ebits−1) − 1`. The
    difference of one is exactly why `Binary16p11se` is not `Float16` — every
    code point denotes a different value. See
    [Why `Binary16p11se` is not `Float16`](workflow_float16.md).

## The NaN anchor

This is the structural keystone. The NaN code is

```text
N = Q − 1 − S(H − 1)
```

which specializes to `N = Q−1` (unsigned: all ones) and `N = H` (signed: sign
bit only, nothing else). Both signed and unsigned formats place the positive
exceptional endpoint immediately *below* `N`, so anchoring at `N` collapses
what would otherwise be a signed/unsigned case split into two one-line
identities:

```text
C(+∞)        = N − 1        (when D = 1)
C(MaxFinite) = N − 1 − D    always
```

Worked for `Binary8p4se` — `K=8, P=4, S=1, D=1`, so `Q=256, H=128, L=8, B=8`:

| quantity | formula | value | confirms |
|:---|:---|:---|:---|
| `N` | `255 − 1·127` | `128` = `0x80` | `Binary8p4se(NaN) ≡ 0x80` |
| `C(+∞)` | `N − 1` | `127` = `0x7f` | `Binary8p4se(Inf) ≡ 0x7f` |
| `M = C(MaxFinite)` | `N − 1 − D` | `126` = `0x7e` | `MaxFiniteOf(Binary8p4se) ≡ 0x7e` |

## Decoding: code to value

Split a positive finite code by Euclidean division on the block size `L`:

```text
j = c ÷ L        the biased exponent (unbiased: e = j − B)
t = c mod L      the trailing significand
```

Then the whole positive finite range decodes with **one** formula in each
regime, and the two agree at the boundary:

```text
V(c) = c · η                                    1 ≤ c < L      (subnormal)
V(c) = (L + t) · 2^(j−1) · η                    L ≤ c ≤ M      (normal)
```

The normal form is more familiar written as `V(c) = (1 + t/L)·2^(j−B)`, which
is the usual hidden-bit reading; the `η`-unit form above is the one to compute
with, because it is integer arithmetic times a single power of two.

!!! tip "Compute the exponent once"
    `(L + t) · 2^(j−1) · η` and `(L + t) · 2^(j−1+2−P−B)` are the same number,
    but the first overflows `Float64` at the wide formats while the second does
    not. This is not hypothetical — it is exactly the mistake the verification
    script for this page made on its first run, and it reported 1405 false
    "defects" in the package before the arithmetic was corrected. Combine the
    exponents, then `ldexp` once.

### Integer image

For positive finite `c`, `I(c) = V(c)/η` is an integer — the value counted in
quanta. Working in `I` turns questions about values into questions about
integers, which is what makes exhaustive proofs about small formats tractable.

## Within a binade

Inside one exponent block, code distance *is* ulp distance. For `c₁ ≤ c₂` with
`c₁ ÷ L = c₂ ÷ L = j`:

```text
V(c₂) − V(c₁) = (c₂ − c₁) · δ(j)
```

Two consequences the package relies on:

- **Midpoints are exact.** The value halfway between two same-binade neighbours
  is representable in the next precision up, which is what makes tie-breaking
  a decidable integer question rather than a floating-point comparison.
- **`codedistance` is meaningful.** The κ registry measures approximation error
  in *code points* precisely because within a binade that unit is proportional
  to the value error, and across binades it is the natural relative unit.

## Ordering

Raw code comparison is **not** a numerical order for signed formats: negative
values occupy the upper half with `C(x) = H + C(|x|)`, so more-negative values
have *larger* codes. The fix is a monotone key. For signed numerical codes,
excluding NaN:

```text
OrderKey(c) =
    Q − c,      H < c < Q       negative values, folded below H
    H,          c = 0           zero
    H + c,      0 < c < H       positive values, above H
```

with `V(c₁) < V(c₂)` iff `OrderKey(c₁) < OrderKey(c₂)`.

The algebra deliberately says nothing about where NaN goes — *"exceptional codes
must be handled according to their specified ordering or unordered semantics"*.
That is the draft's call, and P3109 §4.12.1 places the single NaN **below**
−Inf. The package therefore reserves key `0` for NaN and shifts every datum key
up by one, so:

```text
order_key(NaN) = 0  <  order_key(−Inf)  <  …  <  order_key(+Inf)
```

Which is why `sort` on a `Binary` vector puts NaN **first**, not last as
`Float64` sorting does. See [Julia Compatibility](reference_julia_compat.md) for what
that means for generic code.

## Sign, magnitude, negation

For signed formats and `c ∉ {0, N}`:

```text
MagCode(c) = c mod H        code of |V(c)|
NegCode(c) = c xor H        code of −V(c)
```

Negation is an involution with **one exception**: zero. There is a single zero
code (`c = 0`), and `0 xor H = H`, which is the NaN code `N` in a signed
format — not a negative zero. P3109 has no negative zero, and this is where
that shows up in the algebra.

## Parameter recovery

The format's parameters are recoverable from its own code lattice, which is the
basis of the round-trip validation the test suite performs: precision from the
block structure, bias from where the normal range begins, signedness from
whether the upper half mirrors the lower, and domain from whether `N−1` decodes
to an infinity or to a finite datum.

```text
S = [the upper half mirrors the lower]
D = [V(N−1) is infinite]
M = N − 1 − D
```

## Checking your own derivation

The formulas above are worth re-deriving if you are implementing against the
draft. To check a derivation against this package:

```julia
using SmallFloats
using SmallFloats: nan_code, posinf_code, expbias, MaxFiniteOf

T = Binary8p4se
K, P = bitwidth(T), precision(T)
S, D = issigned(T) ? 1 : 0, isextended(T) ? 1 : 0
Q, H, L, B = 1 << K, 1 << (K - 1), 1 << (P - 1), 1 << (K - P - S)
N = Q - 1 - S * (H - 1)

(N == Int(nan_code(T)),
 N - 1 == Int(posinf_code(T)),
 N - 1 - D == Int(codepoint(MaxFiniteOf(T))),
 B == expbias(T))
```

```
(true, true, true, true)
```

The exhaustive form of that check — every distinguished code of every one of
the 504 formats, plus the decoding formula at every positive finite code point
— is in [Verification Sessions](examples_verification.md).

## See also

- [Formats, Aliases & Representations](concept_format_anatomy.md) — what a format is,
  and the type-vs-alias distinction.
- [Encoding and Decoding](internals_encoding_decoding.md) — how the package walks
  this algebra at speed.
- [Why `Binary16p11se` is not `Float16`](workflow_float16.md) — the bias
  difference, stated in these terms.
- [Format Queries](reference_formats_values.md) — the package's accessors for every symbol
  named here.
