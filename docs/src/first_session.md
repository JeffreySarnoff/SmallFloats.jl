# First Session

This session establishes the package's working vocabulary and runs one scalar
and one array operation. It assumes [Installation](install_and_verify.md)
has succeeded.

```julia-repl
julia> using SmallFloats
```

## Construct a value from a number

```julia-repl
julia> x = Binary8p4se(1.6)
Binary8p4se(1.625 ≡ 0x45)
```

`Binary8p4se` is an 8-bit, precision-4, signed, extended format. It does not
contain the number 1.6. Construction therefore projects 1.6 to the nearest
datum, 1.625, and stores its code point, `0x45`.

The display exposes both views. In ordinary application output values may
print more compactly; the documentation uses the typed display so that no
projection is invisible.

## Construct a value from a code point

```julia-repl
julia> y = Binary8p4se(0x46)
Binary8p4se(1.75 ≡ 0x46)
```

An `Unsigned` argument means **code point**, not numeric value. Compare the two
forms:

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ≡ 0x02), Binary8p4se(2.0 ≡ 0x48))
```

Use an unsigned integer when you mean stored identity. Use a signed integer or
other `Real` when you mean a value to project. `decode` and `codepoint` recover
the two views:

```julia-repl
julia> decode(x), codepoint(x)
(1.625, 0x45)
```

## Display

`get_show_style()` returns the process-wide style and `set_show_style!(style)`
sets it. `VALID_SHOW_STYLES` contains four values:

| Style | Example rendering |
|:---|:---|
| `:value` | `1.625` |
| `:codepoint` | `0x45` |
| `:datum` | `(1.625 ≡ 0x45)` |
| `:typed` | `Binary8p4se(1.625 ≡ 0x45)` |

An `IOContext` property, `:binary_show_style`, overrides the process default for
one stream. Prefer that form in concurrent code and in libraries that should
not change another caller's display.

Choose the style for the job:

- Use `:value` for ordinary numerical output when the format and code point are
  already clear from context.
- Use `:codepoint` when inspecting storage, serialization, or a conversion
  boundary.
- Use `:datum` when validating a projection, because it keeps the represented
  value and its identity together.
- Use `:typed` in examples, logs, and mixed-format sessions, where the format
  must remain visible.

For a temporary rendering choice, attach the style to the destination stream
instead of changing process-global state:

```julia
io = IOContext(stdout, :binary_show_style => :typed)
show(io, x)
```

`set_show_style!` is appropriate for an interactive session you own. Restore
the previous setting before returning control to another caller; library code
should use an `IOContext` supplied by its caller, or create a local one as
above. The display style changes presentation only: `decode(x)`,
`codepoint(x)`, comparisons, and arithmetic are unaffected.

## Compute with an explicit policy

```julia-repl
julia> Add(Binary8p4se, RNE_SN, x, y)
Binary8p4se(3.5 ≡ 0x4e)
```

Read the call from left to right:

```text
operation(result format, projection specification, operands...)
```

The exact sum is 3.375. `RNE_SN` says how that exact result lands in
`Binary8p4se`: round to nearest with ties to even, then apply the draft's
`SatNone` boundary rules. The result is 3.5 at code point `0x4e`.

The ordinary Julia spelling uses the current default projection:

```julia-repl
julia> x + y
Binary8p4se(3.5 ≡ 0x4e)
```

Use `+` for exploratory same-format arithmetic. Use `Add(T, ρ, ...)` in code
whose policy must be visible and independent of session state.

## See projection change an overflow

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)
Binary8p4se(224.0 ≡ 0x7e)
```

Both calls compute the exact product 400. `RNE_SN` produces infinity for this
case; `RNE_SF` clamps to the largest finite datum. The projection is part of
the operation's meaning.

## Apply the same contract to an array

```julia-repl
julia> A = Binary8p4se.([-1.0, 0.5, 2.0]);

julia> Exp(Binary8p4se, RNE_SN, A)
3-element Vector{Binary8p4se}:
 Binary8p4se(0.375 ≡ 0x34)
 Binary8p4se(1.625 ≡ 0x45)
 Binary8p4se(7.5 ≡ 0x57)
```

The array form uses the same result format, projection, and scalar semantics.
Its implementation may use a cached function table, but that does not change
the result contract.

## Use it

[Choose a Format](workflow_choose_format.md) or
[Quantize and Measure a Tensor](workflow_quantize_measure.md).

## See also

[Formats and Value Queries](reference_formats_values.md),
[Projection Specifications](reference_projections.md), and
[Operation Catalog](reference_operations.md).
