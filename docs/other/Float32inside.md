# Float32 as the internal carrier for `Binary` values — plan, design, review

*Current role (2026-08-01): rationale for the package's Float32 boundary. This
document supplied the decision; [Float32more.md](Float32more.md) records its
implementation. The measurements below are the K ≤ 8 evidence available when
the decision was made, not a description of the entire 504-format grid.*

> **Current implementation.** Float32 did not replace the universal evaluation
> carrier. `datumcarrier` now selects `Float64`, `Float128`, or the exact
> `Dyadic` carrier from the operand formats, while `promotecarrier` exposes only
> complete Julia float interfaces (`Float64`, `Float128`, or `BigFloat`). The
> useful parts of this study did ship: exact `Float32`/`BFloat16` conversion
> where the datum set permits it, bulk `decode!`, the `f32_exact` capability
> query, and opt-in kappa-measured kernels through `register_f32!`. See
> [`carriers.jl`](../../src/carriers.jl),
> [`kernels.jl`](../../src/kernels.jl),
> [`tables.jl`](../../src/tables.jl), and
> [`approx.jl`](../../src/approx.jl).

## 1. Question and verdict

At the time of this study SmallFloats.jl used `Float64` as its only internal
carrier. The question studied here was: **can `Float32` serve as that internal
type instead?** The extension later generalized the premise to a carrier ladder,
but did not change the answer.

**Verdict, up front:**

1. **As a universal replacement carrier: no.** `Float32` can exactly represent
   every *datum* of all 120 formats, but not the *intermediates* the ω-semantics
   require. Products and sums of wide-exponent K=8 formats leave Float32's
   exponent range entirely, directed and stochastic projection modes are
   corrupted by pre-rounding to 24 bits, and the entire escalation ladder
   (`Float64 → Float128 → BigFloat`, thresholds `_DE_ADD = 100`, `_DE_FMA = 92`,
   `_DE_FAA = 98`) is calibrated to a 53-bit head. A Float32 head would escalate
   at spreads around 15 instead of 44+ — strictly more slow-path traffic for zero
   hot-path gain.
2. **As a surface type: yes, and shipped.** Decode is Float32-exact throughout
   the original K ≤ 8 grid; the package now provides guarded scalar conversion,
   bulk materialization, and BFloat16 interop (§6, Milestone 1).
3. **As a compute type for special kernels (SIMD/GPU): yes, but only through the
   two mechanisms the architecture already provides** — an exactness-*gated*
   carrier for the (op, format, ρ) combinations where Float32 arithmetic is
   provably exact, and the **κ-approximation registry** for everything else
   (invariant 5: nothing approximate is reachable from the default API). §6,
   Milestones 2–3.

The rest of this document is the evidence.

## 2. Where Float64 lived before the carrier extension

"Internal type" is not one declaration; it is a contract threaded through the
layer stack (119 mentions across 12 of the 14 source files). The load-bearing
roles:

