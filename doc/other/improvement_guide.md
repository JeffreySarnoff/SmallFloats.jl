# SmallFloats.jl Improvement Guide

## Purpose and method

This guide turns the conclusions in `reviewed.md` and `improved.md` into an implementation plan grounded in the current repository. It was prepared by tracing the relevant source, test gates, documentation build, and benchmark harness. No tests or benchmarks were executed while preparing it; the existing passing-suite status and checked-in benchmark reports are the baseline.

The plan deliberately protects the package's deepest modules:

- the format/representation seam in `formats.jl`;
- exact carriers and the oracle/result-kind protocol;
- the one-step `project` write path;
- typed `ProjSpec` specialization;
- the operation registry;
- the table-versus-compute kernel seam;
- exact block semantics.

Most improvements belong around those modules, not inside them. The goal is greater truthfulness, locality, reproducibility, and interface depth without weakening the exact-then-project contract.

## Implementation status

The first 0.4.0 tranche now implements the correctness and truth-source work in this guide:

- D1 `ArcTan2`/`ArcTan2Pi` special rows and affected golden sections;
- hierarchy-based rounding classification;
- package-version-derived conformance plus retained-draft identity;
- removal of inert RNG/Rbits defaults;
- corrected `with_default_*` documentation;
- removal of `rawvalue` and `DEFAULT_SHOW_STYLE` from exports;
- expanded documentation claim checks and an operational test guide;
- quick/default/release CI workflows;
- benchmark source provenance and representatives for both storage widths and all carrier rungs.

Allocation optimization, PDF source-bundle migration, full benchmark regeneration, and tagged release publication remain later work. They depend on evidence or external release state and should not be folded into the semantic/interface tranche.

## Decisions refined against the local design

Several broad recommendations need a more precise local answer.

| Topic | Local decision | Reason |
|---|---|---|
| RNG default | Remove/deprecate `DefaultRNG` and use Julia's task-local `Random.default_rng()` when no RNG is supplied | This is already the production behavior, composes with Julia, and avoids a second global entropy model |
| Random-bit default | Keep `DEFAULT_RBITS = 8` as a compile-time constructor default; remove/deprecate mutable `DefaultRbits` | `N` is part of `StochasticA/B/C{N}` and therefore part of specialization; a mutable default would make the projection type dynamic |
| Other session defaults | Retain for compatibility, but document them as process-global and recommend explicit `T`/`ρ` in library code | Their speculation guards and function barriers are deliberate performance engineering |
| `with_default_*` | Keep as default-consumption combinators; do not describe them as scoped setters | Their actual interface is `f(DefaultX(), args...)`; no scoped-mutation methods exist |
| Scoped projection policy | Prefer explicit `ρ`; do not add a process-global mutate/restore helper | Such a helper would remain concurrency-unsafe and would create a shallow convenience interface |
| Rounding taxonomy | Use the abstract hierarchy for classification and remove the private legacy unions | The hierarchy now exists and is exported; the unions are internal and already disagree about `ToOdd` |
| Code-point construction | Keep `T(c::Unsigned)` and checked `reinterpret`; do not add a redundant `fromcodepoint` immediately | The repository already has a checked, width-independent construction interface |
| `rawvalue` | Keep as an internal unchecked primitive but remove it from the public export surface in the next breaking release | Kernels need it; ordinary callers already have checked alternatives |
| Namespaces | Keep `Formats`; do not add `Ops`, `Blocks`, or `Approx` merely to mirror exports | The registry and top-level draft names already form a deep interface; duplicate namespaces would be shallow adapters |
| PDF build tree | Treat removal as an artifact-publication migration, not a blind deletion | `docs/pdf/build` is intentionally documented as an editable source bundle, even though tracking 467 generated files is costly |
| Performance work | Expand evidence before changing hot paths | Common scalar and gather paths are already excellent; current gaps concern carrier coverage and allocation-heavy paths |

## Non-negotiable invariants

Every implementation slice should preserve these invariants:

