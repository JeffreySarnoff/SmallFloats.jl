# How-To: Use Blocks to Track Dynamic Range

Keep a bare element format from clamping data whose dynamic range exceeds one
binade, by sharing a per-group scale (the MX-style scheme).

## Ingredients

- A wide-range staging format (e.g. `Binary8p2se`) to hold raw values before
  scaling.
- `ConvertToBlockMaxAbsFinite(FS, FE, scale_ρ, element_ρ, values_tuple)` to
  build one block per group, picking the scale from the group's max |element|.
- `Val(B)` for the block size.
- `relerr` (or your own metric) to compare plain quantization against blocked
  quantization.

## Recipe

**1. Build data whose scale varies by row.** Here each row of a 64×64 matrix
lives at a different scale, spanning roughly `2^16` across the whole matrix —
exactly the situation a single bare format cannot track:

```julia
using SmallFloats, Random, Statistics

rng = Xoshiro(3)
W = randn(rng, 64, 64) .* 2 .* (2.0 .^ (collect(0:63) ./ 4))   # per-row scales
```

**2. Stage wide, then block-quantize per row.** Convert each row's raw values
through a *wide-range* format first (so nothing clamps before the block scale
sees it), then hand fixed-size chunks to `ConvertToBlockMaxAbsFinite`:

```julia
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

Plain `Binary8p4se` quantization clamps the large rows and posts a relative
error of 0.616; the block scheme tracks each row's own scale and cuts that to
0.109 — the residual there is the staging format's own precision, the floor
any downstream scheme can reach.

At `B = 32` with an 8-bit scale, the storage cost is 8.25 bits/value —
slightly more than the bare element format's 8 bits, in exchange for tracking
dynamic range the bare format cannot.

## What can go wrong

!!! warning "Stage wide, then block-quantize"
    `ConvertToBlockMaxAbsFinite` takes already-`Binary` elements. If you stage
    your `Float64` data through the *element* format first, `SatFinite` clamps
    the large values **before** the block scale can absorb them, and blocks
    buy you nothing — we measured exactly that (0.617 vs 0.616) with
    `Binary8p4se` staging. Stage through a wide-range format
    (`Binary8p2se` above); the residual 0.109 here is the staging format's own
    precision, which bounds what any downstream scheme can keep.

!!! note "The scale format should be unsigned"
    Scales are non-negative by construction, so the scale format (`FS` above)
    should be unsigned with as much range as you can spare — `Binary8p1uf` is
    the canonical MX scale shape: precision 1, unsigned, extended for maximal
    dynamic range at minimal bits.

## Where next

[How-To: Choose a Format](howto_choose_format.md)
[How-To: Quantize a Tensor or Model](howto_quantize_tensor.md)
