# Projection Specifications

This page is the lookup contract for `ProjSpec`, the predefined deterministic
grid, stochastic constructor families, and projection accessors. For the
conceptual model, read [Rounding and Saturation](concept_rounding_saturation.md).

## `ProjSpec` constructor

```julia
ProjSpec(rounding_mode, saturation_mode)
```

A `ProjSpec` is the pair `(rounding mode, saturation mode)`. Both components
are zero-size singleton types; a `ProjSpec` costs nothing at runtime and fully
specializes every call that reaches it.

## Deterministic predefined specs (6 × 3)

Named `R<mode>_Sat<mode>`. Every cell below is an exported constant.

| Rounding | `SatFinite` | `SatPropagate` | `SatNone` | Related guide |
|:---|---|---|---|---|
| `NearestTiesToEven` | `RNE_SF` | `RNE_SP` | `RNE_SN` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `NearestTiesToAway` | `RNA_SF` | `RNA_SP` | `RNA_SN` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `TowardPositive` | `RTP_SF` | `RTP_SP` | `RTP_SN` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `TowardNegative` | `RTN_SF` | `RTN_SP` | `RTN_SN` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `TowardZero` | `RTZ_SF` | `RTZ_SP` | `RTZ_SN` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `ToOdd` | `RTO_SF` | `RTO_SP` | `RTO_SN` | [Rounding and Saturation](concept_rounding_saturation.md) |

`RNE_SN` is the package-wide initial default (`DefaultProjection()`).

## Stochastic families

Constructors, not constants — the random-bit budget `N` is a type parameter.
`N ∈ 1:60`; omitting `N` uses the default `N = 8` (`SmallFloats.DEFAULT_RBITS`).

| Variant | `SatFinite` | `SatPropagate` | `SatNone` | Related guide |
|:---|---|---|---|---|
| `StochasticA` | `RSA_SF(N)` | `RSA_SP(N)` | `RSA_SN(N)` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `StochasticB` | `RSB_SF(N)` | `RSB_SP(N)` | `RSB_SN(N)` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `StochasticC` | `RSC_SF(N)` | `RSC_SP(N)` | `RSC_SN(N)` | [Rounding and Saturation](concept_rounding_saturation.md) |

```julia
RSA_SN()      # StochasticA, N = 8, SatNone — the default form
RSA_SN(16)    # StochasticA, N = 16, SatNone
RSC_SF(16) === ProjSpec(StochasticC{16}(), SatFinite())   # true
```

## Accessors

| Accessor | Returns | Related guide |
|:---|---|---|
| `roundingmode(ρ)` | the rounding-mode instance | [Rounding and Saturation](concept_rounding_saturation.md) |
| `saturationmode(ρ)` | the saturation-mode instance | [Rounding and Saturation](concept_rounding_saturation.md) |
| `isstochastic(ρ)` | `Bool` | [Rounding and Saturation](concept_rounding_saturation.md) |
| `nrandbits(ρ)` | `N` for a stochastic spec | [Rounding and Saturation](concept_rounding_saturation.md) |

## Saturation-mode meaning

| Mode | Out-of-range behavior |
|:---|---|
| `SatFinite` | clamp everything to the finite range |
| `SatPropagate` | preserve representable infinities; clamp other overflow |
| `SatNone` | apply the draft's domain-, signedness-, and direction-dependent rows (nearest modes overflow to ±Inf or NaN for finite formats; directed modes pointing away from the overflow clamp to the extremal finite value) |

## Explicit `R` range rule

For an `N`-bit stochastic mode, an explicit draw `R` passed as a keyword must
satisfy `0 ≤ R ≤ 2^N - 1`. Passing `R` outside that range is an error.

```julia
Add(T, σ, x, y; rng = Xoshiro(1))   # reproducible stream
Add(T, σ, x, y; R = 17)             # exact draw, ideal for tests
```

## Related contracts

[Rounding and Saturation](concept_rounding_saturation.md),
[Session Defaults](reference_defaults_random_display.md).
