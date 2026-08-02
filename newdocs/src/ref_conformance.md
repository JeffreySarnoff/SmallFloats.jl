# Conformance & Approximation Registry

Dry listing of the conformance-declaration functions and the κ-approximation
registry. For narrative explanation, see the User Guide's Conformance and
κ-approximate implementations section.

## Conformance functions

| Function | Signature | Returns | Teaching page |
|---|---|---|---|
| `conformance` | `conformance()` | the live declaration: formats, operations, mode vocabulary, table specializations instantiated this session, registered approximations | User Guide |
| `conformance_dict` | `conformance_dict()` | a plain nested `Dict`, for JSON/TOML serialization | User Guide |
| `conformance_report` | `conformance_report()` | prints the declaration | User Guide |
| `draft_revision` | `draft_revision()` | the P3109 draft revision this package conforms to | User Guide |

## κ registry

| Function | Signature | Returns | Teaching page |
|---|---|---|---|
| `measure_kappa` | `measure_kappa(fn, op, fr, (argformats...), ρ)` | `(κ, exhaustive)` — measured max code-point deviation and whether the measurement was exhaustive | User Guide |
| `register_approx!` | `register_approx!(name, op, fr, args, ρ, fn; κ)` | registers `fn` as approximation `name` for `op`, declaring bound `κ` | User Guide |
| `approx` | `approx(name)` | the registered implementation object | User Guide |
| `kappa` | `kappa(impl)` | the declared κ bound | User Guide |
| `kappa_measured` | `kappa_measured(impl)` | the measured κ from registration | User Guide |
| `list_approx` | `list_approx()` | all registered approximation names | User Guide |
| `unregister_approx!` | `unregister_approx!(name)` | removes a registered approximation | User Guide |

```julia
κ, exhaustive = measure_kappa(fn, :Exp, T, (T,), ρ)
register_approx!(:fast_exp, :Exp, T, (T,), ρ, fn; κ)
impl = approx(:fast_exp)
kappa(impl)
kappa_measured(impl)
list_approx()
unregister_approx!(:fast_exp)
```

## Understatement-rejection rule

κ is measured exhaustively at registration time whenever the domain permits
exhaustive enumeration. Declaring a κ smaller than the measured deviation
throws — an implementation cannot register itself as more accurate than it
measures.

## κ = NaN acknowledgment rule

An implementation whose NaN behavior differs from the default API's (a NaN
mismatch against the exhaustive reference) must be registered with an
explicit `κ = NaN`. This is an acknowledgment, not a numeric bound: it cannot
be produced by measurement alone and must be supplied by the caller of
`register_approx!`.

Approximate implementations registered through this path are never
substituted into the default API; the default API is bit-exact, always.

## see also

[Read & Export the Conformance Declaration](howto_conformance.md),
[Package Verification & Benchmarking](under_verification.md).
