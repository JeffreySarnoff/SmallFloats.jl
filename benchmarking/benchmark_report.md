# Benchmark report

Generated: 2026-08-04 00:56 UTC  ·  Julia 1.12.6  ·  alderlake (32 logical CPUs, 8 Julia threads)  ·  Float128 paths: enabled  ·  Chairmarks 1.3.1

Source: SmallFloats.jl 0.4.0  ·  commit `ed6a0b7ba6cfdcc0452ac4c8fdab91522ba82fc0`  ·  tree dirty  ·  seed 2026

Reference format for per-operation tables: `Binary8p4se` under `(NearestTiesToEven, SatNone)`. Every table names its operand class: the scalar-operation tables appear in four variants — all code points (NaN and ±Inf sampled), NaN excluded, finite-only, and per-operation in-domain — and every other sampled table uses the all-code-points pool, identified in its note. Times are per call; minima first, medians alongside. Methodology per the recorded benchmark doctrine: type-parameterized barriers, untimed setup, specialization preflight.

## Core primitives

The decode/compare/step/classify layer plus the projection engine. Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `decode` | 1.4 ns | 1.4 ns | 0 |
| `order_key` | 1.4 ns | 1.6 ns | 0 |
| `x < y` | 1.6 ns | 1.6 ns | 0 |
| `TotalOrder` | 1.6 ns | 2.1 ns | 0 |
| `Class` | 1.2 ns | 2.1 ns | 0 |
| `NextGreaterThan` | 1.2 ns | 1.8 ns | 0 |
| `project (RNE·SatNone)` | 1.6 ns | 6.7 ns | 0 |
| `project (StochasticA[8], R drawn)` | 1.8 ns | 7.3 ns | 0 |

## Scalar operations

Each arity is measured under four operand classes — safe args, no NaN/Inf, no NaN, and all code points — so operand-class effects (NaN fast rows, ±Inf special rows) are separable.

```@raw latex
\clearpage
```

### Unary (30)

#### Safe args

Finite operands within each operation's safe domain — the fully unmasked per-operation scalar cost. The argument-restricted ops (Sqrt, RSqrt, Log, Log2, LogOnePlus, Recip, Divide, ArcSin, ArcCos, ArcCosh, ArcTanh) draw from explicit per-argument safe-domain predicates; every other op uses finite operand tuples whose defined result is not NaN (oracle-derived). Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Negate` | 4.8 ns | 6.9 ns | 0 |
| `Abs` | 4.4 ns | 7.1 ns | 0 |
| `Recip` | 7.9 ns | 18.2 ns | 0 |
| `Sqrt` | 4.9 ns | 18.7 ns | 0 |
| `Cosh` | 7.3 ns | 20.6 ns | 0 |
| `RSqrt` | 9.6 ns | 20.7 ns | 0 |
| `Sin` | 5.7 ns | 21.7 ns | 0 |
| `Cos` | 7.3 ns | 22.2 ns | 0 |
| `Exp2` | 7.3 ns | 22.3 ns | 0 |
| `Exp` | 7.2 ns | 22.5 ns | 0 |
| `ArcSin` | 6.0 ns | 23.1 ns | 0 |
| `Tanh` | 5.6 ns | 23.3 ns | 0 |
| `ExpMinusOne` | 5.7 ns | 23.4 ns | 0 |
| `ArcCos` | 5.6 ns | 24.4 ns | 0 |
| `ArcSinPi` | 5.3 ns | 25.6 ns | 0 |
| `Sinh` | 5.5 ns | 25.6 ns | 0 |
| `Log` | 5.7 ns | 25.8 ns | 0 |
| `Log2` | 6.0 ns | 26.6 ns | 0 |
| `LogOnePlus` | 5.5 ns | 26.7 ns | 0 |
| `Tan` | 5.7 ns | 26.8 ns | 0 |
| `ArcCosPi` | 5.4 ns | 26.8 ns | 0 |
| `CosPi` | 6.6 ns | 28.0 ns | 0 |
| `SinPi` | 6.0 ns | 28.1 ns | 0 |
| `ArcTan` | 4.9 ns | 28.4 ns | 0 |
| `ArcTanh` | 6.1 ns | 30.8 ns | 0 |
| `TanPi` | 6.3 ns | 31.1 ns | 0 |
| `ArcTanPi` | 5.3 ns | 31.1 ns | 0 |
| `ArcCosh` | 5.6 ns | 33.3 ns | 0 |
| `ArcSinh` | 5.3 ns | 33.3 ns | 0 |
| `Softplus` | 14.9 ns | 33.4 ns | 0 |

