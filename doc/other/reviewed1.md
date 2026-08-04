# Review of SmallFloats.jl — second pass

*Static review at `3e940d6` (main, clean), package version 0.4.0, 2026-08-03.*

## Scope and method

Every file in `src/` was read in full, together with `test/runtests.jl`, the gate
and tier files, `CLAUDE.md`, `benchmarking/benchmark_report.md`, the CI
workflows, and the repository's tracked-file inventory.

**No tests and no benchmarks were executed**, per instruction. The suite is
taken to pass; the checked-in benchmark report is taken as the performance
evidence. Consequently every finding below is derived from the source itself —
control flow, type reachability, and arithmetic that can be discharged by hand.
Where a claim needs a run to settle, it is labelled as such rather than
asserted.

This is a second pass. `doc/other/reviewed.md` reviewed 0.3.0; the first section
below records which of its findings are now closed, because a review that
re-reports fixed defects is worse than no review.

---

## What the 0.4.0 cycle closed

Verified closed against the current source:

| 0.3.0 finding | Status |
|---|---|
| Inert `DefaultRNG` / `DefaultRbits` session controls | **Closed.** Removed entirely; `defaults.jl:98-114` records the decision and its reasoning (invariant 5, not tidiness). Entropy is now explicit-or-task-local. |
| `conformance()` reported a hand-copied version | **Closed.** `approx.jl:303` derives it from `Base.pkgversion`, with a representable `v"0.0.0-DEV"` fallback for non-Pkg loads. |
| Draft identity was a date | **Closed.** `DRAFT_IDENTITY` (`approx.jl:20-25`) carries designation, upload date, retained source path, and a SHA-256 of the transliteration. |
| Two rounding taxonomies (`ToOdd` faithful *and* directed) | **Closed.** `projspec.jl:9-27` is now the single hierarchy; the legacy unions are gone. |
| No CI | **Closed.** `.github/workflows/ci.yml` (PR ⇒ quick tier, push/nightly ⇒ default tier, plus a docs build) and `release.yml` (release tier, conformance artifact, PDF). |
| `DEFAULT_SHOW_STYLE` / `rawvalue` exported | **Closed.** Neither appears in the export lists; `set_show_style!`/`get_show_style` and an `IOContext` property are the interface. |
| Docs described nonexistent scoped `with_default_*` mutation | **Closed.** `defaults.jl:191-232` documents them accurately as consumption combinators, including the allocation contract. |

Still open from that pass, unchanged: **benchmark coverage omits K > 8
entirely**, **generated PDF build products are tracked**, **no release tags**.
Each is re-stated below with current evidence.

---

## Executive assessment

The arithmetic core is, if anything, stronger than the previous review found it.
The K ≤ 16 extension did not dilute the design: it *promoted* the escalation
ladder from an implementation detail to a first-class trait axis
(`carriers.jl`), split the representation seam by dispatch rather than by
branching (`Code8`/`Code16`), and kept the single-write-path invariant intact
across three carriers. The `Dyadic` rung is the right answer to unbounded
exponent range, and its separation — zero package dependencies, checkable on its
own terms — is the kind of decision that pays for itself later.

What I did not find: any place where an approximate result can reach a default
path; any second write path into a code point; any hand-written per-format
variant; any silent narrowing of a datum.

What I did find, in descending severity:

1. A **public exported function that fails with the wrong error class on 384 of
   the 504 formats** (`f32_exact`).
2. A **permanently downgraded verification axis with a dead switch** — the suite
   cannot be asked for the loop counts it was written with.
3. An **ordinary `AbstractFloat` verb that raises a bare `MethodError`**
   (`eps(x::Binary)`), which is precisely the class G10 exists to close.
