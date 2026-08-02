# Operation Catalog

This is the canonical catalog of 52 operations: 30 unary, 18 binary, 3
ternary, and `Convert`. The tables distinguish P3109 operation names from
Julia Base spellings. Use the named form when result format and projection must
be explicit; use [Julia Compatibility Register](reference_julia_compat.md) for
the complete Base mapping.

## Unary (30)

| Operation | Arity | Base spelling | Notes | Related guide |
|---|---|---|---|---|
| `Abs` | unary | `abs` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Negate` | unary | unary `-` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Sqrt` | unary | `sqrt` | | [Cheat Sheet](help_cheat_sheet.md) |
| `RSqrt` | unary | — | no Base counterpart; call by draft name | [Julia Compatibility Register](reference_julia_compat.md) |
| `Recip` | unary | `inv` | `Recip(±Inf) = 0` | [Cheat Sheet](help_cheat_sheet.md) |
| `Exp` | unary | `exp` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Exp2` | unary | `exp2` | | [Cheat Sheet](help_cheat_sheet.md) |
| `ExpMinusOne` | unary | `expm1` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Log` | unary | `log` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Log2` | unary | `log2` | | [Cheat Sheet](help_cheat_sheet.md) |
| `LogOnePlus` | unary | `log1p` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Softplus` | unary | — | no Base counterpart; call by draft name | [Julia Compatibility Register](reference_julia_compat.md) |
| `Sin` | unary | `sin` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Cos` | unary | `cos` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Tan` | unary | `tan` | | [Cheat Sheet](help_cheat_sheet.md) |
| `ArcSin` | unary | `asin` | | [Cheat Sheet](help_cheat_sheet.md) |
| `ArcCos` | unary | `acos` | | [Cheat Sheet](help_cheat_sheet.md) |
| `ArcTan` | unary | `atan` | single-argument form; see `ArcTan2` for two-argument | [Cheat Sheet](help_cheat_sheet.md) |
| `Sinh` | unary | `sinh` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Cosh` | unary | `cosh` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Tanh` | unary | `tanh` | | [Cheat Sheet](help_cheat_sheet.md) |
| `ArcSinh` | unary | `asinh` | | [Julia Compatibility Register](reference_julia_compat.md) |
| `ArcCosh` | unary | `acosh` | | [Julia Compatibility Register](reference_julia_compat.md) |
| `ArcTanh` | unary | `atanh` | | [Julia Compatibility Register](reference_julia_compat.md) |
| `SinPi` | unary | `sinpi` | reduces exactly mod 2 first | [Cheat Sheet](help_cheat_sheet.md) |
| `CosPi` | unary | `cospi` | reduces exactly mod 2 first | [Cheat Sheet](help_cheat_sheet.md) |
| `TanPi` | unary | `tanpi` | reduces exactly mod 2 first | [Cheat Sheet](help_cheat_sheet.md) |
| `ArcSinPi` | unary | — | no Base counterpart; call by draft name | [Julia Compatibility Register](reference_julia_compat.md) |
| `ArcCosPi` | unary | — | no Base counterpart; call by draft name | [Julia Compatibility Register](reference_julia_compat.md) |
| `ArcTanPi` | unary | — | no Base counterpart; call by draft name | [Julia Compatibility Register](reference_julia_compat.md) |

Trig of ±Inf is NaN for all rows above.

## Binary (18)

