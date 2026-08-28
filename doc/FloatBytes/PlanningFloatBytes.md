# Planning FloatBytes.jl

*A deep reimplementation of the IEEE P3109 draft for `3 ≤ K ≤ 8`, written from
the ground rather than derived from SmallFloats.jl.*

Drafted 2026-08-04. Three passes: initial design, review for clarity and
performance, revision. §17 records what the review changed and why — the
first draft was wrong in five places, and the corrections are the most
load-bearing content in this document.

---

## 1. Why this is a different package, not a smaller one

The instinctive framing — "SmallFloats with `KMAX` set to 8" — is wrong, and
getting that wrong would produce a package that is 20% smaller and 0% better.
Restricting to `K ≤ 8` does not shrink the existing architecture; it removes
the *premise* the existing architecture was built to satisfy.

Three facts do the work. Each is measured, not assumed.

### 1.1 One storage unit

Every `K ≤ 8` code point fits a byte. SmallFloats splits `Binary{K,P,S,E}`
(abstract format) from `Code8`/`Code16` (concrete representation) because at
`K ≤ 16` the storage unit is not a function of the format alone in any way the
type system makes convenient. At `K ≤ 8` it is a constant.

So `Binary{K,P,S,E}` can be **concrete**:

```julia
primitive type Binary{K,P,S,E} <: AbstractFloat 8 end
```

Verified: this parses, `isbitstype` is `true`, `sizeof` is 1,
`Base.elsize` of a `Vector` is 1, and the array reinterprets to `Vector{UInt8}`
with no copy.

That single change deletes `reptype`, `codeunit_type`, `decodepolicy`,
`Code8`/`Code16`, the `_finite_datum` representation dispatch, the
abstract-format forwarders every representation-keyed function needs — and
SmallFloats' architectural invariant 8 in its entirety, along with the textual
`stage_gates.jl` scan that enforces it. Invariant 8 exists because rebuilding
`Binary{K,P,S,E}` in a method body yields an abstract type that is not a valid
array element type and *stores silently* into a `Ref{Type{<:Binary}}`. When the
format type is concrete, rebuilding it is the identity. The defect class is not
policed; it does not exist.

### 1.2 One evaluation model — and it is integer arithmetic

Measured over all 120 formats (`K ∈ 3:8`, `P ∈ 1:K`, signed/unsigned,
finite/extended, less the two `P == K` signed combinations):

| quantity | value |
|:---|:---|
| formats | 120 |
| code points, summed over all formats | 13 296 |
| maximum exponent bias `B` | 128 |
| datum magnitude range | `2^-127 … 2^126` |
| datum binade spread | 253 |
| significand bits per datum | ≤ 8 |

Every datum is `±s · 2^e` with `s < 2^8` and `e ∈ [-134, 126]`. A product of two
datums is `±s · 2^e` with `s < 2^16`. These are **exact small integers**, and
correct rounding to a `P ≤ 8` target needs the true result only to `P + 2` bits
plus the sign of everything below.

That is the whole thesis: at `K ≤ 8`, **every defined algebraic result is
correctly roundable in fixed-width integer arithmetic.** No `Float64` carrier,
no `Float128`, no `Dyadic`, no MPFR — on any defined path.

SmallFloats cannot make that claim, and its architecture is the shape of the
reasons it cannot. `src/carriers.jl` (416 lines) selects among three carrier
rungs because a `P = 16`, `B = 32768` format overflows `Float64`.
`src/dyadic.jl` (941 lines) is the rung-3 exact carrier. `src/fma128.jl` and
`src/faa128.jl` (631 lines) are vendored `Float128` kernels. `src/oracle.jl`
(1136 lines) is a catalogue of exactness-by-width thresholds, sticky-band
analyses, and MPFR enclosure ladders — its own header lists five distinct result
protocols. `src/project.jl` carries three separate `round_to_precision`
implementations, one per carrier, with an exhaustive gate (G3) asserting they
agree bit-for-bit.

None of that is over-engineering. All of it is the correct answer to
`K ≤ 16`. None of it is needed at `K ≤ 8`.

### 1.3 The lattice is exhaustively enumerable in *every* direction

| enumeration | points |
|:---|:---|
| all code points of all 120 formats | 13 296 |
| all same-format binary operand pairs, summed | 2 504 832 |
| all **cross**-format binary operand pairs | 176 782 416 |
| all same-format ternary operand triples, summed | 564 261 888 |

The cross-format number is the one that matters. SmallFloats' verification
doctrine says "enumerate where affordable, and say *sampled* in so many words
where not"; at `K ≤ 16` the cross-format binary lattice is far past affordable,
so it is sampled by shape class. At `K ≤ 8` it is 177 million points — a few
minutes at a release tier. **Every unary and binary operation over the entire
format lattice, cross-format included, can be verified by enumeration.**

