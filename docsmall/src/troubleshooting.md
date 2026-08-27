# Troubleshooting

Symptom-first. Each entry names what you see, why, and the fix.

**`T(0x02)` and `T(2)` give different values, and it looks like a bug.**
An `Unsigned` argument is a code point; every other integer is a value to
project. Both calls are valid, so nothing warns. Fix: `T(Int(c))` when you
mean the number, `T(c::Unsigned)` when you mean the code point, or
`Convert(T, ρ, x)` when intent must be explicit. See
[Formats and Values](values.md).

**An array of `Binary` values is slow, or every element is boxed.**
The element type is the abstract parametric format, which is not `isbits`.
Fix: use a concrete alias as the element type (`Vector{Binary8p4se}`), or
obtain one from `format(...)` when the parameters are runtime values.

**A benchmark reports about 1 µs per call for a warm scalar operation.**
The format or spec was read from a non-`const` global, so every call pays
dynamic dispatch; the benchmark measures the dispatcher. Fix: pass formats
as type parameters or `const` bindings, and verify zero warm-path
allocation before trusting a number.

**Overflow produced `Inf` where a clamp was expected (or the reverse).**
`SatNone` is not a clamp; it applies the draft's domain-, sign-, and
direction-dependent rows, which can yield ±Inf, an extremal finite value, or
NaN. Only `SatFinite` guarantees a finite result. See
[Computing](computing.md).

**Mixing two `Binary` formats throws a promotion error.**
Deliberate: no automatic rule can soundly pick a containing format. Fix:
`Convert(T, ρ, x)` to the format you want before combining.

**Constructing from a `Rational` throws.**
Also deliberate: it would require a hidden second rounding. Fix: convert to
a supported carrier first (`T(Float64(r))`) and own that rounding.

**A stochastic pipeline gives different results each run.**
Stochastic projections draw random bits. Fix: pass a seeded `rng` for a
reproducible stream, or an explicit `R` in `0:2^N−1` for bit-exact single
projections in tests. Thread one `rng` through every call that must agree;
constructing a second generator mid-pipeline desynchronizes the streams.

**The first array call is much slower than every later one.**
Deterministic unary/binary calls may build a cached result table on first
use; you measured the build. Fix: warm the exact specialization first;
benchmark cold and warm separately. `table_bytes()` inspects the cache,
`empty_tables!()` resets it.

**`Float16`/`BFloat16` data comes through at half or double its value.**
Bits were reinterpreted across an exponent-bias difference of one. Fix:
always `Convert`, never `reinterpret`, across the IEEE boundary. See
[Data at Scale](data.md).

**Block quantization did not help data with wide per-row scales.**
The raw values were staged through the narrow element format first, so
`SatFinite` clamped them before the block scale could absorb the range.
Fix: stage through a wide-range format, then `ConvertToBlockMaxAbsFinite`.

**`sort` puts NaN first, unlike `Float64` sorting.**
Not a bug: the draft's total order places the single NaN below −Inf. Sort
with `rev=true` if you need it last.

**Division by zero returned NaN, not `Inf`.**
P3109 defines `Divide(x, 0)` as NaN for every `x`, and `Recip(±Inf)` as 0.
Check divisors explicitly if an algorithm relies on IEEE signed-infinity
quotients.
