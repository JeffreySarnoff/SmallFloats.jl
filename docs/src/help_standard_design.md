# Standard and Design Notes

An index to the curated `docs/other/` collection: the standard's concept map,
the design rationales behind specific implementation choices, and the working
papers that planned the K > 8 extension. Each entry carries a status label —
read it before treating a document as current.

## Designing to the Draft Standard

**P3109 Draft Notes** — [`IEEE_D1_concepts.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/IEEE_D1_concepts.md).
A concept map of the whole IEEE P3109/D1 draft (July 2026): format-defining
parameters, value space, operation machinery, and projection, with every node
linked back to the draft's line numbers. Status: normative-description.

The full draft transliteration, `IEEE_D1.md`, is repo-only and is not part of
this curated set — it is linked out from the concept map and from the working
papers below (see Decision D1). Find it at
[`IEEE_D1.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/IEEE_D1.md) in the repository.

## Design Rationales

**dyadic_rational.md** — [`dyadic_rational.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/dyadic_rational.md).
The `Dyadic` ↔ `Rational` bridge: how the rung-3 exact carrier converts to and
from Julia's `Rational` exactly, and the three laws that conversion must obey
(round-trip on every finite dyadic, ±∞ agreement with Base's `1//0`, and
rejection only at the true NaN slot). Status: design-rationale.

**promoterules.md** — [`promoterules.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/promoterules.md).
Works out why `promote_rule` between two P3109 formats cannot mean "widen to
a bigger format" the way `Int`/`Float64` promotion does, and what the
promotion carrier is instead. Status: design-rationale, partially superseded
by the promotion-carrier section in the Cheat Sheet and Julia Compatibility
guide — those pages reflect the shipped `promotecarrier(T)` behavior, and this
document should be read as the reasoning behind it rather than as the current
API description.

**Float32inside.md** — [`Float32inside.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/Float32inside.md).
A design study asking whether `Float32` can replace `Float64` as the internal
carrier; verdict is no as a universal replacement, yes as a surface type and
as a gated compute carrier for specific kernels. Status: exploratory.

**Float32more.md** — [`Float32more.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/Float32more.md).
Companion to Float32inside.md: a detailed, empirically validated
implementation plan for the Float32/BFloat16 surface, the exactness-gated
compute path, and κ-registered Float32 kernels, with measured pass/fail
counts per milestone. Status: exploratory.

## Development notes

Four documents plan and re-plan the extension of the format grid from `K ≤ 8`
(120 at K ≤ 8, retained as the default exports) to `3 ≤ K ≤ 16` (504 formats).
Read in this order; each
says explicitly where it overrides its predecessor.

**extendingK.md** — [`extendingK.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/extendingK.md).
The first pass: what the draft permits, the two axes (storage unit and
evaluation carrier/rung) that govern the extension, and format counts by
starting rung. Status: exploratory/historical.

**doingtheextensions.md** — [`doingtheextensions.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/doingtheextensions.md).
Turns the plan into an architecture — the representation lattice, the carrier
dispatch lattice, and generated per-format trait methods — staged so every
step compiles and passes independently. Status: exploratory/historical.

**implementextensions.md** — [`implementextensions.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/implementextensions.md).
The execution plan: a line-by-line audit of the source tree that found ten
findings (errors or gaps) against the inherited plan, followed by a
ten-stage, single-commit-per-stage implementation schedule. Status:
exploratory/historical.

**morejulian.md** — [`morejulian.md`](https://github.com/JeffreySarnoff/SmallFloats.jl/blob/main/docs/other/morejulian.md).
A separate audit of where the package's Julia interface departs from
idiomatic Julia — ranked by user impact rather than by extension stage —
covering broken `AbstractFloat` contract methods and deliberate departures
alike. Status: exploratory/historical.

## See also

[Cheat Sheet](help_cheat_sheet.md),
[Glossary](help_glossary.md),
[Architecture and Invariants](internals_architecture.md).
