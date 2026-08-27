# Pack Values for Storage

A `Vector{Binary5p2se}` spends a whole byte on each 5-bit code point — three
bits per element wasted, 37% of the array. `PackedVector` stores them at their
true width instead. The trade is explicit: storage shrinks by exactly
`bitwidth(F)/8`, and every read pays a small unpack cost, so this is a win
when memory or bandwidth binds and a loss when only compute does.

## Ingredients

- `PackedVector(v)` built from an existing `Vector{F}`.
- Standard indexing, `collect`, iteration — `PackedVector` is a full
  `AbstractVector{F}`.
- `vmap` for computing directly on packed data (it unpacks tiles internally).
- The sizing rule: `bitwidth(F)` bits per element, rounded up to whole storage
  words.

## Recipe

**1. Build a packed vector from ordinary values.** `PackedVector{F}` stores
each code point in exactly `bitwidth(F)` bits:

```julia-repl
julia> v = Binary5p2se.(rand(Xoshiro(3), 6) .* 4);

julia> pv = PackedVector(v); sizeof(pv.data)
8                     # 6 × 5 bits = 30 bits → one 64-bit word

julia> pv[3] == v[3]
true
```

Six values at 5 bits each is 30 bits, which rounds up to one 64-bit backing
word — `sizeof(pv.data)` reports 8 bytes.

**2. Index, collect, and iterate like any other vector.** `PackedVector` is a
full `AbstractVector{F}`:

```julia
pv[2]
pv[2] = Binary5p2se(0.75)
collect(pv)
```

**3. Compute with `vmap` directly on the packed vector.** `vmap` accepts a
`PackedVector` argument directly, unpacking cache-friendly tiles internally —
you do not need to `collect` first:

```julia
out = vmap(:Exp, Binary5p2se, ρ, pv)
```

**4. Size larger vectors the same way.** The packing ratio is exactly
`bitwidth(F) / 8` against a plain byte-per-element vector (for `K ≤ 8`
formats). At a million elements of a 5-bit format:

```julia-repl
julia> n = 1_000_000;

julia> model = [Binary5p2se(UInt8(rand(0:31))) for _ in 1:n];

julia> pv = PackedVector(model);

julia> (sizeof(model), sizeof(pv.data))
(1000000, 625000)
```

1,000,000 bytes of plain storage becomes 625,000 bytes packed — `n × K / 8`
bytes, in general, rounded to whole words.

## What can go wrong

!!! warning "There is deliberately no in-place packed arithmetic"
    The rule is *store packed, compute unpacked*. Don't reach for an in-place
    packed `+=`-style operation — it doesn't exist. Compute with `vmap`
    (which unpacks internally and returns a fresh result) or unpack with
    `collect` first, compute, then re-pack with `PackedVector` if you want to
    keep the result compressed at rest.

!!! perf "Packing helps storage bandwidth, not per-element compute speed"
    Reach for `PackedVector` when memory footprint or bandwidth is the
    bottleneck (e.g. a large quantized model kept resident). If you are only
    computing, not storing, an ordinary `Vector{F}` is simpler and does not pay
    unpacking cost. Its code-unit storage is one byte for `Code8` and two bytes
    for `Code16`; compare that representation-specific cost with the packed
    bitwidth before choosing a layout.

## Next steps

[Quantize a Tensor or Model](workflow_quantize_measure.md),
[Choose a Format](workflow_choose_format.md).
