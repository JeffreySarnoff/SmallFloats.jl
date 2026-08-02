# How-To: Quantize a Tensor or Model

Project a full weight tensor into a small format, measure the damage, and pack
the result for storage.

## Ingredients

- `Binary8p4se.(...)` (or any format, broadcast) to project every element.
- `decode.(...)` to bring the quantized values back to `Float64` for
  measurement.
- `mean`, `maximum`, `count`/`isinf` from `Statistics`/`Base` for MSE, max
  error, and overflow fraction.
- `rawvalue`, `PackedVector` to pack the quantized codes for storage.

## Recipe

**1. Project the tensor.** Broadcasting the format constructor projects every
weight independently, exactly as a single value would:

```julia
using SmallFloats, Random, Statistics

rng = Xoshiro(42)
w = randn(rng, 10_000) .* 0.25          # typical trained-weight scale
q = Binary8p4se.(w)                     # project every weight
back = decode.(q)

mean((w .- back).^2), maximum(abs.(w .- back)), count(isinf, back) / length(back)
```

```
(4.41e-5, 0.0312, 0.0)                  # MSE, max |error|, overflow fraction
```

Report all three numbers together, not just MSE: the max error is exactly half
an ulp of the largest binade the data reached (the worst case nearest rounding
permits), and the overflow fraction catches tail values that clamped or blew
up to `Inf` — a failure mode MSE alone can hide if it affects only a few
elements.

**2. Pack the quantized model for storage.** Once you have code points, a
`PackedVector` stores them at `bitwidth(F)` bits per element instead of one
byte (or two) per element:

```julia
n = 1_000_000
model = [rawvalue(Binary5p2se, UInt8(rand(0:31))) for _ in 1:n]
pv = PackedVector(model)
(sizeof(model), sizeof(pv.data))
```

```
(1000000, 625000)   # 8 bits → 5 bits per value; indexing and vmap work directly on pv
```

`Binary5p2se` is 5 bits wide, so 1,000,000 values pack into 625,000 bytes
instead of 1,000,000 — indexing, `collect`, and `vmap` all work directly on
`pv` without a separate unpacking step.

**3. Verify the quantizer, don't just trust it.** Formats are small enough to
check exhaustively rather than spot-check. Enumerate every in-range code point
of the source format, project it, and compare against an independent
brute-force nearest search:

```julia
using SmallFloats

function ref_nearest_distance(::Type{T}, x) where {T}
    fins = [v for v in (rawvalue(T, UInt8(c)) for c in 0:255) if isfinite(decode(v))]
    minimum(abs(setprecision(() -> BigFloat(decode(v)) - BigFloat(x), BigFloat, 256))
            for v in fins)
end

function verify_quantizer()
    ok = true
    for c in 0x00:0xff
        x = decode(rawvalue(Binary8p3se, c))
        (isfinite(x) && abs(x) <= decode(MaxFiniteOf(Binary8p4se))) || continue
        got = Convert(Binary8p4se, RNE_SN, x)
        ok &= abs(decode(got) - x) == Float64(ref_nearest_distance(Binary8p4se, x))
    end
    ok
end
verify_quantizer()
```

```
true
```

This pattern — enumerate the inputs, compare against an independently written
reference — costs a few hundred comparisons and is available to your own
quantization code at trivial cost.

## What can go wrong

!!! warning "MSE looks fine while overflow silently eats the tail"
    A tensor with a few large outliers can show excellent MSE while those
    outliers all clamp to `Inf` (or `MaxFinite` under `SatFinite`). Always
    check the overflow fraction, and if it is nonzero, either widen the
    format's range or move to a block-scaled format instead of a bare element
    format.

!!! perf "Packing is for storage, not compute"
    `PackedVector` is deliberately not in-place-arithmetic-capable: the rule
    is store packed, compute unpacked. Don't try to quantize *into* a
    `PackedVector` element by element — build the plain `Vector{F}` first
    (as above), then wrap it with `PackedVector`.

## Where next

[How-To: Choose a Format](howto_choose_format.md)
[How-To: Work with Packed Storage](howto_packed_storage.md)
[How-To: Use Blocks to Track Dynamic Range](howto_blocks_dynamic_range.md)