| Operation | Arity | Base spelling | Notes | Related guide |
|---|---|---|---|---|
| `CopySign` | binary | `copysign` | | [Julia Compatibility Register](reference_julia_compat.md) |
| `Add` | binary | `+` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Subtract` | binary | `-` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Multiply` | binary | `*` | | [Cheat Sheet](help_cheat_sheet.md) |
| `Divide` | binary | `/` | `x / 0 → NaN` for every `x`, including ±Inf | [Cheat Sheet](help_cheat_sheet.md) |
| `Hypot` | binary | `hypot` | | [Julia Compatibility Register](reference_julia_compat.md) |
| `ArcTan2` | binary | `atan(y, x)` | Base's `(y, x)` argument order | [Cheat Sheet](help_cheat_sheet.md) |
| `ArcTan2Pi` | binary | — | no Base counterpart; call by draft name | [Julia Compatibility Register](reference_julia_compat.md) |
| `Maximum` | binary | `max` | NaN-propagating, exactly Base's float semantics | [Cheat Sheet](help_cheat_sheet.md) |
| `Minimum` | binary | `min` | NaN-propagating, exactly Base's float semantics | [Cheat Sheet](help_cheat_sheet.md) |
| `MaximumNumber` | binary | — | NaN-ignoring extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MinimumNumber` | binary | — | NaN-ignoring extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MaximumMagnitude` | binary | — | magnitude extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MinimumMagnitude` | binary | — | magnitude extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MaximumMagnitudeNumber` | binary | — | NaN-ignoring magnitude extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MinimumMagnitudeNumber` | binary | — | NaN-ignoring magnitude extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MinimumFinite` | binary | — | finite-preferring extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `MaximumFinite` | binary | — | finite-preferring extremum; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |

`0 · ∞ → NaN`. A NaN operand generally propagates, except the
`*Number`/`*Finite` extremum variants, which prefer a non-NaN (and, for the
`Finite` variants, finite) operand.

## Ternary (3)

| Operation | Arity | Base spelling | Notes | Related guide |
|---|---|---|---|---|
| `FMA` | ternary | `fma`, `muladd` | one rounding for both Base spellings | [Cheat Sheet](help_cheat_sheet.md) |
| `FAA` | ternary | — | fused add-add; no Base counterpart | [Julia Compatibility Register](reference_julia_compat.md) |
| `Clamp` | ternary | `clamp` | | [Cheat Sheet](help_cheat_sheet.md) |

## Conversion

| Operation | Arity | Base spelling | Notes | Related guide |
|---|---|---|---|---|
| `Convert` | conversion | — | the one operation accepting non-`Binary` operands: `Binary` (any format), `Float16/32/64`, `Float128`, `Integer`, `BigFloat` | [Values, Code Points, and Conversion](concept_values_codepoints.md) |

Catalog total: 30 unary + 18 binary + 3 ternary + 1 conversion = 52.

## Base spellings that are componentwise composites

These Base functions are not single draft operations; each is a componentwise
tuple of draft operations run under the session default.

| Base spelling | Composite of |
|---|---|
| `sincos` | `(Sin(x), Cos(x))` |
| `sincospi` | `(SinPi(x), CosPi(x))` |
| `minmax` | `(Minimum(x, y), Maximum(x, y))` |

## Deliberately unmapped draft operations

No Base spelling exists for these; call them by draft name. Base has no
counterpart for any row in this list.

| Draft operation | Reason unmapped |
|---|---|
| `RSqrt` | Base has `inv(sqrt(x))` as two roundings, not one; no single-rounding Base spelling |
| `Softplus` | no Base equivalent |
| `ArcSinPi` | Base has only the `sinpi` family (no inverse) |
| `ArcCosPi` | Base has only the `sinpi` family (no inverse) |
| `ArcTanPi` | Base has only the `sinpi` family (no inverse) |
| `ArcTan2Pi` | Base has only the `sinpi` family (no inverse) |
| `MaximumNumber`, `MinimumNumber` | Base has no NaN-ignoring extremum pair |
| `MaximumMagnitude`, `MinimumMagnitude` | Base has no magnitude-extremum pair |
| `MaximumMagnitudeNumber`, `MinimumMagnitudeNumber` | Base has no NaN-ignoring magnitude-extremum pair |
| `MinimumFinite`, `MaximumFinite` | Base has no finite-preferring extremum pair |
| `FAA` | Base has no fused add-add |

The mapping is a declarative partition over the full op list; the test suite
asserts it is exhaustive — every operation is either mapped to a Base spelling
or listed in `_NO_BASE_COUNTERPART`.

## Call shapes

Explicit form, every operation:

```julia
Op(result_format, ρ, operands...; rng, R)
```

`rng` and `R` apply only to stochastic `ρ`.

Convenience form, same-format operands, `DefaultProjection()`:

```julia
Op(x...)
```

## Related contracts

[Cheat Sheet](help_cheat_sheet.md),
[Why No Cross-Format Promotion](concept_julia_numeric.md),
[Values, Code Points, and Conversion](concept_values_codepoints.md).
