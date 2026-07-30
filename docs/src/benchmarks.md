# SmallFloats.jl benchmark report

Generated: 2026-07-30 06:40 UTC  ·  Julia 1.12.6  ·  alderlake (32 logical CPUs, 1 Julia thread)  ·  Float128 paths: enabled  ·  Chairmarks 1.3.1

Reference format for per-operation tables: `Binary8p4se` under `(NearestTiesToEven, SatNone)`. Every table names its operand class: the scalar-operation tables appear in four variants — all code points (NaN and ±Inf sampled), NaN excluded, finite-only, and per-operation in-domain — and every other sampled table uses the all-code-points pool, identified in its note. Times are per call; medians with minima alongside. Methodology per the recorded benchmark doctrine: type-parameterized barriers, untimed setup, specialization preflight.

## Core primitives

The decode/compare/step/classify layer plus the projection engine. Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs |
|---|---|---|---|
| `decode` | 1.2 ns | 1.2 ns | 0 |
| `order_key` | 1.6 ns | 1.4 ns | 0 |
| `x < y` | 1.6 ns | 1.4 ns | 0 |
| `TotalOrder` | 1.9 ns | 1.8 ns | 0 |
| `Class` | 2.1 ns | 1.4 ns | 0 |
| `NextGreaterThan` | 1.9 ns | 1.4 ns | 0 |
| `project (RNE·SatNone)` | 6.6 ns | 1.8 ns | 0 |
| `project (StochasticA[8], R drawn)` | 7.1 ns | 1.8 ns | 0 |

## Scalar operations

Each arity is measured under four operand classes — safe args, no NaN/Inf, no NaN, and all code points — so operand-class effects (NaN fast rows, ±Inf special rows) are separable.

```@raw latex
\clearpage
```

### Unary (30)

#### Safe args

Finite operands within each operation's safe domain — the fully unmasked per-operation scalar cost. The argument-restricted ops (Sqrt, RSqrt, Log, Log2, LogOnePlus, Recip, Divide, ArcSin, ArcCos, ArcCosh, ArcTanh) draw from explicit per-argument safe-domain predicates; every other op uses finite operand tuples whose defined result is not NaN (oracle-derived). Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `Abs` | 6.7 ns | 4.2 ns | 0 |
| `Negate` | 6.8 ns | 4.3 ns | 0 |
| `Recip` | 18.2 ns | 7.9 ns | 0 |
| `Sqrt` | 18.6 ns | 5.1 ns | 0 |
| `Cosh` | 20.7 ns | 7.3 ns | 0 |
| `RSqrt` | 20.7 ns | 9.6 ns | 0 |
| `Sin` | 21.7 ns | 5.5 ns | 0 |
| `Cos` | 21.7 ns | 7.3 ns | 0 |
| `Exp2` | 22.2 ns | 7.3 ns | 0 |
| `Exp` | 22.5 ns | 7.3 ns | 0 |
| `ArcSin` | 23.2 ns | 6.2 ns | 0 |
| `Tanh` | 23.2 ns | 5.5 ns | 0 |
| `ExpMinusOne` | 23.3 ns | 4.8 ns | 0 |
| `ArcCos` | 24.3 ns | 5.0 ns | 0 |
| `ArcSinPi` | 25.5 ns | 5.0 ns | 0 |
| `Sinh` | 25.6 ns | 5.5 ns | 0 |
| `Log` | 25.8 ns | 6.4 ns | 0 |
| `Log2` | 26.6 ns | 6.0 ns | 0 |
| `LogOnePlus` | 26.7 ns | 5.5 ns | 0 |
| `Tan` | 26.8 ns | 4.7 ns | 0 |
| `ArcCosPi` | 26.9 ns | 5.3 ns | 0 |
| `CosPi` | 27.9 ns | 6.6 ns | 0 |
| `SinPi` | 28.2 ns | 6.0 ns | 0 |
| `ArcTan` | 28.4 ns | 5.1 ns | 0 |
| `ArcTanh` | 31.0 ns | 5.8 ns | 0 |
| `TanPi` | 31.1 ns | 5.2 ns | 0 |
| `ArcTanPi` | 31.1 ns | 4.8 ns | 0 |
| `ArcCosh` | 33.2 ns | 5.1 ns | 0 |
| `ArcSinh` | 33.4 ns | 4.9 ns | 0 |
| `Softplus` | 33.5 ns | 14.5 ns | 0 |

