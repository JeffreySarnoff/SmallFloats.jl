# FloatBytes.jl — Unified Plan

*A clean-sheet implementation of IEEE P3109/D1 for `3 ≤ K ≤ 8`.*

Written 2026-08-04 by merging two independent clean-sheet plans:
[PlanFloatBytes.md](PlanFloatBytes.md) (architecture-led: deep modules, plan
compiler, assurance) and [PlanningFloatBytes.md](PlanningFloatBytes.md)
(theorem-led: exact integer evaluation, enumerated evidence, gate accounting).

They were written without knowledge of each other and converged on the two
decisions that matter most — **one concrete byte-wide primitive type** and
**SmallFloats as a differential oracle rather than a template**. Where they
diverged, §2 records the decision and its reason. This document supersedes both.

---

## 1. The premise, in measured numbers

Everything below is a consequence of these. All are checked, not assumed.

| quantity | value |
|:---|:---|
| legal formats (`4K − 2` per `K`, `K ∈ 3:8`) | 120 |
| code points, summed over all formats | 13 296 |
| maximum exponent bias `B` | 128 (unsigned, `K = 8`, `P = 1`) |
| datum magnitude range | `2^-127 … 2^126` |
| datum binade spread | 253 |
| significand bits per datum | ≤ 8 |
| complete Float64 decode atlas | 106 368 B |
| complete Float32 decode atlas | 53 184 B |
| same-format binary operand pairs, summed | 2 504 832 |
| **cross-format** binary operand pairs | 176 782 416 |
| same-format ternary operand triples, summed | 564 261 888 |

Two theorems follow, and both are the reason this is a different package rather
than a smaller one.

### 1.1 Theorem A — exact evaluation in fixed-width integers

Every datum is `±s · 2^e` with `s < 2^8`. A product of two datums has `s < 2^16`.
Correct rounding to a `P ≤ 8` target needs the true result to `P + 2` bits plus
the sign of everything below it.

> **Window lemma.** For any fixed 2-term expression over `K ≤ 8` datums — `Add`,
> `Subtract`, `FMA`, `FAA`, `Hypot`'s inner sum — place the larger-magnitude
> significand in a `UInt64` with its LSB at bit `G = 40`, align the smaller by the
> exponent difference, and record whether nonzero bits fell off the bottom. The
> resulting `(window, exponent, tail-sign)` triple determines the same correctly
> rounded `P`-significant-bit result as the exact rational value, for every
> `P ≤ 8` and every rounding mode.

*Why.* If the exponent difference `sh ≤ 40` the smaller term is retained
exactly, so the sum is exact. If `sh > 40` the smaller term is below `2^-40` of
the larger, so no cancellation is possible and the window carries ≥ 40 correct
bits above the truncation point — against the 10 the target needs. A dropped
tail is recorded as a sign, which is exactly the evidence every rounding
predicate consumes.

The one subtle case is a *negative* tail from `w1 − w2`. Normalize it away:
`w − ε ≡ (w − 1) + (1 − ε)`. This is sound only because a dropped tail requires
`sh > 40`, which forces `w1 ≥ 2^40 > 255 ≥ w2` — the premise is asserted inside
the check, not claimed in prose.

**Evidence**, against a `Rational{BigInt}` reference
([w1_window_lemma_add.jl](w1_window_lemma_add.jl),
[w1_window_lemma_fma.jl](w1_window_lemma_fma.jl)):

```
Add:    2 459 235 datum pairs, all 120 formats                       0 mismatches
FMA:  109 800 088 operand triples, every K ≤ 6 format plus nine
      K ∈ {7,8} formats including every widest-spread case           0 mismatches
```

`Binary8p1uf` — `B = 128`, the 506-binade worst case in the lattice — is covered
at all 16 581 375 of its triples. Not yet enumerated: `K ∈ {7,8}` at `P ≥ 2`, all
of which have strictly narrower spread than what is covered. §14 makes closing
that a Stage 4 entry condition rather than an assumption.

**Consequence.** No `Float64` carrier, no `Float128`, no `Dyadic`, no MPFR on any
defined algebraic path. The single 64-bit window replaces SmallFloats'
`src/carriers.jl` (416 lines), `src/dyadic.jl` (941), `src/fma128.jl` +
`src/faa128.jl` (631), and most of `src/oracle.jl` (1136).

### 1.2 Theorem B — the lattice is exhaustively enumerable

At 177 million points the **entire cross-format binary lattice** is enumerable in
minutes. SmallFloats must sample that direction by shape class; here it need not.
Verification stops being evidence and becomes proof.

### 1.3 What remains genuinely hard

Honesty about the residue, so the lightness is not oversold:

- **Transcendentals** — 25 unary plus `ArcTan2`/`ArcTan2Pi` — still require
  rigorous enclosure. MPFR remains, confined to cold table construction (§8).
- **Reductions of more than two terms** are not covered by the window lemma.
  Blocks and dot products need a wider accumulator (§10).
- **Divide and Sqrt** produce non-terminating expansions; they need
  quotient/remainder and integer-sqrt/remainder reasoning, which the window
  handles but does not by itself justify.

---

## 2. Where the two plans differed, and what was decided

The merge is only useful if the disagreements are resolved rather than
concatenated.

