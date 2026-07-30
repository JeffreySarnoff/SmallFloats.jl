# Introduction

SmallFloats.jl is a conforming, performance-oriented Julia implementation of the **IEEE P3109
draft standard** — *Arithmetic Formats for Machine Learning* — covering every binary
format the draft defines at bitwidths 3 through 16, every projection (rounding ×
saturation) mode including the three stochastic families, the full scalar operation
catalog, block-scaled ("MX-style") operations, and the draft's conformance and
κ-approximation machinery.

## Why this package exists

Small floating-point formats are easy to implement *approximately* and surprisingly hard
to implement *exactly*. An FP8 `Exp` differs from a bit-exact one only in a handful of
code points near rounding boundaries — invisible in a demo, decisive in a conformance
suite, and quietly corrosive in research that compares number formats. SmallFloats.jl takes
the position that for value sets this small there is no excuse for approximation:

- **Bit-exact defined results on every default path.** Every operation's result is the
  correct projection of the mathematically exact value, established through a rigorous
  oracle (exact arithmetic, correctly-rounded `Float128` where IEEE mandates it, and
  MPFR directed-rounding enclosures with automatic precision escalation everywhere else).
- **One projection engine.** `RoundToPrecision → Saturate → Encode` is the *single*
  write path into a code point. There is no second, "fast but slightly different"
  rounding routine anywhere in the package.
- **Approximation is opt-in, named, and measured.** Faster-but-inexact implementations
  live behind an explicit registry ([`register_approx!`](@ref)); each registration's
  deviation bound κ is *measured by exhaustive enumeration* at registration time, and
  understated declarations are rejected. Nothing approximate is reachable from the
  default API.
- **Enumerated where enumeration is affordable, and labelled where it is not.**
  The code lattice is swept **exhaustively at every bitwidth** — all 504 formats,
  7 602 160 code points — and the projection engine is checked against an
  independent `Rational{BigInt}` reference over every realized `(P, B)` cell.
  Where a space is too large to enumerate (the ordered-pair cross-product above
  K = 8 is 4.3 × 10⁹ pairs for a single format), the suite says **"sampled"** in
  those words rather than rounding up. Every run ends with a coverage roll-call
  naming each gate, what it compared, and which of the two it was: ≈ 35 million
  verified units across 13 gates and tiers.
- **Fast where it matters.** Pure-mode elementwise work runs through precomputed
  lookup tables (sub-nanosecond per element); the scalar path is fully specialized
  and allocation-free (`decode` ≈ 1.2 ns, `project` ≈ 6.6 ns, a complete `Add`
  ≈ 9 ns including projection); sub-byte packed storage, integer-keyed ordering
  with an O(n) counting sort, and a mask-based rounding core round out the
  performance story. A reproducible Chairmarks benchmark suite ships in
  `benchmarking/`, and every number here comes from it.

## Thirty-second tour

```julia-repl
julia> using SmallFloats

julia> x = Binary8p4se(1.6)          # construct = project under the default spec
Binary8p4se(1.625 ≡ 0x45)

julia> x + Binary8p4se(0.25)         # Base operators use the format's default spec
Binary8p4se(1.875 ≡ 0x47)

julia> Add(Binary8p4se, RTP_SN, x, Binary8p4se(0.25))
Binary8p4se(1.875 ≡ 0x47)            # spec-named register: any mode, explicitly

julia> σ = RSA_SN();            # stochastic rounding, default N = 8 bits

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 255)
Binary8p4se(2.25 ≡ 0x49)             # explicit draw R makes it reproducible

julia> Exp(Binary8p4se, RNE_SN, Binary8p4se.([-1.0, 0.5, 2.0]))   # via a 256-byte table
3-element Vector{Binary8p4se}:
 Binary8p4se(0.375 ≡ 0x34)
 Binary8p4se(1.625 ≡ 0x45)
 Binary8p4se(7.5 ≡ 0x57)
```

## The formats

A format is the type `Binary{K,P,SGN,EXT}`: bitwidth `K ∈ 3:16`, precision `P ∈ 1:K`
(with the signedness constraint), signed/unsigned `SGN`, and extended (has ±Inf) or
finite `EXT`. All **504** draft formats carry their draft names as aliases. The
**120 at K ≤ 8 are exported** by `using SmallFloats`; the other 384 are opt-in via
`using SmallFloats.Formats`, and are always reachable as `SmallFloats.Binary16p6se`
or programmatically as `format(16, 6, true, true)`.

`Binary8p4se` *represents* `Binary{8,4,true,true}` ("K = 8, P = 4, signed,
extended"); the trailing letters are `s`/`u` for signedness and `e`/`f` for
extended/finite. Note that the two are related by `<:`, not `===` — `Binary` is
abstract (a format is "a datum set and an encoding"), and the alias names its
concrete *representation*.

Values are immutable wrappers around their code point: one byte at K ≤ 8,
two above it. Every format has a single NaN and no negative zero. `Float64` is the
exact interchange carrier for the 432 formats whose exponent range it holds;
the remaining 72 use `Float128` or an exact dyadic carrier, selected by the
format and never by the caller.

## Where to go next

- **[User Guide](@ref)** — the complete tour of the public API: formats and values,
  projection specifications, the two operation registers, arrays and sorting, blocks
  and scaled operations, packed storage, conversion, conformance, and performance
  guidance.
- **[User Examples](@ref)** — worked, runnable examples in three tiers: basic usage,
  machine-learning quantization workflows, and deep-learning block/kernel patterns.
- **[Technical Guide](@ref)** — the internals: the encoding and projection engine, the
  oracle's evaluation protocol and its two rigor classes, tables and kernels, the block
  layer's exactness filters, and the testing and benchmarking doctrine.
- **[Technical Examples](@ref)** — internals-level recipes: pipeline introspection,
  verifying custom kernels against the oracle, κ measurement, differential builds,
  and doctrine-compliant benchmarking.

## Installation

The package is not yet registered, so install it by URL:

```
pkg> add https://github.com/JeffreySarnoff/SmallFloats.jl
```

Append `#main` (or a tag/commit) to pin a revision. For an editable install,
`pkg> dev https://github.com/JeffreySarnoff/SmallFloats.jl` clones into
`~/.julia/dev`, or `pkg> dev path/to/SmallFloats.jl` uses an existing clone.

Requires Julia 1.12. `Quadmath` (libquadmath's `Float128`) is a hard dependency used
only inside the oracle and exact-fallback paths; on platforms where it misbehaves,
`ENV["SmallFloats_Float128"] = "disable"` before loading selects the pure-MPFR configuration
with **identical results** (this equivalence is itself part of the test suite).

## Status and conformance

`conformance()` returns the live, serializable conformance declaration (formats,
operations, modes, instantiated table specializations, and κ registrations);
`SmallFloats.draft_revision()` names the implemented draft revision. Interpretations
made where the draft text under-determined behavior are marked `[interp]` in the
source comments.
