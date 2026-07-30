# Float32 inside — detailed implementation of the recommended paths

*Status update 2026-07-24: **M1–M3 are implemented** — `_decode_table32` +
`Float32`/`BFloat16` scalar surface + `decode!` + array `Convert` (M1),
`f32_exact` in `tables.jl` (M2), `_f32_base`/`f32_impl`/`register_f32!` in
`approx.jl` (M3), with `test/float32surface.jl` included from the suite and
JET `@test_call` lines in `quality.jl`. The new test file passes standalone
(30/30); the full suite was deliberately not run in that session.*

*Companion to [Float32inside.md](Float32inside.md), which established the
verdict: keep Float64 as the universal internal carrier; add a Float32/BFloat16
surface (M1), an exactness-gated Float32 compute capability (M2), and
κ-registered Float32 kernels (M3). This document turns each milestone into a
concrete, file-by-file implementation — and, unlike the first document, its
claims are **empirically validated by exhaustive enumeration** run against the
package on 2026-07-24. Every κ and every gate count below is a measured value,
not a prediction. The harness is reproduced in Appendix A; no changes were made
to `src/` or `test/`.*

## 0. Validation summary (read this first)

| claim | method | result |
|---|---|---|
| ωDecode is Float32-exact, all formats | enumerate all codes × 120 formats | **PASS**, 120/120 |
| ωDecode is BFloat16-exact, all formats | same, via `BFloat16s.BFloat16` | **PASS**, 120/120 |
| Multiply is Float32-carrier-exact | all finite same-format pairs, 120 formats | **118/120** — fails only `Binary8p1ue`, `Binary8p1uf` (witness: `2^-127 · 2^-127` underflows to `0.0f0`; exact `2^-254`) |
| Add is Float32-carrier-exact | same | **88/120** (list in §3.2; worst inexact fraction `Binary8p1uf` = 0.183) |
| decode32→op32→project kernels, RNE: κ = 0 | `measure_kappa`, exhaustive | full sweeps, all 120 formats × 5 ops (§4.4): `RNE_SN` **600/600**, `RNE_SF` **600/600**, `RNE_SP` 598/600 — the two exceptions (`8p1ue` Multiply/Divide, Float32 overflow vs SatPropagate's Inf/finite distinction) re-measure **κ = 0** with the §4.2 overflow guard |
| Directed modes after RN32 compute break | `measure_kappa` | confirmed: Add `8p3se` RTZ κ = 1; Add `8p3se` **RTP κ = NaN** (witness: `7.6e-6 + 49152.0` — defined `+Inf`, kernel `49152.0`); Multiply `8p1ue` RTZ κ = NaN |
| IEEE ≠ P3109 specials must be guarded | `measure_kappa` + witness hunt | confirmed: unguarded Divide κ = NaN on *every* tested format — witness `x/0.0`: P3109 (one unsigned zero) defines NaN, IEEE gives Inf. With the guard: κ = 0 everywhere tested, including RTZ `8p3se` |
| κ machinery enforces invariant 5 | `register_approx!` round-trip | confirmed: f32 Multiply kernel registered with measured κ = 0 (exhaustive); understated `κ=0` declaration against true κ = 1 **rejected**; stochastic ρ **rejected** by `measure_kappa` |

Three of these were surprises worth internalizing:

1. **RNE κ = 0 holds far beyond the analytic gate.** Multiply on `Binary8p1u*`
   is *not* carrier-exact (over/underflow), yet the full kernel measures κ = 0
   under `RNE_SN` and `RNE_SF`: an overflowed `Inf32` and the true
   huge-finite value happen to project identically under those ρ, and an
   underflowed `0.0f0` and the true tiny value both round to zero under RNE.
   This is a coincidence of ρ semantics, **not** transferable — the same format
   under `RTZ_SN` measures κ = NaN. Consequence: κ must be measured per
   (op, formats, ρ) specialization, never generalized from a neighbor. The
   registry already enforces exactly this.
2. **Directed-mode failure is a saturation-boundary failure.** The RTP witness
   is not a mid-grid rounding slip: `49152 = MaxFinite(Binary8p3se)`, the exact
   sum is `49152.000007…`, defined RTP result is `+Inf`, but RN32 collapses the
   sum onto `49152.0` before projection ever sees it. κ = NaN (an
   Inf/finite class mismatch), not κ = 1 — worse than naive analysis suggests.
3. **The dangerous divergences are semantic, not numeric.** Every unguarded
   Divide measured κ = NaN for the same reason (`x/0`), and Julia's
   `sqrt(::Float32)` *throws* on negative arguments where the draft defines
   NaN. A Float32 kernel is IEEE-semantics code feeding P3109-semantics
   projection; the bridge needs explicit special-case guards (§4.2).

---

## 1. Plan

Dependency order M1 → M2 → M3; each independently shippable.

- **M1 — surface (do now):** exact Float32/BFloat16 decode surface + bulk
  materialization + array ingestion. Pure additions to existing layers; no new
  layer, no carrier change, no semantics change.
- **M2 — carrier-exactness trait (with M3, or when a stochastic-SIMD kernel is
  wanted):** memoized, enumeration-backed `f32_exact(op, fr, args…)`. Where it
  holds, Float32 compute is *exact*, hence legal under **every** ρ including
  stochastic and directed, and admissible from the default API.
- **M3 — κ-registered Float32 kernels (GPU/SIMD ambition):** registry-generated
  `decode32 → op32(guarded) → project` kernels registered through
  `register_approx!`, κ measured exhaustively per specialization. RNE-family
  only by policy (validated above); never reachable from the default API.

---

## 2. Milestone 1 — the Float32/BFloat16 surface

### 2.1 `decode_encode.jl` — the narrowed decode table

Add beside `_decode_table` (one truth: generated from the same
`_decode_compute`, narrowed once; exactness is a proven property — V1/V2):

```julia
# Float32 twin of _decode_table: same ground truth, narrowed once. Narrowing is
# exact for every K ≤ 8 datum (asserted exhaustively in the suite; see also the
# note at Base.Float32 in formats.jl).
@generated function _decode_table32(::Type{Binary{K,P,S,E}}) where {K,P,S,E}
    t = ntuple(i -> Float32(_decode_compute(rawvalue(Binary{K,P,S,E}, UInt8(i - 1)))), 1 << K)
    :($t)
end
```

### 2.2 `formats.jl` — scalar surface

Replace line 215 (`Base.Float32(v) = Float32(decode(v))`) with the direct
gather, and add BFloat16 (the dependency is already in Project.toml):

```julia
Base.Float32(v::Binary{K,P,SGN,EXT}) where {K,P,SGN,EXT} =
    @inbounds _decode_table32(Binary{K,P,SGN,EXT})[Int(codepoint(v)) + 1]   # exact
Base.BFloat16(v::Binary) = BFloat16(decode(v))   # exact: ≤8-bit significands, exp ⊂ BF16 range
Base.promote_rule(::Type{<:Binary}, ::Type{BFloat16}) = Float64   # same policy as Float32/16
```

and in `src/SmallFloats.jl` add `using BFloat16s: BFloat16` next to the other
deps (keeps Aqua's stale-deps check green now that the dependency exists).
Ingestion needs **no** new `Convert` method: `BFloat16 <: AbstractFloat`, so the
existing fallback `Convert(fr, ρ, x::AbstractFloat) = Convert(fr, ρ, Float64(x))`
at [`ops_scalar.jl:263`](../../src/ops_scalar.jl#L263) already widens it exactly.

Semantics note: after `Base.Float32` becomes a table gather it is bit-identical
to the old definition (V1 is exactly that assertion), so this is a pure
strength-reduction; broadcast `Float32.(A)` then compiles to a constant-tuple
gather per element with no Float64 intermediate.

### 2.3 `kernels.jl` — bulk materialization and ingestion

```julia
"""
    decode!(dest::AbstractArray{Float32}, A::AbstractArray{<:Binary}) -> dest
    decode!(dest::AbstractArray{Float64}, A::AbstractArray{<:Binary}) -> dest

Exact bulk ωDecode: a Shape-A gather into an external float array."""
function decode!(dest::AbstractArray{Float32}, A::AbstractArray{F}) where {F<:Binary}
    axes(dest) == axes(A) || throw(DimensionMismatch("dest and A must share axes"))
    tbl = _decode_table32(F)
    @inbounds for i in eachindex(dest, A)
        dest[i] = tbl[Int(codepoint(A[i])) + 1]
    end
    dest
end
# Float64 twin gathers _decode_table(F); identical shape.

"""
    Convert(fr, ρ, A::AbstractArray{<:Union{Float16,Float32,Float64}}; rng) -> Array{fr}

Bulk ingestion: exact widening per element, then projection under ρ. Unlike the
Binary-array Convert (Shape-A table), external inputs are not enumerable, so
this is a Shape-B loop; stochastic ρ draws per element from `rng`."""
function Convert(fr::Type{<:Binary}, ρ::ProjSpec,
                 A::AbstractArray{<:Union{Float16,Float32,Float64}}; rng::MaybeRNG=nothing)
    dest = similar(A, fr)
    rr = _rng_for(ρ, rng)                      # hoisted, resolved once
    @inbounds for i in eachindex(dest, A)
        dest[i] = project(fr, ρ, Float64(A[i]); R=_drawR(ρ, rr, nothing))
    end
    dest
end
```

(BFloat16 arrays: add `BFloat16` to that `Union` — widening is exact.)

### 2.4 Tests to add (`test/runtests.jl` harnesses + `quality.jl`)

- Exhaustive: `Float64(Float32(decode(v))) == decode(v)` and BFloat16 twin, all
  codes × all 120 formats (V1/V2 — ~31K assertions, trivial).
- `decode!` gather ≡ elementwise `Float32.(A)` on an all-codes vector per format.
- Array `Convert` ≡ scalar `Convert` per element, both pure and stochastic ρ
  (fixed rng ⇒ reproducible; compare against scalar loop with the same stream).
- JET: `@test_call decode!(zeros(Float32, 4), rand(Binary8p4se, 4))` and the
  array `Convert` entry, per the specialization doctrine; allocation pins on the
  new loops (zero per element).

Effort: ~60 lines of src, ~40 of tests. No risks identified; nothing here can
disturb invariants 1–7 (no new write path — array `Convert` calls `project`).

---

## 3. Milestone 2 — the carrier-exactness trait

### 3.1 Design

`f32_exact(op, f1[, f2])` answers: *is `op` computed in Float32 on decoded
operands exactly equal to the true real result, for every finite operand pair?*
When yes, a Float32 intermediate is a legitimate exact carrier — every ρ
(directed, stochastic) remains correct, because the engine receives the same
value it would have received from Float64. This is strictly stronger than M3's
"κ = 0 under one ρ".

The authority is **enumeration against a BigFloat oracle**, not analytic bounds
(the bounds mispredict: analysis in Float32inside.md §3.2 said "`Binary8p1u`
and near relatives" fail Multiply; measurement says *exactly* `Binary8p1ue/uf`
and no others — V3). Memoized like tables; cold cost ≤ 64K BigFloat ops per
(op, pair), amortized to zero.

### 3.2 Measured gate contents (validated, same-format)

- **Multiply:** 118/120. Excluded: `Binary8p1ue`, `Binary8p1uf`.
- **Add:** 88/120. Gated set: all K ≤ 5 formats except `Binary5p1u*`; all
  K = 6 except `6p1**`, `6p2u*`; K = 7 from P ≥ 3 signed / P ≥ 4 unsigned; K = 8
  from P ≥ 4 signed / P ≥ 5 unsigned (full list in the harness output —
  reproduce with Appendix A). Excluded formats still have most pairs exact
  (worst: `Binary8p1uf`, 18.3% of pairs).

### 3.3 Implementation (`tables.jl`, new section)

```julia
# ---- Float32 carrier-exactness trait (enumeration-backed, memoized) ----------
const F32_EXACT_CACHE = Dict{Tuple{Symbol,NTuple{4,Int},NTuple{4,Int}},Bool}()

_f32op(op::Symbol) = op === :Add ? (+) : op === :Subtract ? (-) :
                     op === :Multiply ? (*) : throw(ArgumentError(
                         "f32_exact defined for Add/Subtract/Multiply, got :$op"))

"""True iff `op` on Float32-decoded operands is exact for every finite pair of
(f1, f2) datums — checked once by enumeration against a 300-bit oracle, cached.
When true, a Float32 intermediate is an exact carrier: all ρ remain correct."""
function f32_exact(op::Symbol, f1::Type{<:Binary}, f2::Type{<:Binary})::Bool
    key = (op, _fkey(f1), _fkey(f2))
    c = lock(() -> get(F32_EXACT_CACHE, key, nothing), TABLE_LOCK)
    c !== nothing && return c
    g = _f32op(op)
    ok = setprecision(BigFloat, 300) do
        for c1 in 0x00:UInt8((1 << bitwidth(f1)) - 1), c2 in 0x00:UInt8((1 << bitwidth(f2)) - 1)
            x = decode(rawvalue(f1, c1)); y = decode(rawvalue(f2, c2))
            (isfinite(x) & isfinite(y)) || continue
            z32 = g(Float32(x), Float32(y))
            BigFloat(z32) == g(BigFloat(x), BigFloat(y)) || return false
        end
        true
    end
    lock(() -> (F32_EXACT_CACHE[key] = ok), TABLE_LOCK)
    ok
end
```

Notes reviewed against the codebase:
- Uses `_fkey`/`TABLE_LOCK` already in `tables.jl`; no new globals per element
  anywhere near a hot loop (`@noinline` fetch if a kernel consults it — once
  per array call, like `get_table`).
- Restricted to Add/Subtract/Multiply deliberately: they are the ops where
  carrier exactness is both checkable and useful (Divide quotients are almost
  never representable; transcendentals never). Extending = adding a method,
  and the BigFloat oracle stays valid.
- The suite should pin the measured gate contents (§3.2) as regression data —
  the counts 118 and 88 are now known-good constants of the format grid.

### 3.4 What consumes it

The only default-API consumer worth building today: a SIMD-friendly loop for
**stochastic** vmap on gated signatures (stochastic ρ is untabulable, so it is
the one pure-CPU path that actually computes per element). Sketch — Shape B
variant in `kernels.jl`, selected when `f32_exact(op, F1, F2)`:

```julia
tbl1, tbl2 = _decode_table32(F1), _decode_table32(F2)   # hoisted
@inbounds for i in eachindex(dest, A, B)
    z = op32(tbl1[...A[i]...], tbl2[...B[i]...])        # exact by the gate
    dest[i] = project(FR, ρ, Float64(z); R=_drawR(ρ, rr, nothing))
end
```

Exactness of `z` means this is bit-identical to the ωeval path (no escalation
can trigger: the gate proves the fast class). Admissible from the default API
under invariant 5 because it is *exact*, provided the suite proves the
equivalence exhaustively per gated signature — same doctrine as the table
builders. If that proof obligation feels heavier than the win, keep M2 purely
as M3's foundation; the trait itself is the deliverable.

---

## 4. Milestone 3 — κ-registered Float32 kernels

### 4.1 Design

For SIMD/GPU throughput where the M2 gate fails, or on hardware without fast
Float64: named kernels `decode32 → guarded op32 → project`, registered through
`register_approx!` so κ is a measured, exhaustively verified property. Policy,
justified by the validation runs:

- **RNE family only** (`NearestTiesToEven`/`NearestTiesToAway` × any saturation
  mode). Directed modes measured κ = 1 (RTZ) and κ = NaN (RTP, saturation
  boundary); do not offer them from this path. Stochastic is rejected by the
  measurement machinery itself.
- **Registration is the gate.** Do not predict κ; register and let
  `measure_kappa` decide. The `Binary8p1ue` Multiply case (κ = 0 under RNE,
  NaN under RTZ) is the proof that prediction fails across ρ.
- Every registered κ = NaN is a rejected kernel, not a shipped one.

### 4.2 The guard table — IEEE-vs-P3109 special semantics

Measured necessity (unguarded Divide: κ = NaN on all five formats tested):

| op | guard | reason |
|---|---|---|
| Divide | `iszero(y32) → NaN` | P3109 has one unsigned zero ⇒ `x/0` has no determinable sign ⇒ defined NaN; IEEE Float32 returns ±Inf. Covers `0/0` and `Inf/0` correctly too (both NaN) |
| Sqrt | `x32 < 0 → NaN32` | Julia `sqrt(::Float32)` **throws** `DomainError`; the draft defines NaN. Without the guard the kernel crashes, not merely deviates |
| Log-family, ArcSin/ArcCos, ArcCosh, ArcTanh | domain guard → NaN | same throw-vs-NaN hazard for out-of-domain arguments |
| RSqrt, Recip | `iszero(x32)` handling per draft tables | sign-of-zero conventions differ |
| Multiply, Divide (SatPropagate only) | finite operands + `Inf32` result → substitute `copysign(1e300, z32)` | Float32 intermediate overflow reads as Inf; SatPropagate is the one saturation mode that sends true Inf to `+Inf` but finite-over-range to `MaxFinite`, so the misclassification becomes a κ = NaN class error. Any same-sign finite over-magnitude carrier projects identically (ωSaturate consumes only the over-magnitude flag), so the substitution is semantics-preserving |

Guards are cheap branches on the scalar; on GPU they compile to predicated
selects. Audit each op against the draft's special-value tables
(`oracle.jl`'s ωeval specials are the in-repo reference) when writing its guard.

### 4.3 Implementation (`approx.jl`, new section)

```julia
# ---- Float32 kernel family (κ-registered; never reachable by default) --------
_f32_base(op::Symbol) =
    op === :Add ? (+) : op === :Subtract ? (-) : op === :Multiply ? (*) :
    op === :Divide  ? ((x, y) -> iszero(y) ? NaN32 : x / y)       :   # P3109: x/0 = NaN
    op === :Sqrt    ? (x -> x < 0 ? NaN32 : sqrt(x))              :   # draft: NaN, not throw
    throw(ArgumentError("no Float32 kernel base for :$op"))           # extend per audit (§4.2)

"""
    f32_impl(op, fr, argformats, ρ) -> fn

The decode32 → guarded-op32 → project kernel for `op⟨argformats → fr, ρ⟩`,
shaped for `register_approx!`. RNE-family ρ only (see the M3 policy)."""
function f32_impl(op::Symbol, fr::Type{<:Binary}, argformats, ρ::ProjSpec)
    roundingmode(ρ) isa RoundingModes_Ties ||
        throw(ArgumentError("Float32 kernels are registered for nearest-ties modes only"))
    g = _f32_base(op)
    (xs::Binary...) -> project(fr, ρ, Float64(g(map(x -> Float32(decode(x)), xs)...)))
end

"""
    register_f32!(op, fr, argformats, ρ) -> ApproxImpl

Build, measure, and register the Float32 kernel under the canonical name
`Symbol("f32/", op, "/", formatname(fr), "/", rm, "_", sm)`. Registration
fails loudly if measured κ is understated or NaN — that is the point."""
register_f32!(op::Symbol, fr::Type{<:Binary}, argformats, ρ::ProjSpec; κ=nothing) =
    register_approx!(Symbol("f32/", op, "/", formatname(fr), "/",
                            _rmname(ρ), "_", _smname(ρ)),
                     op, fr, argformats, ρ, f32_impl(op, fr, argformats, ρ); κ)
```

Round-trip validated against the real registry (V6): a Multiply kernel
registered with κ_declared = κ_measured = 0.0, exhaustive; an understated
declaration (`κ=0` vs true κ = 1) rejected with `ArgumentError`; stochastic ρ
rejected. `conformance()` then lists each registered kernel with its κ and
`exhaustive=true` automatically — no extra wiring.

### 4.4 Measured κ inventory (the shippable starter set)

The initial validation runs probed K = 8 formats as the worst case (widest
exponent spans, finest grids — every smaller K is strictly easier on both the
Float32 range and the `2P + 2` double-rounding bound). A subsequent **full
sweep** removed the sampling entirely:

> **All 120 formats × {Add, Subtract, Multiply, Divide (guarded), Sqrt
> (guarded)}, verified exhaustively per kernel:**
> - `RNE_SN`: **κ = 0 in 600/600.**
> - `RNE_SF`: **κ = 0 in 600/600.**
> - `RNE_SP`: κ = 0 in 598/600; the two exceptions (Multiply and
>   Divide on `Binary8p1ue`, κ = NaN) are the Float32-overflow
>   misclassification — SatPropagate distinguishes true Inf from
>   finite-over-range where SatNone/SatFinite happen not to. **With the
>   overflow guard of §4.2 both re-measure κ = 0**, closing the set at
>   600/600 for all three saturation modes.

So under the M3 policy (RNE family + §4.2 guards) the entire same-format
binary/unary arithmetic surface is registrable at κ = 0 across every
saturation mode — there is no format or saturation restriction. The K = 8 spot checks that generalize *off* the RNE policy remain
the counter-cases:

| counter-case (do not register) | κ |
|---|---|
| Add `8p3se` RTZ_SN | 1.0 |
| Add `8p3se` RTP_SN | NaN |
| Multiply `8p1ue` RTZ_SN | NaN |
| any unguarded Divide (all formats tested) | NaN |

(One directed-mode curiosity from the spot checks: guarded Divide `8p3se`
under RTZ_SN also measured κ = 0 — measured fact for that specialization
only; the RTZ Add/Multiply failures above show it does not generalize, which is
why directed modes stay outside the policy.)

The κ = 0 breadth under RNE is better than the analytic double-rounding bound
promises. Treat each κ = 0 as a per-specialization measured fact; the
registration flow re-measures on every `register_f32!`, so drift is impossible.

### 4.5 GPU direction (design only — not validated here)

The kernel body is GPU-shaped: decode via a 2^K-entry `Float32` constant-memory
table, guarded op32, then projection. Projection on-device should not run the
engine; for pure ρ it is a monotone step function from Float32 to code points,
implementable as a branchless search over a per-(fr, ρ) boundary table of
2^K Float32 thresholds — build that table on CPU *through the engine* (each
boundary is a projection-verified value, preserving invariant 6's spirit), ship
it with the decode table. Validation story on GPU hardware: run the κ
measurement with the device kernel in the `fn` slot — `measure_kappa` does not
care where `fn` computes. **FTZ warning is load-bearing:** device FTZ flushes
the `2^-127` datums of `Binary8p1u*` (the V3 witness is exactly that value);
compile with FTZ off or exclude those two formats on device.

---

## 5. Invariant review (all milestones)

| invariant | disposition |
|---|---|
| 1 One write path | Every path above ends in `project`; the GPU boundary table (§4.5) is built through the engine |
| 2 Code point vs value | Untouched; `Float32`/`BFloat16` are `Real`s ⇒ value semantics |
| 3 Low-K zeros | Untouched |
| 4 Stochastic never tabulable | Reinforced: `measure_kappa` rejects stochastic ρ (validated); M2's stochastic loop is exact-carrier, not a table |
| 5 Nothing approximate by default | M3 kernels live only in `APPROX_REGISTRY` by name; M2's default-API use requires the exactness proof; understatement is machine-rejected (validated) |
| 6 Table entry IS the defined result | Tables still built via the Float64 scalar path; §4.5 keeps the property for boundary tables |
| 7 Registry-driven codegen | `register_f32!` derives arity/validation from `OP_REGISTRY`; no hand-written per-op variants |

Performance rules: decode32 tables are `@generated` constant tuples (fold like
`_decode_table`); trait and table fetches are once-per-array-call; new public
entries get JET `@test_call` + zero-allocation pins.

## 6. Suggested landing order

1. **M1** (surface): src + tests as §2 — small PR, immediately useful for ML
   interop, exercises the new BFloat16s dependency.
2. **M2 trait only** (`f32_exact` + gate-content regression test) — lands the
   enumeration oracle; defer the stochastic SIMD loop until profiled demand.
3. **M3** (`_f32_base` guards + `f32_impl` + `register_f32!` + the §4.4 starter
   registrations as an opt-in snippet or docs example) — κ re-measured at every
   registration, so the shipped artifact is the mechanism, not frozen numbers.
4. GPU work branches from §4.5 when hardware targets are real.

---

## Appendix A — validation harness

Run from the repo root with `julia --project=. <file>`. Consolidated from the
three scripts executed for this document; findings above are its output.

```julia
using SmallFloats; const BF = SmallFloats
using BFloat16s: BFloat16

const FORMATS = sort(collect(BF._NAMED); by=first)
@inline function twosum(a::Float64, b::Float64)
    s = a + b; bb = s - a; (s, (a - (s - bb)) + (b - bb))
end
finitecodes(T) = [c for c in 0x00:UInt8((1 << BF.bitwidth(T)) - 1) if isfinite(BF.rawvalue(T, c))]

# V1/V2 — decode exactness in Float32 and BFloat16
for (name, T) in FORMATS, c in 0x00:UInt8((1 << BF.bitwidth(T)) - 1)
    d = BF.decode(BF.rawvalue(T, c))
    isnan(d) && (@assert isnan(Float32(d)) && isnan(BFloat16(d)); continue)
    @assert Float64(Float32(d)) == d "$name f32 $c"
    @assert Float64(BFloat16(d)) == d "$name bf16 $c"
end

# V3/V4 — carrier-exactness gates (same-format, finite pairs)
for (name, T) in FORMATS
    mul_ok = add_ok = true
    for c1 in finitecodes(T), c2 in finitecodes(T)
        dx, dy = BF.decode(BF.rawvalue(T, c1)), BF.decode(BF.rawvalue(T, c2))
        mul_ok &= Float64(Float32(dx) * Float32(dy)) == dx * dy      # f64 product exact: ≤16-bit sig
        s, err = twosum(dx, dy)
        add_ok &= err == 0.0 && isfinite(s) && Float64(Float32(dx) + Float32(dy)) == s
    end
    println(name, "  multiply-gated=", mul_ok, "  add-gated=", add_ok)
end

# V5 — κ of decode32 → guarded op32 → project kernels
_g(op) = op === :Add ? (+) : op === :Subtract ? (-) : op === :Multiply ? (*) :
         op === :Divide ? ((x, y) -> iszero(y) ? NaN32 : x / y) :
         op === :Sqrt   ? (x -> x < 0 ? NaN32 : sqrt(x)) : error(op)
k2(op, T, ρ) = BF.measure_kappa((x, y) -> BF.project(T, ρ,
                   Float64(_g(op)(Float32(BF.decode(x)), Float32(BF.decode(y))))),
                   op, T, (T, T), ρ)[1]
k1(op, T, ρ) = BF.measure_kappa(x -> BF.project(T, ρ, Float64(_g(op)(Float32(BF.decode(x))))),
                   op, T, (T,), ρ)[1]
for (op, T, ρ) in [(:Add, BF.Binary8p4se, BF.RNE_SN), (:Add, BF.Binary8p3se, BF.RNE_SN),
                   (:Add, BF.Binary8p1uf, BF.RNE_SN), (:Add, BF.Binary8p3se, BF.RTZ_SN),
                   (:Add, BF.Binary8p3se, BF.RTP_SN), (:Subtract, BF.Binary8p3se, BF.RNE_SN),
                   (:Multiply, BF.Binary8p4se, BF.RNE_SN), (:Multiply, BF.Binary8p1ue, BF.RNE_SN),
                   (:Multiply, BF.Binary8p1ue, BF.RTZ_SN), (:Divide, BF.Binary8p3se, BF.RNE_SN),
                   (:Divide, BF.Binary8p1uf, BF.RNE_SN), (:Divide, BF.Binary8p3se, BF.RTZ_SN)]
    println(op, "  ", BF.formatname(T), "  ", ρ, "  κ = ", k2(op, T, ρ))
end
for (T, ρ) in [(BF.Binary8p1uf, BF.RNE_SN), (BF.Binary8p3se, BF.RNE_SN)]
    println(:Sqrt, "  ", BF.formatname(T), "  ", ρ, "  κ = ", k1(:Sqrt, T, ρ))
end

# V6 — registry enforcement round-trip
T = BF.Binary8p4se
impl = BF.register_approx!(Symbol("f32/Multiply/demo"), :Multiply, T, (T, T), BF.RNE_SN,
    (x, y) -> BF.project(T, BF.RNE_SN, Float64(Float32(BF.decode(x)) * Float32(BF.decode(y)))))
@assert BF.kappa(impl) == 0.0 && impl.exhaustive
@assert try   # understated declaration must be rejected (true κ = 1)
    BF.register_approx!(:bad, :Add, BF.Binary8p3se, (BF.Binary8p3se, BF.Binary8p3se),
        BF.RTZ_SN, (x, y) -> BF.project(BF.Binary8p3se, BF.RTZ_SN,
            Float64(Float32(BF.decode(x)) + Float32(BF.decode(y)))); κ=0); false
catch e; e isa ArgumentError end
@assert try   # stochastic ρ must be rejected by measurement
    BF.measure_kappa((x, _) -> x, :Add, T, (T, T), BF.RSA_SN(8)); false
catch e; e isa ArgumentError end
BF.unregister_approx!(Symbol("f32/Multiply/demo"))
println("V6 PASS")

# Full-sweep confirmation of §4.4: all 120 formats × 5 ops, RNE_SN
nz = nt = 0
for (name, T) in FORMATS
    for op in (:Add, :Subtract, :Multiply, :Divide)
        nt += 1; nz += (k2(op, T, BF.RNE_SN) == 0.0)
    end
    nt += 1; nz += (k1(:Sqrt, T, BF.RNE_SN) == 0.0)
end
println("sweep: κ = 0 for $nz / $nt")   # measured 2026-07-24: 600 / 600
# Repeating with ρ = BF.RNE_SF: 600/600. With BF.RNE_SP:
# 598/600 (Multiply/Divide on Binary8p1ue κ = NaN — Float32 overflow vs
# SatPropagate's Inf/finite-over distinction); adding the §4.2 overflow guard
#   ovf(z, x, y) = (isinf(z) && isfinite(x) && isfinite(y)) ?
#                  copysign(1.0e300, Float64(z)) : Float64(z)
# re-measures both at κ = 0.
```

**Scope of validation:** same-format signatures, arity ≤ 2, exhaustive
(every κ above says `exhaustive=true`). Cross-format pairs, ternary ops, and
block/scaled paths were not enumerated here; the harness extends to them by
substituting formats/arity, and M2/M3's mechanisms (trait enumeration,
registration-time measurement) cover them by construction when implemented.
