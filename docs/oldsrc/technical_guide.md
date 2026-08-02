# Technical Guide

How SmallFloats.jl works inside: the encoding, the projection engine, the oracle and its
correctness protocol, the performance layers, and the verification doctrine that holds
it all together. Read the [User Guide](@ref) first; this page assumes its vocabulary.

## Layer map

Source files load in dependency order, each layer speaking only downward:

| layer | file | provides |
|---|---|---|
| exact carrier | `dyadic.jl` | dependency-free rung-3 `Dyadic` arithmetic and exact `Rational` bridge |
| formats | `formats.jl` | abstract `Binary{K,P,SGN,EXT}`, `Code8`/`Code16`, the 504 aliases, Group M queries |
| carriers | `carriers.jl` | evaluation heads, `datumcarrier`/`promotecarrier`, exact lifting and carrier joins |
| specs | `projspec.jl` | rounding/saturation singletons, `ProjSpec{R,S}`, the predefined spec grid |
| defaults | `defaults.jl` | settable session defaults (`DefaultType`, `DefaultProjection`, …) behind `Ref`s; consumed via the speculation guard |
| codec | `decode_encode.jl` | decode (generated tables + bit-composed compute), encode, order keys, counting sort, `Class`, Next ops |
| engine | `project.jl` | `round_to_precision` (mask-based Float64 core + generic core), `saturate`, `project`, `project_interval` |
| ops | `ops_scalar.jl` | result-kind protocol, `apply_op`, the operation registry, the spec register |
| compat | `juliacompat.jl` | the Base register: declarative op ⇒ Base-function map |
| oracle | `oracle.jl` | ω-semantics for all 52 operations |
| tables | `tables.jl` | the pure-ρ result-table cache (unary/binary + bitwidth-gated ternary) |
| kernels | `kernels.jl` | Shape-A gathers, Shape-B scalar/threaded loops, `vmap` |
| blocks | `blocks.jl` | `Block`, block/scaled ops, exact reductions |
| packed | `packed.jl` | sub-byte `PackedVector` storage |
| approx | `approx.jl` | κ measurement/registry, conformance declaration |
| rand | `rand.jl` | Random-API hooks: uniform-[0,1) floor projection, clamped normal |

## Encoding and decoding

A value wraps its code point: `UInt8` through K = 8 and `UInt16` above it. The
code occupies the low K bits of that storage unit. The bit layout is the draft's:
sign (signed formats), biased exponent, trailing significand; one NaN at the
negative-zero slot; no −0; ±Inf adjacent to the extremes in extended formats.

`decode` has **two shapes, selected by `decodepolicy(T)`** — a representation
decision, not a semantic one.

At `K ≤ 8` it is a **`@generated` constant-tuple lookup**: per format, a
`2^K`-tuple of datums built once from the computational decode (so table and
computation are correct by construction and asserted equivalent exhaustively).
Constant inputs still fold — `maxfinite_datum(T)` is a compile-time constant —
while runtime decode is a single indexed load. Above `K = 8` a
`2^16`-tuple is not a constant worth materializing, so the computational decode
runs directly.

The computational decode assembles the datum **by bits** (normalize with
`leading_zeros`, place exponent and mantissa fields, `reinterpret`) wherever the
carrier is `Float64`.

**Which carrier that is depends on the format's exponent bias, and is the second
of the package's two axes.** `Float64`'s normal range holds every datum of the
432 formats at rung 1 — the property the bit-assembly rests on. It does not hold
the other 72: `Binary16p1uf` reaches `2^32768`. Those decode to `Float128`
(rung 2) or to an exact dyadic carrier (rung 3), chosen by `datumcarrier(T)`,
and every one of them is exact for the datums it accepts. So the invariant is not
"`Float64` is the exact carrier for all datums" — that was true only while
`K ≤ 8` — but the stronger and still-checkable one:

> **every format's datum carrier is exact for that format's datums**, and the
> choice is a dispatch decision derived from the exponent bias, never a caller's.

