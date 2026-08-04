# How I would improve SmallFloats.jl — second pass

*Companion to `doc/other/reviewed1.md`. Package 0.4.0 at `3e940d6`.*

## Strategy

The 0.4.0 cycle already did the "make public controls truthful" work that
`doc/other/improved.md` sequenced: the inert RNG knobs are gone, conformance
identity is derived and hashed, the rounding taxonomy has one source, CI exists.
That was the right first cycle and it should not be relitigated.

The remaining defects share one shape, and the improvement plan should be
organized around that shape rather than around subsystems. Every open finding is
**a claim with no executor**:

- a function whose signature admits 504 formats and whose body admits 120;
- a tier name that no longer selects what it says;
- a docstring stating a format's range wrongly;
- an exactness gate whose arithmetic is masked by a coincidence;
- a performance report that stops where the package's interesting half begins.

So the organizing principle is: **for every claim the package makes, name the
thing that would fail if the claim went false.** Where that thing does not
exist, either build it or delete the claim. `CLAUDE.md` already says this
("a doctrine file is code that nothing executes"); the work is to apply it
outward from the doctrine file to the source, the docstrings, the tiers, and
the report.

Ordering below is by *risk removed per unit of work*, not by novelty. Phases A
and B are small and should land together; C and D are the substantial work.

---

## A. Close the four reachable defects

These are bounded, independently landable, and each comes with a specific pin.

### A1 — `f32_exact`: widen the loop, add a budget, state the refusal

Two things are wrong at `src/tables.jl:452-467`: the code unit is hardcoded to
`UInt8`, and there is no cost gate on an enumeration that is 2³² pairs of
300-bit `BigFloat` arithmetic at K1 = K2 = 16.

Fix both, in the shape the package already uses elsewhere:

```julia
function f32_exact(op::Symbol, f1::Type{<:Binary}, f2::Type{<:Binary})::Bool
    # Cheap structural screen first: if either format's datums do not fit
    # Float32 at all, no enumeration can make the answer `true`.
    (datumsexact(Float32, f1) && datumsexact(Float32, f2)) || return false
    ΣK = bitwidth(f1) + bitwidth(f2)
    ΣK <= F32_EXACT_MAX_BITS[] || _refuse_f32_enumeration(op, f1, f2, ΣK)
    ...
    U1, U2 = codeunit_type(f1), codeunit_type(f2)
    for c1 in zero(U1):U1((1 << bitwidth(f1)) - 1),
        c2 in zero(U2):U2((1 << bitwidth(f2)) - 1)
        ...
```

Three notes on the shape:

- `codeunit_type(F)` rather than `UInt8` is the same correction
  `measure_kappa` already carries (`approx.jl:70-75`, the "A1" note). Making the
  two read identically is worth more than either fix alone — it turns a
  one-off repair into a recognizable pattern.
- The budget mirrors `TABLE_EAGER_BITS` (`tables.jl:134-148`): a *time* bound in
  entries, not a memory bound, because this enumeration allocates nothing
  persistent and costs one oracle-grade comparison per point. Default it to 16
  bits so **no K ≤ 8 answer changes** — the same fixed-point argument
  `TABLE_EAGER_BITS` makes for itself — and let the `Ref` raise it.
- The refusal must be a stated one (`_unsupported`-style, naming the format and
  the budget), never an `InexactError`. That is `juliacompat.jl:116-118`'s rule
  applied where it was missing.

The `datumsexact` screen is not just an optimization: it makes the function's
answer *derivable* for the formats it declines to enumerate, so the budget
refusal only ever fires where the answer is genuinely unknown.

Pin: extend `test/float32surface.jl`'s sweep past `_K8_FORMATS` to one
representative per code unit, assert the K = 12 refusal is an `ArgumentError`
naming the budget, and correct `test/rollcall.jl:75` to say what is actually
uncovered.

### A2 — restore the suite's loop counts under the tier dial

Delete the dead `FastTest` scaffolding at `test/runtests.jl:46-73` and derive
the counts from `SUITE_TIER`, which already exists and is already read by every
other axis:

```julia
# test/formatsel.jl — beside SUITE_TIER, so one dial moves everything
const LOOP_SCALE = SUITE_TIER == "quick" ? 5 : SUITE_TIER == "default" ? 4 : 1
```

```julia
# test/runtests.jl
const K5  = cld(5000, LOOP_SCALE)
const K4B = cld(4096, LOOP_SCALE)
...
```

