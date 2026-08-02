# Session State and Reproducibility

Six values control what "the default" means for any convenience call in
SmallFloats.jl — the format `T(2.1)` produces, the projection `x + y`
follows, the RNG `rand(T)` draws from. This page explains what those six
defaults are, how they stay consistent with each other, why they are
dangerous to set casually, and the safe pattern for consuming them.

## The six defaults

Six session-wide defaults are readable as `DefaultX()` and settable as
`DefaultX!(v)`:

| default | initial value | setter accepts |
|---|---|---|
| `DefaultType` | `Binary8p2se` | any fully-parameterized `Binary` type |
| `DefaultReturnType` | `Binary8p2se` | any fully-parameterized `Binary` type |
| `DefaultRoundingMode` | `NearestTiesToEven()` | mode instance or type |
| `DefaultSaturationMode` | `SatNone()` | mode instance or type |
| `DefaultProjection` | `RNE_SN` | a `ProjSpec`, or `(mode, sat)` |
| `DefaultRNG` | the `Xoshiro` type | RNG type or instance |
| `DefaultRbits` | `8` | `Int` in `1:60` |

## Coherence in both directions

`DefaultProjection` and its two component defaults, `DefaultRoundingMode`
and `DefaultSaturationMode`, are kept coherent no matter which one you
change. Setting `DefaultRoundingMode!` or `DefaultSaturationMode!` rebuilds
`DefaultProjection` around the new component; setting `DefaultProjection!`
directly decomposes it back into both components. The invariant
`DefaultProjection() === ProjSpec(DefaultRoundingMode(), DefaultSaturationMode())`
holds always, regardless of which of the three setters you used last:

```julia-repl
julia> DefaultRoundingMode!(TowardZero())
TowardZero()

julia> DefaultProjection()               # followed the component
(TowardZero, SatNone)

julia> DefaultProjection!(RNA_SF)
(NearestTiesToAway, SatFinite)

julia> DefaultRoundingMode(), DefaultSaturationMode()   # followed the projection
(NearestTiesToAway(), SatFinite())

julia> DefaultProjection!(RNE_SN)        # restore: these setters are PROCESS-wide
(NearestTiesToEven, SatNone)
```

## The defaults are process-global

!!! warning "The session defaults are process-global and they stay set"
    `DefaultProjection!` and its siblings mutate state shared by every
    module in the process. Nothing scopes them for you: set one in a
    script, a notebook cell, or a REPL session and *every* later
    `T(x::Real)`, `a + b`, and `Exp(x)` follows it until something sets it
    back.

    Prefer `with_default_projection` (and `with_default_type`,
    `with_default_returntype`), which restore on exit even if the body
    throws:

    ```julia
    with_default_projection(RTZ_SF) do
        Binary8p4se(1e9)          # clamps, inside this block only
    end
    ```

    Every example in the manual assumes the pristine
    `(NearestTiesToEven, SatNone)`, which is why each demonstration that
    changes a default restores it explicitly afterward.

`DefaultProjection` is not merely advisory — `default_projspec` reads it, so
the same-format convenience methods (`a + b`, `Exp(x)`, …), the Base-register
operators, and `T(x::Real)` construction all follow it:

```julia-repl
julia> x, y = Binary8p4se(200.0), Binary8p4se(2.0);

julia> x * y                              # RNE_SN: overflow → +Inf
Binary8p4se(Inf ≡ 0x7f)

julia> DefaultProjection!(RTZ_SF);

julia> x * y                              # now clamps to MaxFinite
Binary8p4se(224.0 ≡ 0x7e)

julia> DefaultProjection!(RNE_SN)         # restore before moving on — see below
(NearestTiesToEven, SatNone)

julia> Multiply(Binary8p4se, RNE_SN, x, y)   # explicit ρ is unaffected
Binary8p4se(Inf ≡ 0x7f)
```

!!! warning "Changing the default is a global semantic change"
    Every caller of the convenience forms — including code in other
    packages — sees it. Library code that needs a specific projection
    should name it explicitly rather than rely on the session default.

## The `with_default_*` combinators

To *consume* a default in your own code without paying dynamic-dispatch
costs, go through the `with_default_*` combinators — `with_default_type`,
`with_default_returntype`, `with_default_projection` — which call
`f(default, args...)`:

```julia-repl
julia> with_default_type((T, x) -> T(x), 1.5)
Binary8p2se(1.5 ≡ 0x41)
```

### The speculation-guard cost model

Following the default costs nothing while it holds its initial value: the
convenience forms consume it through a speculation guard, the same
mechanism the `with_default_*` combinators use, so they compile against the
constant and stay allocation-free with concretely inferred results — this is
pinned in the test suite, not an incidental optimization. Once you change
the default, they cross a function barrier instead: one dynamic dispatch per
call, with everything inside that barrier still fully specialized. The
explicit forms, `Add(T, ρ, x, y)`, are unaffected either way — they never
read a default in the first place.

### Allocation contract

When `f`'s result type does not depend on the default — `with_default_projection`
with the formats fixed by the caller is the normal shape — the call is
zero-allocation with a concretely inferred result, pinned in the test suite.
When the result's type *is* the default (`with_default_type` used as a
constructor, where the returned value's type is whatever `DefaultType`
currently names), the value is still computed on the specialized path, but
it boxes once where it escapes the function barrier — the irreducible cost
of returning a runtime-chosen type.

## There is no accumulator default

!!! note "There is no accumulator default"
    `DefaultAccumulatorType` existed through v0.1.0 and was removed. The
    wide-precision accumulator used inside a reduction is not a matter of
    preference: the span filter measures the operands and picks the
    cheapest carrier that is *provably exact* for them, so the reduction
    returns the defined result regardless of which carrier that turns out
    to be. A knob overriding that choice would make `BlockDotProduct`
    inexact from the default API — a much larger cost than losing a
    configuration option. To trade speed for nothing else, set
    `ENV["SmallFloats_Float128"] = "disable"`, which is bit-identical by
    construction and only affects build/oracle speed.

## Go deeper

> Continue with **Projection: Rounding & Saturation** (Insights track)
> to see the default projection interact with explicit rounding and
> saturation choices across a full set of worked overflow examples.