1. A defined operation computes the mathematical result and calls `project` once.
2. Deterministic projection does not read or advance RNG state.
3. Stochastic `N` remains visible in the type of the rounding mode.
4. An explicit `R` remains a deterministic testing and conformance route.
5. Table entries and compute kernels use the same scalar semantics.
6. Table policy may change cost, never code points.
7. `Binary{K,P,S,E}` remains the abstract format and `Code8`/`Code16` remain its representations.
8. The low-K bits/high-bits-zero representation invariant remains enforced at checked construction seams.
9. Carrier selection remains a proof-driven implementation choice, not a user accuracy knob.
10. Approximation remains opt-in through the κ registry.

These are the acceptance frame for all work below. If an improvement requires weakening one of them, stop and redesign the improvement.

## Workstream 0: resolve live D1 special-row contradictions

### Current implementation and retained draft

The retained mechanical transliteration at `docs/other/IEEE_D1.md` makes two current `[interp]` markers auditable. `CopySign` already agrees with its D1 special rows, including NaN in either argument. The `ArcTan2` family does not fully agree:

- D1 says `ArcTan2(0, 0) -> NaN`; `oracle.jl` returns `0.0`.
- D1 says `ArcTan2Pi(0, 0) -> NaN`; `oracle.jl` returns `0.0`.
- D1 says `ArcTan2(±Inf, ±Inf) -> NaN`; `oracle.jl` returns quadrant angles.
- D1 says `ArcTan2Pi(±Inf, ±Inf) -> NaN`; `oracle.jl` returns quadrant fractions.

The current tests explicitly expect `ArcTan2(0,0) == 0`, so a passing suite confirms the implementation's present interpretation rather than its agreement with the retained D1 text. This is the first item to resolve because every table, array, block, and scaled surface inherits the scalar oracle result.

### Implementation plan

1. Confirm that `docs/other/IEEE_D1.md` is the exact D1 source the package intends to implement. Its header says it is a mechanical markup conversion with wording unchanged; record that provenance in the standard descriptor proposed in Workstream 4.
2. In both `ωeval(::Val{:ArcTan2}, ...)` and `ωeval(::Val{:ArcTan2Pi}, ...)`, order the special rows exactly as D1 does:
   - NaN in either operand -> NaN;
   - both operands zero -> NaN;
   - both operands infinite -> NaN;
   - only then handle one-zero, one-infinite, and finite quadrant rows.
3. Keep D1's single-zero behavior for nonzero counterparts: `(0, x>0) -> 0`, `(0, x<0) -> π` or `1`, and `(y, 0) -> ±π/2` or `±1/2` for nonzero `y`.
4. Replace the current pins in `test/runtests.jl` and add all four sign combinations of `(±Inf, ±Inf)` for both operations. Exercise at least one finite and one extended result format so saturation/project behavior remains visible after the oracle row.
5. Update independent reference cases, table-versus-scalar cases, block/scaled surface checks, and golden digests that cover these inputs. Do not edit only the scalar expectation.
6. Remove the `[interp]` marker once behavior is directly prescribed by the retained text. Remove the `CopySign` marker as well if there is no remaining ambiguity; its current NaN rows already match D1.
7. Record the correction in `CHANGELOG.md` as a defined-result fix, including the affected code points/special operand classes.

Before changing behavior, inspect whether a newer working draft supersedes these rows. If it does, update the retained draft artifact and identity first; do not silently implement a different document than conformance reports.

### Acceptance criteria

- Scalar, table, array, block, and scaled entry points agree on every affected special row.
- The retained draft, oracle comments, tests, and changelog state the same result.
- No `[interp]` marker remains for behavior explicitly defined by the retained D1 source.
- Golden changes are limited to results transitively affected by the corrected special rows.

## Workstream 1: repair stochastic configuration truth

### Current implementation

The production entropy path is already coherent:

- `ops_scalar.jl::_resolve_rng(nothing)` returns `Random.default_rng()`;
- `_rng_for` returns `nothing` for deterministic projection;
- array loops resolve the RNG once outside the loop;
- `rand.jl` uses the same caller-supplied RNG for the source draw and stochastic conversion;
- an explicit `R` bypasses random drawing;
- stochastic projection constructors encode `N` in `StochasticA/B/C{N}`.

