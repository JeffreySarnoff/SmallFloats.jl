# FloatBytes.jl — Refactored Plan

*Refactor of [PlanTogether.md](PlanTogether.md), which merged
[PlanFloatBytes.md](PlanFloatBytes.md) and
[PlanningFloatBytes.md](PlanningFloatBytes.md).*

The merged plan described roughly twenty features. Reading it back, most of them
are **the same five mechanisms instantiated repeatedly** — the plan had merged
two documents without factoring what they shared. Tables, SIMD kernels, byte
laws, packed adapters, threading, artifacts and approximation each carried their
own admission rules, their own proof obligation and their own test story, and
those stories were the same story six times.

This refactor names the five abstractions once (Part I), shows every feature as
an instance (Part II), and keeps only what is genuinely irreducible (Part III).
No measured claim changed. The plan got shorter; more importantly, so did the
implementation it describes — five shared mechanisms means five test harnesses,
not twenty.

---

# Part I — The five abstractions

Everything in the package is one of these, or an instance of one.

## A1 · Signature — the immutable name of a defined function

```julia
Signature{OP,FR,POL,FS}      # operation, result format, policy, operand formats
```

Zero-size, fully static, hashable to a compact ID for value-keyed use. It names
*what* is computed and never *how*. Everything downstream is keyed by it:
`defined_code`, bounds derivation, domain construction, plan preparation, table
identity, certificates, conformance rows.

**One rule.** A signature determines the result bytes completely. Anything that
does not change the signature may not change the bytes.

## A2 · Domain — an enumerable operand set that knows its own completeness

```julia
Domain(sig)                  # the full operand space of a signature
enumerate(domain)            # iterate operand-code tuples
Verdict(:exhaustive | :sampled, count, generator, seed)
```

`Domain` is the single source of "what inputs exist", and it is shared by four
consumers that in PlanTogether each rolled their own:

| consumer | what it does with the same iteration |
|:---|:---|
| table compiler | writes `defined_code` into a table |
| verification | compares `defined_code` against `reference/` |
| κ measurement | records maximum code distance |
| conformance | reports coverage and its verdict |

Because `K ≤ 8`, a `Domain` is usually small enough to be exhausted, and it says
so itself. Nothing downstream may claim "verified" without a `Verdict`, and a
`:sampled` verdict may never be reported as a bound.

| domain | size | exhaustible |
|:---|:---|:---|
| all code points, all 120 formats | 13 296 | always |
| same-format binary, summed | 2 504 832 | always |
| **cross-format** binary, all pairs | 176 782 416 | release tier |
| same-format ternary, summed | 564 261 888 | release tier |

That last two rows are the reason this package can prove what SmallFloats can
only evidence.

## A3 · Collapse — any faster path, admitted by one gate

This is the largest consolidation. PlanTogether described these separately:
lookup tables, direct byte laws, SIMD kernels, threaded execution, packed
execution, artifact tables, approximate kernels, stochastic decision records.

They are one thing: **a candidate implementation that claims to agree with
`defined_code` over a declared applicability domain.**

```julia
collapse(candidate, sig; domain=Domain(sig)) -> Certificate
```

The certificate records candidate and semantic digests, the domain and its
`Verdict`, maximum code distance κ, special-value agreement, and toolchain
identity. One admission rule governs all eight:

> A collapse is admitted only with an exhaustive equivalence certificate over
> its declared domain **and** a measured win. κ = 0 makes it a *defined* path;
> κ > 0 makes it an *approximation*, which is a disjoint type that a defined
> request can never select.

Consequences that used to be written eight times:

- Tables are not special. A table is a collapse whose candidate is an array.
- Approximation is not special. It is a collapse with κ > 0 and a different type.
- Artifacts are not authorities. An artifact is a cached collapse; a digest
  mismatch falls back to local construction.
- Threading and SIMD are collapses whose domain includes the schedule.
- One certificate type, one verification harness, one failure-injection suite.

**Narrowest bypass wins.** A candidate returning a final *code* carries a
stronger obligation than one returning an exact *projection input*; prefer the
latter.