That changes what verification *is*. It stops being evidence and starts being
proof.

---

## 2. The load-bearing lemma, and its evidence

Everything in §1.2 reduces to one claim, so it was tested before it was
written down.

> **Window lemma.** Let `a` and `b` be datums of any `K ≤ 8` format. Place the
> larger-magnitude significand into a `UInt64` with its least significant bit at
> position `G = 40`. Align the smaller by the exponent difference, recording
> whether any nonzero bits fell off the bottom. Then the resulting
> `(window, exponent, tail-sign)` triple determines the same correctly rounded
> `P`-significant-bit result as the exact rational sum, for every `P ≤ 8` and
> every rounding mode.

**Proof sketch.** The window holds the dominant significand at bits `40 … 55`
with eight bits of carry headroom above. If the exponent difference `sh ≤ 40`,
the smaller term is retained *exactly* — nothing is lost, so the sum is exact.
If `sh > 40`, the smaller term is at most `2^-40` of the larger, so no
cancellation is possible and the result magnitude is at least `(1 − 2^-40)`
times the larger; the window therefore carries at least 40 correct bits above
the truncation point, against the 10 the target needs. A dropped tail is
recorded as a sign, which is exactly the evidence every rounding predicate
consumes.

The one subtle case is a *negative* tail, from `w1 − w2` where `w2`'s tail was
dropped: the true magnitude is `w − ε`. Normalize by decrementing the window and
setting the tail positive — `w − ε ≡ (w − 1) + (1 − ε)`. This requires
`w1 > w2` strictly whenever a tail exists, which holds because a tail requires
`sh > 40`, which forces `w1 ≥ 2^40 > 255 ≥ w2`.

**Evidence.** Implemented against a `Rational{BigInt}` reference and enumerated:

```
Add:    2 459 235 datum pairs across all 120 formats — 0 mismatches
FMA:  109 800 088 operand triples — every format at K ≤ 6 exhaustively,
      plus nine K ∈ {7,8} formats including every widest-spread case — 0 mismatches
```

FMA is the harder case: the product carries 16 significand bits and the
addend-versus-product exponent spread reaches 506 binades, where Add's reaches
253. `Binary8p1uf` — `B = 128`, the widest spread in the entire lattice — is in
the sweep at all 16 581 375 of its triples, clean. The window and the tail rule
are unchanged between the two operations, and the run's `@assert` on the lemma's
premise (equal windows never carry a dropped tail) never fired across 109.8
million triples.

Not yet enumerated: the remaining `K ∈ {7,8}` formats at `P ≥ 2`. Those have
strictly *narrower* exponent spread than the `P = 1` cases already covered, so
the risk is low — but "low" is not "checked", and §9 makes completing the sweep a
Stage 2 entry condition rather than an assumption.

This lemma is promoted to a **required gate** in the new package, not left as a
comment. A design that rests on an arithmetic argument should re-run the
argument on every commit.

---

## 3. What carries over from SmallFloats

Reimplementation is not repudiation. These are correct and should be restated
verbatim in the new doctrine file.

- **One write path.** `project = round → saturate → encode` is the only producer
  of a code point. Every operation and every carrier enters through it.
- **Code point versus value.** `Unsigned` means *code point* at every width;
  every other `Real` means *value*. `T(0x08)` is code point 8, `T(8)` is the
  value 8.0. `convert` is the deliberate value-preserving exception.
- **The representation invariant.** The code point occupies the low `K` bits;
  high bits are maintained zero.
- **Stochastic ρ is never tabulable.** A stochastic result is a distribution over
  the random draw, not a function of the operands. Table builders must refuse it
  loudly.
- **Nothing approximate is reachable from the default API.** The κ registry, with
  κ verified by enumeration at registration time.
- **A table entry IS the defined result** — one trip through the same scalar
  path, so there is no residual correctness reasoning at a use site.
- **Registry-driven codegen.** One `OP_REGISTRY` generates the spec register, the
  convenience methods, the Base veneers, the bulk variants, the test enumeration
  and the conformance report. A variant that cannot be written unevenly cannot
  diverge.
- **Policy is dispatch, never a branch.**
- **The total order puts NaN first, below −Inf** (draft §4.12.1), the opposite end
  from `Float64` sorting, with key 0 reserved for NaN.
- **`show` must never be the thing that throws**, and display styles are a view
  that no kernel, trait or projection may read.
- **Docstrings are string literals before they are prose** — no `\(`, `\[`, or
  `\text`, which are invalid Julia escapes and stop the file parsing.
