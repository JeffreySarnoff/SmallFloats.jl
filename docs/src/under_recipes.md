# Internals Recipes

Outputs below are captured from real sessions. These examples use unexported
internals (`SmallFloats.round_to_precision`, `SmallFloats.project`, `SmallFloats.get_table`,
`SmallFloats.order_key`, …); those are stable enough to learn from but are not
covered by semantic-versioning guarantees.

## Watching RoundToPrecision work

`round_to_precision` returns the draft's exact `(sign, S, Q)` decomposition before
saturation ever sees it:

```julia
using SmallFloats
using SmallFloats: round_to_precision

r = round_to_precision(4, 8, NearestTiesToEven(), 2.30078125, 0, 0)   # P=4, bias=8
(r.sign, r.S, r.Q, r.S * 2.0^r.Q)
```

```
(1, 9, -2, 2.25)          # S·2^Q = 9/4: the nearest P=4 value
```

## Symbolic sticky: projecting "just below" a number

The engine accepts `sticky ∈ {-1, 0, +1}` meaning "the true value is the carrier
plus an infinitesimal of this sign". This is how enclosure endpoints and asymptotes
(`tanh → 1⁻`) are projected exactly:

```julia
using SmallFloats: project
project(Binary8p4se, ProjSpec(TowardNegative(), SatNone()), 1.0; sticky=-1)
```

```
Binary8p4se(0.9375 ≡ 0x3f)     # == NextLessThan(1.0): the engine crossed the binade
```

## Tables are the scalar path, memoized

```julia
using SmallFloats: get_table
empty_tables!()
tbl = get_table(:Exp, Binary8p4se, Binary8p4se, RNE_SN)
(tbl[Int(0x45) + 1],
 codepoint(Exp(Binary8p4se, RNE_SN, rawvalue(Binary8p4se, 0x45))),
 table_bytes())
```

```
(0x52, 0x52, 256)              # table entry ≡ scalar result; one 256-byte table cached
```

## Order keys

Ordering is integer arithmetic: a sign-magnitude fold, monotone with the total
order, NaN at the top. This is what comparisons and the O(n) counting sort run on:

```julia
using SmallFloats: order_key
[(v, order_key(v)) for v in (Binary8p4se(-1.0), Binary8p4se(0.0),
                             Binary8p4se(1.0), Binary8p4se(NaN))]
```

```
-1.0 → 64      0.0 → 129      1.0 → 193      NaN → 65535
```

## see also

[The Encoding & Projection Engine](under_engine.md),
[Tables, Kernels & Sorting](under_tables.md),
[Verify Custom Code](howto_verify_custom.md).