The incoherence is confined to `defaults.jl`: `_DEFAULT_RNG` and `_DEFAULT_RBITS` are stored and exported but never consumed by production operations. Wiring them in would be worse than removing them:

- `_DEFAULT_RNG` admits either an RNG type or instance, while `MaybeRNG` intentionally admits only `nothing` or an instance;
- instantiating an RNG type per operation would not provide one reproducible stream;
- sharing a process-global RNG instance would be unsafe across tasks;
- reading a mutable Rbits value would turn `RSA_SN()` from a concretely typed constructor into a dynamically selected `ProjSpec`.

### Implementation plan

Target a breaking pre-1.0 release, preferably 0.4.0, for removal.

1. In `src/defaults.jl`, delete `_DEFAULT_RNG`, `_DEFAULT_RBITS`, their accessors, setters, and the comment claiming they need no combinator.
2. In `src/SmallFloats.jl`, remove the four exports.
3. Keep `src/projspec.jl::DEFAULT_RBITS = 8` private and immutable. Keep `RSA_SF/SP/SN()`, `RSB_*()`, and `RSC_*()` as aliases for their `(...)(8)` forms.
4. Preserve every explicit constructor route: `RSA_SN(N)`, `RSA_SN(Val(N))`, and `ProjSpec(StochasticA{N}(), sat)`.
5. Preserve the existing `rng=nothing` keyword and explicit `R` keyword on scalar operations.
6. Update `workflow_stochastic.md`, `reference_defaults_random_display.md`, `concept_session_state.md`, and the cheat sheet. Reproducibility guidance should use either an explicit RNG or `Random.seed!` for Julia's task-local default.
7. Update the documentation-example state snapshot so it no longer saves/restores dead controls.
8. Replace getter/setter tests with behavioral stochastic tests at the interface:
   - equal seeded RNGs produce equal code-point streams;
   - explicit `R` produces the expected endpoint decisions;
   - a deterministic operation leaves an RNG's next draw unchanged;
   - no-RNG calls follow Julia's task-local default stream;
   - `RSA_SN()` is exactly `RSA_SN(8)` and `RSA_SN(16)` has `nrandbits == 16`.

If compatibility requires a warning period, retain deprecated functions for one release but make their status truthful. `DefaultRbits!` must not continue silently storing an unused value. It may warn and reject values other than 8 with a message directing callers to `RSA_SN(n)`. `DefaultRNG!` should warn and direct callers to explicit `rng=` or `Random.seed!`. Do not create a compatibility layer that changes the hidden state while arithmetic ignores it.

### Acceptance criteria

- There is exactly one implicit RNG source: `Random.default_rng()`.
- There is exactly one implicit stochastic-bit value: the compile-time constant 8 used by no-argument constructors.
- Deterministic calls retain static RNG elimination.
- No documentation claims a package-global stochastic stream exists.
- Searching production source for `DefaultRNG` or `DefaultRbits` finds only intentional deprecation shims, or nothing.

## Workstream 2: correct default-state documentation

### Current implementation

`with_default_type`, `with_default_returntype`, and `with_default_projection` are not scoped override functions. They read the current process-global value through a speculation guard and invoke `f(default, args...)`. Their implementation and docstrings in `defaults.jl` say this correctly.

`concept_session_state.md` and `reference_julia_compat.md` nevertheless show or describe a nonexistent form such as:

```julia
with_default_projection(RTZ_SF) do
    # temporary override
end
```

They also say the combinator restores state after exceptions. No matching method exists.

### Implementation plan

1. Correct these pages immediately; this does not need to wait for 0.4.0.
2. Present the two real choices:
   - explicit policy: `Add(T, RTZ_SF, x, y)` or `Convert(T, RTZ_SF, x)`;
   - consume the configured policy efficiently: `with_default_projection((ρ, args...) -> ..., args...)`.
3. State plainly that setters are process-global, persistent, non-atomic, and intended for controlled interactive/session setup.
4. Do not add `with_default_projection(ρ, f)` as a mutate/restore helper. It would look scoped while remaining observable by unrelated tasks.
5. Add documentation-consistency checks that reject the nonexistent call form and the phrase “restores on exit” when referring to `with_default_*`.

