# SmallFloats.jl Improvement Guide — second cycle, revised

*Supersedes `doc/other/improved_guide.md`. Traced against `3e940d6`
(main, clean, 0.4.0) and Julia 1.12.6's Base. No tests or benchmarks executed.*

## What this revision changes

Three designs did not survive re-tracing, and one of them would have caused a
performance regression on the package's hottest path. They are stated first
because a guide that quietly replaces its own advice is the failure mode this
whole cycle is about.

**W5 (`saturate`) was redesigned and demoted.** The previous version had
`saturate` return an abstract `SatOutcome` consumed by `_emit`. That introduces a
**six-way small union** where a concrete `Symbol` stands today. Julia's
union-splitting budget is small — historically four — so six singleton return
types can fall out of union-splitting into dynamic dispatch, inside `project`,
which is a 6.7 ns zero-allocation function on every write in the package. The
previous acceptance criterion (G5 digests byte-identical) would **not** have
caught it: digests are about values, not about dispatch. Redesigned below with
the emission folded into the dispatch, and the gate changed from digest equality
to digest equality **plus** the existing inference and allocation pins.

**W3's non-finite row changed.** `T(NaN)` routes through `_convert_default` →
`with_default_projection`, so `eps(Inf)` would have read the session default and
gone dynamic if it had been changed. `rawvalue(T, nan_code(T))` is the direct,
default-independent spelling — and `eps` must not depend on session state.

**W1's refusal message changed.** It printed `trailing_zeros(budget)`, which is
only correct if the budget is a power of two. The `Ref` is user-settable.

Everything else from `improved_guide.md` stands; it is restated here in full so
this file is self-contained.

---

## Ground rules

Every workstream is accepted against four axes, and each must be answered
explicitly rather than assumed:

| Axis | The question that must be answered |
|---|---|
| **Correctness** | What independent witness fails if this is wrong? Not "a test exists" — *which* comparison, against *what* reference, over *what* domain |
| **Performance** | Does this touch a warm path? Does it change inference, allocation, or specialization? If not, say so and move on; if yes, name the pin |
| **Clarity** | Does the change make a claim *checkable* that was previously only readable? |
| **Throughput** | Package: does it change work-per-second on array, table, or block paths? Development: what does it unblock, and what can land beside it |

The two carried invariants from `reviewed1.md` that the 0.4.0 doctrine did not
yet name:

7. **A refusal is a stated refusal.** No public entry point may fail with an
   exception about a representation type when the caller's error is about a
   format (`juliacompat.jl:116-118`).
8. **A tier runs what its name says.** No axis may be narrowed by a mechanism
   the tier dial cannot reach.

Plus the six from `doc/other/improvement_guide.md`, unchanged.

---

## Corrections to `improved1.md`, carried forward

Both narrow the work and both were found by tracing the harness rather than the
report.

**The benchmark harness already covers all three carrier rungs and already
emits provenance.** `benchmarking/benchmarking.jl:299-308` benches format
sensitivity over `Binary8p4se`, `Binary16p8se`, `Binary16p5se`, `Binary16p1uf`,
`Binary3p1se` — explicitly "one representative of Code8/rung 1, Code16/rung 1,
rung 2, and rung 3". `:478-505` emits commit SHA, dirty state, package version
and seed. That landed in `5e70873` (2026-08-03); the checked-in
`benchmark_report.md` was regenerated at `51abbc9` (2026-08-02).

The report is **stale by one commit, not incapable.** First action is
`regenerate`, and its output re-scopes the rest of W6.

**`allocation_profile` is defined and never called.**
`benchmarking/benchmarking.jl:226-239` computes exactly the per-rung allocation
table `CLAUDE.md`'s benchmark doctrine asserts in prose. `generate_report` never
invokes it. Same species as every finding in `reviewed1.md`: an executor that
exists and is wired to nothing.

---

## Decisions, refined against the local design

| Topic | Decision | Reason |
|---|---|---|
| `f32_exact` scope | Serve every K behind a stated entry budget | The question is meaningful at K ≥ 9 (`Binary9p4se`: B = 16, P = 4, all datums Float32-exact) and 2^18 pairs is cheap. Restricting would be a scope claim the signature contradicts |
| `f32_exact` fast-`false` screen | `datumsexact(Float32, ·)` on both formats, justified by **witness construction**, pinned as a *subset* of enumeration-`false` | Sound only because `P ≤ 16 < 24`: the trait can fail only by range or by underflow-to-zero, and both exhibit a concrete inexact pair. A precision-only failure has no witness and cannot occur here |
| `f32_exact` budget | Pairs, `2^(K1+K2)`, in a `Ref`, floor 2^16 | Same unit as the bounded quantity; 2^16 is the fixed point at which no K ≤ 8 answer changes — `TABLE_EAGER_BITS`' own argument |
| Loop-count tier | One `LOOP_SCALE` from `SUITE_TIER` in `formatsel.jl`; full literals become the source of truth | The tier dial already exists and is where every other axis reads. A second mechanism is the defect being fixed |
| Default-tier cost | Accept a one-time move in the roll-call total; record the new number | Today's divisors are inconsistent (4 for seven constants, 5 for two), so no single scale reproduces them. Keeping the mix to hold a statistic stable is keeping the defect |
| `eps(x::Binary)` | Derive from `round_to_precision`'s `Q`; non-finite row via `rawvalue`, **not** `T(NaN)` | Reuses the engine's own normalization (as `Base.decompose` does) so it cannot drift from the grid, removes both edge cases in Base's formula, and stays independent of session defaults |
| `ldexp(x::Binary, n)` | Add it; exact on the carrier, one `project` | It is `significand`'s construction with a different exponent, and `eps`'s Base fallback needs it |
| `datumsexact` | `emax = B - 1` unconditionally; land alone | Changes no current answer (verified against all four `_extexprange` rows), so its pin is the deliverable |
| `saturate` | **Fold emission into per-mode dispatch**; keep a separate introspection function for tests | Avoids a six-way union in `project`. See W5 |
| `_bp_element` branch | Leave it; add a stated carve-out | The result kind is genuinely dynamic — it is the oracle's declared protocol |
| `show.jl` style branch | Leave the branch; drop per-call re-validation; state the carve-out | Display is explicitly not a semantic |
| Benchmarks | Regenerate → wire `allocation_profile` → widen two sections → cold start | The capability gap is one commit of drift plus one unwired function |
| `docs/pdf/build` | Migration, not deletion | `docs/pdf/build/README.md` documents it as editable LaTeX source with a stated recompile command |
| Julia 1.12 floor | Record the reason in `Project.toml`'s neighbourhood and the README | `base/mpfr.jl:1210`, `:248-249`: `setprecision`/`setrounding` function forms are `ScopedValue`-backed. On 1.11 they mutate globals — unsound under the threaded ternary kernel and under any user `Threads.@threads` over an escalating operation. A correctness floor |
| Package throughput | Treat parallel table builds and Shape-B threading as one workstream with one correctness constraint | Both are "more workers through `_scalar_code`", and invariant 6 is the single thing that must hold for both |