## A4 · StaticBounds — every width derived, asserted, never branched

PlanTogether derived widths in five places with five vocabularies: the 64-bit
window's `G = 40`, tier-2 limb counts, the block restart bound, the stochastic
`N` cap, the table byte budget. All are the same operation — **a static function
of the signature's format parameters, computed once at preparation, asserted,
and thereafter consumed by dispatch.**

```julia
bounds(sig) -> StaticBounds     # window sufficiency, limb count, restart bound,
                                # entropy width, table bytes, accumulator ceiling
```

Two laws, and they are what keep hot loops branch-free:

1. **Derive, assert, dispatch.** A bound is never recomputed in a loop and never
   consulted as a runtime condition. Where a condition is a function of static
   parameters, it goes behind a `Val` and dispatch selects the method.
2. **Refuse rather than degrade.** A bound that cannot be met returns a refusal
   before execution — `WorkspaceError`, `UnsupportedExecutionError`,
   `InconclusiveProjectionError` — and never a quietly widened or narrowed path.

## A5 · Plan — cost-only, immutable, empty in the interior

```julia
prepare(sig; execution=:auto) -> Plan       # immutable; owns its tables strongly
plan_traits(plan) / workspace_spec(plan)    # what it chose, and what it needs
```

**A different plan may never change a result.** Semantics select by dispatch on
singleton types; cost selects by an immutable plan value. The two axes never mix,
which is the whole of invariant "policy is dispatch, cost is a plan".

The interior of a prepared loop contains no registry lookup, format check, symbol
dispatch, dictionary lookup, cache lock, or strategy branch. Everything a loop
needs was resolved once, outside it.

Start with **three** plan classes. Add more only as admitted collapses (A3):

```text
DenseComputePlan     the tier-1 kernel over a byte view
UnaryTablePlan       the always-on 256-byte table
GenericArrayPlan     correctness adapter for odd axes, strides, views
```

---

# Part II — Everything as an instance

## 2.1 The one seam, and the one kernel shape

Every operation, at every arity, is four lines:

```julia
@inline function defined_code(sig::Signature{OP,FR,POL,FS}, w::EntropyWord,
                              codes::Vararg{UInt8,N}) where {OP,FR,POL,FS,N}
    r = special_row(OP, FS, codes)          # code-point rows — the draft's tables
    r === NotSpecial || return r
    x = evaluate(OP, bounds(sig), map(unpack, FS, codes)...)   # exact (A4)
    project_code(FR, POL, x, w)             # the one write path
end
```

Only `special_row` and `evaluate` vary by operation, and both are ordinary
reviewed Julia dispatched on the operation tag — not generated from strings, not
an expression tree. The catalogue supplies metadata; it never replaces
implementation with a meta-language.

Three properties follow from the shape rather than from discipline:

- **Specials are resolved on code points, before unpacking.** The draft's special
  rows *are* statements about code points, so this is one indirection closer to
  the text than decoding and testing `isnan`. It is also faster.
- **Projection happens exactly once**, because there is exactly one call to it.
- **Scalar apply, table build, array kernel, block lane, κ measurement and
  conformance are the same call**, differing only in how `A2` supplies operands.

`Convert` is the one deliberate variation: its operand is external, so `unpack`
is replaced by an exact ingest that produces the same `Datum`.

## 2.2 Exact evaluation — two tiers, one vocabulary

```julia
struct Datum    sig::UInt64; exp::Int32; neg::Bool end          # finite value
struct Aligned  w::UInt64; exp::Int32; neg::Bool; tail::Bool end # magnitude ± one unit
```

Both `isbits` and register-resident. **Nothing on any defined algebraic path
allocates, at any operation, for any format** — unconditionally, which is
stronger than SmallFloats can pin.

| tier | scope | width | selected by |
|:---|:---|:---|:---|
| 1 | every fixed 2-term expression | **one `UInt64`**, proven (Part III §1) | `bounds(sig)` |
| 2 | reductions, > 2 factors | `ExactDyad{L}`, `L` derived | `bounds(sig)` |

