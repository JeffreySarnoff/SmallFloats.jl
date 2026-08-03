# SmallFloats.jl Improvement Guide — second cycle

## Purpose and method

This guide turns `doc/other/reviewed1.md` and `doc/other/improved1.md` into an
implementation plan grounded in the current repository at `3e940d6`
(main, clean, package 0.4.0). Every workstream below was traced against the
actual source, the gate files, the benchmark harness, and Julia 1.12's Base, so
the code shapes are the ones that will compile in this tree rather than
illustrative sketches.

No tests and no benchmarks were executed. The suite is taken to pass; the
checked-in report is the performance baseline.

It supersedes nothing in `doc/other/improvement_guide.md` — that guide covered
the 0.4.0 tranche, and its "Decisions refined against the local design" table is
still binding. This guide adds the decisions the second review forced and
revises one of them (the PDF tree) only in scope, not in direction.

## Two corrections to `improved1.md`

Both were found while tracing the benchmark harness, and both narrow the work.

**The benchmark harness already covers all three carrier rungs and already
emits provenance.** `benchmarking/benchmarking.jl:299-308` benches format
sensitivity over `Binary8p4se`, `Binary16p8se`, `Binary16p5se`, `Binary16p1uf`,
`Binary3p1se` — explicitly "one representative of Code8/rung 1, Code16/rung 1,
rung 2, and rung 3" — and `:478-505` emits commit SHA, dirty state, package
version, and seed into the report header. That landed in `5e70873`
(2026-08-03). The checked-in `benchmark_report.md` was last regenerated at
`51abbc9` (2026-08-02), one commit earlier.

So the report is **stale, not incapable**. `improved1.md` §C1 and §C3 said
"extend the harness"; the correct first action is `regenerate`. What remains
genuinely missing after regeneration is smaller and is scoped in W6.

**`allocation_profile` is defined and never called.**
`benchmarking/benchmarking.jl:226-239` computes exactly the per-rung allocation
table `CLAUDE.md`'s benchmark doctrine asserts in prose — selection / add / fma /
ladder, tagged with rung and carrier name. `generate_report` never invokes it.
That is the same species as every finding in `reviewed1.md`: a claim whose
executor exists but is not wired to anything.

## Decisions refined against the local design

| Topic | Local decision | Reason |
|---|---|---|
| `f32_exact` scope | Serve **every** K, behind a stated entry budget; do not restrict to K ≤ 8 | The question is meaningful at K ≥ 9 (`Binary9p4se` has B = 16, P = 4 — all datums Float32-exact), and enumerating 2^18 pairs is cheap. Restricting would be a scope claim the signature contradicts |
| `f32_exact` fast-`false` screen | `datumsexact(Float32, ·)` on both operand formats, justified by a **witness construction**, and pinned as a subset of enumeration-`false` | Sound only because `P ≤ 16 < 24`, so the trait can fail only by range or by underflow-to-zero — both of which exhibit a concrete inexact pair. A precision-only failure would not be provable and cannot occur here |
| `f32_exact` budget units | Pairs, `2^(K1+K2)`, in a `Ref`, floor 2^16 | Same unit as the thing bounded, and 2^16 is the fixed point at which **no K ≤ 8 answer changes** — the same argument `TABLE_EAGER_BITS` makes for itself |
| Loop-count tier | One `LOOP_SCALE` derived from `SUITE_TIER` in `formatsel.jl`; full literals become the source of truth | The tier dial already exists and is already the single place every other axis reads. A second mechanism would be the defect being fixed |
| Default-tier cost | Accept a one-time move in the roll-call's total, and record the new number | Today's divisors are inconsistent (4 for most, 5 for `K5`/`TEN5`), so no single scale reproduces them exactly. Pretending otherwise would require keeping the mixed divisors, i.e. keeping the defect |
| `eps(x::Binary)` | Define directly from `round_to_precision`'s `Q`, not by lattice walking or by Base's formula | `Base.decompose` (`juliacompat.jl:135-142`) already establishes that reusing the engine's own normalization is how a derived quantity avoids drifting from it. It also removes the top-binade and subnormal edge cases outright |
| `ldexp(x::Binary, n)` | Add it; exact on the carrier, one `project`, saturation from the session default | It is `significand`'s construction (`juliacompat.jl:180-190`) with a different exponent, and `eps`'s Base fallback needs it |
| `datumsexact` fix | `emax = B - 1` unconditionally; land it alone | Changes no current answer (verified against all four `_extexprange` rows), so it is separable from anything else and its pin is the deliverable |
| `saturate` protocol | Six singleton tags replacing six `Symbol`s; `project` dispatches | One call site (`project.jl:424`), and G5's golden digests are a byte-exact oracle for "this was a refactor" |
| `_bp_element` branch | Leave the `res isa …` chain | The result kind is genuinely dynamic there and the union is the oracle's declared protocol. Add a comment stating the carve-out rather than forcing dispatch |
| `show.jl` style branch | Leave the branch; drop the per-call re-validation | Display is explicitly not a semantic. Record the carve-out in `CLAUDE.md` so it is deliberate |
| Benchmarks | **Regenerate first**, then wire `allocation_profile`, then widen the remaining sections | The capability gap is one commit of drift plus one unwired function; treating it as new work would rebuild what exists |
| `docs/pdf/build` | Migration, not deletion — unchanged from the prior guide | `docs/pdf/build/README.md` documents it as an editable LaTeX source bundle with a stated recompile command. Untracking it blind destroys a documented workflow |
| Julia 1.12 floor | Record the reason in `Project.toml`'s neighbourhood and the README | `base/mpfr.jl:1210` and `:248-249` make `setprecision`/`setrounding`'s function forms `ScopedValue`-backed. On 1.11 they mutate globals, which would make the threaded ternary kernel and any user-level `Threads.@threads` over an escalating operation unsound. That is a correctness floor, not a convenience |

## Non-negotiable invariants

Carried forward from the prior guide, plus two the second review adds:

1. A defined operation computes the mathematical result and calls `project`
   once.