---

## Dependency graph

Development throughput matters as much as ordering. Five of the nine
workstreams are mutually independent and can land in any order or in parallel;
the constraints are few and each has a reason.

```
W1 f32_exact ─┐
W2 LOOP_SCALE ─┤
W3 eps/ldexp  ─┼─── independent, land in any order, no shared file
W4 datumsexact ┘         │
                         │  W4 must be verified digest-neutral
                         ▼  BEFORE W5 starts
W6a regenerate ──► W6b allocation_profile ──► W6c widen ──► W6d cold start
       │                                          │
       └── re-scopes W6c/W6d                      ▼
                                        W8 throughput (measured after)
W5 saturate ──── alone in its commit, gated on inference + allocation + digests
W7 release state ─── independent; tag last
W9 doctrine table ── ongoing, closes as W4/W5/W6b land
```

The only hard edge is **W4 before W5**. Both can move G5's golden digests; W4 is
expected not to and W5 must not. Landing them separately means a digest movement
has exactly one candidate explanation. Everything else is scheduling preference.

Files touched, for merge planning: W1 `src/tables.jl` · W2 `test/runtests.jl`,
`test/formatsel.jl` · W3 `src/juliacompat.jl`, `test/gates_g10.jl` ·
W4 `src/carriers.jl`, `test/gates_g6.jl` · W5 `src/project.jl` · W6
`benchmarking/` · W8 `src/kernels.jl`, `src/tables.jl`. Only W1 and W8 collide.

---

## W1 — `f32_exact` over the whole grid

### Current

`src/tables.jl:452-467`. After a cache probe and `_f32op`:

```julia
for c1 in 0x00:UInt8((1 << bitwidth(f1)) - 1), c2 in 0x00:UInt8((1 << bitwidth(f2)) - 1)
```

`UInt8` is a checked conversion, so `bitwidth(f1) = 9` raises `InexactError`
before the loop begins. Exported (`SmallFloats.jl:205`), typed
`Type{<:Binary}`, docstring states no K restriction, and there is no cost gate:
`K1 = K2 = 16` is 2^32 pairs at 300-bit `BigFloat`.

`measure_kappa` had the identical defect and fixed it — `approx.jl:70-75`
records it as finding A1, resolution `codeunit_type(argformats[i])(codes[i])`.

### Design

Three changes; only the screen needs an argument.

**The code unit.** Mechanical. Write it so it reads identically to
`measure_kappa`'s fix — two one-off repairs are worth less than one recognizable
pattern.

**The fast-`false` screen.** `datumsexact(Float32, F)` (`carriers.jl:283-288`,
loaded well before `tables.jl`) can fail in exactly two ways at `P ≤ 16`, and
each exhibits a concrete inexact pair:

- **Range.** Some datum `x` has `Float32(x) = ±Inf32`. For any nonzero finite
  datum `y`, `BigFloat(g(Inf32, Float32(y)))` is non-finite while
  `g(BigFloat(x), BigFloat(y))` is finite. Witnessed.
- **Underflow.** The step `2^(2−P−B)` is below Float32's least subnormal, so the
  smallest positive datum `d` has `Float32(d) = 0.0f0`. For `Add`,
  `0 + Float32(y) = Float32(y) ≠ d + y`; for `Multiply`,
  `0 · Float32(y) = 0 ≠ d·y` for nonzero `y`. Witnessed.
- **Precision cannot fail.** The first condition is `P ≤ precision(X)` and
  `P ≤ KMAX = 16 < 24`.

That argument is specific to Float32 **and** to `KMAX ≤ 24`. Write it at the
screen, because it stops holding the moment `KMAX` is raised past 24 — and
`KMAX` is a constant this package expects to raise.

**The budget.** In pairs, floor 2^16 so every K ≤ 8 signature is inside and no
current answer changes. The default above the floor wants one measurement: each
pair is two decodes plus two 300-bit `BigFloat` operations, plausibly 2–5 µs, so
2^20 pairs is roughly 2–5 s. Ship `Ref(1 << 20)` and correct from measurement
rather than pretending to precision.

Rejected: restricting the signature to `K ≤ KSPLIT`. It would make the throw a
`MethodError`, which is the same failure class one layer up, and it would refuse
K = 9…11 where the answer is both meaningful and cheap.

### Code

```julia
"""Largest `2^(K1+K2)` pair count `f32_exact` will enumerate. A **time** bound:
each pair costs two decodes and two 300-bit `BigFloat` operations. The floor is
2^16 — the largest K ≤ 8 signature — so no answer that existed before the
K ≤ 16 extension can change, by the same fixed-point argument
`TABLE_EAGER_BITS` makes for itself."""
const F32_EXACT_MAX_PAIRS = Ref(1 << 20)

@noinline _refuse_f32_enumeration(op, f1, f2, ΣK) = throw(ArgumentError(
    "f32_exact(:$op, $(formatname(f1)), $(formatname(f2))) would enumerate " *
    "2^$ΣK operand pairs against a 300-bit oracle, over the " *
    "$(F32_EXACT_MAX_PAIRS[])-pair budget. Raise " *
    "`SmallFloats.F32_EXACT_MAX_PAIRS[]` to ask for it anyway"))

function f32_exact(op::Symbol, f1::Type{<:Binary}, f2::Type{<:Binary})::Bool
    key = (op, _fkey(f1), _fkey(f2))
    c = lock(() -> get(F32_EXACT_CACHE, key, nothing), TABLE_LOCK)
    c !== nothing && return c
    g = _f32op(op)          # BEFORE the screen: an unknown op is a caller error
                            # regardless of the formats, and must report as one.
    # Provably false without enumerating — the witness construction above. Sound
    # only while P ≤ KMAX ≤ 24 = precision(Float32): the trait can then fail only
    # by range or by underflow-to-zero, and each exhibits an inexact pair. If
    # KMAX is ever raised past 24 this screen must go, because a precision-only
    # failure has no witness.
    ok = if !(datumsexact(Float32, f1) && datumsexact(Float32, f2))
        false
    else
        # `1 << ΣK` is safe here and is NOT safe in `tablebits`: ΣK ≤ 32 for two
        # K ≤ 16 formats, while a ternary table's ΣK reaches 48. Different
        # bound, different spelling — do not unify them.
        ΣK = bitwidth(f1) + bitwidth(f2)
        (1 << ΣK) <= F32_EXACT_MAX_PAIRS[] || _refuse_f32_enumeration(op, f1, f2, ΣK)
        U1, U2 = codeunit_type(f1), codeunit_type(f2)
        setprecision(BigFloat, 300) do
            for c1 in zero(U1):U1((1 << bitwidth(f1)) - 1),
                c2 in zero(U2):U2((1 << bitwidth(f2)) - 1)
                x = decode(rawvalue(f1, c1)); y = decode(rawvalue(f2, c2))
                (isfinite(x) & isfinite(y)) || continue
                BigFloat(g(Float32(x), Float32(y))) == g(BigFloat(x), BigFloat(y)) ||
                    return false
            end
            true
        end
    end
    lock(() -> (F32_EXACT_CACHE[key] = ok), TABLE_LOCK)
    ok
end
```

