# Doing the extensions — design, architecture, and implementation direction for 8 < K ≤ 16

*Original status: implementation-directing document, written 2026-07-29 against commit
`9195d32`. Companion to [extendingK.md](extendingK.md), which established the
plan (grouping, counts, carrier boundaries, milestones) — this document turns
that plan into an architecture and a mandated set of Julia techniques, staged so
that **every stage compiles, passes, and is independently revertible**. Ground
truth is [IEEE_D1.md](IEEE_D1.md) (IEEE P3109/D1, July 2026), addressed through
[IEEE_D1.json](IEEE_D1.json) and mapped by
[IEEE_D1_concepts.md](IEEE_D1_concepts.md). No code changed; no tests run.*

> **Current role (2026-08-01): architecture map for the implementation that now
> ships.** `formats.jl` owns the abstract-format/representation lattice and the
> K = 8 storage split; `carriers.jl` owns rung selection and the distinction
> between internal `datumcarrier` and public `promotecarrier`;
> `decode_encode.jl` dispatches between table and computed decoding;
> `tables.jl`/`kernels.jl` enforce the table-cost policy; and `dyadic.jl` supplies
> the allocation-free exact rung. The staged verbs below are retained because
> they expose the dependency structure, but the stages are complete, not future
> work. [implementextensions.md](implementextensions.md) §11 is the execution
> record and the source files are the final authority.
>
> The `Dyadic` sketch in §5 uses the shipped tag vocabulary and `(S, Q, kind)`
> field order. It remains explanatory; [`src/dyadic.jl`](../../src/dyadic.jl) is
> the API and invariant source of truth.

---

## 0. How to read this, and what it decides

[extendingK.md](extendingK.md) answers *what* and *why*. This document answers
*how*, at the level of "a competent Julia implementer can execute it without
inventing anything." Where the two disagree, this one wins — it was written
after a second source audit, and §8 records exactly what that audit changed.

Three things are **decided** here and must not be relitigated during
implementation, because each has a downstream design that assumes it:

- **D1 — the representation lattice** (§1.1): `Binary{K,P,SGN,EXT}` becomes an
  abstract *format*; `Code8`/`Code16` are concrete *representations*.
- **D2 — the carrier lattice** (§1.2): the evaluation carrier is selected by
  **dispatch on a singleton head tag**, never by a branch that returns a type.
- **D3 — trait methods are generated, not computed** (§1.3): per-format traits
  are emitted as constant methods by the same loop that emits the format
  aliases, so they resolve in the method table with zero inference risk.

Two things this audit **reversed** from the earlier plan, with reasons in §8:

