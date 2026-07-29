# Checkpoint — SmallFloats.jl

*Working record of the K ≤ 16 extension. Written 2026-07-29 against branch
`main` (`e1ea2aa`). Companion to [CLAUDE.md](CLAUDE.md) (the doctrine — what
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
| **0 — prerequisites and baseline** | **done except the golden capture** |
| **1 — traits, tags, T11 constants, audit fixes** | **partially applied, UNVERIFIED** |
| 2–9 | not started |

**Blocked.** The Bash safety classifier is unavailable, so `julia` cannot be
run. Only allowlisted commands (`echo`, `grep`, `wc`, `find`) pass. Nothing in
Stage 1 can be verified until that clears or
`.claude/settings.json` gains `"permissions": {"allow": ["Bash(julia:*)"]}`.

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

### Additive — cannot affect behaviour until wired in

| file | role | wired in? |
|---|---|---|
| `CLAUDE.md` | doctrine reconstituted: invariants 1–7 restored from `src/` statements and [extendingK.md §10](docs/other/extendingK.md); 8–10 added for the extension; layer order, performance rules, verification and benchmark doctrine | n/a |
| `src/carriers.jl` | `Head` tags, `carriertype` (instance **and** `::Type{H}` forms), `rung`, `datumcarrier`, `promotecarrier`, `_cnan`/`_cinf`/`_cninf`/`_czero`, `bigprec` | **no** — absent from `SmallFloats.jl`'s include list, so inert |
| `test/golden/harness.jl` | the G5 oracle: 15 sections over the K ≤ 8 observable surface | n/a |
| `test/golden/capture.jl` | writes `test/golden/k8.sha256`; refuses to overwrite without an explicit env override | n/a |
| `test/golden.jl` | gate G5; tier from `SMALLFLOATS_G5` ∈ {`fast`, `full`, `off`} | **no** — not yet `include`d from `runtests.jl` |
| `docs/other/implementextensions.md` | §11 execution log added (M1–M9); G5 tier table; Stage 0 step 0 | n/a |

### Live and UNVERIFIED — the risk

| file | change |
|---|---|
| `src/formats.jl` | representation trait block (`codeunit_type`, `codemask`, `decodepolicy`, `orderkeytype`, `reptype`, `_unitmask`, `DecodePolicy` tags); Group M signatures widened to `::Type{<:Binary{K,P,S,E}}`; every special and extremal code point rebuilt by complement construction (T11) |

All eight rewritten constants were hand-checked against the originals for
K ≤ 8 and match: `signmask` = `2^(K−1)`; `nan_code` = `signmask` (signed) /
`codemask` (unsigned); `posinf_code` = that − 1; `neginf_code` = `codemask`;
`MaxFiniteOf` = (`signmask`|`codemask`) − (2 if Extended else 1) across all
four rows; `MaxSubnormalOf` = `2^(P−1) − 1`; `MinNormalOf` = `2^(P−1)`.

**Hand-checking is precisely what G5 exists to replace.** Stage 1's whole claim
is that it is *provably* zero-behaviour-change, and that proof is unrun. To
restore a known-green tree: `git checkout src/formats.jl`. Everything else
listed above stands on its own.

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

The last figure is the one that shaped the design: it is why G5 is tiered
(M2) and why ρ-breadth over the operation catalogue is bought on a derived
representative subset rather than on all 120 formats (M4).

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
touched it and have not run it. It needs a disposition before Stage 2, because
a second copy of the suite is exactly the divergence risk invariant 7 exists to
prevent — and G5's value depends on there being one oracle, not two.

### O3 — the four Stage 0 decisions are still open

From [implementextensions.md §9](docs/other/implementextensions.md): export
surface (recommend opt-in `SmallFloats.Formats` submodule), `f32_exact`
disposition (recommend restrict to K ≤ 11 by construction),
`DefaultAccumulatorType` disposition (recommend wire into the reduction
accumulator), `PackedVector` at K = 16 (recommend refuse loudly). Stage 1
touches the first three.

### O4 — stale rename artifacts

`docs/build_latex/ByteFloats.jl-0.1.0.tex` and `docs/pdf/ByteFloats.pdf`
survive the rename and feed the released PDF. `README.md` is two lines and
states no format count or bitwidth range. Stage 9.

---

## 6. Next actions, in order

1. **Unblock `julia`** — `.claude/settings.json` with
   `{"permissions": {"allow": ["Bash(julia:*)"]}}`.
2. `using SmallFloats` — does `formats.jl` compile?
3. `Pkg.test()` — is Stage 1 so far zero-behaviour-change?
4. **Capture the golden** (`julia --project=. test/golden/capture.jl`) — note
   this must run against a tree that is *semantically* pre-refactor. The
   `formats.jl` edits are asserted zero-change; if step 3 passes they qualify,
   but the cleaner sequence is to capture from a stashed clean tree and then
   re-apply. **Decide this before capturing** — a golden captured after an
   unverified edit is not an oracle.
5. Finish Stage 1: `_decode_compute` reshape to `(::Type{F}, c)` returning
   `datumcarrier(F)`; A1 fix in `approx.jl:60`; delete the dead
   `_cmp_rounded_datum` ([`project.jl:237`](src/project.jl#L237), C8); wire
   `carriers.jl` into the include list and update the order comment; wire
   `test/golden.jl` into `runtests.jl`; write gate G9.
6. Stage 1 exit: **G5 `:full` byte-identical**, G9 green, suite green,
   benchmark baseline unmoved.

---

## 7. Standing risk

The single highest-value property in this project is that **G5 is captured from
a tree nobody has edited**. Item 4 above is the one place that property can be
lost quietly, and it can only be lost once.