That preserves today's default-tier cost exactly (the divisors are already 4 and
5), makes `quick` genuinely cheaper, and makes `release` mean what the doctrine
says it means. The comment at `runtests.jl:1329-1331` ("derived from K5 so it
tracks the FastTest scaling") then becomes true again rather than referring to a
mode that no longer exists.

Pin: have `rollcall.jl` print `LOOP_SCALE` next to `SUITE_TIER` in its header,
and assert `LOOP_SCALE == 1` in the same place it already asserts a `quick` run
cannot masquerade as a release gate. The roll-call's own "35 332 465 compared
units" figure will move on the release tier — that is correct, and the header
line is what keeps the two numbers interpretable.

### A3 — `eps(x)` and `ldexp(x, n)` on `Binary`

Both are exact operations on a P3109 datum and both belong to the package
rather than to Base's fallback.

`ldexp` is the primitive: scaling by a power of two moves the exponent field and
nothing else, so it is exact on the carrier and needs one projection —
`juliacompat.jl:180-190`'s `significand` already does exactly this and is the
model to copy, including its saturation-mode choice:

```julia
function Base.ldexp(v::T, n::Integer) where {T<:Binary}
    d = decode(v)
    isfinite(d) || return v
    project(T, ProjSpec(NearestTiesToEven(), saturationmode(default_projspec(T))),
            ldexp(d, Int(n)))
end
```

`eps(x)` should then be written directly rather than inherited, because the
draft's answer is a lattice question and the package can answer it exactly:
the ulp at `x` is `NextGreaterThan(|x|) − |x|` on the carrier, projected once.
Writing it directly also gives the right answers at the two places Base's
formula is awkward — the subnormal band (where the step is constant) and the top
binade of an extended format (where `NextGreaterThan` runs into `Inf`).

Pin: add `eps` and `ldexp` to G10's veneer list
(`test/gates_g10.jl:207-235`) — that list is the right home, and its stated
principle ("sweep what the subtype *promises*") is precisely why they belong
there. While in that list, audit it once against `AbstractFloat`'s full surface
and record which verbs are deliberately absent, the way
`_NO_BASE_COUNTERPART` (`juliacompat.jl:70-78`) does for the registry side.

### A4 — `datumsexact`: fix the arithmetic, fix the docstring, pin it

Replace `emax = S ? B - 1 : 0` with `emax = B - 1` at `carriers.jl:286`, and
rewrite the docstring's second bullet, which currently describes a format range
the decoder does not produce (`Binary16p1uf`'s largest datum is 2³²⁷⁶⁶, not 0.5;
its smallest positive is 2⁻³²⁷⁶⁷, not 2⁻³²⁷⁶⁹).

This changes no current answer — verified by hand against all four entries in
`_extexprange`, where the subnormal condition binds first at every power-of-two
bias with exactly zero margin — which is what makes it safe to land alone.

The pin matters more than the fix, because zero margin is why nothing caught it:

```julia
# for every format, and every X in _extexprange's domain:
#   datumsexact(X, F) ⟺ every datum of F round-trips through X exactly
@test datumsexact(X, F) == all(exactly_representable(X, decode(rawvalue(F, c)))
                               for c in 0:(1 << bitwidth(F)) - 1)
```

At K ≤ 8 that is fully exhaustive; at K ≥ 9 it is 2^K per format and still
cheap. Run it over the tier's representative set and exhaustively at release.
That test would have failed the moment `_extexprange` gained a fifth entry, which
is the whole point.

While there: `Float128` is already named in a `datumsexact` context at
`formats.jl:602` but is not in `_extexprange`. Either add the row (with the
corrected `emax`, it is now safe to) or delete the reference.

---

## B. Repository and release hygiene

Small, mechanical, and blocking nothing — which is exactly why it keeps not
happening.

1. **Untrack `docs/pdf/build`.** 472 files, 29 MB, 251 `_minted` fragments and
   195 PNGs. Add `docs/pdf/build/` to `.gitignore` beside the existing
   `docs/build/` entry; keep `docs/pdf/SmallFloats.pdf` if a checked-in artifact
   is wanted, or move it to the release attachment that `release.yml` already
   builds.
2. **Tag 0.4.0.** `release.yml` triggers on `tags: ["v*"]` and has never run.
   Release automation that has never fired is untested automation; the
   conformance artifact and PDF paths in it are unverified today.
3. **Record why Julia 1.12.** There is at least one real reason and it is worth
   writing down: `setprecision`/`setrounding`'s function forms are
   `ScopedValue`-backed in 1.12 (`base/mpfr.jl:1210`, `:248-249`), which is what
   makes the MPFR escalations task-local and therefore safe under the threaded
   ternary kernel and under any user-level `Threads.@threads`. On 1.11 those are
   global `Ref` mutations. That is a correctness dependency, not a convenience,
   and it belongs in `Project.toml`'s neighbourhood as a comment and in the
   README.
4. **Publish run metadata from CI.** `release.yml` already uploads the roll-call
   log and `conformance.txt`; add a small JSON with Julia version and build, CPU
   target, thread count, commit SHA, dirty state, tier, gate count, and total
   compared units. That artifact is what makes a conformance claim reproducible
   rather than merely printed.

---

## C. Extend the performance evidence before optimizing anything

This is the largest genuine gap and the one with the most user value.

The report measures five formats, all rung 1, all K ≤ 8, for a package that
ships 504 formats across three carrier rungs. `CLAUDE.md`'s benchmark doctrine
goes to the trouble of tabulating *when* arithmetic allocates by rung — "the
enclosure ladder allocates at rungs 2 and 3 by construction" — and none of it is
measured. A user choosing between `Binary16p8se` (rung 1) and `Binary16p5se`
(rung 2) has no basis for the choice.

### C1 — one representative per rung, across the existing tables

Add `Binary16p8se` (rung 1, wide K, `Code16` storage, `ComputeDecode`),
`Binary16p5se` (rung 2, `Float128` carrier), and `Binary16p1uf` (rung 3,
`Dyadic` carrier, and the MX scale shape) to:

- core primitives (`decode` under `ComputeDecode` is a different function from
  the `TableDecode` gather and should be measured as one);
- scalar operations, at least the Group A rows and one Group B enclosure;
- format sensitivity;
- array kernels — where the interesting result is the **Shape-A/Shape-B
  boundary**, since at K = 16 a binary table is 2³² entries and the compute
  kernel is the only path. `table_policy` (`tables.jl:195-223`) already reports
  which shape a signature takes and why; the benchmark should print that
  alongside each row so a slow number is self-explaining.

Three formats, not thirty. The rung is the variable that matters; adding a
second format at the same rung measures the same code with a different type
parameter.

### C2 — measure what the doctrine says is expensive

Two rows the report should carry because the doctrine already predicts them:

- **First-call latency per rung.** `SmallFloats.jl:245-268` records "≈ 1.8 s per
  format, essentially all specialization" as the motivation for the wide
  precompile entries. That is the single largest user-visible cost in the
  package and it appears in a source comment rather than in the report.
- **Allocation by operation class and rung**, matching the doctrine's own table:
  exact selections zero at every rung; arithmetic zero until the operand spread
  escalates to MPFR; the enclosure ladder allocating at rungs 2 and 3 by
  construction. Printing the measured table beside the claimed one turns
  `CLAUDE.md`'s benchmark section into something a run can falsify.

### C3 — metadata, then optimization

Add commit SHA, dirty state, and benchmark-suite revision to the report header,
and give the fast and full reports shared case identifiers so a difference can
be attributed to workload or environment rather than eyeballed.

Only then optimize, and only the rows the broadened report still flags. On
current evidence that is:

1. **`ConvertToBlockMaxAbsFinite`** — 111 allocations, 3.95 µs at B = 32. The
   suspects are visible in `blocks.jl:511-528`: `map(decode, xs)`,
   `_joinheads(X...)` on a splat, `map` over the abs, and a `foldl` with a
   closure. `apply_op`'s `Vararg{Any,N}` lesson (`ops_scalar.jl:211-223`, where
   an untyped splat boxed 304 bytes per call on `Float128` and 592 on `Dyadic`,
   with every *component* measuring zero) applies directly here — the splat into
   `_joinheads` is the same construction. Measure at the entry point, not by
   assembling the parts.