#### No NaN, Inf args

Operands exclude NaN and ±Inf; finite datums only (zeros and subnormals kept). Domain-restricted ops still take NaN fast rows on out-of-domain finite operands. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `ArcCosh` | 1.6 ns | 1.6 ns | 0 |
| `Sqrt` | 1.6 ns | 1.6 ns | 0 |
| `ArcSinPi` | 2.0 ns | 1.9 ns | 0 |
| `ArcCos` | 3.3 ns | 1.9 ns | 0 |
| `ArcTanh` | 5.6 ns | 1.6 ns | 0 |
| `Abs` | 6.7 ns | 4.1 ns | 0 |
| `Negate` | 6.9 ns | 4.1 ns | 0 |
| `ArcCosPi` | 7.4 ns | 1.8 ns | 0 |
| `Log2` | 8.6 ns | 1.8 ns | 0 |
| `RSqrt` | 9.6 ns | 1.4 ns | 0 |
| `TanPi` | 13.9 ns | 4.9 ns | 0 |
| `Recip` | 18.0 ns | 1.8 ns | 0 |
| `Cos` | 21.5 ns | 7.1 ns | 0 |
| `Sin` | 21.7 ns | 5.0 ns | 0 |
| `Cosh` | 21.9 ns | 7.0 ns | 0 |
| `Exp2` | 22.2 ns | 7.1 ns | 0 |
| `Exp` | 22.3 ns | 7.0 ns | 0 |
| `ArcSin` | 22.9 ns | 1.8 ns | 0 |
| `ExpMinusOne` | 23.1 ns | 5.0 ns | 0 |
| `Tanh` | 23.2 ns | 4.7 ns | 0 |
| `Log` | 25.3 ns | 1.6 ns | 0 |
| `Sinh` | 25.6 ns | 4.5 ns | 0 |
| `LogOnePlus` | 26.2 ns | 1.4 ns | 0 |
| `Tan` | 26.8 ns | 4.7 ns | 0 |
| `CosPi` | 27.7 ns | 5.8 ns | 0 |
| `SinPi` | 27.7 ns | 4.8 ns | 0 |
| `ArcTan` | 28.2 ns | 5.0 ns | 0 |
| `ArcTanPi` | 30.8 ns | 4.5 ns | 0 |
| `Softplus` | 33.5 ns | 13.9 ns | 0 |
| `ArcSinh` | 33.6 ns | 4.8 ns | 0 |

#### No NaN args

Operands exclude the NaN code point; ±Inf and every finite datum are sampled. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `RSqrt` | 1.4 ns | 1.4 ns | 0 |
| `ArcCosh` | 1.6 ns | 1.6 ns | 0 |
| `ArcSinPi` | 2.0 ns | 1.9 ns | 0 |
| `ArcCos` | 2.1 ns | 1.9 ns | 0 |
| `Sqrt` | 4.6 ns | 1.6 ns | 0 |
| `Abs` | 6.7 ns | 4.1 ns | 0 |
| `Negate` | 6.9 ns | 4.2 ns | 0 |
| `Log2` | 8.6 ns | 1.8 ns | 0 |
| `Recip` | 18.0 ns | 1.8 ns | 0 |
| `Cos` | 21.5 ns | 1.8 ns | 0 |
| `Sin` | 21.5 ns | 1.9 ns | 0 |
| `Cosh` | 22.1 ns | 4.7 ns | 0 |
| `Exp2` | 22.2 ns | 4.3 ns | 0 |
| `Exp` | 22.3 ns | 4.3 ns | 0 |
| `ExpMinusOne` | 22.7 ns | 5.2 ns | 0 |
| `ArcSin` | 22.8 ns | 1.8 ns | 0 |
| `Tanh` | 23.1 ns | 4.8 ns | 0 |
| `Log` | 25.2 ns | 1.6 ns | 0 |
| `Sinh` | 25.7 ns | 5.1 ns | 0 |
| `LogOnePlus` | 26.3 ns | 1.4 ns | 0 |
| `ArcCosPi` | 26.7 ns | 1.8 ns | 0 |
| `Tan` | 26.7 ns | 2.0 ns | 0 |
| `CosPi` | 27.7 ns | 1.5 ns | 0 |
| `SinPi` | 27.7 ns | 1.6 ns | 0 |
| `ArcTan` | 28.2 ns | 4.9 ns | 0 |
| `ArcTanh` | 28.5 ns | 1.6 ns | 0 |
| `ArcTanPi` | 30.8 ns | 4.5 ns | 0 |
| `TanPi` | 30.8 ns | 1.8 ns | 0 |
| `Softplus` | 33.5 ns | 4.3 ns | 0 |
| `ArcSinh` | 33.9 ns | 4.8 ns | 0 |