2. Deterministic projection does not read or advance RNG state.
3. Stochastic `N` remains visible in the type of the rounding mode.
4. An explicit `R` remains a deterministic testing and conformance route.
5. Table entries and compute kernels use the same scalar semantics.
6. Table policy may change cost, never code points.
7. **A refusal is a stated refusal.** No public entry point may fail with an
   exception about a representation type when the caller's error is about a
   format. (`juliacompat.jl:116-118`.)
8. **A tier runs what its name says.** No axis may be narrowed by a mechanism
   the tier dial cannot reach.

---

## Workstream 1 — `f32_exact` over the whole grid

### Current implementation

`src/tables.jl:452-467`. After a cache probe and `_f32op`, the enumeration is:

```julia
for c1 in 0x00:UInt8((1 << bitwidth(f1)) - 1), c2 in 0x00:UInt8((1 << bitwidth(f2)) - 1)
```

`UInt8` is a checked conversion, so `bitwidth(f1) = 9` raises `InexactError`
before the loop starts. The function is exported (`SmallFloats.jl:205`), takes
`Type{<:Binary}`, and its docstring states no K restriction. There is no cost
gate at all: `K1 = K2 = 16` is 2^32 pairs at 300-bit `BigFloat`.

`measure_kappa` had the identical defect and fixed it — `approx.jl:70-75`
records it as finding A1, with the resolution
`codeunit_type(argformats[i])(codes[i])`. This is the same construction, one
file over, unfixed.

### Local design

**Three changes, and the middle one is the only one that needs an argument.**

*The code unit.* Mechanical, and it should read identically to `measure_kappa`'s
fix so the pattern is recognizable rather than two one-offs.

*The fast-`false` screen.* `datumsexact(Float32, F)` (`carriers.jl:283-288`,
loaded well before `tables.jl`) can fail in exactly two ways at P ≤ 16, and both
exhibit a concrete inexact pair — which is what makes the screen sound rather
than merely plausible:

- **Range.** Some datum `x` has `Float32(x) = ±Inf32`. Then for any nonzero
  finite datum `y`, `BigFloat(g(Inf32, Float32(y)))` is non-finite while
  `g(BigFloat(x), BigFloat(y))` is finite. Inexact, witnessed.
- **Underflow.** The format's step `2^(2−P−B)` is below Float32's least
  subnormal, so the smallest positive datum `d` has `Float32(d) = 0.0f0`. For
  `Add`, `0 + Float32(y) = Float32(y) ≠ d + y`; for `Multiply`,
  `0 · Float32(y) = 0 ≠ d·y` for nonzero `y`. Inexact, witnessed.
- **Precision cannot fail.** `datumsexact`'s first condition is
  `P ≤ precision(X)`, and `P ≤ KMAX = 16 < 24`. So there is no third case, and
  the screen never has to reason about a rounding that might coincidentally
  cancel.

That argument is *specific to Float32 and to `P ≤ 16`*. It must be written at
the screen, because it stops being true the moment `KMAX` moves past 24 — and
`KMAX` is a constant the package expects to raise.

*The budget.* Expressed in pairs, `2^(K1+K2)`, with a floor of 2^16 so every
K ≤ 8 signature (max 8+8) is inside it and **no current answer changes**. The
exact default above that floor needs one measurement of per-pair cost — two
300-bit `BigFloat` operations plus two decodes, plausibly 2–5 µs, making 2^20
pairs roughly 2–5 s. Ship `Ref(1 << 20)` and correct it from the measurement
rather than guessing precisely.

Refusal goes through the package's own mechanism. `juliacompat.jl` loads before
`tables.jl` in the include chain (`SmallFloats.jl:70-85`), so `_unsupported` is
available — but its signature is `(f, ::Type{T}, why) where {T<:Binary}` and
this refusal names two formats, so a local `@noinline` thrower in the style of
`_refuse_over_budget` (`tables.jl:159-167`) is the closer fit.

### Implementation plan

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
    "2^$(trailing_zeros(F32_EXACT_MAX_PAIRS[]))-pair budget. Raise " *
    "`SmallFloats.F32_EXACT_MAX_PAIRS[]` to ask for it anyway"))

function f32_exact(op::Symbol, f1::Type{<:Binary}, f2::Type{<:Binary})::Bool
    key = (op, _fkey(f1), _fkey(f2))
    c = lock(() -> get(F32_EXACT_CACHE, key, nothing), TABLE_LOCK)
    c !== nothing && return c
    g = _f32op(op)                       # validates the op before anything else
    # Provably false without enumerating — see the witness construction above.
    # Sound only while P ≤ 16 < precision(Float32); if KMAX ever passes 24 this
    # screen must go, because a precision-only failure has no witness.
    ok = if !(datumsexact(Float32, f1) && datumsexact(Float32, f2))
        false
    else
        ΣK = bitwidth(f1) + bitwidth(f2)
        (1 << ΣK) <= F32_EXACT_MAX_PAIRS[] ||
            _refuse_f32_enumeration(op, f1, f2, ΣK)
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

Two details that matter and are easy to get wrong:

- `1 << ΣK` is safe here because `ΣK ≤ 32` by construction (two K ≤ 16
  formats), unlike `tablebits`, which must compare in bits precisely because
  `ΣK` can reach 48. Say so in a comment, or the next reader will "fix" it into
  the bit form and make it inconsistent with its own budget's units.
- `_f32op(op)` must stay **before** the screen. An unknown op is a caller error
  and must report as one regardless of the formats; moving it after the screen
  would make `f32_exact(:Divide, wide, wide)` return `false` instead of
  throwing.
- `decode(x)` at rung 2/3 returns `Float128`/`Dyadic`; `Float32(::Dyadic)`
  exists (`dyadic.jl:838`) and `BigFloat(::Dyadic)` exists (`:607`), so the body
  is already carrier-generic. The screen makes those paths unreachable anyway —
  no rung-2 or rung-3 format can satisfy `datumsexact(Float32, ·)` — which is
  worth stating so the dead-looking generality is understood as defence.

### Acceptance criteria

