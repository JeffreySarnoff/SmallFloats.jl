# Glossary

Alphabetical, one or two lines per term, with links to the page where the term
is defined or used in full.

| Term | Definition | See |
|:---|:---|:---|
| Carrier | The concrete numeric type an exact intermediate or datum is held on during computation — `Float64` at rung 1, `Float128` at rung 2, or an exact dyadic carrier at rung 3, chosen by the format's exponent bias, never by the caller. | [Architecture and Invariants](internals_architecture.md); [Projection Engine](internals_projection_engine.md) |
| Code point | The `2^K`-valued integer identity of a value within its format — what a `Binary` value actually stores, in bijection with the format's datum set. | [Core Model](core_model.md) |
| Code unit | The storage word a format's code points are packed into — `UInt8` at `K ≤ 8`, `UInt16` above — returned by `codeunit_type(T)` and by `codepoint(x)`. | [Cheat Sheet](help_cheat_sheet.md), [Values, Code Points, and Conversion](concept_values_codepoints.md) |
| Datum | The exact mathematical value a code point denotes — a member of the closed extended reals (finite dyadic values, ±Inf, NaN). | [Core Model](core_model.md) |
| Datum carrier | The specific carrier type that is exact for a given format's datums, named by `datumcarrier(T)`; not to be confused with the promotion carrier used for mixed-type Base arithmetic. | [Projection Engine](internals_projection_engine.md) |
| Dyadic | An exact rational-like carrier, `S · 2^Q` with an `Int128` significand and `Int64` exponent, `isbits`, used at rung 3 where even `Float128` cannot hold a format's range or precision; converts to and from Julia's `Rational` exactly. | [Oracle and Rigor Classes](internals_oracle.md); [Standard and Design Notes](help_standard_design.md) |
| κ (kappa) | The maximum code-point distance, measured along the total order, between an approximate implementation's result and the defined result — measured by exhaustive enumeration at registration time, never declared unchecked. | [Oracle and Rigor Classes](internals_oracle.md); [Defined, Stochastic, and Approximate Results](concept_defined_stochastic_approximate.md) |
| Niven peel | The termination argument for π-scaled trigonometric operations: a finite set of exactly-representable cases split off ("peeled") before interval enclosure begins, with Niven's theorem proving the peel set is complete. | [Oracle and Rigor Classes](internals_oracle.md) |
| Omega-operation (ω) | The auxiliary, mathematically exact operation (`ωeval`) that a defined operation's result is the projection of — the thing that is computed *before* rounding and saturation ever see it. | [Oracle and Rigor Classes](internals_oracle.md) |
| Order key | An integer, sign-magnitude-folded encoding of a value used for comparisons and sorting — monotone with the total order, NaN mapped to key `0` (below every datum, per §4.12.1), enabling O(n) counting sort. | [Projection Engine](internals_projection_engine.md) |
| Projection | The single write path that produces every code point in the package: exact result → RoundToPrecision → Saturate → Encode. There is no second rounding routine anywhere in the package. | [Projection Engine](internals_projection_engine.md) |
| Projection specification (ProjSpec) | The pair `(rounding mode, saturation mode)` that parameterizes a projection, constructed as `ProjSpec(rounding, saturation)` or via a named constant like `RNE_SN`. | [Cheat Sheet](help_cheat_sheet.md), [Projection Specifications](reference_projections.md) |
| Promotion carrier | The ordinary Julia float type (`Float64` at rung 1, `BigFloat` at rung 2/3) that a `Binary` value promotes to when combined with an ordinary number — named by `promotecarrier(T)`; distinct from the datum carrier used internally. | [Standard and Design Notes](help_standard_design.md); [Julia Compatibility Register](reference_julia_compat.md) |
| Result kind | One of the five categories `ωeval` returns a computed result as (for example exact-`Float64`, exact-`Dyadic`, or an enclosure needing further work), which `apply_op` dispatches on to finish the projection. | [Oracle and Rigor Classes](internals_oracle.md) |
| Rigor class (R/E) | The two grades of justification for a non-`Float64` computed result: Class R (unconditional, provable without any accuracy assumption) and Class E (envelope-conditional, a faithful-but-not-correctly-rounded estimate validated by a measured slack). | [Architecture and Invariants](internals_architecture.md); [Oracle and Rigor Classes](internals_oracle.md) |
| Rounding mode | One of the six deterministic modes (`NearestTiesToEven`, `NearestTiesToAway`, `TowardPositive`, `TowardNegative`, `TowardZero`, `ToOdd`) or three stochastic variants (`RSA`, `RSB`, `RSC`) that make up half of a projection specification. | [Cheat Sheet](help_cheat_sheet.md), [Projection Specifications](reference_projections.md) |
| Rung | One of three carrier tiers a format is assigned to by its exponent bias: rung 1 (`Float64`, 432 formats), rung 2 (`Float128`, formats whose range needs more exponent room), rung 3 (exact dyadic carrier, formats whose range or precision breaks `Float128`). | [Architecture and Invariants](internals_architecture.md) |
| Saturation mode | One of three policies for out-of-range projection results: `SatFinite` (clamp to the finite range), `SatPropagate` (preserve representable infinities, clamp other overflow), `SatNone` (apply the draft's domain-, signedness-, and direction-dependent rows). | [Cheat Sheet](help_cheat_sheet.md), [Projection Specifications](reference_projections.md) |
| Saturation rows | The draft's twenty-row table mapping a rounded value's range classification to its final disposition (as-is, MaxFinite, MinFinite, ±Inf, NaN), consulted by the Saturate stage of projection. | [Projection Engine](internals_projection_engine.md) |
| Span filter | An integer pre-pass over lane exponents in a block reduction that proves a narrower carrier already covers every value the reduction can produce, licensing a faster accumulation path without loss of exactness. | [Exact Block Reductions](internals_blocks.md) |
| Sticky (symbolic) | A `sticky ∈ {-1, 0, +1}` argument to the projection engine meaning "the true value is the carrier value plus an infinitesimal of this sign" — how enclosure endpoints and asymptotes (`tanh → 1⁻`) project exactly without inventing a fake carrier value. | [Projection Engine](internals_projection_engine.md) |
| Table gather | The array-kernel strategy of computing a result by indexing a precomputed, cached lookup table (built once through the scalar path) rather than recomputing per element. | [Function Tables and Array Kernels](internals_tables.md) |
| Total order | The draft's total ordering over a format's value set, with the single NaN placed first, below −Inf (§4.12.1); the basis for `TotalOrder`, `isless`, comparisons, and counting sort. | [Projection Engine](internals_projection_engine.md) |

## See also

[Cheat Sheet](help_cheat_sheet.md),
[Troubleshooting](help_troubleshooting.md),
[Architecture and Invariants](internals_architecture.md).