**Do not use tier 2 where tier 1 applies.** PlanFloatBytes would have paid
`L`-limb cost on every `Add`; the lemma proves one word suffices.

| operation | method | result |
|:---|:---|:---|
| `Add`, `Subtract` | window alignment | exact + tail |
| `Multiply` | `sig₁ * sig₂`, ≤ 16 bits | exact |
| `Divide` | `(sig₁ << 56) ÷ sig₂`, tail from remainder | exact + tail |
| `Sqrt` | `isqrt(sig << 46)`, tail from remainder | exact + tail |
| `RSqrt`, `Recip` | divide composed with sqrt | exact + tail |
| `FMA`, `FAA` | exact 16-bit product, then window | exact + tail |
| `Hypot` | exact `x² + y²` by window, then integer sqrt | exact + tail |
| `Clamp`, min/max, `CopySign` | order keys on code points | exact |
| `Convert` | ingest, round to target | exact |

Selection operations are the natural first **collapse** (A3): they are byte laws
over code points, exhaustively certifiable in 65 536 comparisons.

## 2.3 Everything else, mapped

| PlanTogether feature | is an instance of | what it stops needing |
|:---|:---|:---|
| lookup tables (unary / binary / ternary) | A3 collapse, array candidate | its own admission rules, its own verification |
| direct byte laws | A3 collapse, final-code candidate | a separate certification story |
| SIMD kernels | A3 collapse, domain includes CPU features | a bespoke equivalence argument |
| threaded execution | A3 collapse, domain includes the schedule | separate reproducibility text |
| packed execution | A3 collapse + A5 plan class | a second semantic path |
| artifact table packs | A3 certificate, cached | "artifacts are not authorities" restated |
| approximation and κ | A3 with κ > 0, disjoint type | a registry consulted by defined execution |
| stochastic decision records | A3 collapse over `(inputs × entropy)` | its own budget vocabulary |
| table byte budget | A4 bound | invariant 10's separate machinery |
| accumulator limb count | A4 bound | per-site derivation |
| block restart bound (9) | A4 bound | a standalone proof |
| entropy width `N` cap | A4 bound | a scattered constant |
| verification tiers T1–T8 | A2 domains + one harness | eight bespoke suites |
| conformance record | A2 verdicts + A3 certificates | copied strings |
| plan classes | A5 | strategy branches in loops |

## 2.4 Stochastic execution

Entropy is explicit and **indexed**, which is what makes threaded stochastic
rounding reproducible — a property SmallFloats lacks, since its RNG consumption
follows the schedule.

```julia
IndexedEntropy(seed, stream, invocation)    # counter-based, schedule-independent
SequentialEntropy(rng)                      # conventional; forces a sequential plan
```

Exactly one `N`-bit word per logical output, including exact and special results.
Fixed consumption makes slicing, replay and composition auditable. The key
includes algorithm version, seed, stream, invocation, logical index and
projection slot.

A stochastic result is a distribution over the draw, not a function of the
operands, so **a plain result table is forbidden**. A *decision* record is
permitted: it is a collapse (A3) over the enlarged domain `inputs × entropy`.

## 2.5 Storage adapters

Arrays of `FloatByte` are byte arrays: `reinterpret(UInt8, ::Vector)` is
zero-copy, verified. Dense execution lowers to a byte view **once**, outside the
loop, so result construction is not repeated per element.

Blocks are structure-of-arrays over byte storage, not long tuples. This is not
style: SmallFloats measured a tuple-length allocation cliff — `BlockAdd`
allocating 48 B at `B = 8`, 3200 B at `B = 32`, 6128 B at `B = 64`, where
`ntuple(Val(B))` is no better and the fix is a representation change. Do not
build on tuples and then discover it.

Packed storage (`K ∈ 3:7`) fuses unpack → execute → repack over reusable tiles;
`K = 8` is an identity byte view. Be honest about the payoff: SmallFloats
measures pack at 0.53 ns/element and unpack at 0.44 ns/element against a
0.13 ns/element unary gather, so packing pays on memory-bound workloads and loses
elsewhere.