Extend `test/float32surface.jl`'s `f32_exact` testset (currently
`:118-137`, scoped to `_K8_FORMATS`):

1. **The pinned counts are unchanged**: Multiply 118/120, Add 88/120,
   Subtract 88/120, `mulfail == [:Binary8p1ue, :Binary8p1uf]`. This is the
   no-regression gate and it must run before anything else in the testset.
2. **The screen is a subset of enumeration.** For all 120 K ≤ 8 formats and all
   three ops: `screen_says_false ⇒ enumeration_says_false`. Implement by
   calling the enumeration directly (bypassing the screen) and comparing. This
   is the pin for the witness argument, and it is exhaustive at K ≤ 8. Note it
   should find that the Add/Subtract columns fail 32 formats the screen passes
   — those fail by arithmetic, not by datum representability — so a test
   asserting equality rather than implication would be wrong.
3. **K ≥ 9 answers rather than throwing**: `f32_exact(:Multiply,
   Binary9p4se, Binary9p4se)` returns a `Bool`.
4. **The budget refuses by name**: `@test_throws ArgumentError f32_exact(:Add,
   Binary16p8se, Binary16p8se)`, and the message contains the budget.
5. **Correct `test/rollcall.jl:75`**, which currently says "`f32_exact`'s
   enumeration at K >= 12, per its section 9 disposition" — implying K = 9, 10,
   11 work. Replace with the budget's actual boundary.

---

## Workstream 2 — put the loop counts under the tier dial

### Current implementation

`test/runtests.jl:46-73`:

```julia
# Main.FastTest = true
#
# if isdefined(Main, :FastTest)

const K5  = div(5000, 5)
const K4B = div(4096, 4)
...
#else
#=
const K5  = 5000
...
=#
#end
```

The `if` is commented out and the `else` is inside a block comment, so the
divided values are the only reachable ones. They drive roughly thirty sampling
loops (`:729-763`, `:834`, `:888`, `:1227`, `:1283-1358`, `:1621-1630`).
`SMALLFLOATS_TIER=release` does not restore them: `test/formatsel.jl:171` owns
the tier and governs the *format* axis; nothing reads these constants.

### Local design

`formatsel.jl` is the right home for `LOOP_SCALE` because it already owns
`SUITE_TIER` and already publishes derived quantities (`exhaustive_requested`,
`quick_requested`, `sweep_formats`). It does its own
`using SmallFloats` (`:45`), so it can be included from `runtests.jl` any time
after that file's own import block ends at `:43` — i.e. immediately before the
constants at `:48`. Other files already include it defensively
(`isdefined(@__MODULE__, :SUITE_TIER) || include("formatsel.jl")`), so adding a
guarded include at the top is consistent and idempotent.

**One dial cannot reproduce today's mixed divisors.** Seven constants divide by
4 and two (`K5`, `TEN5`) by 5. A single scale must pick one. Choosing 4 — the
majority — raises `K5` from 1000 to 1250 and `TEN5` from 10 to 13 at the default
tier, which moves the roll-call's printed total once. That is the honest
outcome and should be recorded in the changelog rather than engineered around;
keeping the mixed divisors to hold a number stable would be keeping the defect
to protect a statistic.

Use `cld`, not `div`: `TEN1` at a quick-tier scale of 8 would otherwise be
`div(10, 8) = 1`, and a "loop" of one iteration is a different test.

### Implementation plan

In `test/formatsel.jl`, beside `SUITE_TIER`:

```julia
"""Divisor applied to every sampling loop count in `runtests.jl`. The full
literals are the source of truth; this is the only thing that shrinks them, and
it moves with `SMALLFLOATS_TIER` so a tier runs what its name says.

`release` is 1 by definition — the doctrine's "a tier the caller asks for is
honoured, never downgraded" is exactly this constant not being greater than 1
there. Before this existed the counts were divided unconditionally and the
`FastTest` switch that once selected them had been commented out."""
const LOOP_SCALE = SUITE_TIER == "release" ? 1 : SUITE_TIER == "quick" ? 8 : 4
```

In `test/runtests.jl`, replacing `:46-73` entirely:

```julia
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

`runtests.jl:1329-1331` ("derived from K5 so it tracks the FastTest scaling.
Fixed point at the original literals: K5 = 5000 ⇒ 100:4000") becomes true again
and its comment should be updated to name `LOOP_SCALE` instead of `FastTest`.

### Acceptance criteria

1. `rollcall.jl`'s header prints `LOOP_SCALE` beside `SUITE_TIER`. A reader
   given "total compared: N" without the scale has a number, not a coverage
   claim — the same argument `rollcall.jl:40-47` already makes for the tier.
2. `rollcall.jl` asserts `LOOP_SCALE == 1` in the same place it already asserts
   a quick run cannot masquerade as a release gate (`:88` onward).
3. The default-tier total is recorded in the changelog, and `CLAUDE.md`'s
   "35 332 465 compared units" is updated to the new default-tier figure with
   the tier named beside it.
4. No occurrence of `FastTest` remains in `test/`.

---

## Workstream 3 — `eps(x)` and `ldexp(x, n)` on `Binary`

### Current implementation

`formats.jl:505` defines `Base.eps(T::Type{<:Binary})`. No value form exists,
and no `Base.ldexp(::Binary, ::Integer)`. Julia's fallback,
`base/float.jl:983`:

```julia
eps(x::AbstractFloat) = isfinite(x) ? abs(x) >= floatmin(x) ?
    ldexp(eps(typeof(x)), exponent(x)) : nextfloat(zero(x)) : oftype(x, NaN)