| # | question | Plan A (PlanFloatBytes) | Plan B (PlanningFloatBytes) | decision |
|:---|:---|:---|:---|:---|
| 1 | type parameters | `FloatByte{K,P,S<:Signedness,D<:DomainKind}` | `Binary{K,P,S::Bool,E::Bool}` | **A.** `Binary{8,4,true,true}` is unreadable and its two Bools are positionally ambiguous. Costs nothing; both fold. |
| 2 | code identity | `fromcode(T, n)`, explicit | inherit SmallFloats' `Unsigned`-means-code rule | **A.** The `Unsigned` rule keys meaning to a coincidence of Julia's type lattice. `fromcode` is unambiguous at the call site. |
| 3 | public unsafe constructor | none; private, caller names its proof | `rawvalue(T, c)` exported | **A.** A broadly visible unsafe primitive invites bypassing the one invariant byte kernels rely on. |
| 4 | exact evaluation | `ExactDyad{L}`, limbs derived per signature | single 64-bit window, proven | **Both, tiered** — see §7. B's lemma proves `L = 1` for all fixed 2-term algebra; A's derived limbs are needed for reductions. |
| 5 | tables | plan compiler, table store, artifacts, decision records | L1-scoped optimization, kernel-first | **B's default policy inside A's architecture** — see §9. The quantitative argument is decisive. |
| 6 | prepared plans | 10 plan classes | none (rely on hoisted table getter) | **A, reduced to 3 classes** at Stage 6; more only with measured wins. |
| 7 | stochastic entropy | `IndexedEntropy` counter-based + `SequentialEntropy` | pass an RNG | **A, wholesale.** B had no answer for schedule-independent threaded stochastic results. A's best single contribution. |
| 8 | session default | fixed immutable; optional `DynamicContext` | `ScopedValue` | **Both.** Fixed immutable default in core; `with_projection` scoped override as a documented adapter explicitly outside the performance interface. |
| 9 | error taxonomy | `InconclusiveProjectionError`, `EntropyRequiredError`, `AliasingError`, `WorkspaceError` | not addressed | **A.** "Inconclusive is not approximate" is a real invariant. |
| 10 | OCP FP8 aliases | not addressed | measured; refused | **B** — see §12.2. |
| 11 | gate accounting | new tier list T1–T8 | maps each SmallFloats gate to its fate | **Both** — A's tier content, B's disposition table (§13). |
| 12 | decode | atlas vs per-format tuples, benchmark | per-format 256-entry table | **A.** The whole atlas is 106 KiB and avoids large generated syntax; benchmark decides at Stage 2. |
| 13 | `decode` return type | `Float64` | internal unpacked `Datum` | **Both, two names.** `decode(x)::Float64` is the public exact query; `unpack(x)::Datum` is the internal exact form. |

### 2.1 A reconciliation both plans needed

The two plans set different performance targets **from the same package**,
because they quoted different rows:

| case | Plan A quoted | Plan B quoted | actual |
|:---|:---|:---|:---|
| scalar `Add` median | 9.4 ns | 9.0 ns | both right — A read `faster_benchmarking_report.md`, B read `benchmark_report.md` |
| ternary FMA, `K = 8` | 15.4 ns/elem | 3.17 ns/elem | **3.2 ns/elem is the shipped path**; 15.5 ns/elem is the `scalar-loop baseline` row A mistook for it |
| block dot, `B = 32` | 1.24 µs, 66 allocs | 320 ns, 3 allocs | different reports; the tranche-1 work moved this mid-session |
| 64 K binary table build | 15.8 ms, 458 754 allocs | *(repeated A's figure unchecked)* | **79.47 µs, 44 allocs** for an ordinary format; A's row is a wide-spread format on one thread |

Two consequences, both of which changed this document:

- A's §18.4 target "improve ternary compute by at least 1.5×" was set against a
  row that is not the shipped path. The real path is already 4.8× faster than A
  believed, so that target was *already met* — and therefore useless.
- The table-build figures differ by **200× in time and 10 000× in allocations**
  between the two reports, because they measure different formats under different
  threading. §9.1 originally repeated A's number and drew a 79× conclusion from
  it; the checked figures support a ~3× conclusion instead, and a different
  reason for it.

**Rule adopted:** every performance target names its source file, table, and row.
A target quoted from the wrong row is worse than no target, because it will be
declared met without the work being done.

---

## 3. Architecture

Five deep modules. Everything else is an adapter behind one of them.

```text
                        Julia adapters
                 constructors / Base / arrays
                              |
                              v
Byte Domain ------> Defined Signature ------> Plan Compiler
     |                      |                      |
     |                      v                      v
     +-------------> Defined Semantics      Execution adapters
                            |                code | LUT | compute
                            v                dense | packed | block
                        Projection <----------------+
                            |
                            v
                       result code

Assurance independently observes all five.
```

The one internal seam that everything crosses:

```julia
defined_code(signature, entropy_word, operand_codes...)::UInt8
```

Scalar operations, table compilation, array kernels, block lanes, κ measurement
and conformance all go through it. A table entry **is** a call to it, so there is
no residual correctness reasoning at a use site.

| module | owns | deleting it would spread into |
|:---|:---|:---|
| Byte Domain | type, code identity, decode atlas, ordering, metadata | projection, operations, tables, display, tests |
| Projection | the *only* code-producing implementation | every operation |
| Defined Semantics | exact meaning, enclosures | tables, blocks, approximation |
| Plan Compiler | cost-only execution choice | every array entry point |
| Assurance | independent reference, certification, conformance | the whole suite |

---

## 4. The type and code identity

```julia
abstract type Signedness end;  struct Signed   <: Signedness end
                               struct Unsigned <: Signedness end
abstract type DomainKind end;  struct Finite   <: DomainKind end
                               struct Extended <: DomainKind end

primitive type FloatByte{K,P,S<:Signedness,D<:DomainKind} <: AbstractFloat 8 end

const Binary8p4se = FloatByte{8,4,Signed,Extended}
```

Verified: parses, `isbitstype`, `sizeof == 1`, `Base.elsize(Vector) == 1`,
`reinterpret(UInt8, ::Vector)` is zero-copy.

Because the type is concrete, SmallFloats' architectural invariant 8 — "format
types are propagated, never rebuilt", enforced by a textual scan of `src/` —
becomes *vacuous*. Rebuilding `FloatByte{K,P,S,D}` in a method body is the
identity. The defect class is not policed; it does not exist.

**Code identity is named, never inferred:**

```julia
fromcode(::Type{T}, code::Integer)::T     # validates 0 ≤ code < 2^K
codepoint(x::FloatByte)::UInt8
isvalid(::Type{T}, code::Integer)::Bool

quantize(::Type{T}, value, policy; entropy=nothing)::T
T(value::Real)                            # fixed documented default only
decode(x::FloatByte)::Float64             # exact for every datum
```

Every `T(value::Real)` argument means a numeric value, at every integer width.
This drops SmallFloats' rule that `Unsigned` means *code point* — a rule that
makes `T(0x08)` and `T(8)` differ on integer signedness, which is a property of
Julia's type lattice and not a semantic distinction.

A primitive type has no inner constructor, so `reinterpret` can fabricate a value
with nonzero high bits when `K < 8`. Document `reinterpret` into `FloatByte` as
**unsafe**; hot loops rely on the canonical-value invariant exactly as they rely
on array element types. There is no public unchecked constructor.

---

## 5. Invariants

Review criteria. A change that breaks one is wrong even if the suite is green.

1. **One projection.** A logical defined result is projected exactly once.
2. **One-byte identity.** Every canonical value is one byte with zero high bits
   beyond `K`.
3. **Named code construction.** `fromcode` is the only safe code-identity input.
4. **Exact decode.** Every canonical value decodes exactly to Float32 and Float64.
5. **Semantics before execution.** Meaning cannot depend on storage, table state,
   thread count, SIMD width, or plan choice.
6. **Projection owns codes.** Only Projection, or a certified final-code adapter,
   may choose a result code.
7. **Certified collapse.** A direct byte law exists only with an exhaustive
   equivalence certificate for its applicability domain.
8. **Immutable prepared plans.** A plan never observes mutable policy after
   construction.
9. **No hot metadata.** Inner loops contain no registry lookup, format check,
   symbol dispatch, dictionary lookup, cache lock, or strategy branch.
10. **Tables are compiled semantics.** Every entry comes from `defined_code`;
    tables never define behavior, and become visible only after complete
    construction and checksum.
11. **Indexed stochastic meaning.** One logical output consumes exactly one
    `N`-bit word, identified independently of scheduling.
12. **Defined and approximate plans are disjoint types.** A defined request can
    never select approximation.
13. **Exact reductions are order-independent.** Partitioning and merge order
    cannot change a result code.
14. **Inconclusive is not approximate.** If rigorous projection cannot be decided
    within an explicit resource limit, throw `InconclusiveProjectionError` and do
    not mutate the destination.
15. **Closed defined catalogue.** One source generates wrappers, arities, tables,
    tests and conformance.
16. **Policy is dispatch, never a branch.**
17. **The total order puts NaN first, below −Inf** (draft §4.12.1) — the opposite
    end from Float64 sorting, key 0 reserved for NaN.

Two carried from SmallFloats' doctrine because they were paid for:

- **`show` must never be the thing that throws.** A failing testset has to print
  the values it compares, at every carrier.
- **A docstring is a string literal before it is prose.** `\(`, `\[`, `\text` are
  invalid Julia escapes; one of them made `using SmallFloats` fail outright.

---

## 6. Projection

```julia
project_code(result_format, policy, projection_input, entropy_word)::UInt8
project_interval(result_format, policy, enclosure, entropy_word)::UInt8
```

Behind the interface: exact neighbour selection, midpoint and directed
comparisons, all stochastic predicates, saturation and special rows, normal and
subnormal encoding, symbolic sidedness at asymptotes.

**One rounding family.** SmallFloats carries three `round_to_precision`
implementations — Float64 bit path, generic carrier, Dyadic — with an exhaustive
gate (G3) asserting they agree bit-for-bit. Theorem A leaves one integer family,
so there is nothing to agree with and the gate disappears.

Projection knows nothing about arrays, caches, plans, or operation names.

---

## 7. Exact evaluation — two tiers

The merge decision from §2 row 4. Tier 1 is proven and cheap; tier 2 is general
and only paid for where tier 1 provably does not reach.

### Tier 1 — the 64-bit window (all fixed 2-term algebra)

```julia
struct Datum          # a FINITE value: (-1)^neg * sig * 2^exp
    sig::UInt64       # sig == 0 iff zero
    exp::Int32
    neg::Bool
end

struct Aligned        # magnitude known to within one window unit
    w::UInt64         # true magnitude is (w + tail*eps) * 2^exp, 0 < eps < 1
    exp::Int32
    neg::Bool
    tail::Bool        # normalized non-negative (§1.1)
end
```

Both `isbits` and register-resident. **Nothing on any defined algebraic path
allocates, for any operation, at any format** — not "except when the spread
escalates", which is SmallFloats' honest but unavoidable caveat.

| operation | method | result |
|:---|:---|:---|
| `Add`, `Subtract` | window alignment | exact + tail |
| `Multiply` | `sig₁ * sig₂`, ≤ 16 bits | exact |
| `Divide` | `(sig₁ << 56) ÷ sig₂`, tail from remainder | exact + tail |
| `Sqrt` | `isqrt(sig << 46)`, tail from remainder | exact + tail |
| `RSqrt`, `Recip` | divide composed with sqrt | exact + tail |
| `FMA`, `FAA` | exact 16-bit product, then window | exact + tail |
| `Hypot` | exact `x² + y²` by window, then integer sqrt | exact + tail |
| `Clamp`, min/max family, `CopySign` | order keys on code points | exact |
| `Convert` | unpack source, round to target | exact |

Each is a dozen to thirty integer operations.

**Specials never enter `Datum`.** Each kernel dispatches on operand *code points*
first, against the draft's special-value rows, and unpacks only survivors. The
draft's special rows are statements about code points, so writing them as
code-point rows makes the rows literally be the spec — one indirection closer to
the text than decoding to a carrier and testing `isnan`.

### Tier 2 — derived fixed-limb accumulators (reductions and >2 factors)

For block reductions, dot products, and scaled expressions with up to four
factors, derive the limb count at signature preparation from minimum product
exponent, maximum product exponent, significand bits, and `ceil(log2(B))` carry
bits. Select a concrete `ExactDyad{L}` backed by `NTuple{L,UInt64}`.

**Do not use tier 2 where tier 1 applies.** Tier 1 is proven sufficient for every
fixed 2-term expression including FMA, and it is one word instead of `L`. Plan A
would have paid `L`-limb cost on every `Add`.

If a derived width exceeds the static ceiling, use a caller-owned limb workspace
or a `BigInt` cold adapter, and report that through `plan_traits` **before**
execution.

---

## 8. Transcendentals

25 unary operations plus `ArcTan2`/`ArcTan2Pi`. `Hypot` is *not* among them — §7
computes it exactly.

A unary operation on a `K ≤ 8` format has **at most 256 possible inputs**, so its
complete correctly rounded table is at most 256 bytes. Therefore MPFR appears at
exactly one site, in cold table construction, and is never reached from a scalar,
array, or warm path.

The rigorous loop, when a table is not yet built:

1. handle exact and special cases symbolically;
2. produce a directed enclosure at modest precision;
3. project the lower endpoint with positive sidedness and the upper with negative
   sidedness, under the same policy and entropy word;
4. return when both projections agree; otherwise raise precision and repeat.

Asymptotes retain symbolic sidedness: numerically reaching `1` does not erase the
distinction between exact `1` and `1 − ε`. Under a caller-supplied precision
ceiling that does not decide, throw `InconclusiveProjectionError` carrying the
signature, operand codes, precisions and final enclosure — never a midpoint,
never a guess (invariant 14).

Because there are ≤ 256 inputs per table, a hard case is *findable*: enumerate
and record the required precision per `(op, format)` as a constant.

---

## 9. Execution: tables, plans, and the kernel-first policy

### 9.1 The quantitative argument

Plan A specified a table store with LRU/CLOCK admission, artifact packs, and
stochastic decision records. Plan B argued tables are barely worth having. The
package's own evidence settles it — but only after §2.1's rule is applied to the
citation itself, because both plans quoted this wrong.

`benchmark_report.md`, "Table builds (oracle + projection)", 64 K-entry binary
tables, 8 threads:

| row | time (min) | allocations |
|:---|:---|:---|
| `Add⟨8p4se×8p4se⟩` — ordinary format | 79.47 µs | 44 |
| `Add⟨8p1uf×8p1uf⟩` — wide-spread format | 2.57 ms | 536 594 |

**The variance is the finding, not the mean.** The same table for the same
operation costs 32× more time and 12 000× more allocations on a wide-spread
format, entirely because the operand spread escalates the oracle to MPFR.
FloatBytes has no escalation, so its builds are uniform — *removing that cliff is
a larger win than making the mean build faster.*

Break-even against the tier-1 kernel: computing 65 536 elements at 3 ns is
≈ 197 µs serial, against a build of ≈ 640 µs serial (79 µs at 8 threads). A
binary table therefore pays after roughly **3× the array** — about 200 k elements
per signature. That is a real threshold but a modest one, and it is nowhere near
enough to justify a store, artifact packs, and decision records before the reuse
is demonstrated.

### 9.2 Adopted policy

| candidate | size | policy |
|:---|:---|:---|
| unary, any `K` | ≤ 256 B | **always** — L1-resident, one build, byte-shuffle friendly |
| binary, `K ≤ 5` | ≤ 1 KiB | **yes** — L1-resident |
| binary, `K ∈ 6:8` | 4–64 KiB | **only on measured reuse** — see §9.1 |
| ternary, any `K` | 512 B – 16 MiB | **no** — the kernel beats what the build amortizes |
| stochastic ρ as a result table | — | **forbidden** (invariant 10 + 11) |
| artifact packs | — | **deferred** until a demonstrated build-cost problem survives §9.1 |

The ternary row is where the win is concrete. SmallFloats runs `FMA` at `K = 8`
through a scalar loop at 3.17 ns/element **with 42 allocations**, and tables
`K ≤ 6` eagerly at up to 16 MiB of build cost to escape it. A tier-1 window FMA
is an exact 16-bit multiply plus a window add, with **zero** allocations and
**zero** build — which removes the table tier machinery *and* the adaptive-cache
policy that chooses between tiers.

Plan A's own rule governs: *an optimization that misses its target is deleted;
dormant adapters still cost tests, compilation, and maintainer knowledge.*

### 9.3 Plans

Start with **three** plan classes, not ten:

```text
DenseComputePlan     the tier-1 kernel over a byte view
UnaryTablePlan       the always-on 256-byte table
GenericArrayPlan     correctness adapter for odd axes, strides, views
```

Add `BinaryTablePlan`, `StochasticDecisionPlan`, `TernaryTablePlan`,
`PackedTilePlan`, `ExactReductionPlan`, `DirectCodePlan`, SIMD plans **one at a
time, each with a measured win and an exhaustive equivalence certificate**.

Plans are immutable and own their tables strongly, so store eviction cannot
invalidate a running plan. The planner is **cost-only**: a different plan may
never change a result.

Dense lowering takes a byte view once, outside the loop:

```julia
@inbounds @simd for i in eachindex(out, a, b)
    out[i] = kernel(a[i], b[i])        # or: table[(Int(a[i]) << K2 | Int(b[i])) + 1]
end
```

### 9.4 Threading and SIMD

Different thresholds per plan class; table gathers are bandwidth-limited and
threading them small is counterproductive. Threaded deterministic execution must
produce identical bytes.

SIMD is an adapter, not a slogan. AVX2 has no general byte gather from a 64 KiB
table; low-`K` tables may admit shuffle kernels; AVX-512 VBMI changes the
options. Admit a SIMD plan only with exhaustive code equivalence, feature
detection at preparation, tail handling tested at every short length, and a
measured win.

One caution carried from SmallFloats' post-mortems: its threading wins were
substantially **a missing function barrier in disguise** — `Val(op)` built from a
runtime `Symbol` inside the builder caused per-entry dynamic dispatch, and
`Threads.@threads` supplied the barrier for free. Before threading anything,
check that the serial path specializes.

---

## 10. Stochastic execution

Adopted from Plan A wholesale; Plan B had no answer here.

```julia
IndexedEntropy(seed, stream, invocation)   # counter-based, schedule-independent
SequentialEntropy(rng::AbstractRNG)        # conventional stream, forces sequential plan
```

The defined contract consumes **exactly one `N`-bit word per logical output**,
including exact and special results. Fixed consumption makes slicing, replay and
composition auditable. The indexed key includes algorithm version, seed, stream,
invocation, logical index and projection slot.

This is what makes threaded stochastic rounding reproducible — a property
SmallFloats does not have, since it passes an RNG whose consumption order follows
the schedule.

**Reproducibility gate.** For the same signature, entropy identity, inputs and
logical origin, bytes must be identical across: scalar; one and many threads;
different chunk sizes; dense and packed storage; SIMD and generic loops;
subarray calls with adjusted origins.

---

## 11. Blocks, reductions, packed storage

### 11.1 Reductions

The window lemma does not cover more than two terms, so reductions get their own
design. Two candidates were considered and the choice is empirical:

- **Windowed accumulation with bounded restart.** One pass for the maximum
  product exponent; one pass accumulating into a 64-bit window anchored there,
  terms below contributing only a tail sign; on cancellation into the tail,
  re-anchor and repeat. Each restart drops ≥ 63 binades, so the loop is bounded
  at **9 iterations** across the 506-binade product spread.
- **Derived fixed-limb superaccumulator** (§7 tier 2). Unconditionally exact, but
  worst-case cost on every block.

**Ship the windowed form; keep the superaccumulator as the test reference.** It
is obviously correct and too slow to ship, which is exactly what a reference
should be.

Blocks are **structure-of-arrays over byte storage**, not long tuples:

```julia
struct BlockBytes{SF,EF,B}
    scales::Vector{SF}
    elements::Vector{EF}        # contiguous block-major lanes
end
```

`NTuple{B,EF}` is permitted only for small static `B`. This is not a style
preference: SmallFloats measured a **tuple-length allocation cliff** — `BlockAdd`
allocating 48 B at `B = 8`, 3200 B at `B = 32`, 6128 B at `B = 64`, where
`ntuple(Val(B))` is no better and the fix is a representation change. Do not
build on tuples and then discover it.

Threaded reductions merge exact accumulators and project once, so the result is
independent of partition and merge order (invariant 13).

### 11.2 Scaled operations

Scaling by a `FloatByte` scale is integer-significand multiplication plus
exponent addition — no wide carrier. Form the complete mathematical expression
before projection; never round a scale product and feed the rounded value onward
unless the draft explicitly requires that projection.

### 11.3 Packed storage

```julia
struct PackedBytes{K}
    words::Vector{UInt64}
    length::Int
end
```

Reusable byte tiles; fuse unpack → execute → repack in one traversal; `K = 8` is
an identity byte view, not shifts for no saving. Unused tail bits are zeroed
deterministically so packed equality and hashing are stable.

Be honest about when it wins: SmallFloats measures pack at 0.53 ns/element and
unpack at 0.44 ns/element against a 0.13 ns/element unary gather. Packing pays on
memory-bound workloads and loses elsewhere. Direct packed-word arithmetic is
admitted only with exhaustive equivalence **and** a measured end-to-end win —
microbenchmarking extraction alone is insufficient.

---

## 12. Julia interoperability

Implement the `AbstractFloat` surface deliberately: `zero`, `one`, `typemin`,
`typemax`, `floatmin`, `floatmax`, `eps`, `ldexp`; classification; comparison,
`isless`, total order, hashing, equality; conversion to and from Float16/32/64,
BigFloat, integers; parsing and stable display; `rand`; zero-copy
`reinterpret(UInt8, array)`; `broadcast`, `similar` with concrete element types.

Promotion targets **Float64** — exact for every datum, and it avoids pretending a
cross-format `FloatByte` join is canonical. Projecting back is explicit.

Base operators require same-format operands and use one **immutable** package
policy (nearest-ties-even, draft `SatNone`). There is no mutable global
projection default in the core. A scoped override

```julia
with_projection(ρ) do ... end        # ScopedValue, task-local
```

is a documented adapter, explicitly **outside** the performance interface:
explicit `apply(sig, x, y)` is the fast path and always was. This deletes
SmallFloats' 232-line speculation-guard apparatus and gains task-locality, which
the `Ref` never had.

### 12.1 Ordering and sorting

A `UInt16` monotone order key — ≤ 256 datum keys plus one NaN sentinel. Counting
sort above a measured break-even, Base comparison sort below, and an optional
caller-owned `SortWorkspace` for repeated zero-allocation sorts. Do not hide a
shared mutable scratch whose concurrency semantics are harder than the allocation
it saves.

### 12.2 OCP FP8: measured, and refused

The obvious ergonomic move is to alias `E4M3`/`E5M2`. **Measured, and the answer
is no.**

| format | max finite | infinities | NaN codes |
|:---|:---|:---|:---|
| `Binary8p4sf` | 240 | 0 | 1 |
| `Binary8p4se` | 224 | 2 | 1 |
| OCP E4M3 | 448 | 0 | 2 |
| `Binary8p3sf` | 57 344 | 0 | 1 |
| `Binary8p3se` | 49 152 | 2 | 1 |
| OCP E5M2 | 57 344 | 2 | 6 |

P3109 uses a power-of-two exponent bias (`2^(K−P)` or `2^(K−P−1)`); IEEE and OCP
use `2^(w−1) − 1`. The biases differ by one, so the grids differ throughout. The
closest pair, `Binary8p3sf` and OCP E5M2, share a maximum finite value of 57 344
and *nothing else*: their finite datum sets have **255 and 248 members** and are
not equal, checked element by element.

**No P3109 8-bit format is bit-identical to either OCP FP8 format.** Therefore:
ship no `E4M3`/`E5M2` aliases; ship a comparison table naming the bias convention
as the cause; and if the OCP formats are wanted, add them as *first-class
separate formats* under their own names, clearly marked non-P3109, sharing the
kernels but not the format lattice.

An alias that is 99% right is worse than none, because it will be believed.

---

## 13. Verification

### 13.1 Independent authority

Two references, and **no code is copied from SmallFloats into `src/`** — copying
would reintroduce circularity through the back door.

1. **`reference/`** — `Rational{BigInt}` for finite dyadic formats and algebraic
   operations, separately coded special-value rows, explicit projection-cell
   comparisons, directed MPFR intervals for elementary functions. It must not
   call production decode, projection, special rules, kernels, or table indexing.
2. **SmallFloats `K ∈ 3:8`** — an independently developed, heavily gated
   implementation of the same draft, as a *second* differential adapter.

A standing rule, enforced by a test that greps: **nothing under `src/` may be
referenced by `reference/`.** A naive reference is only a reference if it shares
no code with what it checks.

Where the two disagree, resolve against the **draft text**, never by majority.

### 13.2 Tiers

| tier | scope | budget |
|:---|:---|:---|
| T1 byte lattice | all 13 296 codes: validity, decode, encode, class, order, next, display/parse, Float32/64 exactness | seconds |
| T2 projection cells | every grid edge, midpoint, adjacent value, saturation edge, exact point, special kind, rounding mode, selected entropy words | ~1 min |
| T3 semantic families | exhaustive unary; exhaustive same-format binary (2.5 M pairs); rational differential for algebraic, interval for elementary | ~6 min |
| T4 tables and plans | entry-for-entry equality for every materialized table; every adapter compared byte-for-byte with `defined_code` | ~5 min |
| T5 stochastic | exhaust all entropy words at tractable `N`; pin maximum-`N` edges; reproducibility across execution shapes | ~3 min |
| T6 blocks and reductions | independent exact sums/products across block sizes, cancellation, exponent extremes, specials, thread partitions, accumulator-width transitions | ~3 min |
| T7 failure injection | corrupt artifacts, stale digests, undersized workspaces, invalid codes, inconclusive enclosures, alias violations, sampled certificates | ~1 min |
| T8 Julia interface | inference, allocations, promotion, generic algorithms, parsing, hashing, docs examples | ~2 min |
| **release** | + the full **177 M** cross-format binary lattice; full ternary | ~45 min |

A tier the caller asks for is **honoured, never downgraded**. A gate that quietly
runs less than it was told to is worse than no gate.

### 13.3 Gate accounting

Six of SmallFloats' ten gates exist to police machinery this design does not
contain:

| SmallFloats gate | fate |
|:---|:---|
| G1 `_DE_*` exactness-by-width thresholds | **gone** — no Float128 width analysis |
| G2 `bigprec` sufficiency | **gone** — no MPFR on a defined algebraic path |
| G3 `_rtp_f64` bit ≡ generic | **gone** — one rounding family |
| G4 rung-selection equivalence | **gone** — no rungs |
| G5 golden non-regression | **replaced** by the SmallFloats differential |
| G6 carrier-lift exactness | **gone** — no carriers |
| G7 `HeadExact` carrier swap | **gone** |
| G8 representation invariant | kept, as construction validation plus round-trip |
| G9 trait folding | **kept** — traits must still constant-fold |
| G10 surface totality | **kept and widened** |

Three new gates replace them:

- **W1 — the window lemma.** §1.1's enumeration, as a test.
- **W2 — the reduction restart bound.** Terminates within 9 restarts on every
  input; agrees with the superaccumulator reference on constructed cancellation.
- **W3 — zero allocation on every defined path, unconditionally.** SmallFloats
  can only pin this per operation class, because its enclosure ladder allocates
  at rungs 2 and 3 by construction. Here it is unconditional, which is both
  stronger and simpler.

**G10 is kept and widened, and the reason bears restating.** It is the one gate
that is broad rather than deep — it asserts only that every catalogue operation on
every surface returns and holds its declared result type. Six Stage 7 defects in
SmallFloats lived in exactly that blind spot and survived a green suite. A shallow
gate earns its place by being total: do not deepen it, do not narrow it.

### 13.4 Adapter equivalence

```text
independent reference == defined_code == direct byte law == local table
   == artifact table == dense == generic == SIMD == threaded == packed
```

Comparison is **code identity in identical logical order**. Numerical tolerance
is not evidence for a finite code function.

### 13.5 Static gates

Concrete inferred result types; zero warm allocations where promised; no dynamic
dispatch, lock, dictionary or symbol lookup inside loops; bounded table size
before allocation; strong table lifetime while plans exist; workspace validated
before destination mutation; no invalidation explosion from optional extensions.

---

## 14. Performance

### 14.1 Baselines

All rows from `benchmarking/benchmark_report.md` at `Binary8p4se` under
`(NearestTiesToEven, SatNone)` — a `K = 8` rung-1 format, the best case for the
existing architecture. **Each target names its row** (§2.1).

| case | baseline (min / median) | target | basis |
|:---|:---|:---|:---|
| `decode` | 1.4 / 1.4 ns | ≤ 1.4 ns | unchanged — a table load |
| `project` (RNE·SatNone) | 1.6 / 6.7 ns | ≤ 2 / ≤ 2.5 ns | one integer family |
| `Multiply` | 5.1 / 7.5 ns | ≤ 2.5 ns | one 16-bit multiply |
| `Add` | 6.8 / 9.0 ns | ≤ 3 ns | window, no escalation |
| `Divide` | 6.7 / 18.7 ns | ≤ 4 ns | one 64-bit divide |
| `Sqrt` | 4.9 / 18.7 ns | ≤ 4 ns | one `isqrt` |
| `FMA` | 7.5 / 9.6 ns | ≤ 3.5 ns | exact product, then window |
| `Hypot` | 7.7 / 28.0 ns | ≤ 6 ns | algebraic, not enclosure-bracketed |
| unary transcendental | 5–7 / 20–33 ns | ≤ 1.5 ns | 256-byte table, always |
| `vmap` unary (table gather) | 0.13 ns/elem | ≤ 0.13 ns/elem | already gather-bound |
| `vmap` binary (table gather) | 0.25 ns/elem | ≤ 0.25 ns/elem | table ≤ `K` 5, kernel above |
| `vmap` ternary (**shipped compute path**) | 3.17 ns/elem, **42 allocs** | ≤ 3 ns/elem, **0 allocs** | kernel, no table tier |
| 64 K binary table build, ordinary format | 79.5 µs, 44 allocs | ≤ 80 µs, ≤ 44 allocs | already good; do not regress |
| 64 K binary table build, wide-spread format | 2.57 ms, 536 594 allocs | **≤ 80 µs, ≤ 44 allocs** | no escalation ⇒ build cost is format-independent |
| `BlockDotProduct` (B = 32) | 320 ns, 3 allocs | ≤ 250 ns, **0 allocs** | windowed reduction |
| `ConvertToBlockMaxAbsFinite` (B = 32) | 3.75 µs, 111 allocs | ≤ 1 µs, **0 allocs** | no tuple cliff |

**The medians are the story.** SmallFloats' minima are already good; its medians
run 2–5× higher because the median operand pair triggers escalation — the
enclosure path, the MPFR tail, the sticky-band analysis. An integer kernel has no
such distribution. *The target is not primarily a lower minimum; it is a median
that equals the minimum.*

### 14.2 Measurement states, reported separately

Package load and precompile · first semantic call · cold plan preparation · cold
table compilation · prepared scalar · warm bulk · eviction and rebuild · rigorous
fallback frequency · workspace allocation versus reuse. Mixing these produces
meaningless averages.

Every bulk result reports ns/element and cycles/element, elements/s, bytes moved,
working-set size, likely cache level, allocations, threads and parallel
efficiency, CPU model, and cold/prepared/warm state.

### 14.3 Doctrine, adopted whole

Recorded after four measurement post-mortems in SmallFloats. Every rule was paid
for:

- A closure over any non-`const` global measures Julia's dispatch machinery, and
  it distorts **ratios**, not just absolutes.
- **One variant per process, alternating, or nothing.** A harness compiling
  several variants in one process reported a rewrite as a 1.87× win that
  alternating single-variant processes reversed into a 31% loss.
- **A loop that overwrites its accumulator measures dead-code elimination.**
  Reduce into an accumulator and end with `Base.donotdelete`.
- Warm up until the number stops moving; seed the data.
- Machine drift between blocks reached ~10%; A/B runs from a git worktree pinned
  at the base commit, in immediate alternation.
- A preflight **aborts the run** if a warm scalar path allocates.
- **Name the source row** (§2.1).

Benchmark inputs: uniform random codes, sequential codes, constant and sparse
zeros, skewed distributions, alternating extrema and specials, cancellation-heavy
arithmetic, exact versus enclosure-triggering inputs, and contiguous / strided /
offset / packed / aliased layouts.

**An optimization that misses its target is deleted.** Dormant adapters still
cost tests, compilation, and maintainer knowledge.

---

## 15. Dependencies and layout

Core: `Random`, `SHA`, threading primitives, `BigInt`/`BigFloat` (all `Base` or
stdlib). `PrecompileTools` only if measured first-use benefit exceeds image cost.
**No non-stdlib runtime dependency** — `Quadmath` and `BFloat16s` are dropped.

Optional extensions may improve cost only; the core fallback stays complete and
bit-identical: Float128 filters, BFloat16 interop, architecture-specific SIMD,
external RNG adapters, artifact packs.

Load order, stated here and in exactly one comment at the top of the module file.
Changing the order means changing that comment in the same commit.

```text
src/  FloatBytes.jl
      result_protocol.jl   <- FIRST, zero package dependencies
      domain.jl  formats.jl  show.jl  policies.jl  projection.jl
      semantics.jl  operations/{algebraic,selection,elementary,conversion}.jl
      catalogue.jl  planning.jl  tables.jl
      execution/{dense,generic,stochastic,threaded}.jl
      blocks.jl  packed.jl  approximation.jl  conformance.jl  julia_adapters.jl
ext/  Quadmath  BFloat16  SIMD
reference/  draft_model.jl  rational_projection.jl  interval_oracle.jl
test/  lattice  projection  semantics  plans  stochastic  blocks  packed
       assurance  julia_interface
```

`result_protocol.jl` — `Datum`, `Aligned`, the window primitives — loads first
with **zero package dependencies**: the exact-evaluation substrate must be
checkable on its own terms, reaching for no format, no trait, and no projection.
It inherits the role `src/dyadic.jl` holds in SmallFloats.

`show.jl` sits early, directly after `formats.jl`, so the display layer is
available to every subsequent file's error paths — which is what makes "`show`
must never be the thing that throws" enforceable rather than aspirational.

These are ownership suggestions, not a mandate for many shallow files. Merge
files whose knowledge moves together; preserve the five deep modules even where
their implementations span several.

---

## 16. Stages

Every stage produces a green, reviewable package. Optimization begins only after
independent defined behaviour exists.

| stage | content | exit gate |
|:---|:---|:---|
| 0 | charter, non-goals, error taxonomy, benchmark and verification manifests, envelope gate | §1's facts machine-checked across all 120 formats |
| 1 | independent `reference/`; golden corpus for all 13 296 codes; differential vs SmallFloats | a slow clear authority exists that production cannot call |
| 2 | Byte Domain: type, `fromcode`, metadata, decode atlas, ordering | T1 exhaustive; one-byte layout and concrete inference pinned; **no arithmetic yet** |
| 3 | Projection: all policies, saturation, encoding | T2 exhaustive vs `reference/`; Projection is the only code-producing implementation |
| 4 | tier-1 window, `defined_code`, semantic spine (Convert, Abs/Negate, Add/Multiply, Divide/Sqrt, FMA/FAA, Min/Max, Exp/Log/Sin) | **W1** complete, including `K ∈ {7,8}` at `P ≥ 2`; **W3**; T3 same-format exhaustive |
| 5 | Julia scalar interface, aliases, fixed default, `with_projection` | T8; scalar inference and allocation baselines |
| 6 | unary tables, three plan classes, dense byte execution | table-build allocation target; every entry matches `reference/` |
| 7 | full catalogue, family by family | generated surfaces cannot drift; **G10** at full tier |
| 8 | stochastic: indexed entropy, decision records | §10's reproducibility gate across all execution shapes |
| 9 | blocks, scaled, exact reductions | **W2**; zero allocation at every `B` |
| 10 | packed execution | end-to-end targets without a second semantic path |
| 11 | binary/ternary tables, direct-code laws, SIMD, threading — **one at a time** | each has a measured win *and* an exhaustive certificate; losers deleted |
| 12 | approximation and conformance | no approximate implementation reachable from a defined plan |
| 13 | release review | full matrix on x86-64 and AArch64; deletion test on every seam |

Stage 4 is the risk concentration: if the window lemma fails on a case §1.1 did
not reach, the thesis needs revisiting. It is deliberately small, and its gate is
deliberately the most expensive relative to the code it covers.

Stages 1–7 depend on SmallFloats as a **test-only, version-pinned** dependency.
Once the exhaustive differentials are green and their digests are recorded as
goldens, the dependency is a digest, not a package.

---

## 17. Risks

| risk | severity | mitigation |
|:---|:---|:---|
| window lemma fails on an unreached case | **high** — the thesis rests on it | enumerated clean over 2.46 M pairs and 109.8 M triples; residual gap `K ∈ {7,8}` at `P ≥ 2` (strictly narrower spread) closed as a Stage 4 entry condition |
| `reinterpret` fabricates invalid high bits | high | `fromcode` is the only safe route; unsafe path private; exhaustive canonical-construction tests |
| tier-2 limb width mis-derived | high | derive and assert width mechanically; independent BigInt differential; exponent-gap and cancellation tests |
| a table becomes the semantic authority | high | semantic digest, checksum, entry differential, local rebuild fallback |
| indexed RNG repeats streams | high | versioned key derivation; explicit stream and invocation; collision tests |
| rigorous loop does not decide under a ceiling | medium | explicit `InconclusiveProjectionError`, destination unmodified — never a guess |
| catalogue becomes a meta-language | medium | catalogue holds metadata only; semantic families stay ordinary reviewed Julia |
| prepared plans explode specializations | medium | executor types vary by loop shape, IDs stay values, measure method instances |
| SmallFloats differential decays | medium | capture digests early; pin the version in the test manifest |
| performance plan overfits one CPU | medium | x86-64 and AArch64 matrices; ISA adapters optional and removable |
| fusion removes a mandated projection | medium | fusion whitelist limited to storage transforms around one signature |
| sampled κ described as a bound | medium | certificate type distinguishes estimate from exhaustive |
| `ScopedValue` read costs more than estimated | low | benchmark gate; fallback is a compile-time default with runtime setting removed |
| integer `Divide` dominates its target | low | 256-entry fixed-point reciprocal table — the operand significand is one byte |

Open questions that planning cannot settle:

1. Does a 64 KiB binary table beat a 3 ns kernel at `K ∈ 6:8`, given §9.1's
   79× build cost? Sets the table policy and nothing else.
2. Does `PackedVector` win on any workload that is not synthetically
   memory-bound?
3. Is threading worth having when the kernel is 3 ns and the bulk loop
   vectorizes? Check for a missing function barrier first (§9.4).
4. Atlas versus per-format decode tables — Stage 2 benchmark, including image
   size and load time, not just lookup latency.

---

## 18. Non-goals

- **`K > 8`.** Not a dormant seam. A `K = 16` format genuinely needs the carrier
  ladder, and not having one is this package's whole advantage. That is
  SmallFloats, and the split is a scope split, not a version split — neither
  package should grow toward the other.
- Implicit cross-format arithmetic; promotion is explicit, to Float64.
- Subtyping `FloatByte` — it is a primitive type and package methods assume the
  canonical-code invariant.
- Runtime registration of new *defined* operations.
- Approximate execution reachable from a defined plan.
- Direct packed-word arithmetic as a default strategy.
- Mutable session-wide rounding, result-format, or RNG defaults in the
  performance interface.
- Bit-compatibility with OCP FP8 under P3109 names (§12.2).
- GPU execution until a real second adapter passes the same assurance interface.
- Copying any code from SmallFloats into `src/` or `reference/`.

---

## 19. Completion criteria

FloatBytes 1.0 is complete when:

1. exactly 120 formats and 13 296 canonical codes exist;
2. every value is one byte, every safe construction maintains zero high bits;
3. code/value, decode, order, class, next, parse and display laws pass
   exhaustively;
4. Projection is independently verified across all policies and critical cells;
5. every defined operation reaches one `defined_code` seam;
6. every materialized table matches that seam entry-for-entry;
7. every adapter matches the independent reference wherever applicable;
8. **W1**, **W2**, **W3**, **G9** and **G10** are green at the release tier;
9. stochastic results do not change with threads, tiling, SIMD, or packing;
10. common scalar, array and block paths allocate **zero**, unconditionally;
11. no approximate implementation is reachable from a defined plan;
12. every conformance or κ claim states exhaustive, proved, or sampled scope;
13. load time, first use, code size, method count and cache bytes meet recorded
    ceilings;
14. every losing experimental adapter has been deleted;
15. documentation, catalogues and tests report the same semantic revision.

---

## 20. In one page

```text
FloatByte{K,P,S,D}     one concrete byte; named code identity; ordinary Julia float
Signature              immutable operation + formats + policy + entropy contract
defined_code           decode -> exact integer window (or enclosure) -> one projection -> UInt8
Prepared plan          immutable cost choice; strong table ownership; no semantic choice
Execution              kernel-first; unary LUT always; wider tables only on measured reuse
Assurance              independent rational/MPFR authority -> exhaustive certificates
```

The design is deliberately asymmetric: **scalar values carry rich format identity
in their type; bulk loops discard it once, operate on bytes, and regain typed
results without per-element construction.** Expensive rigour is paid during
semantic evaluation or table compilation, never per element.

Two facts make that asymmetry available, and both are `K ≤ 8` facts rather than
design cleverness: every defined algebraic result is exact in a single 64-bit
integer window, and the entire format lattice — cross-format included — can be
verified by enumeration rather than by argument.

What this plan must not claim is that the lightness came free. It came from a
restriction, and the restriction is exactly the thing SmallFloats exists to lift.