The suite checks it against an independent big-float transliteration of the
draft (gate G6, exhaustively over the `(datum, head)` pairs), and gate G4 checks
the consequence that matters: forcing a *wider* carrier never changes a code
point, so the choice buys time and never an answer.

Ordering runs on **integer order keys**: a sign-magnitude fold into an unsigned
type wide enough for the format's `2^K + 1` keys (`UInt16` at K ≤ 8, wider above),
monotone with the total order, NaN mapped to `typemax`. Same-format `TotalOrder`,
`isless`, and the numeric comparisons are key comparisons (~1 ns); since a format has
at most `2^K + 1` distinct keys, vectors sort with an **O(n) counting sort**
installed via `Base.Sort.defalg` (forward and reverse orderings; anything exotic
falls back to the stock algorithm).

## The projection engine

`project(fr, ρ, X; R, sticky)` is the single write path into a code point:

```
RoundToPrecision  →  Saturate  →  Encode
```

**RoundToPrecision** produces a `Rounded(kind, sign, S, Q)` — an exact scaled
significand `S` and exponent `Q` per the draft's `Q = max(⌊log₂|X|⌋, 1−B) − P + 1`.
Two implementations, proven equivalent exhaustively:

- the **generic floating-point core** (`_rtp_core`) handles `Float128` and
  `BigFloat` via exact power-of-two scaling and a fraction ν compared against the
  mode's decision points; `Dyadic` has its own exact fixed-point core over its
  native `(S, Q)` representation;
- the **mask-based Float64 core** (`_rtp_f64`) extracts sign/exponent/significand
  fields directly, represents ν as a 128-bit fixed-point integer with an OR-mask
  sticky for bits shifted out, and evaluates every mode — including the stochastic
  `⌊ν·2^N⌋` comparisons and `RNITE` ties — as integer field tests. Specials, zeros,
  and (Convert-only-reachable) subnormal Float64 inputs bail to the generic core.

**Symbolic sticky** is how enclosures talk to the engine: `sticky ∈ {−1, 0, +1}`
declares the true value to be the carried value plus an infinitesimal of that sign.
The engine folds it into every comparison; the delicate case — true value just
*below* a representable dyadic — decrements into the previous binade and sets
ν = 1⁻ (encoded in the mask core as an all-ones fixed-point fraction, which
reproduces every predicate including the RNITE tie behavior). This is what lets
directed modes land exactly on asymptotes: `tanh → 1⁻` under `TowardNegative`
projects to `NextLessThan(1)`, automatically.

**Saturate** classifies against the format's range with two integer comparisons per
side, then maps the classification through the draft's twenty saturation rows to
`as-is / MaxFinite / MinFinite / ±Inf / NaN`. The comparisons stay cheap because:

- the extremal magnitude in canonical `(S, Q)` form is a constant-folded function
  of the type parameters;
- the rounded value and the extremum share one lexicographic `(Q, S)` order
  (subnormals and the lowest normal binade share the same `Q`);
- signed formats use sign–magnitude symmetry, and unsigned underflow is just the
  sign bit;
- an internal `HUGEQ` sentinel represents "finite but astronomically large" (the
  ν = 1⁻ image of an infinite endpoint), so directed `SatNone` clamps it to
  MaxFinite correctly.

**Encode** is pure integer bit assembly, including the significand-carry
renormalization and the subnormal/normal field split.

## The oracle and the result-kind protocol

Every operation's defined result is computed by `ωeval`. It returns one of four
exact carrier types or four protocol wrappers; `apply_op` fast-splits the common
`Float64` case and finishes the rest:

| kind | meaning | finished by |
|---|---|---|
| `Float64` | exact (specials; representable arithmetic) | direct `project` |
| `Float128` | exact by **width analysis** | direct `project` |
| `BigFloat` | exact MPFR value produced at derived precision | direct `project` |
| `Dyadic` | exact at rung 3: an `Int128` significand and an `Int64` exponent, `isbits` | direct `project` (dyadic carrier) |
| `StickyF` | wide-spread `FMA`/`FAA` tail: exact head plus tail sign | direct `project` with `sticky` set — no allocation |
| `BigExactF` | lazy exact result at precision derived from the operands | evaluate, then `project` on `BigFloat` |
| `Enclose128F` | correctly-rounded Float128 bracket | sticky agreement, then MPFR fallback if needed |
| `EncloseF` | directed MPFR enclosure with optional Float64/Float128 prefilters | `yd` → `fq` → interval protocol |

The dyadic carrier converts to and from `Rational` **exactly**, and that bridge
is the cleanest way to reason about a rung-3 value:

```julia
using SmallFloats.DyadicNumbers: dyadic_to_rational, rational_to_dyadic, isdyadic

dyadic_to_rational(x)          # Rational{BigInt}, exact — a Dyadic IS S·2^Q
rational_to_dyadic(3 // 4)     # exact, or throws
isdyadic(1 // 3)               # false — no Dyadic represents it
```

Three properties are worth knowing. The infinities convert (`±1//0`, matching
`Rational{BigInt}(Inf)`) and NaN does not, because `Rational` has no NaN slot.
A non-dyadic rational is **refused rather than rounded** — rounding it here would
be a rounding outside `project`. And the round trip is a law about *values*, not
fields: `Dyadic`'s significand is deliberately unnormalized, so `6·2⁻²` and
`3·2⁻¹` are the same value and round-trip to the canonical one.

The full design, with every edge case and the three laws, is in
`docs/other/dyadic_rational.md`.

Two **rigor classes** govern every non-`Float64` path, and their arguments are never
mixed:

**Class R (unconditional)** rests on two facts that hold without any accuracy
assumption:

- **Width analysis.** Sums of decoded datums are *exactly representable* in
  `Float128` whenever operand bits + exponent spread fit 113 bits — checked in
  advance by integer exponent arithmetic (`Add` at ΔE ≤ 100, `FMA` ≤ 92, `FAA`
  span ≤ 98). Beyond the threshold, `Add` escalates to the exact MPFR path — at a
  precision **derived from the operands** by `bigprec`, not the retired 2200-bit
  constant, which was ample at K ≤ 8 and insufficient for 50 of the 504 formats
  (gate G2 measures this) — while
  `FMA`/`FAA` take a non-allocating **sticky-head** shortcut: past that spread the
  smaller term is provably too small (by construction of the threshold) to affect
  anything but the tail direction of the larger one, so the result is
  `StickyF(head, sign)` — no `BigFloat` involved. `FAA`'s three-term case runs a
  bounded Float128 2sum-distillation (Priest-style, ≤ 6 sweeps) to find that
  head/tail split directly; the residual `BigExactF` MPFR fallback exists only for
  the near-impossible case the distillation doesn't converge.
- **IEEE correct rounding.** Division and `sqrt` are correctly rounded at *every*
  binary width, by mandate. `Divide`/`Recip` therefore use the **Float64**
  quotient directly: it is within half an ulp of truth, so it serves as
  `EncloseF`'s eager `yd` estimate with no Float128 arithmetic on the path at all.
  `Sqrt`/`RSqrt` use the **Float128** CR result: an inexact nearest-CR value `q`
  brackets the truth in the *open* interval `(prevfloat(q), nextfloat(q))`.
  Exactness itself is detected by an `fma` residual test.

**Class E (envelope-conditional).** Faithful-but-not-CR evaluations stand in for an
enclosure only inside a generous envelope, resolved by the two-sided sticky gate.
Two stages, cheapest first:

- *Float64 stage:* for operations whose Float64 libm is faithful (≤ 1 ulp ≈ 2⁻⁵²
  relative — the exp/log families, the hyperbolics, forward trig inside the
  |x| ≤ 10¹⁵ reduction window, `atan`, `asinh`, the softplus composition), the
  eager estimate `yd` carries envelope `E = |yd|·2⁻⁴⁵`, ≥ 2⁷ slacker than any
  faithful-libm error (measured margin on this machine: ≥ 2⁶·⁶).