- **Group C is not a curiosity — it is the block-scale tier.** Annex F pairs
  `k8p1uf` with OCP's **E8M0**, the scale format of MX-style block arithmetic
  ([Annex F](IEEE_D1.md#L2791)). `Binary16p1uf` is its 16-bit analog, so
  Group C sits on the **block hot path**, not off in the weeds. `Dyadic` is
  therefore the *primary* Group C carrier, not an optional M5 optimization.
- **`Float128` is a fallback for Group C, not its foundation**, and the
  P = 1 special case makes the fast path trivial (§4.3).

---

## 1. Architecture

### 1.1 D1 — the representation lattice

```julia
# formats.jl, replacing the concrete struct
"""
    Binary{K,P,SGN,EXT} <: AbstractFloat

A P3109 *format*: bitwidth `K ∈ 3:16`, precision `P`, signedness `SGN`, domain
`EXT`. Abstract — the format is the semantics (D1 §3.1: "a datum set and an
encoding"); the concrete subtypes below differ only in the width of the machine
word that carries a code point, which is a representation choice below the
standard's level of description.
"""
abstract type Binary{K,P,SGN,EXT} <: AbstractFloat end

struct Code8{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}
    x::UInt8
    @inline function Code8{K,P,SGN,EXT}(::Val{:code}, x::UInt8) where {K,P,SGN,EXT}
        @boundscheck (checkformat(K, P, SGN, EXT);
                      K <= 8 || throw(ArgumentError("Code8 requires K ≤ 8, got K=$K"));
                      x & codemask(Code8{K,P,SGN,EXT}) == x ||
                          throw(ArgumentError("code point $x out of range for K=$K")))
        new{K,P,SGN,EXT}(x)
    end
end

struct Code16{K,P,SGN,EXT} <: Binary{K,P,SGN,EXT}
    x::UInt16
    @inline function Code16{K,P,SGN,EXT}(::Val{:code}, x::UInt16) where {K,P,SGN,EXT}
        @boundscheck (checkformat(K, P, SGN, EXT);
                      9 <= K <= 16 || throw(ArgumentError("Code16 requires 9 ≤ K ≤ 16, got K=$K"));
                      x & codemask(Code16{K,P,SGN,EXT}) == x ||
                          throw(ArgumentError("code point $x out of range for K=$K")))
        new{K,P,SGN,EXT}(x)
    end
end
```

The range test is a **mask test, not a comparison against `2^K`**, and
`codemask` is a generated per-format constant (D3) built by the complement
construction of technique **T11**:

```julia
_codemask(U, K) = typemax(U) >> (8 * sizeof(U) - K)   # total for 1 ≤ K ≤ 8*sizeof(U)
```

Two reasons, and the first is the one that matters:

- **`2^K` computed in the storage type is 0 exactly when K equals that type's
  width** — Julia defines an oversized shift as zero, so `UInt8(1) << 8` and
  `UInt16(1) << 16` are both `0`. The format grid *always contains* a format
  whose K equals its storage width (K = 8 on `UInt8` today, K = 16 on `UInt16`
  after this change), so this is structural, not incidental to widening. The
  complement construction shifts by `width − K ∈ [0, width−1]`, in which the
  pathological amount is unreachable **by construction**, at every K, for every
  unit — including a future `Code32`/`Code64`.
- The mask test states invariant 3 (*the high bits of the payload word are
  maintained zero*) directly, rather than a numeric range that merely implies
  it.

See §7 A2 for what this means for the existing code — which is safe, but safe
for a reason worth making explicit rather than continuing to rely on.

Why this shape (the alternatives are re-argued in §6): it maps exactly onto the
draft's own format/encoding split; every existing signature
(`f(x::Binary)`, `where {K,P,S,E,T<:Binary{K,P,S,E}}`, `::Type{<:Binary}`)
keeps both its text and its parameter destructuring; and there is exactly one
set of registry-generated methods (invariant 7).

**This applies uniformly to all 504 formats — there is no K-dependent
exception.** Abstractness is a property of the type constructor `Binary`, not
of any parameter value, so `Binary{6,2,false,false}` is abstract for exactly
the same reason `Binary{12,7,true,true}` is, and each has exactly **one**
concrete subtype: `Code8{6,2,false,false}` (the alias `Binary6p2uf`) and
`Code16{12,7,true,true}` (the alias `Binary12p7se`). The rule is one sentence
with no carve-outs — *the parameterized name is the format; the alias is the
representation* — and that uniformity is worth more than it may appear: a
K-dependent rule ("K ≤ 8 stays concrete, K ≥ 9 becomes abstract") would put a
seam through the middle of the grid, in the one place where the draft has none.

**Julia will not exploit "exactly one subtype", and the design must not assume
it will.** There are no sealed or final types: inference cannot narrow an
abstract element type to its unique subtype, and nothing prevents a third party
from declaring another `<: Binary{K,P,S,E}`. `reptype`, the `similar`
normalization, and `format(K,P,Σ,Δ)` therefore carry real weight rather than
being belt-and-braces. Document that subtyping `Binary` is **not** a supported
extension point: package methods assume `codepoint`/`rawvalue` semantics and
the representation invariant, neither of which an outside subtype can be held
to.

**The one breaking consequence and its mitigation.** `Binary{8,4,true,true}`
stops being concrete, so `similar(A, Binary{8,4,true,true})` and
`Vector{Binary{8,4,true,true}}` fail. The aliases (`Binary8p4se`) are concrete
and unaffected, which covers the documented usage. Recover the rest with a
normalizing overload and a public constructor:

```julia
# formats.jl — normalize an abstract format request at the array boundary
Base.similar(A::AbstractArray, ::Type{Binary{K,P,S,E}}, dims::Base.Dims) where {K,P,S,E} =
    similar(A, reptype(Binary{K,P,S,E}), dims)

"""`format(K, P, Σ, Δ)` — the concrete representation type for a format, for
programmatic construction. `format(12, 7, true, true) === Binary12p7se`."""
@inline format(K::Int, P::Int, S::Bool, E::Bool) = ... # see §2 T2
```

`Vector{Binary{...}}(undef, n)` cannot be intercepted and will produce an
abstract-eltype array; document it, and make `format` the advertised route.

### 1.2 D2 — the carrier lattice

```julia
# carriers.jl (new layer; see §3)
"""Evaluation-carrier selector. A singleton tag, so carrier choice is a method
lookup, not a value the compiler must fold."""
abstract type Head end
struct HeadF64   <: Head end     # rung 1: Float64 arithmetic, existing ladder
struct HeadF128  <: Head end     # rung 2: Float128 arithmetic, MPFR escalation
struct HeadExact <: Head end     # rung 3: Dyadic arithmetic, MPFR transcendentals

@inline carriertype(::HeadF64)   = Float64
@inline carriertype(::HeadF128)  = Float128
@inline carriertype(::HeadExact) = Dyadic     # BigFloat during Stage 6; see §5
# type-argument forms, for use where only the tag TYPE is in hand (apply_op)
@inline carriertype(::Type{H}) where {H<:Head} = carriertype(H())
```

Both an instance form and a `::Type{H}` form are needed: the tag flows as a
*value* through `ωeval` dispatch but as a *type parameter* through `apply_op`'s
result split (§2 T3). Defining only one of them is the first thing an
implementer will get wrong.

Rung boundaries, from [extendingK.md §3.2](extendingK.md), restated as the two
inequalities an implementer checks:

```
ΣB ≤ 1024                      and  Σ(Bᵢ + Pᵢ) ≤ 1074 + 2n   ⇒  HeadF64()
ΣB ≤ 16384                     and  Σ(Bᵢ + Pᵢ) ≤ 16494 + 2n  ⇒  HeadF128()
otherwise                                                      HeadExact()
```

where the sums run over the **datum factors of the operation's worst-case
monomial**: `n = 1` for unary and additive operations, `2` for
`Multiply`/`Divide`/`FMA`/`Hypot`, and `+1` per block scale factor
participating in a product (so a `ScaledMultiply` is `n = 4`). `n` comes from a
new `OpInfo` column (§5, Stage 5) — never from a hand-maintained table, because
`Block*`/`Scaled*` variants are generated and their factor counts must be
generated with them.

**Why dispatch and not a branch.** The obvious spelling —
`headtype(f) = ΣB ≤ 1024 ? Float64 : Float128` — returns a `Type`, so its
inferred return type is a small `Union` unless the compiler folds the
comparison. It usually will; "usually" is not a basis for a correctness-critical
selection that also gates a zero-allocation guarantee. A singleton tag consumed
by dispatch (`ωeval(::HeadF64, ::Val{op}, xs...)`) has no return type to infer:
the method is selected at compile time or the call is dynamic and visibly so.
Mandated as technique **T3** (§2).

### 1.3 D3 — traits are generated, not computed

Every per-format trait — `reptype`, `codeunit_type`, `datumtype`, `rung`,
`expbias` — is a pure function of `(K, P, SGN, EXT)`. Emit them as **constant
methods from the alias-generating loop**, which is already the single spelling
of the grid ([`formats.jl:130-144`](../../src/formats.jl#L130-L144)):

```julia
const _NAMED = Dict{Symbol,DataType}()
for K in 3:16, P in 1:K, S in (true, false), E in (true, false)
    S && P >= K && continue
    R = K <= 8 ? :Code8 : :Code16
    T = @eval $R{$K,$P,$S,$E}
    name = _formatname(K, P, S, E)
    @eval begin
        const $name = $T
        @inline reptype(::Type{Binary{$K,$P,$S,$E}}) = $T          # abstract → concrete
        @inline reptype(::Type{$T}) = $T                            # concrete → itself
        @inline codeunit_type(::Type{$T}) = $(K <= 8 ? UInt8 : UInt16)
        @inline datumtype(::Type{$T}) = $(_datumtype(K, P, S))
        @inline rung(::Type{$T}) = $(_rungtag(K, P, S))()
    end
    _NAMED[name] = T
end
```

504 one-line methods per trait. Each is a literal; each resolves in the method
table; none can be mis-inferred. This is the same mechanism invariant 7 already
mandates for operations, applied to formats — and it makes the trait table and
the alias table impossible to desynchronize, because one loop emits both.

**Cost and its bound.** 504 × 5 = 2520 tiny methods. Method-table lookup is
O(1); precompile time grows by the cost of 2520 trivial method definitions
(milliseconds). Compare with the alternative — `@generated` functions, which
cost a code-generation invocation per new specialization and cannot be
redefined interactively. Generated-at-alias-time wins on both.

### 1.4 New architectural invariants

Add to CLAUDE.md alongside the existing seven:

> **8. Format types are propagated, never rebuilt.** A method that received a
> format type or a value uses *that* type; it never re-forms
> `Binary{K,P,S,E}` from destructured parameters. Rebuilding yields the
> abstract format, which is not a valid array element type and not a valid
> constructor target. `Binary{K` appearing in a method **body** (as opposed to
> a signature) is a defect; grep enforces it.
>
> **9. The evaluation carrier is chosen by dispatch on a `Head` tag.** No code
> path may compute a carrier type into a variable and branch on it. Adding a
> format or an operation changes which method is selected, never which branch
> is taken.
>
> **10. Nothing is `@generated` over data whose size grows with `2^K`.**
> Constant-tuple tables are permitted only where the tuple length is bounded by
> 256 (i.e. K ≤ 8, selected by `Val`-dispatch, technique T4).

---

## 2. Mandated Julia techniques

Each is a rule, a rationale, and the anti-pattern it exists to forbid. These are
review criteria, not suggestions.

**T1 — Propagate format types; never rebuild them.**
*Anti-pattern:* `_decode_table(Binary{K,P,SGN,EXT})` inside a method whose
argument is `v::Binary{K,P,SGN,EXT}`.
*Correct:* `_decode_table(typeof(v))`. Where only parameters are in hand and a
type is genuinely needed, call `reptype(Binary{K,P,S,E})`, which is a generated
constant method (D3), not a computation.

**T2 — Type-valued traits are exact-type method tables.**
*Anti-pattern:* `codeunit_type(::Type{<:Binary{K}}) where {K} = K ≤ 8 ? UInt8 : UInt16`.
*Correct:* one method per format, generated (D3). For the non-format case
(`format(K,P,S,E)` taking runtime `Int`s) return through a `Dict` lookup into
`_NAMED` — that path is not performance-sensitive and must not pretend to be:

```julia
@inline function format(K::Int, P::Int, S::Bool, E::Bool)
    T = get(_NAMED, _formatname(K, P, S, E), nothing)
    T === nothing && (checkformat(K, P, S, E); error("unreachable"))
    T
end
```

**T3 — Carrier selection is dispatch on a singleton, never a returned type.**
*Anti-pattern:* `C = headtype(op, F1, F2); res = ωeval(op, C(x), C(y))`.
*Correct:* `res = ωeval(rung(op, F1, F2), Val(op), x, y)`, with one `ωeval`
method per `Head`. The Float64/escalation split in `apply_op`
([`ops_scalar.jl:130-139`](../../src/ops_scalar.jl#L130-L139)) — measured worth
399 → 269 ns/elem — is preserved by making it per-head:
`res isa carriertype(H) && return project(fr, ρ, res; R)`, where `H` is a type
parameter so `carriertype(H)` folds to a literal type in each specialization.

**T4 — Branch on K only through a `Val` barrier, and only where a method table
would be excessive.**
*Anti-pattern:* `if bitwidth(F) <= 8 ... else ... end` inside a hot function.
*Correct:*

```julia
@inline decode(v::F) where {F<:Binary} = _decode(F, codepoint(v), Val(bitwidth(F) <= 8))
@inline _decode(::Type{F}, c, ::Val{true})  where {F} = @inbounds _decode_table(F)[Int(c) + 1]
@inline _decode(::Type{F}, c, ::Val{false}) where {F} = _decode_compute(F, c)
```

`bitwidth(F)` is a type parameter, so `Val(...)` is a compile-time constant and
the branch disappears. This is the *only* sanctioned K-branch idiom.

**T5 — Table storage is `Memory{U}` with `U = codeunit_type(fr)`; getters stay
`@noinline` and are called once per array call.** Unchanged doctrine, widened
element type. The gather loop indexes a **local** `Memory`, never a global or a
`Dict`.

**T6 — Every public entry that accepts a format type as a value crosses a
function barrier `f(::Type{T}, args...) where {T}`.** Already package doctrine;
it becomes load-bearing for 504 formats because the dynamic-dispatch penalty
(~1 µs) is now spread across a grid four times larger.

**T7 — No `@generated` over `2^K` data** (invariant 10). The existing
`_decode_table`/`_decode_table32` stay, gated by T4's `Val(K ≤ 8)`.

**T8 — Allocation discipline is stated per head, not globally.**
`HeadF64` and `HeadF128` are zero-allocation on warm paths (both carriers are
bitstypes). `HeadExact` with `Dyadic` is also zero-allocation; only its MPFR
transcendental fallback allocates. The benchmark preflight's abort condition
becomes per-head, so a Group C `Log` allocating is a recorded property, not a
suite failure.

**T9 — Every coverage budget is a `Ref`, never a literal.**
`max_exhaustive`, the table byte budgets, the T3/T4 test-tier thresholds — all
settable, all reported in suite output. A budget spelled as a literal in a test
becomes invisible the moment the grid outgrows it.

**T10 — Cold, per-format code that is compiled once per signature is left to
specialize; do not reach for `@nospecialize`.** Table builders, conformance
reporting, and κ measurement are called once per signature. Compile latency is
a real risk at 504 formats (§9 R4) but the mitigation is the precompile
workload's *contents*, not de-specialization of paths whose whole value is
specialization.

**T11 — Width-sensitive constants are built by complement, generated once, and
never computed at a use site.**

*The hazard, stated precisely:* Julia defines a shift at or beyond a type's
width as zero — `UInt8(1) << 8 === 0x00`, `UInt16(1) << 16 === 0x0000`,
`1 << 64 === 0` in `Int`. So `2^K` computed in a type of width `K` is `0`. The
format grid **always contains a format whose K equals its storage width**
(K = 8 on `UInt8`, K = 16 on `UInt16`), so this case is structural, not an edge.

*Why the existing code is safe, and why that is not enough:* every current site
shifts in `Int` and narrows once — `Int(x) < (1 << K)`
([`formats.jl:22`](../../src/formats.jl#L22)), `UInt8((1 << K) - 1)`,
`UInt64((1 << K) - 1)`. Correct today and correct through K = 16. But the
safety is *width-relative*, not absolute: the same idiom fails at K = 64. It is
an accident that holds, and an accident that holds is exactly what a
504-format grid will eventually walk into.

*The rule:*

```julia
_codemask(U, K) = typemax(U) >> (8 * sizeof(U) - K)     # total, 1 ≤ K ≤ 8*sizeof(U)
```

Shift *down* from `typemax`, never up from `one`. The shift amount is
`width − K ∈ [0, width−1]`, so the pathological amount is unreachable by
construction at every K, for every unit, forever. Then emit `codemask`,
`nan_code`, `posinf_code`, `neginf_code`, `signmask`, and the extremal codes as
**generated per-format constants** (D3): the arithmetic runs once, at
precompile, and no width-sensitive expression survives to a use site at all.

*Anti-patterns, in ascending order of subtlety:* `UInt16(1) << K` (wrong at
K = 16); `(one(U) << (K-1)) << 1` (right, but a workaround for a self-inflicted
problem — it advertises that someone thought about the hazard rather than
removing it); `Int(x) < (1 << K)` (right today, silently width-relative).

**T12 — Golden capture is a digest, not a dump.** Capture the current release's
exhaustive-harness outputs as a per-testset SHA-256 of the concatenated result
code points, ~50 lines of text, diffable and reviewable. A megabyte of
serialized values is a golden nobody reads.

---

## 3. Module architecture after the change

Include order becomes **sixteen** layers plus the two vendored modules. The
comment in [`SmallFloats.jl:48-52`](../../src/SmallFloats.jl#L48-L52) must be
updated in the same commit that changes the order (CLAUDE.md rule).

```
dyadic → formats → carriers → projspec → defaults → decode_encode → project
       → ops_scalar → juliacompat → oracle → tables → kernels → blocks
       → packed → approx → rand
```

| layer | status | role |
|---|---|---|
| `dyadic.jl` | **new, first** | `Dyadic` exact dyadic number: `(S::Int128, Q::Int64)`. Self-contained, zero SmallFloats dependencies — placed with the vendored numeric modules for the same reason they are. |
| `formats.jl` | **rewritten head** | abstract `Binary` + `Code8`/`Code16` + generated per-format traits (D1, D3) |
| `carriers.jl` | **new** | `Head` tags, `carriertype`, the format-level rung lattice, `bigprec` |
| `projspec.jl` … `defaults.jl` | unchanged | `_DEFAULT_TYPE::Ref{Type{<:Binary}}` still works — `Binary` abstract is what that `Ref` already expected |
| `decode_encode.jl` | widened | T4-gated decode, carrier-typed `_decode_compute`, widened `encode`/order keys/sort gate |
| `project.jl` | +1 method | `round_to_precision(::…, X::Dyadic, …)`; everything else unchanged |
| `ops_scalar.jl` | + head dispatch | `factors` registry column; `rung(op, Fs...)`; per-head `apply_op` split |
| `oracle.jl` | + per-head rows | `ωeval(::HeadF128, …)`, `ωeval(::HeadExact, …)`; `_DE_*` and `bigprec` parameterized |
| `tables.jl` | unified policy | one arity-agnostic `_table_for`; `Memory{U}` |
| `kernels.jl` … `rand.jl` | widened | as [extendingK.md §5.6–§5.10](extendingK.md) |

Two files' *purpose* changes, and this should be said in their headers:
`carriers.jl` is where a reader learns which carrier a format uses and why;
`dyadic.jl` is where a reader learns that exactness at extreme exponent ranges
is an integer property, not a floating-point one.

---

## 4. The three carriers, implemented

### 4.1 `HeadF64` — unchanged

No new code. The work is *removal of hidden K ≤ 8 assumptions* (§7), not
addition. Every `ωeval` row, every `_DE_*` threshold, every `EncloseF` stage
keeps its shape; the thresholds become functions of `P` with a fixed point at
today's constants (gate **G1**, [extendingK.md §8.5](extendingK.md)).

### 4.2 `HeadF128` — one rung up an existing ladder

```julia
# oracle.jl — the Class-1 arithmetic rows, per head
@inline function ωeval(::HeadF128, ::Val{:Add}, x::Float128, y::Float128)
    s, e = _twosum128(x, y)                 # already exists (oracle.jl:53)
    iszero(e) && return s                   # exact in 113 bits
    _bigsum2(Float128, x, y)                # MPFR, precision from bigprec
end
```

`_twosum128`, `Enclose128F`, the `fq` prefilter, and
`round_to_precision(::Float128)` all exist today as escalation machinery.
Group B is that machinery promoted to entry point. The `ENV["SmallFloats_Float128"]
= "disable"` configuration must produce bit-identical results — today a
confirmatory CI job, after this change **the only verification** that Group B's
default path agrees with the rigorous one. Re-label it in CI.

### 4.3 `HeadExact` — `Dyadic`, and why it is the block-scale carrier

**The audit finding that reorders this work.** Annex F pairs the P3109
subformat `k8p1uf` with OCP's **E8M0** ([Annex F](IEEE_D1.md#L2791)) — the
8-bit unsigned, finite, single-significand-bit *scale* format of MX-style block
arithmetic. `Binary16p1uf` is its 16-bit analog. Since
`blockdecode` forms `ωMultiply(decode(s), decode(xᵢ))`
([`blocks.jl:45-48`](../../src/blocks.jl#L45)), **any block whose scale format
is a wide P = 1 unsigned format lands in Group C on every lane**. Group C is
therefore on the block hot path, and a `BigFloat`-based Group C would allocate
once per lane per block operation. `Dyadic` is not an optimization here; it is
the design.

```julia
# dyadic.jl
"""
    Dyadic(S::Int128, Q::Int64, kind)

A closed-extended-real carrier: the exact real `S · 2^Q` when `kind == DY_FINITE`,
otherwise NaN / ±∞. Represents every datum of every P3109 format at every
bitwidth exactly, with no exponent limit and no allocation: a datum's `S` holds
at most `P ≤ 16` significant bits (at most 32 after one multiplication), and
`Q` spans `|Q| ≤ B + P ≤ 32784`, well inside `Int64`.

The `kind` tag is **not optional**: `ωeval` rows return ±∞ and NaN for the
draft's special-value patterns, so the carrier must carry the same three
classes `Float64` and `Float128` carry natively. Mirrors `Rounded`'s tag
(`project.jl`) rather than inventing a second convention.
"""
const DY_FINITE = 0x00; const DY_POSINF = 0x01
const DY_NEGINF = 0x02; const DY_NAN    = 0x03

struct Dyadic <: Real
    S::Int128
    Q::Int64
    kind::UInt8        # tag LAST: leading, it costs 15 bytes of padding
end
Dyadic(S::Integer, Q::Integer) = Dyadic(Int128(S), Int64(Q), DY_FINITE)

@inline Base.isnan(d::Dyadic)    = d.kind == DY_NAN
@inline Base.isinf(d::Dyadic)    = d.kind == DY_POSINF || d.kind == DY_NEGINF
@inline Base.isfinite(d::Dyadic) = d.kind == DY_FINITE
@inline Base.iszero(d::Dyadic)   = d.kind == DY_FINITE && iszero(d.S)
@inline Base.signbit(d::Dyadic)  = d.kind == DY_NEGINF || (d.kind == DY_FINITE && d.S < 0)
@inline Base.ldexp(d::Dyadic, n::Integer) =
    d.kind == DY_FINITE ? Dyadic(d.S, d.Q + n, DY_FINITE) : d      # exact, free
@inline function Base.:*(a::Dyadic, b::Dyadic)                     # exact, closed
    (a.kind == DY_FINITE && b.kind == DY_FINITE) || return _mul_special(a, b)
    Dyadic(a.S * b.S, a.Q + b.Q, DY_FINITE)
end
```

> **Vocabulary note.** This block was written with the tags spelled
> `D_FIN`/`D_NAN`/`D_PINF`/`D_NINF` and the `kind` field first. Both changed
> before Stage 7 shipped, and the *numbering* changed with the names — NaN moved
> from `0x01` to `0x03` — so a sketch left in the original spelling would not
> merely fail to compile, it would silently classify wrongly against the shipped
> constants. It is restated above in the shipped vocabulary
> ([`src/dyadic.jl`](../../src/dyadic.jl)); the argument this section makes is
> unchanged, and `Base.:*` as shipped is `mul_dy`, a partial engine kernel, with
> total `Base.:*` routed through `BigFloat`.

**Multiply's precondition, stated because `Int128` is not infinite.** `*` is
exact only while both operands' significands are datum-sized or
datum-product-sized (≤ 32 bits each). It is never applied to an *accumulated
sum*, whose significand can reach 127 bits — the ω-semantics never multiply a
sum, so the precondition holds by construction, but it must be written at the
method or a future `Block` composition will violate it silently. Assert it in
the debug build (`@boundscheck nbits(a.S) + nbits(b.S) <= 96`).

**Add: the exact band and the sticky band must overlap, and they do.** Aligning
two terms with exponent gap `ΔQ` is exact in `Int128` while
`nbits(S_head) + ΔQ ≤ 127`; with a head significand of at most 32 bits that is
**ΔQ ≤ 95**. The sticky shortcut — treat the smaller term as pure sign
information — is sound once the term lies strictly below the finest stochastic
sub-grid unit, i.e. **ΔQ > P + N + 2**, at most `16 + 60 + 2 = 78`. The bands
therefore overlap on `ΔQ ∈ [79, 95]`, so every gap is covered by at least one
of them with margin. *This overlap is the correctness argument for the `Dyadic`
add; it must appear as a comment at the method and as an assertion in the
suite, because it is the one place where widening `P` or raising the stochastic
bit cap `N` could silently open a gap.* (At `N = 60`, `P` may grow to 45 before
the bands separate — ample, but no longer unbounded.)

Three properties that make it the right carrier rather than merely a working
one:

1. **Multiply is exactly closed with no widening.** `|S| < 2^16` per datum, so
   a product's `|S| < 2^32` — `Int128` is not even stressed, and a three-factor
   `FMA` product stays under 2^48.
2. **The P = 1 scale case degenerates to an integer add.** A P = 1 datum is
   `±2^e`, i.e. `Dyadic(±1, e)`. Block decode becomes
   `Dyadic(S_elem, Q_elem + e_scale)` — a *shift of the exponent field*, no
   arithmetic at all, and no overflow question. In `Float64` or `Float128` the
   same operation is an `ldexp` that can overflow the carrier; in `Dyadic` it
   cannot. The hardest case in the grid is the cheapest one.
3. **Add reuses `StickyF`'s existing soundness argument, with `ΔQ` replacing
   binade spread.** Align the smaller term when `|ΔQ| ≤ 100` (exact in
   `Int128`); when `|ΔQ| > P + N + 2` — `N ≤ 60` stochastic bits — the smaller
   term lies strictly below the finest sub-grid unit and contributes only its
   sign, which is exactly `StickyF`'s contract
   ([`ops_scalar.jl:30-43`](../../src/ops_scalar.jl#L30-L43)). The band between
   is covered by the `Int128` path. No new proof; an existing proof with a
   wider variable.

**`round_to_precision` on `Dyadic` is simpler than on any float** — this is the
strongest argument for the type and the clearest instruction for implementing
it:

```julia
function round_to_precision(P::Int, B::Int, μ::RoundingMode3109,
                            X::Dyadic, R::Int, sticky::Int)
    # Specials and zero are handled HERE, not by delegating to `_rtp_core`:
    # that function's zero row builds `zero(float(typeof(X)))`, and `float(Dyadic)`
    # does not exist. The rows are three lines; delegating is what would be subtle.
    X.kind == DY_NAN    && return Rounded(KIND_NAN, Int8(1), 0, 0)
    X.kind == DY_POSINF && return (sticky < 0 ? Rounded(KIND_FIN, Int8(1), (Int64(1) << P) - 1, HUGEQ)
                                              : Rounded(KIND_PINF, Int8(1), 0, 0))
    X.kind == DY_NEGINF && return (sticky > 0 ? Rounded(KIND_FIN, Int8(-1), (Int64(1) << P) - 1, HUGEQ)
                                              : Rounded(KIND_NINF, Int8(-1), 0, 0))
    if iszero(X.S)                                            # zero row, sticky-aware
        sticky == 0 && return Rounded(KIND_FIN, Int8(1), 0, 0)
        return _rtp_zero_sticky(P, B, μ, sticky, R)           # shared with _rtp_core
    end
    sign = Int8(X.S < 0 ? -1 : 1)
    S    = X.S < 0 ? -X.S : X.S
    n    = 128 - leading_zeros(reinterpret(UInt128, S))      # msb position + 1
    e    = X.Q + n - 1                                       # ⌊log₂|X|⌋, exact
    Q    = max(e, 1 - B) - P + 1
    sh   = Q - X.Q
    if sh <= 0
        Sfl  = Int64(S << (-sh)); νfix = UInt128(0); lost = false   # exactly representable
    else
        Sfl  = Int64(S >> sh)
        frac = S & ((Int128(1) << sh) - 1)                   # the fraction, exactly
        νfix = sh <= 128 ? (UInt128(frac) << (128 - sh)) : UInt128(0)
        lost = sh > 128 && frac != 0
    end
    # …identical tail to _rtp_f64 from here: the same `_rab` fixed-point predicate
    # family, the same sticky step-down, the same next-binade carry.
end
```

The shifted-out bits **are** ν as an exact fixed-point fraction — no `ldexp`, no
`floor`, no ν-exactness argument to discharge. The tail is shared with
`_rtp_f64`'s existing `_rab` predicate family, so `Dyadic` joins the *fixed-point*
twin rather than creating a third family (the twin-sync warning at
[`project.jl:62-66`](../../src/project.jl#L62-L66) stays a warning about two
families, not three).

Transcendentals under `HeadExact` route to the existing `EncloseF` MPFR ladder,
whose closures take a precision and return directed bounds — carrier-agnostic
already. Only `bigprec` needs the format-derived value (§5, Stage 6).

---

## 5. Implementation strategy: nine stages

Each stage compiles, passes the suite, and is revertible in one commit. The
ordering is chosen so that the **highest-risk change is isolated from the
highest-volume change** — see Stage 2/3.

| # | stage | net effect | gate |
|---|---|---|---|
| 0 | Golden capture | none | **G5** baseline recorded |
| 1 | Traits over today's grid | none | G5 green |
| 2 | Abstractify `Binary`, `Code8` only | none | **G5 green — the critical checkpoint** |
| 3 | Add `Code16`, open `checkformat` to 3:16 | 504 formats exist | lattice sweeps green |
| 4 | Widen decode/encode/keys/sort/packed | K ≤ 11 fully operational | **G3** |
| 5 | Unified table policy + kernels | wide array ops correct | table gates |
| 6 | Carriers: rung dispatch, `bigprec`, `_DE_*` | Groups B, C correct | **G2 (red first), G1, G4** |
| 7 | `Dyadic` | Group C allocation-free; block scale path | G4 re-run |
| 8 | Doctrine, docs, exports, deprecations | shippable | full CI matrix |

### Stage 0 — Golden capture (do this first, before any edit)

Run the existing suite against the current release, capture per-testset SHA-256
digests of concatenated result code points (technique T12), commit as
`test/golden/k8.sha256`. **Capture before the refactor, not after** — a golden
derived from the new code proves only self-consistency.

### Stage 1 — Traits over today's grid

Add `reptype`, `codeunit_type`, `datumtype`, `rung`, `Head`, `carriertype`,
`carriers.jl`, and the generated trait methods — all returning today's answers
for the existing 120 formats. `Binary` stays concrete. **Zero behavior change**;
this stage exists so that Stage 2's diff is *only* the type refactor.

### Stage 2 — Abstractify `Binary`, with `Code8` alone

The single highest-risk edit in the project: it touches every layer. Doing it
with **no new formats** means G5 is a complete oracle — any difference is a
refactor bug, not a wide-K bug. Concretely: `abstract type Binary`, add
`Code8`, retarget the alias loop, apply technique T1 to every rebuild site,
route `codepoint`'s return type through `codeunit_type`, add the `similar`
normalization and `format(K,P,S,E)`.

**Plus one sweep that is easy to overlook and total in scope (O12):** every
signature written as the *exact* type `::Type{Binary{K,P,S,E}}` must become
`::Type{<:Binary{K,P,S,E}}`, or it will stop matching the concrete `Code8`
values that now flow through it. The Group M family
([`formats.jl:64-75`](../../src/formats.jl#L64-L75)), `formatname`,
`nan_code`/`posinf_code`/`neginf_code`/`signmask`, and the extremal queries are
all currently exact. Grep for `::Type{Binary{` — every hit is either this sweep
or a deliberate abstract-only method (`reptype`'s abstract case, D3), and the
deliberate ones are few enough to enumerate in the commit message.

**Do not proceed past this stage until G5 is byte-identical.** If Stage 2 is
green, the representation lattice is proven on 120 formats and 8.9 M assertions
before a single wide format exists.

### Stage 3 — `Code16` and the grid

Add `Code16`; open `checkformat` to `3 <= K <= 16`; extend the alias loop to
`3:16` (504 names + 2520 trait methods). Restated invariant 2 lands here
(§ [extendingK.md 5.13](extendingK.md)): `(::Type{T})(c::Unsigned)` replaces the
`UInt8` method, `show` padding becomes `2*sizeof(codeunit_type(T))`.

At the end of this stage the wide formats *exist* and their lattice operations
work; arithmetic on Group B/C formats is still wrong and must be explicitly
disabled. **Throw from the not-yet-implemented head methods, not from `rung`:**

```julia
ωeval(::HeadF128, ::Val{op}, xs...) where {op} =
    throw(ArgumentError("$op on this format needs the rung-2 carrier (Stage 6)"))
ωeval(::HeadExact, ::Val{op}, xs...) where {op} = throw(ArgumentError(...))
```

`rung` stays **total** — it is a generated per-format constant (D3) and a trait
that throws for a third of its domain is not a trait. The unimplemented rungs
are missing *methods*, which is what an incomplete implementation actually is,
and which the method table reports precisely. An explicit throw is mandatory
either way: a wide format silently computing on a Float64 head between Stages 3
and 6 is exactly the wrong-answer regime this whole plan exists to prevent.

### Stage 4 — Decode, encode, keys, sort, packed

T4-gated decode; carrier-typed `_decode_compute` via `ldexp`; `encode` returning
the storage unit; `UInt32` order keys for K ≥ 9; the counting-sort length gate;
`PackedVector` widening with a loud refusal at K = 16. Gate **G3** (`_rtp_f64`
bit ≡ generic over the widened `(P ≤ 16, B ≤ 512)` grid) runs here, because
this is the first stage where P > 8 formats reach the bit path.

### Stage 5 — Tables and kernels

Replace the split table policy with one arity-agnostic byte-budget
`_table_for`; make Shape A conditional at every arity; `Memory{U}`; parallel
table build (`Threads.@threads` over the pure index space, outside the lock);
`table_bytes` companion reporting declined signatures.

### Stage 6 — Carriers

`factors` registry column; `rung(op, Fs...)`; per-head `ωeval` and `apply_op`;
carrier-aware `promote_rule`; format-derived `bigprec`; `_DE_*` as functions of
P; Group C temporarily on `BigFloat` behind `HeadExact`.

**Write G2 first and watch it fail.** The `Binary16p1uf` maximal-spread witness
(`MaxFinite = 2^32766`, `MinPositive = 2^-32767`, spread 65533) against
`_BIGP = 2200`, with `Rational{BigInt}` from `test/refimpl.jl` as oracle. A
precision-truncation bug produces plausible results; a red test is the only
proof the fix was necessary.

### Stage 7 — `Dyadic`

`dyadic.jl`; the `round_to_precision(::Dyadic)` method; `HeadExact` arithmetic
rows; the P = 1 scale fast path in `blockdecode`. Re-run **G4** with the
block/scaled four-factor cases, which is where the factor-count rule is
load-bearing.

### Stage 8 — Doctrine, docs, exports

The restated test doctrine ([extendingK.md §8](extendingK.md)); `refimpl`
promoted into the shipped suite as the T2 oracle; `SmallFloats_EXHAUSTIVE`;
export policy (§6.7); the `f32_exact` and `DefaultAccumulatorType` dispositions
(§7); documentation of the `Binary16p*` ≠ `binary16` trap.

---

## 6. Options and avenues evaluated

Beyond those already rejected in [extendingK.md §7](extendingK.md).

### 6.1 Scaled-`Float64` carrier (per-format exponent offset) — **rejected, with proof**

The clever idea: keep `Float64` for Group B by representing a datum `X` as a
mantissa `m::Float64` with an implicit per-format shift σ, `X = m · 2^σ`, so a
format whose exponents sit outside Float64's range is re-centred into it.

It fails on **span**, not offset. A format's datums span from `2^(2−P−B)` to
just under `2^B`, i.e. `2B + P − 2` binades. `Float64`'s total exponent span is
~2098 binades (normals plus subnormals), so a scaled Float64 carries a format
exactly only when `2B + P − 2 ≤ 2098`, i.e. `B ≲ 1024` — *the same bound the
unscaled carrier already achieves*. Offsetting buys nothing because the
constraint is dynamic range, and a format with `B ≥ 2048` simply has more
dynamic range than `Float64` has.

It also breaks closure: multiplying two σ-scaled values produces a `2σ`-scaled
result, so σ becomes a value that must be tracked and renormalized — at which
point it is `Dyadic` with a worse representation. **Rejected**, and worth
recording because it is the first idea a reader will have.

### 6.2 Double-double / compensated carrier — **rejected in one line**

Extends *precision*, not exponent range. Group B and C are exponent-range
problems. Irrelevant.

### 6.3 `Dyadic` as the *universal* carrier (all rungs) — **deferred, not rejected**

The argument is real: it would make exactness a type-level property instead of
a per-format range analysis, collapse three rungs into one, and delete the
`_DE_*` threshold family entirely. Against it: `Float64` arithmetic on Group A
is measured (26 ns scalar `Add`) and `Int128` shifting is not; the transcendental
catalog needs MPFR regardless, so the unification is partial; and the change
would put every K ≤ 8 result at risk for a benefit that is architectural rather
than behavioral. **Decision: keep it as the stated long-run direction; the
`rung`/`carriertype` traits are the seam that makes it a later local change
rather than a rewrite.** Revisit only with a benchmark showing `Dyadic` within
1.5× of `Float64` on scalar `Add` at K ≤ 8.

### 6.4 Storage-agnostic representation via `NTuple{N,UInt8}` — **rejected**

Would admit K > 16 later without another representation. But it forfeits
`Base` integer operations on the code point, complicates the packed path, and
buys generality nobody has asked for. `Code8`/`Code16` cover K ≤ 16 and a
`Code32` is a copy-paste away if K ≤ 32 ever arrives.

### 6.5 K as a runtime value ("dynamic formats") — **rejected**

Formats as values rather than type parameters would collapse the specialization
space (a real compile-latency win, §9 R4) at the cost of every performance
property the package is built on. Contradicts the module's own headline
performance note. **However**, a *reflection* API that maps runtime
`(K,P,Σ,Δ)` to a concrete type (`format(...)`, T2) is needed and is provided —
that is the legitimate 5% of this idea.

### 6.6 Split into two packages (`SmallFloats` + a wide sibling) — **rejected**

Would keep the K ≤ 8 package untouched. But the registry, the oracle, the
projection engine, and the conformance machinery are shared; two packages means
two copies or a dependency with a hard-to-place seam — the exact divergence
invariant 7 exists to prevent. Rejected on the same grounds as the parallel-type
option.

### 6.7 Export surface — **decided: opt-in submodule**

504 exported names is a large namespace claim for a `using`. Decision: export
the 120 K ≤ 8 names as today (no breakage), define all 504 in the module, and
add

```julia
module Formats            # re-exports all 504 aliases
    using ..SmallFloats
    for n in sort!(collect(keys(SmallFloats._NAMED))); @eval export $n; end
end
```

so `using SmallFloats.Formats` is explicit. `format(K,P,Σ,Δ)` serves programmatic
use. This is reversible in the widening direction (exporting more later is not
breaking) and not in the narrowing direction — which settles it.

### 6.8 Cap K at 15 to eliminate Group C — **rejected**

Would remove the only formats needing an unbounded-exponent carrier. But
[Annex F](IEEE_D1.md#L2791) makes the P = 1 unsigned finite family the *scale*
format of block arithmetic (E8M0), so capping K at 15 would exclude the natural
16-bit block scale format — the single most likely wide format to be wanted in
practice. The cap would also be a conformance limitation the draft does not
have. **This is the finding that promoted `Dyadic` from M5 to Stage 7.**

---

## 7. Audit: latent defects and unconsumed surface found in this pass

Additions to [extendingK.md §2](extendingK.md)'s inventory, all found by direct
source inspection during this pass.

**A1 — `measure_kappa` hard-codes `UInt8` code construction.**
[`approx.jl:60`](../../src/approx.jl#L60) builds arguments with
`rawvalue(argformats[i], UInt8(codes[i]))`. At K ≥ 9 this truncates silently for
codes ≥ 256, so κ would be measured against the wrong inputs — a wrong κ, which
invariant 5 treats as a verified property. Must become
`codeunit_type(argformats[i])(codes[i])`. **Severity: high** — it corrupts a
correctness guarantee rather than a result.

**A2 — width-sensitive constants: no live defect, one latent policy gap.**
Technique T11. Audited sites, with verdicts:

| site | form | verdict |
|---|---|---|
| [`formats.jl:22`](../../src/formats.jl#L22) code-point range check | `Int(x) < (1 << K)` | **correct**, K ≤ 63 |
| [`formats.jl:86-112`](../../src/formats.jl#L86-L112) `nan_code`, `posinf_code`, `neginf_code`, `signmask`, `MaxFiniteOf`, `MinNormalOf` | `UInt8((1 << K) - 1)` etc. | **correct** — `Int` shift, narrowed once |
| [`decode_encode.jl:139`](../../src/decode_encode.jl#L139) counting sort | `nk = (1 << K) + 1` | **correct**, `Int` |
| [`packed.jl:68`](../../src/packed.jl#L68) `_codemask` | `UInt64((1 << K) - 1)` | **correct** to K ≤ 62 |
| [`tables.jl`](../../src/tables.jl), [`kernels.jl`](../../src/kernels.jl), [`approx.jl:27`](../../src/approx.jl#L27) index arithmetic | `1 << K`, `1 << (K1+K2)` | **correct**, `Int`; but see §9 R2 — a K = 16 ternary index is `1 << 48`, fine, while a *product* of such is not |

**So there is no live defect, and no site changes for correctness.** What
changes is the *reason* the sites are correct: today it is "the shift happens
to be in `Int`, and K ≤ 8 ≪ 63". That reason is width-relative and undocumented,
which is why it reads as a hazard when the grid doubles the number of
K == storage-width formats.

The action is therefore a **policy migration, not a bug fix**: move these
constants to the generated-per-format form (D3) built by T11's complement
construction, so the property becomes structural rather than incidental, and
`Code32`/`Code64` would inherit it for free. Schedule with Stage 1 (traits over
today's grid) — it is a zero-behavior-change edit that G5 verifies completely,
and doing it there means Stage 3 adds 384 formats to an already-safe
construction rather than to an accident.

**A3 — `f32_exact` has no consumer in `src/`.** Confirmed by grep: defined at
[`tables.jl:236`](../../src/tables.jl#L236), exported, never called internally.
The SIMD stochastic loop it was designed to gate
([Float32more.md §3.4](Float32more.md)) was not built. Disposition required
before the grid multiplies its cost (each answer is up to `2^(K1+K2)` BigFloat
comparisons): restrict its domain to K ≤ 11 by construction, build the
consumer, or deprecate. Recommended: restrict — its premise (`Float32`
datum-exactness) fails once `B > 128` anyway, so it can only return `true` in
the high-P corner of the wide grid.

**A4 — `DefaultAccumulatorType` has no consumer in `src/`.** Same pattern:
a settable default (`_GUARD_ACCUM = binary32`,
[`defaults.jl:56`](../../src/defaults.jl#L56)) with a full setter/getter/
combinator surface, while `blocks.jl` uses its own exact wide-precision
accumulator. Either wire it into the reduction accumulator's precision choice
(where wide K makes it genuinely useful — see
[extendingK.md §5.7](extendingK.md)) or document it as advisory. Do not carry an
unconsumed knob into a 504-format grid.

**A5 — the working-tree addition to `juliacompat.jl` is already wide-K safe.**
The new `Op(ρ, x::Binary)` / `Op(ρ, A::AbstractArray{T})` unary forms dispatch
on `Binary`, so they extend to every new format automatically once `Binary` is
abstract. No action; recorded so it is not re-examined.

---

## 8. Review: what this pass changed in the plan

| # | change | reason |
|---|---|---|
| 1 | **Group C promoted from M5 curiosity to Stage 7 necessity**; `Dyadic` is its primary carrier | Annex F: P = 1 unsigned finite formats are the *block scale* family (E8M0). Group C sits on the block hot path, where `BigFloat` would allocate per lane. |
| 2 | **Carrier selection became dispatch on a `Head` tag** (D2/T3), replacing a trait returning a type | A type-returning ternary infers a `Union` unless folded; "usually folds" cannot underwrite a zero-allocation guarantee or a correctness-critical selection |
| 3 | **Per-format traits are generated at alias-definition time** (D3), replacing computed traits and `@generated` | Method-table constants: no inference risk, no codegen cost, and the trait table cannot desynchronize from the alias table because one loop emits both |
| 4 | **Stage 2/3 split: abstractify with `Code8` alone before adding `Code16`** | Isolates the highest-risk edit (type refactor, every layer) from the highest-volume one (384 new formats), so G5 on 120 formats is a *complete* oracle for the refactor |
| 5 | **G2 must be written red before the `_BIGP` fix** | Precision truncation yields plausible results; a passing test after the fix proves nothing about whether the fix was needed |
| 6 | **`Dyadic` joins the fixed-point twin family, not a third family** | Its ν is already an exact fixed-point fraction; sharing `_rab` keeps the twin-sync obligation at two families |
| 7 | **New invariants 8–10** (propagate-don't-rebuild; carrier-by-dispatch; nothing `@generated` over `2^K`) | Each corresponds to a defect class the widening introduces that the existing seven do not cover |
| 8 | **Stage 3 must `throw` for non-`HeadF64` formats** until Stage 6 | A wide Group B format silently computing on a Float64 head is precisely the silent-wrong-answer regime the plan exists to prevent |
| 9 | **A1 added to the inventory** (`measure_kappa`'s `UInt8`) | Found by inspection; it corrupts κ, a declared conformance property |
| 10 | **Export decision settled** (opt-in `Formats` submodule) | Asymmetric reversibility: exporting more later is non-breaking, un-exporting is |
| 11 | **The shift-width item was re-diagnosed and downgraded from "defect the widening introduces" to "incidental correctness to be made structural"** (T11, A2, R2) | The audit found no live defect: every existing site shifts in `Int` and narrows once. The hazard is structural to *K equalling the storage width* — already true at K = 8 on `UInt8` — and today's safety is width-relative (`1 << 64` is `0` too), not absolute. The fix is the complement construction `typemax(U) >> (width − K)`, in which the pathological shift amount is unreachable by construction, migrated in Stage 1 where G5 verifies it at zero behavior change. An earlier draft of this document proposed `(one(U) << (K−1)) << 1`, which is correct but is a workaround for a self-inflicted problem rather than its removal. |

---

## 9. Risk register

| id | risk | likelihood | mitigation |
|---|---|---|---|
| R1 | Stage 2 type refactor regresses a K ≤ 8 result | med | G5 golden captured **before** the refactor (Stage 0); Stage 2 adds no formats, so any diff is the refactor |
| R2 | A hidden `UInt8` assumption survives into a wide path | med | The §7 A2 audit found **no live width-sensitive defect** — every existing shift runs in `Int` — so the residual risk is *new* code, not existing code. Mitigations: T11's complement construction migrated in Stage 1 (making the property structural, verified by G5 at zero behavior change); a Stage-3 test constructing every code point of every K = 16 format and asserting invariant 3; A1's `measure_kappa` fix, which is the one real hard-coded `UInt8` found |
| R3 | `_BIGP` truncation ships undetected | med | G2 written red first (Stage 6), `Rational{BigInt}` oracle |
| R4 | Compile latency explodes at 504 formats × 51 ops × 27 ρ | med | precompile workload stays K ≤ 8 + one Group A wide + one Group B format; measure first-use `@time` for a wide format as a tracked number; T10 forbids the tempting-but-wrong `@nospecialize` fix |
| R5 | `Union`-typed trait leaks into a hot path and allocates | med | D2/T3 make traits dispatch-shaped; the existing zero-allocation pins extend per head (T8) |
| R6 | Rung selection is subtly wrong for block/scaled monomials | med | G4's domain **must** include the four-factor `ScaledMultiply` case — that is the case the naive per-format rule gets wrong ([extendingK.md §5.7](extendingK.md)) |
| R7 | Table build stalls a first array call for seconds at K = 16 | low | parallel build (Stage 5) + cost-aware eager band + `table_bytes` reporting |
| R8 | Test wall clock outgrows `Pkg.test()` | med | T9 budgets as `Ref`s; `SmallFloats_EXHAUSTIVE` split; the measured 7.6 M-point lattice sweep is affordable, the composition tiers are what get budgeted |

---

## 10. Second-pass review: oversights found and closed

A re-read of this document against the source found fourteen gaps. Five were
substantive (would have produced wrong code); the rest are specification gaps
that would have produced *ambiguity*, which in a directive document is the same
failure. All are closed above; they are listed here so the closure is auditable
and so the same holes are not re-opened.

### Substantive

**O1 — `Dyadic` could not represent NaN or ±∞.** The first sketch was
`(S, Q)` only. But `ωeval`'s special-value rows return `Inf` and `NaN` — they
are the *specification*, written out explicitly
([`oracle.jl:20-22`](../../src/oracle.jl#L20-L22)) — so any carrier must carry
three classes, as `Float64` and `Float128` do natively. Closed: `Dyadic` gains
a `kind` tag mirroring `Rounded`'s (§4.3). Cost: 32 bytes, still isbits, still
allocation-free. Had this shipped, every `HeadExact` operation on an infinite
operand would have been a wrong answer or a `MethodError`.

**O2 — the `Dyadic` zero row delegated to `_rtp_core`, which cannot accept it.**
`_rtp_core`'s zero branch builds `zero(float(typeof(X)))`
([`project.jl:165`](../../src/project.jl#L165)) and `float(Dyadic)` does not
exist. Closed: specials and zero are handled in the `Dyadic` method directly,
with the sticky-zero row factored into a shared `_rtp_zero_sticky` so the two
carriers cannot drift (§4.3).

**O3 — the `Dyadic` add's two bands were asserted, never checked for overlap.**
The exact `Int128` alignment band is `ΔQ ≤ 95` (127 bits minus a ≤ 32-bit head
significand — the earlier text said "≤ 100", which is wrong), and the sticky
band is `ΔQ > P + N + 2 ≤ 78`. They overlap on `[79, 95]`, so coverage is
total — *with the margin now stated*, along with the fact that it is `P ≤ 45`
at `N = 60` that keeps them overlapping. An uncovered gap in the middle would
have been a silently wrong sum at a specific exponent separation: the hardest
possible bug to find by sampling.

**O4 — `Dyadic` multiply had no stated precondition.** `Int128` overflows if
an *accumulated sum* (up to 127 significand bits) is multiplied. The
ω-semantics never do this, so it holds by construction — but "by construction"
is a claim, and a future block composition could break it. Closed with the
precondition written at the method plus a `@boundscheck` assertion (§4.3).

**O5 — `carriertype` was defined only on instances**, while `apply_op`'s
Float64-fast-split needs it on the *type* (`H` arrives as a type parameter).
Closed by defining both forms and saying why (§1.2). The single most likely
first-day implementation error, and it would have shown up as an inference
failure that quietly costs the zero-allocation property rather than as an error.

### Specification gaps

**O6 — `show` would print two distinct types identically.** `_fully_instantiated`
tests `T isa DataType && length(T.parameters) == 4`
([`formats.jl:150-153`](../../src/formats.jl#L150-L153)); after D1 *both* the
abstract `Binary{12,7,true,true}` and the concrete `Code16{12,7,true,true}`
satisfy it, so both would print `Binary12p7se` — and the difference between
them is precisely what an error message about `similar` or `eltype` needs to
communicate. **Fix:** print the concrete representation as the draft name and
the abstract format distinguishably, e.g. `Binary12p7se` versus
`Binary12p7se{format}`; add a test asserting the two strings differ.

**O7 — `rawvalue` was not respecified.** It must accept an abstract format and
normalize: `@inline rawvalue(::Type{F}, x) where {F<:Binary} =
@inbounds reptype(F)(Val(:code), codeunit_type(F)(x))`, with `reptype` the
identity on concrete input (D3). Kernel call sites pass concrete types and pay
nothing.

**O8 — `promote_rule` needs an explicit carve-out from T3.** T3 forbids traits
that return types; `promote_rule` is *inherently* type-returning and is
resolved by the compiler at the type level, so the rule does not apply — but it
must still be emitted as a **generated per-format method** in the alias loop
(D3), not computed from `datumtype` at call time. Both facts belong in T3's
text.

**O9 — `carriertype(::HeadExact)` changes between Stage 6 and Stage 7**
(`BigFloat`, then `Dyadic`). Stated in §1.2 and §5 now; it is deliberate — the
tag is the seam that makes the swap a one-line change — but an unannounced
change of a trait's answer between stages is exactly the kind of thing that
looks like a merge error.

**O10 — `project_interval`'s `maxprec = 4096` was never examined, and it is
fine.** Recorded *because* it looks like a sibling of `_BIGP` and will attract a
"fix". The distinction: `_BIGP` needs **absolute** precision, sized by the
operand exponent *span* (up to 65533 bits at `Binary16p1uf`), which is why the
constant fails. `project_interval` resolves transcendental *enclosures*, where
MPFR precision is **relative** to the value's own magnitude and the exponent
range is irrelevant. 4096 bits of relative precision resolves a grid straddle
at any K. Leave it alone, and leave this paragraph next to it.

**O11 — Appendix B omitted three trees.** `docs/src/*.md` states the 3–8 range
in many places and feeds the LaTeX/PDF pipeline
([docs/pdf/howto.md](../pdf/howto.md)); `benchmarking/` has its own environment
and needs a per-rung report section (the preflight abort condition becomes
per-head, T8); `README.md` states the format count. All three are Stage 8. A
file-by-file index that omits the documentation of a 4×-larger format grid is
not an index.

**O12 — the release is breaking, the break is *documented public API*, and the
first draft understated it.** `Binary` becomes abstract, so
`Binary{8,4,true,true}` becomes a fully-parameterized **abstract** type: still a
`DataType` with four parameters, but `isconcretetype` is `false`, because layout
is precisely what the concrete subtype supplies (`x::UInt8` versus `x::UInt16`).
A struct's field type cannot depend on its own parameters without a further
parameter, so one name over two storage widths forces the split.

*What still works:* constructors — `Binary{8,4,true,true}(0x02)` is legal on an
abstract type and forwards to `Code8` — and every trait or `where` clause
spelled `::Type{<:Binary{K,P,S,E}}`, which matches abstract and concrete alike.
**Audit that all such signatures use `<:`**; `formatname`, `expbias`, and the
Group M family are currently written as exact `::Type{Binary{K,P,S,E}}`
([`formats.jl:64-75`](../../src/formats.jl#L64-L75)) and would stop matching
concrete values. This is a mechanical but *total* sweep of `formats.jl`.

*What breaks:* array element type (`Vector{Binary{8,4,true,true}}` gets a
non-isbits eltype and boxes) — and, the item the first draft missed:

> **`Binary8p4se === Binary{8,4,true,true}` becomes `false`.**

That identity is **taught in the tutorial and pinned by the suite**:
[`cheat_sheet.md:58`](../src/cheat_sheet.md), [`introduction.md:72`](../src/introduction.md),
[`user_guide.md:14`](../src/user_guide.md), and
[`runtests.jl:117`](../../test/runtests.jl#L117). The replacement is `<:`.

*This does not reopen the D1 decision, and here is why:* **no option supporting
two storage widths preserves the identity.** Under the five-parameter option
(§6, T1) `Binary{8,4,true,true}` is a `UnionAll` — likewise neither `===` to a
concrete type nor concrete itself. Under the parallel-type option (T2) the name
does not span both widths at all. The identity is incompatible with two
representations, so it is a cost of *the extension*, not of D1.

*The replacement framing is better teaching, not merely adequate:*
`Binary{8,4,true,true}` **is the format**; `Binary8p4se` **is its
representation** — which is exactly D1 §3.1's own split, "a datum set and an
encoding" ([§3.1](IEEE_D1.md#L270)). Rewrite the three doc sites to say that
rather than to patch `===` into `<:`.

*Also in the same sweep:* [`runtests.jl:118`](../../test/runtests.jl#L118)
asserts `Binary{9,4,true,true}` throws — K = 9 becomes **valid** at Stage 3, so
that assertion must move to a genuinely invalid bitwidth (K = 17) while keeping
its sibling (`P ≥ K`) intact. A test that asserts the old limit will fail
loudly, which is correct; a test that asserts it *indirectly* would not.

Under semver this is a major bump (or a minor bump pre-1.0). The `similar`
normalization and `format(K, P, Σ, Δ)` (§1.1) are the documented migration.

**O13 — no new dependencies, and that is worth asserting.** `Quadmath` and
`BFloat16s` are already present; `Dyadic` is hand-written `Int128` arithmetic;
MPFR is `Base`. The extension adds **zero** entries to `Project.toml`. A
plan that quadruples the format grid without touching the dependency surface
should say so, because the opposite would be a significant cost.

**O14 — JET load will change and no budget was set.** The abstract-type
boundary (`Ref{Type{<:Binary}}` in defaults, containers built from an abstract
format request) is exactly the shape that produced the existing `_vmap_packed`
filter ([`packed.jl:93-98`](../../src/packed.jl#L93-L98)). Expect new
`report_package` findings at Stage 2. The rule from
[CLAUDE.md](../../CLAUDE.md) stands unchanged and must be enforced: **a new
filter requires a concrete-call gate proving the path is clean.** Budget review
time for this in Stage 2 rather than discovering it as a red CI at the end of
the highest-risk stage.

---

## Appendix A — the API surface this adds

**Types:** `Binary` (now abstract), `Code8`, `Code16`, `Dyadic`, `Head`,
`HeadF64`, `HeadF128`, `HeadExact`.

**Traits (per-format, generated):** `reptype`, `codeunit_type`, `datumtype`,
`rung`. **Traits (op-aware):** `rung(op, Fs...)`, `factors(op)`,
`carriertype(::Head)`, `bigprec(Fs...)`.

**Functions:** `format(K,P,Σ,Δ)`; `Base.similar(A, ::Type{Binary{K,P,S,E}}, dims)`.

**Changed signatures:** `codepoint(v)::codeunit_type(typeof(v))`;
`encode(...)::codeunit_type(T)`; `rawvalue(::Type{F}, ::codeunit_type(F))`;
`(::Type{T})(c::Unsigned)`; `get_table(...)::Memory{codeunit_type(fr)}`;
`order_key(v)::UInt16 | UInt32`.

**Module:** `SmallFloats.Formats` (opt-in re-export of all 504 aliases).

## Appendix B — file-by-file edit index

| file | stages | nature |
|---|---|---|
| `dyadic.jl` | 7 | new, ~150 lines |
| `formats.jl` | 1,2,3 | rewritten head; generated traits; constructor and `show` per invariant 2 |
| `carriers.jl` | 1,6 | new, ~80 lines |
| `decode_encode.jl` | 4 | T4-gated decode; `ldexp` compute; widened encode/keys/sort |
| `project.jl` | 4,7 | comment fix (`d ≤ P−1 ≤ 15`); `Dyadic` method; no other change |
| `ops_scalar.jl` | 6 | `factors` column; per-head `apply_op` split |
| `juliacompat.jl` | — | none (A5) |
| `oracle.jl` | 6 | per-head `ωeval` rows; `_DE_*(P…)`; `bigprec` |
| `tables.jl` | 5,8 | unified `_table_for`; `Memory{U}`; parallel build; `f32_exact` disposition |
| `kernels.jl` | 4,5 | conditional Shape A at every arity; carrier-typed `decode!` |
| `blocks.jl` | 6,7 | factor-aware rung; P = 1 scale fast path; accumulator precision from `bigprec` |
| `packed.jl` | 4 | unit widening; K = 16 refusal |
| `approx.jl` | 3,6 | **A1 fix** (`UInt8` code construction); `codedistance` follows the widened `order_key`; budget as `Ref` (T9) |
| `rand.jl` | 8 | reachability documentation only |
| `SmallFloats.jl` | 2,3,8 | include order (16 layers); exports; `Formats` submodule; precompile workload |
| `test/` | 0,4,6,7,8 | golden digests (T12); G1–G5; restated tiers; `refimpl` promoted to shipped |
| `docs/src/*.md` | 8 | the 3–8 range is stated throughout; format-count claims; the `Binary16p*` ≠ `binary16` trap; feeds the LaTeX/PDF pipeline, so a stale range propagates into a released PDF |
| `benchmarking/` | 8 | per-rung report sections; the preflight abort condition becomes per-head (T8); own environment, so it needs its own `Pkg.develop` refresh |
| `README.md` | 8 | format count and supported bitwidth range |
| `Project.toml` | — | **no change — the extension adds zero dependencies** (O13) |
| `CLAUDE.md` | 2,3,8 | invariants 2, 8, 9, 10; include-order comment; K range; the restated test doctrine |
