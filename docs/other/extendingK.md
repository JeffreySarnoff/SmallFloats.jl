# Extending SmallFloats.jl to bitwidths 8 < K ≤ 16 — plan, options, and means

*Original status: design study, written 2026-07-29 against the source tree at commit
`9195d32` and against [IEEE_D1.md](IEEE_D1.md) (IEEE P3109/D1, July 2026) as
ground truth, with [IEEE_D1.json](IEEE_D1.json) used for section addressing and
[IEEE_D1_concepts.md](IEEE_D1_concepts.md) for the concept/relation map. No code
was changed and no tests were run. Every numeric claim below (bias tables, group
memberships, overflow boundaries, counts) is computed from the D1 formulas by
exact rational arithmetic; the derivations are shown so they can be re-checked.*

> **Current role (2026-08-01): decision record for the shipped K ≤ 16
> extension.** The final package has 504 formats over K in 3:16, an abstract
> `Binary{K,P,SGN,EXT}` format with `Code8`/`Code16` representations, table
> decoding for `Code8` and computed decoding for `Code16`, and a three-rung
> `Float64`/`Float128`/`Dyadic` internal carrier lattice. Wide aliases are
> available through `SmallFloats.Formats`; the original 120 K ≤ 8 aliases stay
> exported by `SmallFloats`. The option analysis below explains why those choices
> were made. [doingtheextensions.md](doingtheextensions.md) maps them to the
> current architecture, and [implementextensions.md](implementextensions.md)
> records what execution changed.
>
> Code sketches remain design evidence, not public API. Where `Dyadic` is shown,
> the sketch uses the shipped `(S, Q, kind)` layout and `DY_*` tags; the complete
> implementation is [`src/dyadic.jl`](../../src/dyadic.jl).

---

## 0. Verdict up front