2. **`BlockAdd`** — 35 allocations at B = 32, i.e. roughly one per lane, which
   points at the `ntuple(Val(B)) do i ... end` in the generated `$bname` body
   (`blocks.jl:311-317`) recomputing `_joinheads` per lane. The head is a
   function of the two blocks' formats, not of the lane, so it can be hoisted
   out of the `ntuple` entirely.

Both are structural rather than escalation-driven, which is what makes them
worth touching; the sub-10 ns scalar paths are not.

---

## D. Make the doctrine executable

`CLAUDE.md` is the best design record I have read in a Julia package, and its
own review section identifies the right problem: it is code nothing executes.
Three of its ten invariants already have executors (invariant 8 via
`stage_gates.jl`'s textual scan, invariants 5 and 6 via κ registration and
`gates_shape.jl`, invariant 10 via the byte budget). The remaining ones are
prose.

### D1 — give invariant 9 an executor, starting with `saturate`

Invariant 9 ("policy is dispatch, never a branch") is the one most often
departed from in the current source, and the departures are recorded in
`reviewed1.md`. Two are cheap to close and one is not worth closing:

- **`saturate`'s `Symbol` protocol** (`project.jl:365-431`) is the one that
  matters, because it sits inside the single write path. Replace the six
  symbols with six singleton tags and the `===` chain in `project` with
  dispatch:

  ```julia
  abstract type SatOutcome end
  struct AsIs <: SatOutcome end; struct MaxFin <: SatOutcome end
  struct MinFin <: SatOutcome end; struct PosInf <: SatOutcome end
  struct NegInf <: SatOutcome end; struct NaNOut <: SatOutcome end

  @inline _emit(::AsIs,   ::Type{T}, r) where {T} = rawvalue(T, encode(T, Int(r.sign), r.S, r.Q))
  @inline _emit(::MaxFin, ::Type{T}, _) where {T} = MaxFiniteOf(T)
  ...
  ```

  This buys three things: a mistyped outcome becomes a `MethodError` at
  definition rather than a fall-through to `:nan` at runtime; the outcome set
  becomes enumerable (so a test can assert the six rows are total over the
  `(Sat, Round, Σ, Δ)` grid); and the doctrine's central invariant holds at the
  centre of the write path rather than everywhere except there.

  This is a pure refactor with a strong pin available: G5's golden digests
  should be byte-identical across it, and if they are not, the change was not a
  refactor.

