# Binary16p11se Is Not Float16

!!! warning "Same bit layout, different values"
    `Binary16p11se` shares a significand layout with IEEE-754 `Float16`, and
    `Binary16p8se` shares one with the machine-learning `BFloat16`. Neither
    pair is interchangeable. Reinterpreting the bits of one as the other
    produces a number that looks entirely plausible and is wrong by a
    factor of two.

The K ≤ 16 grid contains two formats that resemble well-known IEEE and
ML-community 16-bit types closely enough to be mistaken for them. This page
explains exactly where they diverge, why the divergence is a single-bit bias
difference rather than a structural one, and how to convert between them
safely.

## The comparison

| | `Binary16p11se` | `Float16` | `Binary16p8se` | `BFloat16` |
|---|---|---|---|---|
| precision `P` | 11 | 11 | 8 | 8 |
| exponent bias | **16** | **15** | **128** | **127** |
| largest finite | **65472** | **65504** | **3.3762e38** | **3.3895e38** |
| NaN encodings | **1** | **2046** | **1** | **2046** |
| negative zero | **no** | yes | **no** | yes |
| domain is a parameter | **yes** (`se`/`sf`) | no | **yes** | no |

Every bolded pair looks close enough to be the same thing at a glance, and
none of them are.

## The bias is the key difference

The root cause of every row above is a single design choice about how the
exponent bias is defined. P3109 sets the bias so that the exponent range is
symmetric about the format's midpoint. IEEE-754 defines it as `2^(E-1) − 1`.
The two rules differ by exactly one for these bit layouts — bias 16 versus
15, bias 128 versus 127 — and that difference of one propagates through
every code point in the format. `Binary16p11se` and `Float16` share a
significand layout bit-for-bit and disagree on the *value* of every single
code point they hold. It is not that a few values differ at the edges; the
entire mapping from bit pattern to number is shifted by a power of two.

## 65472 versus 65504

The largest-finite row is a direct consequence of that shift, plus one more
detail specific to extended formats. `Binary16p11se`'s largest finite value
is `(2^11 − 1) · 2^5 = 65472`. `Float16`'s is `65504`, one ulp larger. The
gap is not the bias difference alone — it's because `Binary16p11se` is an
extended format (`se`), meaning its top code point in each sign is reserved
for `Inf`, one step short of the largest value the bit pattern could
otherwise reach. `Float16` reserves an entire exponent field for
NaN/Inf encodings, which lands its largest finite value one ulp higher in
the same layout. The two numbers are close enough that a bug producing
`65472` instead of `65504` (or vice versa) would not look like an obviously
wrong answer — it would look like rounding.

## Single NaN, no −0, domain as a parameter

The remaining rows are draft design decisions, not incidental byproducts of
the bias shift:

- **A single NaN encoding** means there is no payload to propagate and no
  quiet/signalling distinction. The 2045 extra code points IEEE spends on
  NaN payloads are ordinary datums in a P3109 format instead.
- **No negative zero** means `-0.0` and `0.0` are the same code point, which
  is why a sign-symmetric format has an odd number of finite values rather
  than an even one.
- **The domain parameter** — `e` for extended (with ±Inf), `f` for finite —
  has no IEEE analogue at all. `Binary16p11sf` spends the two code points
  `Binary16p11se` gives to infinity on two more finite values instead. There
  is no such choice available in `Float16`; the domain is fixed by the IEEE
  standard.

## Convert, never reinterpret

Because the two formats disagree on the value of every code point, moving a
value from one to the other must be a genuine numeric conversion — recompute
the code point that represents the same number — never a bit-for-bit
reinterpretation:

```julia-repl
julia> using SmallFloats.Formats

julia> Convert(Binary16p11se, RNE_SF, Float16(1.5))    # a conversion: 1.5 ↦ 1.5
Binary16p11se(1.5 ≡ 0x4200)

julia> reinterpret(Binary16p11se, Float16(1.5))        # the SAME BITS: 1.5 ↦ 0.75
Binary16p11se(0.75 ≡ 0x3e00)
```

The second line demonstrates the hazard in one expression. `Float16(1.5)` has the bit
pattern `0x3e00`. Read as a `Binary16p11se` code point, those same bits
denote not 1.5 but `0.75`, because the exponent bias differs by one.
Nothing errors, nothing warns, and the returned value is a plausible,
finite, correctly-typed number that is off by a factor of exactly two. This
is the single most important habit this page can leave you with: `Convert`
between these formats, always; never `reinterpret`.

## Why P3109 chose a different bias rule at all

It is worth asking why the draft did not simply reuse the IEEE bias
convention and avoid this entire class of error. The answer is that P3109
formats span a much wider range of bitwidths — 3 through 16 bits — and a
single bias rule has to behave sensibly at every one of them, including the
very smallest formats where an off-by-one in the bias has a proportionally
much larger effect on the usable exponent range. Defining the bias so the
exponent range sits symmetrically about the format's midpoint is the choice
that generalizes cleanly across that whole span; the IEEE `2^(E-1) - 1`
convention was fixed for a small, specific set of binary interchange
formats and was never asked to generalize to a 3-bit format. The two rules
agree in spirit — both center the exponent range as sensibly as the bit
budget allows — and disagree by exactly one at every bitwidth where they
overlap, which is precisely why `Binary16p11se` and `Float16`, sharing a
significand layout, do not share a value mapping.

## Interop via `datumsexact`

If IEEE semantics are what you actually want, use `Float16` and `BFloat16`
directly — the package converts to and from both, exactly, wherever the two
datum sets permit it. `datumsexact` is the query that tells you whether a
given conversion between two formats (or a format and `Float16`/`BFloat16`)
is exact for every value, so you can check before relying on a round trip
rather than discover a rounding after the fact.

This is the same discipline the rest of the package applies to every
conversion: rather than promising exactness everywhere and hoping, it
exposes a query you can call before trusting a round trip. `datumsexact`
between `Binary16p11se` and `Float16` reports false in the direction that
matters here, and that answer is available before you write a single line
of code that depends on the two formats agreeing.

## The general lesson

The `Binary16p11se`/`Float16` pair is the sharpest illustration in the whole
package of a rule worth generalizing: two types that look alike are not
interchangeable just because their bit patterns are the same shape. Nothing
about Julia's type system stops you from calling `reinterpret` between any
two `isbits` types of the same size, and nothing about the result looking
like a normal number will tell you it's wrong. The only defense is knowing,
for any two formats you might be tempted to treat as equivalent, whether
they actually share a value mapping — and `Convert` plus `datumsexact` are
the tools that answer that question honestly instead of assuming it.

## Go deeper

> Continue with **Values, Code Points & Conversion** (Insights track)
> for the general rule this page is a special case of: `UInt8` means code
> point, every other numeric type means value, and `Convert` is how you move
> a value between any two supported representations. That page also covers
> the carrier `decode` returns at these wider formats, which is the other
> half of getting `Binary16p11se` and `Binary16p8se` interop right.