---

# Part III — What does not factor

Four things are irreducible. They are the actual content of the package.

## 1 · The window lemma, and its evidence

> Place the larger-magnitude significand in a `UInt64` with its LSB at bit
> `G = 40`; align the smaller by the exponent difference; record whether nonzero
> bits fell off the bottom. The resulting `(window, exponent, tail-sign)` triple
> determines the same correctly rounded `P`-significant-bit result as the exact
> rational value, for every `P ≤ 8` and every rounding mode.

*Why.* If the exponent difference `sh ≤ 40`, the smaller term is retained exactly
and the sum is exact. If `sh > 40`, the smaller is below `2^-40` of the larger,
so no cancellation is possible and the window carries ≥ 40 correct bits above the
truncation point — against the 10 the target needs. A dropped tail is recorded as
a sign, which is exactly the evidence every rounding predicate consumes.

The subtle case is a *negative* tail from `w1 − w2`; normalize it away by
`w − ε ≡ (w − 1) + (1 − ε)`. Sound only because a dropped tail requires
`sh > 40`, forcing `w1 ≥ 2^40 > 255 ≥ w2` — asserted inside the check, not
claimed in prose.

**Evidence**, against a `Rational{BigInt}` reference
([w1_window_lemma_add.jl](w1_window_lemma_add.jl),
[w1_window_lemma_fma.jl](w1_window_lemma_fma.jl)):

```
Add:    2 459 235 datum pairs, all 120 formats                       0 mismatches
FMA:  109 800 088 operand triples, every K ≤ 6 format plus nine
      K ∈ {7,8} formats including every widest-spread case           0 mismatches
```

`Binary8p1uf` — `B = 128`, the 506-binade worst case — is covered at all
16 581 375 of its triples. Residual gap: `K ∈ {7,8}` at `P ≥ 2`, all strictly
narrower in spread. Closed as a Stage 4 entry condition, not assumed.

This lemma is why there is no carrier lattice, no `Float128`, no `Dyadic`, and no
MPFR on any defined algebraic path. It replaces `src/carriers.jl` (416 lines),
`src/dyadic.jl` (941), `src/fma128.jl` + `src/faa128.jl` (631) and most of
`src/oracle.jl` (1136).

## 2 · The premise, in measured numbers

| quantity | value |
|:---|:---|
| legal formats (`4K − 2` per `K`, `K ∈ 3:8`) | 120 |
| code points, summed | 13 296 |
| maximum exponent bias `B` | 128 (unsigned, `K = 8`, `P = 1`) |
| datum magnitude range | `2^-127 … 2^126` |
| datum binade spread | 253 |
| significand bits per datum | ≤ 8 |
| Float64 / Float32 decode atlas | 106 368 B / 53 184 B |

What stays hard, so the lightness is not oversold: **transcendentals** (25 unary
plus `ArcTan2`/`ArcTan2Pi`) still need rigorous enclosure; **reductions of more
than two terms** are outside the lemma; **`Divide`/`Sqrt`** need
quotient/remainder reasoning the window supports but does not by itself justify.

Transcendentals are contained rather than solved: a unary operation on a `K ≤ 8`
format has **at most 256 inputs**, so its complete correctly rounded table is
≤ 256 bytes. MPFR appears at exactly one site, in cold table construction, and is
never reached from a scalar, array or warm path. Under a caller's precision
ceiling that does not decide, throw `InconclusiveProjectionError` — never a
midpoint, never a guess. With ≤ 256 inputs a hard case is *findable*: enumerate
and record the required precision as a constant.

## 3 · The type, and named code identity

```julia
abstract type Signedness end;  struct Signed <: Signedness end
                               struct Unsigned <: Signedness end
abstract type DomainKind end;  struct Finite <: DomainKind end
                               struct Extended <: DomainKind end

primitive type FloatByte{K,P,S<:Signedness,D<:DomainKind} <: AbstractFloat 8 end
const Binary8p4se = FloatByte{8,4,Signed,Extended}
```

