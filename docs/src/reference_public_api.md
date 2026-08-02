# Public API Index

This index renders source docstrings for the public surface. Begin with the
curated family table: it states where each contract is maintained. The 120
format aliases at `K ≤ 8` are exported by `using SmallFloats`; the other 384
are opt-in through `SmallFloats.Formats` or available by qualification.

The index below groups the exported surface by family and points each family
at the descriptive reference page that documents its full table. The
`@autodocs` block that follows renders the docstrings themselves,
alphabetically, as generated from source.

## Index

| Family | Scope | Descriptive reference page |
|---|---|---|
| Arrays, blocks, packed storage | `Op(fr,ρ,A,...)`, `vmap`/`vmap!`, `Block`, `BlockVector`, `PackedVector`, `table_bytes`, `empty_tables!` | [Arrays, Blocks, and Packed Storage](reference_arrays_blocks_storage.md) |
| Conformance and approximation registry | `conformance`, `conformance_dict`, `conformance_report`, `draft_revision`, `measure_kappa`, `register_approx!`, `approx`, `kappa`, `kappa_measured`, `list_approx`, `unregister_approx!` | [Conformance and Approximation Registry](reference_conformance.md) |
| Formats | 504 aliases (120 exported at `K ≤ 8`), `format`, `formatname`, and format-query accessors | [Formats and Value Queries](reference_formats_values.md) |
| Operations | 30 unary, 18 binary, 3 ternary, and `Convert` | [Operation Catalog](reference_operations.md) |
| Projection specs | `ProjSpec`, deterministic grid, stochastic constructors, and accessors | [Projection Specifications](reference_projections.md) |
| Session state | defaults, RNG control, display styles, and scoped combinators | [Defaults, Randomness, and Display](reference_defaults_random_display.md) |
| Julia integration | Base overloads, promotion carriers, sorting, and conversion behavior | [Julia Compatibility Register](reference_julia_compat.md) |

```@autodocs
Modules = [SmallFloats]
Private = false
```
