# Troubleshooting

Symptom-first reference. Find what you are seeing, not what you did wrong —
each entry names the symptom, the cause, the fix, and where to read the full
explanation.

## Values and Construction

**Symptom: `T(0x02)` gives a different value than `T(2)`, and it looks like a bug.**
Cause: an `Unsigned` argument is a *code point*, at every bitwidth — `T(0x02)`
constructs code point `0x02`, while `T(2)` projects the numeric value two.
Signedness of the integer type is what distinguishes them, so this holds for
`UInt8`, `UInt16`, and any other `Unsigned`. Fix: use `T(Int(c))` when you mean
the number, `T(c::Unsigned)` when you mean the code point, or call `Convert`
when intent should be unmistakable. Full explanation: [Cheat Sheet](help_cheat_sheet.md), Values,
Code Points & Conversion.

**Symptom: `Binary8p4se(0x02)` and `convert(Binary8p4se, 0x02)` disagree.**
Cause: `convert` is the deliberate exception to the Unsigned-is-a-code-point
rule and is value-preserving — `Binary8p4se(0x02)` is code point 2, while
`convert(Binary8p4se, 0x02)` is the value 2.0. Promotion, `similar`, and `fill`
depend on `convert` behaving this way. Fix: know which one you are calling;
prefer `T(x)` or `Convert(T, ρ, x)` in your own code and reserve bare `convert`
for places Base itself calls it. Full explanation: [Cheat Sheet](help_cheat_sheet.md), Values, Code
Points & Conversion.

**Symptom: constructing from a `Rational` throws.**
Cause: `Rational` is not one of the supported construction carriers. Fix:
convert explicitly to an exact supported carrier (a `Float64`, `Dyadic`, or
similar) or knowingly to `Float64` first, then construct. Full explanation:
[Cheat Sheet](help_cheat_sheet.md), Values and code points.

**Symptom: `T(-0.0) === zero(T)` surprises code that expects signed zero.**
Cause: every P3109 format has exactly one zero; there is no negative zero to
distinguish. Fix: stop testing for negative zero; if you need "approached from
below," use the projection engine's `sticky` argument instead of relying on a
stored sign. Full explanation: [Core Model](core_model.md), [Encoding and Decoding](internals_encoding_decoding.md).

**Symptom: a value built with `SmallFloats.rawvalue` decodes to garbage or a non-existent datum.**
Cause: `SmallFloats.rawvalue(T, c)` is an internal unchecked constructor — it skips the
range validation that `T(c::Unsigned)` performs, so an out-of-range integer
produces a bit pattern with no corresponding intent-checked datum. Fix:
use validated `T(c::Unsigned)` outside package implementation code.
Full explanation: [Cheat Sheet](help_cheat_sheet.md), Values and code points.

**Symptom: dividing by zero gives `NaN`, not `Inf` as IEEE-754 code expects.**
Cause: P3109 defines `x / 0 → NaN` (and `Recip(±Inf) = 0`), which is not IEEE
division-by-zero semantics. Fix: do not port IEEE-754 zero-division
assumptions across; check for zero divisors explicitly if your algorithm
depends on signed infinities from division. Full explanation: [Cheat Sheet](help_cheat_sheet.md),
Values and code points; [P3109 in One Chapter](concept_p3109.md).

## Arithmetic and Semantics

**Symptom: `Multiply`/`Add` overflowed and you expected a clamp, but got `Inf`
(or vice versa).**
Cause: `SatNone` does not mean "no saturation" in the clamping sense — it
applies the draft's domain-, signedness-, and direction-dependent rows, which
can still produce `Inf`, `MaxFinite`, or `NaN` depending on the case. Only
`SatFinite` guarantees clamping to the finite range. Fix: choose `SatFinite`
whenever clamping is actually required; do not assume `SatNone` behaves like
`clamp`. Full explanation: [Cheat Sheet](help_cheat_sheet.md), Projection specifications.

**Symptom: mixing two `Binary` formats in one expression throws a promotion
error instead of silently widening.**
Cause: this is deliberate — the package refuses silent cross-format promotion
so that no rounding step happens somewhere nobody wrote. Fix: convert
explicitly, `Convert(T, ρ, x)`, to the format you actually want before
combining. Full explanation: [Cheat Sheet](help_cheat_sheet.md), Values and code points.

