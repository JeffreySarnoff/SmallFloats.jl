# Tutorial 4: Blocks & MX-Style Quantization

Tutorial 3 covered arrays of a single format. This tutorial covers `Block`
values, which pair one shared scale with a group of narrow elements — the
MX-style scheme for buying dynamic range that a single narrow format cannot
hold on its own.

## Scale × element

Small formats have small ranges. A `Block{B,FS,FE}` fights that by sharing one
scale, in format `FS`, across `B` elements in format `FE`; the value each
element *represents* is `scale × element`, not the element alone. Construct
one directly from a scale and its elements:

```julia-repl
julia> b = Block(Binary8p1uf(4.0), Binary8p4se(1.5), Binary8p4se(-0.75),
                 Binary8p4se(2.0), Binary8p4se(0.5))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(4.0 ≡ 0x82), (…))
```

Read the type parameters: block size 4, scale format `Binary8p1uf` (unsigned —
scales are non-negative — with the huge range that precision 1 buys), element
format `Binary8p4se`. The represented values are `4.0 × 1.5 = 6.0`,
`4.0 × -0.75 = -3.0`, and so on.

## `ConvertToBlockMaxAbsFinite`

Building a block by hand from a scale you already chose is one path; the more
common one is to quantize a tuple of values and let the draft's algorithm pick
the scale for you, from the maximum finite `|element|`, then project each
element against it:

```julia-repl
julia> ConvertToBlockMaxAbsFinite(Binary8p1uf, Binary8p4se, RNE_SN, RNE_SN,
           (Binary8p4se(100.0), Binary8p4se(-12.0), Binary8p4se(0.5), Binary8p4se(3.0)))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(64.0 ≡ 0x86), (…))
```

Read the arguments in order: scale format, element format, a projection spec
for the scale, a projection spec for the elements, then the values. The
algorithm picked scale 64 from the largest-magnitude element (100) and
projected each of the four elements against that scale.

## `ConvertFromBlock`

Read a block back out as plain values in a format of your choosing: each
`scale × element` is decoded exactly and projected once.

```julia-repl
julia> ConvertFromBlock(Binary8p3se, RNE_SN, b)   # decode scale×elem, project
(Binary8p3se(6.0 ≡ 0x4a), Binary8p3se(-3.0 ≡ 0xc6), Binary8p3se(8.0 ≡ 0x4c), Binary8p3se(2.0 ≡ 0x44))
```

## The stage-wide pitfall

`ConvertToBlockMaxAbsFinite` takes already-`Binary` elements as input. If you
stage your raw `Float64` data through the narrow *element* format before
quantizing into a block, `SatFinite` clamps the large values **before** the
block scale ever gets a chance to absorb them — and the block buys you
nothing. This is the single most consequential mistake with this API, so watch
it happen on real data before you write code that makes it.

Each row of `W` here lives at a different scale, spanning roughly `2^16` across
the matrix — exactly the shape MX-style blocking exists for:

```julia
using SmallFloats, Random, Statistics

rng = Xoshiro(3)
W = randn(rng, 64, 64) .* 2 .* (2.0 .^ (collect(0:63) ./ 4))   # per-row scales

function mx_rows(W, ::Type{FST}, ::Type{FS}, ::Type{FE}, ::Val{B}) where {FST,FS,FE,B}
    n, m = size(W)
    [begin
        # stage through a WIDE-RANGE format so nothing clamps before scaling
        seg = ntuple(k -> Convert(FST, RNE_SF, W[i, (j-1)*B + k]), Val(B))
        ConvertToBlockMaxAbsFinite(FS, FE, RNE_SN, RNE_SN, seg)
    end for i in 1:n, j in 1:m ÷ B]
end

blocks = mx_rows(W, Binary8p2se, Binary8p1uf, Binary8p4se, Val(32))
recon = [let b = blocks[i, (j-1) ÷ 32 + 1]
             decode(b.s) * decode(b.x[(j-1) % 32 + 1])
         end for i in 1:64, j in 1:64]
plain = [decode(Convert(Binary8p4se, RNE_SF, w)) for w in W]

relerr(A) = sqrt(mean(((W .- A) ./ max.(abs.(W), 1e-9)).^2))
relerr(plain), relerr(recon)
```