- **`_bp_element`'s `res isa …` chain** (`blocks.jl:189-232`) should be
  dispatch for consistency with its own sibling method 20 lines below, which
  *is* dispatch and carries a comment explaining why. Lower value than
  `saturate` — the result kind is genuinely dynamic there — but the two halves
  of one function should not disagree about the rule.

- **`show.jl`'s style branch** should stay a branch. Display is explicitly not a
  semantic, the styles are user-facing symbols, and dispatch would buy nothing.
  What it should lose is the per-call re-validation in `binary_show_style`
  (`show.jl:37-42`): `set_show_style!` already validates, and the `IOContext`
  path can validate at the `else` arm. Better: state the carve-out in
  `CLAUDE.md` so the departure is deliberate rather than merely unfixed.

### D2 — a doctrine-claims manifest

Every falsifiable statement in `CLAUDE.md` should name its executor, and the
ones with none should say so. The 2026-08-02 review found six false claims by
hand; the same review would be automatic against a small table:

| Claim | Executor |
|---|---|
| Include order matches the comment | `stage_gates.jl` textual check against `SmallFloats.jl` |
| 504 formats, K ∈ 3:16 | `docs_consistency.jl` (already) |
| `Binary{K` never appears in a method body | `stage_gates.jl` (already) |
| NaN sorts first, below −Inf | T1 order sweep (already) |
| Warm scalar paths allocate zero | specialization regressions (already) |
| `Float128=disable` is bit-identical | differential build gate (already) |
| Fourteen roll-call entries | `REQUIRED_GATES` (already) |
| Total compared units = N | roll-call, **plus** `LOOP_SCALE` in the header (A2) |
| G8 has no file, deliberately | roll-call's uncovered list (already) |
| Rung partition is 432/64/8 | G9 (already) |
| Invariant 9 holds | *nothing* — D1 |
| `datumsexact` is sound | *nothing* — A4 |

Two blank rows out of twelve is a good position to be in. Filling them, and
keeping the table beside the doctrine, is what stops the count from creeping
back up.

### D3 — separate the record from the contract, but do not thin the record

`reviewed.md` recommended moving the M-number post-mortems out of the source and
into design records. I would **not** do that wholesale, and the reason is
visible in `dyadic.jl:219-243`: the measurement history there is what stops the
next person from re-applying a "1.87× win" that reverses under a correct
harness. That knowledge has no other home where it will be read at the moment it
is needed.

