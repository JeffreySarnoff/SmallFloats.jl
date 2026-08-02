# SmallFloats.jl

*A conforming, performance-oriented Julia implementation of the IEEE P3109 draft
standard — arithmetic formats for machine learning at bitwidths 3–16.*

```julia-repl
julia> using SmallFloats

julia> Binary8p4se(1.6) + Binary8p4se(0.25)
Binary8p4se(1.875 ≡ 0x47)

julia> Binary5p3sf(0x08) == Binary5p3sf(1.0)     # an Unsigned is a CODE POINT
true
```

## Why this package exists

Small floating-point formats are easy to implement *approximately* and surprisingly
hard to implement *exactly*. An FP8 `Exp` differs from a bit-exact one only in a
handful of code points near rounding boundaries — invisible in a demo, decisive in
a conformance suite, and quietly corrosive in research that compares number formats.
SmallFloats.jl takes the position that for value sets this small there is no excuse
for approximation:

- **Bit-exact defined results on every default path.** Every operation's result is
  the correct projection of the mathematically exact value.
- **One projection engine.** `RoundToPrecision → Saturate → Encode` is the single
  write path into a code point. There is no second, "fast but slightly different"
  rounding routine anywhere in the package.
- **Approximation is opt-in, named, and measured.** Faster-but-inexact kernels live
  behind an explicit registry whose deviation bound κ is *measured by exhaustive
  enumeration* at registration time; understated declarations are rejected.
- **Enumerated where enumeration is affordable, and labelled where it is not.**
  ≈ 35 million verified units across 13 gates and tiers, each labelled *exhaustive*
  or *sampled* in a roll-call printed at the end of every run.
- **Fast where it matters.** Table-gather kernels at fractions of a nanosecond per
  element; the scalar path fully specialized and allocation-free.

## Two things to know before you start

!!! warning "`Binary16p11se` is not `Float16`"
    Nor is `Binary16p8se` a `BFloat16`. The exponent biases differ by one, so
    *every code point denotes a different value*. Converting between them is a
    conversion, never a reinterpretation.

!!! warning "Most format names are opt-in"
    `using SmallFloats` exports the **120 aliases at K ≤ 8**. The other 384
    arrive with `using SmallFloats.Formats`, and are reachable without it as
    `SmallFloats.Binary16p6se` or `format(16, 6, true, true)`.

## Where to go

- **Get started** — [Installation & Setup](installation.md), then the
  [Quickstart](quickstart.md): a working session in ten minutes.
- **Understand the ideas** — the [Mental Model](mentalmodel.md) (five ideas
  that carry the whole package), or [P3109 in Fifteen Minutes](fifteenminutes.md)
  if you want the standard itself first.
- **Look something up** — the Reference section: formats, projection specs, the
  operation catalog, and the one-page [Cheat Sheet](cheatsheet.md).