1. **The draft permits it without qualification.** D1 §3.1 fixes only `K > 2`
   ([IEEE_D1.md#L276](IEEE_D1.md#L276)); nothing else in the document is
   bitwidth-limited. K ∈ 3:16 is a **504-format** grid (120 today + 384 new).
2. **Two orthogonal axes govern the extension — and only two.**
   *Storage unit*, a function of K alone (1 byte for K ≤ 8, 2 bytes for
   9 ≤ K ≤ 16), and *evaluation carrier*, a function of the **exponent bias**
   B — not of K. These are independent; the plan is organized around them.
3. **The carrier ladder already exists.** `Float64 → Float128 → MPFR` is the
   package's current escalation ladder. Extending K does not add a rung; it
   makes the *starting* rung a per-specialization trait instead of the constant
   `Float64`. That reframing is the single most important simplification in
   this document: it turns a "new carrier" project into a "choose the entry
   point" project, and it leaves every K ≤ 8 path on rung 1 exactly as today
   (verified: the worst K ≤ 8 monomial, a four-factor scaled block multiply of
   `Binary8p1u` datums, needs ΣB = 512 ≪ 1024).
4. **Format counts by starting rung** (all 504 formats, scalar ops):
   **432 on Float64**, **64 on Float128**, **8 on MPFR**. The Float128 tier is
   allocation-free (`Float128` is a bitstype), so only 8 of 504 formats — all
   of them P ≤ 2 extreme-dynamic-range curiosities — leave the isbits world,
   and even those have an allocation-free option (§6, the `Dyadic` carrier).
5. **The three things that genuinely break and must be fixed, not deferred:**
   the `UInt8` payload field (§5.1), the unconditional `@generated` decode
   tuple and the unconditional binary table (§5.2, §5.5 — 2^32 entries at
   K = 16 is not a policy question, it is an impossibility), and the constant
   `_BIGP = 2200` MPFR precision, which is silently too small once B > 1024
   (§5.4). Everything else is mechanical widening.
6. **Two rules the package states today are K ≤ 8 theorems and must be
   restated, not stretched.** Invariant 2 ("`UInt8` means code point") ties a
   *meaning* to a type that was unique only because there was one storage
   width — restated in §5.13 as *every `Unsigned` is a code point at every
   width, range-checked*, which keeps meaning format-independent instead of
   trading one K-dependence for another. The enumerate-don't-sample doctrine is
   a theorem whose hypothesis is `K ≤ 8` — restated in §8 around a
   factorization that makes the engine stages *cheaper* to cover completely at
   K ≤ 16 than they are today (252 parameter tuples versus 504 formats) while
   keeping the full code-lattice sweep exhaustive at 7.6 M points, with five
   named standing gates (G1–G5) and one honest residual-risk statement.
7. **Recommended landing order:** M1 storage+format grid (all 504 formats
   *exist*, K ≤ 10 fully operational) → M2 table/kernel policy → M3 rung
   selection (Groups B and C correct) → M4 wide-K test doctrine → M5 optional
   `Dyadic` fast path and `_rtp_f128` bit twin.

---

## 1. Ground truth: what D1 actually says about K

### 1.1 The format grid is unbounded above

> "Bitwidth K, an integer greater than two" — [§3.1](IEEE_D1.md#L276)

The precision constraint is `0 < P < K` (signed) / `0 < P ≤ K` (unsigned)
([§3.1](IEEE_D1.md#L277)); the bias is `B = 2^(K−P−1)` signed, `2^(K−P)`
unsigned ([§3.1](IEEE_D1.md#L282)); naming is `Binary⟨K⟩p⟨P⟩⟨s|u⟩⟨e|f⟩` and
the document's own example is a **12-bit** format:

> "The format 'Binary12p7se' is a 12-bit signed, extended format with precision 7."
> — [§3.2](IEEE_D1.md#L323)

So K > 8 is not an extrapolation; the draft names such a format in its
normative naming clause.

Everything downstream is written in terms of K, P, B, Σ, Δ and never in terms
of a byte: `ωDecodeAux` ([§4.7.2](IEEE_D1.md#L619)), `ωRoundToPrecision`
([§4.7.4](IEEE_D1.md#L704)), `ωSaturate` ([§4.7.5](IEEE_D1.md#L770)),
`ωEncode` ([§4.7.6](IEEE_D1.md#L818)), the special-code table
([Annex B Table 3](IEEE_D1.md#L2550)), the block clauses
([§5](IEEE_D1.md#L2077)), the conformance and κ machinery
([§4.4](IEEE_D1.md#L468)–[§4.6](IEEE_D1.md#L588)). **No behavioral rule
changes with K.** The extension is therefore purely an implementation-carrier
and storage-representation exercise, not a semantics exercise. That is the
strongest fact in this document and it should be stated in the package docs.

### 1.2 The grid, counted

For a given K the format count is `2·(K−1)` signed + `2·K` unsigned = `4K−2`.

| K | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|----|----|----|----|----|----|
| formats | 10 | 14 | 18 | 22 | 26 | 30 | 34 | 38 | 42 | 46 | 50 | 54 | 58 | 62 |

K ≤ 8: **120** (today). 9 ≤ K ≤ 16: **384**. Total **504**.

### 1.3 Two traps worth naming now

**`Binary16p11se` is not `Float16`, and `Binary16p8se` is not `BFloat16`.**
P3109 derives the bias from (K, P, Σ): `Binary16p11se` has `B = 2^(16−11−1) =
16`, while IEEE binary16 has bias 15; `Binary16p8se` has `B = 2^7 = 128` while
BFloat16 has bias 127. They also differ in NaN count, negative zero, and the
domain parameter (the divergence table in
[IEEE_D1_concepts.md §9](IEEE_D1_concepts.md#L602) collects these). The module
already binds lowercase `binary16 = Float16` as an *external* format per
[§4.8](IEEE_D1.md#L865); the new uppercase `Binary16p*` aliases are unrelated
types. Julia's case sensitivity keeps them apart mechanically, but the
docstrings must say this out loud or users will assume a hardware-format
bridge that does not exist.

**Some new formats are degenerate in the same way Annex C's K = 2 formats
are.** [Annex C](IEEE_D1.md#L2648) documents that at small K certain formats
have no normal values, no subnormals, or duplicate datum sets. The analogous
edge at large K is the opposite extreme: `Binary16p1uf` has *one* significand
bit and a bias of 32768, so its datum set is `{0} ∪ {2^e : −32767 ≤ e ≤
32766} ∪ {NaN}` — a pure exponent format spanning 65534 binades. It is a legal
conforming format and the implementation must handle it; it is also the single
format that drives the widest carrier requirement in the whole grid (§4.3).

---

## 2. Inventory: what in the package actually depends on K

Thirteen sites. Everything else is K-agnostic already.

| # | site | dependence | severity |
|---|---|---|---|
| 1 | [`formats.jl:17`](../../src/formats.jl#L17) `Binary`'s `x::UInt8` field | K ≤ 8 hard-coded in the representation | **blocking** |
| 2 | [`formats.jl:31`](../../src/formats.jl#L31) `checkformat` `3 <= K <= 8` | the gate itself | trivial |
| 3 | [`formats.jl:86-112`](../../src/formats.jl#L86-L112) special/extremal code points | `UInt8(...)` constructors | mechanical |
| 4 | [`formats.jl:210-222`](../../src/formats.jl#L210-L222) promotion + `Float32`/`BFloat16` | assumes Float64/Float32 are exact carriers | **semantic** |
| 5 | [`decode_encode.jl:36,44`](../../src/decode_encode.jl#L36) `@generated` 2^K constant tuples | 65 536-element tuple literal | **blocking** |
| 6 | [`decode_encode.jl:25-33`](../../src/decode_encode.jl#L25-L33) direct Float64 bit assembly | comment asserts \|e\|≲260, false for B > 512 | **correctness** |
| 7 | [`decode_encode.jl:69`](../../src/decode_encode.jl#L69) `encode → UInt8` | return width | mechanical |
| 8 | [`decode_encode.jl:92-101`](../../src/decode_encode.jl#L92-L101) `order_key::UInt16`, `NAN_ORDER_KEY` | K = 16 needs 2^16+1 keys | mechanical |
| 9 | [`decode_encode.jl:135-164`](../../src/decode_encode.jl#L135-L164) counting sort | allocates 2^K counters unconditionally | policy |
| 10 | [`project.jl:84-131`](../../src/project.jl#L84-L131) `_rtp_f64` | comment `d ≤ P−1 ≤ 7`; also the Float64-range premise | **correctness** |
| 11 | [`oracle.jl:24,38-40`](../../src/oracle.jl#L24) `_BIGP = 2200`, `_DE_ADD/FMA/FAA` | calibrated to ≤ 8-bit significands and Float64 spans | **correctness** |
| 12 | [`tables.jl:28,88-111`](../../src/tables.jl#L28) `Memory{UInt8}`, unconditional unary/binary build | 2^(K1+K2) entries | **blocking** |
| 13 | [`packed.jl:50,68`](../../src/packed.jl#L50) `UInt8(c & mask)` | element unit | mechanical |

Two things are notably *absent* from this list and that is worth recording:

- **`project.jl`'s saturation stage is already K-agnostic.** `saturate` works
  entirely in the canonical `(sign, S, Q)` integer space against
  `_extremal_SQ(T)` ([`project.jl:260`](../../src/project.jl#L260)); it never
  touches a float. The only float-valued comparator,
  `_cmp_rounded_datum(..., m::Float64)`
  ([`project.jl:237`](../../src/project.jl#L237)), is not on the `saturate`
  path. This is a large piece of good luck: the hardest stage to widen is
  already wide.
- **`approx.jl`'s κ machinery already degrades honestly.** `measure_kappa`
  takes `max_exhaustive = 2^22` and reports `exhaustive = false` when the
  input space is larger ([`approx.jl:38-54`](../../src/approx.jl#L38)). At
  K = 16 a unary sweep (2^16) stays exhaustive; a binary sweep (2^32) becomes
  sampled and *says so*. Invariant 5 survives wide K with no change, because
  the mechanism was designed as a measurement, not an assertion.

---

## 3. The organizing principle

### 3.1 Axis 1 — storage unit, a function of K

| unit | K | formats | rationale |
|---|---|---|---|
| `UInt8` | 3 – 8 | 120 | unchanged; the byte layout, packed storage, and every measured hot path stay bit-identical |
| `UInt16` | 9 – 16 | 384 | the code point occupies the low K bits; the high 16−K bits are maintained zero (representation invariant 3, restated for the wider unit) |

No third unit is needed and none should be introduced. The invariant-3
statement generalizes verbatim: *the code point occupies the low K bits of the
payload word; the high bits are maintained zero.*

### 3.2 Axis 2 — evaluation carrier, a function of exponent bias

This is the axis the user's framing asks for, and the correct variable is
**B, not K**. `Binary16p12se` (B = 2^3 = 8) is numerically *tamer* than
`Binary8p1uf` (B = 2^7 = 128); K tells you how many code points there are, B
tells you how far apart they can be.

**Derivation of the rung boundaries.** Every finite datum satisfies
`|X| ≤ MaxFinite = (2^P − 1)·2^(B−P) < 2^B`, and every nonzero finite datum
satisfies `|X| ≥ MinPositive = 2^(2−P−B)`. An operation's worst-case
intermediate is a monomial in *n* datum factors (n = 1 for unary and additive
ops, 2 for `Multiply`/`FMA`, 4 for a scaled or block multiply — see §5.7).
Then

```
|product|  <  2^(ΣBᵢ)                     and, since Π(2^Pᵢ − 1) ≥ 2^(ΣPᵢ − n),
|product|  ≥  2^(ΣBᵢ − n)   (nonzero)     |product| ≥ 2^(Σ(2 − Pᵢ − Bᵢ))
```

so the monomial fits carrier `C` with maximum exponent `emax_C` and minimum
subnormal exponent `emin_C` exactly when

```
ΣBᵢ ≤ emax_C            (over-range)
Σ(Bᵢ + Pᵢ) ≤ −emin_C + 2n   (under-range, and exactness there because the
                             value carries at most ΣPᵢ ≤ 16n significant bits)
```

The `ΣBᵢ ≤ emax_C` form is exact rather than conservative because the leading
`(2 − 2^(1−P))` factors always give ≥ 2^-16 of headroom, far more than the
2^-53 (Float64) / 2^-112 (Float128) needed at the very top binade — verified by
exact rational arithmetic for every P ≤ 16.

| rung | carrier | `emax` | `−emin` | rung-1/2/3 condition (scalar ops, ΣB = n·B) |
|---|---|---|---|---|
| 1 | `Float64` | 1024 | 1074 | `ΣB ≤ 1024` |
| 2 | `Float128` | 16384 | 16494 | `ΣB ≤ 16384` |
| 3 | MPFR / `Dyadic` | unbounded | unbounded | otherwise |

**Cross-check against the existing package:** the worst K ≤ 8 monomial is a
four-factor block/scaled multiply of `Binary8p1u` datums, ΣB = 4·128 = 512 ≤
1024 — rung 1. **No K ≤ 8 specialization moves.** Verified by exact rational
arithmetic, not asserted.

---

## 4. The groups

### 4.1 Group A — Float64 head (432 formats)

**Membership:** every format with `2B ≤ 1024`, i.e. `B ≤ 512`. That is *all*
formats at K ≤ 10, plus, at each K ∈ 11:16, the 40 formats with
`P ≥ K − 10` (signed) / `P ≥ K − 9` (unsigned).

| K | 3–10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|
| Group A | all (192) | 40 | 40 | 40 | 40 | 40 | 40 |

**"Float64 head" means today's carrier, unchanged — and `Float32` is not a
carrier at any K.** This needs saying because the package exports `f32_exact`
and ships a Float32 kernel family, which makes it look otherwise. `Float32`
occupies three roles in `src/`, none of them the carrier: an **exact output
surface** (`Base.Float32(v)` gathering `_decode_table32`,
[`formats.jl:218`](../../src/formats.jl#L218), and `decode!` into a `Float32`
array, [`kernels.jl:168`](../../src/kernels.jl#L168)); a **trait**,
`f32_exact` ([`tables.jl:236`](../../src/tables.jl#L236)), which answers
whether a Float32 intermediate *would* be exact and **has no call site
anywhere in `src/`** — the SIMD stochastic loop sketched as its consumer in
[Float32more.md §3.4](Float32more.md) was never built; and **κ-registry
kernels** (`f32_impl`/`register_f32!`,
[`approx.jl:183-211`](../../src/approx.jl#L183-L211)) reachable only by
explicit name under invariant 5. The carrier proper is `decode(v)::Float64`
feeding `apply_op(..., xs::Float64...)`, and
[Float32inside.md](Float32inside.md) already settled why it cannot be Float32:
`Float32` holds every K ≤ 8 *datum* exactly but not the *intermediates*.

**What Group A needs:** storage widening (§5.1), computed decode (§5.2), the
generalized table policy (§5.5), `_DE_*` thresholds as functions of P (§5.4),
and a format-derived `_BIGP` (§5.4). **No carrier change at all.** Every
existing proof in `oracle.jl` transfers with `8` replaced by `P` in the width
arithmetic. This is where ~86% of the new grid lives and it is the cheap part.

**Performance expectation:** identical class to today for K ≤ 8; for
K ∈ 9:16 the scalar path is the same instruction sequence with a 16-bit code
unit, and the array path loses the smallest tables (a K = 16 unary table is
128 KiB, a K = 16 binary table is impossible) — see §5.5 for what replaces
them.

### 4.2 Group B — Float128 head (64 formats)

**Membership:** `1024 ≤ B ≤ 8192`. Explicitly, by K (each entry is two
formats, `…e` and `…f`):

| K | Group B formats |
|---|---|
| 11 | `Binary11p1u` |
| 12 | `Binary12p1s`, `Binary12p1u`, `Binary12p2u` |
| 13 | `Binary13p1s`, `Binary13p2s`, `Binary13p1u`, `Binary13p2u`, `Binary13p3u` |
| 14 | `Binary14p1s`–`p3s`, `Binary14p1u`–`p4u` |
| 15 | `Binary15p1s`–`p4s`, `Binary15p2u`–`p5u` |
| 16 | `Binary16p2s`–`p5s`, `Binary16p3u`–`p6u` |

(32 (K, P, Σ) combinations × 2 domains = 64 formats.)

Note the diagonal structure: Group B is exactly the band `10 ≤ log₂B ≤ 13`,
which for signed formats is `K − P ∈ 11:14` and for unsigned `K − P ∈ 10:13`.
It is a *stripe*, not a K-range, which is why the grouping must be stated in B.

**What Group B needs, and why it is cheap:** the package already computes in
`Float128` — `_twosum128`, `_faa_wide`, `Enclose128F`, the `fq` prefilter, and
`round_to_precision(::Float128)` all exist and are exercised today as
*escalation* targets. Group B starts one rung up:

- `decode` returns `Float128` (exact: 113-bit significand ≫ P ≤ 16; exponent
  range covers B ≤ 8192 datums with ~2^4 binades to spare at the top and
  ~2^13 at the bottom).
- `ωeval`'s Class-1 arithmetic rows run on `Float128` operands; the residual
  test uses `_twosum128` (already written) instead of `_twosum`.
- Exactness thresholds become `113`-based instead of `53`-based: escalate to
  MPFR when `spread + max(Pᵢ) + 1 > 113`.
- `round_to_precision` needs no new method —
  [`project.jl:139`](../../src/project.jl#L139) already routes `Float128`
  through `_rtp_core` with a written argument for why every step is exact
  there, and that argument is a function of P and the carrier, not of K.
- **Allocation-free.** `Float128` is a bitstype, so Group B keeps the
  zero-warm-path-allocation regression pins. This is the property that makes
  Group B a first-class tier rather than a slow tier.

**Cost:** `Float128` arithmetic is software-emulated (Quadmath) or 128-bit
hardware where available; expect roughly 5–20× the scalar latency of Group A.
For array work the table cache absorbs it entirely at K ≤ 12 (§5.5). Under
`ENV["SmallFloats_Float128"] = "disable"`, Group B must fall back to MPFR with
**bit-identical results** — the existing pure-MPFR configuration contract
([CLAUDE.md](../../CLAUDE.md)) extends unchanged, but now covers a *default*
path for 64 formats rather than only escalations, so the dual-configuration CI
job becomes load-bearing for Group B correctness rather than merely
confirmatory.

### 4.3 Group C — MPFR / Dyadic head (8 formats)

**Membership:** `B ≥ 16384`. Exactly four (K, P, Σ) combinations:

| format | B | datums fit `Float128`? | monomials fit `Float128`? |
|---|---|---|---|
| `Binary15p1u{e,f}` | 2^14 | yes | no (products reach 2^32768) |
| `Binary16p1s{e,f}` | 2^14 | yes | no |
| `Binary16p2u{e,f}` | 2^14 | yes | no |
| `Binary16p1u{e,f}` | 2^15 | **no** (max datum 2^32767) | no |

So of 504 formats, exactly **two** (`Binary16p1ue`, `Binary16p1uf`) cannot
even *decode* into `Float128`, and six more can decode but cannot multiply
there.

**What Group C needs:** a carrier with an unbounded exponent. Two candidates,
evaluated in §6. The recommendation is `Dyadic` (an exact `(sign, S::Int128,
Q::Int64)` triple) for the Group-A-registry arithmetic — which is *exact,
isbits, and allocation-free* — with MPFR retained for transcendentals via the
existing `EncloseF` ladder, whose closures are already carrier-agnostic.

**Honest statement to ship:** Group C is a *correctness* tier. Transcendental
scalar operations there are microsecond-class MPFR ladders. Nobody should be
surprised: these are formats where `Exp` of almost every input either
overflows past 2^32767 or underflows past 2^-32767, so the transcendental
catalog is mostly special-value rows anyway.

### 4.4 The two axes are independent — the shipping matrix

|  | Group A (Float64) | Group B (Float128) | Group C (MPFR/Dyadic) |
|---|---|---|---|
| `UInt8` storage (K ≤ 8) | 120 formats — **today's package** | — | — |
| `UInt16` storage (K 9–16) | 312 formats | 64 formats | 8 formats |

Read the matrix as the delivery plan: the top-left cell must not regress; the
middle-left cell is M1+M2; the two right cells are M3.

---

## 5. Manner and means, layer by layer

### 5.1 `formats.jl` — the type

Three options were considered for admitting a second storage width.

**Option T1 — fifth type parameter.**
`struct Binary{K,P,SGN,EXT,U<:Unsigned} <: AbstractFloat; x::U; end`, with
`U` fixed by the named aliases. Signatures written `Binary{K,P,S,E}` keep
working (they become `UnionAll` bounds and still destructure in `where`
clauses). *Rejected* because `Binary{8,4,true,true}` — a spelling that appears
in user code, in `similar(A, fr)`, and in this repository's own tests — stops
being a concrete type, so `eltype` and array construction silently break for
anyone not using the aliases.

**Option T2 — a parallel `WideBinary` type.**
Two concrete structs under a parametric abstract supertype. *Rejected* on
invariant 7: every registry-generated method family would need two
instantiations, and the whole point of the registry is that a per-format
variant cannot be hand-written unevenly. It also duplicates the inner
constructor and the representation invariant, which is where a divergence
would be least visible.

**Option T3 — `Binary` becomes the abstract *format*; concrete subtypes are
*representations*. Recommended.**

```julia
"""A P3109 floating-point format. Concrete subtypes differ only in the width of
the storage unit holding the code point; the format's semantics are a function
of (K, P, SGN, EXT) alone."""
abstract type Binary{K,P,SGN,EXT} <: AbstractFloat end

struct Code8{K,P,SGN,EXT}  <: Binary{K,P,SGN,EXT};  x::UInt8  end   # K ≤ 8
struct Code16{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT};  x::UInt16 end   # 9 ≤ K ≤ 16

"""The concrete representation type for a format — folds to a literal type
whenever K is a static parameter, which it always is at a call site."""
@inline reptype(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} =
    K <= 8 ? Code8{K,P,S,E} : Code16{K,P,S,E}
"""The storage unit of a format: `UInt8` or `UInt16`."""
@inline codeunit_type(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} =
    K <= 8 ? UInt8 : UInt16
```

This maps exactly onto D1's own distinction: a *format* comprises "a datum set
and an encoding" ([§3.1](IEEE_D1.md#L270)), while the storage unit is an
implementation choice below that. Concretely it wins because:

- **Every existing signature keeps its text.** `f(x::Binary)`,
  `where {K,P,S,E,T<:Binary{K,P,S,E}}`, `::Type{<:Binary}` all continue to
  work and continue to destructure the parameters. This is the property T1 and
  T2 each lose in a different place.
- **One set of registry-generated methods**, dispatching on the abstract bound
  and reaching storage only through `codepoint(v)` and `rawvalue(T, c)`.
- **The named aliases stay concrete**: `const Binary8p4se = Code8{8,4,true,true}`,
  `const Binary12p7se = Code16{12,7,true,true}`. Since `_NAMED` and
  `formatname` already read the grid from one place
  ([`formats.jl:130-144`](../../src/formats.jl#L130-L144)), this is a
  three-line change to the generating loop.
- **`show` keeps printing draft names**, since `_fully_instantiated` tests the
  parameter shape, which is unchanged (4 parameters).

The migration cost is confined to *construction* sites — anywhere the code
today writes `Binary{K,P,S,E}` to mean "the concrete type" it must write
`reptype(...)` (or, better, `typeof(v)` where a value is in hand). There are
~20 such sites, all inside `src/`, all found by a compile error rather than by
a test.

The remaining `formats.jl` edits are mechanical:

```julia
3 <= K <= 16 || throw(ArgumentError("bitwidth K=$K outside supported range 3:16"))
@inline nan_code(::Type{F}) where {F<:Binary{K,P,S,E}} where {K,P,S,E} =
    S ? codeunit_type(F)(1) << (K - 1) : ~codeunit_type(F)(0) >> (8*sizeof(codeunit_type(F)) - K)
```

— i.e. every `UInt8(...)` in the special/extremal code-point block becomes
`U(...)` for `U = codeunit_type(F)`. The values are unchanged; only the width
of the literal changes, and all of them still constant-fold.

**Promotion must become carrier-aware** (inventory item 4). Today
`promote_rule(::Type{<:Binary}, ::Type{Float64}) = Float64`
([`formats.jl:210`](../../src/formats.jl#L210)). For Group B/C formats
`Float64` is not an exact carrier, so `x + 1.0` would silently round a datum
that the package elsewhere guarantees is exact. Replace with:

```julia
Base.promote_rule(::Type{F}, ::Type{<:Union{Float64,Float32,Float16,BFloat16,Integer}}
                 ) where {F<:Binary} = datumtype(F)
```

where `datumtype` is the trait of §5.4. This keeps `Float64` for 432+ formats
and widens only where widening is forced — and it makes the promotion rule a
*theorem about exactness* rather than a convention.

### 5.2 `decode_encode.jl` — decode, encode, keys, sort

**Decode: compute, do not tabulate, for K ≥ 9.** The `@generated` constant
tuple ([`decode_encode.jl:36`](../../src/decode_encode.jl#L36)) is excellent at
K ≤ 8 (256 entries, folds, one load) and catastrophic at K = 16 (a
65 536-element tuple literal; tuple-`getindex` inference is linear in the
length). Split by trait:

```julia
@inline decode(v::F) where {F<:Binary} = _decode(F, codepoint(v), Val(bitwidth(F) <= 8))
@inline _decode(::Type{F}, c, ::Val{true})  where {F} = @inbounds _decode_table(F)[Int(c)+1]
@inline _decode(::Type{F}, c, ::Val{false}) where {F} = _decode_compute(F, c)
```

`_decode_compute` must also lose its Float64 bit-assembly shortcut, whose
justifying comment — "every datum exponent is deep inside Float64's normal
range (|e + nb − 1| ≤ ~260)"
([`decode_encode.jl:25-27`](../../src/decode_encode.jl#L25-L27)) — is exactly
the K ≤ 8 premise. For K ≥ 9 write it in the carrier-generic form, which is
still branch-free-ish and exact:

```julia
C = datumtype(F)                       # Float64 | Float128 | Dyadic
sig == 0 && return zero(C)
ldexp(C(sig), e)                       # exact: sig < 2^P ≤ 2^16, and by
                                       # construction e is in C's range
```

`ldexp` on `Float64`/`Float128` is exact for in-range results and handles the
subnormal landing zone that B ≈ 1024 formats reach (min datum 2^(2−P−B) can be
as low as 2^-1038, a Float64 subnormal — the current bit assembly would produce
garbage there). An optional K ≥ 9 bit-assembly fast path can be added later
behind the same exhaustive equivalence gate the K ≤ 8 path already carries;
it is not needed for correctness and should not be written before a
measurement demands it.

**A middle tier is available and should be measured, not assumed:** a lazily
built, cached `Memory{Float64}` decode table for K ∈ 9:12 (≤ 32 KiB) in the
existing `TABLE_CACHE` style. Whether a 4 KiB–32 KiB table beats ~10 integer
ops plus an `ldexp` is a cache-pressure question with no a-priori answer.
Ship computed decode; add the table only if the benchmark suite shows a win on
a realistic array workload.

**Encode** ([`decode_encode.jl:69`](../../src/decode_encode.jl#L69)) returns
the storage unit instead of `UInt8`; the arithmetic inside is already
`Int64`-based and needs no change (`Eb ≤ 2^16`, `S ≤ 2^16`).

**Order keys** ([`decode_encode.jl:92-101`](../../src/decode_encode.jl#L92)):
the key space is `2^K + 1` values, so `UInt16` runs out at exactly K = 16.
Make the key type a trait (`UInt16` for K ≤ 15, `UInt32` for K = 16) or simply
`UInt32` for all K ≥ 9; `NAN_ORDER_KEY` becomes `typemax(keytype(F))`, a
per-format function rather than a const. The monotone-key equivalence proof is
a statement about the code lattice and is independent of K, so the existing
exhaustive gate generalizes directly (and at K ≤ 12 can still run exhaustively
over all 2^K codes).

**Counting sort** ([`decode_encode.jl:135`](../../src/decode_encode.jl#L135))
allocates `2^K + 2` counters and runs a `2^K` key↔code inversion loop
unconditionally. At K = 16 that is 512 KiB and 65 536 iterations of setup
before touching the data — a pessimization for any array shorter than about
2^16. Gate it:

```julia
n = hi - lo + 1
n < (1 << K) && return sort!(v, lo, hi, Base.Sort.DEFAULT_UNSTABLE, o)
```

The counting sort remains asymptotically right where it was right, and the
crossover is now stated rather than assumed. (The same one-line reasoning
applies at K ≤ 8 today, where the setup is 256 elements and the gate almost
never fires — so this is a generalization, not a behavior change, for existing
users.)

### 5.3 `project.jl` — the engine

**`_rtp_f64` remains valid for Group A, with one comment correction and one
premise to re-check.** Its arithmetic:

```
Q = max(e, 1−B) − P + 1 ;  d = e − Q   ;  t = 52 − d
```

The comment says `d ≤ P−1 ≤ 7` ([`project.jl:90`](../../src/project.jl#L90));
the true bound is `d ≤ P−1 ≤ 15`, giving `t ∈ [37, 52]` instead of `[45, 52]`.
Every shift in the body (`m >> t`, `UInt128(...) << (128−t)`) stays in range,
and `Sfl ≤ 2^16` still fits `Int64`. So the bit path generalizes to P ≤ 16
**unchanged except for the comment** — but the exhaustive bit ≡ generic
equivalence gate must be re-run over the wider (P, B) grid, and it is that
gate, not the comment, that licenses the claim.

The dispatcher at [`project.jl:36-40`](../../src/project.jl#L36) already bails
to `_rtp_core` for Float64-subnormal inputs, which is exactly the landing zone
B ≈ 1024 formats reach. That guard was written for `Convert` and turns out to
be precisely what wide-B formats need. Keep it; do not "optimize" it away.

**No `_rtp_f128` is required.** `round_to_precision(::Float128)` routes to
`_rtp_core` with a written exactness argument
([`project.jl:133-140`](../../src/project.jl#L133-L140)) that depends on P and
the carrier, not on K. Group B therefore pays generic-path cost in the
projection stage. A `_rtp_f128` bit twin is a legitimate later optimization,
but it would be the *third* member of the twin family that
[`project.jl:62-66`](../../src/project.jl#L62-L66) warns must be kept in sync,
so it should not be written until Group B benchmarks justify the permanent
maintenance surface.

**`Rounded` needs no change.** `S::Int64` holds `S ≤ 2^P ≤ 2^16`; `Q::Int64`
holds `|Q| ≲ B + P ≤ 32784`; `HUGEQ = 2^40` still exceeds every reachable Q by
five orders of magnitude. `saturate` is already pure integer work against
`_extremal_SQ`. **The projection engine is the layer that needs the least
work**, which is the opposite of the naive expectation and worth saying in the
docs.

### 5.4 `ops_scalar.jl` / `oracle.jl` — rung selection and the width proofs

Two new traits, both pure functions of type parameters, both constant-folding:

```julia
"""The narrowest exact carrier for the *datums* of format F."""
@inline datumtype(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} =
    (B = S ? 1<<(K-P-1) : 1<<(K-P);
     B <= 1024 ? Float64 : (B <= 16384 && 2-P-B >= -16494) ? Float128 : Dyadic)

"""The starting rung for evaluating `op` over the given formats: the narrowest
carrier holding every monomial the op's ω-semantics can form. `factors(op)` is
a registry column (1 for additive/unary, 2 for Multiply/FMA, +1 per block
scale factor)."""
@inline headtype(op, fs...) = ...   # ΣB ≤ 1024 → Float64; ≤ 16384 → Float128; else Dyadic/MPFR
```

`factors` is a **new `OpInfo` column**, not a hand-maintained table — invariant
7 requires that the block and scaled variants derive their factor counts from
the same row that generates them ([`blocks.jl`](../../src/blocks.jl) generates
`Block*`/`Scaled*` from `OP_REGISTRY`), so adding a scale factor to a generated
variant automatically raises its ΣB.

**Three concrete correctness fixes inside `oracle.jl`:**

1. **`_BIGP = 2200` becomes format-derived.**
   ([`oracle.jl:24`](../../src/oracle.jl#L24), commented "> full Float64
   exponent span + slack".) An exact sum of two datums needs
   `spread + max(Pᵢ) + 1` bits, and the spread can reach `2B + P`. At B = 512
   that is ~1040 bits — inside 2200, which is why the constant works today and
   would keep appearing to work through Group A. At B = 8192 it is ~16400 bits
   and at B = 32768 it is ~65600: **the constant silently truncates**, and a
   truncated "exact" BigFloat is the worst possible failure mode because it is
   indistinguishable from a correct one without a reference. Replace with
   `bigprec(fs...) = 2*(maxB + maxP) + 64` and add a regression that asserts
   the computed precision exceeds the actual operand spread on the widest
   format. This is the highest-priority item in the whole plan: it is a
   *latent* wrong-answer bug in a path that is currently unreachable and
   becomes reachable the moment K > 11 exists.

2. **`_DE_ADD/_DE_FMA/_DE_FAA` become functions of P.**
   ([`oracle.jl:38-40`](../../src/oracle.jl#L38-L40).) The current values
   (100, 92, 98) are `113 − (significand bits) − margin` with "significand
   bits" computed for P ≤ 8. Generalize:

   ```
   _DE_ADD(P₁,P₂) = 113 − (max(P₁,P₂) + 1) − 4
   _DE_FMA(P₁,P₂,P₃) = 113 − (P₁ + P₂ + 1) − 3
   _DE_FAA(P₁,P₂,P₃) = 113 − (max(Pᵢ) + 3) − 4
   ```

   At P = 8 these reproduce 100/92/98 exactly, so the change is a
   generalization with a fixed point at today's values — which is the right
   shape for a threshold refactor and should be asserted as such in the suite.
   At P = 16 they give 92/80/90, all comfortably positive, so the Float128 rung
   still covers the whole band between the Float64 residual test and MPFR.

3. **The `yd`/`fq` prefilters are already sound at any K, and this is a
   finding rather than a fix.** `_finish` guards the Float64 estimate with
   `isfinite(yd) && abs(yd) >= _F64_MINNORMISH`
   ([`ops_scalar.jl:100`](../../src/ops_scalar.jl#L100)) and the Float128
   estimate with `isfinite(y) && !iszero(y)`
   ([`ops_scalar.jl:108`](../../src/ops_scalar.jl#L108)). A wide-B true value
   that leaves the prefilter's range therefore *skips* the prefilter and falls
   to the rigorous ladder — it cannot produce a wrong answer, only a slow one.
   No new proof obligation for the entire transcendental catalog. Record this
   explicitly so a future reader does not re-derive it.

**`apply_op`'s fast split** ([`ops_scalar.jl:130-139`](../../src/ops_scalar.jl#L130))
tests `res isa Float64` to keep the widened union off the hot path. Under rung
selection this becomes `res isa headtype(...)` — statically known at each
specialization, so the split survives with the same shape and the same measured
benefit. Group B's split tests `Float128`; Group C's tests `Dyadic`.

### 5.5 `tables.jl` — one policy for every arity

Today the policy is split: unary and binary tables are built *unconditionally*
(they can't exceed 64 KiB at K ≤ 8), while ternary tables go through a
three-band policy with an eager bit budget, an adaptive element counter, and an
LRU byte budget ([`tables.jl:57-67`](../../src/tables.jl#L57-L67)). At K ≤ 16
the unconditional path is untenable: a K = 16 binary table has 2^32 entries.

**The fix is a simplification: delete the special case.** Route every arity
through the shape the ternary path already has:

```julia
_table_for(op, fr, fs::Tuple, ρ, nelems) -> Union{Nothing, Memory{U}}
    bits  = Σ bitwidth(fᵢ)
    bytes = (1 << bits) * sizeof(codeunit_type(fr))
    bytes ≤ EAGER_BYTES[]     (default 256 KiB)  → build now
    bytes ≤ ADAPTIVE_BYTES[]  (default 2 MiB)    → build once the signature has
                                                   seen BUILD_ELEMS[] elements
    otherwise                                    → nothing; compute per element
```

Consequences, all good:

- K ≤ 8 behavior is **unchanged**: every unary (≤ 256 B) and binary (≤ 64 KiB)
  table falls in the eager band, and the existing ternary bands are expressed
  in bytes rather than bits with the same effective thresholds.
- K = 16 unary tables (128 KiB) are eager; K = 16 binary tables are never
  built; the interesting middle (e.g. two K = 11 operands → 4 MiB) lands in
  the adaptive band and earns its table only under real load. Exactly the
  intended behavior, obtained by *removing* a code path rather than adding one.
- The table element type becomes `Memory{U}` for `U = codeunit_type(fr)`; the
  Shape-A gather in `kernels.jl` changes one type annotation.

**Two additions specific to wide K:**

*Build cost, not just build size.* A K = 16 unary `Exp` table is 65 536 trips
through the oracle, each potentially an MPFR ladder — plausibly seconds, spent
inside a first array call, holding no lock (builds already run outside the
lock, [`tables.jl:128-137`](../../src/tables.jl#L128-L137)). Two mitigations,
both cheap: (a) **build tables in parallel** — the builder is a pure function
of the code point, so `Threads.@threads` over the index space is trivially
correct and turns seconds into tens of milliseconds; (b) gate the eager band on
an estimated cost `entries × opcost(group)` in addition to bytes, so Group :B
and :C transcendentals at K ≥ 14 need the adaptive counter's evidence before
paying. Neither changes a single result — invariant 6 holds because every entry
still comes from one trip through the oracle-backed scalar path.

*Report it.* `table_bytes()` should gain a companion that names what was
declined, so "this signature is running the compute kernel" is discoverable
rather than inferred from a benchmark.

### 5.6 `kernels.jl` — array kernels

Shape A generalizes by changing `Memory{UInt8}` to `Memory{U}` and letting the
index arithmetic run in `Int` (already true). Shape B is carrier-agnostic
already, since it calls `apply_op` on decoded operands.

The only structural change: **Shape A must become conditional at every arity**,
mirroring the ternary method's existing `tbl === nothing` branch
([`kernels.jl:66-88`](../../src/kernels.jl#L66-L88)). The unary and binary
methods currently assume `get_table` succeeds. After §5.5 they take the same
two-branch shape, and — since that branch already exists and is already
threaded and tested for ternary — this is a copy of a proven shape, not a new
design.

`decode!` ([`kernels.jl:168-183`](../../src/kernels.jl#L168)) gains a
carrier-typed method set: `decode!(::AbstractArray{Float64}, ::AbstractArray{F})`
stays valid only where `datumtype(F) == Float64`, and must *throw* (not
silently round) for Group B/C. The `Float128` and `Dyadic` twins are new
methods with the same body.

### 5.7 `blocks.jl` — where the factor count bites

`blockdecode` computes `ωMultiply(decode(s), decode(xᵢ))` lanewise
([`blocks.jl:45-48`](../../src/blocks.jl#L45)) with a `::Float64` assertion.
This is the site where the naive per-format carrier rule fails and the
factor-count rule earns its keep: a `ScaledMultiply` forms
`s₁·x₁·s₂·x₂` — four datum factors — so a Group A element format with B = 512
combined with a Group A scale format with B = 512 gives ΣB = 2048 and
**overflows Float64**, even though every operand is individually Group A.
Verified by exact rational arithmetic: `MaxFinite(P=8, B=512)^4 > floatmax(Float64)`.

Therefore:

- `headtype` must take the *operation* and *all* participating formats,
  including block scales (§5.4). A block path's rung can be one or two rungs
  above the rung any of its operand formats would take alone.
- `blockdecode`'s `::Float64` assertion becomes `::headtype(...)`.
- The reduction accumulator precision ("wide-precision accumulator ... chosen
  from the operand structure ⇒ provably exact",
  [`blocks.jl:17-18`](../../src/blocks.jl#L17)) must add `log₂(B_blocksize)`
  to the derived precision and read the same `bigprec` used in §5.4 — one
  precision policy, not two.

At K ≤ 8 the rule changes nothing (worst case ΣB = 512), which is the required
non-regression.

### 5.8 `packed.jl` — sub-byte storage becomes sub-word storage

Mechanically small: `_codemask(K)` already returns a `UInt64` and is correct to
K = 63; `_wordpos` is already K-generic; `getindex`'s `UInt8(c & mask)` becomes
`U(c & mask)`. An element spans at most two 64-bit words for any K ≤ 64, so the
splice logic is unchanged.

The *policy* changes: packing is a win only when K is not a multiple of the
storage unit. For K ∈ 9:15 the win is real (`Binary12p7se` packs 12/16 = 75% of
`UInt16` storage); at K = 16 packing is the identity and `PackedVector` should
either refuse or degenerate to a plain `Vector` — refusing loudly is better,
since a silent identity invites benchmark confusion. The `_PACK_TILE = 256`
unpack tile stays as-is; the tile buffer just holds a wider element type.

### 5.9 `approx.jl` — κ under wide K

No mechanism change needed (§2). Three notes:

- The exhaustive/sampled boundary now bites: at K = 16, binary specializations
  are sampled and `conformance_report` will print "(κ sampled — not
  exhaustive)" ([`approx.jl:335`](../../src/approx.jl#L335)). That is the
  system working, and it is the reason invariant 5 says *measured*, not
  *proved*.
- `max_exhaustive = 2^22` should probably rise (a 2^22-point sweep of a cheap
  op is seconds), but it must remain a *budget*, and raising it must not be
  confused with widening a guarantee.
- The `_mixed_radix_codes` linear index ([`approx.jl:27`](../../src/approx.jl#L27))
  packs arity-3 K = 16 signatures into 48 bits — fine in `Int64`, but the
  `total` computation should be checked for overflow at arity 3, K = 16
  (2^48 points), where the sampled path is the only sane one anyway.

### 5.10 `rand.jl` — a reachability statement, not a change

`rand(T)` draws a 53-bit `Float64` uniform on [0,1) and floor-projects
([`rand.jl:34`](../../src/rand.jl#L34)); the draw width is part of the defined
distribution. For a format whose subnormals reach 2^-32767, the overwhelming
majority of datums are unreachable by that draw. This is already true at K ≤ 8
(`Binary8p1u`'s 2^-127 datums are unreachable) and is not a new defect — but at
K = 16 it becomes the *typical* case for Group B/C rather than an edge case, so
it must be documented at the function, not left to be discovered. No code
change is proposed: changing the draw width would change an observable
specification for existing users.

### 5.11 The `Float32`/`BFloat16` surface must become gated

[`formats.jl:218`](../../src/formats.jl#L218) states `Float32(v::Binary)` is
exact for every format and backs it with an exhaustive test — true at K ≤ 8,
false from K = 9 onward. `Float32` has emax 128 and its subnormals bottom out
at 2^-149, so the datum-exactness condition is `B ≤ 128` and `2−P−B ≥ −149`.
The same bound applies to `BFloat16` (same exponent range) with the extra
significand condition `P ≤ 8`.

Do **not** remove the conversions — narrowing is a legitimate rounding — but:

- add a trait `f32_exact_datums(F)::Bool` (analogous to the existing
  `f32_exact` compute trait in [`tables.jl:236`](../../src/tables.jl#L236)),
- keep `_decode_table32` only for K ≤ 8 (it has the same 2^K tuple problem),
- change the exhaustive test from "all formats" to "all formats where the trait
  holds, and a round-trip inequality witness for a format where it does not" —
  so the *boundary* is tested, not just the interior.

The existing `f32_exact` compute trait ([`tables.jl:236`](../../src/tables.jl#L236))
enumerates `2^K1 × 2^K2` pairs against a 300-bit oracle: at K = 16 that is 2^32
pairs and must acquire the same budget/sampling discipline as `measure_kappa`,
or be restricted to K ≤ 11 by construction.

**Decide `f32_exact`'s future before extending it.** It is exported, memoized,
and enumeration-backed, but it has **no consumer in `src/`** (§4.1): the
stochastic SIMD loop it was built to gate was never written, so it is
currently a fact-provider for external callers only. Extending an unconsumed
trait across 384 new formats — each answer costing up to 2^32 BigFloat
comparisons — is the wrong default. Three options, in preference order:
(a) leave it defined and *restrict its domain to K ≤ 11 by construction*, so
it stays cheap, stays honest, and stays available to the callers it already
has; (b) build the consumer, at which point its cost is justified by a
measured win; (c) deprecate it. Do not silently widen it to K = 16 and let the
first caller discover the cost. Note that at K ≥ 9 the trait's *premise* also
narrows sharply: `Float32` stops being datum-exact once `B > 128`, so
`f32_exact` can only ever return `true` for the high-P corner of the wide
grid, which is a further argument for (a).

### 5.12 Naming, exports, precompilation

- The alias-generating loop ([`formats.jl:136`](../../src/formats.jl#L136))
  extends from `3:8` to `3:16` and produces all 504 names. Keep the loop as the
  single spelling of the grid.
- **Export policy.** Exporting 504 symbols is legal and costs little, but it
  makes `using SmallFloats` a large namespace claim. Recommendation: export the
  120 K ≤ 8 names (unchanged, no breakage) plus a documented, discoverable path
  for the rest — `SmallFloats.Formats` as a submodule re-exporting all 504, so
  `using SmallFloats.Formats` is an explicit opt-in. Provide
  `format(K, P, Σ, Δ)` returning the concrete type for programmatic use, which
  is what the test harnesses and the benchmark suite actually want.
- The precompile workload ([`SmallFloats.jl:157-177`](../../src/SmallFloats.jl#L157))
  should stay K ≤ 8 for the tier-1 entries and add exactly one Group A wide
  format and one Group B format, so the wide code paths are compiled but the
  image does not grow with the grid.

### 5.13 Invariant 2 restated: what counts as a code point

This is the one user-visible semantic decision in the plan, so it is settled
here rather than left to §12.

**Why the current spelling cannot survive.** Invariant 2 reads:

> `UInt8` is the one argument type meaning *code point*; every other `Real`
> means *value*. `T(0x08)` and `T(8.0)` are different things by design.

The *content* of that invariant is **the meaning of an argument type must not
depend on the format**. The *spelling* couples that meaning to a concrete type,
`UInt8`, which was unambiguous only because there was exactly one storage
width. With two widths the spelling and the content come apart, and there are
three candidate resolutions.

| candidate | `Binary12p7se(0x08)` (a `UInt8`) | verdict |
|---|---|---|
| **R1** meaning follows the *format's* unit: `UInt8` is a code point at K ≤ 8 and a *value* at K ≥ 9 | value 8.0 | **catastrophic** — the same literal silently means two different things depending on a type parameter. Exactly what invariant 2 exists to prevent. |
| **R2** strict: only `codeunit_type(F)` is a code point; other widths throw | `ArgumentError` | safe but wrong-shaped — see below |
| **R3** uniform: **every `Unsigned`, at any width, is a code point**, range-checked | code point 8 | **recommended** |

**R3 is the correct restatement, and it supersedes the strict-throw suggestion
made earlier in this document's own summary.** The reasoning:

- R3 restores the invariant's content exactly. Under R3 the sentence becomes
  *"`Unsigned` is the argument-type class meaning code point; every other
  `Real` means value"* — and that sentence is true at every K, with no
  parameter-dependent clause. R2's sentence is *"the format's own code unit
  means code point"*, which is a format-dependent rule about **acceptance**;
  it trades one K-dependence for another.
- R2 breaks generic code for no gain. A helper written `f(::Type{F}, c::UInt8)`
  — of which this repository's own test harnesses have several, e.g.
  [`runtests.jl:1145`](../../test/runtests.jl#L1145) — works today for all 120
  formats and would need a per-format cast under R2 while continuing to work
  unchanged under R3.
- The safety R2 appears to buy is already provided by the existing range check
  (`Int(x) < (1 << K)`, [`formats.jl:22`](../../src/formats.jl#L22)). Widening
  an `Unsigned` is lossless, so the only way a wrong-width argument can be
  wrong is by being out of code range — which throws under both R2 and R3.
  R2 rejects a strictly larger set of *correct* programs and no additional
  incorrect ones.
- Julia's literal typing makes R3 ergonomic rather than merely tolerable: hex
  literal width follows digit count, so `0x08` is `UInt8` and `0x0008` is
  `UInt16`. The natural spelling at each K already produces the format's own
  unit; R3 simply means the unnatural spelling is still *right* instead of an
  error.

**Restated invariant (drop-in replacement for CLAUDE.md invariant 2):**

> **2. Code point vs value.** `Unsigned` is the one argument-type class meaning
> *code point*, at every bitwidth and for every format; every other `Real`
> means *value*. `T(0x08)` and `T(8.0)` are different things by design, and
> `T(8)` is the value 8.0 — signedness of the integer type is what
> distinguishes them. A code-point argument is range-checked against `2^K`
> regardless of its width. The format's storage unit, `codeunit_type(T)`
> (`UInt8` for K ≤ 8, `UInt16` for 9 ≤ K ≤ 16), is the type `codepoint` returns
> and the type `rawvalue` — the unchecked kernel route — requires; it is an
> implementation detail of the *representation*, never of the *meaning*.

**Consequences to implement:**

1. `(::Type{T})(c::Unsigned)` replaces `(::Type{T})(c::UInt8)`
   ([`formats.jl:57`](../../src/formats.jl#L57)); the body converts to
   `codeunit_type(T)` after the range check. `Unsigned` is more specific than
   `Real`, so dispatch against `(::Type{T})(x::Real)` resolves without a new
   ambiguity, and the existing `Rational` disambiguator is untouched.
2. `rawvalue(::Type{F}, c)` keeps requiring the exact unit. It is the kernel
   contract, not the user API, and every internal caller has the unit in hand.
3. **`codepoint(v)` now returns `codeunit_type(typeof(v))`.** For K ≤ 8 that is
   still `UInt8`, so no existing program changes; for K ≥ 9 it is `UInt16`.
   Code that annotates `codepoint(v)::UInt8` is writing a K ≤ 8 assumption and
   should say so.
4. `show` prints the code with `pad = 2 * sizeof(codeunit_type(T))` instead of
   the hard-coded `pad=2` ([`formats.jl:167`](../../src/formats.jl#L167)), so a
   K = 12 value prints `0x0abc`, not `0xabc`. Round-tripping the printed form
   through the constructor must produce the same value — that is a test, not a
   hope.
5. **The `convert`/constructor asymmetry becomes twice as important and must be
   documented.** `Binary8p4se(0x02)` is code point 2, while
   `convert(Binary8p4se, 0x02)` is the *value* 2.0, because `convert` must be
   value-preserving (promotion and `similar`/`fill` depend on it) while a
   constructor may reinterpret. This asymmetry exists today
   ([`formats.jl:231`](../../src/formats.jl#L231)) and is a legitimate Julia
   pattern, but it is currently undocumented. With two storage widths and 504
   formats it will be tripped over; write it down at both methods.

**Tests that pin it** (all cheap, all exhaustive):

- for every format and every code `c < 2^K`: `codepoint(T(c)) == c` where `c`
  is offered as *each* of `UInt8` (when in range), `UInt16`, `UInt32`,
  `UInt64` — the width-independence of meaning, stated as an assertion;
- for every format: `T(oftype(...))` of an out-of-range code throws, at every
  offered width;
- for every format: `T(2) == T(2.0) != T(0x02)` unless code point 2 happens to
  decode to 2.0 — the signed/unsigned meaning split, enumerated rather than
  spot-checked;
- `parse ∘ show` round-trip on the printed hex code, all formats, all codes;
- `convert(T, 0x02) === T(2.0)` — the asymmetry, asserted so it cannot be
  "fixed" by accident.

---

## 6. Group C in detail: `Dyadic` versus `BigFloat`

Group C (8 formats) needs a carrier with an unbounded exponent. Two options.

**Option C1 — `BigFloat` throughout.** Zero new machinery: `decode` returns
`BigFloat`, `project` already has a `BigFloat` method with a precision-raising
function barrier ([`project.jl:144-145`](../../src/project.jl#L144)), and the
whole `EncloseF` ladder is MPFR-native. Cost: every scalar operation allocates,
so Group C leaves the zero-allocation regime; latency is microsecond-class even
for `Add`.

**Option C2 — a `Dyadic` carrier for arithmetic, MPFR for transcendentals.
Recommended.**

```julia
"""Exact dyadic value sign·S·2^Q. Represents every datum of every format at any
K exactly, with no exponent limit; isbits, so allocation-free."""
struct Dyadic <: Real
    S::Int128       # value = S · 2^Q, sign carried in S
    Q::Int64
    kind::UInt8     # DY_FINITE | DY_POSINF | DY_NEGINF | DY_NAN
end
```

> **Two fields became three.** This sketch carries no non-finite rows, and that
> is the one thing the option comparison below gets wrong: the ω-semantics
> catalog produces NaN and ±∞, a dyadic rational cannot spell either, and
> encoding them as `(S, Q)` sentinels puts a special case in every kernel's fast
> path. [doingtheextensions.md](doingtheextensions.md) §5 added the tag; Stage 7
> shipped it **last** rather than first, because `S` needs 16-byte alignment and
> a leading `UInt8` costs 15 bytes of padding — 40 bytes against 32. Nothing
> else in this option's argument depends on the field count.

Why this is the better fit for *this* codebase specifically:

- **The engine already speaks this language.** `Rounded` is
  `(kind, sign, S::Int64, Q::Int64)` ([`project.jl:15-20`](../../src/project.jl#L15))
  and `saturate` works entirely in `(S, Q)` space. A `Dyadic` input to
  `round_to_precision` is *simpler* than a float input: the target quantum is
  `Q_t = max(Q + nbits(S) − 1, 1 − B) − P + 1`, the kept significand is
  `S >> (Q_t − Q)`, and the shifted-out bits **are** ν as an exact fixed-point
  fraction — no `ldexp`, no `floor`, no ν-exactness argument. It is closer to
  the existing `_rtp_f64` fixed-point family than to `_rtp_core`.
- **Multiply is exactly closed.** `(S₁·S₂, Q₁+Q₂)`, and `S₁·S₂ < 2^32` since
  `P ≤ 16` — no widening, no overflow, no proof debt.
- **Add reuses the existing sticky machinery.** When `|ΔQ| ≤ 100` the aligned
  sum is exact in `Int128`; when `|ΔQ|` exceeds `P + N + 2` (N = stochastic
  random bits, ≤ 60) the smaller term is strictly below the finest sub-grid
  unit and contributes only its sign — which is precisely `StickyF`'s existing
  contract and soundness argument
  ([`ops_scalar.jl:30-43`](../../src/ops_scalar.jl#L30-L43)), restated with
  `ΔQ` in place of a binade spread. Nothing new is proved; an existing proof is
  reused with a wider variable.
- **Allocation-free**, so Group C keeps the package's headline property rather
  than carving out an exception to it.

Transcendentals stay on MPFR in both options — `EncloseF` closures take a
precision and return directed bounds, and MPFR's exponent range (±2^62) covers
every P3109 format at any K anyone will build.

**Assessment.** C2 is more code than C1 (a fourth `round_to_precision` method
and a small arithmetic module) for a tier of 8 formats. If the goal is
*shipping Group C at all*, C1 is a one-week answer and is honest. If the goal
is a uniform story — and there is a real argument that `Dyadic` is the *right*
carrier for the whole wide-K project, since it makes exactness a type-level
property instead of a per-format range analysis — C2 pays for itself. **Ship
C1 first behind the `datumtype` trait, then swap in C2 without touching a call
site**, since the trait is the only thing any other layer consults. That
sequencing is the actual recommendation: the trait makes the choice reversible.

---

## 7. Options considered and rejected

| option | why rejected |
|---|---|
| **One storage type, `UInt16` everywhere** | doubles the memory of every K ≤ 8 array and destroys the packed-storage story, which is a stated purpose of the package |
| **Fifth type parameter for storage (T1)** | `Binary{8,4,true,true}` stops being concrete; breaks `similar`, `eltype`, and user code that does not use the aliases |
| **Parallel `WideBinary` type (T2)** | violates invariant 7: every registry-generated family would need two instantiations, and divergence would be invisible |
| **Float32 as a wide-K carrier** | already settled in [Float32inside.md](Float32inside.md); K ≥ 9 makes it worse, not better — `Float32` is not even a *datum*-exact carrier once B > 128 |
| **Raise `_BIGP` to a larger constant** (e.g. 70 000) | makes every escalation on every format pay for the worst format in the grid; the precision must be derived, and deriving it is three lines |
| **Keep unconditional unary/binary tables and cap K at 12** | an arbitrary cap that the draft does not have; the unified byte-budget policy (§5.5) is strictly simpler than the split policy it replaces and needs no cap |
| **Extend the enumerate-everything test doctrine to K = 16** | 2^32 assertions per binary specialization; the doctrine must be restated (§8), and restating it honestly is better than quietly sampling |
| **Support K ≤ 32 or arbitrary K now** | K = 16 covers every format anyone has proposed and keeps the storage unit story to two cases; the traits introduced here (`codeunit_type`, `datumtype`, `headtype`) are the extension points if K ≤ 32 is ever wanted, and they are the same three functions |

---

## 8. Testing doctrine under wide K

### 8.1 What the current doctrine actually is

> "It **enumerates rather than samples** — the value sets are small enough that
> sampling is never necessary. Preserve that property in new tests."
> — [CLAUDE.md](../../CLAUDE.md)

Read precisely, this is not a value judgment but a **theorem with a
hypothesis**: *for K ≤ 8, the input space of every specialization is at most
2^24 points, therefore exhaustive enumeration is affordable, therefore sampling
is never necessary.* The conclusion is inherited from the hypothesis, and the
hypothesis is `K ≤ 8`. At K = 16 a same-format binary specialization has 2^32
input pairs and a ternary one has 2^48; the theorem's conclusion simply does
not follow any more.

The wrong response is to keep the sentence and quietly sample underneath it.
The right response is to **find the largest sub-claim that is still a theorem**
and state it, then name — precisely, in one place — what is left over and how
it is covered. That is what follows.

### 8.2 The factorization that preserves most of the guarantee

K enters the implementation in far fewer places than the format count
suggests. Tracing the engine:

| stage | its actual parameter domain | K-dependent? | exhaustive cost |
|---|---|---|---|
| `round_to_precision` ([`project.jl:36`](../../src/project.jl#L36)) | `(P, B, μ, X, R, sticky)` | **no** | 252 distinct `(P, log₂B, Σ)` tuples over the whole K ∈ 3:16 grid |
| `saturate` ([`project.jl:277`](../../src/project.jl#L277)) | `(P, B, Σ, Δ, ρ, Rounded)` | **no** — reads `_extremal_SQ`, itself `f(P,B,Σ,Δ)` | same 252, × a small structured `Rounded` set |
| `encode` / `decode` | `(K, P, B, Σ, Δ, code)` | **yes** | 2^K per format |
| order keys, `Next*`, `Class`, sort | the code lattice | **yes** | 2^K per format |
| `ωeval` | operand datum tuples | only via the datum sets | 2^(ΣKᵢ) per specialization |

Two consequences, both measured rather than estimated:

**(a) The engine stages are cheaper to cover completely at K ≤ 16 than they
are today at K ≤ 8 — because their domain is smaller than the format grid.**
There are **252** distinct `(P, log₂B, Σ)` parameter tuples across all 504
formats (many formats share one: `Binary8p3se` and `Binary9p4se` both have
B = 16, and the engine cannot tell them apart because it never sees K).
Enumerating the engine over its own domain therefore covers *every* format by
construction, and does so with half as many parameter settings as there are
formats. This is not a weakening of the doctrine; it is a strengthening, and
it should be adopted for K ≤ 8 as well.

**(b) The K-dependent stages stay fully exhaustive and cost about what the
suite already costs.** Summing 2^K over all 504 formats:

| K | 3–8 | 9–11 | 12–14 | 15 | 16 | **total** |
|---|---|---|---|---|---|---|
| code points | 13 296 | 142 336 | 1 482 752 | 1 900 544 | 4 063 232 | **7 602 160** |

7.6 M lattice points across the entire 504-format grid, against a suite that
already runs ~8.9 M assertions. **The full code-lattice sweep at every K is
affordable in the shipped suite and must stay exhaustive.** (An earlier draft
of this document estimated 25 M; the measured figure is 7.6 M.)

**What is left over** is exactly one thing: the **composition** `ωeval ∘
project` over multi-operand input spaces at K ≥ 12. Both halves are covered
exhaustively over their own domains, so the residual risk is not "a rounding
mode is wrong" — it is "an escalation *decision* is wrong for an operand pair
nobody enumerated". That is a sharp, bounded risk, and §8.5's structured edge
set is aimed directly at it.

### 8.3 The tiers

| tier | scope | policy | budget |
|---|---|---|---|
| **T1 lattice** | decode/encode round-trip, order-key monotonicity, `Next*`, `Class`, special codes, `show`/parse round-trip | **exhaustive, every format, every K** | 7.6 M points |
| **T2 engine** | `round_to_precision`, `saturate`, `encode` preconditions | **exhaustive over `(P, log₂B, Σ, Δ, μ, sat)` × a structured carrier-value set**, format-free | 252 parameter tuples × 27 ρ |
| **T3 composition** | `ωeval ∘ project`, per specialization | exhaustive to a stated point budget (2^22 ⇒ binary exhaustive through K = 11, ternary through K = 7) | 2^22 points |
| **T4 edges** | specializations above the T3 budget | structured edge set (§8.5) + fixed-seed random, **reported as sampled** | fixed |
| **T5 differential** | rung selection, MPFR-only configuration, `refimpl` | always on, boundary-targeted | small |

`test/refimpl.jl` — the `Rational{BigInt}` reference that "shares no code with
the engine under test" — is the natural T2 oracle precisely because it is
carrier-independent. It is currently manual-only; **promote its
`ωRoundToPrecision`/`ωSaturate`/`ωEncode` comparison into the shipped suite as
T2.** Wide K is the reason it stops being optional: it is the only oracle in
the repository whose validity does not depend on a carrier being wide enough.

### 8.4 Two sampling dimensions, not one

The doctrine as written addresses only the *input* space. Wide K forces the
*specialization* space into view as well: 51 operations × 504 result formats ×
operand formats × 27 projection specifications. Even restricted to same-format
signatures that is ~694 k specializations, against ~165 k today.

The suite already samples this dimension — `allfmts` sweeps sit alongside
hand-picked representative sets such as
`(Binary8p4se, Binary8p1uf, Binary5p2se, Binary3p1se)`
([`runtests.jl:1011`](../../test/runtests.jl#L1011)) — but the selection is
implicit in the harness structure. Wide K makes it necessary to state it:

- **Format selection must be derived, not hand-listed.** The representative set
  should be *computed* from the grid: for each (group, rung-boundary
  proximity, P-extreme, Σ, Δ) cell, take the format that maximizes B. A
  hand-listed tuple of four names cannot track a 504-format grid, and a
  hand-listed tuple that silently stops covering a new group is the most
  likely way this extension ships a hole.
- **Every ρ family must appear at every rung.** The stochastic families are
  the ones whose correctness depends on carrier precision at the sub-grid
  level, so "stochastic × Group B" and "stochastic × Group C" must be
  explicitly present, not left to a random draw.
- **The full cross-product is the opt-in sweep**, not the shipped suite.

### 8.5 The five standing gates

Four are new; G5 is a non-regression rather than new coverage, and is listed
because it is the gate that makes M1 shippable.

**G1 — `_DE_*` threshold gate.** *Protects:* the generalization of the
Float128 exactness-by-width thresholds (§5.4).
*Domain:* all `P ≤ 16` triples. *Assertions:* (i) fixed point at today's
values — `_DE_ADD(8,8) == 100`, `_DE_FMA(8,8,8) == 92`, `_DE_FAA(8,8,8) == 98`
— so the refactor provably does not move K ≤ 8 behavior; (ii) positivity for
every `P ≤ 16`, so the Float128 rung never becomes empty; (iii) *soundness*:
for operand pairs constructed at a spread just below each threshold, the
Float128 result equals the MPFR result exactly. (iii) is the one that matters
— (i) and (ii) are arithmetic about the formula, (iii) is about the claim.

**G2 — `bigprec` sufficiency gate.** *Protects:* the latent truncation bug
that `_BIGP = 2200` becomes once B > 1024 (§5.4). *Witness:* the maximal-spread
operand pair of `Binary16p1uf` — `MaxFinite` (2^32766) and `MinPositive`
(2^-32767), spread 65533. *Oracle:* `Rational{BigInt}`, i.e. `refimpl`.
*Assertions:* `bigprec(...)` exceeds the required `spread + max Pᵢ + 1`, and
the BigFloat sum computed at that precision equals the exact rational sum.
This gate must fail loudly against the current constant — write it before the
fix, watch it fail, then fix. A precision-truncation bug is invisible to every
other test in the suite because a truncated result is a plausible result.

**G3 — `_rtp_f64` bit ≡ generic gate, widened.** *Protects:* the bit path's
shift bounds, derived for `d ≤ P−1 ≤ 7` and now claimed for `P ≤ 16` (§5.3).
*Domain:* the full `(P ≤ 16, B ≤ 512, μ)` grid — a T2-shaped enumeration, not
a per-format one — crossed with a structured Float64 input set (binade edges,
subnormal boundaries, exact ties, ties ± 1 ulp, the format's own extremal
datums). *Assertion:* `_rtp_f64 ≡ _rtp_core`, field for field. The existing
gate is the right shape; only its parameter domain widens.

**G4 — rung-selection equivalence gate.** *The central gate; it is what
protects this document's main claim.*
*Statement:* for a specialization whose selected rung is `r`, evaluating the
same operands with the carrier forced to rung `r+1` (and `r+2` where defined)
must produce the **identical code point**.
*Validity:* rung `r+1` is a strictly wider exact carrier over the same monomial
domain. If `headtype`'s selection is sound, both evaluations are exact and
project identically; if it is unsound — the monomial over- or underflows at
rung `r` — they differ. The gate is therefore precisely a soundness test for
`headtype`, and it needs no reference implementation.
*Domain, boundary-targeted rather than random:* (i) every format whose ΣB sits
within one power of two of a rung boundary (ΣB ∈ {512, 1024, 2048} and
{8192, 16384, 32768}) — this is where a wrong inequality shows up; (ii) all 8
Group C formats; (iii) every block/scaled operation, where the factor count
raises ΣB above what any single operand format would suggest (§5.7) — the
`ScaledMultiply` four-factor case is the one the naive per-format rule gets
wrong, so it must be in the gate, not in a comment; (iv) a fixed-seed sample
of the interior; (v) pure **and** stochastic ρ with an explicit `R`, since a
carrier-precision difference manifests on the stochastic sub-grid before it
manifests anywhere else.
*Implementation note:* no production knob is required. `headtype` is a trait
and the internals accept carrier-typed operands, so the test calls
`ωeval(op, Float128(x), Float128(y))` directly. Do **not** add a runtime
rung-override switch for a test's convenience; it would become a way to reach
a wrong answer from user code.
*Relationship to the existing contract:* the
`ENV["SmallFloats_Float128"] = "disable"` dual-configuration CI job is the
rung-2-vs-rung-3 instance of exactly this gate. G4 generalizes it downward to
rung 1 vs rung 2 and makes it boundary-targeted. Once Group B exists, that CI
job is no longer confirmatory — it is the only thing standing between a Group B
default path and an unverified MPFR fallback — and it should be re-labelled
accordingly.

**G5 — K ≤ 8 golden non-regression.** *Protects:* the promise that this
extension changes nothing for existing users. *Method:* a stored golden file of
code points produced by the current release over the existing exhaustive
harnesses, compared byte-for-byte after the refactor. Not a re-derivation —
re-deriving with the new code proves only that the new code agrees with itself.
This is the M1 exit criterion and should ship as a standing gate, because the
storage-type refactor (§5.1) touches every layer.

### 8.6 What is knowingly not covered

Stated once, plainly, so it is not rediscovered as a surprise:

- Multi-operand input cross-products above 2^22 points for K ≥ 12 — covered by
  T4's structured edges and seeded random, reported as sampled.
- κ for binary and ternary specializations at K ≥ 12 — `measure_kappa` already
  reports `exhaustive = false` and `conformance_report` already prints
  "(κ sampled — not exhaustive)" ([`approx.jl:335`](../../src/approx.jl#L335)).
  No mechanism change; the honesty is already built in.
- `f32_exact`'s enumeration ([`tables.jl:236`](../../src/tables.jl#L236)) at
  K ≥ 12, which must acquire the same budget discipline or be restricted to
  K ≤ 11 by construction (§5.11).

The T4 edge set must be **derived from the thresholds in the source**
(`_DE_*`, `bigprec`, the rung boundaries, the saturation thresholds) rather
than hand-listed, so that moving a threshold moves the edges that test it. A
hand-listed edge set silently stops testing the thing it was written for the
first time someone tunes a constant.

### 8.7 Wall clock

| suite | contents | intent |
|---|---|---|
| `Pkg.test()` | T1 (full, 7.6 M), T2 (full, format-free), T3 within the 2^22 budget, T4, T5 boundary-targeted, G1–G5 | must stay in the same wall-clock class as today |
| `SmallFloats_EXHAUSTIVE=1` | T3 unbudgeted, full specialization cross-product, unbudgeted `f32_exact` and κ sweeps | nightly CI, decoupled from developer iteration |

The split is a *budget*, not a *guarantee change*: raising the budget must
never be described as widening a guarantee, and any suite output that reports
sampled coverage must say so in the same words `measure_kappa` already uses.

---

## 9. Performance expectations and how to measure them

| path | K ≤ 8 (today) | Group A, K 9–16 | Group B | Group C |
|---|---|---|---|---|
| scalar `Add` | ≈ 26 ns | ≈ 26 ns (2-byte unit, computed decode) | ~5–20× | MPFR: µs; `Dyadic`: ~2–4× |
| `project` | ≈ 13 ns | ≈ 13 ns | generic `_rtp_core` | integer-only, likely fastest of the three |
| array unary | table gather | gather ≤ 128 KiB table | same | same |
| array binary | gather ≤ 64 KiB | gather to ΣK ≤ 18, else compute | same | same |
| warm-path allocation | zero | zero | zero (`Float128` isbits) | zero with `Dyadic`; nonzero with `BigFloat` |

The benchmark suite's specialization preflight — which *aborts* rather than
publish numbers if warm scalar paths allocate — should gain per-group
expectations rather than one global gate, so a Group C `BigFloat` allocation is
a recorded property of that tier instead of a suite failure.

The two measurements that should decide open questions rather than be guessed:
(a) computed decode versus a cached decode table at K ∈ 9:12; (b) whether a
`_rtp_f128` bit twin is worth its permanent sync obligation for Group B.

---

## 10. Invariant review

| invariant | disposition under this plan |
|---|---|
| 1. One write path | Preserved. `project` remains the only producer of a code point; `encode`'s return type widens but nothing else creates one. The `Dyadic` path (§6) enters through `round_to_precision`, i.e. through the engine. |
| 2. Code point vs value | **Restated, not weakened — see §5.13.** The invariant's content is that an argument type's *meaning* must not depend on the format; the current spelling ties that meaning to `UInt8`, which was unambiguous only while there was one storage width. Resolution: **every `Unsigned`, at any width, is a code point** (range-checked against `2^K`); every other `Real` is a value. The format's storage unit `codeunit_type(T)` governs `codepoint`'s return type and `rawvalue`'s signature — representation, never meaning. Both alternatives are rejected in §5.13: meaning-follows-the-format is silently catastrophic, and strict-width-throwing trades one K-dependence for another while rejecting only correct programs. |
| 3. Representation invariant | Generalizes verbatim: low K bits hold the code, high bits of the unit are maintained zero. |
| 4. Stochastic ρ never tabulable | Untouched; the unified table policy keeps the loud rejection. |
| 5. Nothing approximate from the default API | Untouched, and reinforced: `measure_kappa` already reports non-exhaustive measurement honestly, so wide-K κ claims are weaker but not false. |
| 6. A table entry IS the defined result | Preserved. Parallel table building (§5.5) does not change what a builder computes; declining to build a table means running the same scalar path per element. |
| 7. Registry-driven codegen | Preserved and extended: `factors` becomes a registry column so block/scaled variants derive their carrier rung from the row that generates them. No hand-written per-format variants anywhere. |

Performance rules are unaffected in kind: format types still flow through
`const` bindings, type parameters, and function arguments; the new traits
(`codeunit_type`, `datumtype`, `headtype`, `reptype`) are pure functions of
type parameters and constant-fold, so a specialized call site sees literals.

---

## 11. Milestones

**M1 — the grid exists (largest single change).**
`Binary` becomes abstract with `Code8`/`Code16` representations (§5.1);
`checkformat` opens to 3:16; the alias loop generates 504 names; special and
extremal code points widen; computed decode for K ≥ 9 (§5.2); `encode`, order
keys, and the sort gate widen; `PackedVector` widens.
Also lands the restated invariant 2 (§5.13) — `Unsigned`-means-code-point,
`codepoint`'s widened return type, `show` padding — since it is a change to the
constructor surface and must not arrive after users have written against the
old one.
*Exit criterion:* **G5** (K ≤ 8 golden non-regression, §8.5) passes
byte-for-byte against a golden file captured from the current release *before*
the refactor begins; **G3** (`_rtp_f64` bit ≡ generic, widened to P ≤ 16)
passes; every K ≤ 10 format passes the full existing suite.

**M2 — tables and kernels.**
Unified byte-budget `_table_for` across all arities (§5.5); Shape A becomes
conditional at every arity (§5.6); parallel table build; `table_bytes`
companion reporting declined signatures.
*Exit criterion:* K = 16 unary array ops run on tables; K = 16 binary array ops
run on the compute kernel; no signature attempts an impossible allocation.

**M3 — rung selection (Groups B and C correct).**
`datumtype`/`headtype`/`factors` traits (§5.4); format-derived `bigprec`;
`_DE_*` as functions of P; `Float128`-headed `ωeval` arithmetic rows;
carrier-aware `promote_rule`; Group C on `BigFloat` behind the trait.
*Order within M3:* write **G2** (`bigprec` sufficiency) *first* and watch it
fail against `_BIGP = 2200` on the `Binary16p1uf` witness — a
precision-truncation bug is invisible to every other test, so the only proof
the fix was needed is a red test before it.
*Exit criterion:* **G1** (threshold fixed point + soundness) and **G4**
(rung-selection equivalence, boundary-targeted, including the four-factor
`ScaledMultiply` case and stochastic ρ with explicit `R`) pass; the
`SmallFloats_Float128 = "disable"` configuration produces bit-identical results
for Group B — now a load-bearing gate rather than a confirmatory one.

**M4 — test doctrine.**
The restated doctrine and its five tiers (§8.2–§8.3), derived rather than
hand-listed format selection and edge sets (§8.4, §8.6), `refimpl` promoted
from manual-only into the shipped suite as the T2 oracle,
`SmallFloats_EXHAUSTIVE` nightly sweep (§8.7), and the gated
`Float32`/`BFloat16` surface (§5.11). G1–G5 are written with the milestones
that need them (G3/G5 in M1, G1/G2/G4 in M3); M4 is what makes the *coverage
policy* explicit and machine-checked rather than implicit in harness structure.

**M5 — optional performance work, only if measured.**
`Dyadic` carrier replacing `BigFloat` for Group C (§6); `_rtp_f128` bit twin;
cached decode tables for K ∈ 9:12; K ≥ 9 decode bit-assembly fast path.

M1 and M2 are independent of M3 in the sense that they are correct for Group A
alone; a defensible intermediate release is "K ≤ 10 fully supported, K ≥ 11
constructible but only Group A operational". M3 is what closes the grid.

---

## 12. Open questions

1. ~~**Code-point constructor semantics (invariant 2).**~~ **Resolved in
   §5.13**, and resolved *against* this document's own first proposal. The
   earlier draft said the constructor should accept exactly
   `codeunit_type(F)` and throw otherwise; that was wrong twice over. It
   mis-stated the alternative (accepting any `Unsigned` does *not* make
   `T(0x08)` mean different things at different K — it makes the meaning
   uniform, which is the point), and it made *acceptance* format-dependent in
   order to make *meaning* format-independent, when the range check already
   available makes both possible at once. The rule is: **every `Unsigned` is a
   code point at every width, range-checked; every other `Real` is a value.**
   Recorded here rather than silently corrected, because the discarded
   proposal is the one a reader is most likely to re-invent.
2. **Export surface.** 504 exported names versus an opt-in `SmallFloats.Formats`
   submodule (§5.12). Recommendation stated; it is a taste call the package
   owner should make before M1, since it is hard to reverse.
3. **`PackedVector` at K = 16.** Refuse loudly, or degenerate to `Vector`?
   Recommendation: refuse, with a message pointing at `Vector`.
4. **Does Group B want its own bit-path projection?** Deferred to measurement
   (§9); the cost is a permanent third member of the twin-predicate family.
5. **`max_exhaustive` budget.** Whether to raise it, and whether the raised
   value belongs in `Preferences.jl` rather than a `Ref`.
6. **Whether `Dyadic` should eventually replace the float carriers entirely.**
   Not proposed here, but §6's argument suggests it is the simpler long-run
   design; the `datumtype`/`headtype` traits make that a later, local decision
   rather than a rewrite.
