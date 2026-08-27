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
Binary8p4se(1.625 ⇆ 0x45)
```

`Binary8p4se` is an 8-bit, precision-4, signed, extended format: a fixed set
of 256 code points. The number 1.6 is not among the values it holds. The
nearest data in this format are 1.5, 1.625, and 1.75 — the spacing here is
0.125 — so construction must *project*: it rounds 1.6 to the nearest datum,
1.625, and stores that datum's code point, `0x45`. Every construction from a
`Real` answers the same question — *which datum stands in for my number?* —
and the constructor never refuses to answer; it rounds.

The display shows both halves of the answer: the datum that now represents
1.6, and the identity under which it is stored. Application output may print
more compactly; the documentation uses the typed display so that no projection
is invisible.

## Construct a value from a code point

```julia-repl
julia> y = Binary8p4se(0x46)
Binary8p4se(1.75 ⇆ 0x46)
```

An `Unsigned` argument means **code point**, not numeric value. The signedness
of the integer type is the entire distinction. Compare:

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ⇆ 0x02), Binary8p4se(2.0 ⇆ 0x48))
```

The same digit, read two ways: `0x02` asks *give me the datum stored at code
point 2* and gets 0.001953125; `2` asks *represent the value 2* and gets 2.0
— results a factor of 1024 apart. Neither call is an error, so an integer of
the wrong signedness is not caught; it is a different, valid request. Use an
unsigned integer when you mean stored identity — reading a byte from a file,
reconstructing a value from a wire format. Use a signed integer or any other
`Real` when you mean a value to project. `decode` and `codepoint` ask the two
questions in reverse — *what value does this represent?* and *under what
identity?*:

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
| `:datum` | `(1.625 ⇆ 0x45)` |
| `:typed` | `Binary8p4se(1.625 ⇆ 0x45)` |

An `IOContext` property, `:binary_show_style`, overrides the process default for
one stream. Prefer that form in concurrent code and in libraries that should
not change another caller's display.

The four styles answer four different questions about the same value. For the
`x = Binary8p4se(1.6)` constructed above:

- `:value` prints `1.625` and answers *what number is this?* Use it when
  results are read as numbers — comparing against a `Float64` reference,
  printing residuals, tabulating measurements — where `⇆ 0x45` on every line
  is noise.
- `:codepoint` prints `0x45` and answers *which code point is stored?* Use it
  where identity matters and magnitude does not: diffing a serialized buffer,
  inspecting a slot in a packed array, checking that a round-trip returned to
  the same code point. Two values are the same datum exactly when their code
  points match.
- `:datum` prints `(1.625 ⇆ 0x45)` and answers *where did my input land?* Use
  it when watching a projection: construct from 1.6 and see, on one line, both
  the datum the input rounded to and the identity it received. Either half
  alone hides the other.
- `:typed` prints `Binary8p4se(1.625 ⇆ 0x45)` and answers *in which format?*
  Use it wherever the format cannot be inferred later — logs, saved output,
  examples meant to be pasted elsewhere, sessions mixing formats — because a
  code point means nothing without its format: `0x45` names a different value
  in every format that contains it. This documentation renders `:typed`
  throughout for exactly that reason.

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
Binary8p4se(3.5 ⇆ 0x4e)
```

Read the call from left to right:

```text
operation(result format, projection specification, operands...)
```

The exact sum, 1.625 + 1.75 = 3.375, is once again not a datum. It falls
*exactly halfway* between the neighbors 3.25 ⇆ `0x4d` and 3.5 ⇆ `0x4e`, so
the operation's result is entirely a question of policy: `RNE_SN` rounds to
nearest with ties to even, which selects 3.5, then applies the draft's
`SatNone` boundary rules. A different projection could legitimately land the
same exact sum on `0x4d`. That is why the projection sits in the argument
list: it is an operand of the operation, not an ambient setting the result
quietly depends on.

The ordinary Julia spelling uses the current default projection:

```julia-repl
julia> x + y
Binary8p4se(3.5 ⇆ 0x4e)
```

The two spellings differ in who decides the policy. `+` delegates to the
session default, which is right for exploratory same-format arithmetic at the
REPL. `Add(T, ρ, ...)` names the policy at the call site, which is right for
code whose results must not change because someone, somewhere, changed the
session default — the line means the same thing in every session that runs it.

## See projection change an overflow

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)
Binary8p4se(Inf ⇆ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)
Binary8p4se(224.0 ⇆ 0x7e)
```

A projection has already happened before either multiply runs: 200 is not a
datum, and it sits exactly halfway between the neighbors 192 and 208, so `w`
holds 192.0 ⇆ `0x7c` — another tie broken to even. Both calls therefore
compute the exact product 384, which exceeds 224, the largest finite datum of
the format. The two projections disagree about what exceeding the range should
mean. `SatNone` answers with infinity, preserving the evidence that the range
was exceeded; `SatFinite` clamps to 224.0 ⇆ `0x7e`, keeping the result finite
for pipelines that cannot absorb an infinity. Same exact product, two defined
results: the projection is part of the operation's meaning, not a rounding
afterthought.

## Apply the same contract to an array

```julia-repl
julia> A = Binary8p4se.([-1.0, 0.5, 2.0]);

julia> Exp(Binary8p4se, RNE_SN, A)
3-element Vector{Binary8p4se}:
 Binary8p4se(0.375 ⇆ 0x34)
 Binary8p4se(1.625 ⇆ 0x45)
 Binary8p4se(7.5 ⇆ 0x57)
```

Each element is the answer the scalar call would give. Look at the middle one:
exp(0.5) = 1.6487… projects to 1.625 ⇆ `0x45` — the same datum `x` landed on
at the top of this page, reached now from a different number by a different
operation. The array form adds no semantics of its own: same result format,
same projection, same scalar answer per element. Its implementation may serve
those answers from a cached table, but a table entry is the scalar result
precomputed, so the contract is unchanged whether the table is used or not.

## What this leaves open

This session used four things without explaining any of them: a format that
did not contain 1.6, a projection named in the call, an overflow that resolved
two ways, and an array result that matched the scalar one. [Core
Model](core_model.md) is those four as one connected idea, and it is the page
to read next — everything else in the documentation develops one of its five
parts.

If you would rather work first and generalize later, the two workflows that
start from real data are [Choose a Format](workflow_choose_format.md) — which
format fits numbers you already have — and [Quantize and Measure a
Tensor](workflow_quantize_measure.md), which measures what a choice cost you.
Both assume only what this page established.

## See also

[Formats and Value Queries](reference_formats_values.md),
[Projection Specifications](reference_projections.md), and
[Operation Catalog](reference_operations.md).