Longer term, consider deprecating process-global numerical defaults only if usage evidence justifies it. That would be a separate design project because constructor and Base-operation convenience forms currently consume `DefaultProjection`, and their specialization guards are explicitly tested.

### Acceptance criteria

- Every documented `with_default_*` call matches an implemented method.
- “Scoped” examples pass policy explicitly rather than mutating shared state.
- The process-global semantics and post-mutation dispatch cost are documented together.

## Workstream 3: make rounding classification singular

### Current implementation

The exported hierarchy is structurally sufficient:

```text
RoundingMode3109
├── DeterministicRoundingMode
│   ├── NearestRoundingMode
│   ├── DirectedRoundingMode
│   └── FaithfulRoundingMode
└── StochasticRoundingMode
```

`ToOdd <: FaithfulRoundingMode`, but the private `RoundingModes_Directed` union includes `ToOdd`. The legacy unions have only two live behavioral consumers: stochastic classification in `projspec.jl` and nearest-mode validation in `approx.jl`.

### Implementation plan

1. Replace:

   ```julia
   isstochastic(::Type{<:RoundingModes_Stochastic}) = true
   ```

   with:

   ```julia
   isstochastic(::Type{<:StochasticRoundingMode}) = true
   ```

2. Replace `roundingmode(ρ) isa RoundingModes_Ties` in `approx.jl` with `roundingmode(ρ) isa NearestRoundingMode` if both nearest modes are valid there. If the implementation requires only the two current concrete modes, state that requirement explicitly and dispatch on the abstract class only after confirming its invariant.
3. Delete `RoundingModes_Ties`, `RoundingModes_Directed`, `RoundingModes_Stochastic`, `RoundingModes_Deterministic`, and `RoundingModes` unless a private use remains.
4. Add taxonomy checks using `supertype`/`<:` and behavioral queries. Pin `ToOdd <: FaithfulRoundingMode` and `!(ToOdd <: DirectedRoundingMode)`.
5. Generate the conformance rounding-mode list from one private descriptor tuple rather than maintaining a second freehand list in `conformance()`.

Do not use `subtypes` at runtime to generate behavior or exports. It depends on loaded types and would turn a closed package vocabulary into an accidental extension seam. A private descriptor tuple can name the supported concrete modes while the abstract hierarchy provides classification.

### Acceptance criteria

- Each supported rounding mode has one class in the hierarchy.
- Behavioral dispatch uses abstract classes, not parallel unions.
- The conformance vocabulary and exported concrete modes are checked against the same descriptor.

## Workstream 4: make conformance identity reproducible

### Current implementation

`conformance()` derives formats, operations, block names, table specializations, and approximations live, but hardcodes `SmallFloats.jl 0.1.0`. `DRAFT_REVISION` identifies the standard only as a working draft uploaded on a date. The repository contains a D1 transliteration and concept map, so “D1” is already the local vocabulary and should be part of the identity.

### Local design

Keep package runtime identity independent of git. An installed Julia package may not have a `.git` directory, so `conformance()` must not shell out to git. Git state belongs in generated benchmark/release artifacts, whose generator runs in a checkout.

Introduce one private standard descriptor, for example:

```julia
const DRAFT_IDENTITY = (
    designation = "IEEE P3109/D1",
    uploaded = "2026-07-17",
    transliteration_sha256 = "820cb5009cd6fe9032f5bdfb661bc639e33296f716a552eafc81f899411bb5f2",
)
```

That digest is the current SHA-256 of `docs/other/IEEE_D1.md`. Calling it a transliteration digest is deliberate: the repository retains the mechanically converted Markdown, not the original IEEE file. The digest should be updated deliberately when that retained source changes. Avoid adding `SHA` as a runtime dependency merely to recompute an immutable release fact at package load; verify it in development/release tooling instead.

### Implementation plan

