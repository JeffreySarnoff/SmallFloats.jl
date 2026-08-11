# Conformance and Approximation Registry

This page is the contract for exporting the live conformance declaration and
for measuring and registering optional approximate implementations. The
default operation API never substitutes a registered approximation.

## Conformance functions

| Function | Signature | Returns | Related guide |
|:---|:---|:---|:---|
| `conformance` | `conformance()` | the live declaration: formats, operations, mode vocabulary, table specializations instantiated this session, registered approximations | [Read and Export Conformance](workflow_conformance.md) |
| `conformance_dict` | `conformance_dict()` | a plain nested `Dict`, for JSON/TOML serialization | [Read and Export Conformance](workflow_conformance.md) |
| `conformance_report` | `conformance_report()` | prints the declaration | [Read and Export Conformance](workflow_conformance.md) |
| `draft_revision` | `draft_revision()` | the P3109 draft revision this package conforms to | [Read and Export Conformance](workflow_conformance.md) |
| `draft_identity` | `draft_identity()` | structured designation, upload date, retained source, and SHA-256 digest | [Read and Export Conformance](workflow_conformance.md) |

## κ registry

| Function | Signature | Returns | Related guide |
|:---|:---|:---|:---|
| `measure_kappa` | `measure_kappa(fn, op, fr, (argformats...), ρ)` | `(κ, exhaustive)` — measured max code-point deviation and whether the measurement was exhaustive | [Register an Approximation](workflow_approximation.md) |
| `register_approx!` | `register_approx!(name, op, fr, args, ρ, fn; κ)` | registers `fn` as approximation `name` for `op`, declaring bound `κ` | [Register an Approximation](workflow_approximation.md) |
| `approx` | `approx(name)` | the registered implementation object | [Register an Approximation](workflow_approximation.md) |
| `kappa` | `kappa(impl)` | the declared κ bound | [Register an Approximation](workflow_approximation.md) |
| `kappa_measured` | `kappa_measured(impl)` | the measured κ from registration | [Register an Approximation](workflow_approximation.md) |
| `list_approx` | `list_approx()` | all registered approximation names | [Register an Approximation](workflow_approximation.md) |
| `unregister_approx!` | `unregister_approx!(name)` | removes a registered approximation | [Register an Approximation](workflow_approximation.md) |

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

## See also

[Read and Export Conformance](workflow_conformance.md),
[Register an Approximation](workflow_approximation.md), and
[Verification Strategy](internals_verification.md).
