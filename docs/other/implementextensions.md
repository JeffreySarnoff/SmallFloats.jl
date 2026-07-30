# Implementing the extensions — the execution plan for 3 ≤ K ≤ 16

*Status: execution document, written 2026-07-29 against the working tree of
`SmallFloats.jl` (branch `main`, `e1ea2aa`). Third and last of the chain:
[extendingK.md](extendingK.md) decides **what and why**,
[doingtheextensions.md](doingtheextensions.md) decides **how** at the
architectural level, and this document decides **what to type, in what order,
and what must be true before the next commit**. Ground truth remains
[IEEE_D1.md](IEEE_D1.md) (IEEE P3109/D1, July 2026).*

*Every numeric claim below was recomputed from the source tree or from the D1
formulas under Julia 1.12.6; the scripts and their outputs are in
[Appendix C](#appendix-c--verification-log). Where this document and its two
predecessors disagree, **this one wins**, and §1 says exactly why in each case.
No code has been changed and no tests have been run.*

---

## 0. How to use this document

§1 is the part that changes plans already made: ten findings from a
line-by-line audit of `src/`, seven of which are errors or gaps in the
inherited plan and three of which are new defects in the package. §2 revises
the design where the audit showed a simpler or safer construction. §3
consolidates the architecture as it now stands. §4 is the executable plan —
ten stages, each a single revertible commit with a named entry condition, a
numbered step list, and an exit gate. §5–§9 are the gates, the test doctrine,
the performance plan, the risks, and the four decisions the package owner must
make before Stage 2.

Three rules govern the whole exercise, and they are the reason for the staging:

1. **Every stage compiles and passes the suite.** A stage that leaves the tree
   red is a stage that was cut in the wrong place.
2. **No stage both refactors and extends.** The type refactor (Stage 2) adds no
   formats; the format extension (Stage 3) changes no types. This is what makes
   the K ≤ 8 golden a *complete* oracle for the refactor.
3. **A wide format never computes on a carrier that cannot hold its
   intermediates.** Between the stage that creates a format and the stage that
   gives it a carrier, its arithmetic must `throw`. Silence there is the exact
   failure mode this project exists to prevent.

---

## 1. Findings from the implementation audit

Ten findings. **C1–C7** correct the inherited plan; **C8–C10** are new
observations about the package or its repository. Each is stated with the
evidence that establishes it, because each contradicts something previously
written down.

### C1 — `_DE_FMA`'s generalization does not reproduce today's constant

[doingtheextensions §5.4 / extendingK §5.4](extendingK.md) generalize the
Float128 exactness-by-width thresholds as

```
_DE_ADD(P₁,P₂)    = 113 − (max(P₁,P₂) + 1) − 4
_DE_FMA(P₁,P₂,P₃) = 113 − (P₁ + P₂ + 1) − 3        # ← wrong
_DE_FAA(P₁,P₂,P₃) = 113 − (max(Pᵢ) + 3) − 4
```

and claim all three reproduce today's `(100, 92, 98)` at P = 8, making gate
**G1(i)** a fixed-point assertion. Evaluated: **(100, 93, 98)**. The FMA row
is off by one, so G1(i) as specified fails on the day it is written.

The source comment states the true accounting —
"17-bit exact product + 8-bit addend: **18** + ΔE ≤ 113, margin 3"
([`oracle.jl:39`](../../src/oracle.jl#L39)) — where 18 is `P₁ + P₂ + 2`
(product plus carry), not `P₁ + P₂ + 1`. The correct generalization is

```
_DE_FMA(P₁,P₂,P₃) = 113 − (P₁ + P₂ + 2) − 3        # = 92 at P = 8, 76 at P = 16
```

**Action:** use the corrected formula; keep G1(i) as a fixed-point assertion,
which now passes for a reason rather than by adjustment. This is the single
most valuable thing the audit found, because the failure mode of the wrong
formula is a *widened* exactness claim — an inexact Float128 sum accepted as
exact — which no other test in the suite can see.

### C2 — the sticky-head shortcut collides with the width threshold at P = 16

A finding with no counterpart in either predecessor. `StickyF`'s soundness
argument ([`ops_scalar.jl:30-43`](../../src/ops_scalar.jl#L30-L43)) has two
premises: the neglected tail must lie below (a) the head's distance to any
off-grid rounding threshold, and (b) **the finest stochastic sub-grid unit**,
which is `2^(e_head − (P−1) − N)` for an N-bit stochastic draw. Premise (b)
therefore requires

```
ΔE > (P − 1) + N + 2        ≡  _STICKY_MIN(P, N)
```

while the emitting site only checks `ΔE > _DE_op(P…)`, a *width* bound. The two
are independent, and at P ≤ 8 the width bound is the stricter one, so the
package is correct today and the collision is invisible:

| P | `_DE_FMA` | `_STICKY_MIN(P, 60)` | sound? |
|---|---|---|---|
| 8 | 92 | 69 | yes, margin 23 |
| 12 | 84 | 73 | yes, margin 11 |
| **16** | **76** | **77** | **no** |

Solving `108 − 2P ≥ P + 61` gives `P ≤ 15`. So exactly one cell of the widened
grid is affected: **FMA at P = 16 with N > 15 stochastic bits.** (`Add` needs
`P ≤ 23` and `FAA` needs `P ≤ 22`; neither can collide at K ≤ 16.)

**Action.** The sticky-head band starts at `max(_DE_op(P…), _STICKY_MIN(P, N))`,
and the interval between the two bounds — nonempty only in that one cell —
falls to the exact `BigExactF` path:

```
ΔE ≤ _DE_op                                     → Float128, exact by width
_DE_op < ΔE ≤ _STICKY_MIN                       → BigExactF (exact MPFR)
ΔE > max(_DE_op, _STICKY_MIN)                   → StickyF   (non-allocating)
```

At P ≤ 15 the middle band is empty and behavior is bit-identical to today, so
this is a generalization with a fixed point, exactly like C1. `N` is a type
parameter of the rounding mode, so the choice is made at compile time — but
`ωeval` does not see ρ, so **`N_max = 60` must be used at the emitting site**
unless ρ is threaded into `ωeval` (it should not be; see §2.6). Gate **G1** is
extended to assert *band contiguity*: for every `P ≤ 16` and every `N ≤ 60`, no
value of ΔE is left uncovered.

*Epistemic note:* the bit accounting above is read off the source comments
rather than re-derived from first principles. The formulas are the plan; **G1
is the proof**, and G1 must be written before the thresholds are touched.

### C3 — the exact-signature sweep is 29 sites in 5 files, not a `formats.jl` sweep

[doingtheextensions §5 Stage 2 (O12)](doingtheextensions.md) describes the
`::Type{Binary{K,P,S,E}}` → `::Type{<:Binary{K,P,S,E}}` migration as "a
mechanical but *total* sweep of `formats.jl`", naming the Group M family,
`formatname`, the special codes, and the extremal queries.

Measured: **29 sites across 5 files.**

| file | sites |
|---|---|
| [`formats.jl`](../../src/formats.jl) | 21 |
| [`decode_encode.jl`](../../src/decode_encode.jl) | 3 |
| [`defaults.jl`](../../src/defaults.jl) | 3 |
| [`tables.jl`](../../src/tables.jl) | 1 |

The four outside `formats.jl` are the dangerous ones, because a
`formats.jl`-scoped sweep will not visit them and each fails differently:
`_fkey` ([`tables.jl:24`](../../src/tables.jl#L24)) is the table cache key —
a `MethodError` on first array call; `_decode_table`/`_decode_table32`/`encode`
are on the hot path; and `defaults.jl`'s three are C4. The full enumeration
with per-site disposition is [Appendix A](#appendix-a--the-exact-signature-sweep).

### C4 — `DefaultType!` stores an *abstract* format, silently (new defect, A7)

The one genuinely silent wide-K defect the audit found, and it is not in any
prior inventory.

```julia
# defaults.jl:76-83
function _set_format_default!(ref, ::Type{Binary{K,P,S,E}}) where {K,P,S,E}
    checkformat(K, P, S, E)
    ref[] = Binary{K,P,S,E}          # ← rebuilds the format type (T1 violation)
end
DefaultType!(T::Type{Binary{K,P,S,E}}) where {K,P,S,E} = _set_format_default!(_DEFAULT_TYPE, T)
```

Two independent failures after D1:

1. `DefaultType!(Binary8p4se)` no longer dispatches — `Binary8p4se` becomes
   `Code8{8,4,true,true}`, which does not match the exact `::Type{Binary{…}}`
   pattern. A `MethodError` on the package's own documented entry point.
2. Worse, if the signature is repaired to `<:Binary` without also repairing the
   **body**, `ref[] = Binary{K,P,S,E}` stores the *abstract* format into
   `_DEFAULT_TYPE::Ref{Type{<:Binary}}`. That assignment **type-checks**, so
   nothing complains; the failure surfaces much later and much further away, as
   `similar(A, DefaultType())` producing a boxed array or an
   `isconcretetype` assertion failing in a benchmark.

This is invariant 8 ("format types are propagated, never rebuilt") with a live
instance, and it is the strongest available argument for making that invariant
grep-enforced rather than aspirational. **Action:** fix in Stage 2; add
`ref[] = reptype(F)` and a test asserting `isconcretetype(DefaultType())`.

### C5 — the "silent truncation" hazard class is empty; A1 is loud, not silent

[doingtheextensions §7 A1](doingtheextensions.md) grades
`rawvalue(argformats[i], UInt8(codes[i]))` ([`approx.jl:60`](../../src/approx.jl#L60))
as **severity: high — it truncates silently for codes ≥ 256, so κ would be
measured against the wrong inputs.**

It does not truncate. `UInt8(x)` in Julia is a *checked* conversion:
`UInt8(256)` throws `InexactError`. Silent truncation requires `x % UInt8` or
`unsafe_trunc`, and a grep of the whole source tree finds **zero** such idioms
in any K-dependent layer — the only two matches are `% UInt16` inside the
vendored [`faa128.jl`](../../src/faa128.jl#L133) and
[`fma128.jl`](../../src/fma128.jl#L140) Float128 bit decomposition, which is
carrier code and K-independent.

The same applies to every other `UInt8(...)` site in the package: the table
builders ([`tables.jl:93`](../../src/tables.jl#L93), `:104`, `:159`), the
counting-sort inversion loop ([`decode_encode.jl:143`](../../src/decode_encode.jl#L143)),
`f32_exact`'s enumeration ([`tables.jl:242`](../../src/tables.jl#L242)), and
`PackedVector`'s getindex ([`packed.jl:50`](../../src/packed.jl#L50)). Storing
a `UInt16` into a `Memory{UInt8}` likewise routes through a checked `convert`.
**Every one of them fails loudly on the first wide-K value.**

This materially changes three things:

- **A1 is a correctness bug of ordinary severity** (a `MethodError`-class
  failure at first use), not a silent-wrong-answer bug. It still must be fixed;
  it no longer heads the inventory.
- **Risk R2 drops from "medium" to "low".** The residual silent-failure surface
  is not `UInt8` conversion at all. It is exactly three things: **oversized
  shifts** (T11's real hazard — `UInt16(1) << 16 === 0x0000`, no error),
  **abstract-type stores through a `Ref{Type{<:…}}`** (C4), and **`Int`
  arithmetic that overflows a table-size computation** (bounded here: the
  largest is `1 << 48`, safe, but it must be asserted, not assumed).
- **Stage 3's test emphasis changes.** A sweep that merely *constructs* every
  code point of every K = 16 format will surface the whole checked-conversion
  class immediately and cheaply. That sweep is therefore the highest-value test
  in the plan per line written, and it belongs at the front of Stage 3, not the
  end.

### C6 — the engine's parameter domain is 135 tuples, not 252 — and `saturate`'s is 504

[extendingK §8.2](extendingK.md) claims **252** distinct `(P, log₂B, Σ)`
parameter tuples across all 504 formats, and that both `round_to_precision` and
`saturate` are covered by enumerating them — "the engine stages are cheaper to
cover completely at K ≤ 16 than they are today at K ≤ 8". The 252 figure is
correct as stated, but it is the wrong count for both stages:

| stage | parameters it actually reads | distinct tuples |
|---|---|---|
| `round_to_precision(P, B, μ, X, R, sticky)` | `(P, log₂B)` — **it never sees Σ or Δ** | **135** |
| `saturate(::Type{T}, ρ, r)` | `(P, log₂B, Σ, Δ)` via `_extremal_SQ` | **504** |
| — the 252 figure | `(P, log₂B, Σ)` | 252 |

So the good news is better than claimed for `round_to_precision` (135 tuples
covers 504 formats — a 3.7× saving, and only 3.9× today's 35 tuples for the
K ≤ 8 grid) and the claim is **false for `saturate`**, whose domain is exactly
as large as the format grid because Δ selects different saturation rows and Σ
selects `MinFiniteOf`. There is no saving there and none should be promised.

**Action:** state tier T2 as *two* enumerations with different domains — a
135-tuple sweep for the rounding stage and a 504-tuple sweep for saturation —
and drop the "cheaper than the grid" framing for the latter. The doctrine is
still a strengthening; it is just a smaller one than advertised.

### C7 — the `Dyadic` add bands: the arithmetic in §4.3 is internally inconsistent

[doingtheextensions §4.3 / O3](doingtheextensions.md) states the exact
`Int128` alignment band as `ΔQ ≤ 95` (127 bits minus a ≤ 32-bit head
significand), the sticky band as `ΔQ > P + N + 2 ≤ 78`, an overlap of
`[79, 95]`, and concludes "*at `N = 60`, `P` may grow to 45 before the bands
separate*".

With the document's own 32-bit head, the ceiling is `P ≤ 33`, not 45 — the 45
figure corresponds to a 20-bit head. And the alignment band itself must reserve
**one carry bit** for the sum, giving `ΔQ ≤ 127 − 32 − 1 = 94`, not 95.
Corrected:

```
exact Int128 alignment      :  ΔQ ≤ 94                (32-bit head + carry)
sticky (tail is sign only)  :  ΔQ > P + N + 2
total coverage              ⟺  P + N ≤ 92
current worst case          :  P = 16, N = 60  ⇒  76 ≤ 92,  margin 16
overlap band                :  ΔQ ∈ [79, 94]
```

The conclusion — the bands overlap with room to spare — is unchanged and
correct. What changes is the *margin*, which is the number a future widening
will be checked against, so it must be right. **Action:** the corrected
inequality `P + N ≤ 92` goes in a comment at the `Dyadic` add method and as a
static assertion in the suite, per the predecessor's own (good) instruction.

### C8 — `_cmp_rounded_datum` has no call site anywhere (new, A6)

[`project.jl:237-255`](../../src/project.jl#L237) is a careful 19-line
sign/msb-position/aligned-significand comparator with a written argument for
why it works when the result exceeds Float64's range. Grep of `src/` **and**
`test/` finds exactly one occurrence: its own definition.

[extendingK §2](extendingK.md) noticed it is "not on the `saturate` path" —
correct, and incomplete: it is on no path. It is the third unconsumed surface
after `f32_exact` (A3) and `DefaultAccumulatorType` (A4).

**Action.** It is the *only* dead code among the three whose logic wide K
actually wants — comparing a rounded `(sign, S, Q)` against an extremal datum
whose magnitude exceeds the carrier is precisely the Group C saturation
question. Two honest dispositions: delete it now and rewrite it against
`Dyadic` at Stage 7, or keep it and wire it into the Group C saturation path at
Stage 7. **Recommended: delete at Stage 1, reintroduce at Stage 7 if the
`Dyadic` saturation path needs it** — `saturate` is already pure `(S, Q)`
integer work and probably will not.

### C9 — the invariants this plan amends live in a file that is not in this repository

Both predecessors instruct "add to CLAUDE.md alongside the existing seven",
quote invariant 2 verbatim from it, and make "the CLAUDE.md rule" the authority
for the include-order comment and the enumerate-don't-sample doctrine.

There is no `CLAUDE.md`, `AGENTS.md`, or equivalent anywhere in the working
tree. The repository is a fresh copy (`e1ea2aa`, "copy from ByteFloats.jl") and
the doctrine file was not copied with it. The seven invariants survive only as
prose inside [`docs/src/technical_guide.md`](../src/technical_guide.md) and as
assertions in the suite.

This is a Stage 0 blocker, not a documentation nicety: **invariants 8, 9 and 10
have nowhere to be written, and the grep enforcement invariant 8 depends on has
nowhere to be declared.** Recompose the file from the surviving prose and the
suite before Stage 1, or the plan's central non-divergence mechanism has no
home.

Two smaller repository facts in the same class: `README.md` is two lines and
states no format count or bitwidth range (so it needs *writing*, not amending,
at Stage 9), and `docs/build_latex/` and `docs/pdf/` still carry
`ByteFloats.jl-0.1.0.tex` and `ByteFloats.pdf` — stale artifacts of the rename
that will otherwise be republished with a stale K range.

### C10 — the projection engine needs no carrier work at all

The most useful simplification in this document, and one both predecessors
obscure by routing everything through a single `datumtype` trait.

`project` and `round_to_precision` are **polymorphic in the carrier value `X`
and correct for any exact `X`, whatever the format's own datum range**:
`round_to_precision(P, B, μ, X, R, sticky)` works in `(P, B)` integer space and
touches `X` only through `exponent`, `ldexp`, `floor` and comparisons
([`project.jl:147-193`](../../src/project.jl#L147)). A `Float64` input
projected into `Binary16p1uf` (B = 32768) is exact and correct; the format's
enormous datum range never enters, because the *input value* is what has to be
representable, not the format's extremes.

Concretely, for all 504 formats, **with zero carrier work**:

- `Convert(fr, ρ, x::Float64 | Float32 | Float16 | Float128 | Integer | BigFloat)`
- `T(x::Real)`, `convert(T, x)`, and therefore `one(T)`, `zero(T)`, `eps(T)`
- `project`, `saturate`, `encode`, the whole write path
- every array `Convert` from an external float array

The carrier ladder is needed for exactly two things: **`decode`** (a datum
leaving the format must land in something that holds it) and **`ωeval`'s
intermediates** (a monomial in datums must not overflow the carrier). Scoping
it that way removes `project.jl` from the carrier work entirely — which is why
[extendingK §5.3](extendingK.md)'s surprising conclusion ("the projection
engine is the layer that needs the least work") is right, and why it deserves
to be stated as a *rule* rather than a happy observation:

> **The carrier is a property of values in flight, not of formats at rest.**
> A format's carrier constrains what `decode` returns and what `ωeval` may
> form. It never constrains what may be projected *into* the format.

---

## 2. Design revisions

Eight revisions. R-A is the largest and touches the technique doctrine
directly; R-B and R-C close correctness gaps; the rest are simplifications.

### R-A — traits by `Val`-barrier dispatch, not by code generation

**Supersedes D3 and merges T3 with T4.**

[doingtheextensions D3](doingtheextensions.md) emits every per-format trait as
a constant method from the alias loop — "504 × 5 = 2520 tiny methods" — on the
grounds that a computed type-valued trait (`K ≤ 8 ? Code8{…} : Code16{…}`)
infers a `Union` unless the compiler folds the comparison, and "usually folds"
is not a basis for a correctness-critical selection.

The premise is right; the conclusion overshoots. The package already has the
correct idiom, and doingtheextensions itself mandates it as **T4**: put the
computed condition behind a `Val` and dispatch.

```julia
@inline reptype(::Type{Binary{K,P,S,E}}) where {K,P,S,E} = _rep(Val(K <= 8), Binary{K,P,S,E})
@inline _rep(::Val{true},  ::Type{Binary{K,P,S,E}}) where {K,P,S,E} = Code8{K,P,S,E}
@inline _rep(::Val{false}, ::Type{Binary{K,P,S,E}}) where {K,P,S,E} = Code16{K,P,S,E}
@inline reptype(::Type{T}) where {T<:Code8}  = T           # concrete → itself
@inline reptype(::Type{T}) where {T<:Code16} = T
```

**Five methods, total, for the whole 504-format grid**, and each `_rep` method
has exactly one concrete return type, so there is no `Union` to infer and
nothing for the compiler to fold *in the result*. If `Val(K <= 8)` failed to
fold (it will not — `K` is a static parameter, the same mechanism as
`ntuple(f, Val(N))`), the cost would be a dynamic dispatch, not a type-unstable
value. **The `Val` barrier is strictly safer than the ternary D3 rejects and
strictly cheaper than the generation D3 proposes.**

The same shape covers the carrier rung, which depends on `(P, B)` rather than
on the representation seam:

```julia
@inline rung(::Type{F}) where {F<:Binary} = _rung(Val(_rungindex(F)), F)
@inline _rungindex(::Type{F}) where {F<:Binary} =                       # pure Int of static params
    (b = expbias(F); b <= 512 ? 1 : b <= 8192 ? 2 : 3)
@inline _rung(::Val{1}, ::Type{<:Binary}) = HeadF64()
@inline _rung(::Val{2}, ::Type{<:Binary}) = HeadF128()
@inline _rung(::Val{3}, ::Type{<:Binary}) = HeadExact()
```

**Where a policy boundary can be chosen to coincide with the representation
seam, choose it there** — then the trait is two methods with no `Val` at all:

```julia
@inline codeunit_type(::Type{<:Code8})  = UInt8
@inline codeunit_type(::Type{<:Code16}) = UInt16
@inline orderkeytype(::Type{<:Code8})   = UInt16          # 2^8  + 1 keys
@inline orderkeytype(::Type{<:Code16})  = UInt32          # 2^16 + 1 keys — uniform for K ≥ 9
@inline decodepolicy(::Type{<:Code8})   = TableDecode()   # 2^K ≤ 256 constant tuple
@inline decodepolicy(::Type{<:Code16})  = ComputeDecode()
```

Totals: **~15 trait methods instead of ~2,520**, no `@eval` in the trait path,
no precompile growth with the grid, interactive redefinition works, and the
alias loop shrinks back to what it is today. The desynchronization D3 worried
about is impossible for a stronger reason than D3's: there is no second table
to desynchronize *from* — every trait is a function of the same `(K,P,S,E)`
`checkformat` already validates.

**What makes this safe is a gate, not an argument.** Add **G9** (§5): for every
one of the 504 formats and every type- or tag-valued trait, assert the inferred
return type is concrete and the call allocates nothing. That is ~5,000 cheap
assertions and it converts "usually folds" into "verified, per format, in CI".
If G9 ever fails for a trait, *that* trait — and only that trait — falls back
to D3's generation. Generation stays in the toolbox; it stops being the
default.

**Consequent merge of the technique list.** T3 (carrier by dispatch) and T4
(K-branch behind a `Val`) become one rule:

> **T3′ — Every policy choice is a singleton tag or a concrete type reached by
> dispatch, never a value branched on and never a `Type` returned from a
> ternary.** Where the condition is a function of static parameters, put it
> behind a `Val` and dispatch on that. Where it coincides with the
> representation seam, dispatch on `Code8`/`Code16` directly. Adding a format
> or an operation changes which method is selected, never which branch is
> taken.

One rule, three spellings, uniformly applied to the carrier head, the storage
unit, the decode policy, the order-key type, and the table cache (R-D).

### R-B — the mixed-format carrier join is missing and is load-bearing

Neither predecessor addresses it, and it is not optional: the spec-register
form accepts **operands of different formats**, generated at every arity —
`$name(fr::Type{<:Binary}, ρ::ProjSpec, x1::Binary, x2::Binary)`
([`ops_scalar.jl:214`](../../src/ops_scalar.jl#L214)). Today every operand
decodes to `Float64`, so `apply_op(op, fr, ρ, R, xs::Float64...)` is
well-typed by construction. After the carrier split, `decode(x1)` and
`decode(x2)` can be **different types** — a `Float64` and a `Float128` — and
there is no `ωeval` row for that pair.

The fix is a *lift to the operation's head*, decided by the same `rung`
machinery and exact by construction:

```julia
# ops_scalar.jl — the carrier join, applied at the one boundary where operands meet
@inline lift(::HeadF64,   x::Float64)  = x
@inline lift(::HeadF128,  x::Float64)  = Float128(x)          # exact widening
@inline lift(::HeadF128,  x::Float128) = x
@inline lift(::HeadExact, x)           = Dyadic(x)            # exact: ≤113-bit significand → Int128

# the generated spec form becomes
@inline function $name(fr::Type{<:Binary}, ρ::ProjSpec, x1::Binary, x2::Binary; kw...)
    h = rung(Val($(QuoteNode(name))), typeof(x1), typeof(x2))     # folded singleton
    apply_op(h, $V(), fr, ρ, _drawR(ρ, rng, R), lift(h, decode(x1)), lift(h, decode(x2)))
end
```

Three properties this must have, and each is a gate obligation:

1. **`rung(op, Fs...)` is a join (a max), not a lookup.** It is the maximum
   over the head each *operand* format needs and the head the op's worst-case
   monomial needs given `factors(op)`. Spelling it as a monoid is what makes
   `Block*`/`Scaled*` compose without a second rule (§2.3).
2. **Every `lift` is exact.** `Float64 → Float128` is exact (53 ≤ 113 bits and
   the exponent range strictly contains Float64's). `Float64 → Dyadic` and
   `Float128 → Dyadic` are exact (`Base.decompose` gives an integer significand
   ≤ 113 bits, inside `Int128`). Gate **G6** enumerates this over every datum
   of every format — a T1-tier sweep, 7.6 M points, affordable.
3. **`lift` never narrows.** There is deliberately no `lift(::HeadF64, ::Float128)`
   method. A missing method is a `MethodError` at compile time on a path that
   would otherwise silently round a datum. That absence is the design.

### R-C — `decode`'s special values need a carrier-generic constructor set

[doingtheextensions §5.2](doingtheextensions.md) sketches `_decode_compute`'s
carrier-generic finite path (`ldexp(C(sig), e)`) but not its special rows,
which are the first three lines of the function
([`decode_encode.jl:11-15`](../../src/decode_encode.jl#L11-L15)) and return
bare `NaN` / `Inf` / `-Inf` — `Float64` literals. Under a `Dyadic` carrier
those are wrong-typed, and under `Float128` they are a silent narrowing
followed by a widening.

Close it with a four-method carrier-constant interface, one of the smallest
pieces of the whole plan and one that must not be improvised at the use site:

```julia
@inline _cnan(::Type{C})  where {C<:AbstractFloat} = C(NaN)
@inline _cinf(::Type{C})  where {C<:AbstractFloat} = C(Inf)
@inline _cninf(::Type{C}) where {C<:AbstractFloat} = C(-Inf)
@inline _czero(::Type{C}) where {C<:AbstractFloat} = zero(C)
@inline _cnan(::Type{Dyadic})  = Dyadic(D_NAN,  Int128(0), Int64(0))
@inline _cinf(::Type{Dyadic})  = Dyadic(D_PINF, Int128(0), Int64(0))
@inline _cninf(::Type{Dyadic}) = Dyadic(D_NINF, Int128(0), Int64(0))
@inline _czero(::Type{Dyadic}) = Dyadic(D_FIN,  Int128(0), Int64(0))
```

This is why `Dyadic` needs a `kind` tag at all (the predecessor's O1), and it
is where that decision is *consumed*.

### R-D — the table cache must be split by code unit, or `get_table` returns a `Union`

[doingtheextensions Stage 5](doingtheextensions.md) says the table element type
"becomes `Memory{U}` for `U = codeunit_type(fr)`" and stops there. But
`TABLE_CACHE::Dict{TableKey,Memory{UInt8}}`
([`tables.jl:28`](../../src/tables.jl#L28)) is a single concrete `Dict`, and
`get_table` carries a `::Memory{UInt8}` return annotation
([`tables.jl:139`](../../src/tables.jl#L139)) precisely so the gather loop
indexes a concretely-typed local. Widening the value type to
`Memory{<:Unsigned}` makes every gather loop index an abstractly-typed array —
which is the one thing the whole kernel design exists to prevent.

Apply T3′: **two caches, selected by dispatch on the representation.**

```julia
const TABLE_CACHE8  = Dict{TableKey,Memory{UInt8}}()
const TABLE_CACHE16 = Dict{TableKey,Memory{UInt16}}()
@inline _tablecache(::Type{<:Code8})  = TABLE_CACHE8
@inline _tablecache(::Type{<:Code16}) = TABLE_CACHE16

@noinline function get_table(op::Symbol, ::Type{FR}, f1::Type{<:Binary}, ρ::ProjSpec
                            )::Memory{codeunit_type(FR)} where {FR<:Binary}
    ...
end
```

`table_bytes()` and `empty_tables!()` sum/clear both; the ternary cache splits
the same way. Cost: one extra global per unit. Benefit: every gather loop keeps
a concrete element type with no annotation gymnastics, and a future `Code32`
adds a third line rather than a redesign.

### R-E — two carrier traits, deliberately distinct

[doingtheextensions](doingtheextensions.md) routes both the *evaluation*
carrier and the *promotion* target through one `datumtype` trait, so
`promote_rule(::Type{F}, ::Type{Float64}) = datumtype(F)` yields `Dyadic` for
Group C. That would make `x + 1.0` on a Group C value promote to `Dyadic`,
which in turn requires `Dyadic` to implement the full `Real` interface —
arithmetic, comparison, conversion, printing, `AbstractFloat` promotion with
every other numeric type. That is a large public surface for an internal
carrier, and every method of it is a new correctness obligation.

Split the trait:

```julia
"""The exact carrier `decode` returns and `ωeval` computes on. Internal."""
datumcarrier(F)    # Float64 | Float128 | Dyadic
"""The public promotion target for `F ⋄ external`. Always a Julia `AbstractFloat`."""
promotecarrier(F)  # Float64 | Float128 | BigFloat
```

`Dyadic` then needs roughly ten methods (`isnan`/`isinf`/`isfinite`/`iszero`/
`signbit`/`ldexp`/`+`/`*`/`-`/`abs`) plus `round_to_precision` and the
`_c*` constants — a closed, auditable surface — and it never escapes into user
code. `promote_rule` for Group C targets `BigFloat`, which already works.

`Base.Float64(v::Binary)` becomes `Float64(decode(v))`: exact for Group A,
**rounding** for Groups B and C, documented as such at the method. That is the
Julia convention for float conversions (`Float64(::BigFloat)` rounds) and it is
the right default; the exactness contract lives in `decode`, `Convert`, and
`promote_rule`, all of which stay exact.

### R-F — no `Val` barrier for decode; dispatch on the representation

[doingtheextensions T4](doingtheextensions.md) illustrates the sanctioned
K-branch with decode:

```julia
@inline decode(v::F) where {F<:Binary} = _decode(F, codepoint(v), Val(bitwidth(F) <= 8))
```

But the table/compute split *is* the representation split — `Code8` ⟺ K ≤ 8 ⟺
a 2^K ≤ 256 constant tuple. Dispatching on the tag removes the `Val`
construction entirely and makes the K ∈ 9:12 cached-table tier (an open
measurement question, §7) a one-line retarget of `decodepolicy` rather than a
change to `decode`:

```julia
@inline decode(v::Binary) = _decode(decodepolicy(typeof(v)), typeof(v), codepoint(v))
@inline _decode(::TableDecode,   ::Type{F}, c) where {F} = @inbounds _decode_table(F)[Int(c) + 1]
@inline _decode(::ComputeDecode, ::Type{F}, c) where {F} = _decode_compute(F, c)
```

Note `_decode_compute` changes shape: today it takes a **value**
(`_decode_compute(v::Binary{…})::Float64`,
[`decode_encode.jl:5`](../../src/decode_encode.jl#L5)) and is called by the
`@generated` table builder through `rawvalue`. It must become
`_decode_compute(::Type{F}, c)` returning `datumcarrier(F)`, with the table
builder adapted. Small, but it is a signature change on the function that is
the ground truth for both decode tables, so it lands in Stage 1 (where G5
verifies it at zero behavior change), not Stage 4.

### R-G — invariant 10 restated as a bound on *tables*, not on `@generated`

[doingtheextensions](doingtheextensions.md) proposes:

> **10. Nothing is `@generated` over data whose size grows with `2^K`.**

The mechanism is not the hazard. `@generated` over a 256-element tuple is fine;
a *non-generated* `Memory` of 2^32 entries is not. Restate around the quantity
that actually bites:

> **10. No construct materializes `2^ΣK` elements without a byte budget.**
> Constant-tuple tables are permitted only where the tuple length is bounded by
> 256 (selected by `decodepolicy`, T3′). Every `Memory`-backed table is
> allocated through the one byte-budget policy in `tables.jl`, which returns
> `nothing` rather than attempting an impossible allocation. Index arithmetic
> for a table is computed in `Int` and asserted `ΣK ≤ 48`.

This is enforceable by grep on `Memory{` and `ntuple(`, which invariant 10 as
written is not.

### R-H — `Dyadic` stays a Stage 7 swap, with the swap itself as the gate

[doingtheextensions §6.3](doingtheextensions.md) defers universal `Dyadic` and
ships Group C on `BigFloat` at Stage 6, swapping to `Dyadic` at Stage 7. Keep
that, for a reason worth making explicit: **the interim costs almost nothing**
— `round_to_precision(::BigFloat)` already exists with a precision-raising
function barrier ([`project.jl:144`](../../src/project.jl#L144)), so
`HeadExact = BigFloat` is a `carriertype` line plus the `_cnan`-family
`AbstractFloat` fallbacks in R-C, and nothing else.

What the predecessor does not say is that the interim buys a **free
differential oracle**. Running the whole Group C surface twice — once with
`carriertype(::HeadExact) = BigFloat` and once with `= Dyadic` — and asserting
identical code points is the strongest possible check on the `Dyadic`
arithmetic and its `round_to_precision` method, and it needs no reference
implementation and no new test data. Promote it to gate **G7** and make it
Stage 7's exit criterion.

---

## 3. The architecture, consolidated

### 3.1 Types

```julia
abstract type Binary{K,P,SGN,EXT} <: AbstractFloat end        # the P3109 format (D1 §3.1)
struct Code8{K,P,SGN,EXT}  <: Binary{K,P,SGN,EXT}; x::UInt8  end     # 3 ≤ K ≤ 8
struct Code16{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}; x::UInt16 end     # 9 ≤ K ≤ 16

abstract type Head end
struct HeadF64 <: Head end; struct HeadF128 <: Head end; struct HeadExact <: Head end

abstract type DecodePolicy end
struct TableDecode <: DecodePolicy end; struct ComputeDecode <: DecodePolicy end

struct Dyadic <: Real; kind::UInt8; S::Int128; Q::Int64 end    # Stage 7
```

`Binary{K,P,S,E}` is abstract with exactly one concrete subtype per parameter
tuple, uniformly across all 504 formats. Subtyping `Binary` is **not** a
supported extension point.

### 3.2 Traits (15 methods, none generated — R-A)

| trait | shape | answers |
|---|---|---|
| `reptype(F)` | `Val(K≤8)` barrier + 2 identities | `Code8{…}` / `Code16{…}` |
| `codeunit_type(F)` | representation dispatch | `UInt8` / `UInt16` |
| `codemask(F)` | one generic method, complement construction (T11) | `typemax(U) >> (8sizeof(U) − K)` |
| `decodepolicy(F)` | representation dispatch | `TableDecode()` / `ComputeDecode()` |
| `orderkeytype(F)` | representation dispatch | `UInt16` / `UInt32` |
| `datumcarrier(F)` | `Val(rungindex)` barrier | `Float64` / `Float128` / `Dyadic` |
| `promotecarrier(F)` | `Val(rungindex)` barrier | `Float64` / `Float128` / `BigFloat` |
| `rung(F)` | `Val(rungindex)` barrier | `Head` singleton |
| `rung(op, Fs...)` | join over operands × `factors(op)` | `Head` singleton |
| `factors(op)` | `OpInfo` registry column | 1 / 2 / +1 per block scale |
| `bigprec(Fs...)` | `2(maxB + maxP) + 64` | MPFR precision |

Every special and extremal code point (`nan_code`, `posinf_code`,
`neginf_code`, `signmask`, and the four extremal codes) becomes one generic
method built from `codemask` and shifts of amount ≤ K−1, so no width-sensitive
expression survives anywhere (**T11**).

### 3.3 Rung boundaries

```
ΣB ≤ 1024   and  Σ(Bᵢ + Pᵢ) ≤ 1074 + 2n    ⇒  HeadF64()
ΣB ≤ 16384  and  Σ(Bᵢ + Pᵢ) ≤ 16494 + 2n   ⇒  HeadF128()
otherwise                                    ⇒  HeadExact()
```

sums over the datum factors of the op's worst-case monomial, `n = factors(op)`.
**Verified counts** over the full grid (Appendix C): **432 / 64 / 8**, and the
scalar-op partition by `2B` coincides exactly with the partition by `B` alone
(`B ≤ 512` / `≤ 8192` / `> 8192`), so `rung(F)` and `rung(op, F)` agree for
every unary and additive op — a useful sanity invariant to assert.

**Caution on the closed form.** `MaxFinite = (2^P − 1)·2^(B−P)` is an **upper
bound**, not the value: the code lattice caps the biased exponent below what
the formula allows, by up to two binades. Verified: `Binary16p1uf`'s true
`MaxFinite` is `2^32766` (bound says `2^32768`) and `MinPositive` is `2^-32767`,
spread **65533**. The bound is conservative in the safe direction for rung
selection, so it may be used there — but every **witness** (G2's operand pair,
G4's boundary formats) must be computed from the lattice, never from the
formula.

### 3.4 Include order — 16 layers

```
dyadic → formats → carriers → projspec → defaults → decode_encode → project
       → ops_scalar → juliacompat → oracle → tables → kernels → blocks
       → packed → approx → rand
```

The comment at [`SmallFloats.jl:43-49`](../../src/SmallFloats.jl#L43) must
change in the same commit that changes the order.

### 3.5 New invariants (for the reconstituted doctrine file — C9)

> **8. Format types are propagated, never rebuilt.** A method that received a
> format type or a value uses *that* type; it never re-forms `Binary{K,P,S,E}`
> from destructured parameters. `Binary{K` in a method **body** is a defect
> (`defaults.jl:78` is the live instance — C4); grep enforces it.
>
> **9. Policy is dispatch, never a branch (T3′).** Carrier head, storage unit,
> decode policy, order-key type, and table cache are singleton tags or concrete
> types reached by dispatch. No code path computes one into a variable and
> branches on it.
>
> **10. No construct materializes `2^ΣK` elements without a byte budget.**
> (as restated in R-G).

---

## 4. The stages

Ten stages. Each is one commit, compiles, passes the suite, and is revertible
without touching its neighbours.

| # | stage | net effect | exit gate |
|---|---|---|---|
| 0 | Prerequisites and baseline | none | doctrine file exists; **G5** captured; baselines recorded |
| 1 | Traits, tags, width-safe constants, audit fixes | none | **G5** byte-identical; **G9** green |
| 2 | Representation lattice (`Code8` only) | none | **G5 byte-identical — the critical checkpoint** |
| 3 | `Code16`; 504 formats exist | wide formats constructible | lattice sweep at every K; wide arithmetic throws |
| 4 | Decode/encode/keys/sort/packed widened | Group A operational at every K | **G3**, **G6** |
| 5 | Table and kernel policy | wide array ops correct | table gates; no impossible allocation |
| 6 | Carrier lattice | Groups B and C correct | **G2** (red first), **G1**, **G4** |
| 7 | `Dyadic` | Group C allocation-free; block scale path | **G7**, **G4** re-run |
| 8 | Test doctrine and gates | coverage policy machine-checked | full tier suite in `Pkg.test()` wall clock |
| 9 | Docs, exports, benchmarks, release | shippable | full CI matrix; PDF pipeline clean |

---

### Stage 0 — Prerequisites and baseline

*No source changes. Everything here is a thing that must exist before an edit
is safe.*

0. **Make the repository build** (§11 M1 — discovered during execution, not by
   the audit). `Project.toml` was rejected outright by Pkg: `Julia = "1.12"` in
   `[compat]` must be lowercase `julia`, and `author` must be `authors`. Until
   both are fixed `Pkg.instantiate()` fails, so *nothing* — not the suite, not
   the golden, not a single `using` — can run. C9 understated the state of the
   rename: the tree was not merely missing its doctrine file, it did not build.
1. **Reconstitute the doctrine file** (C9). Recompose the seven invariants, the
   include-order rule, the enumerate-don't-sample doctrine, the
   `SmallFloats_Float128` dual-configuration contract, and the JET-filter rule
   from [`docs/src/technical_guide.md`](../src/technical_guide.md) and the
   assertions in [`test/`](../../test/). Without it, invariants 8–10 have
   nowhere to live and invariant 8's grep enforcement has nothing to cite.
2. **Capture the K ≤ 8 golden (G5).** SHA-256 one digest per section of the
   K ≤ 8 observable surface; commit as `test/golden/k8.sha256` (~20 lines,
   diffable — technique T12). **Capture before the first edit**; a golden
   derived from refactored code proves only self-consistency, so
   [`capture.jl`](../../test/golden/capture.jl) refuses to overwrite an
   existing file without an explicit environment override.

   *Implementation note (§11 M3).* The plan said "run the existing suite and
   digest each testset". That was the wrong shape: the suite's testsets are
   `@test` calls, not result streams, so digesting them means invasive edits to
   1 500 lines of tests — and it couples the oracle to the *structure* of the
   suite rather than to the *behaviour* of the package. A standalone harness
   ([`test/golden/harness.jl`](../../test/golden/harness.jl)) enumerating the
   surface directly is independent of how the tests happen to be organized, is
   reproducible from one command, and is what G5 actually needs.
3. **Record the performance baseline.** Scalar `Add`, `project`, array unary
   and binary gathers, and the zero-allocation pins, under the existing
   benchmark harness, with the machine and Julia version recorded. Stage 2 is
   the stage most likely to move these and the only defence is a number.
4. **Record the compile-latency baseline**: package load time, and first-use
   `@time` for one cold format. R4's mitigation is a tracked number, not a
   policy.
5. **Decide the four open questions** (§9). Export surface and the three
   unconsumed-surface dispositions gate Stage 1 and Stage 9 respectively.

**Exit:** doctrine file committed; `test/golden/k8.sha256` committed; baselines
in `benchmarking/`; §9 answered.

---

### Stage 1 — Traits, tags, width-safe constants, audit fixes

*Today's 120 formats, today's answers, zero behavior change. This stage exists
so Stage 2's diff is only the type refactor.*

1. **New file `carriers.jl`** between `formats.jl` and `projspec.jl`: `Head`
   and its three singletons, `DecodePolicy` and its two, `carriertype` in
   **both** the instance and the `::Type{H}` forms (the predecessor's O5 — the
   likeliest first-day error), `_rungindex`, `rung(F)`, `datumcarrier`,
   `promotecarrier`, `bigprec`. Every answer is today's answer for every K ≤ 8
   format. Update the include-order comment in the same commit.
2. **Traits in `formats.jl`** per R-A: `reptype` (identity today), 
   `codeunit_type`, `decodepolicy`, `orderkeytype`, `codemask`. All still
   answer `UInt8` / `TableDecode()` / `UInt16`.
3. **Migrate every special and extremal code point to the complement
   construction** (T11). `formats.jl:86-112` becomes `U = codeunit_type(F)` and
   `codemask(F)`; the *values* are unchanged, verified by G5. This is the
   policy migration A2 calls for: a zero-behavior-change edit, verified
   completely by the golden, that makes width-safety structural before 384
   formats are added to it.
4. **Reshape `_decode_compute`** to `(::Type{F}, c)` returning
   `datumcarrier(F)` (R-F), and add the `_c*` carrier-constant interface (R-C).
   Adapt the two `@generated` table builders. Behavior identical.
5. **Audit fixes**, all with today's grid so G5 covers them:
   - **A1** — `approx.jl:60`: `UInt8(codes[i])` → `codeunit_type(argformats[i])(codes[i])`.
   - **A6/C8** — delete `_cmp_rounded_datum` ([`project.jl:237-255`](../../src/project.jl#L237)).
   - **A3/A4** — apply the §9 dispositions for `f32_exact` and
     `DefaultAccumulatorType`.
   - Budgets as `Ref`s (T9): `max_exhaustive`, the table byte budgets, the
     tier thresholds.
6. **Write G9** (trait folding gate) and run it over the 120 formats. It is
   cheap now and it is the thing that licenses R-A for 504 later.

**Exit:** **G5 byte-identical**; **G9** green; benchmark baseline unmoved
(±noise); no new JET findings.

---

### Stage 2 — The representation lattice, `Code8` alone

*The single highest-risk edit in the project: it touches every layer. It adds
no formats, so G5 is a complete oracle and any difference is a refactor bug.*

1. `abstract type Binary{K,P,SGN,EXT} <: AbstractFloat end`; add `Code8` with
   the inner `Val(:code)` constructor whose `@boundscheck` uses the **mask
   test** `x & codemask(F) == x`, not a comparison against `2^K`.
2. Retarget the alias loop: `T = (K <= 8 ? Code8 : Code16){K,P,S,E}` — plain
   code, no `@eval` per iteration.
3. Turn on `reptype`'s `Val` barrier (R-A); `_rep(::Val{false}, …)` returns
   `Code16{…}` which does not exist yet — **define `Code16` here, empty of
   formats**, so `reptype` is total from the moment it is non-trivial. No
   format instantiates it until Stage 3.
4. **The 29-site sweep** (C3, [Appendix A](#appendix-a--the-exact-signature-sweep)).
   Each site is one of three kinds and the commit message must say which:
   *(a)* widen to `::Type{<:Binary{K,P,S,E}}` (the Group M family, `formatname`,
   the extremal queries, `_fkey`, `typemax`/`typemin`/`eps`);
   *(b)* retarget to the representation (`rawvalue`, the code-point
   constructor, `_decode_table`, `_decode_table32`, `encode`);
   *(c)* keep exact **by design** (`reptype`'s abstract case only).
5. **Apply T1 to every rebuild site.** `Binary{K,P,S,E}` in a *body* becomes
   `typeof(v)` or `reptype(…)`. The live instances are
   [`decode_encode.jl:6`](../../src/decode_encode.jl#L6), `:37`, `:45`, `:60`,
   `:70`, `:98`, [`formats.jl:219`](../../src/formats.jl#L219), and
   [`defaults.jl:78`](../../src/defaults.jl#L78) — **the last of which is C4,
   the silent one.** Add the `isconcretetype(DefaultType())` assertion.
6. **`rawvalue` through the function barrier**, so no type is computed into a
   variable:
   ```julia
   @inline rawvalue(::Type{F}, x) where {F<:Binary} = _rawvalue(reptype(F), x)
   @inline _rawvalue(::Type{R}, x) where {R<:Code8}  = @inbounds R(Val(:code), UInt8(x))
   @inline _rawvalue(::Type{R}, x) where {R<:Code16} = @inbounds R(Val(:code), UInt16(x))
   ```
7. **`codepoint`'s return type** routes through `codeunit_type` (still `UInt8`).
8. **The `similar` normalization** and the public `format(K,P,Σ,Δ)`:
   ```julia
   Base.similar(A::AbstractArray, ::Type{Binary{K,P,S,E}}, dims::Base.Dims) where {K,P,S,E} =
       similar(A, reptype(Binary{K,P,S,E}), dims)
   @inline function format(K::Int, P::Int, S::Bool, E::Bool)
       T = get(_NAMED, _formatname(K, P, S, E), nothing)
       T === nothing && (checkformat(K, P, S, E); error("unreachable"))
       T
   end
   ```
   `Vector{Binary{…}}(undef, n)` cannot be intercepted; document it and make
   `format` the advertised route.
9. **Constructor forwarding on the abstract type**, so `Binary{8,4,true,true}(x)`
   keeps working:
   ```julia
   @inline (::Type{Binary{K,P,S,E}})(c::Unsigned) where {K,P,S,E} = reptype(Binary{K,P,S,E})(c)
   @inline (::Type{Binary{K,P,S,E}})(x::Real)     where {K,P,S,E} = reptype(Binary{K,P,S,E})(x)
   ```
10. **`show` must distinguish the two** (O6), keeping the `_fully_instantiated`
    guard that a test found necessary:
    ```julia
    function Base.show(io::IO, T::Type{<:Binary})
        if _fully_instantiated(T)
            print(io, formatname(T)); isabstracttype(T) && print(io, "{format}")
        else
            invoke(show, Tuple{IO,Type}, io, T)
        end
    end
    ```
11. **Update the pinned identities.** [`runtests.jl:117`](../../test/runtests.jl#L117)
    `Binary8p4se === Binary{8,4,true,true}` becomes `<:`, and the three doc
    sites ([`cheat_sheet.md`](../src/cheat_sheet.md),
    [`introduction.md`](../src/introduction.md),
    [`user_guide.md`](../src/user_guide.md)) are **rewritten to teach the
    format/representation split**, not patched. This is D1 §3.1's own
    distinction and it is better teaching than the identity it replaces.
12. **Budget JET review time** (O14). The abstract-type boundary is the shape
    that produced the existing `_vmap_packed` filter. A new filter requires a
    concrete-call gate proving the path is clean — that rule does not bend here.

**Exit:** **G5 byte-identical.** Do not proceed otherwise. If Stage 2 is green,
the representation lattice is proven on 120 formats and ~8.9 M assertions
before a single wide format exists.

---

### Stage 3 — `Code16` and the 504-format grid

1. Populate `Code16`; open `checkformat` to `KMIN:KMAX` with the range as named
   constants. **Three** constants, not two: `KMIN = 3` and `KMAX = 16` are a
   scope claim about the package, while `KSPLIT = 8` is a *representation* fact
   (`8 * sizeof(UInt8)`) and the `Code8`/`Code16` seam. All three were being
   written as the literal `8`, and they do not move together — that is how
   `K <= 8` comes to mean "narrow enough for a byte" in one file and
   "supported" in another.
2. Extend the alias loop to `KMIN:KMAX` → 504 names. Verify the count in the
   suite (`length(_NAMED) == 504`), and the per-K counts `4K − 2`.
3. **Restated invariant 2** lands here: `(::Type{T})(c::Unsigned)` replaces the
   `UInt8` method (range-checked against `codemask`, so *every* `Unsigned` at
   *every* width is a code point, uniformly); `show` padding becomes
   `2 * sizeof(codeunit_type(T))`; `codepoint` returns the unit;
   `rawvalue` requires it.
4. **Front-load the construction sweep** (C5). Before anything else in this
   stage is tested: construct **every code point of every one of the 504
   formats**, assert `codepoint(T(c)) == c`, assert the representation
   invariant (`codepoint(v) & ~codemask(T) == 0`), and assert out-of-range
   codes throw at every offered `Unsigned` width. 7.6 M points, cheap, and it
   surfaces the entire checked-conversion class in one run.
5. **Disable non-`HeadF64` arithmetic loudly.** Throw from the *missing head
   methods*, never from `rung`:
   ```julia
   ωeval(::HeadF128,  ::Val{op}, xs...) where {op} =
       throw(ArgumentError("$op on this format needs the rung-2 carrier (Stage 6)"))
   ωeval(::HeadExact, ::Val{op}, xs...) where {op} =
       throw(ArgumentError("$op on this format needs the rung-3 carrier (Stage 6/7)"))
   ```
   `rung` stays **total** — it is a trait, and a trait that throws over a third
   of its domain is not a trait. An incomplete implementation is precisely a
   set of missing methods, which is what the method table reports.

   *Reached as `ωeval(rung(fr), op, xs...)` from `apply_op`.* Gating on the
   **result** format alone is complete at this stage and only at this stage:
   operands arrive already decoded, `decode` refuses every K ≥ 9 format until
   Stage 4, and every K ≤ 8 format has B ≤ 128 and is therefore rung 1. Stage 6
   replaces it with the `rung(op, Fs...)` join (R-B). Measured: the tag argument
   is free — warm scalar paths still allocate zero and `vmap!` still runs at
   0.26 ns/elem on the table path.

   *Same discipline, wider than the plan said:* `decode` is gated too (§11 M17).
   It is not arithmetic, but `_decode_compute`'s Float64 bit-assembly tail is
   the one wide route that would have been **silently wrong** rather than
   loudly missing.
6. Update [`approx.jl:313`](../../src/approx.jl#L313)'s conformance banner
   (`K ∈ 3:8` → the constants) so the declaration cannot go stale.
7. `test/runtests.jl:118`'s `Binary{9,4,true,true}` invalidity assertion moves
   to K = 17, keeping its `P ≥ K` sibling intact.

**Exit:** the full lattice sweep passes at every K; every Group B/C arithmetic
call throws with a message naming its stage; G5 still byte-identical.

**Achieved.** Lattice sweep 504 formats × 7 602 160 code points, exhaustive,
10 s (`test/sweep_lattice.jl`). Stage gates 634 assertions
(`test/stage_gates.jl`) — a new file that *shrinks* as the extension lands, and
whose rows are meant to go red by being implemented. G9 4 290 assertions over
the whole grid. **G5 33/33 byte-identical** through the grid opening. Aqua and
both JET passes green with no new filter. Warm scalar paths allocate zero.

---

### Stage 4 — Decode, encode, keys, sort, packed

1. **Decode by policy** (R-F). `_decode_compute` gains the carrier-generic
   finite path (`ldexp(C(sig), e)`) and the `_c*` special rows. The Float64
   bit-assembly shortcut is retained **only** under `TableDecode` — its
   justifying comment (`|e + nb − 1| ≤ ~260`) is exactly the K ≤ 8 premise.
   Note the landing zone this fixes: a B ≈ 1024 format's minimum datum is
   `2^(2−P−B)`, as low as `2^-1038`, a Float64 **subnormal**, where the current
   bit assembly produces garbage. `ldexp` handles it; the shortcut must not be
   reached.
2. **`encode`** returns `codeunit_type(T)`; its interior arithmetic is already
   `Int64` and needs no change (`Eb ≤ 2^16`, `S ≤ 2^16`).
3. **Order keys**: `orderkeytype` (R-A), `nan_order_key(F) = typemax(orderkeytype(F))`
   replacing the `NAN_ORDER_KEY` const, `codedistance` follows.
   **→ landed in Stage 3 (§11 M16):** a `UInt16` key wraps silently to 0 at
   K = 16, and Stage 3's whole discipline is that wide formats fail *loudly*.
4. **Counting sort**: `key2code::Vector{codeunit_type(T)}`, and the length
   gate
   ```julia
   n = hi - lo + 1
   n < (1 << K) && return sort!(v, lo, hi, Base.Sort.DEFAULT_UNSTABLE, o)
   ```
   At K = 16 the unconditional setup is 512 KiB and 65 536 iterations before
   touching the data. The gate is a generalization, not a behavior change: at
   K ≤ 8 it almost never fires.
   **→ landed in Stage 3 (§11 M16)**, with item 3: the sort reads
   `NAN_ORDER_KEY`, so it had to move when the key type did, and a sort that
   *works* while allocating 512 KiB for a three-element vector is the kind of
   thing that gets measured before it gets fixed.
5. **`PackedVector`**: `U(c & mask)` for `U = codeunit_type(F)`; `_codemask(K)`
   already returns `UInt64` and is correct to K = 63. **Refuse loudly at
   K = 16** — packing is the identity there and a silent identity invites
   benchmark confusion.
6. **`Float32`/`BFloat16` surface gated.** `_decode_table32` stays `Code8`-only;
   `Base.Float32(v::Code16) = Float32(decode(v))`, documented as rounding;
   `decode!(::AbstractArray{Float32}, ::AbstractArray{F})` throws unless the
   datum-exactness trait holds (`B ≤ 128` and `2−P−B ≥ −149`), and
   `decode!(::AbstractArray{Float64}, …)` throws unless
   `datumcarrier(F) === Float64`. The exhaustive Float32 test changes from "all
   formats" to "all formats where the trait holds, plus a round-trip inequality
   witness where it does not" — so the *boundary* is tested.
7. **Write G6** (carrier-lift exactness) here, since `decode` now produces the
   wide carriers.

**Exit:** **G3** (`_rtp_f64` bit ≡ generic over the widened `(P ≤ 16, B ≤ 512)`
grid — the first stage where P > 8 reaches the bit path); **G6**; the full
lattice sweep still green; Group A operational at every K.

**Achieved.** **G3** green over **135 `(P, B)` cells** — every pair the grid
realizes, not just the rung-1 ones (§11 M22) — 4 839 210 bit-vs-generic
comparisons, 1.1 s. **G6** green over **19 976 144 `(datum, head)` pairs**,
exhaustive, 27 s. **Group A verified at every K** by
[test/wide_ops.jl](../../test/wide_ops.jl): 321 984 results on the 312 wide
rung-1 formats, each recomputed from the draft definition in MPFR rather than
compared against the package's own oracle. Ordering and the counting sort
checked against decoded datums at K = 16, which is the first point at which
Stage 3's key retyping could be verified against values rather than structure.
G5 33/33 byte-identical; lattice sweep, G9, Aqua and both JET passes green;
warm scalar paths allocate zero on **both** narrow and wide formats and the
narrow array path holds 0.26 ns/elem.

---

### Stage 5 — Table and kernel policy

1. **Delete the split policy.** One arity-agnostic gate replaces the
   unconditional unary/binary build and the ternary three-band policy:
   ```julia
   _table_for(op, fr, fs::Tuple, ρ, nelems) -> Union{Nothing, Memory{codeunit_type(fr)}}
       bits  = Σ bitwidth(fᵢ);  @assert bits <= 48
       bytes = (1 << bits) * sizeof(codeunit_type(fr))
       bytes ≤ EAGER_BYTES[]    (256 KiB) → build now
       bytes ≤ ADAPTIVE_BYTES[] (2 MiB)   → build once the signature has seen BUILD_ELEMS[]
       otherwise                          → nothing; compute per element
   ```
   K ≤ 8 behavior is unchanged: every unary (≤ 256 B) and binary (≤ 64 KiB)
   table falls in the eager band. This is a *simplification* — a removed code
   path, not an added one.
2. **Two typed caches** (R-D), selected by dispatch on the representation.
3. **Shape A becomes conditional at every arity** in `kernels.jl`, mirroring
   the ternary method's existing `tbl === nothing` branch — a copy of a proven,
   threaded, tested shape rather than a new design.
4. **Parallel build.** The builder is a pure function of the code point, so
   `Threads.@threads` over the index space is trivially correct, runs outside
   the lock as builds already do, and turns a K = 16 unary `Exp` table (65 536
   oracle trips, plausibly seconds) into tens of milliseconds. Invariant 6
   holds: every entry is still one trip through the oracle-backed scalar path.
5. **Cost-aware eager band.** Gate the eager band on
   `entries × opcost(group)` in addition to bytes, so Group B/C transcendentals
   at K ≥ 14 need the adaptive counter's evidence before paying.
6. **`table_bytes` companion** naming declined signatures, so "this signature
   is running the compute kernel" is discoverable rather than inferred from a
   benchmark.

**Exit:** K = 16 unary array ops run on tables; K = 16 binary array ops run on
the compute kernel; no signature attempts an impossible allocation; first-call
latency for the largest eager table is recorded.

---

### Stage 6 — The carrier lattice

*Write **G2** first and watch it fail.*

1. **G2, red.** The `Binary16p1uf` maximal-spread witness — `MaxFinite = 2^32766`,
   `MinPositive = 2^-32767`, spread **65533**, taken from the lattice not the
   closed form (§3.3) — against `_BIGP = 2200`, with `Rational{BigInt}` from
   [`test/refimpl.jl`](../../test/refimpl.jl) as oracle. A precision-truncation
   bug produces plausible results; a red test is the only proof the fix was
   necessary.
2. **`factors` as an `OpInfo` registry column**, so `Block*`/`Scaled*` derive
   their factor counts from the row that generates them (invariant 7). Never a
   hand-maintained table.
3. **`rung(op, Fs...)` as a join** (R-B), and the `lift` family with **no
   narrowing method**.
4. **Per-head `ωeval` rows** and the per-head `apply_op` split:
   ```julia
   @inline function apply_op(h::H, op::Val, ::Type{fr}, ρ::ProjSpec, R::Int, xs...) where {H<:Head,fr<:Binary}
       res = ωeval(h, op, xs...)
       res isa carriertype(H) && return project(fr, ρ, res; R)     # H is a TYPE parameter (O5)
       _finish_slow(fr, ρ, R, res)
   end
   ```
   The measured 399 → 269 ns/elem benefit of the existing split is preserved by
   making it per-head; `carriertype(H)` folds to a literal type in each
   specialization.
5. **`bigprec(fs…) = 2*(maxB + maxP) + 64`**, replacing `_BIGP`, threaded
   through `_bigsum2`/`_bigfma`/`_bigsum3` and through `blocks.jl`'s reduction
   accumulator — **one precision policy, not two**.
6. **`_DE_*` as functions of P, with C1's corrected FMA margin and C2's
   sticky-band guard.** The three-way band split of C2 is written here, with
   `N_max = 60` at the emitting site.
7. **Carrier-aware `promote_rule`** targeting `promotecarrier(F)` (R-E), emitted
   per external type. `promote_rule` is inherently type-returning and is
   resolved by the compiler at the type level, so it is an explicit carve-out
   from T3′ — but it is still derived from a trait, never computed at a call
   site.
8. **`blockdecode`'s `::Float64` assertion** becomes `::carriertype(rung(…))`.
9. **Group C on `BigFloat`** behind `HeadExact` (R-H). `carriertype(::HeadExact)`
   answers `BigFloat` in this stage and `Dyadic` in the next; say so in the
   code, because an unannounced change of a trait's answer between stages looks
   like a merge error.
10. Re-label the `SmallFloats_Float128 = "disable"` CI job: it is no longer
    confirmatory. It is now the only verification that Group B's **default**
    path agrees with the rigorous one.

**Exit:** **G2** green (and demonstrably red before the fix); **G1** including
band contiguity for every `P ≤ 16`, `N ≤ 60`; **G4** including the four-factor
`ScaledMultiply` case and stochastic ρ with explicit `R`; the disable-Float128
configuration bit-identical for Group B.

---

### Stage 7 — `Dyadic`

1. **`dyadic.jl`**, first in the include order, zero SmallFloats dependencies.
   The type, the ten predicates and operations, and the `_c*` constants (R-C).
   Multiply's precondition (`nbits(a.S) + nbits(b.S) ≤ 96`) written at the
   method and asserted under `@boundscheck`.
2. **The add, with C7's corrected bands** in a comment at the method and as a
   static assertion in the suite:
   ```
   exact Int128 alignment : ΔQ ≤ 94        (32-bit head + one carry bit)
   sticky (sign only)     : ΔQ > P + N + 2
   coverage requires        P + N ≤ 92     (currently 16 + 60 = 76, margin 16)
   ```
   This is the one place where widening `P` or raising `N` could silently open
   a gap, which is exactly why it is an assertion and not a comment alone.
3. **`round_to_precision(P, B, μ, X::Dyadic, R, sticky)`**, handling specials
   and zero *directly* — `_rtp_core`'s zero row builds
   `zero(float(typeof(X)))` and `float(Dyadic)` does not exist (O2) — with the
   sticky-zero row factored into a shared `_rtp_zero_sticky` so the carriers
   cannot drift. The shifted-out bits **are** ν as an exact fixed-point
   fraction, so the tail shares `_rtp_f64`'s `_rab` predicate family: `Dyadic`
   joins the fixed-point twin rather than founding a third family.
4. **`carriertype(::HeadExact) = Dyadic`** — the one-line swap the tag exists
   to make possible.
5. **The P = 1 block-scale fast path.** A P = 1 datum is `±2^e`, i.e.
   `Dyadic(±1, e)`, so block decode becomes `Dyadic(S_elem, Q_elem + e_scale)`
   — a shift of the exponent field, no arithmetic, no overflow question. In
   `Float64` or `Float128` the same operation is an `ldexp` that can overflow
   the carrier. The hardest case in the grid is the cheapest one, and Annex F
   makes it the *common* one: `k8p1uf` is OCP's **E8M0**, the scale format of
   MX-style block arithmetic ([Annex F](IEEE_D1.md#L2791)), and `Binary16p1uf`
   is its 16-bit analog. Group C is on the block hot path.
6. Reconsider **C8**: if the Group C saturation path wants a rounded-vs-datum
   comparator, reintroduce `_cmp_rounded_datum` against `Dyadic`. `saturate` is
   already pure `(S, Q)` integer work, so the expectation is that it does not.

**Exit:** **G7** — the entire Group C surface produces identical code points
under `carriertype(::HeadExact) = BigFloat` and `= Dyadic`. **G4** re-run with
the block/scaled four-factor cases. Zero warm-path allocations on `HeadExact`
except the MPFR transcendental fallback (T8: allocation discipline is stated
per head, so a Group C `Log` allocating is a recorded property, not a suite
failure).

---

### Stage 8 — Test doctrine and gates

1. The five tiers (§6) with **corrected domains**: T2 splits into a 135-tuple
   rounding sweep and a 504-tuple saturation sweep (C6).
2. **`refimpl` promoted** from manual-only into the shipped suite as the T2
   oracle. It is the only oracle in the repository whose validity does not
   depend on a carrier being wide enough, which is exactly why wide K makes it
   non-optional.
3. **Derived, not hand-listed, selection.** The representative format set is
   *computed* from the grid — for each (group, rung-boundary proximity,
   P-extreme, Σ, Δ) cell, the format maximizing B. A hand-listed tuple of four
   names cannot track a 504-format grid, and one that silently stops covering a
   new group is the most likely way this extension ships a hole. The T4 edge
   set is likewise **derived from the thresholds in the source** (`_DE_*`,
   `bigprec`, the rung boundaries), so moving a threshold moves the edges that
   test it.
4. **Every ρ family at every rung**, explicitly — stochastic × Group B and
   stochastic × Group C present by construction, not by random draw, because
   carrier-precision differences manifest on the stochastic sub-grid first.
5. **`SmallFloats_EXHAUSTIVE=1`** nightly split; every budget a `Ref` and
   reported in suite output (T9); every sampled result labelled in the same
   words `measure_kappa` already uses.
6. G1–G9 all standing, all named in the suite output.

**Exit:** `Pkg.test()` in the same wall-clock class as today; the nightly sweep
green; every knowingly-uncovered area (§6.4) stated in one place.

---

### Stage 9 — Docs, exports, benchmarks, release

1. **Exports**: the opt-in `SmallFloats.Formats` submodule re-exporting all 504
   aliases; the 120 K ≤ 8 names exported as today (no breakage);
   `format(K,P,Σ,Δ)` for programmatic use. Asymmetric reversibility settles
   this: exporting more later is non-breaking, un-exporting is not.
2. **Documentation.** The `3–8` range is stated in
   [`index.md`](../src/index.md), [`introduction.md`](../src/introduction.md)
   (twice), [`user_guide.md`](../src/user_guide.md),
   [`technical_guide.md`](../src/technical_guide.md), and
   [`external_reference.md`](../src/external_reference.md); the format count in
   two of them. `README.md` needs writing, not amending (C9). The
   `Binary16p11se ≠ Float16` / `Binary16p8se ≠ BFloat16` trap gets its own
   section — the biases differ (16 vs 15, 128 vs 127), as do NaN count,
   negative zero, and the domain parameter.
3. **The PDF/LaTeX pipeline** ([docs/pdf/howto.md](../pdf/howto.md)) is fed by
   `docs/src/*.md`, so a stale range propagates into a released PDF. Purge the
   stale `ByteFloats` artifacts in `docs/build_latex/` and `docs/pdf/` (C9).
4. **`benchmarking/`** has its own environment: `Pkg.develop` refresh, per-rung
   report sections, and the preflight abort condition made **per-head** (T8).
5. **Precompile workload**: stays K ≤ 8 for tier-1 entries plus exactly one
   Group A wide format and one Group B format, so the wide paths compile but
   the image does not grow with the grid. Compare against the Stage 0
   compile-latency baseline.
6. **Semver**: a major bump (or minor, pre-1.0). The documented migration is
   `similar`'s normalization, `format(K,P,Σ,Δ)`, and `<:` in place of `===`.
7. **`Project.toml` is unchanged** — the extension adds **zero** dependencies.
   `Quadmath` and `BFloat16s` are already present, `Dyadic` is hand-written
   `Int128` arithmetic, MPFR is `Base`. A plan that quadruples the format grid
   without touching the dependency surface should say so.

---

## 5. The gates

Nine standing gates. G1–G5 are inherited (G1 corrected); G6–G9 are new.

**G1 — `_DE_*` thresholds.** *Protects:* the generalized Float128
exactness-by-width thresholds (C1) and the sticky-head soundness bound (C2).
*Assertions:* (i) **fixed point** at today's values —
`_DE_ADD(8,8) == 100`, `_DE_FMA(8,8,8) == 92`, `_DE_FAA(8,8,8) == 98` — with
the **corrected** FMA formula; (ii) positivity for every `P ≤ 16`;
(iii) **band contiguity**: for every `P ≤ 16` and every `N ≤ 60`, no ΔE is
uncovered by the Float128 / BigExactF / StickyF three-way split; (iv)
**soundness**: for operand pairs constructed at a spread just below each
threshold, the Float128 result equals the MPFR result exactly. (iv) is the one
that matters; (i)–(iii) are arithmetic about the formulas.

**G2 — `bigprec` sufficiency.** *Protects:* the latent truncation `_BIGP = 2200`
becomes once B > 1024. *Witness:* `Binary16p1uf`'s `MaxFinite = 2^32766` and
`MinPositive = 2^-32767`, spread 65533, **taken from the lattice** (§3.3).
*Oracle:* `Rational{BigInt}` (`refimpl`). *Assertions:* `bigprec(…)` exceeds
`spread + max Pᵢ + 1`, and the BigFloat sum at that precision equals the exact
rational sum. **Write it red.**

**G3 — `_rtp_f64` bit ≡ generic, widened.** *Protects:* the bit path's shift
bounds, derived for `d ≤ P−1 ≤ 7` and now claimed for `P ≤ 16` (`t ∈ [37, 52]`
instead of `[45, 52]`; `Sfl ≤ 2^16` still fits `Int64`). *Domain:* the full
`(P ≤ 16, B ≤ 512, μ)` grid — a T2-shaped enumeration — crossed with a
structured Float64 input set (binade edges, subnormal boundaries, exact ties,
ties ± 1 ulp, extremal datums). *Assertion:* field-for-field equality. Note the
comment at [`project.jl:90`](../../src/project.jl#L90) says `d ≤ P−1 ≤ 7`; the
correction is trivial and it is the **gate**, not the comment, that licenses
the claim.

**G4 — rung-selection equivalence.** *The central gate.* For a specialization
whose selected rung is `r`, evaluating the same operands with the carrier
forced to rung `r+1` (and `r+2` where defined) must produce the **identical
code point**. Rung `r+1` is a strictly wider exact carrier over the same
monomial domain, so if the selection is sound both evaluations are exact and
project identically; if it is unsound they differ. It is therefore precisely a
soundness test for `rung(op, Fs…)` and needs no reference implementation.
*Domain, boundary-targeted:* (i) every format whose ΣB is within one power of
two of a boundary (512/1024/2048, 8192/16384/32768); (ii) all 8 Group C
formats; (iii) **every block/scaled operation** — the four-factor
`ScaledMultiply` case is the one a naive per-format rule gets wrong, so it must
be in the gate, not in a comment; (iv) a fixed-seed interior sample; (v) pure
**and** stochastic ρ with explicit `R`. *No production knob:* the test calls
`ωeval(HeadF128(), …)` directly. A runtime rung-override switch would become a
way to reach a wrong answer from user code.

**G5 — K ≤ 8 golden non-regression.** Captured at Stage 0 *before* any edit,
compared byte-for-byte. The exit criterion for Stages 1 and 2 and a standing
gate thereafter. Implemented in [`test/golden/`](../../test/golden/); the gate
is [`test/golden.jl`](../../test/golden.jl).

**Two tiers** (measured — see §11 M2). The full sweep costs ~5 minutes, which
is right for a stage exit and wrong for a gate you want to run after every
edit, so:

| tier | sections | cost | when |
|---|---|---|---|
| `:fast` | meta, decode, lattice, order, project, packed, sort | **57 s** | after **every** edit |
| `:lazy` | + the cheap full sections in full, and a ~1/6 format sample of the three expensive ones | ~3 min | **stage exit** (the routine gate) |
| `:full` | + convert, unary_default, unary_rho, binary, ternary, blocks, kernels, juliacompat | ~10 min | **Stage 2 exit** and release |

**Why `:lazy` is the routine stage gate, and where it is not enough.** The
expensive sections are defence in depth: an arithmetic result cannot move
without `decode`, `project` or the code lattice moving first, and those are in
`:fast`, exhaustive over all 120 formats at every tier. Sampling the operation
catalogue therefore trades a small amount of redundancy for a 3× shorter gate,
which is the right trade for a gate run at every stage boundary.

**Stage 2 is the exception and must exit on `:full`.** It is the one commit
that changes the type of every value in the package, and the one place where a
defect could plausibly be format-specific rather than systematic — precisely
the failure a 1-in-6 format sample can miss. The same applies to release.

*Figures measured, not estimated (§11 M2, M12). `:full` is dominated by two
sections — `unary_rho` and `unary_default` — because a unary table entry is one
oracle trip and 24 of the 30 unary operations are MPFR directed-enclosure
ladders at ~0.5–1 ms each. Everything else together is under 2 minutes.*

**The `:lazy` sections carry their own names and their own golden entries**
(`unary_rho~lazy`, `unary_default~lazy`, `binary~lazy`). That is forced rather
than stylistic: a digest over a sampled format list is a different number from
the digest over the whole list, so reusing the full section's name would make
every lazy run report a spurious mismatch. `capture.jl` writes every tier's
sections into the one file, so any tier is checkable against it.

The sample is **deterministic** — a fixed stride over the format list, always
including the first and last entries so the extremes of the grid are never
dropped. A golden whose contents depend on a random draw is not a golden.

The split is a wall-clock decision, not a coverage concession: the fast tier is
exhaustive over all 120 formats for exactly the stages a type refactor can
move — storage, traits, constructors, the decode/encode plumbing, and the
projection engine. An arithmetic result cannot change without one of those
changing first. The full tier measures that claim rather than asserting it.

*What is digested is semantic observables only* — code points, decoded bit
patterns, class tags, order keys — never printed type names, because Stage 2
changes `show` for the abstract format on purpose. A golden that fires on an
intended change is a golden that gets disabled.

**G6 — carrier-lift exactness (new).** Every `lift(h, decode(v))` is exact for
every datum of every format, and no narrowing `lift` method exists. A T1-tier
sweep, 7.6 M points. Protects R-B's mixed-format join, which is otherwise
unverified.

**G7 — `HeadExact` carrier-swap differential (new).** The Group C surface
produces identical code points under `BigFloat` and under `Dyadic`. Free (both
implementations exist between Stages 6 and 7), needs no oracle, and is the
strongest available check on the `Dyadic` arithmetic and its
`round_to_precision` method. Stage 7's exit criterion.

**G8 — representation invariant at every K (new).** For every format and every
code point: `codepoint(v) & ~codemask(T) == 0`, `codepoint(T(c)) == c` for `c`
offered as each of `UInt8`/`UInt16`/`UInt32`/`UInt64` in range, out-of-range
codes throw at every width, and `parse ∘ show` round-trips. Folded into tier
T1; called out separately because it is the cheap sweep that surfaces the whole
checked-conversion class (C5).

**G9 — trait folding (new).** For every one of the 504 formats and every type-
or tag-valued trait (`reptype`, `codeunit_type`, `datumcarrier`,
`promotecarrier`, `rung`, `decodepolicy`, `orderkeytype`): the inferred return
type is concrete and the call allocates nothing. ~5,000 cheap assertions.
**This is what licenses R-A**; without it, `Val`-barrier traits rest on
"usually folds", which is exactly the reasoning doingtheextensions rightly
rejects.

---

## 6. Test doctrine under wide K

### 6.1 The doctrine restated

The current rule — "enumerate rather than sample; the value sets are small
enough that sampling is never necessary" — is a **theorem with a hypothesis**:
*for K ≤ 8 every specialization's input space is at most 2^24 points, therefore
exhaustive enumeration is affordable.* The hypothesis is `K ≤ 8`. At K = 16 a
same-format binary specialization has 2^32 input pairs and a ternary one 2^48;
the conclusion no longer follows. The response is to find the largest sub-claim
that is still a theorem, state it, and name precisely what is left over.

### 6.2 The tiers, with corrected domains

| tier | scope | policy | budget |
|---|---|---|---|
| **T1 lattice** | decode/encode round-trip, order-key monotonicity, `Next*`, `Class`, special codes, `show`/parse round-trip, G6, G8 | **exhaustive, every format, every K** | **7 602 160** points (verified) |
| **T2a rounding** | `round_to_precision` | exhaustive over `(P, log₂B, μ)` × a structured carrier-value set, **format-free** | **135** parameter pairs × 27 ρ |
| **T2b saturation** | `saturate`, `encode` preconditions | exhaustive over `(P, log₂B, Σ, Δ)` × a structured `Rounded` set | **504** parameter tuples × 27 ρ |
| **T3 composition** | `ωeval ∘ project`, per specialization | exhaustive to a stated point budget (2^22 ⇒ binary exhaustive through K = 11, ternary through K = 7) | 2^22 points |
| **T4 edges** | specializations above the T3 budget | threshold-derived edge set + fixed-seed random, **reported as sampled** | fixed |
| **T5 differential** | G4, G7, MPFR-only configuration, `refimpl` | always on, boundary-targeted | small |

The T1 total is measured, not estimated: summing `2^K` over all 504 formats
gives 7 602 160 (13 296 of them at K ≤ 8), against a suite that already runs
~8.9 M assertions. **The full code-lattice sweep at every K is affordable in
the shipped suite and must stay exhaustive.**

### 6.3 The specialization dimension

Wide K forces a second sampling dimension into view: 51 operations × 504 result
formats × operand formats × 27 projection specifications — ~694 k same-format
specializations against ~165 k today. The suite already samples this dimension
(`allfmts` sweeps beside hand-picked sets such as
`(Binary8p4se, Binary8p1uf, Binary5p2se, Binary3p1se)` at
[`runtests.jl:1011`](../../test/runtests.jl#L1011)), but the selection is
implicit in the harness structure. Stage 8 makes it explicit and **derived**
(§4, Stage 8 step 3). The full cross-product is the opt-in sweep, not the
shipped suite.

### 6.4 What is knowingly not covered

Stated once, plainly, so it is not rediscovered as a surprise:

- Multi-operand input cross-products above 2^22 points for K ≥ 12 — covered by
  T4's derived edges and seeded random, **reported as sampled**.
- κ for binary and ternary specializations at K ≥ 12 — `measure_kappa` already
  reports `exhaustive = false` and `conformance_report` already prints
  "(κ sampled — not exhaustive)" ([`approx.jl:335`](../../src/approx.jl#L335)).
  No mechanism change; the honesty is already built in. Invariant 5 survives
  wide K unchanged because it was designed as a *measurement*, not an
  assertion.
- `f32_exact`'s enumeration at K ≥ 12, per its §9 disposition.

---

## 7. Performance

| path | K ≤ 8 today | Group A, K 9–16 | Group B | Group C |
|---|---|---|---|---|
| scalar `Add` | ≈ 26 ns | ≈ 26 ns (2-byte unit, computed decode) | ~5–20× | MPFR: µs; `Dyadic`: ~2–4× |
| `project` | ≈ 13 ns | ≈ 13 ns | generic `_rtp_core` | integer-only; likely fastest of the three |
| array unary | table gather | gather, ≤ 128 KiB table | same | same |
| array binary | gather ≤ 64 KiB | gather to ΣK ≤ 18, else compute | same | same |
| warm-path allocation | zero | zero | zero (`Float128` is a bitstype) | zero with `Dyadic`; nonzero with `BigFloat` |

**Non-negotiable pins.** K ≤ 8 scalar `Add` and `project` must not regress past
noise from the Stage 0 baseline, and the zero-warm-path-allocation pins hold
for `HeadF64` and `HeadF128` unconditionally. T8 restates allocation discipline
**per head**, so a Group C `Log` allocating is a recorded property of that tier
rather than a suite failure — and the benchmark preflight's abort condition
becomes per-head to match.

**Three measurements that must decide open questions rather than be guessed:**

1. **Computed decode versus a cached decode table at K ∈ 9:12** (≤ 32 KiB in
   the existing `TABLE_CACHE` style). Whether a 4–32 KiB table beats ~10
   integer ops plus an `ldexp` is a cache-pressure question with no a-priori
   answer. R-F makes the answer a one-line change to `decodepolicy`, so ship
   computed decode and measure.
2. **Whether Group B wants a `_rtp_f128` bit twin.** It would be a permanent
   *third* member of the twin-predicate family that
   [`project.jl:62-66`](../../src/project.jl#L62) warns must be kept in sync.
   Do not write it before Group B benchmarks justify the maintenance surface.
3. **First-use compile latency for a cold wide format** (R4), tracked against
   the Stage 0 baseline. T10 forbids the tempting-but-wrong `@nospecialize`
   fix: table builders, conformance reporting, and κ measurement are called
   once per signature and their whole value is specialization. The mitigation
   is the precompile workload's *contents*.

---

## 8. Risk register

| id | risk | likelihood | mitigation |
|---|---|---|---|
| R1 | Stage 2's type refactor regresses a K ≤ 8 result | med | G5 captured **before** the refactor (Stage 0); Stage 2 adds no formats, so any diff is the refactor |
| R2 | A hidden `UInt8` assumption survives into a wide path | **low** (was med) | **C5**: every `UInt8(…)` in the package is a *checked* conversion and no unchecked truncation idiom exists in any K-dependent layer, so this class fails loudly at first use. G8's construction sweep surfaces it in one cheap run. The residual silent surface is three things only: oversized shifts (removed structurally by T11 in Stage 1), abstract-type stores through `Ref{Type{<:…}}` (C4, fixed in Stage 2), and table-size `Int` overflow (asserted, `ΣK ≤ 48`) |
| R3 | `_BIGP` truncation ships undetected | med | G2 written red first (Stage 6), `Rational{BigInt}` oracle |
| R4 | Compile latency explodes at 504 formats × 51 ops × 27 ρ | **low–med** (was med) | R-A removes ~2 500 generated methods from the plan, so the grid contributes ~15 trait methods rather than thousands; precompile workload stays K ≤ 8 + one Group A wide + one Group B; first-use `@time` tracked from Stage 0 |
| R5 | A `Union`-typed trait leaks into a hot path and allocates | low | T3′ makes every trait dispatch-shaped; **G9 verifies it per format**, converting the argument into a measurement |
| R6 | Rung selection is subtly wrong for block/scaled monomials | med | G4's domain **must** include the four-factor `ScaledMultiply` case; `factors` is a registry column so generated variants carry their own counts |
| R7 | A wide `_DE_*` threshold widens an exactness claim | **med (new)** | C1 and C2 are both threshold errors found by arithmetic, not by testing. G1(i) fixed-point, G1(iii) band contiguity, and G1(iv) soundness are the machine check; the formulas must be re-derived at implementation time and G1 must be written first |
| R8 | Mixed-format operands reach an `ωeval` row that does not exist | **med (new)** | R-B's carrier join, with G6 enumerating lift exactness and the deliberate absence of a narrowing `lift` turning the failure into a compile-time `MethodError` |
| R9 | Table build stalls a first array call for seconds at K = 16 | low | parallel build (Stage 5) + cost-aware eager band + declined-signature reporting |
| R10 | Test wall clock outgrows `Pkg.test()` | med | budgets as `Ref`s (T9); `SmallFloats_EXHAUSTIVE` split; the 7.6 M-point lattice sweep is affordable, the composition tiers are what get budgeted |

---

## 9. Decisions required before Stage 2

Four. Each is cheap to answer now and expensive to reverse later.

1. **Export surface.** Recommended: export the 120 K ≤ 8 names as today, define
   all 504, and add an opt-in `SmallFloats.Formats` submodule re-exporting the
   rest. Asymmetric reversibility settles it — exporting more later is
   non-breaking, un-exporting is.
2. **`f32_exact`** (A3, unconsumed; each answer costs up to `2^(K1+K2)` BigFloat
   comparisons). Recommended: **restrict its domain to K ≤ 11 by construction**.
   Its premise — Float32 datum-exactness — fails once `B > 128` anyway, so it
   can only return `true` in the high-P corner of the wide grid. The
   alternatives are building the consumer (the SIMD stochastic loop sketched in
   [Float32more.md §3.4](Float32more.md), never written) or deprecating.
3. **`DefaultAccumulatorType`** (A4, unconsumed; a full setter/getter/combinator
   surface over `_GUARD_ACCUM = binary32` that nothing reads, while `blocks.jl`
   uses its own exact wide-precision accumulator). Recommended: **wire it into
   the reduction accumulator's precision choice**, where wide K makes it
   genuinely useful — or document it as advisory. Do not carry an unconsumed
   knob into a 504-format grid.
4. **`PackedVector` at K = 16.** Recommended: **refuse loudly**, with a message
   pointing at `Vector`. Packing is the identity there and a silent identity
   invites benchmark confusion.

Two further questions may be deferred to measurement: whether `max_exhaustive`
should rise (and whether it belongs in `Preferences.jl` rather than a `Ref`),
and whether `Dyadic` should eventually replace the float carriers entirely.
The `rung`/`datumcarrier` traits are the seam that keeps the latter a local
decision rather than a rewrite; revisit only with a benchmark showing `Dyadic`
within 1.5× of `Float64` on scalar `Add` at K ≤ 8.

---

## 10. What this pass changed

| # | change | reason |
|---|---|---|
| 1 | **`_DE_FMA`'s generalization corrected** (margin 3 → 4, i.e. `P₁+P₂+2`) | It gives 93 at P = 8, not today's 92, so G1(i) as specified fails on day one. A wrong threshold *widens* an exactness claim, which no other test can see |
| 2 | **The sticky-head / width-threshold collision at P = 16 identified and resolved** | `StickyF`'s soundness needs `ΔE > (P−1)+N+2`, independent of the width bound. At P = 16, N > 15 the two conflict. A three-way band split with a fixed point at P ≤ 15 closes it |
| 3 | **The exact-signature sweep sized: 29 sites, 5 files** | The predecessor scoped it to `formats.jl`. The four sites outside it are the dangerous ones — the table cache key, both decode tables, `encode`, and the three in `defaults.jl` |
| 4 | **C4 found: `DefaultType!` silently stores an abstract format** | The only genuinely silent wide-K defect in the package, and a live violation of the invariant the plan is adding |
| 5 | **The "silent truncation" hazard class shown to be empty** | Every `UInt8(…)` in the package is a checked conversion; no unchecked idiom exists in any K-dependent layer. A1 is re-graded from silent-wrong-κ to loud failure, R2 drops to low, and Stage 3's cheap construction sweep becomes the highest-value test per line |
| 6 | **Engine domains corrected: 135 for rounding, 504 for saturation** | The 252 figure counts `(P, log₂B, Σ)`, which is neither stage's domain. The saving is larger than claimed for `round_to_precision` and **nil** for `saturate` |
| 7 | **The `Dyadic` add bands corrected** | The predecessor's ΔQ ≤ 95 omits the carry bit and its "P ≤ 45 at N = 60" corresponds to a 20-bit head, not the 32-bit head it states. Correct: ΔQ ≤ 94, coverage requires `P + N ≤ 92`, current margin 16 |
| 8 | **R-A: traits by `Val`-barrier dispatch, not generation** | ~15 methods instead of ~2 520, no `@eval` in the trait path, no precompile growth with the grid, and strictly safer than the ternary D3 rejects. G9 converts "usually folds" into a per-format verification. Merges T3 and T4 into one rule |
| 9 | **R-B: the mixed-format carrier join specified** | The spec register accepts operands of *different* formats at every arity. After the carrier split their decoded types differ and no `ωeval` row matches. Neither predecessor addresses it |
| 10 | **R-C/R-E: carrier-generic special values; `datumcarrier` split from `promotecarrier`** | `decode`'s NaN/±Inf rows are Float64 literals; and promoting Group C to `Dyadic` would force a full `Real` interface on an internal carrier. Promoting to `BigFloat` keeps `Dyadic`'s surface at ~10 methods |
| 11 | **R-D: the table cache split by code unit** | "`Memory{U}`" is under-specified: one `Dict` with a widened value type makes every gather loop index an abstractly-typed array, which is the one thing the kernel design exists to prevent |
| 12 | **C10: the projection engine needs no carrier work** | `project`/`round_to_precision` are carrier-polymorphic and correct for any exact input, so `Convert`, `one`, `zero`, `eps`, and the whole write path work for all 504 formats with zero carrier work. States the scope of the carrier project correctly |
| 13 | **C8: `_cmp_rounded_datum` has no call site** | Third unconsumed surface after `f32_exact` and `DefaultAccumulatorType`, and the only one whose logic wide K might want |
| 14 | **C9: the doctrine file does not exist in this repository** | Both predecessors instruct amending a `CLAUDE.md` that was not copied with the rename. Invariants 8–10 have nowhere to live; a Stage 0 blocker |
| 15 | **G6–G9 added; G1 extended to band contiguity** | Each new gate corresponds to a defect class introduced above that the inherited five do not cover |
| 16 | **Stage 0 added; nine stages became ten** | Golden capture, doctrine reconstitution, baselines, and the four decisions are prerequisites, not step 1 of the first edit |

---

## 11. Execution log — modifications made while implementing

*Appended as each stage is executed. A plan is a hypothesis; this is what
contact with the code changed about it. Items are numbered `M<n>` and are
referenced from the stage and gate text above.*

### Stage 0

**M1 — the repository did not build; C9 understated the state of the rename.**
`Project.toml` was rejected by Pkg outright: `[compat]` had `Julia = "1.12"`
(the key must be lowercase `julia`) and the metadata key was `author` rather
than `authors`. `Pkg.instantiate()` therefore failed, and with it every
subsequent action — the suite, the golden, a bare `using`. C9 reported a
missing doctrine file; the truth was that the copy from `ByteFloats.jl` left
the tree **unbuildable**, which is a stronger reason for Stage 0 to exist than
the one given. Fixed, plus `SHA` declared in `[extras]`/`[targets]` for the
golden harness. *Baseline once building: the full suite passes — ~8.9 M
assertions, 2 m 33 s.*

**M2 — G5 is tiered, because the full sweep costs 15 minutes.** The first
capture attempt ran 13 minutes before failing. Profiling by section showed the
cost is almost entirely the unary catalogue: 30 operations × 4 ρ × 120 formats
≈ 14 400 tables, and a table entry is one oracle trip at a measured **~200 µs**
for the MPFR-backed transcendentals. A gate that costs minutes is a gate that
gets skipped, so G5 splits into `:fast` (**57 s** measured, run after every
edit) and `:full` (**15 min 13 s** measured, run at stage exit).

*The tiering worked; the sizing estimate did not.* This entry first claimed
`:full` would cost ~5 minutes after the M4 subsetting. Measured: 913 s, of which
`unary_rho` is 532 s and `unary_default` 196 s — 80 % in two sections. M4 cut
the format count for ρ-breadth but the surviving 46 representative formats ×
30 ops × 3 ρ is still ~4 100 MPFR-backed tables. The lesson is the one this
project keeps relearning: **a cost model over MPFR work is worthless until
measured.** If `:full` needs to come down further, the lever is ρ-breadth on
the transcendental catalogue, not format count.

**M3 — the golden is a standalone harness, not instrumented testsets.** See
Stage 0 step 2. Digesting the existing suite's testsets would couple the oracle
to the suite's *structure*; enumerating the surface directly couples it to the
package's *behaviour*, which is what is being protected.

**M4 — ρ-breadth for the expensive catalogue is bought on a derived
representative subset.** Sweeping 30 unary ops × 4 ρ over all 120 formats is
~3.7 M MPFR ladders. The full-grid claim that matters for G5 — that no format's
decode, projection, ordering or code lattice moved — is carried exhaustively by
the fast tier; ρ-breadth over the operation catalogue is defence in depth and
runs on a subset **derived from the grid** (for each `(K, Σ, Δ)`, the extreme
and middle precisions), never hand-listed. This is Stage 8's
"derived-not-hand-listed" rule applied a stage early, where it first bites.

**M5 — there is deliberately no `conformance` section in the golden.**
`conformance_dict()` embeds `collect(keys(TABLE_CACHE))`, so its value depends
on which tables happen to be cached when it is called — nondeterministic across
runs and across section orderings — and it lists the 120 format names, which
Stage 3 changes to 504 **on purpose**. Digesting a *declaration* byte-exact
guarantees false positives of both kinds. Invariant 5's real content (κ
measured by exhaustive enumeration at registration) is pinned by the suite.

### Stage 1

**M7 — the disposition-(a) signature widening moves from Stage 2 to Stage 1.**
Appendix A splits the 29 exact `::Type{Binary{K,P,S,E}}` signatures into
(a) widen to `<:`, (b) retarget to the representation, (c) keep exact. The plan
put all three in Stage 2. But while `Binary` is still concrete,
`::Type{<:Binary{K,P,S,E}}` and `::Type{Binary{K,P,S,E}}` **match exactly the
same single type**, so every (a) site can be widened at Stage 1 as a provably
zero-behaviour-change edit — and Stage 1's exit is G5, which verifies that
completely.

Doing so is strictly better than the plan: it removes ~21 of the 29 sites from
the diff of the single riskiest commit in the project, leaving Stage 2 to carry
only the edits that genuinely need the type refactor (the (b) sites, which must
route through `reptype`). *Rule generalized:* **any edit that is a no-op while
`Binary` is concrete belongs in Stage 1, not Stage 2.** The same argument moved
the T11 complement migration there, and for the same reason.

**M12 — M4's "representative subset" was 58 % of the grid, and the ρ sweep paid
for work it re-derived.** Measuring `:full` by section exposed two sizing errors
in my own harness, both of the same kind: a claimed reduction that was not
computed.

*The subset was not a subset.* `representative_formats()` took three precisions
per `(K, Σ, Δ)` cell — the two extremes and the midpoint — giving **70 of 120
formats**. Since `B` is monotone in `P` at fixed `K`, the midpoint is
interpolation between the two ends for every trait these sections exercise, so
it bought repetition rather than coverage. Two-per-cell gives 46.

*The ρ sweep re-derived ρ-independent work.* For a given `(op, format, code)`,
`ωeval` yields the same exact value or enclosure whatever ρ is; only `project`
differs. Sweeping three pure ρ therefore ran the MPFR ladder three times to
exercise three projection modes — roughly **350 s of the 532 s** spent
recomputing identical intermediates. Cut to two directed modes on opposite
sides (`RTZ_SatFinite`, `RTP_SatPropagate`); `RTO` remains covered exhaustively
over all 120 formats by the `project` section, which is carrier-cheap.

*What was deliberately NOT done.* The tempting fix is to call `ωeval` once and
project it under each ρ. That would be correct arithmetic and wrong testing:
the golden's job is to exercise the scalar path invariant 6 names, and a
harness that bypasses that path no longer protects it. **Cut the breadth, keep
the mechanism.**

### Stage 2

**M13 — the `similar` normalization is only implementable on the `Array`
family.** §1's migration plan specifies
`Base.similar(A::AbstractArray, ::Type{Binary{K,P,S,E}}, dims)`. That method is
more specific in the element-type slot and *less* specific in the container
slot than every container-specialized `similar` in Base and the stdlibs, so it
is ambiguous with all of them — measured: `Diagonal`, `Hermitian`,
`SymTridiagonal`, `LowerTriangular`, `UnitLowerTriangular`, `UpperHessenberg`,
`Adjoint`/`Transpose` (vector and matrix forms), `ReinterpretArray`. That family
is **open-ended**: any package defining `similar(::MyArray, ::Type{T})` adds
another, so adding disambiguators does not terminate, and Aqua's ambiguity gate
is in the shipped suite.

Resolution: scope the normalization to `Vector`, `Matrix` and `Array`, which is
what the package's own kernels and `similar(A, fr)` calls actually use, and
which shadows exactly Base's three specializations — closed and ambiguity-free.
Every other container keeps stock Base behaviour, which fails loudly on an
abstract element type. That is the correct outcome, since the aliases and
`format(K,P,Σ,Δ)` are the supported route.

*Two arities are needed, not one.* `similar(a, T)` does not funnel through the
three-argument method for `Array` — it reaches `Array{S,N}(undef, size(a))`
directly — so a three-argument-only normalization is silently bypassed for
exactly the container people use. Found by test, not by reading.

**M14 — every representation trait needs an abstract-format forwarder.**
`codeunit_type`, `decodepolicy` and `orderkeytype` dispatch on `Code8`/`Code16`
(the seam), but Group M and the extremal queries are bounded by
`::Type{<:Binary{K,P,S,E}}`, which **admits the abstract format itself** — and
asking a *format* for its extremal code point is legitimate usage that both the
suite and the documentation do (`MaxFiniteOf(Binary{5,2,true,true})`). Without a
forwarder those calls reach `codeunit_type` with an abstract argument and die
with a `MethodError`. Each trait therefore gets three methods: one per
representation, plus an exact `::Type{Binary{K,P,S,E}}` forwarder through
`reptype`. The exact signature matches only the abstract type, so it cannot be
ambiguous with the two `<:Code*` methods.

*Related, same cause:* the `Val(:code)` constructor forwarder must narrow the
code to the representation's unit **before** reaching the inner constructor.
Without that, a `UInt8` code aimed at a `Code16` format raises a `MethodError`
before `@boundscheck` can run `checkformat`, turning a parameter-validation
error (`ArgumentError` for K = 9 at this stage) into a dispatch error. That path
is deliberately not `@inbounds`: it is the checked route and the check is the
point.

**M15 — G5's own completeness check failed `:full` by construction.** The Stage 2
exit run reported `30 passed, 3 failed` and the three failures were *not* moved
results: all fifteen digests `:full` computes matched the oracle byte for byte.
The gate's second loop — "a section in the oracle but absent from the harness is
a deletion" — was written as `for name in keys(want); @test any(p -> first(p) ==
name, got)`, comparing the oracle's **18** entries against the **15** a `:full`
run produces. The three `~lazy` sample sections are in the oracle (`capture.jl`
writes every tier's entries, by design — §4 Stage 8) and are never computed at
`:full`, so they failed every time. The check was testing the tier table, not the
harness.

Fixed by comparing the oracle's names against `all_sections()` — the harness's
declared set — which is what "did a section disappear" actually means, and which
is correct at *every* tier, so the check no longer needs to be `:full`-gated.

*Second defect, same file:* a stray guard forced `ENV["SMALLFLOAT_G5"]` (missing
the `S`) to `"lazy"` whenever it was unset **or equal to `"full"`**. The typo
made it dead code; had it been spelled correctly it would have silently
downgraded exactly the tier Stage 2 mandates. Replaced with
`get!(ENV, "SMALLFLOATS_G5", "lazy")`: `lazy` becomes the routine default (which
is what the suite should run per edit), and an explicitly requested tier is
always honoured. **A gate that quietly runs less than it was told to is worse
than no gate.**

**M10 — G9's predicate is `Base.isdispatchelem`, not `isconcretetype`.** The
obvious spelling of "this trait folded to one exact answer" is
`isconcretetype(only(Base.return_types(trait, Tuple{Type{F}})))`. It is wrong
for exactly the traits G9 exists to protect: a type-valued trait infers to
`Type{Float64}` / `Type{UInt8}` / `Type{Code8{…}}`, and **`isconcretetype(Type{Float64})`
is `false`** — `Type{X}` is a kind, not a concrete type, even though it has one
inhabitant. The mistake fails every type-valued trait while passing every
tag-valued one, which reads exactly like a real defect in the trait design and
is not. `Base.isdispatchelem` is the correct predicate: true for a concrete
type and for a `Type{X}` singleton, false for a `Union` and for `Any` — which
is precisely "inference resolved this call to one exact answer". Written down
because the false reading would have sent the next person to re-introduce D3's
2 520 generated methods to fix a problem that does not exist.

**M11 — the golden was captured from a clean `main` worktree, not from HEAD.**
Checkpoint §6 flagged this as the one property that can only be lost once:
`src/formats.jl` already carried the (asserted zero-change) Stage 1 edits, so
capturing in place would have made G5 partly self-referential. Resolved by
`git worktree add` at `main`, copying in only `Project.toml` (the build fix —
without it the worktree cannot instantiate) and the harness, and capturing
there. The golden's header records `git: 51abb00`, which is the commit the
oracle actually describes. **G5 fast then passed 7/7 against the Stage 1 tree**,
which is the intended use: the oracle is independent of the code it judges.

**M8 — `_cu(F, x)` as the single narrowing point.** The T11 rewrite needs the
storage unit at a dozen sites (`signmask`, `nan_code`, the four extremal
codes …). Spelling `codeunit_type(F)(x)` at each is noisy and invites someone
to shortcut it back to a `UInt8` literal. One `@inline _cu(::Type{F}, x)`
helper makes the unit a single grep-able point and keeps every constant a
literal after folding. The special-code block now reads as arithmetic on
`signmask`/`codemask` rather than on `1 << K`, which is also what makes the
four `MaxFiniteOf` rows collapse into one expression.

**M9 — `Convert` is registry arity 1 but registry group `:conv`, and every
consumer that filters by arity alone walks into it.** The first harness built
its unary list as `arity == 1` and died in `apply_op` with
`MethodError: no method matching ωeval(::Val{:Convert}, ::Float64)` — `Convert`
has no ω-semantics, and `tables.jl`'s `_scalar_code` special-cases it into a
bare projection. Recorded here because **Stage 6 adds `factors` as an `OpInfo`
column** and will iterate the registry the same way: `factors(:Convert)` must
be defined (or `:conv` excluded) or the same trap fires in the carrier
selection, where it would be far less obvious. The rule for every registry
consumer is **filter by `(arity, group)`, never by arity alone.**
*Closed in Stage 3 by giving `Convert` the ω-semantics it actually has — the
identity on the datum. See M18.*

### Stage 3

**M16 — two Stage 4 items moved into Stage 3, on a hazard-class rule.** Stage 3
opens the grid to 504 formats while the wide *paths* land in Stages 4–7, so the
stage's whole discipline is that an unimplemented route fails loudly. Sorting
the changes by how they fail rather than by which stage listed them gives a
rule: **a route that would fail loudly waits for its stage; a route that would
be silently wrong does not.**

Two of Stage 4's items are the second kind:

* *Order keys.* `order_key` computed `UInt16(c) + UInt16(1)`. At K = 16 the top
  code is `0xffff`, so the largest datum's key **wraps to 0** and sorts below
  the smallest — no exception, no warning, a total order that is not one.
  `orderkeytype` already returned `UInt32` for `Code16`; the key function simply
  was not reading it. Now `nan_order_key(F) = typemax(orderkeytype(F))` per
  format, replacing the `NAN_ORDER_KEY` constant.
* *Counting sort.* It reads `NAN_ORDER_KEY` and builds `Vector{UInt8}`, so it had
  to move with the key type regardless; the `n < 2^K` length gate came with it
  rather than leaving a sort that works while allocating 512 KiB of buckets to
  order three elements.

Everything else Stage 4 owns — `decode`'s wide path, `PackedVector`, the
Float32 surface — throws today and stays where the plan put it.

**M17 — `decode` and `_decode_table` refuse by METHOD, and the refusal has to be
a method that throws rather than a method that is absent.** `decode` now
dispatches on `decodepolicy` (R-F, a Stage 4 item in shape but forced here):
`_decode_compute`'s tail is still the Float64 bit assembly whose justifying
comment is *literally* the K ≤ 8 premise, and at B ≈ 1024 a format's minimum
datum is a Float64 subnormal where the assembly returns garbage rather than
failing. So `ComputeDecode` throws until Stage 4 gives it the `ldexp` body.

`_decode_table` is bounded to `Code8` by *signature*, which is invariant 10
enforced where it can be: the tuple length is `2^K`, and asking for `K = 16`
must be an error at the call site rather than a 65 536-element constant tuple
the compiler dutifully materializes.

The first spelling of that bound made the `Code16` case an **absent** method,
and that was wrong for a reason worth recording. The abstract-format forwarder
(§11 M14) infers to `Union{Type{Code8{…}}, Type{Code16{…}}}` when the format
parameters are not statically known, so an absent method turns a deliberate
refusal into a static-analysis defect: JET's whole-package pass reports it as an
unreachable-method bug, and the only way back to green would be a filter — which
the verification doctrine says must be backed by a concrete-call gate proving
the path is clean. **It is not clean; it is refused.** A method that throws says
so, is total, and keeps the guard.

*Same shape, different site:* `show` must never be the thing that throws.
A testset that fails while comparing two wide values has to be able to print
them, or the report becomes an error inside the error reporter. `_show_datum`
dispatches on `decodepolicy` and prints the code point alone until decode is
total again.

**M18 — `Convert` gets its ω-semantics instead of another special case.**
`apply_op` now reaches the catalogue through `ωeval(rung(fr), op, xs...)`, and
that made JET see what §11 M9 predicted in prose: `ωeval(::Val{:Convert}, ::Float64)`
has no method, because `Convert` is registry arity 1 but registry group `:conv`.
The fix is one line — `ωeval(::Val{:Convert}, x::Float64) = x` — and it is not a
patch. Convert's ω-semantics **is** the identity on the datum; the conversion is
the projection into the target format, which `project` already does. Spelling it
makes `ωeval` total over the registry, so the next consumer that filters by
arity alone gets an answer instead of a `MethodError` far from the mistake.
`tables.jl`'s explicit `:Convert` branch stays: that one is not redundancy, it is
the statement that a Convert table entry is a bare projection, and it belongs at
the site where a table entry is defined to be the defined result (invariant 6).

**M19 — the K ≤ 8 test surfaces are scoped, not widened, and each for its own
reason.** Opening `_NAMED` to 504 silently changed the meaning of every loop
written as `for T in values(_NAMED)`. Three were affected and none of them
should simply grow:

* `golden_formats()` (G5). The oracle was captured at `51abb00` when 120 formats
  existed; its digests *are* statements about those 120. Widening the list would
  not strengthen the gate, it would invalidate every digest in the file.
* `float32surface.jl`. The narrowing-exactness claim and the pinned `f32_exact`
  counts (118/120 Multiply, 88/120 Add) are statements about the K ≤ 8 grid.
  Stage 4 gates this surface on the datum-exactness trait; until then, reading
  it over formats whose datums Float32 cannot represent measures nothing.
* `gates_g9.jl`'s zero-behaviour-change pin — which is the one that *earns*
  its scoping. Its Stage 1 comment said "when `Code16` lands this becomes a
  statement about the K ≤ 8 subgrid only, and that is the point". It now asserts
  120 narrow and 384 wide, that no narrow format's traits moved, and — the case
  a width/carrier conflation would fail and nothing else would — that a K = 16
  format can sit on **any** rung: `Binary16p14se` is rung 1, `Binary16p1uf` is
  rung 3.

The conformance-declaration length assertions were the opposite case: they were
literal `120`s and are now `sum(4K − 2 for K in KMIN:KMAX)`, because that
assertion is precisely a claim about the range and must move with it.

---

### Stage 4

**M20 — `decode`'s return type is now format-dependent, and three Base
constructors had to stop assuming otherwise.** `decode(v)` returns
`datumcarrier(typeof(v))`: `Float64` for 432 formats, `Float128` for 64,
`BigFloat` for 8. The consequence is easy to miss because it type-checks
everywhere: **`Base.Float64(v) = decode(v)` became wrong** — a method named
`Float64` returning a `Float128` for 72 of the 504 formats. It is now
`Float64(decode(v))`, which is the identity on the rung-1 path and therefore
free. `Float32` splits on `decodepolicy` (the narrowed-table gather for K ≤ 8,
`Float32(decode(v))` above it) and `BFloat16` routes through `Float64`.

These conversions **round**, in the ordinary Julia sense, and they always did —
what changed is that "always exact" stopped being true incidentally. `decode` is
the exact route; `decode!` is the exact *bulk* route and refuses rather than
rounds; `Float32(x)` rounds. Three surfaces, three contracts, stated.

*Second-order, and worth the three lines it costs:* `show` of a Group C value
printed **~78 decimal digits** for a one-bit significand, because `ldexp`
returns a `BigFloat` at MPFR's 256-bit default and the shortest-round-trip
printer honours the value's precision, not its information content. `show`
rebuilds the datum at `precision(F)` — exact, since a datum fits in `P ≤ 16`
bits by construction — purely for display. `decode` keeps the wide precision,
because a decoded datum goes on to be computed with. Stage 7 makes this moot by
replacing `BigFloat` with `Dyadic`.

**M21 — `PackedVector`'s "refuse at K = 16" is a rule that fires on one of two
identical cases, so it became a predicate instead.** §4 Stage 4 item 5 asked for
a loud refusal at K = 16 because packing is the identity there and a silent
identity invites benchmark confusion. Both halves of that are right, and the
boundary is still wrong: packing is *equally* the identity at K = 8, where
`⌈n·8/64⌉` words is exactly `n` bytes — and K = 8 has shipped since before the
extension and is enumerated by G5's packed section over all 120 formats.
Refusing K = 16 alone would encode an accident of history as a rule; refusing
both would be a breaking change justified by tidiness.

`packing_saves(F)` exposes the fact instead of enforcing it. Benchmarks and docs
read it; `PackedVector` at those two widths stays correct, supported, and
pointless.

**M22 — G3's domain is every `(P, B)` the grid realizes, not the rung-1 grid.**
§5 scoped G3 to `(P ≤ 16, B ≤ 512)` — the pairs where Float64 is the format's
*own* carrier. That is not the reachable set: `Convert(F, ρ, x::Float64)`
projects an external Float64 into **any** format, so `_rtp_f64` runs at every
bias in the grid, up to B = 32768. The wide-B region is exactly where the bit
path's `d < 0` branch would be exercised, and it turns out to be unreachable for
a normal Float64 input because `1 − B` drops below Float64's exponent range —
a fact worth measuring rather than asserting. **135 cells**, which is the same
135 that §1 C6 found for the engine's parameter domain, arrived at independently.

**M23 — the table builders refuse wide formats by name, not by `InexactError`.**
Stage 4 makes the *scalar* path work at every K; the tabulated path still indexes
operands as `UInt8` into a `Memory{UInt8}` sized `2^ΣK` with no byte budget, and
widening it is Stage 5. Left alone, a wide array operation died as
`InexactError: trunc(UInt8, 0x0400)` from three frames inside a builder — loud,
but naming neither the cause nor the remedy, and the remedy exists: the scalar
path works. `get_table` now refuses at all three arities with a message naming
Stage 5, and `test/stage_gates.jl` pins it.

*The guard's first spelling cost a JET failure worth recording:*
`all(F -> bitwidth(F) <= KSPLIT, Fs)` infers `Union{Missing, Bool}`, because
`all` with a general predicate is three-valued. That leaked into every array
entry point as "non-boolean `Missing` found in boolean context" — four
concrete-call gate failures from a guard that is constant-foldable. Spelled as a
recursion over the type tuple it is `Bool` by construction. **A predicate on
types should never be able to return `Missing`.**

**M24 — `decode!`'s Float64 gate is `datumsexact`, not `datumcarrier`, and the
gap between them is the point.** 454 formats have Float64-exact datums; only 432
are rung 1. The 22-format B = 1024 band decodes exactly into Float64 and still
needs `Float128` to *compute* in, because a product of two of its datums leaves
Float64's range even though each operand sits inside it. `datumcarrier` answers
a question about arithmetic; `decode!` asks a question about representation.
Using the arithmetic trait as the gate — which the plan's wording invited —
would have refused 22 formats for which the promise holds. The two axes §3.1
separates are separate here too.

*Testing note, from the first G6 run:* `Base.decompose` puts the **sign in the
denominator** — `decompose(-0.0078125)` is `(4503599627370496, -59, -1)`, a
positive significand over `den = -1`. Reading `den == 1` as "finite" silently
classifies every negative datum as non-finite, which is why the first run
reported 444 failures that were all correct code. Zero's exponent is also
carrier-specific (`(0, -1074, 1)` for Float64, `(0, 0, 1)` for BigFloat). Both
are absorbed in `gates_g6.jl`'s normalizer.

---

## Appendix A — the exact-signature sweep

All 29 occurrences of `::Type{Binary{` in `src/`, with disposition. **(a)** widen
to `<:`; **(b)** retarget to the representation; **(c)** exact by design.

| file:line | symbol | disp. |
|---|---|---|
| [`formats.jl:41`](../../src/formats.jl#L41) | `rawvalue` | b |
| [`formats.jl:57`](../../src/formats.jl#L57) | code-point constructor | b |
| [`formats.jl:64,65,67,69,71,73,75`](../../src/formats.jl#L64) | `bitwidth`, `precision`, `issigned`, `isextended`, `expbias`, `expbitwidth`, `trailingsigbits` | a |
| [`formats.jl:86,88,90,91`](../../src/formats.jl#L86) | `nan_code`, `posinf_code`, `neginf_code`, `signmask` | a (+ T11 rewrite) |
| [`formats.jl:99,104,109,111`](../../src/formats.jl#L99) | `MaxFiniteOf`, `MinFiniteOf`, `MaxSubnormalOf`, `MinNormalOf` | a (+ T11 rewrite) |
| [`formats.jl:144`](../../src/formats.jl#L144) | `formatname` | a |
| [`formats.jl:174,176,180`](../../src/formats.jl#L174) | `typemax`, `typemin`, `eps` | a |
| [`decode_encode.jl:36`](../../src/decode_encode.jl#L36) | `_decode_table` | b (`Code8` only after Stage 4) |
| [`decode_encode.jl:44`](../../src/decode_encode.jl#L44) | `_decode_table32` | b (`Code8` only) |
| [`decode_encode.jl:69`](../../src/decode_encode.jl#L69) | `encode` | b |
| [`defaults.jl:76`](../../src/defaults.jl#L76) | `_set_format_default!` | a **+ C4 body fix** |
| [`defaults.jl:82`](../../src/defaults.jl#L82) | `DefaultType!` | a |
| [`defaults.jl:94`](../../src/defaults.jl#L94) | `DefaultReturnType!` | a |
| [`tables.jl:24`](../../src/tables.jl#L24) | `_fkey` | a |
| — | `reptype`'s abstract case (new) | c |

Grep `::Type{Binary{` after Stage 2: every remaining hit must be dispositon
**(c)**, and there is exactly one.

Companion sweep, T1 (rebuilt format types in method **bodies**):
[`decode_encode.jl:6,37,45,60,70,98`](../../src/decode_encode.jl#L6),
[`formats.jl:219`](../../src/formats.jl#L219),
[`defaults.jl:78`](../../src/defaults.jl#L78). Eight sites; the last is C4.

---

## Appendix B — file-by-file index

| file | stages | nature |
|---|---|---|
| `dyadic.jl` | 7 | new, ~150 lines; first in include order |
| `carriers.jl` | 1, 6 | new, ~90 lines: `Head`, `DecodePolicy`, `carriertype` (both forms), `rung`, `datumcarrier`, `promotecarrier`, `bigprec` |
| `formats.jl` | 1, 2, 3 | abstract `Binary` + `Code8`/`Code16`; T11 complement constants; traits (R-A); constructor and `show` per invariant 2; `format`, `similar` |
| `projspec.jl` | — | none |
| `defaults.jl` | 2 | the three exact signatures; **C4's body fix**; `isconcretetype` assertion |
| `decode_encode.jl` | 1, 4 | `_decode_compute` reshaped (Stage 1); policy-dispatched decode, `ldexp` compute, widened encode/keys/sort (Stage 4) |
| `project.jl` | 1, 4, 7 | delete `_cmp_rounded_datum` (C8); comment fix `d ≤ P−1 ≤ 15`; `Dyadic` method + `_rtp_zero_sticky`. **No carrier work** (C10) |
| `ops_scalar.jl` | 6 | `factors` column; `rung` join and `lift` (R-B); per-head `apply_op` split |
| `juliacompat.jl` | — | none — the `Op(ρ, x::Binary)` unary forms dispatch on `Binary` and extend automatically (A5) |
| `oracle.jl` | 6 | per-head `ωeval` rows; `_DE_*(P…)` with C1's correction and C2's guard; `bigprec` |
| `tables.jl` | 1, 5, 9 | `_fkey`; unified byte-budget `_table_for`; **two typed caches** (R-D); parallel build; `f32_exact` disposition |
| `kernels.jl` | 4, 5 | conditional Shape A at every arity; carrier-typed and gated `decode!` |
| `blocks.jl` | 6, 7 | factor-aware rung; `blockdecode`'s carrier assertion; P = 1 scale fast path; accumulator precision from `bigprec` |
| `packed.jl` | 4 | unit widening; K = 16 refusal |
| `approx.jl` | 1, 3, 6 | **A1 fix**; conformance banner K range; `codedistance` follows the widened key; budgets as `Ref`s |
| `rand.jl` | 9 | reachability documentation only — the 53-bit draw leaves most wide-format datums unreachable; already true at K ≤ 8, typical at K ≥ 11 |
| `SmallFloats.jl` | 1, 2, 3, 9 | include order (16 layers); exports; `Formats` submodule; precompile workload |
| `test/` | 0, 3, 4, 6, 7, 8 | golden digests; G1–G9; restated tiers; `refimpl` promoted to shipped |
| `docs/src/*.md` | 9 | the 3–8 range and format counts; the `Binary16p*` ≠ `binary16` trap; feeds the LaTeX/PDF pipeline |
| `README.md` | 9 | **write** (currently two lines) |
| `benchmarking/` | 9 | per-rung sections; per-head preflight; own environment |
| doctrine file | 0, 2, 3, 9 | **reconstitute** (C9); invariants 2, 8, 9, 10; include-order comment; K range; restated test doctrine |
| `Project.toml` | — | **no change — zero new dependencies** |

---

## Appendix C — verification log

Every count and boundary in this document was recomputed under **Julia 1.12.6**.
The script is reproduced so the claims are re-checkable rather than trusted.

```julia
fmts = [(K,P,S,E) for K in 3:16 for P in 1:K for S in (true,false) for E in (true,false)
        if !(S && P >= K)]
B((K,P,S,E)) = S ? big(2)^(K-P-1) : big(2)^(K-P)
lg(f) = Int(log2(B(f)))

length(fmts)                                          # 504
count(f -> f[1] <= 8, fmts)                           # 120
count(f -> f[1] >= 9, fmts)                           # 384
count(f -> 2B(f) <= 1024,  fmts)                      # 432  Group A
count(f -> 1024 < 2B(f) <= 16384, fmts)               #  64  Group B
count(f -> 2B(f) > 16384,  fmts)                      #   8  Group C
sum(f -> 2^f[1], fmts)                                # 7_602_160  T1 budget
sum(f -> 2^f[1], filter(f -> f[1] <= 8, fmts))        #    13_296  (today)
length(unique([(f[2], lg(f))               for f in fmts]))   # 135  T2a domain
length(unique([(f[2], lg(f), f[3])         for f in fmts]))   # 252  (neither stage's domain)
length(unique([(f[2], lg(f), f[3], f[4])   for f in fmts]))   # 504  T2b domain
```

**Group C, exactly** (`B ≥ 16384`): `Binary15p1u{e,f}`, `Binary16p1s{e,f}`,
`Binary16p1u{e,f}`, `Binary16p2u{e,f}`.

**Extremal datums from the code lattice**, mirroring `_decode_compute` (note
each is up to two binades below the closed-form bound `(2^P−1)·2^(B−P)`):

| format | B | MaxFinite | MinPositive | spread | closed-form bound |
|---|---|---|---|---|---|
| `Binary8p1uf` | 2^7 | 2^126 | 2^-127 | 253 | 2^128 |
| `Binary15p1uf` | 2^14 | 2^16382 | 2^-16383 | 32765 | 2^16384 |
| `Binary16p1sf` | 2^14 | 2^16383 | 2^-16383 | 32766 | 2^16384 |
| `Binary16p2uf` | 2^14 | 2·2^16382 | 2^-16384 | 32767 | 2^16384 |
| **`Binary16p1uf`** | **2^15** | **2^32766** | **2^-32767** | **65533** | 2^32768 |

**Thresholds** (`_DE_FMA` with the corrected `P₁+P₂+2` accounting):

| P | `_DE_ADD` | `_DE_FMA` | `_DE_FAA` | `_STICKY_MIN(N=60)` | Float64 exact-add spread |
|---|---|---|---|---|---|
| 8 | 100 | **92** ✓ | 98 | 69 | ≤ 44 |
| 12 | 96 | 84 | 94 | 73 | ≤ 40 |
| 16 | 92 | **76** | 90 | **77** ⚠ | ≤ 36 |

The P = 8 row reproduces today's `(100, 92, 98)` exactly — the fixed point G1(i)
asserts. The flagged P = 16 cell is C2: `_DE_FMA = 76 < 77 = _STICKY_MIN`,
resolved by the three-way band split. The uncorrected formula
`113 − (P₁+P₂+1) − 3` yields **93** at P = 8 and fails G1(i).

**`Dyadic` add bands** (32-bit head significand, one carry bit):
exact `Int128` alignment to `ΔQ ≤ 94`; sticky from `ΔQ > P + N + 2`; total
coverage requires `P + N ≤ 92`; current worst case `16 + 60 = 76`, margin 16.

**Stochastic bit cap** `N ≤ 60`, from
[`projspec.jl:25-29`](../../src/projspec.jl#L25) — the constraint that makes
`_STICKY_MIN` and the `Dyadic` band arithmetic checkable rather than open.