1. Replace the hardcoded package string with `Base.pkgversion(@__MODULE__)`, formatted for the existing field.
2. Add a structured `draft_identity()` query returning the descriptor. Keep `draft_revision()` as the human-readable compatibility query derived from it.
3. Extend `ConformanceDeclaration` and `conformance_dict` with separate package version and structured draft fields. If preserving the current `package::String` field is important, add fields rather than changing the existing one in place.
4. Add an `interpretations` field containing stable identifiers for genuine `[interp]` decisions. There are currently two live markers in `oracle.jl`, and the file says they are tracked in `checkpoint.md`, which is absent from the repository. Workstream 0 should remove markers already settled by D1; any remaining decisions need one authored, tracked design document and stable identifiers exposed in conformance output.
5. Update `conformance_report` to print package version, draft designation/date/digest, and interpretation identifiers before dynamic session state.
6. Pin package version against `Base.pkgversion(SmallFloats)` and pin every structured dict field.
7. Update the conformance workflow to distinguish reproducible package/draft identity from session-dependent cache and approximation state.

### Acceptance criteria

- No package version literal exists outside `Project.toml` and generated artifacts.
- A conformance dictionary identifies the exact package release and exact retained draft source.
- Runtime conformance works outside a git checkout.
- Draft interpretation decisions are enumerable rather than discoverable only by source search.

## Workstream 5: turn documentation checks into claim checks

### Current implementation

The suite already executes documentation examples and checks selected facts. That is the right seam: callers and tests see the authored documentation, while live package values supply authoritative facts. The weakness is coverage, not architecture.

### Implementation plan

Extend `test/docs_consistency.jl` rather than creating a second documentation generator for every page.

1. Package facts:
   - version text matches `Base.pkgversion(SmallFloats)` wherever a version is claimed;
   - K range and format count match `KMIN`, `KMAX`, and `_NAMED`;
   - exported narrow alias count is computed, not copied.
2. Source references:
   - collect backticked `src/*.jl` paths in implementation pages and assert that each exists;
   - explicitly reject removed `src/dyadic3.jl` references.
3. Session-state facts:
   - ensure the defaults table agrees with the actual exported defaults after Workstream 1;
   - reject scoped `with_default_*` examples.
4. Verification claims:
   - remove fixed assertion totals from evergreen prose, or compare any retained figure to a checked-in release artifact;
   - require the words “sampled” or “exhaustive” to match the roll-call artifact for each named gate.
5. Performance claims:
   - remove nanosecond values from the module docstring and link to the benchmark report;
   - keep machine-specific numbers in `benchmarking/benchmark_report.md` and `examples_performance.md` only;
   - if headline numbers are repeated, extract them from a small machine-readable sidecar produced by the benchmark runner.
6. Rewrite `test/README.md` as a test operator's guide. Document `SMALLFLOATS_TIER=quick|default|release`, gate overrides, expected broad cost, the roll-call output, and how to interpret sampled axes. Move the current historical assessment to a dated design note if it is worth retaining.
7. Update `internals_architecture.md` from the actual include order and include `show.jl` and `carriers.jl`.

Do not generate all prose from source. Authored explanation provides depth; only volatile facts need mechanical enforcement.

### Acceptance criteria

- Known stale counts, paths, timings, and default descriptions are removed.
- Documentation checks fail when a referenced source file disappears or a public fact changes.
- `test/README.md` explains how to operate the current suite rather than narrating an old review.

## Workstream 6: add CI using the existing tier seam

### Current implementation

The suite already has a real tier interface in `test/gatelog.jl` and related gates. `SMALLFLOATS_TIER` controls quick, default, and release coverage; the roll-call runs last and refuses to let a quick run masquerade as a release run. Aqua, JET, documentation consistency, examples, and the gate inventory are already included from `runtests.jl`.

### Workflow design

Add separate workflows rather than one matrix that makes every pull request pay release cost.

#### Pull request workflow

- Ubuntu, Julia 1.12, one thread.
- Instantiate the package environment.
- Run `Pkg.test()` with `SMALLFLOATS_TIER=quick`.
- Build HTML documentation with `DOCS_PDF=skip` so cross-references are checked without requiring the system LaTeX toolchain.
- Use concurrency cancellation for superseded commits.

#### Main-branch/default workflow

- Ubuntu, Julia 1.12, default tier.
- Run after merges or on a nightly schedule.
- Retain the roll-call output as an artifact.

#### Release workflow