- *Float128 stage:* libquadmath's estimate `y = fq()` carries `E = |y|·2⁻⁹⁰`, at
  least 2¹⁸ slacker than any published libquadmath bound.

In both stages, if the sticky-projected endpoints agree, that code point is the
answer; if not, the next stage (ultimately the MPFR ladder) decides. An envelope
failure can therefore only cost speed, never correctness — unless both endpoints
agree *and* the envelope is wrong, which the differential-build tests rule out
empirically by building every standard table twice (Float128-first and pure-MPFR)
and byte-diffing, and which the exhaustive oracle cross-check re-verifies per
operation against the 3072-bit protocol.

**The interval protocol** (`project_interval`) is the termination backbone: evaluate
the MPFR enclosure at precision `p`; if `lo == hi` the value is exactly
representable — project it; otherwise project `lo` with `sticky = +1` and `hi` with
`sticky = −1`; agreement (projection is monotone at fixed `R`) yields the answer;
disagreement doubles `p`, clamped to the `maxprec` ceiling (**derived from the
format**, `max(4096, bigprec(T) + 64)` — a flat 4096 was ample at K ≤ 8 and could
not decide `ArcCosPi` at `Binary15p2ue` under a directed or stochastic rule,
honored exactly even when it is not a power-of-two multiple of the 256-bit start).
Termination requires that the enclosure not be chasing a value the grid can
actually hit — which is why the π-scaled operations carry **Niven peels**: for
dyadic arguments, `tan(πr)` takes rational values only at the quarter-integers
(±1) and `atan2/π` only on the diagonals (±¼, ±¾); those cases are answered
exactly before any enclosure is built, and Niven's theorem proves the peel set
complete.

## Tables and kernels

For pure specs over K ≤ 8 operands, unary and binary operations are small
**finite functions** — at most 256 or 65 536 entries — so the kernel layer
materializes them once per `(op, formats, ρ)` into a
locked cache (`Dict{TableKey, Memory{UInt8}}`, double-checked locking, builds outside
the lock) and serves every later array call as a gather: Shape-A, one load per
element. On the recorded host that is 0.13 ns/elem unary and 0.26 ns/elem binary.
Tables are built
*through the scalar path*, so they inherit its bit-exactness; the suite asserts
table ≡ scalar over every entry. Signatures involving K > 8 formats compute
directly.

Ternary (`FMA`, `FAA`, `Clamp`) is a finite function too — 2^(K1+K2+K3) entries —
but that count already spans four orders of magnitude across the table-eligible
K = 3:8 region (512 B at K=3, 16 MiB at K=8), so one policy does not fit even
that range. A separate
`TernaryKey → TernaryEntry` cache (`_ternary_table_for`, in `tables.jl`) tiers by
Σ bitwidth:

- **Eager** (≤ 18 bits, all `K ≤ 6` combinations, ≤ 256 KiB): builds and caches
  on the first array call.
- **Adaptive** (≤ 21 bits, the `K = 7` band, up to 2 MiB): accumulates a
  per-signature element count across calls and builds only once a signature has
  processed enough elements to amortize the build; a byte-bounded LRU eviction
  (`TERNARY_CACHE_BYTES`) guards against many hot signatures coexisting.
- **Compute** (`K = 8`, 16+ MiB — a table is never worth it): `vmap!` runs
  Shape-B, the fully specialized scalar pipeline per element, optionally split
  across `Threads.@threads` for long enough arrays (each ternary draw is
  independent under a fixed, non-stochastic ρ, so lanes cannot interact).

Any ternary signature containing a K > 8 format also takes the compute path.

Every ternary table entry, eager or adaptive, is still built *through the scalar
path* — the tiering changes when/whether the cache exists, never what it contains.
Stochastic calls of any arity always take Shape-B, with the RNG resolved once per
array rather than per element.

## Blocks: exactness without a superaccumulator