- **Enumerate rather than sample, and say "sampled" in so many words when you
  cannot.**

---

## 4. What is deliberately different

Ordered by how much each one changes.

### 4.1 The format type is concrete

Per §1.1. `Binary{K,P,S,E}` is a parametric primitive type of 8 bits.

The one thing lost is a place to hang a second representation. At `K ≤ 8` there
is no second representation, and if one is ever wanted the package is the wrong
one — that is what SmallFloats is for. The relationship between the two packages
is a **scope split, not a version split**, and neither should grow toward the
other.

A primitive type has no inner constructor, so validation moves outward. This is
an improvement rather than a compromise: SmallFloats puts the format check
inside a `@boundscheck`, which — per its own performance doctrine, learned from
the `mul_dy` post-mortem — elides only under an `@inbounds` caller and therefore
has a cost profile nobody can predict from the call site. FloatBytes gets two
explicitly named routes instead:

| route | checks | use |
|:---|:---|:---|
| `Binary{K,P,S,E}(c::Unsigned)` | format validity, `c < 2^K` | public construction |
| `rawvalue(T, c::UInt8)` | nothing | kernel interior, after `encode` |

Two names, one contract each, visible at the call site. The rule SmallFloats
arrived at the hard way, adopted from the start.

### 4.2 Evaluation is exact integer arithmetic

The core type is a finite-only unpacked datum:

```julia
struct Datum          # a FINITE value: (-1)^neg * sig * 2^exp
    sig::UInt64       # sig == 0 iff the value is zero
    exp::Int32
    neg::Bool
end

struct Aligned        # a magnitude known to within one window unit
    w::UInt64         # true magnitude is (w + tail*eps) * 2^exp, 0 < eps < 1
    exp::Int32
    neg::Bool
    tail::Bool        # normalized: the tail is never negative (§2)
end
```

Both are `isbits` and register-resident. Nothing on any defined path allocates,
at any operation, for any format — not "except when the spread escalates to
MPFR", which is SmallFloats' honest but unavoidable caveat.

**Specials never enter `Datum`.** Each kernel dispatches on the operand *code
points* first, against the draft's special-value tables, and only unpacks
survivors. This is both faster and more faithful: the draft's special rows are
statements about code points, so writing them as code-point rows makes the rows
literally be the spec. SmallFloats decodes to a carrier and then tests
`isnan`/`isinf` on the carrier, which is one indirection away from the text.

The complete kernel set:

| operation | method | exactness |
|:---|:---|:---|
| `Add`, `Subtract` | window alignment (§2) | exact + tail |
| `Multiply` | `sig1 * sig2`, ≤ 16 bits | exact |
| `Divide` | `(sig1 << 56) ÷ sig2`, tail from remainder | exact + tail |
| `Sqrt` | `isqrt(sig << 46)`, tail from remainder | exact + tail |
| `RSqrt`, `Recip` | divide composed with sqrt | exact + tail |
| `FMA`, `FAA` | exact 16-bit product, then window | exact + tail |
| `Hypot` | exact `x² + y²` by window, then integer sqrt | exact + tail |
| `Clamp`, min/max family, `CopySign` | order keys on code points | exact |
| `Convert` | unpack source, round to target | exact |

Every row is a dozen to thirty integer operations. There is no escalation ladder
because there is nothing to escalate to and nothing to escalate for.

### 4.3 Transcendentals are a cold table build, not a hot path

Twenty-five unary operations (`Exp`, `Log`, the trigonometric and hyperbolic
families, `Softplus`) and two binary ones (`ArcTan2`, `ArcTan2Pi`) are genuinely
transcendental. `Hypot` is not — it is algebraic, and §4.2 computes it exactly.

A unary operation on a `K ≤ 8` format has **at most 256 possible inputs**. Its
complete correctly rounded result table is at most 256 bytes. So:

- MPFR appears exactly once in the package, in `transcend.jl`, building a
  ≤ 256-entry table with a Ziv loop that terminates on a proven-unambiguous
  rounding.
- It is never called on a scalar path, an array path, or a warm path.
- The `ArcTan2` family is 65 536 entries — 64 KiB — built the same way, cost-gated.

This is a *lower* dependency footprint than SmallFloats (MPFR is `Base`;
`Quadmath` and `BFloat16s` are dropped) and a *higher* confidence one: the
enclosure ladder, the `Enclose128F` / `EncloseF` protocols, the `fq` pre-filter
with its `2^-90` error budget, and the published-libquadmath-bound arguments all
disappear, replaced by "build the table with enough precision and prove the
rounding is unambiguous".

### 4.4 Tables are an array-throughput optimization, not a subsystem

This is the reversal the review forced (§17.3), and it matters.