#### No NaN, Inf args

Operands exclude NaN and ±Inf; finite datums only (zeros and subnormals kept). Domain-restricted ops still take NaN fast rows on out-of-domain finite operands. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `ArcCosh` | 1.6 ns | 1.6 ns | 0 |
| `Log2` | 1.8 ns | 1.8 ns | 0 |
| `Sqrt` | 1.8 ns | 1.9 ns | 0 |
| `ArcSinPi` | 1.9 ns | 2.0 ns | 0 |
| `RSqrt` | 1.8 ns | 2.2 ns | 0 |
| `Log` | 1.9 ns | 5.5 ns | 0 |
| `Abs` | 4.7 ns | 6.7 ns | 0 |
| `Negate` | 4.6 ns | 6.8 ns | 0 |
| `ArcCosPi` | 1.8 ns | 7.5 ns | 0 |
| `ArcCos` | 1.9 ns | 16.3 ns | 0 |
| `ArcSin` | 1.8 ns | 17.2 ns | 0 |
| `Recip` | 1.8 ns | 17.9 ns | 0 |
| `Sin` | 4.7 ns | 21.6 ns | 0 |
| `Cos` | 7.1 ns | 21.6 ns | 0 |
| `Cosh` | 7.0 ns | 21.6 ns | 0 |
| `Exp2` | 7.0 ns | 22.2 ns | 0 |
| `Exp` | 7.0 ns | 22.3 ns | 0 |
| `Tanh` | 5.0 ns | 23.1 ns | 0 |
| `ExpMinusOne` | 5.3 ns | 23.3 ns | 0 |
| `Sinh` | 5.6 ns | 25.7 ns | 0 |
| `LogOnePlus` | 1.6 ns | 26.3 ns | 0 |
| `Tan` | 4.9 ns | 26.7 ns | 0 |
| `CosPi` | 6.5 ns | 27.8 ns | 0 |
| `SinPi` | 5.0 ns | 27.8 ns | 0 |
| `ArcTan` | 5.1 ns | 28.3 ns | 0 |
| `ArcTanh` | 1.9 ns | 28.8 ns | 0 |
| `TanPi` | 5.7 ns | 30.8 ns | 0 |
| `ArcTanPi` | 4.5 ns | 30.9 ns | 0 |
| `Softplus` | 14.5 ns | 33.5 ns | 0 |
| `ArcSinh` | 5.0 ns | 33.6 ns | 0 |

#### No NaN args

Operands exclude the NaN code point; ±Inf and every finite datum are sampled. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `ArcCosh` | 1.6 ns | 1.6 ns | 0 |
| `Sqrt` | 1.8 ns | 1.8 ns | 0 |
| `ArcTanh` | 1.9 ns | 1.9 ns | 0 |
| `ArcSin` | 1.8 ns | 2.0 ns | 0 |
| `Log` | 1.9 ns | 5.5 ns | 0 |
| `Abs` | 4.7 ns | 6.7 ns | 0 |
| `Negate` | 4.6 ns | 7.0 ns | 0 |
| `ArcSinPi` | 1.9 ns | 7.2 ns | 0 |
| `ArcCosPi` | 1.8 ns | 7.3 ns | 0 |
| `Log2` | 1.8 ns | 8.6 ns | 0 |
| `RSqrt` | 1.8 ns | 9.4 ns | 0 |
| `TanPi` | 1.8 ns | 12.3 ns | 0 |
| `Recip` | 1.8 ns | 17.9 ns | 0 |
| `Cos` | 1.5 ns | 21.7 ns | 0 |
| `Sin` | 2.0 ns | 21.7 ns | 0 |
| `Exp2` | 4.9 ns | 22.3 ns | 0 |
| `Exp` | 4.5 ns | 22.3 ns | 0 |
| `ExpMinusOne` | 5.2 ns | 22.9 ns | 0 |
| `Tanh` | 5.0 ns | 23.1 ns | 0 |
| `ArcCos` | 1.9 ns | 23.8 ns | 0 |
| `Cosh` | 5.2 ns | 25.0 ns | 0 |
| `Sinh` | 5.3 ns | 25.7 ns | 0 |
| `LogOnePlus` | 1.6 ns | 26.2 ns | 0 |
| `Tan` | 2.0 ns | 26.9 ns | 0 |
| `SinPi` | 1.6 ns | 27.8 ns | 0 |
| `CosPi` | 1.6 ns | 27.8 ns | 0 |
| `ArcTan` | 5.2 ns | 28.2 ns | 0 |
| `ArcTanPi` | 4.5 ns | 30.9 ns | 0 |
| `Softplus` | 5.0 ns | 33.5 ns | 0 |
| `ArcSinh` | 4.9 ns | 33.5 ns | 0 |

