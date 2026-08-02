# SmallFloats.jl

SmallFloats.jl implements the IEEE P3109 draft's small binary formats for
Julia. It provides all 504 formats at bitwidths 3 through 16, the draft's
rounding and saturation policies, scalar and array operations, shared-scale
blocks, packed storage, stochastic rounding, and measured approximations.

The central contract is simple: a defined operation computes the
mathematically exact result and projects it once into the requested format.
Scalar methods, array kernels, and cached function tables preserve that same
contract.

[Documentation](https://JeffreySarnoff.github.io/SmallFloats.jl) ·
[First session](docs/src/first_session.md) ·
[Choose a format](docs/src/workflow_choose_format.md) ·
[Operation reference](docs/src/reference_operations.md)

## Try it

SmallFloats.jl requires Julia 1.12 or later. The package is not yet registered,
so install it from GitHub:

```text
pkg> add https://github.com/JeffreySarnoff/SmallFloats.jl
```

Then construct two values and add them under an explicit projection policy:

```julia-repl
julia> using SmallFloats

julia> set_show_style!(:typed);

julia> x = Binary8p4se(1.6)
Binary8p4se(1.625 ≡ 0x45)

julia> y = Binary8p4se(1.75)
Binary8p4se(1.75 ≡ 0x46)

julia> Add(Binary8p4se, RNE_SN, x, y)
Binary8p4se(3.5 ≡ 0x4e)
```

`set_show_style!(:typed)` makes the transcript display both the exact datum and
its stored code point; omit it when compact value-only output is preferable.

`Binary8p4se` is an 8-bit, precision-4, signed, extended-domain format. It
cannot represent 1.6, so construction projects that number to the exact datum
1.625 and stores code point `0x45`.

Read the operation call from left to right:

```text
operation(result format, projection specification, operands...)
```

`RNE_SN` means round to nearest with ties to even, followed by the draft's
`SatNone` boundary behavior. Naming the result format and policy makes the
operation independent of session defaults. Ordinary Julia operators are also
available for same-format exploratory work:

```julia-repl
julia> x + y
Binary8p4se(3.5 ≡ 0x4e)
```

## Projection is part of the computation

Rounding and saturation are represented together by a `ProjSpec`. Changing the
projection can change a boundary result without changing the exact arithmetic:

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)
Binary8p4se(224.0 ≡ 0x7e)
```

Both calls multiply exactly to 400. `RNE_SN` produces infinity in this format;
`RNE_SF` clamps to its largest finite datum. See
[Control Rounding and Overflow](docs/src/workflow_rounding_overflow.md) for the
deterministic and stochastic projection families.

## Values and code points are different inputs

An unsigned constructor argument selects a stored code point. Every other
`Real` constructor argument is a numeric value to project:

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ≡ 0x02), Binary8p4se(2.0 ≡ 0x48))
```

Use `codepoint(x)` when stored identity matters and `decode(x)` when the exact
datum matters. The distinction is developed in
[Values, Code Points, and Conversion](docs/src/concept_values_codepoints.md).

## Formats

A format has four parameters:

```julia
Binary{K, P, SGN, EXT}
```

- `K` is the bitwidth, from 3 through 16.
- `P` is the precision, including the implicit significand bit.
- `SGN` chooses unsigned or signed values.
- `EXT` chooses a finite or extended domain.

There are 504 legal combinations. `using SmallFloats` exports the 120
draft-named aliases at `K ≤ 8`. Wider aliases remain available by qualification,
through the opt-in namespace, or programmatically:

```julia
using SmallFloats                    # Binary8p4se and the other K ≤ 8 aliases
using SmallFloats.Formats            # opt in to all 504 aliases

SmallFloats.Binary16p6se             # qualification needs no opt-in
format(16, 6, true, true)            # runtime K, P, SGN, EXT
```

Use [Choose a Format](docs/src/workflow_choose_format.md) to compare precision,
range, signedness, and domain against representative data.

## P3109 is not IEEE 754 in fewer bits

P3109 formats have one zero and one NaN, use a different exponent-bias rule,
and make signedness and finite/extended domain explicit format parameters.
Consequently, `Binary16p11se` is not `Float16`, and `Binary16p8se` is not
`BFloat16`. Convert between them; do not reinterpret their bits.

[P3109 in One Chapter](docs/src/concept_p3109.md) summarizes the differences.
[Interoperate with Float16 and BFloat16](docs/src/workflow_float16.md) gives the
safe conversion patterns.

## What the package guarantees

- **Defined results are bit-exact.** Operations project the mathematically exact
  result once. A cached table is the scalar operation memoized, not a second
  semantics.
- **Policy can be explicit.** Draft-named operations accept a result format and
  `ProjSpec`; Julia operators use the current session default.
- **Array and block forms preserve scalar semantics.** Optimized execution does
  not change the result contract.
- **Approximation is opt-in.** Approximate kernels live in a separate registry;
  registration measures their code-point deviation κ, and the default API never
  substitutes them silently.
- **Carrier choice does not change results.** Formats dispatch to `Float64`,
  `Float128`, or an exact wider path according to their range. The test suite
  compares carrier paths at code-point identity.

The implementation architecture and its invariants are described in
[Architecture and Invariants](docs/src/internals_architecture.md).

## Verification and conformance

The test suite enumerates complete finite spaces where practical and labels
sampled checks as sampled. It sweeps the full 504-format code lattice and checks
the projection engine against an independent `Rational{BigInt}` reference.

From a clone, run:

```text
pkg> test SmallFloats
```

At runtime, inspect the declaration for the current session with
`conformance()` or print it with `conformance_report()`. See
[Read and Export Conformance](docs/src/workflow_conformance.md) and
[Verification Strategy](docs/src/internals_verification.md) for scope and
evidence.

## Documentation by goal

- Start with [Install and Verify](docs/src/install_and_verify.md),
  [First Session](docs/src/first_session.md), and
  [Core Model](docs/src/core_model.md).
- Apply the package through the [workflow guides](docs/src/index.md#complete-an-application-task).
- Understand the semantics through the [concept guides](docs/src/index.md#understand-the-semantics).
- Look up formats, projections, and operations in the
  [reference](docs/src/reference_public_api.md).
- Inspect complete runs in [Examples and Evidence](docs/src/examples_gallery.md).
- Contribute implementation work from
  [Architecture and Invariants](docs/src/internals_architecture.md).

The maintained manual lives in [`docs/src`](docs/src/index.md). Design records
and development notes live in [`docs/other`](docs/other/).

## Deliberate boundaries

- Arithmetic between two different `Binary` formats requires an explicit
  `Convert`; there is no implicit cross-format widening rule.
- Combining a `Binary` value with an ordinary Julia number promotes to the
  format's exact promotion carrier. Project the result back explicitly when
  that is the intended boundary.
- Packed storage does not provide in-place packed arithmetic; unpack, compute,
  and repack.
- `Irrational` and `Rational` inputs to `Convert` are rejected rather than
  silently double-rounded.
- External subtypes of `Binary` are unsupported because package methods rely on
  its representation and code-point invariants.

SmallFloats.jl is released under the [MIT License](LICENSE). Release changes are
recorded in the [changelog](CHANGELOG.md).