Verified: parses, `isbitstype`, `sizeof == 1`, `Base.elsize(Vector) == 1`,
zero-copy `reinterpret`.

Because the type is **concrete**, SmallFloats' invariant 8 — "format types are
propagated, never rebuilt", enforced by a textual scan of `src/` — is vacuous
here. Rebuilding `FloatByte{K,P,S,D}` is the identity. The defect class is not
policed; it does not exist.

```julia
fromcode(::Type{T}, code::Integer)::T     # validates 0 ≤ code < 2^K
codepoint(x)::UInt8                       # decode(x)::Float64 — exact
quantize(::Type{T}, value, policy; entropy=nothing)::T
```

Every `T(value::Real)` argument means a numeric value, at every integer width.
This drops SmallFloats' rule that `Unsigned` means *code point*, which keys
meaning to a coincidence of Julia's type lattice. There is no public unchecked
constructor; `reinterpret` into `FloatByte` is documented unsafe.

**Package-wide naming law**, from SmallFloats' `mul_dy` post-mortem: where a
checked and an unchecked form both exist, they get **two names**, never one name
with an annotation. `@boundscheck` elides only under an `@inbounds` caller, so a
precondition guarded that way has a cost profile no call site can predict — it
cost SmallFloats 3.3× on every rung-3 multiply.

## 4 · OCP FP8: measured, and refused

| format | max finite | infinities | NaN codes |
|:---|:---|:---|:---|
| `Binary8p4sf` | 240 | 0 | 1 |
| `Binary8p4se` | 224 | 2 | 1 |
| OCP E4M3 | 448 | 0 | 2 |
| `Binary8p3sf` | 57 344 | 0 | 1 |
| `Binary8p3se` | 49 152 | 2 | 1 |
| OCP E5M2 | 57 344 | 2 | 6 |

P3109 uses a power-of-two exponent bias; IEEE and OCP use `2^(w−1) − 1`. The
biases differ by one, so the grids differ throughout. The closest pair,
`Binary8p3sf` and OCP E5M2, share a maximum finite value and *nothing else*:
their finite datum sets have **255 and 248 members** and are not equal, checked
element by element.

**No P3109 8-bit format is bit-identical to either OCP FP8 format.** Ship no
aliases; ship the comparison table; if OCP formats are wanted, add them as
first-class separate formats under their own names, sharing the kernels but not
the lattice. An alias that is 99% right is worse than none, because it will be
believed.

---

# Part IV — Assurance, performance, execution

## 4.1 Independent authority

Two references, and **no code copied from SmallFloats into `src/`** — copying
reintroduces circularity through the back door.

1. **`reference/`** — `Rational{BigInt}` for algebraic operations, separately
   coded special rows, directed MPFR intervals for elementary functions. It must
   not call production decode, projection, special rules, kernels, or tables.
2. **SmallFloats `K ∈ 3:8`** — an independently developed, heavily gated
   implementation of the same draft, as a second differential adapter, test-only
   and version-pinned.

Enforced by a test that greps: **nothing under `src/` may be referenced by
`reference/`.** A naive reference is only a reference if it shares no code with
what it checks. Where the two disagree, resolve against the **draft text**, never
by majority.

One comparison, for every collapse in the package:

```text
reference/ == defined_code == byte law == local table == artifact
           == dense == generic == SIMD == threaded == packed
```

Comparison is **code identity in identical logical order**. Numerical tolerance
is not evidence for a finite code function.

## 4.2 Gate accounting

Six of SmallFloats' ten gates police machinery this design does not contain:

| gate | fate | gate | fate |
|:---|:---|:---|:---|
| G1 `_DE_*` width thresholds | **gone** | G6 carrier-lift exactness | **gone** |
| G2 `bigprec` sufficiency | **gone** | G7 `HeadExact` carrier swap | **gone** |
| G3 `_rtp_f64` bit ≡ generic | **gone** | G8 representation invariant | kept, as construction + round-trip |
| G4 rung-selection equivalence | **gone** | G9 trait folding | **kept** |
| G5 golden non-regression | replaced by the SmallFloats differential | G10 surface totality | **kept and widened** |