#### All code points

Operands drawn uniformly over ALL code points — NaN and ±Inf are sampled; medians of domain-restricted ops are diluted by instant NaN rows. Sorted by median. Transcendental rows mix special-row fast returns with enclosure-path evaluations, so these are *scalar-path* costs; bulk unary work routes through 256-byte tables (see Array kernels).

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `ArcCosh` | 1.6 ns | 1.6 ns | 0 |
| `Log2` | 1.8 ns | 5.9 ns | 0 |
| `Sqrt` | 1.8 ns | 6.2 ns | 0 |
| `Abs` | 1.9 ns | 6.7 ns | 0 |
| `Negate` | 1.8 ns | 6.9 ns | 0 |
| `RSqrt` | 1.8 ns | 9.4 ns | 0 |
| `ArcSin` | 1.6 ns | 17.1 ns | 0 |
| `Recip` | 1.8 ns | 18.1 ns | 0 |
| `Cosh` | 1.8 ns | 21.2 ns | 0 |
| `Cos` | 1.5 ns | 21.5 ns | 0 |
| `Sin` | 1.8 ns | 21.9 ns | 0 |
| `Exp2` | 1.6 ns | 22.2 ns | 0 |
| `Exp` | 1.8 ns | 22.3 ns | 0 |
| `ExpMinusOne` | 1.9 ns | 23.1 ns | 0 |
| `Tanh` | 1.9 ns | 23.4 ns | 0 |
| `ArcCos` | 1.9 ns | 23.9 ns | 0 |
| `ArcSinPi` | 1.8 ns | 24.3 ns | 0 |
| `Log` | 1.9 ns | 25.3 ns | 0 |
| `Sinh` | 1.8 ns | 25.7 ns | 0 |
| `LogOnePlus` | 1.6 ns | 26.4 ns | 0 |
| `Tan` | 1.8 ns | 26.4 ns | 0 |
| `ArcCosPi` | 1.8 ns | 26.6 ns | 0 |
| `CosPi` | 1.6 ns | 27.8 ns | 0 |
| `SinPi` | 1.4 ns | 27.8 ns | 0 |
| `ArcTan` | 1.8 ns | 28.2 ns | 0 |
| `ArcTanh` | 1.8 ns | 28.5 ns | 0 |
| `ArcTanPi` | 2.0 ns | 30.8 ns | 0 |
| `TanPi` | 1.7 ns | 30.8 ns | 0 |
| `Softplus` | 1.8 ns | 33.5 ns | 0 |
| `ArcSinh` | 1.8 ns | 33.6 ns | 0 |

```@raw latex
\clearpage
```

### Binary (18)

#### Safe args

