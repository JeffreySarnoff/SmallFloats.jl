# Register an Approximation

Register a faster, inexact kernel in place of the bit-exact default, with an
honest, measured error bound.

## Ingredients

- `measure_kappa(fn, opname, resultformat, operandformats, ρ)` to measure the
  worst-case code-point deviation exhaustively.
- `register_approx!(name, opname, resultformat, operandformats, ρ, fn; κ)` to
  register the implementation under a declared bound.
- `approx`, `list_approx`, `kappa`, `kappa_measured` to retrieve and inspect
  registered approximations.
- `unregister_approx!` to remove one.

## Recipe

**1. Measure κ before declaring anything.** `measure_kappa` runs your
approximate function against the defined operation over every input and
returns the worst code-point distance, exhaustively verified:

```julia
step2(x) = (r = Exp(Binary8p4se, RNE_SN, x);
            isfinite(decode(r)) ? NextGreaterThan(NextGreaterThan(r)) : r)

measure_kappa(step2, :Exp, Binary8p4se, (Binary8p4se,), RNE_SN)
```

```
(2.0, true)                # κ = 2 code points, verified over all 256 inputs
```

**2. Register with the measured (or a larger) κ.** `register_approx!` takes
the same signature plus the implementation and a declared `κ`:

```julia
register_approx!(:cheater, :Exp, Binary8p4se, (Binary8p4se,), RNE_SN, step2; κ=1)
```

```
ERROR: ArgumentError: declared κ = 1.0 understates measured κ = 2.0 — registration rejected
```

Declaring `κ = 1` when the measured deviation is 2 is rejected outright — the
registry measures your honesty at registration time; you cannot understate
the bound.

**3. Register with a truthful κ and retrieve it.** Using `κ=1` failed above;
declaring the true value (or higher) succeeds. The same shape applied to a
hardware-style approximation (`hardtanh` standing in for `Tanh`) shows the
full round trip:

```julia
one4 = Binary8p4se(1.0)
hardtanh(x) = Clamp(Binary8p4se, RNE_SN, x, Negate(one4), one4)

κ, exhaustive = measure_kappa(hardtanh, :Tanh, Binary8p4se, (Binary8p4se,), RNE_SN)
(κ, exhaustive)
```

```
(4.0, true)                # worst deviation: 4 code points, verified on all 256 inputs
```

```julia
impl = register_approx!(:hardtanh_act, :Tanh, Binary8p4se, (Binary8p4se,),
                        RNE_SN, hardtanh; κ=4)
(kappa(:hardtanh_act), kappa_measured(impl), :hardtanh_act in list_approx())
```

```
(4.0, 4.0, true)           # declared = measured; conformance_report() now lists it
```

**4. Remove a registration when you're done with it.**

```julia
unregister_approx!(:hardtanh_act)
```

## What can go wrong

!!! warning "Understating κ is not silently clamped — it throws"
    You cannot register `:cheater` with `κ=1` "just to see" and get a warning;
    `register_approx!` throws `ArgumentError` and refuses the registration
    entirely. There is no partial-registration state to clean up.

!!! note "NaN-mismatching implementations need κ = NaN, not a number"
    If your approximate kernel disagrees with the defined operation on
    whether a NaN is produced, you must acknowledge this explicitly by
    declaring `κ = NaN` — a numeric κ asserts NaN behavior matches.

!!! note "Approximate implementations never enter the default API"
    Registering `:my_fast_exp` or `:hardtanh_act` does not change what `Exp`
    or `Tanh` return by default — the bit-exact path is always the one `Exp`,
    `+`, and friends use. Retrieve an approximation explicitly with
    `approx(:name)` and call it yourself; `list_approx()` enumerates what's
    registered, and `conformance_report()` lists them alongside the exact
    catalog.

## see also

[Read & Export the Conformance Declaration](workflow_conformance.md).