- Run `SMALLFLOATS_TIER=release` on the primary supported platform.
- Add at least one secondary OS smoke job for package load and targeted interface checks if the full release tier is prohibitively expensive there.
- Build HTML and PDF with the documented system dependencies.
- Publish conformance output, roll-call output, final PDF, and optional editable PDF source bundle.
- Benchmarking remains a separately approved release action, not an automatic PR gate.

Do not claim a multi-version Julia matrix until compatibility is intentionally broadened. `Project.toml` currently says Julia 1.12; CI should first prove what the package claims.

### Acceptance criteria

- Every pull request receives the quick gate and documentation check.
- Main receives the default gate automatically.
- A release cannot publish without a release-tier roll-call and conformance artifact.
- Workflow names and artifacts make the executed tier unmistakable.

## Workstream 7: refine the public interface conservatively

### Code-point interface

The checked interface is already good:

- `T(c::Unsigned)` validates against the K-bit code range;
- `reinterpret(T, u::Unsigned)` validates storage width and high bits;
- `codepoint(x)` extracts the code unit;
- `rawvalue(T, c)` is the internal unchecked constructor.

Do not add `fromcodepoint` solely as another spelling. Instead:

1. Stop exporting `rawvalue` in 0.4.0.
2. Keep `SmallFloats.rawvalue` temporarily reachable for migration if needed, but mark it internal and unsupported.
3. Update user-facing examples to use `T(c)`; retain `rawvalue` only in implementation, verification, and benchmark documentation where prevalidated code enumeration is the point.
4. Consider renaming the internal primitive to `_rawvalue` only when the migration cost is justified; hundreds of internal call sites make a cosmetic rename low leverage.

### Display interface

`set_show_style!`, `get_show_style`, and the `IOContext` key already provide the behavioral interface. Remove `DEFAULT_SHOW_STYLE` from exports in 0.4.0, but keep the private `Ref` implementation. Encourage `IOContext` for local display policy and the setter only for process-wide interactive preference.

Delete the obsolete commented example block in `show.jl` after its useful concurrency rationale is moved into the live docstring or manual.

### `Binary` and namespaces

Keep `Binary` exported because it is needed for dispatch, trait signatures, and describing format relationships. Document that external subtyping is not a supported representation adapter; `reptype` knows only `Code8` and `Code16`, so Julia's open abstract type does not imply an open package extension seam.

Keep the top-level draft operation names. They are generated from `OP_REGISTRY`, documented as the spec register, and give high leverage through a consistent call shape. Additional namespace modules would duplicate rather than hide interface knowledge.

### Acceptance criteria

- Ordinary code-point construction is checked by default.
- No mutable `Ref` is exported.
- Internal unchecked construction remains allocation-free and local to trusted code.
- Documentation distinguishes dispatch use of `Binary` from unsupported external representation subtyping.

## Workstream 8: make benchmark evidence cover the architecture

### Report metadata

Add a helper in each benchmark runner that records repository state when available:

- full commit SHA;
- dirty/clean state;
- active project path;
- package version;
- benchmark script revision or SHA;
- seed;
- CPU, Julia version, thread count, Float128 state, and Chairmarks version.

The helper must degrade to “unavailable” outside a git checkout. Keep it in `benchmarking/`; do not add git awareness to package runtime code.

### Carrier and representation matrix

The current format-sensitivity rows are all K <= 8. Replace the hardcoded list with a named matrix containing at least:

- `Binary8p4se`: Code8, rung 1, common tabled format;
- a Code16/rung-1 format above K=8;
- `Binary16p5se` or the repository's established rung-2 representative;
- `Binary16p1uf`: rung 3/wide exponent spread;
- one small K=3 or K=5 format for tiny tables.

For each representative, measure only informative operations rather than the entire registry: decode, project, `Add`, `Multiply`, `Divide`, one transcendental, one array compute path, and an applicable block path. Record first call/compilation separately from warm latency. Do not combine JIT time with scalar execution.

Table coverage should explain when a wide operand combination is rejected by the byte budget instead of trying to materialize it.

### Thread evidence

The full runner already contains conditional threaded ternary comparisons. Publish both a one-thread and multi-thread report when threading is part of a release claim. Include array length and forced threshold state in row context.