Finite operands within each operation's safe domain — the fully unmasked per-operation scalar cost. The argument-restricted ops (Sqrt, RSqrt, Log, Log2, LogOnePlus, Recip, Divide, ArcSin, ArcCos, ArcCosh, ArcTanh) draw from explicit per-argument safe-domain predicates; every other op uses finite operand tuples whose defined result is not NaN (oracle-derived). Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `MinimumMagnitude` | 4.6 ns | 7.1 ns | 0 |
| `MaximumMagnitude` | 6.9 ns | 7.1 ns | 0 |
| `Maximum` | 4.6 ns | 7.2 ns | 0 |
| `Minimum` | 4.6 ns | 7.2 ns | 0 |
| `MaximumFinite` | 4.5 ns | 7.2 ns | 0 |
| `MinimumFinite` | 5.3 ns | 7.2 ns | 0 |
| `MaximumNumber` | 4.8 ns | 7.3 ns | 0 |
| `MinimumNumber` | 5.1 ns | 7.3 ns | 0 |
| `MaximumMagnitudeNumber` | 7.1 ns | 7.3 ns | 0 |
| `CopySign` | 4.6 ns | 7.3 ns | 0 |
| `MinimumMagnitudeNumber` | 5.3 ns | 7.3 ns | 0 |
| `Multiply` | 5.1 ns | 7.5 ns | 0 |
| `Add` | 6.8 ns | 9.0 ns | 0 |
| `Subtract` | 7.4 ns | 9.2 ns | 0 |
| `Divide` | 6.7 ns | 18.7 ns | 0 |
| `Hypot` | 7.7 ns | 28.0 ns | 0 |
| `ArcTan2` | 6.5 ns | 33.1 ns | 0 |
| `ArcTan2Pi` | 9.1 ns | 35.6 ns | 0 |

#### No NaN, Inf args

Operands exclude NaN and ±Inf; finite datums only (zeros and subnormals kept). Domain-restricted ops still take NaN fast rows on out-of-domain finite operands. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `CopySign` | 4.8 ns | 7.2 ns | 0 |
| `Maximum` | 4.7 ns | 7.2 ns | 0 |
| `Minimum` | 4.4 ns | 7.2 ns | 0 |
| `MinimumMagnitude` | 5.0 ns | 7.2 ns | 0 |
| `MaximumFinite` | 5.3 ns | 7.2 ns | 0 |
| `MaximumMagnitude` | 6.9 ns | 7.2 ns | 0 |
| `MinimumFinite` | 4.9 ns | 7.3 ns | 0 |
| `MaximumMagnitudeNumber` | 7.1 ns | 7.4 ns | 0 |
| `Multiply` | 5.2 ns | 7.4 ns | 0 |
| `MaximumNumber` | 5.1 ns | 7.4 ns | 0 |
| `MinimumNumber` | 4.9 ns | 7.5 ns | 0 |
| `MinimumMagnitudeNumber` | 4.7 ns | 7.6 ns | 0 |
| `Add` | 6.6 ns | 9.0 ns | 0 |
| `Subtract` | 7.5 ns | 9.3 ns | 0 |
| `Divide` | 2.5 ns | 18.4 ns | 0 |
| `Hypot` | 7.7 ns | 28.0 ns | 0 |
| `ArcTan2` | 6.8 ns | 33.1 ns | 0 |
| `ArcTan2Pi` | 4.2 ns | 35.9 ns | 0 |

#### No NaN args

Operands exclude the NaN code point; ±Inf and every finite datum are sampled. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `MaximumMagnitude` | 5.4 ns | 7.2 ns | 0 |
| `CopySign` | 4.8 ns | 7.2 ns | 0 |
| `Maximum` | 4.7 ns | 7.2 ns | 0 |
| `Minimum` | 4.8 ns | 7.2 ns | 0 |
| `MinimumNumber` | 4.8 ns | 7.3 ns | 0 |
| `MaximumNumber` | 4.9 ns | 7.3 ns | 0 |
| `MaximumFinite` | 5.6 ns | 7.4 ns | 0 |
| `Multiply` | 5.1 ns | 7.4 ns | 0 |
| `MinimumMagnitude` | 5.2 ns | 7.4 ns | 0 |
| `MinimumFinite` | 5.1 ns | 7.5 ns | 0 |
| `MaximumMagnitudeNumber` | 5.5 ns | 7.5 ns | 0 |
| `MinimumMagnitudeNumber` | 4.6 ns | 7.5 ns | 0 |
| `Add` | 6.5 ns | 9.1 ns | 0 |
| `Subtract` | 6.7 ns | 9.2 ns | 0 |
| `Divide` | 2.5 ns | 18.3 ns | 0 |
| `Hypot` | 5.2 ns | 28.0 ns | 0 |
| `ArcTan2` | 6.7 ns | 33.0 ns | 0 |
| `ArcTan2Pi` | 7.3 ns | 35.4 ns | 0 |

