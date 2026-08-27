# Run Operations over Arrays

Array operations return exactly what the scalar call would return, element by
element — that is the whole semantic story, and it does not change no matter
which of the four spellings you use. What differs between them is
ergonomics and, on a first call, timing. This page covers the spellings, then
the one measurement mistake the caching makes easy.

## The two registers

Every scalar operation comes from one of two registers, and the same split
carries over to arrays:

- **The spec-named register** exposes every draft operation under its draft
  name with an explicit result format and spec: `Op(fr, ρ, operands...)`. This
  is `Add`, `Multiply`, `Exp`, and the rest of the operation catalog,
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
 Binary8p4se(-0.875 ⇆ 0xbe)
 Binary8p4se(4.0 ⇆ 0x50)
 Binary8p4se(-3.25 ⇆ 0xcd)
 Binary8p4se(2.25 ⇆ 0x49)

julia> Exp(Binary8p4se, RNE_SN, A)
4-element Vector{Binary8p4se}:
 Binary8p4se(0.40625 ⇆ 0x35)
 Binary8p4se(56.0 ⇆ 0x6e)
 Binary8p4se(0.0390625 ⇆ 0x1a)
 Binary8p4se(9.0 ⇆ 0x59)
```

`Add(T, ρ, A, B)` reads the same way, elementwise, for a two-array call.

## Understand cold and warm calls

The first deterministic array call for a new `(operation, formats, projection)`
specialization may build a result table. Later calls reuse it. Warm the exact
specialization before measuring steady-state performance, and use
`table_bytes()` or `empty_tables!()` only when you need to inspect or reset the
cache.

This does not create another numerical path. Every table entry is produced by
the scalar operation, so scalar and array forms have the same code-point
contract. Stochastic operations compute per element because each projection
consumes its own draw.

The cache design and ternary tier policy belong to
[Function Tables and Array Kernels](internals_tables.md); they are not required
to use the array API correctly.

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
 Binary8p4se(1.75 ⇆ 0x46)
 Binary8p4se(1.75 ⇆ 0x46)

julia> Op(:Exp, Binary8p4se, RNE_SN).(A)
2-element Vector{Binary8p4se}:
 Binary8p4se(4.5 ⇆ 0x51)
 Binary8p4se(1.25 ⇆ 0x42)
```

`Op` is a singleton type — the operation, format, and projection all live in
its type parameters — so a call specializes exactly as `Add(Binary8p4se,
RNE_SN, x, y)` does and allocates nothing beyond the array `map` or broadcast
itself builds.

## Sorting

Sorting is special-cased for every `Binary` format: values compare through
integer order keys, and vectors of `Binary` sort with an O(n) **counting
sort** installed as the default algorithm. `sort(A)` follows P3109's total
order, with the single NaN first (last under `rev=true`):

```julia-repl
julia> decode.(sort(Binary4p2se.(0x00:0x0f)))      # broadcast the code-point constructor
16-element Vector{Float64}:
 NaN
 -Inf
  -2.0
  -1.5
  -1.0
  -0.75
  -0.5
  -0.25
   0.0
   0.25
   0.5
   0.75
   1.0
   1.5
   2.0
  Inf
```

`TotalOrder(x, y)` exposes the draft's total order directly if you need the
comparison itself rather than a sorted array. This NaN placement differs from
`Float64` sorting and is intentional.

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

## Next steps

[Use Blocks for Dynamic Range](workflow_blocks.md),
[Operation Catalog](reference_operations.md),
[Arrays, Blocks & Packed Storage](reference_arrays_blocks_storage.md).
