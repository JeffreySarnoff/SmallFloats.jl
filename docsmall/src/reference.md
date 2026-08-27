# Quick Reference

Names and signatures in brief. For semantics, see the preceding chapters;
for exhaustive tables, the full manual's Reference section.

## Values in and out

```julia
Binary8p4se(1.6)          # Real → project to nearest datum
Binary8p4se(0x45)         # Unsigned → CODE POINT (validated)
Convert(T, ρ, x)          # explicit projection, numeric for every integer
decode(x)                 # the exact datum, on the format's carrier
codepoint(x)              # the stored identity
T(codepoint(x)) === x     # the round-trip law
```

## Format queries

Pure functions of the type parameters; each takes a type or a value, and
folds to a constant either way.

```julia
bitwidth(T)  precision(T)  issigned(T)  isextended(T)
expbias(T)   expbitwidth(T)  trailingsigbits(T)
MaxFiniteOf(T)  MinFiniteOf(T)  MinPositiveOf(T)
MinNormalOf(T)  MaxSubnormalOf(T)
format(K, P, SGN, EXT)    # programmatic route to any of the 504
```

Draft-named twins exist throughout: `BitwidthOf`, `PrecisionOf`,
`ExponentBiasOf`, ….

## Projection specifications

`ProjSpec(rounding, saturation)`; every deterministic pairing is predefined
as `R<mode>_S<mode>`:

| | `SatNone` | `SatFinite` | `SatPropagate` |
|:--|:--|:--|:--|
| `NearestTiesToEven` | `RNE_SN` | `RNE_SF` | `RNE_SP` |
| `NearestTiesToAway` | `RNA_SN` | `RNA_SF` | `RNA_SP` |
| `TowardPositive` | `RTP_SN` | `RTP_SF` | `RTP_SP` |
| `TowardNegative` | `RTN_SN` | `RTN_SF` | `RTN_SP` |
| `TowardZero` | `RTZ_SN` | `RTZ_SF` | `RTZ_SP` |
| `ToOdd` | `RTO_SN` | `RTO_SF` | `RTO_SP` |

Stochastic constructors: `RSA_SN(N)`, `RSB_SF(N)`, `RSC_SP(N)`, … — families
A/B/C crossed with the saturation modes, `N` random bits (default 8). Pass
`rng` for a stream or `R ∈ 0:2^N−1` for one exact draw. `RNE_SN` is the
initial session default.

## Operations

52 draft operations — 30 unary, 18 binary, 3 ternary, plus `Convert` — every
one spelled `Op(fr, ρ, operands…)` with a same-format convenience `Op(x…)`,
array methods, and `Block`/`Scaled` variants. Families: sign and arithmetic
(`Abs` … `Divide`, fused `FMA`/`FAA`), roots and exp/log, trig, hyperbolic,
π-scaled trig, `Softplus`/`Hypot`/`ArcTan2`, extrema and `Clamp`,
comparisons and `TotalOrder`, format queries, `NextGreaterThan` /
`NextLessThan`. Base spellings (`+`, `exp`, `sqrt`, `min`, `nextfloat`, …)
map one-to-one onto same-format calls under the session default.

## Session defaults

Read with `DefaultX()`, set with `DefaultX!(v)`:

```julia
DefaultType        DefaultReturnType
DefaultRoundingMode  DefaultSaturationMode  DefaultProjection
```

The projection default and its two component defaults stay coherent no
matter which setter ran last. All five are process-global; name `T` and `ρ`
explicitly in anything that must be reproducible.

## Display

`set_show_style!(s)` / `get_show_style()`, or per-stream
`IOContext(io, :binary_show_style => s)`, with
`s ∈ (:value, :codepoint, :datum, :typed)` — e.g. `1.625` · `0x45` ·
`1.625 ⇆ 0x45` · `Binary8p4se(1.625 ⇆ 0x45)`. Presentation only; no result
ever depends on it.

## Blocks, storage, conformance

```julia
Block(scale, elems...)                       # scale × element per lane
ConvertToBlockMaxAbsFinite(FS, FE, ρs, ρe, elems)
BlockReduceAdd(T, ρ, b);  BlockDotProduct(T, ρ, a, b)
PackedVector(v)                              # true bit-width storage
measure_kappa(f, op, T, argTs, ρ)            # exhaustive κ measurement
register_approx!(name, op, T, argTs, ρ, f; κ)
conformance_dict();  draft_revision()
```

## Common mistakes

1. `T(2)` where `T(0x02)` was meant, or the reverse. The integer type's
   signedness selects value versus code point, and both calls succeed.
2. `Vector` of the abstract `Binary{K,P,SGN,EXT}`. The abstract format
   boxes every element; use the concrete alias.
3. A format or spec held in a non-`const` global. Every call then pays
   dynamic dispatch (about 1 µs), and benchmarks measure the dispatcher
   rather than the package.
4. Reading `SatNone` as a clamp. Only `SatFinite` guarantees a finite
   result; `SatNone` applies the draft's rows and can produce ±Inf or NaN.
5. Staging raw data through the narrow element format before
   block-quantizing. The clamp then happens before the block scale can
   absorb it; stage through a wide-range format instead.