```

For any finite value at or above `floatmin` — the common case — this reaches
`ldexp(::Binary, ::Int)` and raises a `MethodError` naming `ldexp` at the user's
call site. The subnormal and non-finite rows work by accident (`nextfloat` and
`oftype` are both provided). G10's veneer sweep
(`test/gates_g10.jl:207-235`) omits both verbs.

### Local design

**`ldexp` is the primitive and belongs in `juliacompat.jl`'s AbstractFloat
section.** Scaling by a power of two moves the exponent field and nothing else,
so it is exact on every carrier — the argument `blocks.jl:70-94` already makes
for the P = 1 block fast path. It is `significand`'s construction
(`juliacompat.jl:180-190`) with a different exponent, so it should be written
the same way, including the projection: nearest rounding (which only matters at
overflow, where the value has left the datum set) with saturation from the
session default, so it agrees with `floor`/`ceil`/`round` about the top of the
range.

**`eps(x)` should be written directly rather than inherited**, and the right
construction is the one `Base.decompose` already uses
(`juliacompat.jl:135-142`): run the exact datum through `round_to_precision`,
which on an exact input is pure extraction rather than rounding, and read `Q`.
`Q` *is* the binary exponent of the ulp at `x`.

That construction is better than the two obvious alternatives:

- Better than `decode(NextGreaterThan(v)) - decode(v)`, which walks the lattice
  and needs a special case at the top binade (where `NextGreaterThan` returns
  `Inf` or `NaN` by design, `decode_encode.jl:317-331`), and which on `Dyadic`
  routes through `add_sticky_dy`'s alignment band for no reason.
- Better than Base's `ldexp(eps(T), exponent(x))`, which is wrong in the
  subnormal band (where the step is constant, not scaled) unless guarded.

It also yields a fact worth asserting: **`eps(x)` is always exactly a datum.**
The ulp is `2^Q` with `2−P−B ≤ Q ≤ e_max−P+1`, and every power of two in a
format's range is a datum for every `P ≥ 1`. So the projection is exact and the
rounding mode is irrelevant — which is what makes this safe to define at all
under invariant 1.

Zero is the one special case: `Q` is meaningless for `S = 0`, and Base's answer
there is `nextfloat(zero(x))`, i.e. `MinPositiveOf(T)`. Non-finites follow
Base's `oftype(x, NaN)`.

### Implementation plan

In `src/juliacompat.jl`, after the `exponent`/`significand`/`frexp` block:

```julia
# ---- ldexp: exact on every carrier, one projection.
#
# Scaling by a power of two moves the exponent and nothing else, so this is the
# same construction as `significand` above with a different exponent — and, like
# it, the projection is only reachable at the range boundary. Saturation comes
# from the session default so this agrees with floor/ceil/round about the top of
# the range; the rounding mode is immaterial because the scaling is exact
# wherever the result is a datum at all.
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
# of the ulp. Reusing it means this cannot drift from the format's actual grid,
# and it removes both edge cases Base's formula has: the subnormal band (where
# the step is constant rather than scaled) and the top binade (where a
# lattice-walking definition would run into the Inf encoding).
#
# The result is always exactly a datum: the ulp is 2^Q with
# 2−P−B ≤ Q ≤ e_max−P+1, and every power of two in a format's range is a datum
# for every P ≥ 1. So the projection below cannot round, and the mode is
# immaterial.
function Base.eps(v::T) where {T<:Binary}
    d = decode(v)
    isfinite(d) || return T(NaN)                   # Base's `oftype(x, NaN)` row
    iszero(d) && return MinPositiveOf(T)           # Base's `nextfloat(zero(x))` row
    r = round_to_precision(precision(T), expbias(T), NearestTiesToEven(), d, 0, 0)
    project(T, ProjSpec(NearestTiesToEven(), saturationmode(default_projspec(T))),
            ldexp(one(datumcarrier(T)), Int(r.Q)))
end
```

`ldexp(one(datumcarrier(T)), Q)` rather than `2.0^Q`: at rung 3 the exponent can
reach ±32 768 and a `Float64` literal cannot hold it. `Dyadic` implements
`ldexp` natively (`dyadic.jl:488`) as an exponent-field add, so this is exact
and allocation-free at every rung.

### Acceptance criteria

1. Add `(:eps, eps)` and `(:ldexp_pow2, v -> ldexp(v, 1))` to G10's veneer list
   (`test/gates_g10.jl:207-235`). That list's stated principle — sweep what the
   subtype *promises*, not what the package provides — is exactly why they
   belong there.
2. A direct identity test over a representative format set:
   `decode(eps(v)) == 2.0^Q` where `Q` comes from an independent reference
   (`Base.decompose(decode(NextGreaterThan(v))) - Base.decompose(decode(v))`, or
   `refimpl.jl`'s rounding reference), for every finite nonzero code point at
   K ≤ 8 — exhaustive there, representative above.
3. `eps(x)` is a datum for **every** code point of every format in the tier's
   set: `eps(v) === T(decode(eps(v)))`, i.e. the projection was exact.
4. While in that list, audit it once against `AbstractFloat`'s full surface and
   record the deliberate absences the way `_NO_BASE_COUNTERPART`
   (`juliacompat.jl:70-78`) does for the registry side. `modf`, `flipsign`,
   `cbrt`, `div`/`fld`/`cld` are the obvious candidates to classify.

---

## Workstream 4 — `datumsexact`'s unsigned `emax`

### Current implementation

`src/carriers.jl:283-288`:

```julia
emax = S ? B - 1 : 0
```

with a docstring (`:275-278`) claiming an unsigned format "spends its whole
exponent field below 1, so `Binary16p1uf`'s datums run down to `2^-32769` while
its largest is `0.5`."

The decoder disagrees. For `Binary8p4uf`: `expbias` = 2^(K−P) = 16;
`MaxFiniteOf` = 254; `_decode_compute` gives `Eb = 254 >> 3 = 31`, `tsig = 6`,
`sig = 14`, `e = 31 − 16 + (1 − 4) = 12`, so the largest datum is 14·2^12 =
57 344 — exponent **15 = B − 1**, not 0. For `Binary16p1uf` the largest datum is
2^32766 and the least positive is 2^-32767.

It changes no current answer, and the reason is a coincidence worth recording,
because it is why nothing caught it: for each of the four rows in
`_extexprange`, the subnormal condition binds strictly before the normal-range
condition would, at every power-of-two bias, with **exactly zero margin**:

| target | subnormal ⇒ `B ≤ 2−P−lo` | true normal ⇒ `B ≤ hi+1` | power of two in the gap |
|---|---|---|---|
| `Float64` | ≤ 1076−P | ≤ 1024 | none |
| `Float32` | ≤ 151−P | ≤ 128 | none |
| `Float16` | ≤ 26−P | ≤ 16 | none |
| `BFloat16` | ≤ 135−P | ≤ 128 | none |

`datumsexact` is the sole guard on `decode!`'s exactness promise
(`kernels.jl:190-226`), and `formats.jl:602` already refers to
`datumsexact(Float128, F)` for a type that is not in `_extexprange`.

### Local design

Land the one-token fix alone, because it changes no behaviour and its pin is the
actual deliverable. Then decide `Float128` separately: with `emax = B − 1`
correct, adding the row `(-16494, 16383)` is safe and makes
`formats.jl:602`'s reference real. Without the fix it would be the first live
instance of the defect.

The pin must be an **independent witness**, not a restatement of the formula.
`test/gates_g6.jl` already has the right tool and the right subject: it
enumerates every datum of every format against `Base.decompose`, normalized, as
"an *independent* witness — it does not go through any conversion this gate is
testing" (`:13-20`). Extend it rather than starting a new gate, and fold the new
counts into G6's existing single `record_gate!` call — `gatelog.jl:47-48` errors
on double registration by design.

### Implementation plan

```julia
# carriers.jl
    # `emax` is `B − 1` for BOTH signedness classes. The unsigned row read `0`
    # until 2026-08-xx, from a reading of the exponent field that the decoder
    # does not implement: an unsigned format's largest datum has exponent B − 1
    # (B − 2 when P = 1, so B − 1 remains a sound upper bound), not 0.
    # `Binary8p4uf`'s largest datum is 57 344 = 14·2^12, exponent 15 = B − 1.
    #
    # It changed no answer, and that is the part worth recording: for every type
    # in `_extexprange` the subnormal condition binds first at every
    # power-of-two bias, with zero margin. The gate in gates_g6.jl now checks
    # this against enumerated datums instead of relying on that coincidence.
    emax = B - 1