#### All code points

Operands drawn uniformly over ALL code points — NaN and ±Inf are sampled; medians of domain-restricted ops are diluted by instant NaN rows. Sorted by median. Transcendental rows mix special-row fast returns with enclosure-path evaluations, so these are *scalar-path* costs; bulk unary work routes through 256-byte tables (see Array kernels).

| operation | median | min | allocs |
|---|---|---|---|
| `ArcCosh` | 1.6 ns | 1.4 ns | 0 |
| `Log2` | 1.8 ns | 1.8 ns | 0 |
| `ArcSinPi` | 2.1 ns | 1.8 ns | 0 |
| `ArcSin` | 5.3 ns | 1.8 ns | 0 |
| `Log` | 5.5 ns | 1.6 ns | 0 |
| `Abs` | 6.7 ns | 1.9 ns | 0 |
| `Negate` | 6.9 ns | 1.9 ns | 0 |
| `ArcCosPi` | 7.3 ns | 1.8 ns | 0 |
| `Sqrt` | 8.1 ns | 1.6 ns | 0 |
| `RSqrt` | 9.5 ns | 1.4 ns | 0 |
| `Recip` | 18.0 ns | 1.8 ns | 0 |
| `Cosh` | 21.2 ns | 1.8 ns | 0 |
| `Cos` | 21.5 ns | 1.8 ns | 0 |
| `Sin` | 21.5 ns | 1.8 ns | 0 |
| `Exp` | 22.2 ns | 1.8 ns | 0 |
| `Exp2` | 22.3 ns | 2.0 ns | 0 |
| `ExpMinusOne` | 22.8 ns | 1.9 ns | 0 |
| `Tanh` | 23.2 ns | 1.8 ns | 0 |
| `ArcCos` | 23.7 ns | 1.9 ns | 0 |
| `Sinh` | 25.6 ns | 2.0 ns | 0 |
| `LogOnePlus` | 26.3 ns | 1.4 ns | 0 |
| `Tan` | 26.5 ns | 1.8 ns | 0 |
| `CosPi` | 27.7 ns | 1.4 ns | 0 |
| `SinPi` | 27.8 ns | 1.6 ns | 0 |
| `ArcTan` | 28.1 ns | 1.8 ns | 0 |
| `ArcTanh` | 28.9 ns | 1.6 ns | 0 |
| `TanPi` | 30.8 ns | 1.6 ns | 0 |
| `ArcTanPi` | 30.8 ns | 1.6 ns | 0 |
| `Softplus` | 33.5 ns | 1.8 ns | 0 |
| `ArcSinh` | 33.8 ns | 2.0 ns | 0 |

```@raw latex
\clearpage
```

### Binary (18)

#### Safe args