In SmallFloats, tables are central because the scalar path is expensive: an
`Add` costs 6.8 ns minimum and 9.0 ns median, and a table gather costs 0.25
ns/element. With an integer kernel targeting 2–3 ns, the calculus changes:

| candidate | table size | verdict |
|:---|:---|:---|
| unary, any `K` | ≤ 256 B | **always** — L1-resident, vectorizes via byte shuffle |
| binary, `K ≤ 5` | ≤ 1 KiB | **yes** — L1-resident |
| binary, `K ∈ 6:8` | 4–64 KiB | **benchmark decides** — L2 gather vs a 2 ns kernel |
| ternary, any `K` | 512 B – 16 MiB | **no** — the kernel is faster than the build amortizes |
| stochastic ρ | — | **forbidden** (invariant) |

The ternary row is the concrete win. SmallFloats runs `FMA` at `K = 8` through a
scalar loop at 3.17 ns/element **with 42 allocations**, and tables `K ≤ 6`
eagerly at 16 MiB of build cost to escape it. FloatBytes' `FMA` kernel is an
exact 16-bit multiply plus a window add — call it 3 ns/element with *zero*
allocations and *zero* build — which removes both the table tier machinery and
the adaptive-cache policy that decides between tiers.

The policy simplifies from "table everything the byte budget allows, adaptively"
to "table what fits L1, compute everything else". One sentence instead of a
subsystem, and it is decided by measurement, not by a byte budget.

### 4.5 The session default is a `ScopedValue`, not a guarded `Ref`

SmallFloats' `src/defaults.jl` is 232 lines implementing a speculation guard: read
a `Ref` once, `===`-test it against the shipped initial value, compile against a
constant on hit, cross an `@noinline` barrier on miss. It is careful, correct,
and documented down to which branch boxes and why. It exists because a mutable
global default must not cost a dynamic dispatch on the convenience form.

`ScopedValue` (Julia 1.11+) is the idiomatic replacement:

```julia
with_projection(ProjSpec(StochasticA{8}(), SatFinite())) do
    y = x1 + x2          # follows the scoped ρ
end
```

It is task-local, so it is correct under threading — which the `Ref` is not, and
SmallFloats says so ("set defaults from one task, not concurrently"). It costs a
few nanoseconds per read that the guard's fast path does not.

The trade is deliberate and the honest framing is: **the convenience form is for
scripts, the explicit form is for kernels.** `Add(F, ρ, x, y)` is fully static
and always was; nothing hot needs to read a default at all. Paying a handful of
nanoseconds on `x + y` to delete 232 lines of world-age and inference subtlety —
and to gain task-locality — is the right side of that trade. A benchmark gate
pins the cost so the claim stays true.

### 4.6 Arrays are byte arrays, and the kernels are written for that

`Vector{Binary{K,P,S,E}}` reinterprets to `Vector{UInt8}` with no copy. Design
consequences taken from the start rather than retrofitted:

- Bulk kernels operate on the reinterpreted `UInt8` view.
- The unary table path is a 256-byte lookup — the shape a SIMD byte shuffle
  wants. On `K ≤ 4` the entire table is 16 bytes and lives in one vector
  register.
- The default-ρ same-format binary kernel is written **branch-free** where the
  rounding mode allows it, so it vectorizes rather than relying on a gather.
- `PackedVector` for `K ∈ 3:7` is designed alongside, not bolted on, and is
  honest about when it wins: memory-bound workloads only, since SmallFloats
  measures pack at 0.53 ns/element and unpack at 0.44 ns/element against a
  0.13 ns/element unary table gather.

### 4.7 Block reductions accumulate exactly, without a superaccumulator

Block formats reduce many products at once, so §2's two-term lemma does not
apply — many small terms can collectively matter.

The first design used a 640-bit fixed-point superaccumulator
(`NTuple{10,UInt64}`) covering the full 506-binade product spread. The review
rejected it (§17.2): it is exact but pays worst-case cost on every block, and
`NTuple` accumulators are precisely where SmallFloats measured a **tuple-length
allocation cliff** — `BlockAdd` at `B = 32` allocates 3200 B, at `B = 64`
allocates 6128 B, on code where `ntuple(Val(B))` is no better and the fix is a
representation change.

The adopted design is **max-exponent window with bounded restart**:

1. One pass to find the maximum product exponent.
2. One pass accumulating into a 64-bit window anchored there; terms below the
   window contribute only a tail sign.
3. If the accumulated window cancels down into the tail — the only case where
   step 2 is insufficient — re-anchor at the new magnitude and repeat.