**Symptom: `rem`, `mod`, or a similar Base numeric function refuses to run, or
errors in a way that looks like a missing method.**
Cause: some generic Base numeric functions are defined in terms of operations
or promotion behavior this package deliberately does not supply by default
(for example, functions that would require an implicit cross-format
promotion or an IEEE-754-only special case). This is a refusal, not an
omission bug. Fix: express the computation with the package's explicit
operation catalog (`Add`, `Subtract`, `Multiply`, `Divide`, `FMA`, …) and
`Convert` calls instead of relying on the generic fallback. Full explanation:
[Cheat Sheet](help_cheat_sheet.md), Scalar operation catalog.

## Arrays and Performance

**Symptom: an array of `Binary` values is slow, or every element looks boxed.**
Cause: the element type is the *abstract* format `Binary{K,P,Σ,Δ}`, not a
concrete alias — the abstract format is not `isbits`, so a generic-element
array boxes every entry. Fix: use a concrete element type, `Vector{Binary8p4se}`
or `Vector{format(K,P,Σ,Δ)}`. Full explanation: [Cheat Sheet](help_cheat_sheet.md),
Common pitfalls (below), and
[Architecture and Invariants](internals_architecture.md).

**Symptom: `Vector{Binary{K,P,Σ,Δ}}(undef, n)` silently boxes every element,
even though you thought you had a concrete type.**
Cause: `Binary{K,P,Σ,Δ}` with type-parameter variables is abstract, and
`Vector{…}(undef, n)` cannot be intercepted or redirected to a concrete
representation the way constructors can. Fix: use `Vector{Binary8p4se}` (a
concrete alias) or `Vector{format(K,P,Σ,Δ)}` (concrete once `K,P,Σ,Δ` are
literal values); `similar` normalizes correctly and is safe. Full
explanation: [Cheat Sheet](help_cheat_sheet.md), Common pitfalls.

**Symptom: benchmarks report ~1 microsecond per call for an operation you
know is sub-nanosecond warm.**
Cause: the format type or projection spec was read from a non-`const` global,
so every call pays Julia's dynamic dispatch instead of running the specialized
method. This is a benchmarking-methodology bug, not a package performance
regression — it has been traced to this exact mistake in real post-mortems.
Fix: keep format types and projection specs in `const` bindings, function
arguments, or type parameters; put runtime-selected-format code behind a
function barrier; verify zero warm-path allocation before trusting a number.
Full explanation: [Verification Sessions](examples_verification.md), Benchmarking without measuring the
dispatcher; [Verification Strategy](internals_verification.md).

**Symptom: the first array call for a given format/operation is much slower
than every call after it.**
Cause: deterministic unary/binary operations build a cached result table on
first use for that specialization; you measured the build, not the steady
state. Fix: warm the specialization before benchmarking, and benchmark warm
calls separately from the first call. Use `table_bytes()` to inspect the
cache footprint and `empty_tables!()` to reset it. Full explanation: Cheat
Sheet, Performance checklist (pointer); [Function Tables and Array Kernels](internals_tables.md).

## Random and Stochastic

**Symptom: a stochastic-rounding pipeline gives different results every run,
even though you want to compare against a fixed baseline.**
Cause: stochastic projections (`RSA`, `RSB`, `RSC`) consume random bits from
an RNG (or an explicit draw), and without a fixed source that draw changes
every run. Fix: supply a seeded `rng` (for example `Xoshiro(1)`), or pass an
explicit `R` in `0:(2^N - 1)` for exact, reproducible draws — ideal in tests.
Full explanation: [Cheat Sheet](help_cheat_sheet.md), Stochastic projections; Reproducible
Stochastic Rounding.

**Symptom: you passed a seed but two calls in the same pipeline still
diverge.**
Cause: the uniform draw and the stochastic rounding draw must come from the
*same* rng stream to stay reproducible together; if you construct a second
`Xoshiro` mid-pipeline instead of threading the same `rng` through, the
streams desynchronize. Fix: thread one `rng` object through every call in the
pipeline that needs to agree. Full explanation: [Cheat Sheet](help_cheat_sheet.md), Stochastic
projections.

## Platform note: disabling Float128

On platforms where libquadmath misbehaves, set an environment variable **before**
loading the package:

```julia
ENV["SmallFloats_Float128"] = "disable"
using SmallFloats
```

This selects the pure-MPFR configuration. Results are **bit-identical** — that
equivalence is itself part of the test suite; only oracle and build speed change.

## Related help

[Cheat Sheet](help_cheat_sheet.md),
[Glossary](help_glossary.md),
[Performance Model](concept_performance.md),
[Verification Strategy](internals_verification.md).