Finite operands within each operation's safe domain — the fully unmasked per-operation scalar cost. The argument-restricted ops (Sqrt, RSqrt, Log, Log2, LogOnePlus, Recip, Divide, ArcSin, ArcCos, ArcCosh, ArcTanh) draw from explicit per-argument safe-domain predicates; every other op uses finite operand tuples whose defined result is not NaN (oracle-derived). Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `MinimumMagnitude` | 7.1 ns | 4.6 ns | 0 |
| `MaximumMagnitude` | 7.1 ns | 7.0 ns | 0 |
| `CopySign` | 7.2 ns | 4.3 ns | 0 |
| `Maximum` | 7.2 ns | 4.6 ns | 0 |
| `Minimum` | 7.2 ns | 4.3 ns | 0 |
| `MinimumFinite` | 7.2 ns | 4.7 ns | 0 |
| `MaximumFinite` | 7.3 ns | 4.5 ns | 0 |
| `MaximumNumber` | 7.3 ns | 4.6 ns | 0 |
| `MinimumNumber` | 7.3 ns | 4.4 ns | 0 |
| `MaximumMagnitudeNumber` | 7.3 ns | 7.1 ns | 0 |
| `MinimumMagnitudeNumber` | 7.3 ns | 4.7 ns | 0 |
| `Multiply` | 7.4 ns | 4.6 ns | 0 |
| `Add` | 9.0 ns | 8.1 ns | 0 |
| `Subtract` | 9.3 ns | 7.2 ns | 0 |
| `Divide` | 18.4 ns | 5.9 ns | 0 |
| `Hypot` | 28.1 ns | 7.8 ns | 0 |
| `ArcTan2` | 32.8 ns | 7.0 ns | 0 |
| `ArcTan2Pi` | 35.4 ns | 6.8 ns | 0 |

#### No NaN, Inf args

Operands exclude NaN and ±Inf; finite datums only (zeros and subnormals kept). Domain-restricted ops still take NaN fast rows on out-of-domain finite operands. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `CopySign` | 7.2 ns | 4.6 ns | 0 |
| `MinimumMagnitude` | 7.2 ns | 4.7 ns | 0 |
| `Minimum` | 7.2 ns | 4.7 ns | 0 |
| `MaximumMagnitude` | 7.2 ns | 6.9 ns | 0 |
| `MaximumFinite` | 7.2 ns | 4.8 ns | 0 |
| `MinimumFinite` | 7.3 ns | 4.9 ns | 0 |
| `Maximum` | 7.3 ns | 4.4 ns | 0 |
| `MaximumNumber` | 7.3 ns | 4.7 ns | 0 |
| `MaximumMagnitudeNumber` | 7.3 ns | 7.1 ns | 0 |
| `MinimumNumber` | 7.3 ns | 4.4 ns | 0 |
| `MinimumMagnitudeNumber` | 7.3 ns | 4.5 ns | 0 |
| `Multiply` | 7.4 ns | 4.9 ns | 0 |
| `Add` | 9.0 ns | 7.8 ns | 0 |
| `Subtract` | 9.3 ns | 7.4 ns | 0 |
| `Divide` | 18.3 ns | 2.3 ns | 0 |
| `Hypot` | 28.0 ns | 7.8 ns | 0 |
| `ArcTan2` | 32.7 ns | 6.7 ns | 0 |
| `ArcTan2Pi` | 35.4 ns | 7.6 ns | 0 |

#### No NaN args

Operands exclude the NaN code point; ±Inf and every finite datum are sampled. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `CopySign` | 7.2 ns | 4.5 ns | 0 |
| `MinimumFinite` | 7.2 ns | 4.8 ns | 0 |
| `MaximumFinite` | 7.2 ns | 4.4 ns | 0 |
| `Minimum` | 7.3 ns | 4.7 ns | 0 |
| `Maximum` | 7.3 ns | 4.4 ns | 0 |
| `MaximumNumber` | 7.4 ns | 4.5 ns | 0 |
| `MinimumMagnitude` | 7.4 ns | 4.7 ns | 0 |
| `MinimumNumber` | 7.4 ns | 4.8 ns | 0 |
| `MinimumMagnitudeNumber` | 7.4 ns | 5.0 ns | 0 |
| `Multiply` | 7.5 ns | 4.9 ns | 0 |
| `MaximumMagnitude` | 7.5 ns | 5.0 ns | 0 |
| `MaximumMagnitudeNumber` | 7.6 ns | 5.2 ns | 0 |
| `Add` | 9.1 ns | 4.1 ns | 0 |
| `Subtract` | 9.4 ns | 6.9 ns | 0 |
| `Divide` | 18.3 ns | 2.3 ns | 0 |
| `Hypot` | 28.0 ns | 5.3 ns | 0 |
| `ArcTan2` | 32.7 ns | 6.0 ns | 0 |
| `ArcTan2Pi` | 35.3 ns | 6.5 ns | 0 |

#### All code points

