# Computing

Every numeric operation follows the same three steps: decode the operands,
compute the mathematically exact result over the extended reals, and project
once. There is no arithmetic "in the format" and no accumulated rounding
inside an operation. Rounding error arises only at the single point where the
exact result becomes a code point. This chapter covers that point: the two
policy choices that decide it, and how to keep the decision stable.

## One projection, named in the call

```julia-repl
julia> x, y = Binary8p4se(1.6), Binary8p4se(0x46);

julia> Add(Binary8p4se, RNE_SN, x, y)
Binary8p4se(3.5 ⇆ 0x4e)
```

The call reads left to right: operation, result format, projection
specification, operands. The exact sum, 1.625 + 1.75 = 3.375, is not a
datum; it lies exactly halfway between 3.25 and 3.5, so the stored result is
determined entirely by policy. `RNE_SN` rounds to nearest with ties to even,
selecting 3.5, then applies the draft's `SatNone` boundary rules. A
different projection could land the same sum on 3.25. The projection
therefore appears in the argument list: it is part of the operation, not an
ambient setting.

The ordinary Julia spelling uses the current session default:

```julia-repl
julia> x + y
Binary8p4se(3.5 ⇆ 0x4e)
```

Use `+` and the other operators for interactive work. Use
`Add(T, ρ, ...)` in code whose results must not depend on session state.

## Rounding and saturation

A `ProjSpec` pairs two independent choices. Rounding selects the neighbor:
six deterministic modes (nearest-ties-even, nearest-ties-away, toward
positive, toward negative, toward zero, to-odd), with every pairing
predefined under names such as `RNE_SN` and `RTZ_SF`. Saturation decides
what an out-of-range result becomes: `SatFinite` clamps to the finite
extremes, `SatPropagate` preserves representable infinities, and `SatNone`
applies the draft's full domain-, sign-, and direction-dependent rows.
`SatNone` does not mean "no saturation"; it means neither simplifying policy
was selected.

The axes separate cleanly on one overflow. Note first that
`Binary8p4se(200.0)` already projected during construction — 200 ties
between 192 and 208 and lands on 192 — so both multiplies below compute the
exact product 384, which exceeds the largest finite datum, 224:

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)   # nearest + draft rows → Inf
Binary8p4se(Inf ⇆ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)   # nearest + clamp → 224
Binary8p4se(224.0 ⇆ 0x7e)

julia> Multiply(Binary8p4se, RTZ_SN, w, two)   # toward zero + draft rows → 224
Binary8p4se(224.0 ⇆ 0x7e)
```

The first two calls differ in saturation; the first and third differ in
rounding. The third is the subtle case: rounding runs first and knows
nothing about range, and saturation then classifies the out-of-range result
with the rounding mode passed in — so a directed mode pointing away from the
overflow yields the finite extreme even under `SatNone`. Choose `SatNone`
when an overflow should remain observable as an infinity, `SatFinite` when
downstream code cannot absorb one.

## Stochastic rounding

The three stochastic families (`StochasticA/B/C`, with random-bit budget
`N`) make the landing depend on the exact fractional position and a draw
`R ∈ 0:2^N−1`. The distribution is part of the definition: projecting
2 + 3/64 under `RSA_SN(4)`, a value three sixteenths of the way from 2.0 to
2.25, rounds upward for exactly 3 of the 16 possible draws. Fixing `R` makes
a single projection exactly reproducible, which suits tests:

```julia-repl
julia> σ = RSA_SN();                 # StochasticA, default N = 8

julia> a, b = Binary8p4se(2.0), Binary8p4se(0.03125);

julia> Add(Binary8p4se, σ, a, b; R = 0)
Binary8p4se(2.0 ⇆ 0x48)      # smallest draw: rounds down

