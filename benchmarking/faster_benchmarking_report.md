# SmallFloats fast benchmark report

This deadline-aware run samples representative work from the full suite. It favors breadth first and adds depth as the requested budget grows. Results are useful for rapid feedback; use `benchmarking.jl` for the exhaustive report.

- Requested runtime: `60.0 s`
- Observed runtime: `59.487 s` (from script entry through report preparation)
- Completed: `38 / 38` eligible cases (`38` in catalog)
- Measurement passes: `5` (`185` total case measurements)
- Initial per-case Chairmarks sampling slice: `100.0 ms`
- Seed: `2026`; Julia: `1.12.6`; threads: `1`
- Stop condition: deadline guard stopped during refinement pass 5

The runtime is approximate: Julia process startup precedes the timer, while package loading, compilation, data preparation, and measurement are included. An in-progress compilation or table build cannot be interrupted and can cause an overshoot.

## Core representation

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `decode` | 1.2 ns | 1.3 ns | 0 | 355 |  |
| `order_key` | 1.6 ns | 1.7 ns | 0 | 318 |  |

## Scalar operations

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `Add` | 7.4 ns | 9.4 ns | 0 | 188 | safe arguments |
| `Abs` | 6.6 ns | 6.8 ns | 0 | 204 | safe arguments |
| `Sqrt` | 5.3 ns | 19.1 ns | 0 | 255 | safe arguments |
| `Exp` | 13.6 ns | 22.6 ns | 0 | 191 | safe arguments |
| `Multiply` | 4.8 ns | 7.4 ns | 0 | 242 | safe arguments |
| `Divide` | 8.3 ns | 18.4 ns | 0 | 240 | safe arguments |
| `FMA` | 9.0 ns | 9.7 ns | 0 | 200 | safe arguments |
| `Log` | 5.7 ns | 25.8 ns | 0 | 182 | safe arguments |
| `Sin` | 5.2 ns | 21.7 ns | 0 | 224 | safe arguments |
| `Tanh` | 16.7 ns | 23.3 ns | 0 | 134 | safe arguments |
| `Minimum` | 7.2 ns | 7.2 ns | 0 | 201 | safe arguments |
| `ArcTan2` | 17.2 ns | 32.8 ns | 0 | 177 | safe arguments |

## Projection modes

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `NearestTiesToEven · SatNone` | 1.6 ns | 6.7 ns | 0 | 256 | deterministic |
| `StochasticA[8] · SatNone` | 4.8 ns | 7.4 ns | 0 | 201 | stochastic; random bits drawn |
| `NearestTiesToEven · SatFinite` | 6.2 ns | 6.4 ns | 0 | 233 | deterministic; finite saturation |

## Array kernels

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `vmap Exp (table gather)` | 2.2 μs | 2.26 μs | 0 | 1305 | n=16384; 0.14 ns/element; 7.26 Gelement/s |
| `vmap Add (table gather)` | 4.2 μs | 4.3 μs | 0 | 894 | n=16384; 0.26 ns/element; 3.81 Gelement/s |
| `vmap FMA (compute)` | 250.35 μs | 252.63 μs | 0 | 20 | n=16384; 15.42 ns/element; 0.06 Gelement/s |

## Sorting

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `counting sort` | 31.13 μs | 31.91 μs | 2 | 140 | n=16384; default algorithm |
| `comparison sort` | 411.87 μs | 415.63 μs | 3 | 12 | n=16384; stock comparison algorithm |

## Block operations

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `BlockDotProduct` | 211.8 ns | 1.24 μs | 66 | 71 | B=32; 38.66 ns/lane |
| `BlockReduceAdd` | 47.5 ns | 493.7 ns | 0 | 274 | B=32; 15.43 ns/lane |

## Conversions

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `numeric constructor` | 2.7 ns | 7.8 ns | 0 | 248 | Float64 → Binary8p4se |
| `PackedVector pack` | 8.13 μs | 8.48 μs | 3 | 525 | n=16384; 0.52 ns/element; 1.93 Gelement/s |
| `format conversion` | 1.9 ns | 6.9 ns | 0 | 243 | Binary8p4se → Binary8p3se |
| `PackedVector unpack` | 7.27 μs | 7.51 μs | 3 | 551 | n=16384; 0.46 ns/element; 2.18 Gelement/s |

## Function tables

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `Exp table` | 30.44 μs | 31.31 μs | 257 | 154 | cold build; 256 entries |
| `Add table` | 15.8 ms | 15.8 ms | 458754 | 1 | cold build; 65536 entries |

## Operand sensitivity

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `Add (all code points)` | 3.9 ns | 9.0 ns | 0 | 241 | all code points |
| `Sqrt (all code points)` | 1.8 ns | 1.8 ns | 0 | 386 | all code points |

## Format sensitivity

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `Add · Binary8p1uf` | 8.5 ns | 74.1 ns | 0 | 24 | all code points |

## Extended scalar coverage

| benchmark | min | median | allocs | samples | context |
|:---|---:|---:|---:|---:|:---|
| `Recip` | 7.9 ns | 18.3 ns | 0 | 1260 | safe arguments |
| `Log2` | 5.7 ns | 27.0 ns | 0 | 482 | safe arguments |
| `ArcSin` | 5.3 ns | 23.5 ns | 0 | 1215 | safe arguments |
| `MaximumMagnitude` | 7.0 ns | 7.3 ns | 0 | 1303 | safe arguments |
| `CopySign` | 4.7 ns | 7.3 ns | 0 | 1284 | safe arguments |