4. A **false arithmetic statement inside the gate guarding `decode!`'s
   exactness promise** (`datumsexact`'s unsigned `emax`), currently masked by
   an exactly-zero margin.
5. Continuing gaps in evidence and hygiene: no wide-format benchmarks, 29 MB of
   generated PDF intermediates tracked, no tags.

None of these is an arithmetic defect in the shipped default paths. All of them
are the same species: *a claim that nothing executes*. That is the failure mode
`CLAUDE.md` names in its own review section, and it is where this package's
remaining risk lives.

---

## Architecture

The dependency direction is coherent and the layering comment in
`src/SmallFloats.jl:49-69` is now accurate (it was not at 0.3.0). Two axes are
cleanly separated and that separation is the extension's central insight:

- `formats.jl` owns **storage**, a function of `K` (`Code8`/`Code16`,
  `codeunit_type`, `decodepolicy`, `orderkeytype`).
- `carriers.jl` owns **evaluation**, a function of the exponent bias `B`
  (`HeadF64`/`HeadF128`/`HeadExact`, `rung`, `lift`, `bigprec`).

`Binary16p12se` (B = 8) being numerically tamer than `Binary8p1uf` (B = 128) is
the observation that makes the whole grid tractable, and the code says so where
it matters rather than in prose alone.

Specific decisions worth naming as strengths:

- **`lift` has no narrowing method, on purpose** (`carriers.jl:228-244`). The
  absence is the design; the `rung(op, Fs...)` join is what makes it
  unreachable. This is a much better shape than a `convert` that quietly
  rounds.
- **Refusals are methods, not missing methods** (`decode_encode.jl:89-95`,
  `oracle.jl:374-381`, `oracle.jl:476-479`, `tables.jl:159-167`). The recorded
  reason — JET reports an absent method on an inferred `Union` as a package
  defect, and the only alternative would be an unbacked filter — is correct and
  generalizable.
- **`table_for` vs `get_table`: one name per question** (`tables.jl:332-344`).
  One returns `nothing` without prejudice, one throws because its contract is to
  return a table. This is exactly right and is the kind of distinction most
  libraries collapse.
- **`mul_dy` / `mul_dy_checked`** (`dyadic.jl:297-343`). The `@boundscheck`
  post-mortem recorded there (3.3× the cost of the multiply, because no
  `oracle.jl` call site is `@inbounds`) is a genuinely useful piece of
  engineering knowledge, and the resolution — two names — is the right one.
- **The two table budgets are in different units for stated reasons**
  (`tables.jl:122-148`): bytes for memory (invariant 10), entries for build
  time. Comparing bits as bits rather than computing `1 << ΣK` to discover that
  `1 << ΣK` is too large is the correct instinct.
- **`_encl_div_scale` forms the divisor as an exact `BigFloat` at its own
  width** (`blocks.jl:140-141`), rather than letting promotion round it at the
  ambient precision. That is a subtle enclosure bug avoided by construction.

The source comments are unusual in a way worth stating plainly: they record
*measurements and their reversals*, not just intent. `dyadic.jl:219-243` records
a 1.87× "win" that inverted to a 20% loss when the harness was fixed, and says
which conclusion survives and why. That is more valuable than most design docs.

### Where the source and the doctrine disagree

`CLAUDE.md` invariant 9 says "policy is dispatch, never a branch." Three places
depart from it, in descending order of how much it matters:

- **`saturate` returns a `Symbol`** (`project.jl:365-431`). The whole ωSaturate
  decision — six outcomes — is encoded as `:asis`/`:mhi`/`:mlo`/`:pinf`/`:ninf`/
  `:nan`, produced by an `if`/`elseif` chain over `sat isa SatFinite` and
  consumed by a `===` chain in `project`. Both the saturation mode and the
  rounding mode are static type parameters there, so this should fold — but it
  is the one stringly-typed protocol at the centre of the single write path, and
  it is the one place where a typo in a symbol is a runtime fall-through to
  `nan` rather than a `MethodError`. It is also the shape invariant 9 was
  written against.
- **`show_binary` branches on a `Symbol` style** (`show.jl:90-106`), and
  `binary_show_style` re-validates the style against `VALID_SHOW_STYLES` on
  every `show` call. Display is explicitly "a view, never a semantic", so this
  costs nothing that matters — but it is a branch on a policy value, and the
  doctrine does not carve display out.
- **`_bp_element` branches on `res isa Float64` / `isa Float128` / `isa
  Enclose128F` / `isa EncloseF`** (`blocks.jl:189-232`). Here the values are
  genuinely dynamic (the oracle's result kind is a union decided at runtime), so
  a branch is defensible — but the sibling method one screen down
  (`blocks.jl:250-256`) *is* written as dispatch on the scale's carrier, with a
  comment explaining why dispatch was the right choice there. The two halves of
  the same function disagree about the rule.

Invariant 8 ("format types are propagated, never rebuilt") is enforced
textually by `stage_gates.jl` and I found no violation.

---

## Defects

### D1 — `f32_exact` raises `InexactError` for every format with K ≥ 9

`src/tables.jl:458`:

```julia
for c1 in 0x00:UInt8((1 << bitwidth(f1)) - 1), c2 in 0x00:UInt8((1 << bitwidth(f2)) - 1)
```

`UInt8((1 << 9) - 1)` is `UInt8(511)`, a *checked* conversion, so
`f32_exact(:Add, Binary9p4se, Binary9p4se)` throws `InexactError` before the
enumeration begins. The function is exported (`SmallFloats.jl:205`), documented
in `docs/other/Float32inside.md`, and has no consumer inside `src/` — so this is
a user-facing surface that fails on **384 of 504 formats**, with an error that
names `UInt8` rather than the format.

This is the exact failure mode `formats.jl:236-248` argues against for
`_checkcode`, in the same words: "the caller's error is about the *format*", not
about the representation. And it is what `juliacompat.jl`'s `_unsupported`
(`juliacompat.jl:116-118`) exists to make impossible — "absence and refusal must
not look alike."

The roll-call's uncovered list (`test/rollcall.jl:75`) reads "`f32_exact`'s
enumeration at K ≥ 12, per its section 9 disposition", which implies the K = 9,
10, 11 cases work. They do not; and at K = 12 the honest answer is a budget
refusal, not an omission from a list. `test/float32surface.jl:126-128` scopes
its sweep to `_K8_FORMATS` deliberately, so nothing in the suite can see this.

There is also a real cost question underneath: at K1 = K2 = 16 the enumeration
is 2³² pairs at 300-bit `BigFloat`, which is not "memoized and cheap" — it needs
the same kind of budget the table cache already has.

*Confidence: high — the conversion is unconditional and the argument is a
compile-time-known integer.*

### D2 — the suite runs permanently reduced loop counts, with a dead switch

`test/runtests.jl:46-73`:

```julia
# Main.FastTest = true
#
# if isdefined(Main, :FastTest)

const K5  = div(5000, 5)
const K4B = div(4096, 4)
const K4  = div(4000, 4)
...
#else
#=
const K5  = 5000
...
=#
#end
```

The `if` is commented out, the `else` branch is inside a block comment, and the
divided values are the only reachable ones. These constants drive ~30 sampling
loops in `runtests.jl` — the sort/packed/kernel/Convert/rand axes among them
(lines 729-763, 1283-1358, 1621-1630). `SMALLFLOATS_TIER=release` does **not**
restore them: `formatsel.jl`'s tier machinery governs the *format* axis only, and
these constants are read by nobody in that machinery.

`CLAUDE.md`'s verification doctrine states: "A tier the caller asks for is
**honoured, never downgraded**: a gate that quietly runs less than it was told to
is worse than no gate." This is that, structurally — there is no spelling of the
release tier that runs the counts the suite was written with.

One nuance worth stating precisely, because it changes what the fix is: the
division landed in `a0913ef` (2026-07-29) and the "35 332 465 compared units"
figure in `CLAUDE.md` was written in `b06feb5` (2026-08-02). The figure is
therefore *current* — it was captured under the divided counts. The defect is
not a stale number; it is that the undivided counts are unreachable and the
comment at line 1329-1331 ("derived from K5 so it tracks the FastTest scaling")
documents a mode that no longer exists.

*Confidence: high — mechanical reading of the file.*

### D3 — `eps(x::Binary)` is a bare `MethodError`

`formats.jl:505` defines `Base.eps(T::Type{<:Binary})`. There is no value form,
and no `Base.ldexp(::Binary, ::Integer)`. Julia's fallback
(`base/float.jl:983`) is:

```julia
eps(x::AbstractFloat) = isfinite(x) ? abs(x) >= floatmin(x) ?
    ldexp(eps(typeof(x)), exponent(x)) : nextfloat(zero(x)) : oftype(x, NaN)
```

For any finite value at or above `floatmin` — the common case — this reaches
`ldexp(::Binary, ::Int)` and dies with a `MethodError` naming `ldexp`, at the
user's call site. The subnormal and non-finite rows happen to work
(`nextfloat` and `oftype` are both provided).

G10's veneer sweep (`test/gates_g10.jl:207-235`) is admirably broad — `hash`,
`decompose`, `frexp`, `significand`, `reinterpret` round-trip, `Dict` keys,
`Set` elements — and `eps` is simply not in the list. Neither is `ldexp`, which
is the more useful of the two to have: scaling by a power of two is exact for
every format, so it is a method the package can offer without rounding outside
`project`.

`docs/other/morejulian.md`'s Tier-1 argument applies verbatim: this is a method
generic Julia code reaches for without asking.

*Confidence: high — no definition exists in `src/`, and Base's fallback is as
quoted.*

### D4 — `datumsexact`'s unsigned `emax` is arithmetically wrong

`carriers.jl:283-288`:

```julia
emax = S ? B - 1 : 0
```

with the docstring claiming (`carriers.jl:275-278`) that "an unsigned format
spends its whole exponent field below 1, so `Binary16p1uf`'s datums run down to
`2^-32769` while its largest is `0.5`."

That is not what the package's own decoder does. For `Binary8p4uf`
(K = 8, P = 4, unsigned, finite): `expbias` = 2^(K−P) = 16;
`MaxFiniteOf` = codemask − 1 = 254; `_decode_compute` gives `Eb` = 254 ≫ 3 = 31,
`tsig` = 6, `sig` = 14, `e` = 31 − 16 + (1 − 4) = 12, so the largest datum is
14·2¹² = 57 344, whose exponent is **15 = B − 1**, not 0. The same computation
for `Binary16p1uf` gives a largest datum of 2³²⁷⁶⁶ and a smallest positive of
2⁻³²⁷⁶⁷ — three orders of magnitude away from the docstring's "0.5" and
"2⁻³²⁷⁶⁹". The correct expression is `B - 1` for both signedness classes (it is
`B - 2` for the P = 1 unsigned formats, so `B - 1` remains a sound upper bound).

**Currently this changes no answer**, and the reason is worth recording because
it is why nothing caught it: for each of the four types in `_extexprange`, the
subnormal condition `2 - P - B ≥ lo` binds strictly before the normal-range
condition would, at every power-of-two bias. Checked exhaustively by hand:

| target | `lo` ⇒ `B ≤ 2−P−lo` | `hi` ⇒ true `B ≤ hi+1` | power of 2 in the gap? |
|---|---|---|---|
| `Float64` | B ≤ 1076−P | B ≤ 1024 | none |
| `Float32` | B ≤ 151−P | B ≤ 128 | none |
| `Float16` | B ≤ 26−P | B ≤ 16 | none |
| `BFloat16` | B ≤ 135−P | B ≤ 128 | none |

The margin is exactly zero in every row: at B = 1024 the true `emax` is 1023 and
`Float64`'s `hi` is 1023. So the gate is correct today by coincidence of the
IEEE exponent/precision relationship, and the first wider external type added to
`_extexprange` — `Float128` is already imported and already appears in a
`datumsexact` reference at `formats.jl:602` — walks straight into a
`decode!` that promises exactness and delivers `±Inf`.

The bright side: because the fix changes no current answer, it is free to make
and mechanically testable against the extremal datums.

*Confidence: high on the arithmetic; high on "benign today" for the four listed
types; the `formats.jl:602` comment already names a fifth.*

### D5 — `measure_kappa`'s docstring is false under K ≤ 16

`approx.jl:46-53`: "Enumerates the full input cross-product when it has at most
`max_exhaustive` points (**always true for arity ≤ 2**)."

With `max_exhaustive = 2^22`, a binary specialization over two K = 16 formats is
2³² points and falls to the 2²⁰-sample path. The mechanism is fine — κ is a
measurement, `exhaustive=false` is reported, and `conformance_report` prints
"(κ sampled — not exhaustive)". Only the parenthetical is a K ≤ 8 leftover, and
it is exactly the kind of claim `CLAUDE.md`'s review section says should be
checked by something.

### D6 — dead code and small asymmetries

- **`formats.jl:463-482`**: a commented-out `Base.show(io, ::Type{<:Binary})`
  and `Base.show(io, ::Binary)` pair, superseded by `show.jl`. `show.jl:121-122`
  explains why the duplicate was removed (method overwriting is an *error*
  during precompilation, which silently un-precompiled the package). Keeping the
  corpse in a `#= =#` invites its resurrection; the reason belongs in the
  changelog, not in the file it broke.
- **`Convert(fr, ρ, A::AbstractArray{<:Binary})`** (`kernels.jl:170-171`) takes
  no `rng` keyword, while the scalar `Convert` and every generated array
  operation do. A stochastic bulk `Convert` therefore works but cannot be given
  an owned stream — the one thing `defaults.jl`'s entropy decision says callers
  should do.
- **`add_dy` has no `add_dy_checked` twin.** `dyadic.jl:261-262`'s
  `_add_aligned` computes `big.S << d` with `d` up to `DYADIC_ALIGN_MAX = 94`,
  sound only while the head carries ≤ `DYADIC_HEAD_BITS = 32` bits. That
  precondition holds for everything the engine forms, and the module exports
  `add_dy` anyway. `mul_dy`'s two-name resolution is the right pattern and is
  applied to only one of the two operations that needs it.
- **Threading is ternary-only.** `THREADED_KERNELS` / `THREAD_MIN_ELEMS`
  (`kernels.jl:69-72`) are consulted in exactly one loop
  (`kernels.jl:90-97`). The unary and binary Shape-B compute loops — reached
  whenever a table is declined, which is now the *common* case at K ≥ 9 — never
  thread. That is a defensible scope limit but it is not what the two
  package-level `Ref`s' names suggest.

---

## Verification

The design is the strongest part of the package's engineering, and the parts I
can check statically hold up:

- The tier machinery in `test/formatsel.jl:171-207` is well-built: an explicit
  `SMALLFLOATS_G5` / `SMALLFLOATS_G10` / `SmallFloats_EXHAUSTIVE` always wins
  over the suite-wide dial, so a caller can widen one axis without moving the
  tier, and the `@info` lines name the tier that produced the numbers.
- `gates_g10.jl` is the right kind of gate: shallow, total, and explicitly
  refusing to be deepened. Its veneer list sweeps *what the subtype promises*,
  not what the package implements — which is the correct choice and the reason
  it found the missing `Float16` conversion.
- `rollcall.jl` printing the knowingly-uncovered list on every green run is a
  genuinely good idea, and the list is honest about the T2b/G10/ρ format axis
  being sampled.
- `REQUIRED_GATES` being a *named* list rather than a derived one
  (`gatelog.jl`) is the right call for the stated reason: a list derived from
  what ran cannot detect what did not run.

Gaps, beyond D2:

- **The uncovered list has one wrong entry** (D1's `f32_exact` line) and does
  not mention `eps`/`ldexp`.
- **G10's `_PROBED` set is `rep` by default** — one representative per realized
  `(rung, P == 1?, code unit)` class. That is stated, so it is within doctrine;
  but combined with G10 being the *only* totality gate, the default tier's
  totality claim covers a sample of formats rather than the grid. The `full`
  tier exists and the release workflow selects it, which is the right
  arrangement.
- **No test asserts `datumsexact` against the actual extremal datums.**
  `float32surface.jl:20-21` *uses* it to build its format lists, so a wrong
  answer would silently narrow the sweep rather than fail it. D4 survived for
  exactly that reason.

---

## Performance evidence

The report (`benchmarking/benchmark_report.md`, 2026-07-30, Julia 1.12.6,
alderlake, 1 thread) is methodologically sound and its headline numbers are
strong: `decode` 1.6 ns, `project` 6.7 ns median, `Add⟨Binary8p4se⟩` 9.0 ns,
unary table gather 0.13 ns/element, and **zero allocations on every scalar row
in every operand class**. The four-operand-class split (safe / no-NaN-Inf /
no-NaN / all code points) is better practice than most numeric packages manage.

Two limits, both unchanged from the previous review:

**No wide-format coverage whatsoever.** Grepping the report for `Binary9`
through `Binary16`, for `rung`, `HeadF128`, `HeadExact`, or `Dyadic` returns
nothing. The "Format sensitivity" section measures `Binary8p4se`, `Binary8p3sf`,
`Binary8p1uf`, `Binary5p2se`, `Binary3p1se` — all rung 1, all K ≤ 8. The package
ships three carrier rungs, 504 formats, and a documented rung-2/rung-3
allocation contract (`CLAUDE.md`'s benchmark doctrine explicitly tabulates when
arithmetic allocates), and **none of it is measured**. The one number that would
most inform a user's format choice — what the rung-2 and rung-3 cliffs actually
cost — is absent.

**No reproducibility metadata.** No commit SHA, no dirty-tree state, no
benchmark-suite revision. The report says "regenerate with …" but a reader
cannot tell which source produced these numbers.

The report does identify its own optimization targets honestly: `BlockAdd`
(35 allocs, 1.17 µs at B = 32) and `ConvertToBlockMaxAbsFinite` (111 allocs,
3.95 µs) are the two rows with allocation counts that look structural rather
than escalation-driven.

---

## Public interface and Julia integration

The `AbstractFloat` contract work in `juliacompat.jl:95-257` is the best part of
the Julia-facing surface, and the reasoning is right throughout:

- `Base.decompose` reusing `round_to_precision` on an exact datum — "pure
  extraction, not rounding" — so `hash`/`isequal` consistency cannot drift from
  the engine's own normalization.
- `significand` deciding representability **from the format, statically**
  (`_binade0_complete`) rather than round-tripping each value.
- `round(x, RoundNearestTiesUp)` and `RoundFromZero` refused *by name*, with the
  reason and the list of modes that do exist.
- `rem`/`mod` refused with a pointer to what to do instead.
- `reinterpret` gaining the representation-invariant check that the idiomatic
  spelling previously bypassed.

Remaining interface observations:

- **`Op` is the right abstraction** and the generated-per-registry-row
  implementation (`juliacompat.jl:322-326`) is the right way to build it. The
  recorded measurement note — that a 48-byte reading was the harness's
  non-`const` global, not the code — is a good example of the benchmark doctrine
  applied to itself.
- **The export surface is still very large** (the 120 K ≤ 8 aliases, ~50
  registry operations, ~50 `Block*`/`Scaled*` names, the projection constants,
  the defaults, the cache introspection). The `Formats` opt-in namespace is the
  right pattern; the same pattern is not applied to the block surface, which is
  ~100 exported names most users will never call.
- **`Binary` is exported** while `CLAUDE.md` states subtyping it is not a
  supported extension point. That is still an unmarked invitation, though the
  docstring at `formats.jl:19-51` is clear about `Binary8p4se !== Binary{8,4,true,true}`.
- **`eps` aside** (D3), the `AbstractFloat` promise is well covered.

---

## Repository, release, and documentation

- **29 MB of generated LaTeX/PDF intermediates are tracked**: 472 files under
  `docs/pdf`, of which 251 are `_minted` fragments and 195 are PNGs. `.gitignore`
  covers `docs/build/` but not `docs/pdf/build/`. Every documentation rebuild
  produces a large, meaningless diff.
- **No tags.** `git tag` is empty at 0.4.0, with a CHANGELOG that reads like a
  release history and a `release.yml` that triggers on `tags: ["v*"]` — i.e. the
  release automation exists and has never fired.
- **README says the package is unregistered.** Consistent, but the technical
  maturity is well past that point.
- **Julia 1.12-only.** Justified or not, it is not justified *in writing*
  anywhere I found. (One real dependency I can name: `Base.ScopedValues`-backed
  `setprecision`/`setrounding`, which is what makes the MPFR escalations
  task-local and therefore safe under the threaded ternary kernel. That is a
  genuine 1.11-vs-1.12 semantic difference and deserves to be recorded as the
  reason.)
- The CI workflows are well-shaped: PR ⇒ quick, push/schedule ⇒ default,
  tag ⇒ release + conformance artifact + PDF. What they do not publish is
  machine-readable run metadata (Julia build, CPU, thread count, commit, tier,
  unit counts) alongside the roll-call log.

---

## Findings by priority

| Pri | Finding | Where | Consequence |
|---|---|---|---|
| High | `f32_exact` throws `InexactError` for K ≥ 9 | `tables.jl:458` | Exported, documented function fails on 384/504 formats with an error about `UInt8`; roll-call's uncovered list is wrong about it |
| High | Suite loop counts permanently divided; `FastTest` switch is dead code | `runtests.jl:46-73` | No tier — including `release` — can run the counts the suite was written with; contradicts the tier doctrine |
| High | `eps(x::Binary)` raises `MethodError` on `ldexp` | `formats.jl:505`, absent `ldexp` | Ordinary `AbstractFloat` verb fails at a user call site; G10's veneer list omits it |
| High | Benchmark report has zero K > 8 / rung-2 / rung-3 coverage | `benchmark_report.md` | The extension's whole cost structure is unmeasured; users cannot price a format choice |
| Med | `datumsexact` unsigned `emax = 0` is false | `carriers.jl:283-288` | Benign today with exactly zero margin; becomes an exactness-promise violation the moment `_extexprange` gains a wider type |
| Med | `saturate`'s `Symbol` protocol at the centre of the write path | `project.jl:365-431` | Stringly-typed policy where the doctrine requires dispatch; a mistyped symbol falls through to `:nan` |
| Med | 29 MB of generated PDF build products tracked | `docs/pdf/build` | Repository weight and review noise; no source value |
| Med | No release tags; `release.yml` has never fired | repo | Release automation and conformance artifacts are untested in practice |
| Med | Benchmark report carries no commit/dirty/suite-revision metadata | `benchmark_report.md` | Numbers cannot be tied to a source state |
| Low | `measure_kappa` docstring's "always true for arity ≤ 2" | `approx.jl:52` | False at K ≥ 12 pairs; the mechanism is correct, only the claim is stale |
| Low | Dead commented-out `Base.show` block | `formats.jl:463-482` | Invites resurrection of a defect the changelog already records |
| Low | Bulk `Convert` over `Binary` arrays takes no `rng` | `kernels.jl:170` | Stochastic bulk conversion cannot be given an owned stream |
| Low | `add_dy` has no checked twin; threading `Ref`s serve one loop | `dyadic.jl:204`, `kernels.jl:69-72` | Naming implies more generality than the implementation has |

---

## Verdict

The core is right and should not be touched. The K ≤ 16 extension was executed
with unusual discipline, and the carrier/representation split is the kind of
factoring that makes the *next* extension cheap rather than the current one
merely finished.

The remaining risk is entirely in claims that nothing executes: a function whose
domain is narrower than its signature, a tier whose name no longer matches what
it runs, a docstring that describes a format's range wrongly, an exactness gate
whose arithmetic is masked by a zero margin, and a performance story that stops
at K = 8 for a package that ships to K = 16. Every one of them is cheap to fix
and, more importantly, cheap to *pin* — which is the property that would keep
them fixed.

`doc/other/improved1.md` sequences that work.
