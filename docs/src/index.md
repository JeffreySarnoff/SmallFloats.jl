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

Small floating-point formats are easy to implement *approximately* and
surprisingly hard to implement *exactly*. An FP8 `Exp` differs from a bit-exact
one only in a handful of code points near rounding boundaries — invisible in a
demo, decisive in a conformance suite, and quietly corrosive in research that
compares number formats. SmallFloats.jl takes the position that for value sets
this small there is no excuse for approximation:

- **Bit-exact defined results on every default path.** Every operation's result
  is the correct projection of the mathematically exact value.
- **One projection engine.** `RoundToPrecision → Saturate → Encode` is the
  single write path into a code point. There is no second, "fast but slightly
  different" rounding routine anywhere in the package.
- **Approximation is opt-in, named, and measured.** Faster-but-inexact kernels
  live behind an explicit registry whose deviation bound κ is *measured by
  exhaustive enumeration* at registration time; understated declarations are
  rejected.
- **Enumerated where enumeration is affordable, labelled where it is not.**
  ≈ 35 million verified units across the gates and tiers, each labelled
  *exhaustive* or *sampled* in a roll-call printed at the end of every run.
- **Fast where it matters.** Table-gather kernels at fractions of a nanosecond
  per element; the scalar path fully specialized and allocation-free.

## Two things to know before you start

!!! warning "`Binary16p11se` is not `Float16`"
    Nor is `Binary16p8se` a `BFloat16`. The exponent biases differ by one, so
    *every code point denotes a different value*. Converting between them is a
    conversion, never a reinterpretation. See
    [Why `Binary16p11se` is not `Float16`](explain_float16.md).

!!! warning "Most format names are opt-in"
    `using SmallFloats` exports the **120 aliases at K ≤ 8**. The other 384
    arrive with `using SmallFloats.Formats`, and are reachable without it as
    `SmallFloats.Binary16p6se` or `format(16, 6, true, true)`.

## Finding your way

The documentation is organized by *what you are trying to do*, not by module.
Five entrances:

| If you want to… | Start at |
|---|---|
| **run something now** | [Installation](installation.md) → [Quickstart](quickstart.md) |
| **understand the ideas** | [Mental Model](mentalmodel.md) — five ideas that carry the whole package |
| **learn the standard** | [Introducing P3109](fifteenminutes.md) |
| **do a specific task** | the [How-To](howto_choose_format.md) section — each page is one job |
| **look something up** | the [Cheat Sheet](cheatsheet.md), or [Reference](ref_formats.md) |

### The sections, and what each is for

- **Getting Started** — installation, a first session, and the two orientation
  pages. Read `Mental Model` once, slowly; the rest of the docs become
  reference material rather than prose to wade through.
- **Tutorials** — five sequenced lessons that build on each other: values,
  projection, arrays, blocks, stochastic rounding. Follow them in order the
  first time.
- **How-To** — task-shaped answers. "Choose a format", "quantize a tensor",
  "make stochastic rounding reproducible". Independent of each other; go
  straight to the one you need.
- **Explanations** — the *why* behind decisions that surprise people: the
  projection contract, session defaults, `Float16` non-equivalence, the absence
  of automatic promotion, the performance model.
- **Reference** — the API surface: formats, projections, operations, defaults,
  arrays and blocks, conformance, the Base register, and the docstrings.
- **Foundations** — the code-point algebra the whole package computes on,
  stated as verified identities.
- **Examples** — complete runnable sessions with their output, split into
  applied (public API) and internals (unexported machinery).
- **Insights** — how it works inside: architecture, the engine, the oracle,
  tables, blocks, and the verification and benchmark doctrines. Also where to
  go to extend the package.
- **Support** — troubleshooting by symptom, glossary, benchmarks.

!!! tip "The one rule that catches everyone"
    An `Unsigned` argument always means a **code point**; every other `Real`
    means a **value**. `T(0x08)` and `T(8.0)` are different things by design,
    and `T(8)` is the value 8.0 — the signedness of the integer type is what
    distinguishes them. This holds at every bitwidth.