```

In `test/gates_g6.jl`, a new section reusing its existing `_norm` helper:

```julia
# `datumsexact` is the sole guard on `decode!`'s exactness promise, and it is a
# closed-form claim about an enumerable set — so enumerate it. The witness is
# `Base.decompose`, as everywhere else in this gate.
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

`X(d)` for a rung-3 `d` goes through `Float32(::Dyadic)` / `Float16(::Dyadic)`
(`dyadic.jl:838-839`) and can overflow to `Inf`, which `_norm` reports as
non-finite and therefore unequal — the correct answer.

### Acceptance criteria

1. The enumeration above passes for all 504 formats at the release tier and the
   representative set at default. Cost is 2^K per format per target, which is
   ≤ 65 536 × 4 for the widest — cheap enough to be exhaustive at every tier;
   prefer that and say so.
2. G5's golden digests are byte-identical (the fix is a no-op today, and if the
   digests move, it was not).
3. `_extexprange` either gains its `Float128` row or `formats.jl:602`'s
   reference is removed. Do not leave the reference dangling.
4. The docstring's second bullet is rewritten with the corrected arithmetic and
   a real example.

---

## Workstream 5 — `saturate` from `Symbol` to dispatch

### Current implementation

`src/project.jl:365-431`. `saturate` returns one of six `Symbol`s and `project`
consumes them with a `===` chain:

```julia
    a = saturate(T, ρ, r)
    a === :asis && return rawvalue(T, encode(T, Int(r.sign), r.S, r.Q))
    a === :mhi  && return MaxFiniteOf(T)
    ...
    return rawvalue(T, nan_code(T))
```

`RM` and `SM` are static type parameters, so this folds — but it is the one
stringly-typed protocol at the centre of the single write path, it is the shape
`CLAUDE.md` invariant 9 was written against, and a mistyped symbol falls through
to the `nan` catch-all at run time rather than failing at definition.

There is exactly **one** call site in `src/` (`project.jl:424`). The tests use
their own `refsaturate` (`test/refimpl.jl:185`), which is an independent
reference and must not be changed.

### Local design

Six singleton tags under one abstract type, and the emission moves from a
`===` chain in `project` to `_emit` methods. Three things this buys, in order of
importance:

1. An outcome that does not exist becomes a `MethodError` at definition time
   rather than a silent fall-through to NaN at run time.
2. The outcome set becomes **enumerable**, so a test can assert the rows are
   total over the `(SM, RM, Σ, Δ, over/under/kind)` grid — which today can only
   be asserted by reading.
3. Invariant 9 holds at the centre of the write path instead of everywhere
   except there.

The internal `if`/`elseif` on `sat isa SatFinite` should become dispatch on
`SM()` as well, which splits `saturate` into three small methods — one per
saturation mode — each of which reads as the draft's rows for that mode rather
than as one function that branches into three. The `SatNone` method keeps its
inner branching on the rounding mode and on `EXT`/`SGN`; those are genuine
draft-row conditions and forcing them into dispatch would obscure rather than
clarify.

This is a pure refactor with an unusually strong oracle: **G5's golden digests
must be byte-identical.** If they move, it was not a refactor and must be
reverted rather than re-baselined.

### Implementation plan

```julia
"""The six outcomes of ωSaturate (draft §4.7.5), as singleton tags rather than
`Symbol`s. The set is closed and enumerable, and an outcome with no `_emit`
method is a `MethodError` at definition rather than a fall-through to NaN."""
abstract type SatOutcome end
struct AsIs   <: SatOutcome end
struct MaxFin <: SatOutcome end
struct MinFin <: SatOutcome end
struct PosInf <: SatOutcome end
struct NegInf <: SatOutcome end
struct NaNOut <: SatOutcome end

const SAT_OUTCOMES = (AsIs(), MaxFin(), MinFin(), PosInf(), NegInf(), NaNOut())

@inline _emit(::AsIs,   ::Type{T}, r::Rounded) where {T<:Binary} =
    rawvalue(T, encode(T, Int(r.sign), r.S, r.Q))
@inline _emit(::MaxFin, ::Type{T}, ::Rounded) where {T<:Binary} = MaxFiniteOf(T)
@inline _emit(::MinFin, ::Type{T}, ::Rounded) where {T<:Binary} = MinFiniteOf(T)
@inline _emit(::PosInf, ::Type{T}, ::Rounded) where {T<:Binary} =
    rawvalue(T, posinf_code(T))
@inline _emit(::NegInf, ::Type{T}, ::Rounded) where {T<:Binary} =
    rawvalue(T, neginf_code(T))
@inline _emit(::NaNOut, ::Type{T}, ::Rounded) where {T<:Binary} =
    rawvalue(T, nan_code(T))
```

