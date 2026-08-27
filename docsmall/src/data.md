# Data at Scale

One rule governs this chapter: acceleration may change how work is
scheduled, never which code point is returned. Arrays, cached tables, fused
block reductions, and packed storage are four schedules for the same
exact-then-project computation.

## Arrays and tables

Every operation has array methods with the scalar argument shape, operands
replaced by arrays. Each element is exactly the scalar answer:

```julia-repl
julia> A = Binary8p4se.([-1.0, 0.5, 2.0]);

julia> Exp(Binary8p4se, RNE_SN, A)
3-element Vector{Binary8p4se}:
 Binary8p4se(0.375 ⇆ 0x34)
 Binary8p4se(1.625 ⇆ 0x45)
 Binary8p4se(7.5 ⇆ 0x57)
```

Under a deterministic projection, a unary or binary operation is a finite
function on code points, so the package may cache it. The first array call
for a signature can build a result table; later calls gather from it. Every
table entry is produced by the scalar path and compared against it by the
test gates, so declining the table — stochastic specs draw per element, and
large signatures exceed the byte budget — means running the same scalar path
per element, never computing a different answer. `table_policy` reports
which shape a signature receives and why. When benchmarking, measure the
first (table-building) call separately from warm calls.

Sorting uses integer order keys and, for large vectors, an O(n) counting
sort. Order follows the draft's total order, with the single NaN first.

## Choosing a format

Format choice is a measurement, not a guess. At fixed bitwidth, precision
trades against range, and the trade should be evaluated on data shaped like
yours. For a unit-scale Gaussian sample of 50 000 values projected through
each 8-bit signed extended format under `RNE_SF`:

```
Binary8p5se  rmse = 0.0133   maxfinite = 15.0
Binary8p4se  rmse = 0.0266   maxfinite = 224.0
Binary8p3se  rmse = 0.0528   maxfinite = 49152.0
Binary8p2se  rmse = 0.103    maxfinite = 2.147483648e9
```

RMSE roughly doubles for each significand bit given up, while the finite
range grows enormously. For this sample no format overflows, so the extra
range is unused and the highest precision wins. On wider-spread data the
comparison changes, which is why three numbers should accompany any
quantization choice: aggregate error (RMSE), worst single error, and the
overflow or clamp rate. A format can score well on the first and fail on
either of the others. When the dynamic range genuinely exceeds what the
precision budget allows, do not buy range with a wider element format — get
it from a block scale, below.

Unsigned formats suit quantities that are never negative (probabilities,
memberships, normalized scores); finite formats suit domains where an
infinity would be meaningless. Both spend otherwise-idle code points on
resolution.

The decision, as a checklist:

1. Never negative? Use an unsigned format (`u`).
2. Is an infinity a meaningful outcome? If not, use a finite format (`f`).
3. Run the three-number report (RMSE, worst error, overflow rate) on data
   shaped like yours; take the highest precision whose overflow rate is
   acceptable.
4. Range still exceeds the precision budget? Use a block scale, below — not
   a wider element format.
5. Storage- or bandwidth-bound? Pack, at the end (packing changes layout,
   not the quantization).

## Blocks

When data spans more range than a narrow element format holds, widening the
element spends bits on exponent that were wanted for precision. A
`Block{B,FS,FE}` shares one scale (format `FS`) across `B` elements (format
`FE`); each lane represents `scale × element`. This is the draft's MX-style
scheme. Construct a block directly, or quantize a tuple and let the draft's
algorithm derive the scale from the largest finite magnitude:

```julia-repl
julia> Block(Binary8p1uf(4.0), Binary8p4se(1.5), Binary8p4se(-0.75),
             Binary8p4se(2.0), Binary8p4se(0.5))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(4.0 ⇆ 0x82), (…))

julia> ConvertToBlockMaxAbsFinite(Binary8p1uf, Binary8p4se, RNE_SN, RNE_SN,
           (Binary8p4se(100.0), Binary8p4se(-12.0), Binary8p4se(0.5), Binary8p4se(3.0)))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(64.0 ⇆ 0x86), (…))
```

The arguments read in order: scale format, element format, a projection for
the scale, a projection for the elements, then the values. Here the
algorithm chose scale 64 from the largest element, 100, and projected each
element against it. `ConvertFromBlock(T, ρ, b)` reads a block back out as
plain values, decoding each `scale × element` exactly and projecting once.
Scale formats are conventionally unsigned with precision 1
(`Binary8p1uf`): every datum is a power of two, so dividing by the scale is
exact.

