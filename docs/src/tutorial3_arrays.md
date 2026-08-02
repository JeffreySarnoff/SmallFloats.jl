# Operations & Arrays

Values, Code Points & Conversion and Projection: Rounding & Saturation worked
entirely with scalars: `T(x)` to construct,
`Convert`/`Op(T, ρ, ...)` to project explicitly, and `+`/`exp`/... as the
same-format, default-projection convenience forms. This tutorial scales that
up to arrays, and introduces the machinery — table gathers, `vmap`, the `Op`
callable, counting sort — that makes bulk work fast.

## The two registers, again

Every scalar operation used on those pages came from one of two
registers, and the same split carries over to arrays:

- **The spec-named register** exposes every draft operation under its draft
  name with an explicit result format and spec: `Op(fr, ρ, operands...)`. This
  is `Add`, `Multiply`, `Exp`, and the rest of the catalog from Projection: Rounding & Saturation,
  where you name `ρ` yourself.
- **The Base register** makes each format an ordinary Julia number under its
  *default* spec (`RNE_SN` unless you changed it): `+ - * /`, `exp`, `sqrt`,
  `min`, `max`, comparisons — same-format operands only, no silent
  cross-format promotion.

Both registers exist because they serve different code: library code that must
be insensitive to the session default names `ρ` explicitly through the
spec-named register; exploratory code reads naturally through the Base
register's operators. Both extend to arrays without any new vocabulary.

## Array calls: `Add(T, ρ, A, B)`, `Exp(T, ρ, A)`

Every registered operation has array methods with exactly the same argument
shape as the scalar form, operands replaced by arrays:

```julia-repl
julia> A = Binary8p4se.(randn(Xoshiro(7), 4) .* 2)
4-element Vector{Binary8p4se}:
 Binary8p4se(-0.875 ≡ 0xbe)
 Binary8p4se(4.0 ≡ 0x50)
 Binary8p4se(-3.25 ≡ 0xcd)
 Binary8p4se(2.25 ≡ 0x49)

julia> Exp(Binary8p4se, RNE_SN, A)
4-element Vector{Binary8p4se}:
 Binary8p4se(0.40625 ≡ 0x35)
 Binary8p4se(56.0 ≡ 0x6e)
 Binary8p4se(0.0390625 ≡ 0x1a)
 Binary8p4se(9.0 ≡ 0x59)
```

`Add(T, ρ, A, B)` reads the same way, elementwise, for a two-array call.

## Watching a table build

For pure (non-stochastic) specs, unary and binary array calls run as **table
gathers**: the first call builds and caches a result table for that exact
`(op, formats, ρ)` specialization — 256 bytes for a unary 8-bit operation, 64
KiB for binary — and every later element costs a single lookup. You can watch
this happen directly:

```julia
using SmallFloats, Random
empty_tables!()
rng = Xoshiro(4)
pre = Binary8p4se.(randn(rng, 4096) .* 2.5)       # pre-activations, ±2.5σ
act = Tanh(Binary8p4se, RNE_SN, pre)          # table-gather kernel

(table_bytes(),
 round(count(v -> abs(decode(v)) == 1.0, act) / 4096; digits=3),
 length(unique(codepoint.(act))),
 decode(NextLessThan(one(Binary8p4se))))
```

```
(256, 0.384, 100, 0.9375)
# LUT size; fraction saturated to ±1; distinct output codes; last value below 1
```

`empty_tables!()` clears the cache; `table_bytes()` reports its current
footprint. A second unary activation over the same array grows the cache
rather than replacing it:

```julia
actS = Softplus(Binary8p4se, RNE_SN, pre)
(length(unique(codepoint.(actS))), table_bytes())
```

```
(61, 512)          # softplus keeps 61 distinct codes here; two LUTs now cached
```

Every table entry is built through the exact scalar path, so it is bit-identical
by construction to calling the scalar operation element by element — the table
is a cache, not a different, faster-but-approximate implementation. Stochastic
calls never use a table: they always run the scalar pipeline per element,
because each element draws its own random bits.

## `vmap` and `vmap!`

`vmap`/`vmap!` are the generic, table-aware entry points behind the named array
calls above. `vmap!` is the in-place form and is what you want when you already
have a destination array to fill rather than a fresh one to allocate:

```julia
C = vmap(:Add, T, ρ, A, B)
vmap!(C, Val(:Add), T, ρ, A, B)
```

Reach for `vmap!` in a loop that reuses a buffer; reach for the named form
(`Add(T, ρ, A, B)`) everywhere else — they run the same kernel.

## The `Op` callable, with `map` and broadcast

`Op(T, ρ, A)` above already reads like `map`. When you want Julia's own array
verbs — `map`, broadcast — rather than the named array call, bind the
operation, result format, and projection into an `Op` value and use it as a
function:

```julia-repl
julia> A = Binary8p4se.([1.5, 0.25]); B = Binary8p4se.([0.25, 1.5]);

julia> map(Op(:Add, Binary8p4se, RNE_SN), A, B)
2-element Vector{Binary8p4se}:
 Binary8p4se(1.75 ≡ 0x46)
 Binary8p4se(1.75 ≡ 0x46)

julia> Op(:Exp, Binary8p4se, RNE_SN).(A)
2-element Vector{Binary8p4se}:
 Binary8p4se(4.5 ≡ 0x51)
 Binary8p4se(1.25 ≡ 0x42)
```

`Op` is a singleton type — the operation, format, and projection all live in
its type parameters — so a call specializes exactly as `Add(Binary8p4se,
RNE_SN, x, y)` does and allocates nothing beyond the array `map` or broadcast
itself builds.

## Sorting

Sorting is special-cased for every `Binary` format: values compare through
integer order keys, and vectors of `Binary` sort with an O(n) **counting
sort** installed as the default algorithm. `sort(A)` just works, NaN sorts
last (first under `rev=true`), matching Base's conventions:

```julia
decode.(sort(Binary4p2se.(0x00:0x0f)))      # broadcast the code-point constructor
```

```
[-Inf, -2.0, -1.5, -1.0, -0.75, -0.5, -0.25, 0.0,
  0.25, 0.5, 0.75, 1.0, 1.5, 2.0, Inf, NaN]
```

`TotalOrder(x, y)` exposes the draft's total order directly if you need the
comparison itself rather than a sorted array — single NaN largest.

## Try it

Given `A = Binary8p4se.([1.5, 0.25])` and `B = Binary8p4se.([0.25, 1.5])` from
above, write the `Op`-callable version of `Add(Binary8p4se, RNE_SN, A, B)`
using broadcast rather than `map`.

<details>
<summary>Answer</summary>

```julia
Op(:Add, Binary8p4se, RNE_SN).(A, B)
```

This broadcasts the same bound callable used with `map` above and returns the
same two-element vector, `[1.75, 1.75]` in `Binary8p4se`.

</details>

## see also

[Blocks & MX-Style Quantization](tutorial4_blocks.md),
[Operation Catalog](ref_operations.md),
[Arrays, Blocks & Packed Storage](ref_arrays_blocks.md).
