# Quickstart: ten minutes

One continuous session: two values, two ways of adding them, an array through a
nonlinearity, and a block of quantized values. Every line is explained as it
happens; the [Mental Model](@ref) page picks up the "why" where this leaves off.

Assumes a [working install](@ref installation). Start Julia and:

```julia-repl
julia> using SmallFloats
```

## Step 1 — make two values

```julia-repl
julia> x = Binary8p4se(1.6)
Binary8p4se(1.625 ≡ 0x45)
```

You just used the most common format in the examples: `Binary8p4se` — 8 bits,
precision 4, **s**igned, **e**xtended (it has ±Inf). The display tells you both
halves of the story: `1.625` is the *datum* (the exact value the format
represents), `0x45` is the *code point* (the 8-bit name of that datum).

Note what happened to `1.6`: the format has no datum at 1.6, so construction
*projected* — rounded to the nearest representable value, which is 1.625.
Every write into a code point in this package goes through exactly one such
projection.

```julia-repl
julia> y = Binary8p4se(0x46)
Binary8p4se(1.75 ≡ 0x46)
```

An `Unsigned` argument means **code point**, not number — `0x46` is the bit
pattern, and the value is whatever that pattern denotes (1.75).

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ≡ 0x02), Binary8p4se(2.0 ≡ 0x48))
```

Same digit, two very different results: `0x02` is code point 2; `2` is the
numeric value two, projected.

!!! warning "`Unsigned` means code point — at every width"
    `T(0x02)` constructs code point `0x02`; `T(2)` projects the numeric value
    two. Signedness of the integer type is what distinguishes them, and the
    rule holds for `UInt8`, `UInt16` and any other `Unsigned`. Use `Convert`
    when intent should be unmistakable.

## Step 2 — add them, two ways

```julia-repl
julia> x + y
Binary8p4se(3.375 ≡ 0x4d)
```

Ordinary Julia arithmetic works. Under the hood, `+` computed the exact sum
(1.625 + 1.75 = 3.375, which happens to be representable) and projected once.

The same operation, written out in full:

```julia-repl
julia> Add(Binary8p4se, RNE_SN, x, y)
Binary8p4se(3.375 ≡ 0x4d)
```

Every operation in the package has this explicit shape:

```
Op(result_format, projection_spec, operands...)
```

`RNE_SN` is a projection specification: **R**ound to **N**earest, ties
**E**ven, with the draft's default **S**aturation rules (`SN` = SatNone —
the saturation mode is named for what it *doesn't* do: it does not clamp
everything to finite, and it does not blindly propagate infinities; it
applies the draft's domain- and direction-dependent rows). It's the
package-wide default, which is why `+` and `Add(…, RNE_SN, …)` agree.

Why would you want the long form? Because the projection is yours to choose.
Watch an overflow under two different specs (`Binary8p4se` tops out at 224):

```julia-repl
julia> w = Binary8p4se(200.0); two = Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)     # nearest: overflow → +Inf
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)     # SF = clamp to finite range
Binary8p4se(224.0 ≡ 0x7e)
```

Same operands, same exact product (400), different landing — the projection
spec is part of the operation, not an afterthought.

## Step 3 — an array through a nonlinearity

```julia-repl
julia> A = Binary8p4se.([-1.0, 0.5, 2.0])
3-element Vector{Binary8p4se}:
 Binary8p4se(-1.0 ≡ 0xc0)
 Binary8p4se(0.5 ≡ 0x38)
 Binary8p4se(2.0 ≡ 0x48)

julia> Exp(Binary8p4se, RNE_SN, A)
3-element Vector{Binary8p4se}:
 Binary8p4se(0.375 ≡ 0x34)
 Binary8p4se(1.625 ≡ 0x45)
 Binary8p4se(7.5 ≡ 0x57)
```

Broadcasting `Binary8p4se.(…)` projects each element, as you'd expect. The
array call to `Exp` is where the package's speed comes from: an 8-bit unary
operation has only 256 possible inputs, so the first call builds a 256-byte
result table — computed through the exact scalar path — and every element
after that is a single lookup. You can see the table:

```julia-repl
julia> table_bytes()
256
```

One 256-byte table, cached. The Base spelling `exp.(A)` rides the same
machinery under the default projection.

## Step 4 — a block of quantized values

Small formats have small ranges. *Block* formats (the MX-style scheme) fight
that by sharing one scale across a group of narrow elements: each represented
value is `scale × element`.

```julia-repl
julia> values = (100.0, -12.0, 0.5, 3.0);

julia> b = ConvertToBlockMaxAbsFinite(Binary8p1uf, Binary8p4se, RNE_SN, RNE_SN,
                                      Binary8p4se.(values))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(64.0 ≡ 0x86), (…))
```

Read the arguments: scale format `Binary8p1uf` (unsigned — scales are
non-negative — with the huge range precision 1 buys), element format
`Binary8p4se`, one projection spec for the scale and one for the elements, then
the values. The algorithm picked scale 64 from the largest-magnitude element
(100) and projected each element against it.

!!! warning "Stage wide, then block-quantize"
    `ConvertToBlockMaxAbsFinite` takes already-`Binary` elements. If you stage
    `Float64` data through the *element* format first, clamping can happen
    **before** the block scale absorbs it, and blocks buy you nothing. Stage
    through a wide-range format instead. (The example above is safe because
    its values already fit in `Binary8p4se`.)

Read the block back as plain values:

```julia-repl
julia> ConvertFromBlock(Binary8p3se, RNE_SN, b)
(Binary8p3se(6.0 ≡ 0x4a), Binary8p3se(-3.0 ≡ 0xc6), Binary8p3se(8.0 ≡ 0x4c), Binary8p3se(2.0 ≡ 0x44))
```

Each `scale × element` was decoded exactly and projected once into the format
you asked for. And the dot product — the operation blocks exist for — keeps
every lane product and the accumulation *exact* until a single final rounding:

```julia-repl
julia> BlockDotProduct(Binary8p4se, RNE_SN, b, b)
Binary8p4se(10240.0 ≡ 0x6d)
```

## What just happened

Four ideas carried this whole session, and they're the whole package:

1. **A format is a finite set of datums** — `Binary8p4se` is 256 code points
   naming 256 values, no more.
2. **Every write is one projection** — construction, arithmetic, conversion:
   exact math, then round × saturate into a code point.
3. **The projection is explicit** — `RNE_SN` is the default, not the law;
   `Add(T, ρ, …)` takes any spec.
4. **Bulk work is table lookup** — finite functions are precomputed, exactly.

The [Mental Model](@ref) develops each of these properly. If you'd rather
learn by doing, the Tutorials start where this page ends, and the How-To
Guides are organized by task.
