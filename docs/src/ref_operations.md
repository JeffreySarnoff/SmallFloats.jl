# Reference: Operation Catalog

The canonical operation table. 52 operations total: 30 unary, 18 binary, 3
ternary, 1 conversion. Source: the scalar operation catalog in the Cheat
Sheet, cross-checked against Julia Compatibility. For semantics and worked
examples, see the User Guide and Julia Compatibility pages.

## Unary (30)

| Operation | Arity | Base spelling | Notes | Teaching page |
|---|---|---|---|---|
| `Abs` | unary | `abs` | | Cheat Sheet |
| `Negate` | unary | unary `-` | | Cheat Sheet |
| `Sqrt` | unary | `sqrt` | | Cheat Sheet |
| `RSqrt` | unary | — | no Base counterpart; call by draft name | Julia Compatibility |
| `Recip` | unary | `inv` | `Recip(±Inf) = 0` | Cheat Sheet |
| `Exp` | unary | `exp` | | Cheat Sheet |
| `Exp2` | unary | `exp2` | | Cheat Sheet |
| `ExpMinusOne` | unary | `expm1` | | Cheat Sheet |
| `Log` | unary | `log` | | Cheat Sheet |
| `Log2` | unary | `log2` | | Cheat Sheet |
| `LogOnePlus` | unary | `log1p` | | Cheat Sheet |
| `Softplus` | unary | — | no Base counterpart; call by draft name | Julia Compatibility |
| `Sin` | unary | `sin` | | Cheat Sheet |
| `Cos` | unary | `cos` | | Cheat Sheet |
| `Tan` | unary | `tan` | | Cheat Sheet |
| `ArcSin` | unary | `asin` | | Cheat Sheet |
| `ArcCos` | unary | `acos` | | Cheat Sheet |
| `ArcTan` | unary | `atan` | single-argument form; see `ArcTan2` for two-argument | Cheat Sheet |
| `Sinh` | unary | `sinh` | | Cheat Sheet |
| `Cosh` | unary | `cosh` | | Cheat Sheet |
| `Tanh` | unary | `tanh` | | Cheat Sheet |
| `ArcSinh` | unary | `asinh` | | Julia Compatibility |
| `ArcCosh` | unary | `acosh` | | Julia Compatibility |
| `ArcTanh` | unary | `atanh` | | Julia Compatibility |
| `SinPi` | unary | `sinpi` | reduces exactly mod 2 first | Cheat Sheet |
| `CosPi` | unary | `cospi` | reduces exactly mod 2 first | Cheat Sheet |
| `TanPi` | unary | `tanpi` | reduces exactly mod 2 first | Cheat Sheet |
| `ArcSinPi` | unary | — | no Base counterpart; call by draft name | Julia Compatibility |
| `ArcCosPi` | unary | — | no Base counterpart; call by draft name | Julia Compatibility |
| `ArcTanPi` | unary | — | no Base counterpart; call by draft name | Julia Compatibility |

Trig of ±Inf is NaN for all rows above.

## Binary (18)

| Operation | Arity | Base spelling | Notes | Teaching page |
|---|---|---|---|---|
| `CopySign` | binary | `copysign` | | Julia Compatibility |
| `Add` | binary | `+` | | Cheat Sheet |
| `Subtract` | binary | `-` | | Cheat Sheet |
| `Multiply` | binary | `*` | | Cheat Sheet |
| `Divide` | binary | `/` | `x / 0 → NaN` for every `x`, including ±Inf | Cheat Sheet |
| `Hypot` | binary | `hypot` | | Julia Compatibility |
| `ArcTan2` | binary | `atan(y, x)` | Base's `(y, x)` argument order | Cheat Sheet |
| `ArcTan2Pi` | binary | — | no Base counterpart; call by draft name | Julia Compatibility |
| `Maximum` | binary | `max` | NaN-propagating, exactly Base's float semantics | Cheat Sheet |
| `Minimum` | binary | `min` | NaN-propagating, exactly Base's float semantics | Cheat Sheet |
| `MaximumNumber` | binary | — | NaN-ignoring extremum; no Base counterpart | Julia Compatibility |
| `MinimumNumber` | binary | — | NaN-ignoring extremum; no Base counterpart | Julia Compatibility |
| `MaximumMagnitude` | binary | — | magnitude extremum; no Base counterpart | Julia Compatibility |
| `MinimumMagnitude` | binary | — | magnitude extremum; no Base counterpart | Julia Compatibility |
| `MaximumMagnitudeNumber` | binary | — | NaN-ignoring magnitude extremum; no Base counterpart | Julia Compatibility |
| `MinimumMagnitudeNumber` | binary | — | NaN-ignoring magnitude extremum; no Base counterpart | Julia Compatibility |
| `MinimumFinite` | binary | — | finite-preferring extremum; no Base counterpart | Julia Compatibility |
| `MaximumFinite` | binary | — | finite-preferring extremum; no Base counterpart | Julia Compatibility |

`0 · ∞ → NaN`. A NaN operand generally propagates, except the
`*Number`/`*Finite` extremum variants, which prefer a non-NaN (and, for the
`Finite` variants, finite) operand.

## Ternary (3)

| Operation | Arity | Base spelling | Notes | Teaching page |
|---|---|---|---|---|
| `FMA` | ternary | `fma`, `muladd` | one rounding for both Base spellings | Cheat Sheet |
| `FAA` | ternary | — | fused add-add; no Base counterpart | Julia Compatibility |
| `Clamp` | ternary | `clamp` | | Cheat Sheet |

## Conversion

| Operation | Arity | Base spelling | Notes | Teaching page |
|---|---|---|---|---|
| `Convert` | conversion | — | the one operation accepting non-`Binary` operands: `Binary` (any format), `Float16/32/64`, `Float128`, `Integer`, `BigFloat` | Tutorial 1: Values, Code Points & Conversion |

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

Where next: [Cheat Sheet](@ref cheatsheet),
[Why No Cross-Format Promotion](@ref explain_no_promotion),
[Tutorial 1: Values, Code Points & Conversion](@ref tutorial1_values).