julia> Add(Binary8p4se, σ, a, b; R = 255)
Binary8p4se(2.25 ⇆ 0x49)     # largest draw: rounds up
```

For streams, pass a seeded `rng`; stochastic projection draws from the same
generator as any value draws, so one seed reproduces a whole pipeline. An
out-of-range `R` is an error, not a silently wrapped value.

## Random values

`rand` and `randn` work for every format, and both accept an explicit RNG
for reproducibility:

```julia-repl
julia> rand(Xoshiro(1), Binary8p4se)
Binary8p4se(0.0703125 ⇆ 0x21)

julia> rand(Xoshiro(8), Binary8p4se, 4)
4-element Vector{Binary8p4se}:
 Binary8p4se(0.40625 ⇆ 0x35)
 Binary8p4se(0.021484375 ⇆ 0x13)
 Binary8p4se(0.75 ⇆ 0x3c)
 Binary8p4se(0.28125 ⇆ 0x31)
```

Scalar `rand` takes a `projection` keyword. The default is a floor
projection, which keeps results in `[0, 1)` as `rand`'s contract requires;
opting into `RTP_SN` or `RNE_SN` can return exactly 1.0, since mass near the
top rounds up. The array and in-place forms always use the defaults — for an
array under another projection, draw scalars explicitly.

## Session defaults

Five process-wide defaults back the convenience forms: `DefaultType`,
`DefaultReturnType`, `DefaultRoundingMode`, `DefaultSaturationMode`, and
`DefaultProjection`. The projection default and its two components remain
coherent regardless of which setter ran last:

```julia
DefaultProjection() === ProjSpec(DefaultRoundingMode(), DefaultSaturationMode())
```

A setter mutates state shared by every module in the process, and nothing
scopes or restores it:

```julia-repl
julia> w * two                            # follows the default: RNE_SN → Inf
Binary8p4se(Inf ⇆ 0x7f)

julia> DefaultProjection!(RTZ_SF);

julia> w * two                            # every convenience call changed
Binary8p4se(224.0 ⇆ 0x7e)

julia> DefaultProjection!(RNE_SN)         # restore; the setting is process-wide
(NearestTiesToEven, SatNone)

julia> Multiply(Binary8p4se, RNE_SN, w, two)   # explicit ρ never reads a default
Binary8p4se(Inf ⇆ 0x7f)
```

Library code and experiments should name `T` and `ρ` explicitly. The setters
are appropriate for interactive sessions you control.

## Interaction with Julia's numeric model

Same-format expressions use ordinary Julia spellings — `+ - * /`, `exp`,
`sqrt`, comparisons — each equivalent to one draft operation under the
session default. Three boundaries are deliberate:

- **Mixed `Binary` formats do not promote.** No automatic rule can soundly
  pick a containing format (most format pairs have none within the grid, and
  pairwise selection is not associative), so cross-format arithmetic
  requires an explicit `Convert`.
- **`Binary` with an ordinary number promotes to the format's carrier.**
  `Binary8p4se(1.5) + 2.0` returns the `Float64` value `3.5`, not a `Binary`
  value; the 72 wide formats promote to `BigFloat` instead, since a
  `Float64` cannot hold their datums. Project back explicitly when the
  result should be in the format.
- **Some inputs are refused rather than double-rounded.** `Convert` accepts
  every type it can project exactly: `Binary` values, machine floats,
  `Float128`, integers, `BigFloat`. A `Rational` would require a hidden
  second rounding to reach a carrier, so it throws with guidance — convert
  to a supported carrier first, making that rounding your explicit choice.

Two draft semantics differ from IEEE 754 by design. `Divide(x, 0)` is NaN
for every `x`, including ±Inf, and `Recip(±Inf)` is 0 — there are no
signed-infinity quotients. And the total order places the single NaN first,
below −Inf, so sorting a `Binary` vector leads with NaN.

## Next

This chapter computed one value at a time. The same contract must hold for
large arrays, fused reductions, and storage at true bit width, without
acceleration changing any code point. That is the subject of
[Data at Scale](data.md).
