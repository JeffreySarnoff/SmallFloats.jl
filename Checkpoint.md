# Checkpoint — SmallFloats.jl

*Working record of the K ≤ 16 extension. Opened 2026-07-29 against `main`
(`e1ea2aa`); current through **Stage 5** on branch `k16-extension`. Companion
to [CLAUDE.md](CLAUDE.md) (the doctrine — what
must stay true) and [docs/other/implementextensions.md](docs/other/implementextensions.md)
(the plan — what to do and in what order). This file is the third thing: **what
has actually happened, what is verified, and what is not.***

> **On the name.** `src/` and `test/` contain **nine references to a
> `checkpoint.md` that does not exist in this repository** — see
> [Open item O1](#o1--nine-dangling-checkpointmd-references). The original was
> the running design-decision record and was lost in the copy from
> `ByteFloats.jl`, exactly as `CLAUDE.md` was. This file takes the name and the
> role forward; it does **not** reconstruct the lost content, which is recorded
> below as an open item rather than invented.

---

## 1. Position

| stage | state |
|---|---|
| **0 — prerequisites and baseline** | **done** |
| **1 — traits, tags, T11 constants, audit fixes** | **done, verified** |
| **2 — representation lattice (abstract `Binary` + `Code8`)** | **done, verified** |
| **3 — `Code16` and the 504-format grid** | **done, verified** |
| **4 — decode/encode/keys/sort/packed widened** | **done, verified** |
| **5 — table and kernel policy** | **done, verified** |
| 6–9 | not started |

**Stage 5 evidence.** Array operations work at every K. A K = 16 unary op runs
the table gather on a `Memory{UInt16}` at **0.16 ns/elem**; a K = 16 binary op
(2^32 entries) runs the scalar path per element; nothing attempts an impossible
allocation. The narrow path is unchanged at **0.22 ns/elem**, zero allocation.

Two caches, split by result code unit and reached by dispatch, because a single
`Dict` holding both widths returns a `Union` from `get_table` and puts a type
check inside every hot loop. Two budgets, because "may we allocate this" is a
question about **bytes** and "is it worth building" is a question about
**entries** — a `UInt16` table is twice the bytes of a `UInt8` table with the
same entry count and costs exactly the same to build (§11 M25). The byte budget
is compared as bits and never computes `1 << ΣK`, which is the bug it exists to
prevent.

New gate **Shape A ≡ Shape B** ([test/gates_shape.jl](test/gates_shape.jl)):
920 signatures, **2 503 312 element comparisons**, exhaustive over each
signature's input space, every arity, both sides of the code-unit seam. This is
the stage's central claim — from here on, which shape a kernel takes is a
*policy* decision that may differ between machines or after a cache eviction, so
"policy never decides an answer" has to be measured, not argued from invariant 6.

**Two of this stage's own plan items were withdrawn on measurement.** Parallel
build and a cost-aware eager band both target a first-call latency I had
estimated at ~200 µs/entry; measured, a 65 536-entry K = 16 table builds in
**0.085 s** (~1 µs/entry). The 200 µs figure is the rigorous MPFR ladder cost
from the golden capture, and the ordinary path rarely reaches the ladder.
Threading the one function invariant 6 makes every result depend on, to save
0.08 s, is not a trade worth making.

**One real defect found, by a table build rather than by a test** (§11 M28):
Stage 3's rung-2/3 refusal fires *inside* `apply_op`, so it required `Float64`
operands to be reached. Stage 4 made `decode` return wide carriers, and from
that moment same-format wide arithmetic missed `apply_op`'s signature entirely
and raised a `MethodError`. Open for a full stage because the existing gate row
used narrow operands with a wide result — a different route to the same
refusal. Now closed by method, with both routes covered.

**Stage 4 evidence.** `decode` is exact at every K: the carrier-generic `ldexp`
path lands under `ComputeDecode`, and the Float64 bit assembly is kept — by
signature, on `Code8` — where its `|e + nb − 1| ≤ 260` premise actually holds.
**Group A is operational at every K**, measured rather than asserted:
[test/wide_ops.jl](test/wide_ops.jl) recomputes 321 984 results on the 312 wide
rung-1 formats from the draft definition in MPFR and compares code points. That
reference shares `project` with the code under test — the projection engine is
carrier-generic and untouched (§1 C10) — and shares nothing with `decode`'s new
path or the Float64 evaluation route, which are what this stage changed.

**G3** green over **135 `(P, B)` cells**, 4 839 210 bit-vs-generic comparisons.
The domain is wider than the plan specified: every pair the grid realizes, up to
B = 32768, because `Convert(F, ρ, x::Float64)` sends a Float64 into *any* format
(§11 M22). **G6** green over **19 976 144 `(datum, head)` pairs**, exhaustive,
and asserts the *absence* of every narrowing `lift`. G5 33/33 byte-identical.
Warm scalar paths allocate zero on wide formats as well as narrow.

The `Float32`/`BFloat16` surface is now three contracts instead of one accident:
`decode` is exact, `decode!` is exact in bulk and **refuses** rather than
rounding, `Float32(x)` rounds like any Julia conversion. The refusal gate is
`datumsexact` — 454 formats for Float64, 376 for Float32, 244 for BFloat16 —
and the suite tests the gate's **boundary**, so a conservative trait that
refused too much would fail (§11 M24).

What Stage 4 deliberately leaves refused, with the stage named in the message:
tabulated/array routes at wide K (Stage 5), and rung-2/3 arithmetic (Stage 6).
[test/stage_gates.jl](test/stage_gates.jl) pins both.

**Stage 3 evidence.** The grid is open: `KMIN:KMAX` = 3:16, 504 formats, per-K
counts `4K − 2`. The front-loaded construction sweep
([test/sweep_lattice.jl](test/sweep_lattice.jl)) builds **every code point of
every format — 7 602 160 points** — through both the checked constructor and the
unchecked kernel route, at every offered `Unsigned` width, in 10 s. §1 C5's
finding (the silent-truncation hazard class is empty) is now a measured property
rather than a reading of the source.

Everything wide that is not yet implemented **refuses**, and
[test/stage_gates.jl](test/stage_gates.jl) asserts the refusals: rung-2/rung-3
arithmetic, wide `decode`, and the `2^K`-entry constant table. `rung` itself
stays total over all 504 formats — the missing thing is the evaluator, not the
answer. That file is designed to shrink; a row going red *because the operation
started working* is how it is meant to die — *and the wide-`decode` row did
exactly that one stage later, which is the mechanism working as intended.*

Two Stage 4 items moved here (§11 M16) on a hazard-class rule — **loud waits,
silent does not**: `order_key` wrapped `UInt16` to 0 at K = 16, inverting the
total order with no exception, and the counting sort had to move with it.

**G5 33/33 byte-identical** through the grid opening; G9 4 290 assertions,
now asserting both halves of the lattice (120 narrow unchanged, 384 wide, and
that a K = 16 format can sit on **any** rung); Aqua and both JET passes green
with no new filter. Warm scalar paths still allocate zero; `vmap!` on the table
path 0.26 ns/elem.

**Stage 2 evidence.** Full suite green (3 m 23 s), **G5 `:full` — all fifteen
section digests byte-identical to the `51abb00` oracle** (11 m 26 s), zero method
ambiguities (Aqua + `detect_ambiguities`). The first `:full` run reported three
failures; they were the gate's own completeness loop comparing the oracle's 18
entries against the 15 that `:full` computes, not moved results (§11 M15). Three
deliberate, documented breakages landed and are pinned by rewritten tests:
`Binary8p4se === Binary{8,4,true,true}` is now `false` (the alias is the
*representation*, the parameterized name is the *format*); every `Unsigned` at
every width is a code point (restated invariant 2); and the abstract format
prints as `Binary8p4se{format}` so it cannot be confused with its
representation in an error message.

**Stage 1 exit evidence.** Full suite green (~8.9 M assertions + G9 + G5-fast +
Aqua + JET, 3 m 01 s). **G5 fast 7/7 byte-identical** against a golden captured
from a clean `main` worktree at `51abb00` (M11) — so the oracle is independent
of the code it judges. G9 green at 1 212 assertions. Every special and extremal
constant verified byte-identical to its pre-T11 formula across all 120 formats,
independently of the golden.

---

## 2. Repository state, file by file

### Verified (ran, passed)

| file | change | evidence |
|---|---|---|
| `Project.toml` | `Julia` → `julia` in `[compat]`; `author` → `authors`; `SHA` added to `[extras]`/`[targets]` | `Pkg.instantiate()` succeeds; package precompiles in 2.4 s; **full suite passes, ~8.9 M assertions, 2 m 33 s** |

**This was a hard blocker, not a tidy-up.** Pkg rejects a `[compat]` key that
is not a declared dependency, and `Julia` is not `julia`. Before the fix,
`Pkg.instantiate()` failed and therefore so did every `using`, every test, and
every measurement. The tree as inherited did not build.

### Test surface added by the extension

Every file below is `include`d from `runtests.jl` and runs on every `Pkg.test()`.

| file | role | scale |
|---|---|---|
| `test/golden/harness.jl` + `capture.jl` + `k8.sha256` | the G5 oracle, captured from a clean `main` worktree at `51abb00`; 18 section digests over the K ≤ 8 observable surface | see `test/golden.jl` |
| `test/golden.jl` | **G5** — K ≤ 8 golden non-regression. Tier from `SMALLFLOATS_G5` ∈ {`fast`, `lazy`, `full`, `off`}, default `lazy`; a requested tier is never downgraded | 33 assertions, 4 m 21 s at `lazy` |
| `test/gates_g9.jl` | **G9** — trait folding over all 504 formats, plus the narrow/wide zero-behaviour-change pin | 4 290 |
| `test/gates_g3.jl` | **G3** — `_rtp_f64` bit ≡ generic over every realized `(P, B)` | 135 cells, 4 839 210 comparisons |
| `test/gates_g6.jl` | **G6** — carrier-lift exactness, and the *absence* of every narrowing `lift` | 19 976 144 (datum, head) pairs |
| `test/gates_shape.jl` | **Shape A ≡ Shape B** — the table gather and the scalar path agree, at every arity | 920 signatures, 2 503 312 comparisons |
| `test/sweep_lattice.jl` | the front-loaded construction sweep: every code point of every format, both construction routes, every `Unsigned` width | 7 602 160 points |
| `test/wide_ops.jl` | Group A at every K against an MPFR reference; ordering and counting sort at wide K | 321 984 results |
| `test/stage_gates.jl` | what is **not** implemented yet, asserted to fail loudly and to name its stage. Designed to shrink | 1 146 |

### Source state

| file | role after Stage 4 |
|---|---|
| `src/formats.jl` | `KMIN`/`KMAX`/`KSPLIT`; abstract `Binary` + `Code8`/`Code16`; the representation traits and their abstract-format forwarders; T11 constants via the single `_cu` narrowing point; `_checkcode` before every narrowing; `show` (incl. the `_shortdatum` display-precision fix) |
| `src/carriers.jl` | `Head` tags, `carriertype` (both forms), `rung`, `datumcarrier`, `promotecarrier`, the `_c*` constants, **`lift`** (one direction only), **`datumsexact`**, `bigprec` |
| `src/decode_encode.jl` | `decode` by `decodepolicy`; `_decode_compute` with the carrier-generic `ldexp` tail and the `Code8`-only bit assembly; `_decode_table` bounded to `Code8` by signature with a throwing `Code16` method; `order_key`/`nan_order_key` on `orderkeytype`; counting sort with the `n < 2^K` gate |
| `src/oracle.jl` | per-head `ωeval` dispatch (rung 1 forwards, rungs 2–3 refuse); `ωeval(::Val{:Convert}, ::Float64) = x` |
| `src/kernels.jl` | `decode!` gated on `datumsexact`, split by `decodepolicy` |
| `src/tables.jl` | two caches by result code unit; the byte budget (`TABLE_MAX_BITS`) and the build band (`TABLE_EAGER_BITS`); `table_for` (policy) beside `get_table` (total-or-throw); `table_policy` introspection; builders widened |
| `src/kernels.jl` (2) | conditional Shape A at every arity — `tbl === nothing` falls back to the scalar path |
| `src/packed.jl` | code unit via `_cu`; `packing_saves` predicate |
| `src/project.jl` | `_extremal_SQ` width-safe; `_rtp_f64` shift-bound comments corrected (`d ≤ P−1 ≤ 15`, `t ∈ [37, 52]`) — the claim itself is licensed by G3, not by the comment |

---

## 3. Measurements recorded

| quantity | value | conditions |
|---|---|---|
| full suite | ~8.9 M assertions, **2 m 33 s** | Julia 1.12.6, `Pkg.test()`, pre-refactor tree |
| package precompile | 2.4 s | cold |
| package load | 0.39 s | warm |
| G5 full capture (first attempt) | **13 min**, then failed | see M2, M6 |
| G5 section cost — `project` | 33 s | 120 formats × 27 ρ × structured input set |
| G5 section cost — `convert` | 10.4 s | 120 formats × 5 sources × all codes × 4 ρ |
| G5 section cost — meta/decode/lattice/order | 3.6 / 1.5 / 2.1 / 2.6 s | all 120 formats, exhaustive |
| oracle trip, MPFR-backed unary | **~200 µs/entry** | derived: 13 min / ~3.7 M entries |
| lattice sweep | 7 602 160 points, **10 s** | 504 formats, both construction routes, 4 `Unsigned` widths |
| G3 | 4 839 210 comparisons, **1.1 s** | 135 `(P, B)` cells × structured inputs × 15 (μ, R) |
| G6 | 19 976 144 (datum, head) pairs, **27 s** | exhaustive; `Base.decompose` witness |
| `wide_ops` (Group A at every K) | 321 984 results, **50 s** | 312 wide rung-1 formats, MPFR reference |
| Shape A ≡ Shape B | 2 503 312 comparisons, **64 s** | 920 signatures, exhaustive per signature |
| table build | **~1 µs/entry**; 65 536-entry K = 16 table in **0.085 s** | the figure that withdrew two plan items |
| `vmap!` Exp, K = 16 (Shape A, `UInt16`) | **0.16 ns/elem** | 0 allocations |
| `vmap!` Add, K = 12 (Shape B) | **18.9 ns/elem** | 0 allocations; 2^24 entries, over the build band |
| G5 `:lazy` | 33 sections, **4 m 21 s** | the routine stage-exit tier |
| G5 `:full` | 33 sections, **11 m 20 s** | Stage 2 exit and release only |
| warm scalar path, narrow **and** wide | **0 allocations** | `Add`/`Exp`/`decode` behind a function barrier |
| `vmap!` Add, K = 8 | **0.26 ns/elem** | unchanged across Stages 2–4 |

The **oracle trip** figure is the one that shaped the design: it is why G5 is
tiered (M2) and why ρ-breadth over the operation catalogue is bought on a
derived representative subset rather than on all 120 formats (M4).

The rows below it say something worth noticing about where the cost actually
falls. The exhaustive sweeps are *cheap* — 7.6 M constructions in 10 s, 20 M
lift checks in 27 s — because they are pure integer and float work. Everything
expensive in this suite is expensive for exactly one reason: it calls MPFR.
That is why `wide_ops` costs 50 s for 322 k results while G6 costs 27 s for
20 M, and it is the standing argument for enumerating aggressively wherever a
reference is *not* involved.

---

## 4. Decisions taken during execution

Recorded in full in [implementextensions.md §11](docs/other/implementextensions.md).
Summary:

- **M1** repository did not build; C9 understated the state of the rename.
- **M2** G5 tiered — `:fast` (~45 s, after every edit) / `:full` (~5 min, stage
  exit). A gate that costs minutes is a gate that gets skipped.
- **M3** the golden is a standalone harness, not instrumented testsets —
  couples the oracle to the package's behaviour, not the suite's structure.
- **M4** ρ-breadth on a **derived** representative format subset (for each
  `(K, Σ, Δ)`, the extreme and middle precisions), never hand-listed.
- **M5** no `conformance` section in the golden: `conformance_dict()` embeds
  `keys(TABLE_CACHE)` (nondeterministic) and the format list (Stage 3 changes
  it deliberately).
- **M6** `Convert` is registry arity 1 but group `:conv` — filter the registry
  by `(arity, group)`, never arity alone. **Stage 6's `factors` column will hit
  this same trap.**
- **M7** disposition-(a) signature widening moved Stage 2 → Stage 1. While
  `Binary` is concrete the two forms match the same type, so it is a no-op that
  G5 verifies — and it takes ~21 of 29 sites out of the riskiest commit's diff.
  *Generalized: any edit that is a no-op while `Binary` is concrete belongs in
  Stage 1.*
- **M8** `_cu(F, x)` as the single narrowing point for the storage unit.
- **M13/M14** `similar`'s abstract-format normalization is only implementable on
  the `Array` family (the `AbstractArray` spelling is ambiguous with every
  container-specialized `similar` in Base and the stdlibs — an open-ended set);
  every representation trait needs an exact `::Type{Binary{K,P,S,E}}` forwarder
  through `reptype`.
- **M15** G5's own completeness loop failed `:full` by construction, and a
  typo'd guard would have silently downgraded the tier Stage 2 mandates.
  **A gate that quietly runs less than it was told to is worse than no gate.**
- **M16** two Stage 4 items moved into Stage 3 on a hazard-class rule: **loud
  waits, silent does not.** A `UInt16` order key wraps to 0 at K = 16 and
  inverts the total order with no exception.
- **M17** unimplemented routes refuse by **method**, and the refusal must be a
  method that *throws* rather than one that is *absent* — an absent method turns
  a deliberate refusal into a JET defect that could only be silenced by a filter
  the doctrine forbids without a concrete-call gate.
- **M18** `Convert` given the ω-semantics it actually has (the identity on the
  datum), closing M9's registry trap instead of routing around it.
- **M19** the K ≤ 8 test surfaces were **scoped, not widened** — G5's oracle
  describes 120 formats and widening its list would invalidate every digest.
- **M20** `decode`'s return type is format-dependent, so `Base.Float64(v) =
  decode(v)` became wrong for 72 formats. Three surfaces, three contracts:
  `decode` exact, `decode!` exact-or-refuse, `Float32(x)` rounds.
- **M21** `PackedVector`'s planned "refuse at K = 16" fires on one of two
  identical cases (K = 8 is equally an identity), so it became the
  `packing_saves` predicate rather than an inconsistent rule.
- **M22** G3's domain widened to every realized `(P, B)` — a Float64 reaches
  *any* format through `Convert`, so the bit path runs at every bias.
- **M23** the tabulated path refuses wide formats **by name**, not by
  `InexactError` from three frames inside a builder. Its first spelling used
  `all(f, tuple)`, which is three-valued and infers `Union{Missing,Bool}`:
  **a predicate on types should never be able to return `Missing`.**
- **M24** `decode!`'s gate is `datumsexact`, not `datumcarrier` — 454 formats
  have Float64-exact datums but only 432 are rung 1, and conflating
  representation with arithmetic would refuse 22 formats wrongly.
- **M25** two budgets, not one: "may we allocate this" is about **bytes**, "is
  it worth building" is about **entries**. And the byte budget is compared as
  bits — deciding whether `1 << ΣK` is too large by computing `1 << ΣK` is the
  bug it exists to prevent.
- **M26** `get_table` throws, `table_for` returns `nothing`. One name per
  question; the `Union` costs nothing because kernels branch outside the loop.
- **M27** splitting a cache splits every consumer of it, silently — including
  `conformance()`, whose job is to report truthfully what is specialized.
- **M28** a refusal reached only *inside* `apply_op` is not reached by operands
  that never match `apply_op`'s signature. Stage 3's rung gate looked complete
  and was untestable-as-written until Stage 4 produced wide operands. Found by a
  table build, not a test.
- **Withdrawn on measurement:** Stage 5's own plan items 4 (parallel build) and
  5 (cost-aware eager band). The ~200 µs/entry figure behind both is the
  rigorous-ladder cost, not the ordinary path's ~1 µs.

---

## 5. Open items

### O1 — nine dangling `checkpoint.md` references

The lost document was load-bearing for three distinct kinds of content. Each
needs reconstruction or the reference needs removing; leaving a comment that
points at nothing is worse than either.

| site | what it referenced | kind |
|---|---|---|
| [`oracle.jl:22`](src/oracle.jl#L22) | `[interp]` markers — places where the readable draft text was unavailable and an interpretation was chosen | **normative-gap register** |
| [`approx.jl:13`](src/approx.jl#L13) | the κ-semantics interpretation (the Annex worked example, subnormal-flushing `Exp`, "κ = 4") | normative-gap register |
| [`ops_scalar.jl:136`](src/ops_scalar.jl#L136) | "Resolution of the two flagged measurements" — the 399 → 269 ns/elem split justification | **measurement post-mortem** |
| [`ops_scalar.jl:148`](src/ops_scalar.jl#L148) | the withdrawn rng-default performance claim (25.4 vs 26.5 ns/elem; the 1 347 ns reading was dynamic keyword dispatch in the harness) | measurement post-mortem |
| [`blocks.jl:19`](src/blocks.jl#L19) | the register-resident superaccumulator, tracked Phase-3 | **tracked optimization** |
| `runtests.jl:19`, `runtests1.jl:19` | assertion counts | suite bookkeeping |
| `runtests.jl:1286`, `runtests1.jl:1259` | measurement flags | measurement post-mortem |

Enough of the content survives *inline* (the two post-mortems are summarized in
the comments that cite them, and the benchmark doctrine made it into
`CLAUDE.md`) that the measurement items can be closed by folding the surviving
text into this file. The **`[interp]` register cannot** — it was a list of
specific draft-text gaps and the interpretations chosen, and that list is gone.
Rebuilding it means re-auditing `oracle.jl` against
[IEEE_D1.md](docs/other/IEEE_D1.md). Schedule with Stage 9.

### O2 — `test/runtests1.jl` is an unexplained near-duplicate

`test/runtests1.jl` (1 259 lines) was **not present** when the tree was first
surveyed at the start of this work; `test/runtests.jl` is 1 286 lines. It
appeared during the session. Its provenance is unknown to me, so I have not
touched it and have not run it. It needs a disposition, because a second copy of
the suite is exactly the divergence risk invariant 7 exists to prevent — and
G5's value depends on there being one oracle, not two.

**Still open after Stage 4, and now measurably diverged.** `runtests.jl` has
moved through four stages of edits; `runtests1.jl` has not been touched and
still assumes `K ∈ 3:8`, `UInt8` code points, and `Binary{K,P,S,E}` as a
concrete type. It would not run today. That makes it harmless as a live risk
and worse as a document — it reads like a suite and is a snapshot of a tree
that no longer exists. **Recommend deleting it** (git history keeps it) unless
its provenance turns out to matter.

### O3 — the four Stage 0 decisions are still open

From [implementextensions.md §9](docs/other/implementextensions.md): export
surface (recommend opt-in `SmallFloats.Formats` submodule), `f32_exact`
disposition (recommend restrict to K ≤ 11 by construction),
`DefaultAccumulatorType` disposition (recommend wire into the reduction
accumulator), `PackedVector` at K = 16 (recommend refuse loudly).

**One of the four is now settled the other way.** `PackedVector` at K = 16 does
*not* refuse: the rule cannot be stated without also refusing K = 8, which has
shipped and is enumerated by G5. It is a `packing_saves` predicate instead
(§11 M21). The export surface is now the most pressing of the remaining three —
the package exports **504** aliases into `Main`.

### O4 — stale rename artifacts

`docs/build_latex/ByteFloats.jl-0.1.0.tex` and `docs/pdf/ByteFloats.pdf`
survive the rename and feed the released PDF. `README.md` is two lines and
states no format count or bitwidth range. Stage 9.

---

## 6. Next actions, in order

*Stages 0–5 are done and committed; §1 carries the evidence. What follows is
the remaining work, in the order the plan puts it.*

1. **Stage 6 — the carrier lattice.** The only thing still refused for
   *semantic* reasons: rung-2 and rung-3 evaluation. `factors` as an `OpInfo`
   column, the `rung(op, Fs...)` join, per-head `ωeval`/`apply_op`, the
   corrected `_DE_*` thresholds (§1 C1, C2), and `bigprec` wired in. **Write G2
   red first** against the `Binary16p1uf` witness. `lift` already exists and G6
   passes over all 504 formats, so the join has a verified foundation. Watch
   M9/M18 (filter the registry by `(arity, group)`) and M28 (a refusal reached
   only through `apply_op` is not reached by operands that never match its
   signature).

2. **Stage 7 — `Dyadic`.** Swap the rung-3 carrier; G7 is the differential
   against the `BigFloat` implementation, which is free while both exist. This
   also retires the `show` precision workaround recorded in §11 M20.
3. **Stage 8 — test doctrine and tiers**, with G1–G9 standing.
4. **Stage 9 — docs, exports, benchmarks, release.** The `SmallFloats.Formats`
   submodule matters more now than when it was written: the package currently
   exports **504** format aliases into `Main`.

**Open items that should not wait for their stage:** O2 (`test/runtests1.jl`
has no established provenance and is not run by the suite) and O3 (the four §9
decisions). O1's dangling `checkpoint.md` references are cosmetic but multiply
with every stage that adds a citation.

---

## 7. Standing risk

The single highest-value property in this project is that **G5 is captured from
a tree nobody has edited**. That property was secured at Stage 0 (M11: a clean
`main` worktree at `51abb00`, with only the build fix and the harness copied in)
and has now been spent four times — G5 has passed byte-identical through the
carrier traits, the type refactor, the grid opening, and the decode rewrite. It
cannot be re-acquired; **do not recapture the golden.** A red G5 means a K ≤ 8
result moved, which is the thing this extension promises will not happen.

Two ways it could still be lost quietly, both now guarded:

* **widening `golden_formats()`.** Adding the 384 wide formats to the oracle's
  list would invalidate all 18 digests while looking like better coverage
  (§11 M19). The filter is `K ≤ KSPLIT` and is commented with the reason.
* **downgrading a requested tier.** A guard that silently rewrote `full` to
  `lazy` was found and removed at Stage 2 (§11 M15). `lazy` is the default; an
  explicit request is honoured.

The second standing risk is newer and belongs to the staged release: **the
package is shippable at every stage boundary and incomplete at all of them.**
What makes that safe is that every unimplemented route refuses with a message
naming the stage that finishes it, and `test/stage_gates.jl` asserts the
refusals. A route that starts returning a plausible number instead of throwing
— rather than a route that throws — is the failure mode to watch for.