Operands drawn uniformly over ALL code points — NaN and ±Inf are sampled; medians of domain-restricted ops are diluted by instant NaN rows. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `MinimumMagnitude` | 7.1 ns | 1.6 ns | 0 |
| `MaximumMagnitude` | 7.2 ns | 1.6 ns | 0 |
| `CopySign` | 7.2 ns | 1.8 ns | 0 |
| `Maximum` | 7.2 ns | 1.8 ns | 0 |
| `Minimum` | 7.2 ns | 1.4 ns | 0 |
| `MinimumFinite` | 7.2 ns | 4.8 ns | 0 |
| `MaximumFinite` | 7.2 ns | 4.4 ns | 0 |
| `MaximumNumber` | 7.3 ns | 4.5 ns | 0 |
| `MinimumNumber` | 7.3 ns | 4.4 ns | 0 |
| `MaximumMagnitudeNumber` | 7.3 ns | 5.1 ns | 0 |
| `MinimumMagnitudeNumber` | 7.3 ns | 4.7 ns | 0 |
| `Multiply` | 7.4 ns | 1.8 ns | 0 |
| `Add` | 9.0 ns | 3.9 ns | 0 |
| `Subtract` | 9.2 ns | 4.0 ns | 0 |
| `Divide` | 18.3 ns | 2.3 ns | 0 |
| `Hypot` | 28.0 ns | 2.3 ns | 0 |
| `ArcTan2` | 32.7 ns | 3.9 ns | 0 |
| `ArcTan2Pi` | 35.2 ns | 3.6 ns | 0 |

### Ternary (3)

#### Safe args

Finite operands within each operation's safe domain — the fully unmasked per-operation scalar cost. The argument-restricted ops (Sqrt, RSqrt, Log, Log2, LogOnePlus, Recip, Divide, ArcSin, ArcCos, ArcCosh, ArcTanh) draw from explicit per-argument safe-domain predicates; every other op uses finite operand tuples whose defined result is not NaN (oracle-derived). Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `Clamp` | 8.0 ns | 4.8 ns | 0 |
| `FMA` | 9.7 ns | 8.0 ns | 0 |
| `FAA` | 9.7 ns | 7.5 ns | 0 |

#### No NaN, Inf args

Operands exclude NaN and ±Inf; finite datums only (zeros and subnormals kept). Domain-restricted ops still take NaN fast rows on out-of-domain finite operands. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `Clamp` | 8.0 ns | 4.7 ns | 0 |
| `FMA` | 9.6 ns | 7.1 ns | 0 |
| `FAA` | 9.7 ns | 8.2 ns | 0 |

#### No NaN args

Operands exclude the NaN code point; ±Inf and every finite datum are sampled. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `Clamp` | 8.0 ns | 4.8 ns | 0 |
| `FMA` | 9.6 ns | 4.3 ns | 0 |
| `FAA` | 9.7 ns | 4.4 ns | 0 |

#### All code points

Operands drawn uniformly over ALL code points — NaN and ±Inf are sampled; medians of domain-restricted ops are diluted by instant NaN rows. Sorted by median.

| operation | median | min | allocs |
|---|---|---|---|
| `Clamp` | 8.0 ns | 1.6 ns | 0 |
| `FMA` | 9.6 ns | 3.7 ns | 0 |
| `FAA` | 9.8 ns | 3.7 ns | 0 |

## Sensitivity studies

How the scalar costs move with the format and with the projection specification.

### Format sensitivity

Same three binary ops across formats; `Binary8p1uf` exercises the wide-exponent-spread escalations, small-K formats the tiny-table regime. Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs |
|---|---|---|---|
| `Add⟨Binary8p4se⟩` | 9.0 ns | 3.9 ns | 0 |
| `Divide⟨Binary8p4se⟩` | 18.3 ns | 2.3 ns | 0 |
| `Multiply⟨Binary8p4se⟩` | 7.4 ns | 1.8 ns | 0 |
| `Add⟨Binary8p3sf⟩` | 8.7 ns | 3.7 ns | 0 |
| `Divide⟨Binary8p3sf⟩` | 16.4 ns | 2.5 ns | 0 |
| `Multiply⟨Binary8p3sf⟩` | 6.9 ns | 1.6 ns | 0 |
| `Add⟨Binary8p1uf⟩` | 152.3 ns | 152.3 ns | 0 |
| `Divide⟨Binary8p1uf⟩` | 8.4 ns | 2.1 ns | 0 |
| `Multiply⟨Binary8p1uf⟩` | 6.8 ns | 1.8 ns | 0 |
| `Add⟨Binary5p2se⟩` | 9.0 ns | 3.5 ns | 0 |
| `Divide⟨Binary5p2se⟩` | 9.1 ns | 2.3 ns | 0 |
| `Multiply⟨Binary5p2se⟩` | 7.4 ns | 1.6 ns | 0 |
| `Add⟨Binary3p1se⟩` | 7.2 ns | 3.5 ns | 0 |
| `Divide⟨Binary3p1se⟩` | 5.8 ns | 2.3 ns | 0 |
| `Multiply⟨Binary3p1se⟩` | 5.8 ns | 1.4 ns | 0 |