Three new gates, one per irreducible risk:

- **W1 — the window lemma.** Part III §1's enumeration, as a test.
- **W2 — the reduction restart bound.** Terminates within 9 restarts on every
  input; agrees with the superaccumulator reference on constructed cancellation.
- **W3 — zero allocation on every defined path, unconditionally.**

**G10 is kept and widened, and the reason bears restating.** It is the one gate
that is broad rather than deep — it asserts only that every catalogue operation on
every surface returns and holds its declared result type. Six Stage 7 defects in
SmallFloats lived in exactly that blind spot and survived a green suite. A shallow
gate earns its place by being total: do not deepen it, do not narrow it.

Tiers are A2 domains, not bespoke suites: `quick` (all code points, same-format
binary at the default policy) · `default` (+ all policies, sampled ternary) ·
`release` (+ the full 177 M cross-format lattice, full ternary, ~45 min). **A tier
the caller asks for is honoured, never downgraded.**

## 4.3 Performance

Every target names its source file, table and row. This rule exists because both
source plans, reading the same package honestly, set different targets from
different rows — and one of them set a target that was already met.

Baselines from `benchmarking/benchmark_report.md` at `Binary8p4se` under
`(NearestTiesToEven, SatNone)`.

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
| `vmap` unary / binary gather | 0.13 / 0.25 ns/elem | hold | already gather-bound |
| `vmap` ternary (**shipped compute row**) | 3.17 ns/elem, **42 allocs** | ≤ 3 ns/elem, **0 allocs** | kernel, no table tier |
| 64 K binary table build, ordinary format | 79.5 µs, 44 allocs | hold | already good |
| 64 K binary table build, **wide-spread** format | 2.57 ms, 536 594 allocs | **≤ 80 µs, ≤ 44 allocs** | no escalation ⇒ build cost is format-independent |
| `BlockDotProduct` (B = 32) | 320 ns, 3 allocs | ≤ 250 ns, **0 allocs** | windowed reduction |
| `ConvertToBlockMaxAbsFinite` (B = 32) | 3.75 µs, 111 allocs | ≤ 1 µs, **0 allocs** | no tuple cliff |

**The medians are the story.** SmallFloats' minima are already good; its medians
run 2–5× higher because the median operand pair triggers escalation. An integer
kernel has no such distribution: *the target is not a lower minimum, it is a
median that equals the minimum.*

**The table-build variance is the second story.** The same table for the same
operation costs 32× more time and 12 000× more allocations on a wide-spread
format, entirely from MPFR escalation. Removing that cliff matters more than
lowering the mean. Break-even for a binary table against a 3 ns kernel is about
**3× the array** (≈ 200 k elements per signature) — real, but nowhere near enough
to justify a store, artifact packs and decision records before reuse is
demonstrated. Hence A3: they are admitted one at a time, on evidence.

### Doctrine, adopted whole

Each rule was paid for by a measurement post-mortem in SmallFloats:

- A closure over a non-`const` global measures Julia's dispatch machinery, and
  distorts **ratios**, not just absolutes.
- **One variant per process, alternating, or nothing.** A multi-variant process
  reported a rewrite as a 1.87× win that alternating processes reversed into a
  31% loss.
- **A loop that overwrites its accumulator measures dead-code elimination.**
  Reduce, and end with `Base.donotdelete`.
- Warm up until the number stops moving; seed the data.
- Machine drift between blocks reached ~10%; A/B from a git worktree pinned at
  base, in immediate alternation.
- A preflight **aborts the run** if a warm scalar path allocates.
- Before threading anything, check the serial path specializes — SmallFloats'
  threading wins were substantially a missing function barrier in disguise.
- **Name the source row.**

**An optimization that misses its target is deleted.** Dormant adapters cost
tests, compilation and maintainer knowledge.

## 4.4 Julia surface

Full `AbstractFloat` surface; promotion targets **Float64** (exact for every
datum, and it avoids pretending a cross-format join is canonical); `UInt16`
monotone order key with counting sort above a measured break-even.