| role | site | what it assumes |
|---|---|---|
| Decode carrier | [`decode_encode.jl:5-52`](../../src/decode_encode.jl#L5-L52) | `_decode_compute` assembles Float64 bits directly (52-bit mantissa field, bias 1023); per-format constant tuples `_decode_table` are `NTuple{2^K, Float64}` |
| ω-semantics operand/result | [`oracle.jl`](../../src/oracle.jl) throughout | every `ωeval(::Val, xs::Float64...)` signature; exactness-by-width analysis (`_twosum`, `_expdiff`, `_span3`, the `_DE_*` thresholds) proves *Float64* residuals capture the truth |
| Fast-class result | [`ops_scalar.jl:130-141`](../../src/ops_scalar.jl#L130-L141) | `apply_op` splits on `res isa Float64` to keep the widened union off the hot path |
| Projection bit path | [`project.jl:84-131`](../../src/project.jl#L84-L131) | `_rtp_f64` mask-extracts guard/round/sticky from the 52-bit layout (`t ∈ [45, 52]` depends on P ≤ 8 *and* on 52) |
| Saturation comparison | [`project.jl:237-255`](../../src/project.jl#L237-L255) | `_cmp_rounded_datum(…, m::Float64)` — extremal datum passed as exact Float64 |
| Enclosure pre-filter | [`ops_scalar.jl:64-88`](../../src/ops_scalar.jl#L64-L88) | `EncloseF.yd::Float64` with envelope `2^-45`, sound because Float64 libm is faithful to ≤ 1 ulp ≈ `2^-52` |
| Table builders | [`tables.jl:83-169`](../../src/tables.jl#L83-L169) | `_scalar_code(…, xs::Float64...)`; cold path only |
| Block scaling | [`blocks.jl:44-47`](../../src/blocks.jl#L44-L47) | ωBlockDecode = per-lane `ωMultiply(decode(s), decode(xᵢ))`, *exact Float64* |
| Promotion & surface | [`formats.jl:208-215`](../../src/formats.jl#L208-L215) | `Binary ⋄ Float64/32/16/Integer → Float64`; `Float64(v) = decode(v)`; `Float32(v)` exact narrowing |
| `rand`/`randn` semantics | [`rand.jl`](../../src/rand.jl) | the *defined distribution* is "draw a 53-bit `Float64` uniform, floor-project" — the carrier width is part of the observable spec |

Two structural observations before any feasibility math:

- **The hot array paths never touch the carrier.** Shape A kernels
  ([`kernels.jl:24-50`](../../src/kernels.jl#L24-L50)) are pure `UInt8` table
  gathers; the carrier appears only at table-*build* time (cold, oracle-backed).
  The scalar warm path (~26 ns specialized `Add`) is dominated by projection
  logic, not by 64-vs-32-bit ALU width. **A Float32 carrier buys ~nothing on
  the original CPU paths.** The real motivations are elsewhere: GPU (no fast
  Float64), SIMD width in a hypothetical vectorized Shape-B kernel, and interop
  with Float32/BFloat16 ML tensors.
- **Correctness is not carried by Float64 alone but by the oracle result
  protocol built around it** (`Float64 / Float128 / BigExactF / Enclose128F /
  EncloseF` + `sticky`). Any carrier change is a change to that protocol's
  base case, and every width-analysis comment in `oracle.jl` is a proof
  obligation that must be re-discharged.

## 3. What Float32 can represent exactly

### 3.1 Datums: yes, all of them

Worst cases over all 120 formats (bias `B = 2^(K−P−1)` signed, `2^(K−P)`
unsigned; extremes at `Binary8p1u`):

- Largest finite datum: `2^126` (`Binary8p1uf`, code 254). Float32 max is
  `(2 − 2^−23)·2^127 ≈ 2^128` — fits, exactly.
- Smallest positive datum: `2^−127` (`Binary8p1u*`, code 1). Below Float32's
  normal floor `2^−126`, but a 1-bit significand at `2^−127` is an exact Float32
  *subnormal* (subnormal quantum `2^−149`).
- Significands: ≤ 8 bits ≤ 24. No format puts a wide significand at a deep
  exponent (`value scale ≈ 2^(2−B)` when `Q` is minimal), so the subnormal
  region never truncates.

Hence ωDecode is Float32-exact for every K ≤ 8 format — which the current
`datumsexact` gate and suite preserve. (Incidentally the same argument shows
**BFloat16 is also an exact
datum carrier**: 8-bit precision ≥ every P, exponent range identical to
Float32, subnormals reach `2^−133 < 2^−127`. Relevant to the new `BFloat16s`
dependency; see §7.)

**Hardware caveat:** flush-to-zero (default on most GPU Float32 pipelines)
destroys the `2^−127` datums of `Binary8p1u`. Any GPU design must either
disable FTZ or pre-scale that format.

### 3.2 Intermediates: no

The ω-semantics evaluate on decoded operands. Against a 24-bit significand and
exponent range `[−149, 127]`:

- **Multiply.** Significand width `P1 + P2 ≤ 16` always fits. The exponent
  does not: `Binary8p1u` products span `[2^−254, 2^252]` — both ends are
  outside Float32 entirely (overflow to `Inf32`, underflow to `0.0f0`). In
  Float64 the same products are exact. Signed formats stay inside (worst
  `[2^−126, 2^124]`), so this failure is confined to `Binary8p1u` and near
  relatives — but "confined" still means the universal-carrier claim is false,
  and the failure mode is *silent wrong answers*: an overflowed `Inf32` under
  `SatNone`+`TowardZero` projects to `Inf`/NaN territory where the true finite
  value must project to `MaxFinite`; an underflowed `0.0f0` under
  `TowardPositive` projects to `0` where the truth is `MinPositive`. Both
  violate defined results, not accuracy.
- **Add/Subtract.** An exact sum needs `(exponent spread) + P` significand
  bits. Float64's 53 bits cover every same-format add until spread > 44 (the
  escalation comment at [`oracle.jl:36`](../../src/oracle.jl#L36)); Float32's 24
  bits fail as soon as spread + P > 24 — e.g. `Binary8p3s` spans ~30 binades
  alone. The existing ladder escalates `Float64 → Float128` at `ΔE > 100`
  precisely because heads and tails are sized to 53/113 bits; a 24-bit head
  inverts the economics: most of the K=7–8 add space would escalate, i.e. the
  "fast" carrier forces the slow path.
- **FMA/FAA.** Same analysis compounded: the sticky-head soundness argument
  (`StickyF` note, [`ops_scalar.jl:30-43`](../../src/ops_scalar.jl#L30-L43))
  quantifies "operand significands ≤ 17 bits" against 113-bit targets; a
  Float32 stage contributes nothing here.
- **Transcendentals.** The `yd` eager stage is sound because Float64 libm is
  faithful (≤ 1 ulp = `2^−52` relative) under a `2^−45` envelope. A Float32
  `yd` (faithful to `2^−23`) with a `2^−17`-ish envelope would still resolve
  most projections at P ≤ 8 — but it replaces a cheap stage with an equally
  cheap, weaker one. No win on CPU.
- **Block scaling.** ωBlockDecode multiplies scale × datum exactly in Float64;
  scaled products widen the exponent range further, so Float32 fails here
  before it fails on plain Multiply.

### 3.3 Rounding-mode interactions

Suppose intermediates *were* computed in Float32 (correctly rounded IEEE ops),
then projected:

- **Round-to-nearest projections:** innocuous-double-rounding applies when the
  intermediate precision `p` satisfies `p ≥ 2q + 2` for target precision `q`
  (Figueroa's bound). With `q = P ≤ 8`, `24 ≥ 18` holds — RN∘RN is safe *for
  the exactly-rounded arithmetic ops, away from Float32 over/underflow*. This
  is the kernel of truth that makes a gated Float32 path possible.
- **Directed projections after an RN32 compute: wrong.** A true value in
  `(g − ulp32/2, g)` for a grid point `g` rounds *up* to `g` in Float32; a
  `TowardNegative` projection then lands on `g` instead of the grid point
  below. Either the Float32 op must run in the matching directed hardware mode
  (per-ρ mode switching) or directed ρ must be excluded from the Float32 path.
- **Stochastic projections: never.** All three stochastic families consume the
  exact fraction ν to place the draw on the `2^N` sub-grid; pre-rounding ν to
  24 bits biases the distribution. This is invariant-4-adjacent: the result is
  a distribution, and the carrier is part of its definition. Stochastic ρ must
  be excluded from any Float32 compute path (as it is from tables today).
- **`rand`/`randn`:** the 53-bit uniform draw is part of the defined
  distribution. A Float32 internal `rand` is a *semantic* change, not an
  optimization; out of scope for any carrier work.

### 3.4 Engine mechanics

`_rtp_f64` would need an `_rtp_f32` twin (mask layout 23/8 instead of 52/11;
the `d ≤ P − 1 ≤ 7` argument gives `t = 23 − d ∈ [16, 23]`, so the ν fixed-point
construction transfers). Mechanically straightforward — but the repo's
discipline (the twin-family comment at
[`project.jl:62-66`](../../src/project.jl#L62-L66)) requires an exhaustive
bit ≡ generic equivalence gate for every new carrier, and `_cmp_rounded_datum`,
`saturate`, and the `sticky` plumbing all gain a third instantiation to keep in
sync. That is real, permanent maintenance surface purchased for a path with no
CPU payoff.

## 4. Options

**A. Float32 outside, Float64 inside** *(recommended baseline).* Keep the
carrier untouched; finish the Float32 *surface*: bulk exact materialization
(`Float32.(A)` via a `NTuple{2^K, Float32}` decode-table gather, mirroring
Shape A), and exact `Convert` ingestion from Float32 arrays (scalar form already
exists and widens exactly). Zero risk; addresses the interop motivation, which
is the only motivation with observable benefit today.

**B. Exactness-gated carrier parameterization.** Introduce a carrier type
parameter at the `apply_op`/table-build boundary with a trait
`f32_exact(op, fr, f1[, f2, f3], ρ)` derived from the §3 bounds (exponent-range
containment + width fit + non-stochastic, non-directed-after-RN ρ). Where the
trait holds, the Float32 result is *exact* (κ = 0), all projection modes remain
correct, and the path is admissible from the default API. Where it doesn't,
fall back to the Float64 engine. Honest assessment: on CPU this is complexity
with no measurable win (hot paths are gathers); its value is as the correctness
foundation for option C. Build it only when C is wanted.

**C. κ-registry Float32 kernels.** For SIMD/GPU throughput where exactness
gating fails (or directed modes are wanted without hardware mode switching),
implement decode32 → Float32 op → project as **named approximate kernels in the
κ registry** — the mechanism invariant 5 provides for exactly this. κ is
measured exhaustively at `register_approx!` time, so the Float32 kernel's error
is a *verified property*; many (op, format, RN) combinations will measure
κ = 0 by the §3.3 double-rounding bound, and the registry proves it rather than
assuming it. Conformance claims are unaffected because the default API never
routes here.

**D. Wholesale swap of the internal carrier to Float32.** Rejected. Breaks
defined results (§3.2 over/underflow), breaks stochastic and directed modes
(§3.3), inverts the escalation economics, invalidates every width-analysis
proof in `oracle.jl`, and changes observable `rand` semantics — for no
performance benefit on any existing hot path.

## 5. Review against the invariants

| invariant | verdict under A / B / C |
|---|---|
| 1. One write path | Preserved — all three route results through `project`; C's kernels must call the engine (or a table built by it) for the final encode, never hand-pack codes |
| 2. Code point vs value | Untouched — `Float32` is a `Real`, hence value semantics; `UInt8` remains the sole code-point type |
| 3. Low-K representation | Untouched |
| 4. Stochastic never tabulable | Extended, not weakened: stochastic ρ must also be rejected by any Float32 compute path (§3.3); make the gate loud, like the table builders |
| 5. Nothing approximate from default API | The load-bearing one. C lives *only* in the κ registry; B is admissible by default only where the exactness trait is a proven property (and the proof belongs in the suite, enumerated) |
| 6. Table entry IS the defined result | Preserved — table builds stay on the Float64/oracle path regardless of option; never build tables through a Float32 compute path |
| 7. Registry-driven codegen | Any new kernel family must be generated from `OP_REGISTRY` rows, not hand-written per op; a Float32 kernel surface adds a registry-driven dimension, not 50 hand methods |

Performance rules: options keep format types flowing through type parameters;
the specialization preflight and zero-allocation gates apply to any new public
entry unchanged. Testing doctrine: every claim above is enumerable — 120
formats, ≤ 2^16 binary input pairs — so the exactness trait, the κ = 0 double
rounding claim, and decode32 exactness are all *exhaustive* differential tests
against the Float64 path, per the enumerate-don't-sample rule. (None were run
for this study, per instruction.)

## 6. Directions

**Milestone 1 — Float32 surface (small, safe, do first).**
- `_decode_table32(T)::NTuple{2^K, Float32}` generated from `_decode_compute`
  (one truth, narrowed once, exactness asserted exhaustively).
- Array materialization `Float32.(A)` / `convert(AbstractArray{Float32}, A)`
  as a Shape-A-style gather; same for ingestion `Convert(fr, ρ, A::AbstractArray{Float32})`.
- Documentation: state plainly that `Float32` round-trips all formats exactly.

**Milestone 2 — exactness trait (only if M3 is wanted).**
- `f32_exact(...)` predicate from the §3 bounds; exhaustive verification test.
- `_rtp_f32` twin + bit ≡ generic gate, if a Float32-carrier projection is
  actually needed (it is not needed for M1, and M3 can project via Float64).

**Milestone 3 — κ-registered Float32 kernels (GPU/SIMD ambition).**
- Registry-generated `decode32 → op32 → project` kernels registered via
  `register_approx!`; κ measured exhaustively, expected κ = 0 for RN-mode
  arithmetic ops on gated formats, κ > 0 measured honestly elsewhere.
- FTZ hazard for `Binary8p1u` documented at the kernel and tested on the
  target hardware, not assumed.

**Non-goals:** changing `decode`'s return type, the `ωeval` operand type, the
promotion rules (`Binary ⋄ Float32 → Float64` stays — it is what makes mixed
arithmetic exact), or `rand`'s draw width.

## 7. Note on BFloat16s.jl

`BFloat16s` was added to the project dependencies during this study. The §3.1
analysis extends to it: BFloat16 (8-bit precision, Float32 exponent range,
subnormals to `2^−133`) is an **exact datum carrier** for all 120 formats, so
`BFloat16(v::Binary)` and its array gather can be provided exactly, mirroring
Milestone 1 — and ingestion `Convert(fr, ρ, x::BFloat16)` is exact widening
through Float32/Float64. BFloat16 is *not* a candidate compute carrier (8-bit
precision cannot even hold a `P1 + P2`-bit product), so its role ends at the
surface, where it is genuinely useful for ML-tensor interop.