### Report consistency

Give fast and full cases stable identifiers such as `scalar/add/8p4se/safe` and `block/dot/8p4se-b32`. Human labels may differ, but identifiers allow scripts to compare matching cases. Generate a small JSON or TOML sidecar for metadata and headline rows; documentation can consume this instead of copying timings.

### Acceptance criteria

- Published evidence includes all three carrier rungs and both representation widths.
- Every report identifies its source commit and dirty state when available.
- Cold compilation, cold table construction, warm lookup, and warm execution are distinct measurements.
- Threaded claims are backed by a multi-thread report.

## Workstream 9: optimize only measured allocation centers

Do this work only after Workstream 8 establishes reproducible cases. The existing report points to three candidates.

### Packed `vmap`

`packed.jl::_vmap_packed` creates two `view` objects per 256-element tile and re-enters the public `vmap!` interface for every tile. For 65,536 elements that means 256 tile calls and explains the scale of the reported 773 allocations.

Refactor at an internal seam rather than duplicating the public kernel:

1. Extract a private unary range kernel in `kernels.jl` that accepts destination/source offsets and a length.
2. Resolve table policy and RNG once per packed operation, outside the tile loop.
3. Have ordinary unary `vmap!` and packed `_vmap_packed` call the same range implementation.
4. Let the packed path pass `out`, `buf`, offsets, and `len` directly, with no `SubArray` construction.
5. Keep unpack-compute-store as the design; do not introduce packed arithmetic.

Target a size-independent allocation count: output plus one scratch buffer, with no per-tile allocation. Verify code-point equality with the existing path for deterministic and seeded stochastic modes.

### Cold table construction

`_build_binary` already writes code units directly into `Memory` and reuses the second operand's decoded datum collection. Do not assume the remaining allocations are simple container overhead; oracle evaluation and MPFR escalation may dominate.

Use allocation profiling to attribute allocations by operation and operand class before editing. Candidate changes are valid only if they preserve `_scalar_code` as the semantic source. Possible local optimizations include reusing decoded operand arrays, avoiding closures in repeated cache-build plumbing, or adding safe scratch reuse inside exact evaluation. Do not bypass scalar semantics with a second table-only oracle.

### Block operations

`ConvertToBlockMaxAbsFinite` maps decoded values, absolute values, and result kinds into tuples before folding and projecting. `BlockAdd` and dot-product paths may also allocate through exact carrier escalation. Attribute allocations first.

For fixed `NTuple{B}` inputs, prefer generated/static tuple transforms when they remove containers without increasing compilation excessively. For large or dynamic block storage, consider internal destination-writing kernels behind the existing block interface. Never replace exact accumulation with a narrower carrier to gain speed.

### Acceptance criteria

- Each optimization has a named benchmark case and an allocation target before implementation.
- Semantic tests compare code points through the public interface.
- No new user-visible tuning knob chooses a less exact carrier.
- Packed mapping has no allocation proportional to tile count.

## Workstream 10: migrate PDF artifacts deliberately

### Current implementation

The PDF pipeline intentionally treats `docs/pdf/build` as both compiler workspace and editable LaTeX source bundle. It deletes and regenerates that directory, then leaves it populated. Therefore simply ignoring it would remove a documented deliverable.

### Preferred release design

Keep these tracked source artifacts:

- `docs/src` and PDF pipeline scripts;
- `docs/pdf/howto.md`;
- `docs/pdf/render_manifest.json` if it is the validation baseline;
- optionally `docs/pdf/SmallFloats.pdf` if having the latest manual in-tree is valuable;
- `docs/pdf/buildnote.md` if it describes the retained PDF.

Move the editable source bundle to a release artifact:

1. Build in `docs/pdf/build` as today.
2. After validation, archive only the files required to edit/recompile the resolved source.
3. Publish that archive from the release workflow beside the PDF.
4. Add `docs/pdf/build/` to `.gitignore` and remove the 467 tracked build files in the same migration commit.
5. Update `buildpdf.sh`, `howto.md`, and the generated README to name the archive as the editable bundle.

If releases cannot yet host artifacts, defer this workstream. The present tree is noisy but intentional; deleting the bundle without a replacement would break a documented use case.

