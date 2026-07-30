# SmallFloats.jl

A conforming, performance-oriented Julia implementation of the **IEEE SA P3109
Working Group** draft standard for arithmetic formats for machine learning —
every format the draft defines at bitwidths **3 through 16**, every projection
(rounding × saturation), and the full operation register.

Bit-exact defined results on every default path. Approximate fast paths exist
only behind an explicit registry, retrieved by name, never substituted silently.

```julia
using SmallFloats

x = Binary8p4se(1.5)
y = Binary8p4se(0.25)

Add(Binary8p4se, RNE_SatFinite, x, y)      # round-nearest-even, saturating
Multiply(Binary8p4se, RTZ_SatNone, x, y)   # a different projection, same operands
```

## Formats

A format is `Binary{K,P,Σ,Δ}`: bitwidth `K ∈ 3:16`, precision `P ∈ 1:K`
(significand bits including the implicit bit), signedness `Σ`, and domain `Δ` —
extended (with ±Inf) or finite. There are `4K − 2` formats at each `K`, so
**504** in total.

Each carries its draft §3.2 name. The **120 at K ≤ 8 are exported**; the other
384 are one opt-in away, and are always reachable by qualification or
programmatically:

```julia
using SmallFloats                      # Binary8p4se and the other 119
using SmallFloats.Formats              # …and all 504

SmallFloats.Binary16p6se               # always reachable, no opt-in needed
format(16, 6, true, true)              # programmatic: runtime K, P, Σ, Δ
```

> **`Binary16p11se` is not `Float16`.** The exponent biases differ by one (16 vs
> 15), so *every code point denotes a different value*. The NaN count, the
> absence of negative zero, and the domain parameter differ too. Same for
> `Binary16p8se` and `BFloat16` (biases 128 vs 127). Converting is a conversion,
> never a reinterpretation — see the User Guide's section on the trap.

## What is guaranteed

**One write path.** `project` — `RoundToPrecision → Saturate → Encode` — is the
only producer of a code point. Every operation, every carrier, every bitwidth
enters through it.

**A table entry *is* the defined result.** Where the package tabulates an
operation, every entry came from one trip through the same oracle-backed scalar
path, so there is no residual correctness reasoning at a use site. Declining to
build a table means running that scalar path per element — never a different
answer.

**Nothing approximate is reachable from the default API.** Approximate kernels
live in their own registry and are retrieved only by explicit name. Every
declared error bound κ is *verified by exhaustive enumeration at registration
time*, and where the input space is too large to enumerate, `conformance()`
reports that it was sampled — in those words.

**The evaluation carrier is chosen by the format, never by the caller.** 432 of
the 504 formats evaluate in `Float64`; the rest need more exponent range than it
has, and get `Float128` or an exact dyadic carrier. Which one is a dispatch
decision derived from the exponent bias. Every carrier is exact for the operands
it accepts, so the choice buys time and never changes an answer — a property the
suite gates directly, by forcing a wider carrier and comparing code points.

## Verification

The suite **enumerates rather than samples wherever the input space allows it**,
and says "sampled" in those words where it does not. Every green run ends with a
coverage roll-call naming each gate, how much it compared, whether that was
exhaustive, and — in one place — what is knowingly not covered.

Current totals: **13 gates and tiers, ≈ 35.3 M compared units.** The code lattice
is swept exhaustively at every K (7 602 160 code points across all 504 formats).
The projection engine is checked against an independent `Rational{BigInt}`
reference — the one oracle whose validity does not depend on a carrier being wide
enough, which is exactly what makes it the right one here.

```
SMALLFLOATS_G5=full            # release tier of the golden non-regression gate
SMALLFLOATS_G10=full           # surface totality over all 72 formats above rung 1
SmallFloats_EXHAUSTIVE=1       # widen every sampled format axis to all 504
SmallFloats_Float128=disable   # must produce bit-identical results
```

That last one is a standing invariant, not a convenience: every `Float128` path
fronts a complete MPFR path with identical semantics. The switch trades speed
only, never results.

## Installation

```julia
using Pkg; Pkg.add(url="https://github.com/JeffreySarnoff/SmallFloats.jl")
```

Julia 1.12 or later. **The K ≤ 16 extension added zero dependencies** —
`Quadmath` and `BFloat16s` were already present, the exact dyadic carrier is
hand-written `Int128` arithmetic, and MPFR is in `Base`.

## Documentation

The [User Guide](docs/src/user_guide.md) is the place to start; the
[Technical Guide](docs/src/technical_guide.md) covers the projection engine, the
carrier lattice, and the table policy. `docs/other/` holds the design and
execution records.

## Deliberate limitations

No implicit cross-format arithmetic — promotion is to the format's promotion
carrier, explicitly. No in-place packed arithmetic. Threading is opt-in and
narrow. `Irrational` and `Rational` inputs to `Convert` are rejected rather than
double-rounded silently. Subtyping `Binary` is not a supported extension point:
package methods assume `codepoint`/`rawvalue` semantics and the representation
invariant, neither of which an outside subtype can be held to.