#### All code points

Operands drawn uniformly over ALL code points — NaN and ±Inf are sampled; medians of domain-restricted ops are diluted by instant NaN rows. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `MinimumMagnitude` | 1.8 ns | 7.1 ns | 0 |
| `MaximumMagnitude` | 1.9 ns | 7.2 ns | 0 |
| `Maximum` | 1.6 ns | 7.2 ns | 0 |
| `MaximumFinite` | 5.5 ns | 7.2 ns | 0 |
| `MinimumFinite` | 4.6 ns | 7.2 ns | 0 |
| `CopySign` | 1.8 ns | 7.3 ns | 0 |
| `Minimum` | 1.6 ns | 7.3 ns | 0 |
| `MinimumMagnitudeNumber` | 4.6 ns | 7.3 ns | 0 |
| `MinimumNumber` | 4.8 ns | 7.3 ns | 0 |
| `MaximumMagnitudeNumber` | 5.6 ns | 7.3 ns | 0 |
| `MaximumNumber` | 4.9 ns | 7.4 ns | 0 |
| `Multiply` | 1.6 ns | 7.5 ns | 0 |
| `Add` | 3.4 ns | 9.2 ns | 0 |
| `Subtract` | 4.0 ns | 9.4 ns | 0 |
| `Divide` | 2.2 ns | 17.9 ns | 0 |
| `Hypot` | 2.2 ns | 27.5 ns | 0 |
| `ArcTan2` | 3.0 ns | 33.0 ns | 0 |
| `ArcTan2Pi` | 3.4 ns | 35.5 ns | 0 |

### Ternary (3)

#### Safe args

Finite operands within each operation's safe domain — the fully unmasked per-operation scalar cost. The argument-restricted ops (Sqrt, RSqrt, Log, Log2, LogOnePlus, Recip, Divide, ArcSin, ArcCos, ArcCosh, ArcTanh) draw from explicit per-argument safe-domain predicates; every other op uses finite operand tuples whose defined result is not NaN (oracle-derived). Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Clamp` | 5.1 ns | 8.1 ns | 0 |
| `FMA` | 7.5 ns | 9.6 ns | 0 |
| `FAA` | 7.4 ns | 9.9 ns | 0 |

#### No NaN, Inf args

Operands exclude NaN and ±Inf; finite datums only (zeros and subnormals kept). Domain-restricted ops still take NaN fast rows on out-of-domain finite operands. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Clamp` | 5.1 ns | 8.1 ns | 0 |
| `FMA` | 8.2 ns | 9.6 ns | 0 |
| `FAA` | 7.5 ns | 9.7 ns | 0 |

#### No NaN args

Operands exclude the NaN code point; ±Inf and every finite datum are sampled. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Clamp` | 5.0 ns | 8.1 ns | 0 |
| `FMA` | 5.0 ns | 9.7 ns | 0 |
| `FAA` | 4.3 ns | 9.8 ns | 0 |

#### All code points