Base operators require same-format operands and one **immutable** package policy.
No mutable global default. A scoped override

```julia
with_projection(ρ) do ... end        # ScopedValue, task-local
```

is a documented adapter explicitly **outside** the performance interface —
explicit `apply(sig, x, y)` is the fast path and always was. This deletes
SmallFloats' 232-line speculation-guard apparatus and gains task-locality the
`Ref` never had.

**The total order puts NaN first, below −Inf** (draft §4.12.1) — the opposite end
from Float64 sorting, key 0 reserved for NaN. Following Julia's convention here
would be a regression, not a fix.

**`show` must never be the thing that throws**, and no display style may change a
result. **A docstring is a string literal before it is prose**: `\(`, `\[`,
`\text` are invalid Julia escapes, and one of them once made `using SmallFloats`
fail outright.

## 4.5 Dependencies and layout

Core: `Random`, `SHA`, threading, `BigInt`/`BigFloat` — all Base or stdlib.
**No non-stdlib runtime dependency.** Optional extensions may improve cost only;
the core fallback stays complete and bit-identical.

Load order, stated here and in one comment at the top of the module. Changing it
means changing that comment in the same commit.

```text
src/  FloatBytes.jl
      result_protocol.jl   <- FIRST, zero package dependencies
      domain.jl  formats.jl  show.jl  policies.jl  projection.jl
      semantics.jl  operations/{algebraic,selection,elementary,conversion}.jl
      catalogue.jl  signatures.jl  bounds.jl  planning.jl  collapse.jl  tables.jl
      execution/{dense,generic,stochastic,threaded}.jl
      blocks.jl  packed.jl  conformance.jl  julia_adapters.jl
ext/  Quadmath  BFloat16  SIMD
reference/  draft_model.jl  rational_projection.jl  interval_oracle.jl
test/  lattice  projection  semantics  collapse  stochastic  blocks  packed
       assurance  julia_interface
```

`result_protocol.jl` — `Datum`, `Aligned`, the window primitives — loads first
with zero package dependencies: the exact-evaluation substrate must be checkable
on its own terms. `show.jl` sits early so the display layer is available to every
later file's error paths, which is what makes "`show` must never throw"
enforceable rather than aspirational.

Note the three files the refactor *adds* — `signatures.jl`, `bounds.jl`,
`collapse.jl` — and the ones it removes by making them instances:
`approximation.jl` folds into `collapse.jl`, and the table store shrinks to a
cache behind it.

---

# Part V — Stages, risks, non-goals

## 5.1 Stages

Each stage builds one abstraction or instantiates it. Optimization begins only
after independent defined behaviour exists.

| stage | content | exit gate |
|:---|:---|:---|
| 0 | charter, non-goals, error taxonomy, manifests | Part III §2's facts machine-checked over all 120 formats |
| 1 | `reference/`; golden corpus; SmallFloats differential | a slow clear authority exists that production cannot call |
| 2 | **A1** signatures, **A2** domains, Byte Domain, decode atlas | all 13 296 codes exhaustive; one-byte layout pinned; *no arithmetic yet* |
| 3 | Projection — the only code-producing implementation | projection cells exhaustive vs `reference/` |
| 4 | **A4** bounds; tier-1 window; `defined_code`; semantic spine | **W1** complete incl. `K ∈ {7,8}` at `P ≥ 2`; **W3**; same-format binary exhaustive |
| 5 | Julia scalar surface, aliases, fixed policy, `with_projection` | inference and allocation baselines |
| 6 | **A5** plans (3 classes), **A3** collapse machinery, unary tables | every table entry matches `reference/`; one certificate type in use |
| 7 | full catalogue, family by family | generated surfaces cannot drift; **G10** full tier |
| 8 | indexed entropy, stochastic decision collapses | reproducibility across every execution shape |
| 9 | blocks, scaled, exact reductions | **W2**; zero allocation at every `B` |
| 10 | packed execution | end-to-end targets without a second semantic path |
| 11 | further collapses — binary/ternary tables, byte laws, SIMD, threading — **one at a time** | each has a certificate *and* a measured win; losers deleted |
| 12 | κ collapses, conformance | no approximation reachable from a defined plan |
| 13 | release review | x86-64 and AArch64; deletion test on every seam |