Each restart drops at least 63 binades, so the loop is bounded at **9 iterations**
across the full 506-binade spread, and in practice terminates on the first pass
for anything but constructed cancellation. Blocks are represented as views into
a byte array rather than as long tuples, so the cliff has nothing to stand on.

The superaccumulator survives as the **test reference** — obviously correct,
unconditionally exact, and too slow to ship. That is the right home for it.

### 4.8 The differential target is separate, and external

This is a methodological point, and it is the one most worth stating loudly.

In SmallFloats, `src/oracle.jl` computes the defined result *and* is what the
tests compare against. Its gates (G1–G7) are careful compensations, but the
shape of the risk remains: a test suite comparing an implementation to itself
detects inconsistency, not error.

FloatBytes gets two independent references, and **no code is copied from
SmallFloats into FloatBytes** — copying would reintroduce the circularity
through the back door:

1. **`test/reference.jl`** — a deliberately naive implementation over
   `Rational{BigInt}` and `BigFloat`. Perhaps 250 lines, obviously correct,
   far too slow to ship, sharing nothing with `src/`.
2. **SmallFloats itself**, as a test-only dependency. It is an independently
   developed, heavily gated implementation of the same draft, and the entire
   `K ≤ 8` lattice is enumerable against it.

Reference 2 is an unusually strong asset and should be exploited before it
decays: two independent implementations agreeing on 13 296 code points, 2.5
million same-format pairs and 177 million cross-format pairs is evidence of a
kind that is rarely available.

---

## 5. Module layout and load order

`unpacked.jl` inherits the role `src/dyadic.jl` holds today — first, with zero
package dependencies, checkable on its own terms.

```
unpacked.jl   Datum, Aligned, the window primitives         (no dependencies)
formats.jl    the type, parameters, traits, aliases, naming
show.jl       display styles                                (early, for error paths)
projspec.jl   rounding and saturation modes
round.jl      round_to_precision on Aligned — ONE family
encode.jl     saturate, encode, decode, order keys
project.jl    round -> saturate -> encode
registry.jl   OP_REGISTRY and the generated surface
kernels.jl    the exact integer operation kernels
transcend.jl  MPFR-backed cold table construction           (the only MPFR site)
tables.jl     the L1-scoped table cache
arrays.jl     vmap, broadcast, SIMD-shaped bulk kernels
packed.jl     sub-byte storage
blocks.jl     block and scaled formats, windowed reduction
policy.jl     ScopedValue defaults
approx.jl     the kappa registry
rand.jl
```

Fourteen files against SmallFloats' seventeen, but the comparison that matters
is the count of *concepts*: no carrier lattice, no rung selection, no enclosure
protocol, no dyadic arithmetic, no vendored quad-precision kernels, one
`round_to_precision` instead of three.

As in SmallFloats, the load order is stated in exactly one place — the comment
at the top of the module file — and changing the order means changing that
comment in the same commit.

---

## 6. Verification architecture

### 6.1 Tiers

| tier | scope | budget |
|:---|:---|:---|
| `quick` | all code points, all formats; same-format binary at the default ρ | ~1 min |
| `default` | + all rounding modes; same-format ternary sampled by shape | ~6 min |
| `release` | + the full 177 M cross-format binary lattice; full ternary | ~45 min |

A tier the caller asks for is **honoured, never downgraded** — SmallFloats' rule,
and it is right.

### 6.2 Gates

The gate list shrinks because most of SmallFloats' gates police machinery this
package does not have.

| SmallFloats gate | fate in FloatBytes |
|:---|:---|
| G1 `_DE_*` exactness-by-width thresholds | **gone** — no `Float128` exactness analysis |
| G2 `bigprec` sufficiency | **gone** — no MPFR on a defined path |
| G3 `_rtp_f64` bit ≡ generic | **gone** — one rounding family, nothing to agree with |
| G4 rung-selection equivalence | **gone** — no rungs |
| G5 golden non-regression | **replaced** by the SmallFloats differential (§4.8) |
| G6 carrier-lift exactness | **gone** — no carriers |
| G7 `HeadExact` carrier swap | **gone** |
| G8 representation invariant | kept as constructor assertions plus round-trip |
| G9 trait folding | **kept** — traits must still constant-fold |
| G10 surface totality at every rung | **kept, and widened** |

Six of ten gates exist for machinery this design does not contain. Three new
ones replace them:

- **W1 — the window lemma.** §2's enumeration, as a test. Add exhaustively over
  all 120 formats; FMA exhaustively at `K ≤ 6` and over the widest-spread
  `K ∈ {7,8}` formats.
- **W2 — the block restart bound.** The reduction terminates within 9 restarts on
  every input, and agrees with the superaccumulator reference on constructed
  cancellation cases.
