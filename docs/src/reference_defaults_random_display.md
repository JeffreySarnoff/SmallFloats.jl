# Defaults, Randomness, and Display

This page collects the contracts for process defaults, random sources, and
display policy. For their scope and concurrency consequences, read
[Session State and Reproducibility](concept_session_state.md).

## Getter / setter table

Read with `DefaultX()`, set with `DefaultX!(v)`.

| Default | Initial value | Setter accepts | Related guide |
|:---|---|---|---|
| `DefaultType` | `Binary8p2se` | any fully-parameterized `Binary` type | Cheat Sheet |
| `DefaultReturnType` | `Binary8p2se` | any fully-parameterized `Binary` type | Cheat Sheet |
| `DefaultRoundingMode` | `NearestTiesToEven()` | mode instance or type | Cheat Sheet |
| `DefaultSaturationMode` | `SatNone()` | mode instance or type | Cheat Sheet |
| `DefaultProjection` | `RNE_SN` | a `ProjSpec`, or `(mode, sat)` | Cheat Sheet |
| `DefaultRNG` | the `Xoshiro` type | RNG type or instance | Cheat Sheet |
| `DefaultRbits` | `8` | `Int` in `1:60` | Cheat Sheet |

```julia
DefaultType()            # Binary8p2se     DefaultType!(Binary8p4se)
DefaultReturnType()      # Binary8p2se     DefaultReturnType!(Binary8p3se)
DefaultRoundingMode()    # NearestTiesToEven()
DefaultSaturationMode()  # SatNone()
DefaultProjection()      # RNE_SN
DefaultRNG()             # Xoshiro         DefaultRNG!(Xoshiro(42))
DefaultRbits()           # 8               DefaultRbits!(16)
```

## Coherence invariant

```julia
DefaultProjection() === ProjSpec(DefaultRoundingMode(), DefaultSaturationMode())
```

This holds at all times, in both directions:

| Action | Effect |
|:---|---|
| `DefaultRoundingMode!(mode)` | rebuilds `DefaultProjection` around the new mode, holding saturation fixed |
| `DefaultSaturationMode!(mode)` | rebuilds `DefaultProjection` around the new mode, holding rounding fixed |
| `DefaultProjection!(ρ)` | decomposes `ρ` back into both components |

There is no `DefaultAccumulatorType`: removed after v0.1.0. Reduction
accumulator carriers are picked by the span filter (provably exact for the
operands), not by a session preference.

## `with_default_*` combinators

| Combinator | Signature | Related guide |
|:---|---|---|
| `with_default_type` | `with_default_type(f, args...)` calls `f(DefaultType(), args...)` | Cheat Sheet |
| `with_default_returntype` | `with_default_returntype(f, args...)` calls `f(DefaultReturnType(), args...)` | Cheat Sheet |
| `with_default_projection` | `with_default_projection(f, args...)` calls `f(DefaultProjection(), args...)` | Cheat Sheet |

```julia
with_default_type((T, x) -> T(x), 1.5)          # Binary8p2se(1.5 ≡ 0x41)
with_default_projection((ρ, x, y) -> Add(T, ρ, x, y), x, y)
with_default_returntype(f, args...)              # f(DefaultReturnType(), args...)
```

Each combinator restores nothing itself — it only *reads* the default at call
time via `f(default, args...)`. For scoped mutate-and-restore, the same names
also support a do-block form that restores the prior value on exit, even if
the body throws.

## Cost model

- **Speculation guard.** Convenience forms (`x + y`, `Exp(x)`, `T(2.1)`) and
  the `with_default_*` combinators read the default through a speculation
  guard: allocation-free and concretely inferred while the default holds its
  initial value.
- **One barrier dispatch after a change.** Once a default is changed, each
  call crosses a function barrier: one dynamic dispatch at entry, everything
  inside still fully specialized.
- **Explicit forms are unaffected.** `Add(T, ρ, x, y)` with a `const` or
  argument-bound `ρ` never consults a session default and never pays this
  cost either way.
- **Boxing at escape.** When the combinator's result type *is* the default
  itself (`with_default_type` used as a constructor), the value computes on
  the specialized path but boxes once where it escapes the call — the
  irreducible cost of a runtime-chosen type. When the result type does not
  depend on the default, the call is zero-allocation with a concretely
  inferred result.

## Randomness

| Form | Entropy source | Projection control |
|:---|---|---|
| `rand(T)` | task-local RNG | default uniform projection |
| `rand(rng, T)` | explicit `rng` | default uniform projection |
| `rand(rng, T; projection = ρ)` | explicit `rng` | explicit `ρ` |
| `randn(rng, T)` | explicit `rng` | default normal projection |
| stochastic operation with `rng = rng` | explicit stream | selected stochastic `ProjSpec` |
| stochastic operation with `R = r` | exact raw draw | selected stochastic `ProjSpec` |

An explicit `R` must lie in `0:(2^N - 1)` for an `N`-bit stochastic mode.
Array `rand`/`randn` forms use their documented defaults; construct arrays from
scalar calls when each element must use another explicit projection.

## Display

`get_show_style()` returns the process-wide style and `set_show_style!(style)`
sets it. `VALID_SHOW_STYLES` contains four values:

| Style | Example rendering |
|:---|---|
| `:value` | `1.625` |
| `:codepoint` | `0x45` |
| `:datum` | `(1.625 ≡ 0x45)` |
| `:typed` | `Binary8p4se(1.625 ≡ 0x45)` |

An `IOContext` property, `:binary_show_style`, overrides the process default for
one stream. Prefer that form in concurrent code and in libraries that should
not change another caller's display.

## Related contracts

[First Session](first_session.md),
[Julia Numeric Behavior](concept_julia_numeric.md),
[Projection Specifications](reference_projections.md).
