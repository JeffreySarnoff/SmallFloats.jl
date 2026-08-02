# Projection Specifications

Dry listing of `ProjSpec`, the predefined deterministic grid, the stochastic
constructor families, and their accessors. For narrative explanation, see
Projection: Rounding & Saturation.

## `ProjSpec` constructor

```julia
ProjSpec(rounding_mode, saturation_mode)
```

A `ProjSpec` is the pair `(rounding mode, saturation mode)`. Both components
are zero-size singleton types; a `ProjSpec` costs nothing at runtime and fully
specializes every call that reaches it.

## Deterministic predefined specs (6 × 3)

Named `R<mode>_Sat<mode>`. Every cell below is an exported constant.

| Rounding | `SatFinite` | `SatPropagate` | `SatNone` | Teaching page |
|---|---|---|---|---|
| `NearestTiesToEven` | `RNE_SF` | `RNE_SP` | `RNE_SN` | Projection: Rounding & Saturation |
| `NearestTiesToAway` | `RNA_SF` | `RNA_SP` | `RNA_SN` | Projection: Rounding & Saturation |
| `TowardPositive` | `RTP_SF` | `RTP_SP` | `RTP_SN` | Projection: Rounding & Saturation |
| `TowardNegative` | `RTN_SF` | `RTN_SP` | `RTN_SN` | Projection: Rounding & Saturation |
| `TowardZero` | `RTZ_SF` | `RTZ_SP` | `RTZ_SN` | Projection: Rounding & Saturation |
| `ToOdd` | `RTO_SF` | `RTO_SP` | `RTO_SN` | Projection: Rounding & Saturation |

`RNE_SN` is the package-wide initial default (`DefaultProjection()`).

## Stochastic families

Constructors, not constants — the random-bit budget `N` is a type parameter.
`N ∈ 1:60`; omitting `N` uses the default `N = 8` (`SmallFloats.DEFAULT_RBITS`).

| Variant | `SatFinite` | `SatPropagate` | `SatNone` | Teaching page |
|---|---|---|---|---|
| `StochasticA` | `RSA_SF(N)` | `RSA_SP(N)` | `RSA_SN(N)` | Projection: Rounding & Saturation |
| `StochasticB` | `RSB_SF(N)` | `RSB_SP(N)` | `RSB_SN(N)` | Projection: Rounding & Saturation |
| `StochasticC` | `RSC_SF(N)` | `RSC_SP(N)` | `RSC_SN(N)` | Projection: Rounding & Saturation |

```julia
RSA_SN()      # StochasticA, N = 8, SatNone — the default form
RSA_SN(16)    # StochasticA, N = 16, SatNone
RSC_SF(16) === ProjSpec(StochasticC{16}(), SatFinite())   # true
```

## Accessors

| Accessor | Returns | Teaching page |
|---|---|---|
| `roundingmode(ρ)` | the rounding-mode instance | Projection: Rounding & Saturation |
| `saturationmode(ρ)` | the saturation-mode instance | Projection: Rounding & Saturation |
| `isstochastic(ρ)` | `Bool` | Projection: Rounding & Saturation |
| `nrandbits(ρ)` | `N` for a stochastic spec | Projection: Rounding & Saturation |

## Saturation-mode meaning

| Mode | Out-of-range behavior |
|---|---|
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

## see also

[Projection: Rounding & Saturation](tutorial2_projection.md),
[Session Defaults](ref_defaults.md).