What can move: stage numbers and plan references ("arrives in Stage 6 of the
K ≤ 16 extension"), which now appear in *runtime error messages*
(`oracle.jl:374-381`, `:379-381`, `:453-455`, `:476-479`) for stages that are
complete. A user who hits one of those today is told to wait for work that
shipped. Those messages should say what is actually true — which operation, which
carrier, and that the combination has no ω-semantics — and the stage history
should stay in `implementextensions.md §11`.

---

## E. Smaller items, worth doing while nearby

- **Bulk `Convert` over `Binary` arrays** (`kernels.jl:170-171`) should take
  `rng`, matching every other array operation and the entropy decision in
  `defaults.jl:98-114`.
- **`add_dy_checked`**, mirroring `mul_dy_checked`. The head-width precondition
  at `dyadic.jl:261-262` is real and `add_dy` is exported; the two-name pattern
  is already the module's own answer to this exact question.
- **Delete `formats.jl:463-482`.** The commented-out `show` pair is superseded
  and the reason it was removed (method overwriting is a precompilation *error*,
  which silently un-precompiled the package) is already in `show.jl:121-122` and
  in the changelog.
- **Fix `measure_kappa`'s docstring** (`approx.jl:52`): "always true for arity
  ≤ 2" is false above K = 11 per operand pair. The mechanism is right; only the
  parenthetical is a K ≤ 8 leftover.
- **Thread the unary/binary Shape-B loops**, or rename the switches. At K ≥ 9 a
  declined table is the common case, so the compute kernel is now the main array
  path for wide formats, and it is the one place `THREADED_KERNELS` does not
  reach. Threading it is the same construction as the ternary loop (pure ρ ⇒
  deterministic per element) and the MPFR scoping is already task-local on 1.12.
- **An opt-in `Blocks` namespace**, mirroring `Formats`. The block/scaled surface
  is ~100 exported names generated from the registry; `Formats` already
  establishes that opt-in re-export is this package's answer to a wide generated
  surface, and the asymmetric-reversibility argument in `SmallFloats.jl:90-116`
  applies unchanged.

---

## Sequence

**Phase A — reachable defects** (small, independent, each with a pin)
A1 `f32_exact` · A2 tier-scaled loop counts · A3 `eps`/`ldexp` · A4
`datumsexact`. Exit: every one has a test that fails without the fix, and the
roll-call's uncovered list is true.

**Phase B — hygiene and release** (mechanical)
Untrack `docs/pdf/build` · tag 0.4.0 · record the 1.12 dependency · publish CI
run metadata. Exit: `release.yml` has fired once and its artifacts are correct.

**Phase C — evidence** (the largest user-visible gap)
Three representative wide formats through the existing tables · first-call
latency and allocation-by-rung · report metadata · *then* the two block
allocation centres. Exit: the report substantiates all three carrier rungs and
`CLAUDE.md`'s allocation table is a measured table.

**Phase D — executable doctrine**
`saturate` to dispatch (golden-digest-identical) · the claims manifest · correct
the stage-referencing error messages. Exit: no falsifiable doctrine claim lacks
an executor, and the ones that cannot have one say so.

Phases A and B should land together and quickly. C is a cycle's worth of work
and is the one that changes what users can decide. D is ongoing maintenance
discipline rather than a project.

---

## What I would deliberately not do

- **Do not touch the projection engine, the oracle protocol, or the carrier
  lattice.** They are correct, they are the reason the package exists, and the
  extension proved they factor. `saturate`'s refactor (D1) is a change of
  protocol *type*, not of semantics, and must be golden-digest-identical or
  reverted.
- **Do not split `oracle.jl` or `dyadic.jl` by size.** Both are deep modules
  with real interfaces. The only defensible split is exact arithmetic versus
  enclosure construction, and only if it earns its own tested seam.
- **Do not chase the sub-10 ns scalar paths.** They are already zero-allocation
  and near the floor. The allocation-heavy block operations and the entirely
  unmeasured wide rungs are where the remaining performance value is.
- **Do not widen the default export surface** to the other 384 aliases. The
  asymmetric-reversibility argument in `SmallFloats.jl:90-116` is right and
  still applies.
- **Do not deepen G10.** It earns its place by being total and shallow, and its
  own comment says so. Add verbs to its list; do not add assertions to its
  probes.
- **Do not thin the measurement post-mortems out of the source.** They are the
  most transferable knowledge in the repository and they are read exactly where
  they are needed.
- **Do not add a scoped-mutation `with_default_*`.** The consumption-combinator
  semantics are documented, tested, and correct; a second meaning on the same
  name is how the 0.3.0 documentation defect happened.

---

## Desired end state

A package where every claim has an executor. The arithmetic is already there:
one write path, three carriers, 504 formats, bit-exact defined results, and
approximation that is measured rather than promised. What the next cycle adds is
the same property applied to the package *around* the arithmetic — a tier that
runs what its name says, a public function whose domain matches its signature, a
gate whose arithmetic is checked rather than coincidentally sound, and a
performance report that covers the half of the design space the extension added.

None of that changes a single result. All of it changes how long the results
stay right.
