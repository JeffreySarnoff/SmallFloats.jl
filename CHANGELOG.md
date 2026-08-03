# Changelog

## 0.4.0 — Conformance identity and explicit stochastic configuration

### Changed

* **Stochastic entropy is explicit or task-local.** Removed the inert
  `DefaultRNG` and `DefaultRbits` controls. Omitted RNGs use Julia's
  `Random.default_rng()`; pass `rng=` for an owned stream and construct
  `RSA_*`, `RSB_*`, or `RSC_*` with an explicit bit count when it is not 8.
* **Rounding classification has one source of truth.** Internal behavior now
  dispatches on the exported nearest, directed, faithful, deterministic, and
  stochastic abstract mode hierarchy instead of conflicting legacy unions.
* **Conformance identity is structured.** `conformance()` derives version 0.4.0
  from package metadata and reports the retained P3109/D1 transliteration and
  its SHA-256 digest. `draft_identity()` exposes the same facts directly.

### Fixed

* Corrected the D1 special rows for `ArcTan2` and `ArcTan2Pi`: `(0, 0)` and
  every `(±Inf, ±Inf)` pair now produce NaN. The previous implementation and
  its tests pinned host-style zero and quadrant results rather than the retained
  P3109/D1 definitions.
* Corrected documentation that described nonexistent scoped
  `with_default_*` mutation. These functions consume the current process-wide
  defaults; explicit `T` and `ρ` are the local-policy interface.

## 0.3.0 — Julia integration and semantic corrections

### Added

* **A fuller `AbstractFloat` interface.** `Binary` values now support exact
  `decompose`, `hash`, `widen`, `exponent`, `significand` and `frexp`, together
  with `round`, `floor`, `ceil` and `trunc`. This makes format values usable as
  `Dict` keys and `Set` elements and improves compatibility with generic Julia
  code. Deliberately unsupported operations now fail with package-specific
  explanations instead of incidental `MethodError`s.
* **Callable operation-register entries.** `Op(:Add, T, ρ)` captures an
  operation, result format and projection as a zero-allocation callable for
  `map`, broadcast and other higher-order interfaces.
* **Four display styles.** `set_show_style!`, `get_show_style`,
  `VALID_SHOW_STYLES` and the `:binary_show_style` `IOContext` property select
  value-only, code-point-only, datum or typed output.
* **Exact Dyadic–Rational bridges.** `DyadicNumbers` now provides
  `dyadic_to_rational`, `rational_to_dyadic` and `isdyadic`, with corresponding
  `Rational{T}(::Dyadic)` and `Dyadic(::Rational)` conversions. Non-dyadic
  rationals are rejected rather than rounded outside `project`.
* **Deadline-aware benchmarking.** `benchmarking/faster_benchmarking.jl` covers
  representative scalar, projection, array, table, block, conversion and packed
  storage work within a configurable time budget, with a checked-in report.

### Changed — read this before upgrading

* **Projection constants use short saturation suffixes.** The 27 deterministic
  and stochastic families were renamed from spellings such as
  `RNE_SatFinite`, `RNE_SatPropagate` and `RNE_SatNone` to `RNE_SF`, `RNE_SP`
  and `RNE_SN` (and likewise for `RNA`, `RTP`, `RTN`, `RTZ`, `RTO`, `RSA`,
  `RSB` and `RSC`).

  **Migration:** replace `_SatFinite` with `_SF`, `_SatPropagate` with `_SP`
  and `_SatNone` with `_SN`.

* **NaN is first in the P3109 total order.** `TotalOrder`, `isless`, sorting and
  the integer order key now place the format's single NaN below negative
  infinity, as required by draft §4.12.1. The earlier implementation placed it
  above positive infinity. Ordinary numeric comparisons remain unordered for
  NaN.
* **The default display is now `:value`.** A `Binary` prints as the number it
  denotes in ordinary output. Use `set_show_style!(:typed)` for the former
  `Binary8p4se(1.625 ≡ 0x45)` presentation, or an `IOContext` override when
  the choice must be local to one stream.
* **`similar` keeps array element types concrete.** Arrays whose element type is
  an abstract `Binary{K,P,Σ,Δ}` format now produce `similar` arrays using its
  concrete representation, avoiding boxed elements.
* **`reinterpret(T, u::Unsigned)` validates representation invariants.** The
  source and target must have equal storage size and bits above the format's
  `K`-bit code point must be zero.

### Fixed

* `get_show_style()` no longer throws from an undefined variable, and all
  two-argument `show` paths now honor the selected style. Removing a duplicate
  method also restores clean package precompilation.
* Corrected four silent wrong-answer cases in the exact `Dyadic` carrier:
  negation/absolute value at `typemin(Int128)`, integer rounding at
  `typemin(Int64)` exponent, negative infinity converted to an unsigned
  rational, and an invalid `0//0` rational converted as negative infinity.
* Dyadic multiplication no longer pays an always-active bounds check, and the
  finite addition path avoids unnecessary special-value dispatch.
* `Rational{BigInt}(::Dyadic)` now follows Julia's convention for infinities
  (`±1//0`) and rejects only NaN; `Base.isunordered(::Dyadic)` is defined for
  sorting and extrema operations.
* Stochastic short-name constructors such as `RSA_SN` are now actually defined;
  they had been exported but missed by the generated constructor rename.
* Documentation examples no longer leak process-global projection defaults into
  later examples, and every `julia-repl` block is now executed and checked.
* The PDF pipeline now detects partial font coverage, parses nested markup in
  headings, reads the package version from `Project.toml`, preserves part-level
  table-of-contents pagination and packages its artifacts consistently.

### Documentation and verification

* The manual was consolidated under `docs/src`, reorganized by user goal and
  expanded with the recovered Julia-compatibility guide, worked examples, trap
  tables, code-point algebra and implementation guidance. The README now serves
  as a compact runnable introduction.
* The suite has one `SMALLFLOATS_TIER` dial (`quick`, `default`, `release`) and
  asserts that requested coverage is not silently reduced. The release tier
  sweeps every applicable format axis, including all 504 formats and all
  7,602,160 code points; boundary-targeted and otherwise sampled gates identify
  themselves in the final roll-call.
* A fourteenth gate checks the Dyadic–Rational laws, while new gates exercise the
  Julia surface, all display styles, documentation examples and the rule that an
  abstract format is never rebuilt as a concrete representation in method
  bodies.

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