`saturate` splits by saturation mode, keeping the shared range test in the
dispatcher:

```julia
function saturate(::Type{T}, ρ::ProjSpec{RM,SM}, r::Rounded) where
        {K,P,SGN,EXT,T<:Binary{K,P,SGN,EXT},RM,SM}
    r.kind == KIND_NAN && return NaNOut()
    over = false; under = false
    if r.kind == KIND_FIN
        r.S == 0 && return AsIs()
        Shi, Qhi = _extremal_SQ(T)
        overmag = (r.Q > Qhi) | ((r.Q == Qhi) & (r.S > Shi))
        over = overmag & (r.sign > 0)
        under = SGN ? (overmag & (r.sign < 0)) : (r.sign < 0)
        (!over & !under) && return AsIs()
    end
    _saturate(SM(), RM(), T, r, over, under)
end
```

with `_saturate(::SatFinite, …)`, `_saturate(::SatPropagate, …)`, and
`_saturate(::SatNone, …)` carrying the rows verbatim from the current
`if`/`elseif` arms. `project` becomes:

```julia
    r = round_to_precision(P, B, RM(), X, R, sticky)
    _emit(saturate(T, ρ, r), T, r)
```

### Acceptance criteria

1. **G5 golden digests byte-identical.** This is the gate; run it at `full`
   (`SMALLFLOATS_G5=full`), since this touches the write path for every value in
   the package and `CLAUDE.md` names exactly that condition as the one requiring
   the full tier.
2. A totality test: for every `(SM, RM)` pair in the mode vocabulary, every
   `(Σ, Δ)`, and every `Rounded` kind including both over and under, `saturate`
   returns a member of `SAT_OUTCOMES` and `_emit` has a method for it. Cheap,
   and it is the thing the `Symbol` version could not express.
3. `test/refimpl.jl`'s `refsaturate` is **unchanged**. It is the independent
   reference; changing it in the same commit would destroy the comparison.
4. Zero-allocation and concrete-inference pins in the specialization-regression
   testset still hold.

---

## Workstream 6 — benchmark evidence

### Current implementation

Corrected from `improved1.md`, which understated what exists:

- `bench_format_sensitivity` (`:299-308`) already covers Code8/rung 1,
  Code16/rung 1, rung 2, rung 3, and the smallest format.
- `repository_state` (`:478-488`) and the header (`:502-505`) already emit
  commit SHA, dirty state, package version, and seed.
- `preflight` (`:187-222`) already aborts per operation class rather than per
  head, with the rung-aware reasoning §11 M46 established.
- `allocation_profile` (`:226-239`) computes selection/add/fma/ladder
  allocations tagged with rung and carrier — **and is never called**.

What the checked-in report shows is none of this, because it was generated at
`51abbc9` and the harness changed at `5e70873`.

Everything else in the report is `Binary8p4se`-only: core primitives, all twelve
scalar tables, array kernels, sorting, table builds, blocks
(`bench_blocks(Binary8p4se, Binary8p1uf)`), and conversions.

### Local design

Four steps, strictly ordered, because each one's output decides whether the next
is worth doing.

**Step 1 — regenerate.** One command. It costs nothing and it may close the
provenance finding and the format-sensitivity finding outright. Do not plan past
it before reading the result.

