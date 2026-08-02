# SmallFloats.jl

SmallFloats.jl implements the IEEE P3109 draft's small binary formats for
Julia, across bitwidths 3 through 16. Its default operations compute the
mathematically exact result and project once into the requested format.

```julia-repl
julia> using SmallFloats

julia> x = Binary8p4se(1.6)
Binary8p4se(1.625 ≡ 0x45)

julia> Add(Binary8p4se, RNE_SN, x, Binary8p4se(1.75))
Binary8p4se(3.5 ≡ 0x4e)
```

The display shows both parts of a stored value: `1.625` is the exact datum and
`0x45` is the code point that names it. The addition computes the exact sum,
3.375, then applies the named projection `RNE_SN` once. That relationship—an
exact value, a code point, and an explicit projection—is the center of the
package and of this manual.

## Choose a route

### Start using the package

Begin with [Install and Verify](install_and_verify.md), then work through
[First Session](first_session.md). Read [Core Model](core_model.md) once before
moving into a larger workflow. Together these pages take you from installation
to the four distinctions that prevent most mistakes.

### Complete an application task

Go directly to a workflow when you already know the core model:

- [Choose a Format](workflow_choose_format.md)
- [Quantize and Measure a Tensor](workflow_quantize_measure.md)
- [Control Rounding and Overflow](workflow_rounding_overflow.md)
- [Run Operations over Arrays](workflow_arrays.md)
- [Use Blocks for Dynamic Range](workflow_blocks.md)
- [Make Stochastic Work Reproducible](workflow_stochastic.md)
- [Pack Values for Storage](workflow_packed_storage.md)
- [Interoperate with Float16 and BFloat16](workflow_float16.md)

Each workflow gives one shortest correct procedure, a way to validate the
result, and the failure modes most likely to produce a plausible but wrong
answer.

### Understand the semantics

[P3109 in One Chapter](concept_p3109.md) introduces the draft standard.
[Format Anatomy](concept_format_anatomy.md),
[Values, Code Points, and Conversion](concept_values_codepoints.md), and
[The Exact-Then-Project Contract](concept_exact_then_project.md) form the
conceptual spine. The remaining concept pages explain Julia integration,
session state, performance, and the difference between defined, stochastic,
and approximate results.

### Look up a contract

Reference pages are organized by API family. Start with
[Formats and Value Queries](reference_formats_values.md),
[Projection Specifications](reference_projections.md), or the
[Operation Catalog](reference_operations.md). The
[Public API Index](reference_public_api.md) collects source docstrings after
the curated family references.

### Inspect evidence or implementation

[Examples and Evidence](examples_gallery.md) indexes complete applied and
verification sessions. Maintainers should begin with
[Architecture and Invariants](internals_architecture.md), then follow the data
path through encoding, projection, the oracle, tables, and block reductions.

## Three promises and one boundary

### Defined paths are bit-exact

For a defined operation, the package returns the projection of the
mathematically exact result. Table kernels and scalar methods implement the
same function; a table is a cache, not an approximate alternate path.

### Policy is visible

Rounding and saturation are values in a `ProjSpec`. Convenience operators use
the session default, while the spec-named register—`Add(T, ρ, x, y)`,
`Exp(T, ρ, x)`, and so on—makes policy explicit and reproducible.

### Approximation is declared and measured

Optional approximate kernels live behind a registry. Registration measures
their maximum code-point deviation κ and rejects an understated bound.

### P3109 is not IEEE 754 in smaller storage

P3109 has one NaN and one zero, defines a different bias rule, and makes
signedness and finite/extended domain format parameters. In particular,
`Binary16p11se` is not `Float16`, and converting between them is never a
reinterpretation. See [P3109 in One Chapter](concept_p3109.md) before porting
IEEE-specific assumptions.

## The rule to remember first

An `Unsigned` constructor argument is a **code point**. Every other `Real`
constructor argument is a **value to project**.

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ≡ 0x02), Binary8p4se(2.0 ≡ 0x48))
```

Use `codepoint(x)` and `decode(x)` to make the two interpretations explicit.

## Supported formats

The package implements all 504 legal formats at `K ∈ 3:16`. `using
SmallFloats` exports the 120 aliases at `K ≤ 8`; the other 384 are available
through `SmallFloats.Binary…`, `format(K, P, SGN, EXT)`, or `using
SmallFloats.Formats`.

## Next

[Install and Verify](install_and_verify.md) → [First Session](first_session.md)
→ [Core Model](core_model.md).