Stage 4 is the risk concentration: if the lemma fails on a case Part III §1 did
not reach, the thesis needs revisiting. It is deliberately small and its gate is
deliberately the most expensive relative to the code it covers.

Stages 1–7 depend on SmallFloats as a test-only, version-pinned dependency. Once
the differentials are green and digested as goldens, the dependency is a digest,
not a package.

## 5.2 Risks

| risk | severity | mitigation |
|:---|:---|:---|
| window lemma fails on an unreached case | **high** — the thesis rests on it | clean over 2.46 M pairs and 109.8 M triples; residual `K ∈ {7,8}`, `P ≥ 2` closed at Stage 4 |
| `reinterpret` fabricates invalid high bits | high | `fromcode` only safe route; unsafe path private; exhaustive construction tests |
| a derived bound (A4) is wrong | high | derive *and assert*; independent BigInt differential; exponent-gap and cancellation tests |
| a collapse (A3) becomes the authority | high | semantic digest, checksum, entry differential, local rebuild fallback |
| indexed entropy repeats streams | high | versioned key derivation; explicit stream and invocation; collision tests |
| rigorous loop undecided under a ceiling | medium | explicit `InconclusiveProjectionError`, destination unmodified |
| catalogue becomes a meta-language | medium | metadata only; semantic families stay ordinary reviewed Julia |
| plans explode specializations | medium | executor types vary by loop shape; IDs stay values; measure method instances |
| SmallFloats differential decays | medium | capture digests early; pin the version |
| performance overfits one CPU | medium | x86-64 and AArch64; ISA adapters optional and removable |
| sampled κ reported as a bound | medium | `Verdict` type distinguishes sampled from exhaustive |
| `ScopedValue` read costs more than estimated | low | benchmark gate; fallback is a compile-time default |
| integer `Divide` dominates its target | low | 256-entry reciprocal table — the significand is one byte |

Open questions planning cannot settle: does a 64 KiB binary table beat a 3 ns
kernel at `K ∈ 6:8` given the ~3× break-even · does packing win outside
synthetically memory-bound work · is threading worth having once the kernel is
3 ns and the loop vectorizes · atlas versus per-format decode tables, judged on
image size and load time as well as latency.

## 5.3 Non-goals

**`K > 8`** — not a dormant seam. A `K = 16` format genuinely needs the carrier
ladder, and not having one is this package's whole advantage. That is
SmallFloats; the split is a scope split, not a version split, and neither package
should grow toward the other.

Also: implicit cross-format arithmetic · subtyping `FloatByte` · runtime
registration of defined operations · approximation reachable from a defined plan
· direct packed-word arithmetic as a default · mutable session-wide defaults in
the performance interface · bit-compatibility with OCP FP8 under P3109 names ·
GPU until a real second adapter passes the same assurance interface · copying any
code from SmallFloats into `src/` or `reference/`.

---

# In one page

```text
A1 Signature      immutable name of a defined function; determines the bytes
A2 Domain         enumerable operand set that knows its own completeness
A3 Collapse       any faster path, admitted by certificate + measured win
A4 StaticBounds   every width derived, asserted, dispatched — never branched
A5 Plan           cost-only, immutable, empty in the interior

defined_code      special_row -> unpack -> evaluate -> project_code
                  four lines, every operation, every arity
```

The design is deliberately asymmetric: **scalar values carry rich format identity
in their type; bulk loops discard it once, operate on bytes, and regain typed
results without per-element construction.** Expensive rigour is paid during
semantic evaluation or collapse construction, never per element.

Two `K ≤ 8` facts make that available, and neither is design cleverness: every
defined algebraic result is exact in a single 64-bit integer window, and the
entire format lattice — cross-format included — is verifiable by enumeration
rather than by argument.

What this plan must not claim is that the lightness came free. It came from a
restriction, and the restriction is exactly the thing SmallFloats exists to lift.