- **W3 — no allocation anywhere on a defined path.** SmallFloats can only pin
  this per operation class, because its enclosure ladder allocates at rungs 2
  and 3 by construction and its arithmetic allocates whenever the operand spread
  escalates to MPFR. FloatBytes can pin it **unconditionally**, which is a much
  stronger and much simpler regression.

**G10 is kept and widened, and the reason is worth restating.** It is the one
gate that is broad rather than deep — it asserts only that every registry
operation on every surface returns and holds its declared result type. Six Stage
7 defects in SmallFloats lived in exactly that blind spot and survived a green
suite. A shallow gate earns its place by being total; do not deepen it, do not
narrow it.

### 6.3 The circularity check

One standing rule, enforced by a test that greps: **nothing under `src/` may be
referenced by `test/reference.jl`.** The naive reference is only a reference if
it shares no code with the thing it checks.

---

## 7. Performance: baselines and targets

Baselines are SmallFloats' checked-in benchmark report at `Binary8p4se` under
`(NearestTiesToEven, SatNone)` — a fair comparison, since that is a `K = 8`
format on rung 1, the best case for the existing architecture.

| operation | SmallFloats (min / median) | FloatBytes target | basis |
|:---|:---|:---|:---|
| `decode` | 1.4 ns / 1.4 ns | ≤ 1.4 ns | unchanged — a table load |
| `project` (RNE·SatNone) | 1.6 ns / 6.7 ns | ≤ 2 ns / ≤ 2.5 ns | one integer family, no carrier split |
| `Multiply` | 5.1 ns / 7.5 ns | ≤ 2.5 ns | one 16-bit multiply |
| `Add` | 6.8 ns / 9.0 ns | ≤ 3 ns | window alignment, no escalation |
| `Divide` | 6.7 ns / 18.7 ns | ≤ 4 ns | one 64-bit divide; reciprocal table optional |
| `Sqrt` | 4.9 ns / 18.7 ns | ≤ 4 ns | one `isqrt` |
| `FMA` | 7.5 ns / 9.6 ns | ≤ 3.5 ns | exact product, then window |
| `Hypot` | 7.7 ns / 28.0 ns | ≤ 6 ns | now algebraic, not enclosure-bracketed |
| unary transcendental | 5–7 ns / 20–33 ns | ≤ 1.5 ns | 256-byte table, always |
| `vmap` unary | 0.13 ns/elem | ≤ 0.13 ns/elem | already table-gather bound |
| `vmap` binary | 0.25 ns/elem | ≤ 0.25 ns/elem | table at `K ≤ 5`, kernel above |
| `vmap` ternary | 3.17 ns/elem, **42 allocs** | ≤ 3 ns/elem, **0 allocs** | kernel, no table tier |
| `BlockDotProduct` (B=32) | 320 ns, **3 allocs** | ≤ 250 ns, **0 allocs** | windowed reduction |
| `ConvertToBlockMaxAbsFinite` (B=32) | 3.75 µs, **111 allocs** | ≤ 1 µs, **0 allocs** | no tuple cliff |

The medians are where the story is. SmallFloats' minima are already good; its
medians are two to five times higher because the median operand pair triggers
escalation — the enclosure path, the MPFR tail, the sticky-band analysis. An
integer kernel has no such distribution. **The target is not primarily a lower
minimum; it is a median that equals the minimum.**

### 7.1 Benchmark doctrine, adopted whole

Recorded after four measurement post-mortems in SmallFloats. Adopt all of it,
because every rule was paid for:

- A closure over any non-`const` global measures Julia's dispatch machinery, and
  it distorts *ratios*, not just absolutes.
- **One variant per process, alternating, or nothing.** A harness compiling
  several variants in one process reported a rewrite as a 1.87× win that
  alternating single-variant processes reversed into a 31% loss.
- **A loop that overwrites its accumulator measures dead-code elimination.**
  Reduce into an accumulator and end with `Base.donotdelete`.
- Warm up until the number stops moving; seed the data.
- Machine drift between blocks reached ~10%; A/B comparisons run from a git
  worktree pinned at the base commit, in immediate alternation.
- A preflight aborts the run if a warm scalar path allocates.

The worktree harness from SmallFloats' tranche-1 work is directly reusable and
should be ported before the first optimization, not after the first disputed
number.

---

## 8. Public API

### 8.1 Names

Draft naming is canonical: `Binary8p4se`, `Binary5p2uf`, and
`format(K, P, Σ, Δ)` returning the concrete type. All 120 names are defined; all
120 are exported, since 120 is a manageable namespace and the `K ≤ 8` restriction
removes the reason SmallFloats exports only a subset of its 504.

### 8.2 The OCP FP8 question, answered rather than assumed