Operands drawn uniformly over ALL code points — NaN and ±Inf are sampled; medians of domain-restricted ops are diluted by instant NaN rows. Sorted by median.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Clamp` | 1.6 ns | 8.0 ns | 0 |
| `FMA` | 3.9 ns | 9.6 ns | 0 |
| `FAA` | 3.7 ns | 9.7 ns | 0 |

## Sensitivity studies

How the scalar costs move with the format and with the projection specification.

### Format sensitivity

Same three binary ops across formats; `Binary8p1uf` exercises the wide-exponent-spread escalations, small-K formats the tiny-table regime. Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Add⟨Binary8p4se⟩` | 3.4 ns | 9.0 ns | 0 |
| `Divide⟨Binary8p4se⟩` | 2.3 ns | 18.3 ns | 0 |
| `Multiply⟨Binary8p4se⟩` | 1.8 ns | 7.4 ns | 0 |
| `Add⟨Binary16p8se⟩` | 14.6 ns | 77.8 ns | 0 |
| `Divide⟨Binary16p8se⟩` | 11.0 ns | 24.5 ns | 0 |
| `Multiply⟨Binary16p8se⟩` | 9.5 ns | 13.2 ns | 0 |
| `Add⟨Binary16p5se⟩` | 136.6 ns | 698.3 ns | 34 |
| `Divide⟨Binary16p5se⟩` | 428.8 ns | 1.81 μs | 63 |
| `Multiply⟨Binary16p5se⟩` | 94.1 ns | 96.2 ns | 0 |
| `Add⟨Binary16p1uf⟩` | 17.1 ns | 21.8 ns | 0 |
| `Divide⟨Binary16p1uf⟩` | 1.5 μs | 1.61 μs | 81 |
| `Multiply⟨Binary16p1uf⟩` | 9.8 ns | 13.2 ns | 0 |
| `Add⟨Binary3p1se⟩` | 3.7 ns | 7.2 ns | 0 |
| `Divide⟨Binary3p1se⟩` | 2.5 ns | 6.7 ns | 0 |
| `Multiply⟨Binary3p1se⟩` | 1.8 ns | 6.2 ns | 0 |

### Projection by rounding/saturation mode

`project(Binary8p4se, ρ, x)` over the mode vocabulary (stochastic budgets N = 8). Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `NearestTiesToEven` | 1.6 ns | 6.6 ns | 0 |
| `NearestTiesToAway` | 2.6 ns | 7.6 ns | 0 |
| `TowardPositive` | 2.5 ns | 6.0 ns | 0 |
| `TowardNegative` | 2.5 ns | 6.0 ns | 0 |
| `TowardZero` | 2.3 ns | 5.3 ns | 0 |
| `ToOdd` | 1.8 ns | 6.6 ns | 0 |
| `StochasticA[8]` | 1.8 ns | 7.2 ns | 0 |
| `StochasticB[8]` | 1.8 ns | 7.2 ns | 0 |
| `StochasticC[8]` | 1.6 ns | 7.0 ns | 0 |
| `RNE · SatFinite` | 1.8 ns | 6.3 ns | 0 |
| `RNE · SatPropagate` | 1.8 ns | 6.4 ns | 0 |

## Kernels and storage

Array-shaped work: the table-gather and compute kernels, the ternary bitwidth policy, sorting, table builds, blocks, and packed/converted storage.

### Array kernels (vmap)

Warm caches: table specializations prebuilt, so table rows measure the gather; scalar-loop rows measure the full compute pipeline per element. The ternary row here is `Binary8p4se` (K=8, always the compute path); see the next section for how the ternary bitwidth policy behaves across K. Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs | per element |
|:---|:---|:---|:---|:---|
| `vmap unary (table gather), n=65536` | 8.32 μs | 8.68 μs | 0 | 0.13 ns/elem — 7.55 Gelem/s |
| `vmap binary (table gather), n=65536` | 16.35 μs | 16.67 μs | 0 | 0.25 ns/elem — 3.93 Gelem/s |
| `vmap ternary (scalar loop), n=65536` | 135.26 μs | 207.61 μs | 42 | 3.17 ns/elem — 0.32 Gelem/s |
| `vmap binary stochastic (scalar loop), n=65536` | 642.39 μs | 680.83 μs | 0 | 10.39 ns/elem — 0.1 Gelem/s |
| `vmap unary through PackedVector, n=65536` | 80.72 μs | 85.78 μs | 773 | 1.31 ns/elem — 0.76 Gelem/s |

### Ternary bitwidth tiers (FMA/FAA)