Block reductions are where the exactness contract does real work. A
reduction decodes every lane exactly, accumulates exactly — an integer span
filter proves a `Float128` accumulator suffices, or an arbitrary-precision
accumulator sized from the formats takes over — and projects once:

```julia-repl
julia> b = Block(Binary8p1uf(0.5), (Binary8p4se(80.0), Binary8p4se(-0.375),
                                    Binary8p4se(-5.5), Binary8p4se(2.25)));

julia> SmallFloats.blockdecode(b)              # the exact lane values
(40.0, -0.1875, -2.75, 1.125)

julia> BlockReduceAdd(Binary8p4se, RNE_SN, b)  # exact sum 38.1875, projected once
Binary8p4se(40.0 ⇆ 0x6a)

julia> lanes = SmallFloats.blockdecode(b);

julia> foldl((a, v) -> Add(Binary8p4se, RNE_SN, a, Convert(Binary8p4se, RNE_SN, v)),
             lanes; init = zero(Binary8p4se))  # rounding at every step
Binary8p4se(36.0 ⇆ 0x69)
```

The exact sum is 38.1875 and the correct projection is 40. Lane-by-lane
accumulation lands on 36 — a defined-result error that grows with `B`.
`BlockDotProduct` gives the same guarantee for fused products: on random
32-lane blocks, the entire difference from the `Float64` dot product is the
initial quantization of the inputs; accumulation contributes nothing.

One pitfall dominates block practice. `ConvertToBlockMaxAbsFinite`
quantizes a tuple, deriving the scale from the largest finite magnitude —
but it takes elements that are already `Binary`. If raw data is staged
through the narrow element format first, `SatFinite` clamps the large
values before the block scale can absorb them, and blocking gains nothing.
Measured on a 64×64 matrix whose rows span roughly 2^16 in scale: direct
`Binary8p4se` conversion has relative error 0.616, element-format staging
0.617, and staging through the wide-range `Binary8p2se` before
block-quantizing 0.109 — the staging format's own precision. Stage wide,
then block-quantize. At `B = 32` with an 8-bit scale, storage costs 8.25
bits per value.

## Packed storage

A `Vector{Binary5p2se}` spends a full byte on each 5-bit code point.
`PackedVector(v)` stores elements at true bit width. It is a complete
`AbstractVector{F}` — indexing, iteration, `collect` — and `vmap` computes
on it directly, unpacking tiles internally:

```julia-repl
julia> n = 1_000_000;

julia> model = [Binary5p2se(UInt8(rand(0:31))) for _ in 1:n];

julia> pv = PackedVector(model);

julia> (sizeof(model), sizeof(pv.data))
(1000000, 625000)
```

The rule is store packed, compute unpacked; there is deliberately no
in-place packed arithmetic. Packing pays when memory or bandwidth is the
constraint — for example, a large quantized model held resident. For
compute-only work an ordinary `Vector{F}` avoids the unpack cost.

## Float16 and BFloat16

`Binary16p11se` resembles `Float16`, and `Binary16p8se` resembles
`BFloat16`, but P3109's exponent bias differs from IEEE's by one (16 versus
15; 128 versus 127). Every code point therefore denotes a value a factor of
two away from its IEEE counterpart; largest finite values are 65472 versus
65504, there is one NaN rather than 2046 encodings, and no negative zero.

```julia-repl
julia> using SmallFloats.Formats

julia> Convert(Binary16p11se, RNE_SF, Float16(1.5))    # a conversion: 1.5 ↦ 1.5
Binary16p11se(1.5 ⇆ 0x4200)

julia> reinterpret(Binary16p11se, Float16(1.5))        # the same bits: 1.5 ↦ 0.75
Binary16p11se(0.75 ⇆ 0x3e00)
```

The reinterpreted value is wrong by a factor of two, with no error and no
warning — the most dangerous operation in cross-format work, because the
numbers look plausible. Use `Convert` across the IEEE boundary, never
`reinterpret`. `datumsexact` reports which format pairs round-trip
losslessly.

## Next

[A Worked Example](worked_example.md) composes this chapter and the two
before it into one measured quantization task, end to end.