**Step 2 — wire `allocation_profile`.** It is written; it needs a table.
`CLAUDE.md`'s benchmark doctrine asserts a per-rung allocation contract in prose
("the exact selections are zero at every rung, unconditionally… arithmetic
allocates exactly when the operand spread exceeds the carrier's exact range…
the enclosure ladder allocates at rungs 2 and 3 by construction"). Emitting the
measured table beside the claimed one turns that paragraph into something a run
can falsify — which is this whole cycle's theme. Emit over the same four rung
representatives `bench_format_sensitivity` uses.

**Step 3 — widen the two sections where the rung actually changes the code
path**, not all of them:

- **Core primitives.** `decode` under `ComputeDecode` is a *different function*
  from the `TableDecode` gather (`decode_encode.jl:129-132`), and `order_key` at
  `Code16` uses a `UInt32` key. Those are the two rows where a wide format
  measures different code rather than the same code with a different type
  parameter.
- **Array kernels.** The interesting result at K ≥ 9 is the **Shape-A/Shape-B
  boundary**: a binary table at K = 16 is 2^32 entries and `table_for` declines,
  so the compute kernel is the only path. `table_policy`
  (`tables.jl:195-223`) already returns `(; shape, entries, bytes, reason)` —
  print `reason` in the row so a slow number explains itself instead of
  prompting an investigation.

Blocks are worth one wide row (`bench_blocks(Binary16p5se, Binary16p1uf)`)
because `blockdecode`'s carrier is `rung(Val(:Multiply), FS, FE)` and the P = 1
fast path (`blocks.jl:95-109`) is the MX shape. Sorting, table builds, and the
scalar operand-class tables can stay at the reference format — they measure
policy and dispatch, not carrier.

**Step 4 — first-call latency.** `SmallFloats.jl:245-268` records "≈ 1.8 s per
format, essentially all specialization" as the *motivation* for the wide
precompile entries, and `formatsel.jl:12-17` records "21.5 s cold and 0.0 s
warm" for a 20-format × 27-ρ sweep. Those are the largest user-visible costs in
the package and both live in source comments. A short cold-start section — time
to first `Add` on a format at each rung, in a fresh process — is the number a
user actually needs when choosing a format.

Only after all four: optimize, and only what the widened report still flags. On
current evidence that is `ConvertToBlockMaxAbsFinite` (111 allocations, 3.95 µs
at B = 32) and `BlockAdd` (35 allocations, ≈ 1 per lane).

For `BlockAdd` the suspect is visible and cheap to test:
`blocks.jl:311-317` recomputes `h = _joinheads(...)` **inside** the
`ntuple(Val(B))`, once per lane. The head is a function of the two blocks'
formats, not of the lane index, so it hoists out of the closure entirely.

For `ConvertToBlockMaxAbsFinite` the suspect is `_joinheads(X...)`
(`blocks.jl:522`) — a splat, which is exactly the construction §11 M46 measured
boxing 304 bytes per call on `Float128` and 592 on `Dyadic` in `apply_op`, where
every *component* measured zero. The fix there was `Vararg{Any,N}`
(`ops_scalar.jl:224-225`); the same treatment applies. Measure at the entry
point, not by assembling the parts — that is the recorded lesson.

### Acceptance criteria

1. The checked-in report carries a commit SHA matching the source that produced
   it, and its format-sensitivity table names four rungs.
2. An "Allocation by rung" table exists and its rows are consistent with
   `CLAUDE.md`'s benchmark doctrine — or the doctrine is corrected to match the
   measurement, and the changelog says which way it went.
3. Array-kernel rows print `table_policy`'s `reason`.
4. A cold-start section exists with one row per rung.
5. Any allocation optimization is accompanied by an unchanged G5 digest and an
   unchanged block-composition test; execution strategy may change, numerical
   meaning may not.

---

## Workstream 7 — release and repository state

### `docs/pdf/build`

Unchanged in direction from the prior guide, and the reason is stronger than
"large": `docs/pdf/build/README.md` documents it as *editable LaTeX source* with
a stated recompile command and a stated regeneration path
(`docs/pdf/buildpdf.sh`). Untracking it blind deletes a documented workflow.

Migration, in order:

1. Decide what is genuinely source: `custom.sty` (generated but hand-tunable per
   the README), `howto.md`, `buildpdf.sh`, the transform scripts.
2. Everything else — `_minted/` (251 files), `pages/` (195 PNGs), `main.tex`
   post-transform, `.xdv`, `.toc`, the render manifest — is reproducible output
   and belongs in the release artifact `release.yml` already builds.
3. `.gitignore` gains `docs/pdf/build/` with the retained source files
   re-included by negation, so the intent is readable from the ignore file.
4. `docs/pdf/build/README.md` is updated to say which files are tracked and
   which the build produces.

### Tag 0.4.0

`release.yml` triggers on `tags: ["v*"]` and has never fired. Release automation
that has never run is untested automation: the conformance-report invocation,
the artifact paths, and the PDF toolchain step are all unverified. Tagging is
the test.

### Record the Julia 1.12 floor

Write the reason where a reader will look — a comment beside `Project.toml`'s
`julia = "1.12"` and a line in the README:

> `setprecision`/`setrounding`'s function forms are `ScopedValue`-backed as of
> Julia 1.12 (`base/mpfr.jl:1210`, `:248-249`). On 1.11 they mutate process
> globals, which makes concurrent MPFR escalation unsound — and the ternary
> compute kernel threads by default (`kernels.jl:90-97`), as does any user
> `Threads.@threads` over an operation that can reach the enclosure ladder.

### CI run metadata

`release.yml` already uploads `release-rollcall.log` and `conformance.txt`. Add
a JSON with Julia version and build, `Sys.CPU_NAME`, `Threads.nthreads()`,
commit SHA, dirty state, `SUITE_TIER`, `LOOP_SCALE`, gate count, and total
compared units. That artifact is what makes a conformance claim reproducible
rather than merely printed.

---

## Workstream 8 — small items

Each is a few lines; group them into one commit per theme.

- **Bulk `Convert` takes `rng`.** `kernels.jl:170-171`:
  `Convert(fr, ρ, A::AbstractArray{<:Binary})` has no `rng` keyword while the
  scalar form and every generated array operation do, so a stochastic bulk
  conversion cannot be given an owned stream — the one thing
  `defaults.jl:98-114`'s entropy decision tells callers to do. Add
  `rng::MaybeRNG=nothing` and forward it through `vmap`.
- **`add_dy_checked`.** `dyadic.jl:261-262`'s `_add_aligned` computes
  `big.S << d` with `d` up to `DYADIC_ALIGN_MAX = 94`, sound only while the head
  carries ≤ `DYADIC_HEAD_BITS = 32` bits. `add_dy` is exported. `mul_dy` /
  `mul_dy_checked` (`:297-343`) is the module's own answer to exactly this
  question, with a recorded measurement behind it; apply it to the second
  operation that needs it.
- **Delete `formats.jl:463-482`.** The commented-out `Base.show` pair is
  superseded by `show.jl`, and the reason it was removed — method overwriting is
  a precompilation *error*, which silently ran the package unprecompiled — is
  already recorded at `show.jl:121-122` and in the changelog. A corpse in a
  `#= =#` invites resurrection.
- **`measure_kappa`'s docstring** (`approx.jl:52`): "always true for arity ≤ 2"
  is false above K = 11 per operand pair (2^22 budget, 2^32 points at
  16 × 16). The mechanism is right; only the parenthetical is a K ≤ 8 leftover.
- **Stage-referencing runtime errors.** `oracle.jl:374-381`, `:379-381`,
  `:453-455`, `:476-479` tell users that a capability "arrives in Stage 6 of the
  K ≤ 16 extension" — for stages that shipped. A user hitting one today is told
  to wait for completed work. Rewrite them to say which operation, which
  carrier, and that the combination has no ω-semantics; the stage history stays
  in `implementextensions.md §11`.
- **`show.jl:37-42`'s per-call re-validation.** `set_show_style!` already
  validates, so `binary_show_style` only needs to validate the `IOContext` path.
- **Threading scope.** `THREADED_KERNELS` / `THREAD_MIN_ELEMS`
  (`kernels.jl:69-72`) are package-level `Ref`s consulted by exactly one loop.
  Either extend them to the unary/binary Shape-B loops — which at K ≥ 9 are the
  *common* array path, since `table_for` declines — or rename them to say they
  govern the ternary kernel. Extending is the better answer and is the same
  construction: pure ρ is deterministic per element, and MPFR scoping is
  task-local on 1.12 (see W7).

---

## Workstream 9 — make the doctrine executable

`CLAUDE.md` names its own problem: "a doctrine file is code that nothing
executes." Most of its falsifiable claims do have executors; two do not, and
both are closed by workstreams above. The deliverable is the table itself, kept
beside the doctrine, so the count cannot creep back up.

| Claim | Executor |
|---|---|
| Include order matches the comment | `stage_gates.jl` scan against `SmallFloats.jl` |
| 504 formats, K ∈ 3:16 | `docs_consistency.jl` |
| `Binary{K` never appears in a method body | `stage_gates.jl` |
| NaN sorts first, below −Inf | T1 order sweep |
| Warm scalar paths allocate zero | specialization regressions |
| `Float128=disable` is bit-identical | differential build gate |
| Fourteen roll-call entries | `REQUIRED_GATES` |
| Total compared units | roll-call — **plus `LOOP_SCALE` in the header (W2)** |
| G8 has no file, deliberately | roll-call's uncovered list |
| Rung partition is 432/64/8 | G9 |
| Allocation by rung | **W6 step 2** — the function exists, unwired |
| `datumsexact` is sound | **W4** — enumeration in G6 |
| Invariant 9 holds in the write path | **W5** — dispatch plus the totality test |

Two documentation edits belong with this workstream:

- **State the invariant-9 carve-outs.** Display style (`show.jl`) and the
  oracle result-kind dispatch (`_bp_element`) branch on values deliberately.
  A stated exception is a decision; an unstated one is a violation nobody has
  gotten around to.
- **Do not thin the measurement post-mortems out of the source.**
  `dyadic.jl:219-243` is the clearest case: it records a 1.87× "win" that
  inverted to a 20% loss under a corrected harness, and says which conclusion
  survives. That knowledge has no other home where it will be read at the moment
  it is needed. What can move to `implementextensions.md §11` is stage
  numbering, especially where it leaks into user-facing error text.

---

## Sequence

**Tranche 1 — reachable defects.** W1 `f32_exact` · W2 `LOOP_SCALE` · W3
`eps`/`ldexp` · W4 `datumsexact`. Four independent commits, each landing with
its own pin. W4 must be verified digest-neutral before W5 starts, so that if a
digest moves during W5 the cause is unambiguous.

*Exit:* every one has a test that fails without the fix; `rollcall.jl`'s
uncovered list is true; `CLAUDE.md`'s unit figure names its tier.

**Tranche 2 — evidence.** W6 steps 1–2 (regenerate, wire
`allocation_profile`). Small, and its output re-scopes steps 3–4.

*Exit:* the checked-in report matches a named commit and carries the per-rung
allocation table.

**Tranche 3 — release state.** W7 in full, plus W8's one-liners. Tagging is the
last action, because it is the test of everything before it.

*Exit:* `release.yml` has fired once and its artifacts are correct.

**Tranche 4 — the write-path refactor.** W5 alone, at `SMALLFLOATS_G5=full`.
Kept separate from everything else so the digest comparison has exactly one
explanation.

*Exit:* digests byte-identical, `refsaturate` untouched, totality test green.

**Tranche 5 — measured performance.** W6 steps 3–4, then the two block
allocation centres.

*Exit:* the report substantiates all three rungs and `CLAUDE.md`'s allocation
paragraph is a measured table.

**Ongoing.** W9 — the claims table, maintained with the doctrine.

Tranches 1 and 2 should land together and quickly. 3 is bounded. 4 is small but
must not share a commit with anything. 5 is a cycle's worth of work and is the
one that changes what users can decide.

---

## Risks and how each is contained

| Risk | Containment |
|---|---|
| W1's screen is unsound for some format | Acceptance criterion 2 checks `screen-false ⊆ enumeration-false` exhaustively at K ≤ 8. If it fails anywhere, delete the screen and keep the budget — the budget alone fixes the throw |
| W2 moves a published coverage number | Expected and stated. Record the new default-tier total in the changelog and print `LOOP_SCALE` beside it forever after |
| W3's `eps` disagrees with a user's IEEE intuition | It agrees: the construction reproduces `nextfloat(x) − x` exactly, and the acceptance test compares against an independent reference over every K ≤ 8 code point |
| W4 changes an answer after all | G5 digests catch it, and the fix is one token to revert |
| W5 changes a code point | G5 digests at `full`, in a commit that touches nothing else |
| W6 optimizations change semantics | Every allocation change ships with unchanged G5 digests and unchanged block-composition tests |
| W7 deletes something that was source | Migration reads `docs/pdf/build/README.md` first and updates it in the same commit |

---

## Changes deliberately not made

- **The projection engine, the oracle protocol, and the carrier lattice stay
  as they are.** W5 changes a protocol's *type*, not its semantics, and must be
  digest-identical or reverted.
- **No split of `oracle.jl` or `dyadic.jl` by size.** Both are deep modules with
  real interfaces. The only defensible seam is exact arithmetic versus enclosure
  construction, and only if it earns its own tested boundary.
- **No optimization of the sub-10 ns scalar paths.** They are zero-allocation
  and near the floor.
- **No widening of the default export surface** to the other 384 aliases. The
  asymmetric-reversibility argument at `SmallFloats.jl:90-116` still holds.
- **No deepening of G10.** It earns its place by being total and shallow, and
  says so. Add verbs to its list; do not add assertions to its probes.
- **No second meaning on `with_default_*`.** The consumption-combinator
  semantics are documented, tested, and correct; overloading the name is how the
  0.3.0 documentation defect happened.
- **No `Ops`/`Blocks`/`Approx` namespaces in this cycle.** The prior guide
  decided against mirroring exports with shallow adapters, and nothing in the
  second review changes that. The block surface's size is a real observation but
  it is not a defect.
