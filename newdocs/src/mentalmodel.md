# Mental Model

Five ideas. Everything else in SmallFloats.jl — every page of the User Guide,
every tutorial, every recipe — is an elaboration of one of them. Read this
page once, slowly, and the rest of the documentation becomes reference
material you consult, not prose you wade through.

## A format is a finite set of datums

A SmallFloats *format* is not a floating-point type in the IEEE-754 sense of
a continuum sampled at machine precision. It is a **finite, enumerated set of
exact values** — the *datums* — each with a name, its *code point*. The format
`Binary4p2se` (4 bits, precision 2, signed, extended) has 16 code points and
they are all of them:

```julia-repl
julia> decode.(sort(Binary4p2se.(0x00:0x0f)))
16-element Vector{Float64}:
 NaN
 -Inf
  -2.0
  -1.5
  -1.0
  -0.75
  -0.5
  -0.25
   0.0
   0.25
   0.5
   0.75
   1.0
   1.5
   2.0
  Inf
```

That listing *is* the format. There is nothing between the grid points, no
hidden state, no approximation in the set itself — the spacing you see
(subnormals near zero, binades doubling outward) is the whole structure.

Three consequences fall out immediately:

- **One NaN, no negative zero.** The first entry — NaN sorts below −Inf in the
  draft's total order (§4.12.1) — is the format's single NaN; the value `0.0`
  appears exactly once. IEEE-754 spends thousands of code points on NaN
  payloads and two on zeros; P3109 spends them on datums.
- **The set has edges.** `-Inf`, `Inf`, and `NaN` occupy three of the sixteen
  names, which is why the largest *finite* value is 2.0 and not something
  larger. Finite formats (suffix `f` instead of `e`) spend those two infinity
  code points on more finite datums instead.
- **Larger formats are the same idea with more points.** `Binary8p4se` is
  256 names; `Binary16p11se` is 65 536. The 504 formats are just the legal
  choices of how many names (bitwidth `K`), how much of the budget goes to
  significand vs exponent (precision `P`), and whether the set includes
  negatives (`s`/`u`) and infinities (`e`/`f`).

*Now you can read:* [Formats, Aliases & Representations](explain_formats.md) for why
the type `Binary8p4se` is a concrete *representation* of the abstract format
`Binary{8,4,true,true}` — and why `===` is `false` but `<:` is `true`.

## A value is a wrapper around a code point; decode is exact

Construct a value and you hold the code point; ask what it means and you get
the datum back, exactly:

```julia-repl
julia> x = Binary8p4se(1.6)
Binary8p4se(1.625 ≡ 0x45)

julia> codepoint(x)
0x45

julia> decode(x)
1.625
```

The display `1.625 ≡ 0x45` is the idea in one line: the code point `0x45`
*means* the datum 1.625, and the `≡` is exact, not approximate. `decode`
never rounds — it is a table lookup from name to meaning.

The asymmetry that matters: `decode` is exact, but **construction is a
projection**. `Binary8p4se(1.6)` did not store 1.6; it stored the name of the
nearest datum, which happens to be 1.625. The value you get back is the value
the format can say, not the value you asked for.

This is why the `Unsigned`-means-code-point rule (from the Quickstart) exists:
`codepoint` and the constructor are inverses *by design* —

```julia-repl
julia> Binary8p4se(codepoint(x)) === x
true
```

— and that round-trip is the format's identity. A value is its code point;
everything else is a view.

*Now you can read:* [Values, Code Points & Conversion](tutorial1_values.md) for the
four ways in and two ways out, and the carriers `decode` returns at wide
formats.

## Every computation is exact math, then one projection

When you compute, SmallFloats does not simulate low-precision arithmetic
step by step. It computes the **mathematically exact result** of the
operation on the decoded datums, then applies **one projection** — one
rounding plus one saturation decision — to land on a code point:

```
exact result  →  RoundToPrecision  →  Saturate  →  code point
```

`x + y` from the Quickstart: exact sum 3.375, projected once to 3.5. `200 × 2`:
exact product 400 (not representable — projection decides between `Inf`, `224`,
or `NaN`, and the spec says which).

Two things follow from "one projection, at the end":

- **There is no accumulated rounding error inside an operation.** A fused
  `FMA(x, y, z)` rounds once, not twice. A `BlockDotProduct` accumulates all
  32 lane products exactly and projects once at the end. Intermediate
  roundings are not "small" — they are *absent*.