`blockdecode` produces each lane's `scale × element` exactly on the carrier
selected jointly from the scale and element formats. Reductions then apply
**span filters**: one integer pass over lane exponents decides whether the whole
sum or dot product is exactly representable in `Float128`; the filter is used
only when the joined carrier is no wider than `Float128`. If it passes, a plain
`Float128` accumulation *is* the exact answer; otherwise an exact big-float
accumulation at format-derived precision takes over. Either way there is exactly
one projection, at the end. `ωBlockProject`
follows the draft's special rows for the scale (NaN, 0, ±Inf) and divides each
element result by the scale through its own cheapest-first CR-bracket / enclosure
cascade (exact Float64 quotient → CR Float128 → bracket/pre-filter → MPFR
interval), mirroring the scalar quotient group's rigor arguments.

## The κ registry and conformance

κ is the maximum code-point distance (along the total order) between an
implementation's result and the defined result, over inputs with finite defined
results; any mismatch on non-finite defined results makes κ = NaN. Because inputs
are enumerable, `register_approx!` *measures* κ exhaustively at registration and
rejects understatement — a declared bound is a verified property, not a promise.
`conformance()` assembles the declaration live from the operation registry, the
table cache, and the approximation registry.

## Verification doctrine

The suite enumerates every tractable axis and labels the rest. A default run
reports approximately 35.3 million compared units across 14 gates and tiers;
the final roll-call distinguishes exhaustive coverage from sampled or
boundary-targeted coverage. In particular it covers:

- formats against an independent draft transliteration (14 679);
- ordering over all 2.5 M same-format pairs plus Next-op edge tables (7.6 M);
- every unary operation on every input against a 3072-bit protocol run; divide
  and the ternaries exhaustively;
- stochastic R-sweeps with directed-asymptote pins;
- table ≡ scalar over every entry, including the ternary tiers (eager and
  adaptive) against the scalar path;
- the sticky-head `FMA`/`FAA` escalation against the MPFR reference across every
  rounding-mode family and adversarial cancellation cases;
- blocks against a from-scratch reference composition;
- Float128 carrier ≡ Float64 carrier, and Float128-first ≡ MPFR differential
  builds;
- the mask rounding core ≡ the generic core over datums and reachable
  sums/products at boundary stochastic budgets N ∈ {45, 60};
- packed round-trips, and κ/conformance behavior.

Deterministic **specialization regressions** (concrete inferred return types at the
public entry points, zero warm-path allocation) stand in for timing assertions.

## Benchmark doctrine

Recorded after two measurement post-mortems: a benchmark closure over any non-`const`
global measures Julia's dispatch machinery, not the code under test — and it distorts
*ratios*, not just absolutes, because dispatch cost varies with call shape (a dynamic
keyword call costs ~1 µs; a dynamic positional call far less; six unresolved interior
sites cost six times one).

The rules the shipped `benchmarking/benchmarking.jl` enforces structurally:

- format types enter as type parameters, never as globals;
- operands come from untimed setup;
- functions retrieved reflectively pass through argument barriers to specialize;
- a preflight aborts the run if warm scalar paths allocate — including the
  wide-spread `FMA`/`FAA` sticky-head path.

The table-build section reports both the cold build (cache evicted per sample) and
the steady-state warm cache hit, since callers amortize the former through the
latter. Vary one binding per variant; verify specialization before believing a
number.

## Deliberate limitations

No implicit cross-format arithmetic: mixed `Binary` formats refuse, while a
`Binary` mixed with an ordinary Julia number promotes to its public
`promotecarrier`. No in-place packed arithmetic. Threading is opt-in and narrow:
only untabled ternary compute kernels thread, and only above a size cutoff and when
`Threads.nthreads() > 1`; every other kernel is single-threaded.
`Irrational`/`Rational` inputs to `Convert` are rejected rather than
double-rounded silently. The `Float128` machinery never changes results — disabling
it (`SmallFloats_Float128=disable`) is a tested no-op semantically.