The obvious ergonomic idea is to alias `E4M3` and `E5M2` — the OCP FP8 formats
the ML community actually uses. **Measured, and the answer is no.**

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
and *nothing else*: their finite datum sets have 255 and 248 members
respectively and are not equal — checked element by element.

**No P3109 8-bit format is bit-identical to either OCP FP8 format.** So:

- Ship **no** `E4M3`/`E5M2` aliases. An alias that is 99% right is worse than no
  alias, because it will be believed.
- Ship a documented comparison table, with the bias-convention difference stated
  as the cause.
- If OCP formats are wanted, add them as *first-class separate formats* under
  their own names, clearly marked non-P3109, sharing the kernels but not the
  format lattice. This is cheap — the kernels are parameterized on `(P, B)` and
  the special-value layout — and it is the honest way to serve the use case.

This is a genuine finding rather than a design preference, and it is the kind of
thing that is much cheaper to learn during planning than after release.

### 8.3 Surface

```julia
Add(F, ρ, x, y)              # spec form: explicit format and projection, fully static
x + y                        # convenience: same format, scoped ρ
with_projection(ρ) do ... end
Convert(F, ρ, x)             # the one operation accepting external operands
conformance()                # the live declaration
```

---

## 9. Staging, with exit gates

Each stage exits on a gate, not on a judgement.

| stage | content | exit gate |
|:---|:---|:---|
| 0 | type, traits, encode/decode, show | all 13 296 code points round-trip; decode agrees with SmallFloats everywhere |
| 1 | `Datum`, `Aligned`, window, `round_to_precision`, `project` | **W1** (the lemma); `project` agrees with SmallFloats over 13 296 points × 9 ρ |
| 2 | algebraic kernels, registry, generated surface | same-format binary exhaustive vs SmallFloats, all ρ; **W3** (zero allocation) |
| 3 | transcendentals via cold MPFR tables | all 27 transcendental ops exhaustive vs SmallFloats over 13 296 points × 9 ρ |
| 4 | arrays, broadcast, SIMD, packed | throughput targets in §7; **W3** on bulk paths |
| 5 | blocks and scaled formats | **W2**; exact vs the superaccumulator reference; zero allocation at every `B` |
| 6 | κ registry, `rand`, conformance, docs | **G10** at full tier; the release verification tier green |

Stage 1 is the risk concentration. If the window lemma fails for some case the
enumeration in §2 did not reach, the whole thesis needs revisiting — so Stage 1
is deliberately small, and its gate is deliberately the most expensive relative
to the code it covers.

Stages 0–3 depend on SmallFloats being installed as a test dependency. That
dependency is **test-only and temporary**: once the exhaustive differentials have
run green and their digests are recorded as golden files, the runtime dependency
is a recorded digest, not a package.

---

## 10. Risks and open questions

| risk | severity | mitigation |
|:---|:---|:---|
| Window lemma fails on an unreached case | **high** — the thesis rests on it | Enumerated clean: Add over all 120 formats (2.46 M pairs), FMA over 109.8 M triples covering every `K ≤ 6` format and every widest-spread `K ∈ 7:8` case. Residual gap is `K ∈ 7:8` at `P ≥ 2`, all of which have narrower spread than what is covered. Close it as a Stage 2 entry condition. |
| A primitive type has no inner constructor, so an invalid `Binary{9,…}` is a nameable type | medium | Every trait errors on invalid parameters; `format()` is the blessed route; a gate enumerates invalid parameter tuples and asserts each throws. |
| `ScopedValue` read cost exceeds the estimate on the convenience form | low | Benchmark gate. If it does, the fallback is a `const` compile-time default via Preferences, with runtime setting removed rather than re-guarded. |
| Branch-free vectorized kernels prove impossible for some rounding modes | medium | Fall back to the table path for those modes at `K ≤ 5`; document which modes vectorize. This is a throughput question, never a correctness one. |
| Integer `Divide` at ~25 cycles dominates its target | low | 256-entry fixed-point reciprocal table; the operand significand is one byte. |
| Transcendental Ziv loops fail to terminate on a hard case | low | ≤ 256 inputs per table, so a hard case is *findable*: enumerate, and record the required precision per (op, format) as a constant. |
| SmallFloats differential decays as SmallFloats evolves | medium | Capture digests early; pin the SmallFloats version in the test manifest. |

Open questions that planning cannot settle and Stage 4 must measure:

1. Does a 64 KiB binary table beat a 2 ns integer kernel at `K ∈ 6:8`? The
   answer sets the table policy and nothing else depends on it.
2. Does `PackedVector` win on any workload that is not synthetically
   memory-bound?