`decode(x)` at rung 2/3 returns `Float128`/`Dyadic`; `Float32(::Dyadic)`
(`dyadic.jl:838`) and `BigFloat(::Dyadic)` (`:607`) both exist, so the body is
already carrier-generic. The screen makes those paths unreachable — no rung-2 or
rung-3 format can satisfy `datumsexact(Float32, ·)` — which is worth stating, or
the generality reads as dead code rather than as defence.

### Performance

Not a warm path; memoized behind a lock; no consumer in `src/`. The screen turns
the wide-format answer from an exception into O(1). Nothing to pin.

### Pins

1. **No regression:** the pinned counts hold — Multiply 118/120, Add 88/120,
   Subtract 88/120, `mulfail == [:Binary8p1ue, :Binary8p1uf]`
   (`test/float32surface.jl:129-133`). Run first in the testset.
2. **Screen ⊆ enumeration:** for all 120 K ≤ 8 formats × three ops, call the
   enumeration directly (bypassing the screen) and assert
   `screen_false ⇒ enum_false`. Exhaustive at K ≤ 8. It must be *implication*,
   not equality: Add/Subtract fail 32 formats the screen passes, by arithmetic
   rather than by datum representability, and an equality assertion would be
   wrong.
3. **K ≥ 9 answers:** `f32_exact(:Multiply, Binary9p4se, Binary9p4se) isa Bool`.
4. **Budget refuses by name:** `@test_throws ArgumentError f32_exact(:Add,
   Binary16p8se, Binary16p8se)`, message contains the budget.
5. **Correct `test/rollcall.jl:75`**, which says "`f32_exact`'s enumeration at
   K >= 12" — implying K = 9,10,11 work.

---

## W2 — loop counts under the tier dial

### Current

`test/runtests.jl:46-73`: the `if isdefined(Main, :FastTest)` is commented out,
the full literals are inside `#= =#`, and the divided values are the only
reachable ones. They drive ~30 sampling loops (`:729-763`, `:834`, `:888`,
`:1227`, `:1283-1358`, `:1621-1630`). `SMALLFLOATS_TIER=release` does not reach
them: `test/formatsel.jl:171` owns the tier and governs the *format* axis.

### Design

`formatsel.jl` is the home — it owns `SUITE_TIER` and already publishes derived
quantities (`exhaustive_requested`, `quick_requested`, `sweep_formats`). It does
its own `using SmallFloats` (`:45`), so `runtests.jl` can include it any time
after its import block ends at `:43`, guarded the way every other file already
guards it.

**One dial cannot reproduce today's mixed divisors.** Seven constants divide by
4, two by 5. Choosing 4 raises `K5` 1000 → 1250 and `TEN5` 10 → 13 at the
default tier, moving the roll-call total once. That is the honest outcome;
engineering around it means keeping the defect to protect a statistic.

`cld`, not `div`: at a quick scale of 8, `div(10, 8) = 1`, and a loop of one
iteration is a different test.

### Code

```julia
# test/formatsel.jl, beside SUITE_TIER
"""Divisor applied to every sampling loop count in `runtests.jl`. The full
literals are the source of truth; this is the only thing that shrinks them, and
it moves with `SMALLFLOATS_TIER` so a tier runs what its name says.

`release` is 1 by definition — the doctrine's "a tier the caller asks for is
honoured, never downgraded" is exactly this constant not exceeding 1 there.
Before this, the counts were divided unconditionally and the `FastTest` switch
that once selected them had been commented out."""
const LOOP_SCALE = SUITE_TIER == "release" ? 1 : SUITE_TIER == "quick" ? 8 : 4
```

```julia
# test/runtests.jl, replacing :46-73
isdefined(@__MODULE__, :SUITE_TIER) || include("formatsel.jl")

# Full loop counts; `LOOP_SCALE` (formatsel.jl) shrinks them per tier and is 1
# at `release`. Never divide here — the tier is the only dial.
const K5   = cld(5000, LOOP_SCALE)
const K4B  = cld(4096, LOOP_SCALE)
const K4   = cld(4000, LOOP_SCALE)
const K2   = cld(2000, LOOP_SCALE)
const K1   = cld(1000, LOOP_SCALE)
const H2   = cld( 200, LOOP_SCALE)
const H1   = cld( 100, LOOP_SCALE)
const TEN5 = cld(  50, LOOP_SCALE)
const TEN1 = cld(  10, LOOP_SCALE)
```

`runtests.jl:1329-1331` ("derived from K5 so it tracks the FastTest scaling")
becomes true again; update it to name `LOOP_SCALE`.

### Performance

Development throughput only. Default tier moves ≈ +6% on the affected loops
(`K5`/`TEN5` up, the rest unchanged); quick tier halves them; release grows
4–5×. Release is already the ~38-minute tier, so the growth lands where time is
already budgeted.

### Pins

1. `rollcall.jl`'s header prints `LOOP_SCALE` beside `SUITE_TIER`. A reader
   given "total compared: N" without the scale has a number, not a coverage
   claim — `rollcall.jl:40-47` already makes this argument for the tier.
2. `rollcall.jl` asserts `LOOP_SCALE == 1` where it already asserts a quick run
   cannot masquerade as a release gate.
3. New default-tier total recorded in the changelog; `CLAUDE.md`'s
   "35 332 465 compared units" updated with its tier named beside it.
4. No occurrence of `FastTest` remains in `test/`.

---

## W3 — `eps(x)` and `ldexp(x, n)`

### Current

`formats.jl:505` defines `Base.eps(T::Type{<:Binary})`. No value form; no
`Base.ldexp(::Binary, ::Integer)`. Julia's fallback (`base/float.jl:983`):

```julia
eps(x::AbstractFloat) = isfinite(x) ? abs(x) >= floatmin(x) ?
    ldexp(eps(typeof(x)), exponent(x)) : nextfloat(zero(x)) : oftype(x, NaN)
```

For any finite value at or above `floatmin` — the common case — this reaches
`ldexp(::Binary, ::Int)` and raises a `MethodError` naming `ldexp`. The
subnormal and non-finite rows work by accident. G10's veneer sweep
(`test/gates_g10.jl:207-235`) omits both verbs.

### Design

**`ldexp` is the primitive.** Scaling by a power of two moves the exponent field
and nothing else, so it is exact on every carrier — the argument
`blocks.jl:70-94` already makes for the P = 1 block fast path. Write it as
`significand`'s construction (`juliacompat.jl:180-190`) with a different
exponent: nearest rounding (immaterial except at overflow, where the value has
left the datum set) and saturation from the session default, so it agrees with
`floor`/`ceil`/`round` about the top of the range.

**`eps(x)` derives from the engine, not from the lattice and not from Base's
formula.** Run the exact datum through `round_to_precision`, which on an exact
input is pure extraction rather than rounding — the identity `Base.decompose`
relies on (`juliacompat.jl:135-142`) — and read `Q`. `Q` *is* the binary
exponent of the ulp at `x`:

- normal datum: `Q = e − P + 1`, and `nextfloat(x) − x = 2^(e−P+1)` ✓ — this
  matches Base's `ldexp(eps(T), exponent(x))` exactly;
- subnormal: `Q = 2 − B − P`, the constant subnormal step ✓ — where Base's
  formula would be wrong without its `floatmin` guard.

Rejected alternatives, and why:

- `decode(NextGreaterThan(v)) − decode(v)` walks the lattice and needs a special
  case at the top binade, where `NextGreaterThan` returns `Inf`/`NaN` by design
  (`decode_encode.jl:317-331`); on `Dyadic` it also routes a subtraction through
  `add_sticky_dy`'s alignment band for no reason.
- Base's formula needs the `floatmin` guard and an `ldexp` we would be adding in
  the same commit — circular, and it hides the subnormal case.

The construction yields a fact worth asserting rather than assuming: **`eps(x)`
is always exactly a datum.** The ulp is `2^Q` with `2−P−B ≤ Q ≤ e_max−P+1`, and
every power of two in a format's range is a datum for every `P ≥ 1`. So the
projection cannot round and the mode is immaterial — which is what makes
defining this safe under invariant 1.

Two rows follow Base's contract and one of them must **not** go through the
session default:

- `iszero` → `MinPositiveOf(T)` (Base's `nextfloat(zero(x))`).
- non-finite → the format's NaN, spelled `rawvalue(T, nan_code(T))`.
  `T(NaN)` would route through `_convert_default` → `with_default_projection`,
  reading session state and going dynamic once the default is changed. `eps` of
  a non-finite must not depend on a session knob.

### Code

```julia
# ---- ldexp: exact on every carrier, one projection.
#
# Scaling by a power of two moves the exponent and nothing else, so this is
# `significand`'s construction above with a different exponent — and, like it,
# the projection is only reachable at the range boundary. Saturation comes from
# the session default so this agrees with floor/ceil/round about the top of the
# range; the rounding mode is immaterial because the scaling is exact wherever
# the result is a datum at all.
function Base.ldexp(v::T, n::Integer) where {T<:Binary}
    d = decode(v)
    isfinite(d) || return v                        # NaN and ±Inf are fixed points
    project(T, ProjSpec(NearestTiesToEven(), saturationmode(default_projspec(T))),
            ldexp(d, Int(n)))
end

# ---- eps(x): the ulp at x, from the engine's own normalization.
#
# `round_to_precision` on an exact datum is pure extraction, not rounding — the
# identity `Base.decompose` above relies on — and its `Q` IS the binary exponent
# of the ulp. Reusing it means this cannot drift from the format's grid, and it
# removes both edge cases in Base's formula: the subnormal band (constant step,
# not scaled) and the top binade (where a lattice-walking definition runs into
# the Inf encoding).
#
# The result is always exactly a datum: the ulp is 2^Q with
# 2−P−B ≤ Q ≤ e_max−P+1, and every power of two in a format's range is a datum
# for every P ≥ 1. So the projection below cannot round.
#
# The non-finite row is `rawvalue`, NOT `T(NaN)`: the latter routes through
# `_convert_default` → `with_default_projection` and would make `eps` depend on
# the session projection default.
function Base.eps(v::T) where {T<:Binary}
    d = decode(v)
    isfinite(d) || return rawvalue(T, nan_code(T))  # Base's `oftype(x, NaN)` row
    iszero(d) && return MinPositiveOf(T)            # Base's `nextfloat(zero(x))` row
    r = round_to_precision(precision(T), expbias(T), NearestTiesToEven(), d, 0, 0)
    project(T, ProjSpec(NearestTiesToEven(), saturationmode(default_projspec(T))),
            ldexp(one(datumcarrier(T)), Int(r.Q)))
end
```

`ldexp(one(datumcarrier(T)), Q)` rather than `2.0^Q`: at rung 3 the exponent
reaches ±32 768 and no `Float64` literal holds it. `Dyadic` implements `ldexp`
natively (`dyadic.jl:488`) as an exponent-field add, so this is exact and
allocation-free at every rung.

### Performance

Neither is on a warm path. Both are new methods and must not perturb existing
dispatch — checked: `Base.ldexp(x::T, e::Integer) where T<:IEEEFloat` is
disjoint from `T<:Binary`, and `Base.eps(v::T) where {T<:Binary}` is strictly
more specific than `eps(x::AbstractFloat)` and disjoint from
`eps(::Type{<:Binary})`. No ambiguity, so `Test.detect_ambiguities` (already in
the suite) is the standing check.

### Pins

1. Add `(:eps, eps)` and `(:ldexp_pow2, v -> ldexp(v, 1))` to G10's veneer list
   (`test/gates_g10.jl:207-235`). That list's stated principle — sweep what the
   subtype *promises*, not what the package provides — is exactly why they
   belong there.
2. **Independent-witness identity**, exhaustive over every finite nonzero code
   point at K ≤ 8 and over the tier's representative set above:
   `decode(eps(v)) == 2.0^(Qref)` where `Qref` comes from `Base.decompose` on
   the decoded datum, not from `round_to_precision`. Using the same function on
   both sides would prove nothing.
3. **`eps` returns a datum**, for every code point of every format in the tier's
   set: `eps(v) === T(decode(eps(v)))`.
4. **Session-independence:** `eps` and `ldexp` give the same answer under
   `DefaultProjection!(RTZ_SF)` as under `RNE_SN` for every in-range input. This
   pins the `rawvalue` choice and would have caught the `T(NaN)` spelling.
5. While in that list, audit it once against `AbstractFloat`'s full surface and
   record the deliberate absences as `_NO_BASE_COUNTERPART`
   (`juliacompat.jl:70-78`) does for the registry side. `modf`, `flipsign`,
   `cbrt`, `div`/`fld`/`cld` are the candidates.

---

## W4 — `datumsexact`'s unsigned `emax`

### Current

`src/carriers.jl:283-288`: `emax = S ? B - 1 : 0`, with a docstring (`:275-278`)
claiming an unsigned format "spends its whole exponent field below 1, so
`Binary16p1uf`'s datums run down to `2^-32769` while its largest is `0.5`."

The decoder disagrees. `Binary8p4uf`: `expbias` = 2^(K−P) = 16, `MaxFiniteOf` =
254, `_decode_compute` gives `Eb = 254 >> 3 = 31`, `tsig = 6`, `sig = 14`,
`e = 31 − 16 + (1 − 4) = 12` — largest datum 14·2^12 = 57 344, exponent
**15 = B − 1**. `Binary16p1uf`'s largest datum is 2^32766 and its least positive
is 2^-32767.

It changes no current answer, and the reason is why nothing caught it: for every
row in `_extexprange` the subnormal condition binds strictly first, at every
power-of-two bias, with **exactly zero margin**:

| target | subnormal ⇒ `B ≤ 2−P−lo` | true normal ⇒ `B ≤ hi+1` | power of two in the gap |
|---|---|---|---|
| `Float64` | ≤ 1076−P | ≤ 1024 | none |
| `Float32` | ≤ 151−P | ≤ 128 | none |
| `Float16` | ≤ 26−P | ≤ 16 | none |
| `BFloat16` | ≤ 135−P | ≤ 128 | none |

`datumsexact` is the sole guard on `decode!`'s exactness promise
(`kernels.jl:190-226`), and `formats.jl:602` already refers to
`datumsexact(Float128, F)` for a type absent from `_extexprange`.

### Design

Land the one-token fix alone: it changes no behaviour, so its pin is the
deliverable. Then decide `Float128` separately — with `emax = B − 1` correct,
adding `(-16494, 16383)` is safe and makes `formats.jl:602`'s reference real.
Without the fix it would be the first live instance of the defect.

The pin must be an **independent witness**, not a restatement of the formula.
`test/gates_g6.jl` already has both the tool and the subject: it enumerates
every datum of every format against `Base.decompose`, normalized, as "an
*independent* witness — it does not go through any conversion this gate is
testing" (`:13-20`). Extend it, folding the new counts into G6's single
`record_gate!` call — `gatelog.jl:47-48` errors on double registration by
design.

### Code

```julia
# carriers.jl
    # `emax` is `B − 1` for BOTH signedness classes. The unsigned row read `0`,
    # from a reading of the exponent field the decoder does not implement:
    # `Binary8p4uf`'s largest datum is 57 344 = 14·2^12, exponent 15 = B − 1.
    # (It is B − 2 when P = 1, so B − 1 stays a sound upper bound.)
    #
    # It changed no answer, and that is the part worth recording: for every type
    # in `_extexprange` the subnormal condition binds first at every
    # power-of-two bias, with zero margin. The gate in gates_g6.jl now checks
    # this against enumerated datums instead of resting on that coincidence.
    emax = B - 1
```

```julia
# test/gates_g6.jl, reusing this gate's existing `_norm` witness
for F in FORMATS, X in (Float64, Float32, Float16, BFloat16)
    claimed = SmallFloats.datumsexact(X, F)
    actual = all(0:(1 << bitwidth(F)) - 1) do c
        d = decode(rawvalue(F, codeunit_type(F)(c)))
        isfinite(d) || return true               # specials are not datums
        _norm(X(d)) == _norm(d)                  # exact round-trip into X
    end
    @test (formatname(F), X, claimed) == (formatname(F), X, actual)
end
```

`X(d)` for a rung-3 `d` goes through `Float32(::Dyadic)`/`Float16(::Dyadic)`
(`dyadic.jl:838-839`) and can overflow to `Inf`, which `_norm` reports as
non-finite and therefore unequal — the correct answer.

### Performance

`datumsexact` is `@inline` and folds to a literal per `(X, F)` pair; changing a
ternary to a constant can only help. The gate itself is 2^K per format per
target — ≤ 65 536 × 4 for the widest — cheap enough to run exhaustively at every
tier. Prefer that and say so, rather than sampling something affordable.

### Pins

1. The enumeration passes for all 504 formats × four targets, exhaustively, at
   every tier.
2. G5 digests byte-identical. The fix is a no-op today; if digests move, it was
   not.
3. `_extexprange` gains its `Float128` row, or `formats.jl:602`'s reference goes.
   A dangling reference is the state this finding came from.
4. The docstring's second bullet is rewritten with the corrected arithmetic and
   a real example.

---

## W5 — `saturate`: dispatch without a union

### Current

`src/project.jl:365-431`. `saturate` returns one of six `Symbol`s; `project`
consumes them with a `===` chain (`:424-430`). Exactly one call site in `src/`.
The tests use an independent `refsaturate` (`test/refimpl.jl:185`) which must
not change.

`RM` and `SM` are static type parameters so the current form folds; the
objection is that this is the one stringly-typed protocol at the centre of the
single write path, it is the shape invariant 9 was written against, and a
mistyped symbol falls through to the `nan` catch-all at run time.

### Design — and the version that was rejected

**Rejected: `saturate` returns an abstract `SatOutcome`, consumed by `_emit`.**
This introduces a **six-way small union** where a concrete `Symbol` stands
today. Julia's union-splitting budget is small — historically four — so
inference can decline to split six singleton return types and leave a dynamic
dispatch inside `project`: a 6.7 ns, zero-allocation function on every write
in the package. G5 digest equality would not detect it, because digests are
about values.

**Adopted: fold emission into the per-mode dispatch, and keep classification as
a separate, non-hot function.** Two functions with two jobs:

- `saturate(T, ρ, r)::T` — dispatches on `SM()` and returns the **code point**.
  Every method has one concrete return type; there is no intermediate value for
  inference to widen; `project` calls it and returns.
- `saturation_outcome(T, ρ, r)::SatOutcome` — the same rows returning tags,
  used by tests, by `refimpl` comparison, and by anything that wants to *see*
  the classification. Not called by `project`.

That is duplication, and it is the kind worth paying for: the two must agree,
and "they agree" is a testable statement over an enumerable grid rather than a
structural hope. The alternative — one function, one union, one hot path — trades
a checkable duplication for an uncheckable performance risk.

Within `saturate`, the `if sat isa SatFinite` chain becomes three methods, one
per saturation mode, each reading as the draft's rows for that mode. `SatNone`
keeps its internal branching on the rounding mode and on `EXT`/`SGN`: those are
genuine draft-row conditions and forcing them into dispatch would obscure rather
than clarify. Invariant 9 is about *policy* selection, and the policy here is
the saturation mode.

### Code

```julia
"""The six outcomes of ωSaturate (draft §4.7.5), as singleton tags. The set is
closed and enumerable, so a totality test can assert the rows cover the
`(SM, RM, Σ, Δ, kind, over/under)` grid — which the `Symbol` protocol could not
express, and which a fall-through to `:nan` silently absorbed."""
abstract type SatOutcome end
struct AsIs   <: SatOutcome end
struct MaxFin <: SatOutcome end
struct MinFin <: SatOutcome end
struct PosInf <: SatOutcome end
struct NegInf <: SatOutcome end
struct NaNOut <: SatOutcome end
const SAT_OUTCOMES = (AsIs(), MaxFin(), MinFin(), PosInf(), NegInf(), NaNOut())

# Shared range test. Returns the two flags the mode rows branch on, so the three
# `_sat_*` methods below never re-derive them and cannot derive them differently.
@inline function _sat_range(::Type{T}, r::Rounded) where
        {K,P,SGN,EXT,T<:Binary{K,P,SGN,EXT}}
    Shi, Qhi = _extremal_SQ(T)
    overmag = (r.Q > Qhi) | ((r.Q == Qhi) & (r.S > Shi))
    (overmag & (r.sign > 0), SGN ? (overmag & (r.sign < 0)) : (r.sign < 0))
end

# The hot form: one concrete return type per method, no intermediate tag, no
# union for inference to widen. This is the ONLY form `project` calls.
@inline function saturate(::Type{T}, ρ::ProjSpec{RM,SM}, r::Rounded)::T where
        {K,P,SGN,EXT,T<:Binary{K,P,SGN,EXT},RM,SM}
    r.kind == KIND_NAN && return rawvalue(T, nan_code(T))
    over = false; under = false
    if r.kind == KIND_FIN
        r.S == 0 && return rawvalue(T, encode(T, Int(r.sign), r.S, r.Q))
        over, under = _sat_range(T, r)
        (!over & !under) && return rawvalue(T, encode(T, Int(r.sign), r.S, r.Q))
    end
    _sat(SM(), RM(), T, r, over, under)
end
```

with `_sat(::SatFinite, …)`, `_sat(::SatPropagate, …)`, `_sat(::SatNone, …)`
carrying the current rows verbatim, each returning `T` directly.
`saturation_outcome` mirrors the same three methods returning tags. `project`
becomes:

```julia
    r = round_to_precision(P, B, RM(), X, R, sticky)
    saturate(T, ρ, r)
```

### Performance

**This is the highest-risk change in the plan** and the only one that touches a
warm path. It must be measured, not reasoned about:

- `project` is 6.7 ns median / 2.2 ns min, zero allocations
  (`benchmark_report.md`, Core primitives).
- Every write in the package goes through it — scalar, array Shape-B, table
  build, block projection.

The suite already contains the right pins; they must be read as W5's gate rather
than as background:

- `Base.return_types(project, Tuple{Type{T}, typeof(RNE_SN), Float64}) == [T]`
  (`test/runtests.jl:1377`) — catches a widened return.
- `@allocated(prj(2.3)) == 0` (`:1386`) — catches a boxed dispatch.

Add one more, because neither of those catches a *devirtualization* loss that
happens to stay concrete and non-allocating:

```julia
@test !any(e -> e isa Expr && e.head === :call &&
                e.args[1] isa Core.SlotNumber,      # dynamic dispatch marker
           first(Base.code_typed(project, Tuple{Type{T}, typeof(RNE_SN), Float64}))[1].code)
```

or, more robustly, assert on `@code_typed`'s absence of `dynamic` in the
optimizer output for the same signature. Whichever spelling, the requirement is:
**no dynamic call inside `project` after the change.**

And a benchmark diff, not just digests: regenerate the Core primitives table
before and after, in alternating single-variant processes per the benchmark
doctrine. A same-process comparison of two variants is not a measurement here —
`dyadic.jl:241-243` records exactly that mistake.

### Pins

1. **G5 golden digests byte-identical**, run at `SMALLFLOATS_G5=full`. This
   touches the write path for every value in the package, and `CLAUDE.md` names
   exactly that as the condition requiring the full tier.
2. **Inference and allocation pins above hold**, plus the no-dynamic-call
   assertion.
3. **Benchmark diff on `project`** within noise, measured in alternating
   single-variant processes.
4. **Agreement test:** for every `(SM, RM)` in the mode vocabulary, every
   `(Σ, Δ)`, and every `Rounded` kind including both over and under,
   `saturate(T, ρ, r) === _emit_of(saturation_outcome(T, ρ, r), T, r)`. This is
   what buys the duplication.
5. **Totality:** `saturation_outcome` returns a member of `SAT_OUTCOMES` over
   the same grid.
6. `test/refimpl.jl`'s `refsaturate` unchanged — it is the independent
   reference, and changing it in the same commit destroys the comparison.
7. **Alone in its commit**, and after W4 has been shown digest-neutral.

If any of 1–3 fails, revert. The `Symbol` protocol is a clarity defect, not a
correctness one, and it is not worth a nanosecond on the write path.

---

## W6 — benchmark evidence

### Current

Corrected above: the harness covers four rung representatives in format
sensitivity (`:299-308`), emits full provenance (`:478-505`), and has a
rung-aware `preflight` (`:187-222`). `allocation_profile` (`:226-239`) is
written and never called. The checked-in report predates all of it by one
commit.

Everything else in the report is `Binary8p4se`-only: core primitives, twelve
scalar tables, array kernels, sorting, table builds, blocks
(`bench_blocks(Binary8p4se, Binary8p1uf)`), conversions.

### Design — four steps, strictly ordered

Each step's output decides whether the next is worth doing. That ordering is
the throughput argument: step 1 is one command and may close two findings.

**1. Regenerate.** Do not plan past it before reading the result.

**2. Wire `allocation_profile`.** It is written; it needs a table, over the same
four rung representatives. `CLAUDE.md`'s benchmark doctrine asserts a per-rung
allocation contract in prose — exact selections zero at every rung
unconditionally, arithmetic allocating exactly when the operand spread exceeds
the carrier's exact range, the enclosure ladder allocating at rungs 2 and 3 by
construction. Emitting the measured table beside the claimed one makes that
paragraph falsifiable.

**3. Widen only where the rung changes the code path**, not everywhere:

- **Core primitives.** `decode` under `ComputeDecode` is a *different function*
  from the `TableDecode` gather (`decode_encode.jl:129-132`), and `order_key` at
  `Code16` uses a `UInt32` key. These are the rows where a wide format measures
  different code rather than the same code with a different type parameter.
- **Array kernels.** At K ≥ 9 the interesting result is the **Shape-A/Shape-B
  boundary**: a binary table at K = 16 is 2^32 entries, `table_for` declines,
  and the compute kernel is the only path. `table_policy`
  (`tables.jl:195-223`) already returns `(; shape, entries, bytes, reason)` —
  print `reason` in the row so a slow number explains itself.
- **One wide block row**, `bench_blocks(Binary16p5se, Binary16p1uf)`:
  `blockdecode`'s carrier is `rung(Val(:Multiply), FS, FE)` and the P = 1 fast
  path (`blocks.jl:95-109`) is the MX shape.

Sorting, table builds, and the scalar operand-class tables stay at the reference
format — they measure policy and dispatch, not carrier.

**4. Cold-start.** `SmallFloats.jl:245-268` records "≈ 1.8 s per format,
essentially all specialization" as the *motivation* for the wide precompile
entries; `formatsel.jl:12-17` records "21.5 s cold and 0.0 s warm" for a
20-format × 27-ρ sweep. Those are the largest user-visible costs in the package
and both live in source comments. A short section — time to first `Add` on a
format at each rung, in a fresh process — is the number a user needs when
choosing a format.

### Pins

1. The checked-in report carries a commit SHA matching the source that produced
   it, and its format-sensitivity table names four rungs.
2. An "Allocation by rung" table exists, and its rows are consistent with
   `CLAUDE.md`'s benchmark doctrine — or the doctrine is corrected to match the
   measurement and the changelog says which way it went.
3. Array-kernel rows print `table_policy`'s `reason`.
4. A cold-start section exists with one row per rung.

---

## W7 — package throughput

Grouped as one workstream because both halves are the same thing — more workers
through `_scalar_code` — and both rest on the same correctness constraint.

### The constraint

Invariant 6: *a table entry IS the defined result*, one trip through the
oracle-backed scalar path. Parallelism may change who runs that trip and when;
it may not change the trip. Two facts make it sound here:

- `setprecision`/`setrounding`'s function forms are `ScopedValue`-backed on
  Julia 1.12 (`base/mpfr.jl:1210`, `:248-249`), so the MPFR escalations inside
  `_scalar_code` are **task-local**. This is the same fact that justifies the
  1.12 floor in W8, and it is what makes any of this legal.
- Pure ρ is deterministic per element (`kernels.jl:78-101` already relies on
  this for the threaded ternary loop), so results do not depend on execution
  order. Stochastic ρ must stay sequential — one rng stream, reproducible draws
  — exactly as the ternary loop already arranges.

### 7a — thread the unary/binary Shape-B loops

`THREADED_KERNELS` and `THREAD_MIN_ELEMS` (`kernels.jl:69-72`) are package-level
`Ref`s consulted by exactly one loop (`:90-97`). At K ≥ 9 a declined table is
the **common** case — `table_for` returns `nothing` above `TABLE_EAGER_BITS`, so
every wide binary array operation runs `_vmap_scalar!` — and that is the one
array path that never threads.

The construction is the ternary loop's, verbatim: pure ρ, `AbstractUnitRange`
indices, above `THREAD_MIN_ELEMS[]`, `Threads.@threads`. The stochastic branch
stays sequential.

Expected effect: near-linear on the wide-format array path, which is currently
the *only* path for those formats. This is the largest single throughput item
available.

Either do this or rename the two `Ref`s to say they govern the ternary kernel.
Naming that implies more generality than the implementation has is the same
species as everything else in this cycle.

### 7b — parallel table builds

`_build_unary` (`tables.jl:256-265`), `_build_binary` (`:267-282`) and
`_build_ternary` (`:360-378`) are serial loops over an embarrassingly parallel
domain. A 2^16-entry table at the measured ~1 µs/entry is ~65 ms of first-call
latency; the K = 16 unary case is exactly that size.

`docs/other/doingtheextensions.md:1118` already lists "parallel build" as a
planned `tables.jl` item, so this is a scheduled idea rather than a new one.

Three constraints, all local:

- The build already runs **outside** the cache lock (`_cached_table`,
  `:304-315`, with the double-checked pattern and the explicit note that a
  racing duplicate build is benign). So threading the build needs no lock
  changes.
- Writes are to disjoint indices of a preallocated `Memory`, so there is no
  reduction and no ordering question.
- The result must be **identical**, not merely equivalent: `gates_shape.jl`
  already asserts table ≡ scalar, so it is the standing witness.

Chunk over the outer code loop (`c1`) rather than over the flat index, so each
task decodes its own `x1` once — the current loop's own structure.

### 7c — the two block allocation centres

Measured, not guessed: `ConvertToBlockMaxAbsFinite` at 111 allocations / 3.95 µs
and `BlockAdd` at 35 allocations / ≈ 1 per lane, B = 32.

- **`BlockAdd`**: `blocks.jl:311-317` recomputes `h = _joinheads(...)` *inside*
  the `ntuple(Val(B))`. The head is a function of the two blocks' formats, not
  of the lane index, so it hoists out of the closure entirely.
- **`ConvertToBlockMaxAbsFinite`**: `_joinheads(X...)` (`blocks.jl:522`) is a
  splat — precisely the construction §11 M46 measured boxing 304 bytes per call
  on `Float128` and 592 on `Dyadic` in `apply_op`, where every *component*
  measured zero. The fix there was `Vararg{Any,N}` (`ops_scalar.jl:224-225`);
  the same treatment applies here.

Measure at the entry point, not by assembling the parts. That is the recorded
lesson and the reason the earlier `apply_op` profile had to be retaken.

### Pins

1. `gates_shape.jl` (table ≡ scalar) unchanged and green — the witness for 7b.
2. Threaded and sequential `vmap!` produce **identical** arrays for pure ρ, over
   the tier's format set. Not "equal within tolerance" — identical code points.
3. Stochastic ρ remains sequential and remains seed-reproducible; the existing
   stochastic-reproducibility test is the guard.
4. Each allocation fix ships with unchanged G5 digests and unchanged
   block-composition tests. Execution strategy may change; numerical meaning may
   not.
5. Every throughput claim is measured in alternating single-variant processes,
   with an accumulator that `Base.donotdelete` protects — the benchmark
   doctrine's two recorded harness failures are both live hazards here.

---

## W8 — release state and small items

### Release state

**`docs/pdf/build`** — migration, not deletion. `docs/pdf/build/README.md`
documents it as editable LaTeX source with a stated recompile command and a
regeneration path (`docs/pdf/buildpdf.sh`). Untracking it blind deletes a
documented workflow. In order: decide what is genuinely source (`custom.sty`,
`howto.md`, `buildpdf.sh`, the transform scripts); move the reproducible output
(`_minted/`, 251 files; `pages/`, 195 PNGs; post-transform `main.tex`, `.xdv`,
`.toc`, the manifest) to the release artifact `release.yml` already builds; add
`docs/pdf/build/` to `.gitignore` with the retained files re-included by
negation so the intent reads from the ignore file; update the README in the same
commit.

**Tag 0.4.0.** `release.yml` triggers on `tags: ["v*"]` and has never fired.
Release automation that has never run is untested automation — the conformance
invocation, the artifact paths and the PDF toolchain step are all unverified.
Tagging is the test.

**Record the 1.12 floor**, beside `Project.toml`'s `julia = "1.12"` and in the
README:

> `setprecision`/`setrounding`'s function forms are `ScopedValue`-backed as of
> Julia 1.12 (`base/mpfr.jl:1210`, `:248-249`). On 1.11 they mutate process
> globals, making concurrent MPFR escalation unsound — and the ternary compute
> kernel threads by default (`kernels.jl:90-97`), as does any user
> `Threads.@threads` over an operation that can reach the enclosure ladder.

**CI run metadata.** `release.yml` already uploads the roll-call log and
`conformance.txt`. Add a JSON with Julia version and build, `Sys.CPU_NAME`,
`Threads.nthreads()`, commit SHA, dirty state, `SUITE_TIER`, `LOOP_SCALE`, gate
count and total compared units. That artifact is what makes a conformance claim
reproducible rather than merely printed.

### Small items

Group into one commit per theme.

- **Bulk `Convert` takes `rng`.** `kernels.jl:170-171` has no `rng` keyword
  while the scalar form and every generated array operation do, so a stochastic
  bulk conversion cannot be given an owned stream — the one thing
  `defaults.jl:98-114`'s entropy decision tells callers to do.
- **`add_dy_checked`.** `dyadic.jl:261-262`'s `_add_aligned` computes
  `big.S << d` with `d` up to `DYADIC_ALIGN_MAX = 94`, sound only while the head
  carries ≤ `DYADIC_HEAD_BITS = 32` bits; `add_dy` is exported. `mul_dy` /
  `mul_dy_checked` (`:297-343`) is the module's own answer to this question,
  with a measurement behind it. Apply it to the second operation that needs it.
- **Delete `formats.jl:463-482`.** The commented-out `Base.show` pair is
  superseded by `show.jl`, and the reason — method overwriting is a
  precompilation *error*, which silently ran the package unprecompiled — is
  recorded at `show.jl:121-122` and in the changelog.
- **`measure_kappa`'s docstring** (`approx.jl:52`): "always true for arity ≤ 2"
  is false above K = 11 per operand pair (2^22 budget, 2^32 points at 16 × 16).
- **Stage-referencing runtime errors.** `oracle.jl:374-381`, `:453-455`,
  `:476-479` tell users a capability "arrives in Stage 6 of the K ≤ 16
  extension" — for stages that shipped. Rewrite to name the operation, the
  carrier, and the fact that the combination has no ω-semantics; stage history
  stays in `implementextensions.md §11`.
- **`show.jl:37-42`'s per-call re-validation.** `set_show_style!` already
  validates; only the `IOContext` path needs checking.

---

## W9 — make the doctrine executable

`CLAUDE.md` names its own problem: "a doctrine file is code that nothing
executes." Most claims have executors; three did not, and all three close above.
The deliverable is the table, kept beside the doctrine, so the count cannot
creep back.

| Claim | Executor |
|---|---|
| Include order matches the comment | `stage_gates.jl` scan against `SmallFloats.jl` |
| 504 formats, K ∈ 3:16 | `docs_consistency.jl` |
| `Binary{K` never appears in a method body | `stage_gates.jl` |
| NaN sorts first, below −Inf | T1 order sweep |
| Warm scalar paths allocate zero | specialization regressions (`runtests.jl:1372`) |
| `Float128=disable` is bit-identical | differential build gate |
| Fourteen roll-call entries | `REQUIRED_GATES` |
| Total compared units | roll-call — **plus `LOOP_SCALE` in the header (W2)** |
| G8 has no file, deliberately | roll-call's uncovered list |
| Rung partition is 432/64/8 | G9 |
| Allocation by rung | **W6 step 2** — function exists, unwired |
| `datumsexact` is sound | **W4** — enumeration in G6 |
| No dynamic dispatch in `project` | **W5** — inference pin |
| Table ≡ scalar under threading | **W7** — `gates_shape.jl`, already standing |

Two documentation edits belong here:

- **State the invariant-9 carve-outs.** Display style (`show.jl`) and the oracle
  result-kind branch (`_bp_element`) branch on values deliberately. A stated
  exception is a decision; an unstated one is a violation nobody got to.
- **Do not thin the measurement post-mortems out of the source.**
  `dyadic.jl:219-243` records a 1.87× "win" that inverted to a 20% loss under a
  corrected harness and says which conclusion survives. That knowledge has no
  other home where it will be read at the moment it is needed. What can move to
  `implementextensions.md §11` is stage numbering — especially where it leaks
  into user-facing error text.

---

## Sequencing

| Tranche | Contents | Exit condition |
|---|---|---|
| **1 — reachable defects** | W1, W2, W3, W4 as four independent commits, each with its own pin | Every fix has a test that fails without it; `rollcall.jl`'s uncovered list is true; `CLAUDE.md`'s unit figure names its tier. W4 verified digest-neutral |
| **2 — evidence** | W6 steps 1–2 (regenerate, wire `allocation_profile`) | Report matches a named commit and carries the per-rung allocation table. Its output re-scopes steps 3–4 |
| **3 — release state** | W8 in full; tagging last | `release.yml` has fired once and its artifacts are correct |
| **4 — write-path refactor** | W5 alone | Digests identical, inference and allocation pins hold, no dynamic call in `project`, benchmark diff within noise. Revert on any failure |
| **5 — measured performance** | W6 steps 3–4, then W7 | Report substantiates all three rungs; threaded and sequential kernels are bit-identical; `CLAUDE.md`'s allocation paragraph is a measured table |
| **ongoing** | W9 | No falsifiable doctrine claim lacks an executor, and the ones that cannot have one say so |

Tranches 1 and 2 land together and quickly. 3 is bounded. 4 is small and must
not share a commit with anything. 5 is a cycle's worth of work and is the one
that changes what users can decide.

---

## Risk register

| Risk | Containment |
|---|---|
| W1's screen unsound for some format | Pin 2 checks `screen-false ⊆ enumeration-false` exhaustively at K ≤ 8. On failure, delete the screen and keep the budget — the budget alone fixes the throw |
| W2 moves a published coverage number | Expected and stated. Record the new default-tier total; print `LOOP_SCALE` beside it thereafter |
| W3's `eps` disagrees with IEEE intuition | It agrees: the construction reproduces `nextfloat(x) − x`, and pin 2 compares against `Base.decompose` — a different function — over every K ≤ 8 code point |
| W3 introduces a method ambiguity | `detect_ambiguities` is already in the suite; the two new signatures were checked disjoint by hand |
| W4 changes an answer after all | G5 digests catch it; the fix is one token to revert |
| **W5 loses devirtualization in `project`** | **The reason W5 was redesigned.** Inference pin, allocation pin, no-dynamic-call assertion, and an alternating-process benchmark diff. Revert on any failure |
| W5 changes a code point | G5 digests at `full`, in a commit touching nothing else |
| W7 threading changes results | Bit-identical comparison of threaded vs sequential over the tier's format set; stochastic path stays sequential and seed-reproducible |
| W7 measurements mislead | Alternating single-variant processes with a protected accumulator. Both recorded harness failures — same-process variants, and dead-code elimination — are live hazards for exactly this kind of loop |
| W8 deletes something that was source | Migration reads `docs/pdf/build/README.md` first and updates it in the same commit |

---

## Deliberately not doing

- **The projection engine, oracle protocol, and carrier lattice stay.** W5
  changes a protocol's shape, not its semantics, and must be digest-identical
  and dispatch-neutral or reverted.
- **No split of `oracle.jl` or `dyadic.jl` by size.** Both are deep modules with
  real interfaces. The only defensible seam is exact arithmetic versus enclosure
  construction, and only if it earns a tested boundary.
- **No optimization of the sub-10 ns scalar paths.** Zero-allocation and near
  the floor. The wide-format array path (W7a) is where the throughput is.
- **No widening of the default export surface** to the other 384 aliases. The
  asymmetric-reversibility argument at `SmallFloats.jl:90-116` holds.
- **No deepening of G10.** It earns its place by being total and shallow, and
  says so. Add verbs to its list; do not add assertions to its probes.
- **No second meaning on `with_default_*`.** Overloading the name is how the
  0.3.0 documentation defect happened.
- **No `Ops`/`Blocks`/`Approx` namespaces this cycle.** The prior guide decided
  against mirroring exports with shallow adapters, and nothing in the second
  review changes that. The block surface's size is a real observation, not a
  defect.
- **No in-place packed arithmetic**, no implicit cross-format promotion, no
  runtime-symbol rounding modes. All three are stated scope limits and all three
  are load-bearing.