### Projection by rounding/saturation mode

`project(Binary8p4se, ρ, x)` over the mode vocabulary (stochastic budgets N = 8). Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs |
|---|---|---|---|
| `NearestTiesToEven` | 6.6 ns | 1.8 ns | 0 |
| `NearestTiesToAway` | 7.7 ns | 2.1 ns | 0 |
| `TowardPositive` | 5.9 ns | 2.5 ns | 0 |
| `TowardNegative` | 5.9 ns | 2.3 ns | 0 |
| `TowardZero` | 5.3 ns | 2.1 ns | 0 |
| `ToOdd` | 6.6 ns | 1.6 ns | 0 |
| `StochasticA[8]` | 7.0 ns | 1.8 ns | 0 |
| `StochasticB[8]` | 7.1 ns | 1.8 ns | 0 |
| `StochasticC[8]` | 7.1 ns | 1.8 ns | 0 |
| `RNE · SatFinite` | 6.9 ns | 1.8 ns | 0 |
| `RNE · SatPropagate` | 6.7 ns | 1.6 ns | 0 |

## Kernels and storage

Array-shaped work: the table-gather and compute kernels, the ternary bitwidth policy, sorting, table builds, blocks, and packed/converted storage.

### Array kernels (vmap)

Warm caches: table specializations prebuilt, so table rows measure the gather; scalar-loop rows measure the full compute pipeline per element. The ternary row here is `Binary8p4se` (K=8, always the compute path); see the next section for how the ternary bitwidth policy behaves across K. Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs | per element |
|---|---|---|---|---|
| `vmap unary (table gather), n=65536` | 8.71 μs | 8.59 μs | 0 | 0.13 ns/elem — 7.53 Gelem/s |
| `vmap binary (table gather), n=65536` | 16.77 μs | 16.45 μs | 0 | 0.26 ns/elem — 3.91 Gelem/s |
| `vmap ternary (scalar loop), n=65536` | 1.02 ms | 1.02 ms | 0 | 15.63 ns/elem — 0.06 Gelem/s |
| `vmap binary stochastic (scalar loop), n=65536` | 651.8 μs | 646.03 μs | 0 | 9.95 ns/elem — 0.1 Gelem/s |
| `vmap unary through PackedVector, n=65536` | 79.88 μs | 78.1 μs | 773 | 1.22 ns/elem — 0.82 Gelem/s |

### Ternary bitwidth tiers (FMA/FAA)

`FMA`/`FAA`/`Clamp` are total functions on `2^(K1+K2+K3)` code points, but that count spans 512 B (K=3) to 16 MiB (K=8), so the array kernel tables small operand formats eagerly, tables mid-size ones adaptively (after enough elements amortize the build; not shown here — see the adaptive-cache gate in `test/ternary_opt.jl`), and always runs the scalar compute kernel at K=8, threaded above a size cutoff when `Threads.nthreads() > 1`. Each tier's optimized row is paired with a scalar-loop baseline (policy Refs forced off around the measurement, restored after) so the win is visible per tier; this process has 1 Julia thread. No threaded/sequential comparison below — rerun with `julia -t N` (N > 1) to see it. Same reference format, ρ, and operand pool discipline as Array kernels above.