`FMA`/`FAA`/`Clamp` are total functions on `2^(K1+K2+K3)` code points, but that count spans 512 B (K=3) to 16 MiB (K=8), so the array kernel tables small operand formats eagerly, tables mid-size ones adaptively (after enough elements amortize the build; not shown here — see the adaptive-cache gate in `test/ternary_opt.jl`), and always runs the scalar compute kernel at K=8, threaded above a size cutoff when `Threads.nthreads() > 1`. Each tier's optimized row is paired with a scalar-loop baseline (policy Refs forced off around the measurement, restored after) so the win is visible per tier; this process has 8 Julia threads. Same reference format, ρ, and operand pool discipline as Array kernels above.

| operation | min | median | allocs | per element |
|:---|:---|:---|:---|:---|
| `FMA K=4 (eager table), n=65536` | 19.47 μs | 20.72 μs | 0 | 0.32 ns/elem — 3.16 Gelem/s |
| `FMA K=4 (eager table), scalar-loop baseline, n=65536` | 920.36 μs | 972.5 μs | 0 | 14.84 ns/elem — 0.07 Gelem/s |
| `FMA K=6 (eager table), n=65536` | 24.07 μs | 25.15 μs | 0 | 0.38 ns/elem — 2.61 Gelem/s |
| `FMA K=6 (eager table), scalar-loop baseline, n=65536` | 999.05 μs | 1.01 ms | 0 | 15.41 ns/elem — 0.06 Gelem/s |
| `FMA K=8 (compute), n=65536` | 131.64 μs | 209.46 μs | 42 | 3.2 ns/elem — 0.31 Gelem/s |
| `FMA K=8 (compute), scalar-loop baseline, n=65536` | 996.15 μs | 1.01 ms | 0 | 15.48 ns/elem — 0.06 Gelem/s |
| `FMA K=8 (compute), threaded [8t], n=65536` | 133.02 μs | 211.11 μs | 42 | 3.22 ns/elem — 0.31 Gelem/s |
| `FMA K=8 (compute), sequential [1t], n=65536` | 987.69 μs | 1.0 ms | 0 | 15.31 ns/elem — 0.07 Gelem/s |

### Sorting (64 K values)

Counting sort is installed as the default algorithm for `Binary` vectors. Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `sort! (counting sort via defalg), n=65536` | 159.58 μs | 161.56 μs | 2 |
| `sort! (stock comparison sort), n=65536` | 1.34 ms | 1.35 ms | 3 |
| `sort! rev=true (counting sort), n=65536` | 160.9 μs | 165.64 μs | 2 |

### Table builds (oracle + projection, Float128-first)

Cold cache per sample (`empty_tables!` in untimed setup); JIT pre-warmed. The warm-hit column is the steady-state cost of `get_table` when the specialization is already cached (min / median). Table entries enumerate every code point by construction (NaN and ±Inf included).

| operation | min | median | allocs | warm hit |
|:---|:---|:---|:---|:---|
| `Exp⟨8p4se⟩ (256 entries)` | 5.62 μs | 6.01 μs | 1 | 65.9 ns / 68.2 ns |
| `Tanh⟨8p4se⟩ (256 entries)` | 6.05 μs | 6.15 μs | 1 | 66.1 ns / 67.6 ns |
| `Add⟨8p4se×8p4se⟩ (64 K entries)` | 79.47 μs | 158.88 μs | 44 | 62.3 ns / 66.9 ns |
| `Divide⟨8p4se×8p4se⟩ (64 K)` | 131.26 μs | 143.89 μs | 44 | 65.4 ns / 67.3 ns |
| `Add⟨8p1uf×8p1uf⟩ (64 K, wide-spread)` | 2.57 ms | 3.83 ms | 536594 | 64.5 ns / 66.2 ns |

### Block and scaled operations

Elements `Binary8p4se`, scales `Binary8p1uf`, B = 32. Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs | per lane |
|:---|:---|:---|:---|:---|
| `BlockAdd (B=32)` | 964.9 ns | 1.03 μs | 35 | 32.28 ns/lane |
| `BlockDotProduct → 8p4se (B=32)` | 320.0 ns | 399.0 ns | 3 | 12.47 ns/lane |
| `BlockReduceAdd → 8p4se (B=32)` | 45.0 ns | 493.0 ns | 0 | 15.41 ns/lane |
| `ConvertToBlockMaxAbsFinite (B=32)` | 3.75 μs | 3.98 μs | 111 | 124.34 ns/lane |

