# SmallFloats.jl

*A conforming, performance-oriented Julia implementation of the IEEE P3109 draft
standard — arithmetic formats for machine learning at bitwidths 3–16.*

Bit-exact defined results on every default path; one projection engine as the single
write path into a code point; approximation only behind an explicitly named,
exhaustively measured κ registry; **≈ 35 million verified units across 13 gates and
tiers**, each labelled exhaustive or sampled in a roll-call printed at the end of
every run; table-gather kernels at fractions of a nanosecond per element.

```julia-repl
julia> using SmallFloats

julia> Binary8p4se(1.6) + Binary8p4se(0.25)
Binary8p4se(1.875 ≡ 0x47)

julia> Binary5p3sf(0x08) == Binary5p3sf(1.0)     # an Unsigned is a CODE POINT
true
```

## Two things to know before you start

**Most format names are opt-in.** `using SmallFloats` exports the **120 aliases at
K ≤ 8**. The other 384 arrive with `using SmallFloats.Formats`, and are reachable
without it as `SmallFloats.Binary16p6se` or `format(16, 6, true, true)`.

**`Binary16p11se` is not `Float16`** (nor is `Binary16p8se` a `BFloat16`). The
exponent biases differ by one, so *every code point denotes a different value*.
Converting between them is a conversion, never a reinterpretation — the
[User Guide](@ref) has the full comparison.

## Documentation map

- **[Introduction](@ref)** — what the package is, the design pillars, a
  thirty-second tour, installation.
- **[Cheat Sheet](@ref)** — one-page lookup for format names, conversion,
  projections, operations, arrays, blocks, packed storage, and common traps.
- **[User Guide](@ref)** — the complete public API in usage order: formats, values,
  projection specifications, the two operation registers, arrays and sorting,
  blocks, packed storage, conformance and κ, performance guidance.
- **[User Examples](@ref)** — runnable examples in three tiers: basic, machine
  learning, deep learning.
- **[Julia Compatibility](@ref)** — the Base register: which Base functions work
  on `Binary` values, what they map to, and what deliberately isn't mapped.
- **[Technical Guide](@ref)** — internals: the encoding and projection engine, the
  oracle's rigor classes, tables and kernels, the block layer's exactness filters,
  the verification and benchmark doctrines.
- **[Technical Examples](@ref)** — internals-level recipes: pipeline introspection,
  exhaustive verification of custom code, κ measurement, doctrine-compliant
  benchmarking.
- **[Adding Operations](@ref)** — how to add new scalar (unary through
  quaternary) and block (scaled, elementwise, reductive) operations with every
  guarantee intact: registry mechanics, ω-semantics duties, worked examples.
- **[External Reference](@ref)** — docstrings for the documented public surface.
- **[Internal Reference](@ref)** — docstrings for the documented unexported
  machinery.