3. Is threading worth having at all when the scalar kernel is 2 ns and the bulk
   kernel vectorizes? SmallFloats' threading wins were largely a missing function
   barrier in disguise — a lesson to apply, not repeat.

---

## 11. Non-goals

- **`K > 8`.** That is SmallFloats, and the split is deliberate. Neither package
  should grow toward the other; a `K = 16` format genuinely needs the carrier
  ladder, and this package's whole advantage is not having one.
- Implicit cross-format arithmetic. Promotion is explicit.
- In-place packed arithmetic.
- Subtyping `Binary` as an extension point. Package methods assume the code-point
  contract and the representation invariant, and an outside subtype cannot be
  held to either.
- Bit-compatibility with OCP FP8 under P3109 names (§8.2).
- Copying any code from SmallFloats into `src/` (§4.8).

---

## 12. What review changed

The first draft of this plan was wrong in five places. Recording them is not
ceremony — three of the five would have produced a worse package, and the
reasoning is the part worth keeping.

**12.1 ρ as a type parameter of the format.** The first draft wrote
`Binary{K,P,S,E,ρ}` so that `x + y` would be fully static with no default to
read. Rejected: two values of the same format with different ρ then need an
interoperation rule, and there is no good one — either ρ silently takes one
side, or arithmetic between them is an error, and both are worse than reading a
default. Replaced by §4.5's `ScopedValue`, which is where the cost actually
belongs: on the convenience form, which is not the hot path.

**12.2 A superaccumulator for block reductions.** The first draft specified an
`NTuple{10,UInt64}` fixed-point accumulator spanning the full 506-binade product
range. It is exact and it is simple, and it is also worst-case cost on every
block and exactly the shape that SmallFloats measured allocating 6128 B at
`B = 64`. Replaced by §4.7's windowed accumulation with bounded restart — after
first noticing that the *naive* window is wrong under cancellation, which is
what forced the restart rule. The superaccumulator kept its place as the test
reference, which is what it was always good at.

**12.3 Tables as a central subsystem.** The first draft carried SmallFloats'
table architecture across largely intact, including the adaptive cache and the
ternary bitwidth tiers. That is a correct design *for a package whose scalar path
costs 7 ns*. Once the integer kernel targets 2–3 ns, a 64 KiB L2 gather is no
longer obviously a win, and a 16 MiB ternary table build is obviously not. §4.4
demotes tables to an L1-scoped optimization decided by benchmark. This deletes
more code than any other single revision.

**12.4 The window lemma stated rather than tested.** The first draft asserted
that a `UInt64` window suffices, with an arithmetic argument and no evidence.
Given that the entire package rests on it, that was the wrong confidence level.
It was implemented against a `Rational{BigInt}` reference and enumerated —
2 459 235 datum pairs for Add and 109 800 088 operand triples for FMA — before
this document claimed it. The check is now a required gate (**W1**), not a
comment. The subtle case it surfaced, the negative tail from `w1 − w2` and its
normalization, was not in the original argument at all; nor was the fact that
that case is *safe* only because a dropped tail forces `w1 > w2` strictly. That
premise is now an `@assert` inside the check rather than a claim in prose.

**12.5 Dropping `BigFloat` entirely.** The first draft claimed zero MPFR. Wrong:
the 27 transcendental operations need correctly rounded reference values, and
there is nothing else to compute them with. The correct claim is narrower and
still strong — MPFR appears at exactly one site, builds ≤ 256-entry tables, and
is never reached from a scalar, array, or warm path. §4.3 says that instead.

**12.6 The OCP FP8 aliases.** Not an error so much as an assumption that did not
survive being checked. The first draft listed `E4M3`/`E5M2` aliases as a
usability win. Measuring the datum sets showed no P3109 8-bit format matches
either. §8.2 replaces the aliases with a comparison table and an offer to
implement the OCP formats honestly, under their own names.

---

## 13. Summary

`3 ≤ K ≤ 8` is not a smaller version of `3 ≤ K ≤ 16`. It is the range in which
every defined result of every operation is computable exactly in fixed-width
integer arithmetic, and in which the entire format lattice — cross-format
included — can be verified by enumeration rather than by argument.

A package built on that premise has no carrier lattice, no rung selection, no
enclosure protocol, no exact-arithmetic carrier, no vendored quad-precision
kernels, one rounding family instead of three, and no dependency outside `Base`.
Six of SmallFloats' ten gates exist to police machinery it does not contain. Its
median operation cost should equal its minimum, because there is no escalation
distribution to smear it. It should allocate zero bytes on every defined path
unconditionally, rather than per operation class with a documented list of
exceptions.

What it must not do is claim that lightness came free. It came from a
restriction, and the restriction is exactly the thing SmallFloats exists to lift.