### Conversions and packed storage

Operands: all code points — NaN and ±Inf sampled.

| operation | min | median | allocs | per element |
|:---|:---|:---|:---|:---|
| `T(::UInt8) code-point constructor` | 1.2 ns | 1.2 ns | 0 |  |
| `rawvalue (unchecked kernel route)` | 1.2 ns | 1.2 ns | 0 |  |
| `T(::Float64) numeric constructor (projects)` | 2.5 ns | 7.9 ns | 0 |  |
| `Convert 8p4se → 8p3se (scalar)` | 1.8 ns | 6.7 ns | 0 |  |
| `Float64 → 8p4se (project)` | 1.8 ns | 6.6 ns | 0 |  |
| `PackedVector pack, n=65536` | 32.45 μs | 34.75 μs | 3 | 0.53 ns/elem |
| `PackedVector unpack (collect), n=65536` | 28.86 μs | 29.04 μs | 3 | 0.44 ns/elem |

## Parallelism and allocation

The two properties the doctrine states in prose and this report previously left unmeasured.

### Threading

Both variants are warmed before either is measured, and the switch is a `Ref` read inside an already-compiled branch — not a second compilation, which is the harness failure the benchmark doctrine records. `Binary16p8se`'s binary table would be 2^32 entries, so `table_for` declines and the Shape-B compute kernel is the *only* array path that format has; that is what threading it buys. The build rows separate two different wins: `Multiply` is cheap per entry and was dominated by a per-entry dynamic dispatch (now fixed by the `_fill_*!` function barrier), while `Exp` is dominated by MPFR enclosure work and is where threading itself pays. This process has 8 Julia threads.

| operation | min | median | allocs |
|:---|:---|:---|:---|
| `Shape-B compute ⟨Binary16p8se⟩ Add, n=65536 — 8 threads` | 2.69 ms | 5.14 ms | 597767 |
| `Shape-B compute ⟨Binary16p8se⟩ Add, n=65536 — sequential` | 16.19 ms | 18.31 ms | 597725 |
| `build Exp⟨Binary16p8se⟩ (64 K entries) — 8 threads` | 14.57 ms | 16.63 ms | 1654196 |
| `build Multiply⟨Binary8p4se²⟩ (64 K entries) — 8 threads` | 64.46 μs | 132.86 μs | 44 |
| `build Exp⟨Binary16p8se⟩ (64 K entries) — sequential` | 74.51 ms | 77.37 ms | 1764746 |
| `build Multiply⟨Binary8p4se²⟩ (64 K entries) — sequential` | 445.35 μs | 451.85 μs | 2 |

### Allocation by rung

Warm-path bytes for one call of each operation class, per carrier rung. The **exact selections are zero at every rung, unconditionally** — a selection returns one of its operands, so there is nothing to escalate into, and a nonzero reading there is plumbing rather than arithmetic (this is the condition `preflight` aborts on). Arithmetic is *recorded, not gated*: it allocates exactly when the operand spread exceeds the carrier's exact range and evaluation escalates to MPFR, which happens at rung 1 too. The enclosure ladder allocates at rungs 2 and 3 by construction. Times are not meaningful for these calls and are omitted.

| format | rung | carrier | selection | add | fma | ladder |
|:---|:---|:---|:---|:---|:---|:---|
| `Binary8p4se` | 1 | `Float64` | 0 B | 0 B | 0 B | 0 B |
| `Binary16p8se` | 1 | `Float64` | 0 B | 0 B | 0 B | 0 B |
| `Binary16p5se` | 2 | `Float128` | 0 B | 0 B | 0 B | 2544 B |
| `Binary16p1uf` | 3 | `Dyadic` | 0 B | 0 B | 0 B | 2968 B |
| `Binary3p1se` | 1 | `Float64` | 0 B | 0 B | 0 B | 0 B |

---
*All numbers from this machine/run; absolute values vary by host. Regenerate with `julia --project=benchmarking -t auto benchmarking/benchmarking.jl`; the thread count matters for the Threading table and is recorded in the header above.*
