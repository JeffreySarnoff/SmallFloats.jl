# Blocks: Exactness without Superaccumulators

`blockdecode` produces each lane's `scale × element` exactly (≤ 17-bit significands
in Float64). Reductions then apply **span filters**: one integer pass over lane
exponents decides whether the whole sum (or dot product, with ≤ 33-bit lane
products) is exactly representable in `Float128`; if so, a plain `Float128`
accumulation *is* the exact answer; if not, an exact big-float accumulation takes
over. Either way there is exactly one projection, at the end. `ωBlockProject`
follows the draft's special rows for the scale (NaN, 0, ±Inf) and divides each
element result by the scale through its own cheapest-first CR-bracket / enclosure
cascade (exact Float64 quotient → CR Float128 → bracket/pre-filter → MPFR
interval), mirroring the scalar quotient group's rigor arguments.

## see also

[The Oracle & Rigor Classes](under_oracle.md),
[Tables, Kernels & Sorting](under_tables.md),
[Add an Operation](howto_add_operation.md).
