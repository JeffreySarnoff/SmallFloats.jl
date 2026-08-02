# Cheat Cards (Appendix)

These cards contain no content not also on the one-page Cheat Sheet; they are
the same sections extracted for single-topic printing.

## Format Card

```text
Binary K p P (s|u) (e|f)
       │   │  │     └─ extended (Inf) or finite domain
       │   │  └────── signed or unsigned
       │   └───────── significand precision, including the implicit bit
       └───────────── total bitwidth, 3 through 16
```

Examples:

| Name | Meaning |
|---|---|
| `Binary8p4se` | 8-bit, precision 4, signed, extended |
| `Binary8p4sf` | 8-bit, precision 4, signed, finite |
| `Binary6p3ue` | 6-bit, precision 3, unsigned, extended |
| `Binary5p5uf` | 5-bit, precision 5, unsigned, finite |
| `Binary16p6se` | 16-bit, precision 6, signed, extended (opt-in export) |
| `Binary16p1uf` | 16-bit, precision 1, unsigned, finite — the MX scale shape |

The alias is the *representation* of the parametric format, related by `<:` and
**not** by `===`:

```julia
Binary8p4se <: Binary{8, 4, true, true}    # true
Binary8p4se === Binary{8, 4, true, true}   # FALSE — `Binary` is abstract
format(16, 6, true, true)                  # the alias, from runtime parameters
```

`using SmallFloats` exports the 120 aliases at K ≤ 8. For the other 384:
`using SmallFloats.Formats`, or `SmallFloats.Binary16p6se`, or `format(...)`.

Useful format queries:

```julia
bitwidth(T)       # K
precision(T)      # P
issigned(T)
isextended(T)
expbias(T)
expbitwidth(T)
trailingsigbits(T)

MaxFiniteOf(T)
MinFiniteOf(T)
MinPositiveOf(T)
MinNormalOf(T)
MaxSubnormalOf(T)
```

Every query above also takes a **value** instead of a type — `bitwidth(x)` ≡
`bitwidth(typeof(x))` — and folds to the same constant:

```julia
x = Binary8p4se(1.6)
bitwidth(x)       # 8
MaxFiniteOf(x)    # Binary8p4se(224.0 ≡ 0x7e)
```

Format limits: bitwidth `K` ranges 3 through 16; the domain parameter is
extended (`e`, has ±Inf) or finite (`f`, does not); signedness is signed
(`s`) or unsigned (`u`); precision `P` includes the implicit bit.

## Ops Card

The explicit operation shape is always:

```julia
Op(result_format, projection_spec, operands...; rng, R)
```

For same-format operands under the default projection, ordinary Julia syntax is
available:

```julia
z == x + y
exp(x)
fma(x, y, z)
```

The two registers, explicit and convenience:

```julia
# explicit result format and projection
Add(T, ρ, x, y)
FMA(T, ρ, x, y, z)
Convert(T, ρ, external_value)

# same-format default-projection convenience
Add(x, y)
FMA(x, y, z)
```

| Arity | Operations |
|---|---|
| Unary | `Abs`, `Negate`, `Sqrt`, `RSqrt`, `Recip`, `Exp`, `Exp2`, `ExpMinusOne`, `Log`, `Log2`, `LogOnePlus`, `Softplus`, `Sin`, `Cos`, `Tan`, `ArcSin`, `ArcCos`, `ArcTan`, `Sinh`, `Cosh`, `Tanh`, `ArcSinh`, `ArcCosh`, `ArcTanh`, `SinPi`, `CosPi`, `TanPi`, `ArcSinPi`, `ArcCosPi`, `ArcTanPi` |
| Binary | `CopySign`, `Add`, `Subtract`, `Multiply`, `Divide`, `Hypot`, `ArcTan2`, `ArcTan2Pi`, `Maximum`, `Minimum`, `MaximumNumber`, `MinimumNumber`, `MaximumMagnitude`, `MinimumMagnitude`, `MaximumMagnitudeNumber`, `MinimumMagnitudeNumber`, `MinimumFinite`, `MaximumFinite` |
| Ternary | `FMA`, `FAA`, `Clamp` |
| Conversion | `Convert` |

Common Base spellings under `RNE_SN`:

```julia
x + y; x - y; x * y; x / y
-x; abs(x); inv(x); sqrt(x)
exp(x); exp2(x); expm1(x)
log(x); log2(x); log1p(x)
sin(x); cos(x); tan(x)
asin(x); acos(x); atan(x); atan(y, x)
sinh(x); cosh(x); tanh(x)
min(x, y); max(x, y); clamp(x, y, z)
fma(x, y, z); muladd(x, y, z)
```

Array forms — every registered operation has elementwise array methods:

```julia
A = T.([1.0, 1.5, 2.0])
B = T.([0.25, 0.5, 0.75])

C = Add(T, ρ, A, B)
E = Exp(T, ρ, A)
F = FMA(T, ρ, A, B, C)

C = vmap(:Add, T, ρ, A, B)
vmap!(C, Val(:Add), T, ρ, A, B)
```

Operands and destination must have matching axes. Deterministic unary/binary
operations use cached result tables; affordable ternary signatures may also use
tables. Stochastic operations compute each element and consume one draw per
projection.

```julia
table_bytes()
empty_tables!()
```

## Blocks & Packed Card

Block construction and queries:

```julia
FS = Binary8p1uf
FE = Binary8p4se

b = Block(FS(4.0), FE(1.5), FE(-0.75), FE(2.0), FE(0.5))

blocksize(b)
scaleformat(b)
elemformat(b)

ConvertFromBlock(T, ρ, b)
BlockReduceAdd(T, ρ, b)
BlockReduceMultiply(T, ρ, b)
BlockDotProduct(T, ρ, b, b)
```

Every scalar operation except `Convert` has generated block and scaled forms:

```julia
BlockAdd(T, ρ, b1, b2, result_scale)
BlockExp(T, ρ, b, result_scale)

ScaledAdd(T, ρ, scale1, x1, scale2, x2)
ScaledExp(T, ρ, scale, x)
```

Quantization against a supplied or automatically selected scale:

```julia
ConvertToBlock(FS, FE, ρ, values_tuple, scale)
ConvertToBlockMaxAbsFinite(FS, FE, scale_ρ, element_ρ, values_tuple)
```

`BlockVector` stores many equal-shape blocks in a structure-of-arrays layout.

`PackedVector`:

```julia
v = Binary5p2se.([0.5, 1.0, 1.5, 2.0])
pv = PackedVector(v)

pv[2]
pv[2] = Binary5p2se(0.75)
collect(pv)

out = vmap(:Exp, Binary5p2se, ρ, pv)
```

`PackedVector` stores each code point in exactly `bitwidth(F)` bits.
Computation unpacks tiles internally; packed arithmetic is deliberately not
in-place.

Where next: [Cheat Sheet](@ref cheatsheet), [Troubleshooting](@ref troubleshooting).