- **The default path is bit-exact.** Because the exact math is carried far
  enough (Float64, Float128, or MPFR enclosures, escalating automatically),
  the code point you get is *the* defined answer, not a good approximation of
  it. The package can prove this because the value sets are finite — see
  the fifth idea.

*Now you can read:* [The Projection Contract](explain_projection_contract.md) for what "exact"
means at each carrier width, and the symbolic-sticky trick that lets directed
modes land exactly on asymptotes.

## Projection = rounding mode × saturation mode

A projection specification is the pair of two independent choices:

| | what it decides | examples |
|---|---|---|
| **rounding mode** | which neighbor a between-grid value lands on | nearest-ties-even, toward zero, toward ±∞, stochastic |
| **saturation mode** | what an out-of-range result becomes | clamp to finite (`SF`), propagate infinities (`SP`), draft rows (`SN`) |

Watch one overflow resolve three ways (`Binary8p4se`, max finite 224):

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)   # nearest + draft rows → Inf
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)   # nearest + clamp → 224
Binary8p4se(224.0 ≡ 0x7e)

julia> Multiply(Binary8p4se, RTZ_SN, w, two)   # toward zero + draft rows → 224
Binary8p4se(224.0 ≡ 0x7e)
```

The first two differ in *saturation* (SN vs SF); the first and third differ
in *rounding* (RNE vs RTZ) — and the third row is the subtle one: under
`SatNone`, a directed mode that points *away* from the overflow clamps to the
extremal finite value, so `RTZ_SN` agrees with `RNE_SF` here for different
reasons.

The full deterministic grid is 6 rounding modes × 3 saturation modes = 18
predefined specs (`RNE_SN`, `RNA_SF`, `RTP_SP`, …), plus three stochastic
families parameterized by a random-bit budget. `RNE_SN` is the package-wide
default — which is exactly why `+`, `exp`, and `T(1.6)` all agree with
`Add(T, RNE_SN, …)`, `Exp(T, RNE_SN, …)`, and `Convert(T, RNE_SN, …)`.

!!! warning "The default is a session default"
    `+` and friends follow `DefaultProjection()`, which is process-global and
    stays set. Convenience syntax is for exploratory code; anything that must
    be reproducible names its spec explicitly. The Tutorials teach the safe
    `with_default_projection` form before showing `DefaultProjection!`.

*Now you can read:* [Projection: Rounding & Saturation](tutorial2_projection.md) for the
experiments, and [Projection Specifications](ref_projections.md) for the complete grid.

## Approximation is opt-in, named, and measured

The package's speed comes from the first idea's finiteness: an 8-bit unary
operation is a function with 256 inputs, so its *entire* behavior is a
256-byte table, built once through the exact scalar path and then gathered
per element (0.27 ns). The exactness is inherited: table and scalar are the
same function by construction.

The same finiteness makes approximation *honest*. If you register a faster
but inexact kernel — say a hardware-style hard-tanh for `Tanh` — the registry
does not take your word for its accuracy. It **measures** the worst-case
deviation, exhaustively over every input, as a distance in code points:

```julia-repl
julia> κ, exhaustive = measure_kappa(
           x -> Clamp(Binary8p4se, RNE_SN, x,
                      Negate(one(Binary8p4se)), one(Binary8p4se)),
           :Tanh, Binary8p4se, (Binary8p4se,), RNE_SN)
(4.0, true)
```

κ = 4 code points, verified over all 256 inputs — that is a measured fact,
not a claim. Declare κ smaller than the measurement and registration is
*rejected*. Nothing approximate is reachable from the default API; an
approximation exists only because you named it, and its κ is part of the
conformance declaration the package exports.

This is the package's answer to the problem stated in the Introduction: small
formats are easy to implement approximately and hard to implement exactly.
SmallFloats implements them exactly, and when you choose otherwise, it makes
the choice explicit and quantified.

*Now you can read:* [Register & Measure an Approximation](howto_register_approx.md), and
[Conformance & Approximation Registry](ref_conformance.md).

## Visual Synopsis

![A whole of five parts: a finite set of datums, values as code points, exact
computation, one controlled projection, and exact or measured
results.](assets/fiveideas.svg)

Read left to right: a value is a name in a finite set (1–2); computing is
exact math followed by one projection (3); the projection is your choice of
rounding and saturation (4); and the result is exact unless you explicitly
register otherwise (5).

**Where to go from here.** To build the ideas into skills: Values, Code Points &
Conversion. To look something up: the Specifics pages.
To understand *why* the package is built this way: The Projection Contract
and the rest of the Explanations section.
