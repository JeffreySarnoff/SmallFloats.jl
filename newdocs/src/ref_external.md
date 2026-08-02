# External Reference

Docstrings for the documented **public** surface — the exported names. The full
export list is far larger (400+ names, including the 120 exported format aliases
— the other 384 are opt-in via `using SmallFloats.Formats` — the
predefined projection-spec grid, and the generated operation and block
registers); names without docstrings are covered descriptively in the
User Guide; unexported machinery is in the
Reference: Internal (docstrings) page.

The index below groups the exported surface by family and points each family
at the descriptive reference page that documents its full table. The
`@autodocs` block that follows renders the docstrings themselves,
alphabetically, as generated from source.

## Index

| Family | Scope | Descriptive reference page |
|---|---|---|
| Arrays, blocks, packed storage | `Op(fr,ρ,A,...)`, `vmap`/`vmap!`, `Block`, `BlockVector`, `PackedVector`, `table_bytes`, `empty_tables!` | Reference: Arrays, Blocks & Packed Storage |
| Conformance and approximation registry | `conformance`, `conformance_dict`, `conformance_report`, `draft_revision`, `measure_kappa`, `register_approx!`, `approx`, `kappa`, `kappa_measured`, `list_approx`, `unregister_approx!` | Reference: Conformance & Approximation Registry |
| Formats | 504 format aliases (120 exported at `K ≤ 8`), `format`, `formatname`, and the format-query accessors | Reference: Format Names & Queries |
| Operations | the 52-operation catalog: 30 unary, 18 binary, 3 ternary, `Convert` | Reference: Operation Catalog |
| Projection specs | `ProjSpec`, the 6×3 deterministic grid, the `RSA`/`RSB`/`RSC` stochastic constructors, `roundingmode`, `saturationmode`, `isstochastic`, `nrandbits` | Reference: Projection Specifications |
| Session defaults | `DefaultType`, `DefaultReturnType`, `DefaultRoundingMode`, `DefaultSaturationMode`, `DefaultProjection`, `DefaultRNG`, `DefaultRbits`, and their setters and `with_default_*` combinators | Reference: Session Defaults |

```@autodocs
Modules = [SmallFloats]
Private = false
```