### Acceptance criteria

- The editable source bundle remains obtainable for each release.
- The repository no longer reviews page PNGs, minted fragments, logs, and compiler intermediates as source changes.
- The final PDF and its build note identify the same package version and commit.

## Workstream 11: improve release discipline

Prepare 0.4.0 as the interface-cleanup release because it removes inert exports and mutable implementation exposure.

Add a release checklist covering:

1. `Project.toml` version and changelog entry.
2. Exact P3109 draft descriptor and interpretation inventory.
3. Quick, default, and release roll-call artifacts.
4. Aqua/JET and documentation status through the suite.
5. Conformance dictionary/report.
6. HTML and PDF documentation, plus editable source archive if adopted.
7. Full one-thread benchmark report and optional multi-thread companion when performance changed.
8. Clean source commit recorded in every generated artifact.
9. Annotated git tag.
10. Registry submission only after the 0.4 interface migration and CI are stable.

Treat Julia 1.11 support as an independent investigation. First list the concrete 1.12 features in use, especially `Memory`, and estimate adapter cost. Broaden compatibility only if the implementation remains clear and the full verification evidence can cover it.

## Dependency order and proposed change sets

The work should land as small, reviewable change sets in this order:

### Change set 0: D1 defined-result correction

- Confirm the retained D1 provenance.
- Correct `ArcTan2` and `ArcTan2Pi` zero/zero and infinity/infinity rows.
- Update every inherited surface, independent reference, golden digest, and changelog entry.

Keep this separate from refactoring so the semantic diff is reviewable on its own.

### Change set A: documentation truth only

- Correct `with_default_*` semantics.
- Correct stale paths, counts, architecture entries, and module timing prose.
- Rewrite `test/README.md`.
- Extend documentation claim checks.

This is low risk and can land before interface changes.

### Change set B: taxonomy and conformance identity

- Replace legacy rounding unions with hierarchy dispatch.
- Derive package version from `Base.pkgversion`.
- Add structured draft identity and interpretation inventory.
- Update conformance tests and documentation.

This centralizes sources of truth without changing arithmetic.

### Change set C: stochastic-default cleanup for 0.4

- Remove/deprecate RNG and Rbits defaults.
- Update exports, documentation examples, and state restoration.
- Add behavioral RNG checks.

This is intentionally breaking and should be announced together.

### Change set D: public-interface cleanup for 0.4

- Unexport `rawvalue` and `DEFAULT_SHOW_STYLE`.
- Clarify `Binary` extension policy.
- Migrate public examples to checked construction.

Avoid mixing this with numerical implementation changes.

### Change set E: CI and artifacts

- Add quick/default/release workflows.
- Publish roll-call, conformance, docs, and PDF artifacts.
- Migrate the PDF source bundle only when its release replacement is working.

### Change set F: benchmark harness coverage

- Add source metadata and stable case identifiers.
- Add Code16 and carrier-rung representatives.
- Separate first-call, cold-build, and warm execution evidence.

This changes evidence, not package behavior.

### Change set G: measured performance patches

- Remove per-tile packed `vmap` views via a shared private range kernel.
- Profile, then address cold-table and block allocations.
- Keep one optimization topic per commit with its before/after report case.

## Completion criteria for the improvement program

The program is complete when:

- every exported control changes observable behavior or has been removed;
- all stochastic defaults have one coherent ownership model;
- rounding classification has one source of truth;
- conformance identifies the package and exact draft reproducibly;
- documentation claim checks cover volatile facts and all examples match real methods;
- CI exercises the suite's existing quick/default/release tiers;
- ordinary code-point construction is checked and mutable implementation containers are not exported;
- benchmark reports cover Code8, Code16, and all three carrier rungs with source metadata;
- optimization work is confined to demonstrated allocation centers;
- PDF reproducibility is preserved without requiring hundreds of generated files in ordinary source review;
- tagged releases carry conformance, verification, documentation, and performance evidence tied to the same commit.

The intended result is not a broader numerical design. It is a package whose surrounding operational machinery has the same precision as its arithmetic core: one interface per policy, one source of truth per claim, and one reproducible evidence trail per release.
