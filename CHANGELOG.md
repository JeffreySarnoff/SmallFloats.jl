# Changelog

## 0.2.0 — the K ≤ 16 extension

The format grid goes from **120 formats at K ∈ 3:8** to **504 at K ∈ 3:16**.

### Added

* **384 new formats.** `Binary{K,P,Σ,Δ}` for `K ∈ 9:16`, with the same
  `4K − 2` structure at each width. Every operation, projection, block form and
  array kernel works at every one of them.
* **`SmallFloats.Formats`**, an opt-in namespace re-exporting all 504 aliases.
* **`format(K, P, Σ, Δ)`**, `reptype` and `codeunit_type` are now exported.
  `format` is the supported programmatic route to a concrete format type when
  the parameters are runtime values.

### Changed — read this before upgrading

* **The export surface is narrower than the grid.** `using SmallFloats` exports
  the **120 aliases at K ≤ 8**, exactly as in 0.1.0, so no existing program
  changes meaning. The other 384 need `using SmallFloats.Formats`, or
  qualification (`SmallFloats.Binary16p6se`), or `format(16, 6, true, true)`.

  Chosen by asymmetric reversibility: exporting more later is non-breaking,
  un-exporting is not.

* **`Binary` is now abstract**, and the draft-named aliases are its concrete
  *representations*. `Binary8p4se === Binary{8,4,true,true}` is now **`false`**;
  `Binary8p4se <: Binary{8,4,true,true}` is `true`. This is the draft's own
  distinction — a format is a datum set and an encoding, while the width of the
  machine word carrying a code point is a representation choice below the
  standard's level of description.

  **Migration:** replace `===` with `<:` in type comparisons, and use the alias
  or `format(K,P,Σ,Δ)` wherever a concrete type is needed (an array element
  type, a `similar` target, a constructor target).

* **`similar` normalizes** an abstract format request to its representation,
  because an abstract type is not a valid array element type.

* **A value is one byte at K ≤ 8 and two above it.** `codeunit_type(T)` names
  the storage unit. The code point occupies the low `K` bits; the high bits are
  maintained zero.

* **`decode` no longer always returns `Float64`.** 432 of the 504 formats have
  exponent ranges `Float64` holds exactly; the remaining 72 decode to `Float128`
  or to an exact dyadic carrier. Which one is a dispatch decision derived from
  the exponent bias, and every carrier is exact for the operands it accepts —
  the choice buys time and never changes an answer.

  `Float64(x)` still returns a `Float64` for every format, and still rounds
  where the datum does not fit.

* **`promote_rule`** now targets the format's promotion carrier rather than
  `Float64` unconditionally. In 0.1.0 this was correct for every format that
  existed; at a `B = 32 768` datum it would have returned ±Inf from a finite
  value with no P3109 operation involved.

### Fixed

* `Float16(::Binary)` was never defined, at any K.
* `project_interval`'s precision ceiling was a flat 4096 bits, ample at K ≤ 8
  and insufficient above it — `ArcCosPi` under a directed or stochastic rounding
  mode raised an error for subnormal operands of wide formats. Now derived from
  the format.

### Verification

* 13 gates and tiers, ≈ 35.3 M compared units.
* The code lattice is swept **exhaustively at every K** — 7 602 160 code points
  across all 504 formats.
* The projection engine is checked against an independent `Rational{BigInt}`
  reference: 218 988 rounding decisions exhaustive over all 135 realized
  `(P, B)` cells, plus a saturation sweep over the `(P, B, Σ, Δ)` tuples.
* Every green run prints a coverage roll-call naming each gate, what it
  compared, whether that was exhaustive or sampled, and — in one place — what is
  knowingly not covered.

### Dependencies

**None added.** `Quadmath` and `BFloat16s` were already present, the exact
dyadic carrier is hand-written `Int128` arithmetic, and MPFR is in `Base`.

## 0.1.0

Initial implementation: the IEEE SA P3109 draft at bitwidths 3–8.