| operation | median | min | allocs | per element |
|---|---|---|---|---|
| `FMA K=4 (eager table), n=65536` | 20.45 μs | 19.49 μs | 0 | 0.31 ns/elem — 3.2 Gelem/s |
| `FMA K=4 (eager table), scalar-loop baseline, n=65536` | 970.07 μs | 961.16 μs | 0 | 14.8 ns/elem — 0.07 Gelem/s |
| `FMA K=6 (eager table), n=65536` | 24.31 μs | 24.0 μs | 0 | 0.37 ns/elem — 2.7 Gelem/s |
| `FMA K=6 (eager table), scalar-loop baseline, n=65536` | 1.01 ms | 1.0 ms | 0 | 15.45 ns/elem — 0.06 Gelem/s |
| `FMA K=8 (compute), n=65536` | 1.0 ms | 992.7 μs | 0 | 15.31 ns/elem — 0.07 Gelem/s |
| `FMA K=8 (compute), scalar-loop baseline, n=65536` | 1.0 ms | 994.08 μs | 0 | 15.31 ns/elem — 0.07 Gelem/s |

### Sorting (64 K values)

Counting sort is installed as the default algorithm for `Binary` vectors. Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs |
|---|---|---|---|
| `sort! (counting sort via defalg), n=65536` | 160.92 μs | 158.28 μs | 2 |
| `sort! (stock comparison sort), n=65536` | 1.26 ms | 1.24 ms | 3 |
| `sort! rev=true (counting sort), n=65536` | 160.42 μs | 157.39 μs | 2 |

### Table builds (oracle + projection, Float128-first)

Cold cache per sample (`empty_tables!` in untimed setup); JIT pre-warmed. The warm-hit column is the steady-state cost of `get_table` when the specialization is already cached (median / min). Table entries enumerate every code point by construction (NaN and ±Inf included).

| operation | median | min | allocs | warm hit |
|---|---|---|---|---|
| `Exp⟨8p4se⟩ (256 entries)` | 30.42 μs | 29.51 μs | 257 | 67.4 ns / 65.8 ns |
| `Tanh⟨8p4se⟩ (256 entries)` | 32.01 μs | 31.13 μs | 257 | 67.3 ns / 65.7 ns |
| `Add⟨8p4se×8p4se⟩ (64 K entries)` | 14.3 ms | 14.12 ms | 458754 | 68.0 ns / 66.8 ns |
| `Divide⟨8p4se×8p4se⟩ (64 K)` | 14.62 ms | 14.4 ms | 458754 | 68.1 ns / 67.0 ns |
| `Add⟨8p1uf×8p1uf⟩ (64 K, wide-spread)` | 29.98 ms | 27.44 ms | 995304 | 67.8 ns / 66.7 ns |

### Block and scaled operations

Elements `Binary8p4se`, scales `Binary8p1uf`, B = 32. Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs | per lane |
|---|---|---|---|---|
| `BlockAdd (B=32)` | 1.08 μs | 1.02 μs | 35 | 33.88 ns/lane |
| `BlockDotProduct → 8p4se (B=32)` | 251.4 ns | 210.1 ns | 3 | 7.86 ns/lane |
| `BlockReduceAdd → 8p4se (B=32)` | 491.3 ns | 44.4 ns | 0 | 15.35 ns/lane |
| `ConvertToBlockMaxAbsFinite (B=32)` | 4.01 μs | 3.85 μs | 111 | 125.31 ns/lane |

### Conversions and packed storage

Operands: all code points — NaN and ±Inf sampled.

| operation | median | min | allocs | per element |
|---|---|---|---|---|
| `T(::UInt8) code-point constructor` | 1.4 ns | 1.4 ns | 0 |  |
| `rawvalue (unchecked kernel route)` | 1.2 ns | 1.2 ns | 0 |  |
| `T(::Float64) numeric constructor (projects)` | 7.8 ns | 2.5 ns | 0 |  |
| `Convert 8p4se → 8p3se (scalar)` | 6.8 ns | 1.6 ns | 0 |  |
| `Float64 → 8p4se (project)` | 6.6 ns | 1.9 ns | 0 |  |
| `PackedVector pack, n=65536` | 36.29 μs | 32.81 μs | 3 | 0.55 ns/elem |
| `PackedVector unpack (collect), n=65536` | 29.01 μs | 28.87 μs | 3 | 0.44 ns/elem |

---
*All numbers from this machine/run; absolute values vary by host. Regenerate with `julia --project=benchmark benchmark/benchmarking.jl`.*