```
(0.616, 0.109)      # plain 8p4se clamps the large rows; MX tracks them
```

The plain, unblocked `Binary8p4se` conversion clamps every row whose scale
exceeds what `Binary8p4se` alone can hold — relative error 0.616. Staging
through the wide-range `Binary8p2se` first, then letting the per-row block
scale absorb the range, brings that down to 0.109 — the residual is now just
the staging format's own precision.

!!! warning "Stage wide, then block-quantize"
    `ConvertToBlockMaxAbsFinite` takes already-`Binary` elements. If you stage your
    `Float64` data through the *element* format first, `SatFinite` clamps the large
    values **before** the block scale can absorb them, and blocks buy you nothing —
    we measured exactly that (0.617 vs 0.616) with `Binary8p4se` staging. Stage
    through a wide-range format (`Binary8p2se` above); the residual 0.109 here is the
    staging format's own precision, which bounds what any downstream scheme can keep.

At `B = 32` with an 8-bit scale the storage cost is 8.25 bits/value.

## `BlockDotProduct`: one rounding, at the end

`BlockDotProduct` computes every lane product and the accumulation *exactly*,
in a wide carrier, and projects only once, at the very end — there is no
hidden intermediate rounding lane by lane:

```julia
rng = Xoshiro(9)
a64, b64 = randn(rng, 32), randn(rng, 32)
qb(v) = ConvertToBlockMaxAbsFinite(Binary8p1uf, Binary8p4se, RNE_SN, RNE_SN,
            ntuple(i -> Convert(Binary8p4se, RNE_SF, v[i]), Val(32)))
dq = BlockDotProduct(Binary8p4se, RNE_SN, qb(a64), qb(b64))
(a64'b64, decode(dq))
```

```
(5.0634, 4.5)       # difference is input quantization only, never accumulation error
```

The gap between `5.0634` and `4.5` here is entirely the up-front quantization
of `a64` and `b64` into 4-bit-precision elements — accumulation itself
contributes nothing, because the lane products and their sum are carried
exactly until the single final projection. Reductions besides the dot product
follow the same shape: `BlockReduceAdd`, `BlockReduceMultiply`.

## `BlockVector`

For many blocks of the same shape, `BlockVector` stores them in a
structure-of-arrays layout rather than as an array of individually boxed
`Block` values — a memory-bound storage form for blocks, the same way packed
code-point storage exists for bare values.

## Try it

You have raw `Float64` data with widely varying per-row magnitude, and you
want to quantize it into `Block{32,Binary8p1uf,Binary8p4se}`. Name the staging
mistake to avoid, and the one-line fix.

<details>
<summary>Answer</summary>

The mistake is converting straight to `Binary8p4se` (the narrow element
format) before calling `ConvertToBlockMaxAbsFinite` — `SatFinite` clamps large
rows before the block scale can absorb them. The fix is to stage through a
wide-range format first, e.g. `Convert(Binary8p2se, RNE_SF, w)` for each raw
value, and pass those staged elements into `ConvertToBlockMaxAbsFinite` — exactly
the `seg = ntuple(k -> Convert(FST, RNE_SF, ...), ...)` line in the demo above.

</details>

Where next: [Tutorial 5, Stochastic Rounding](tutorial5_stochastic.md) returns to scalars and to the
`StochasticA`/`B`/`C` families introduced briefly in Tutorial 2, with the full
unbiasedness and reproducibility story. For the block operation catalog
(`BlockAdd`, `ScaledOp`, `ConvertToBlock`), see
[Arrays, Blocks & Packed Storage](ref_arrays_blocks.md).
