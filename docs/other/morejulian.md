# More Julian

*Where this API departs from idiomatic Julia, which departures are defects,
which are deliberate and right, and what changed.*

Everything below was **probed against the running package**, not read off the
source. Where a claim is a measurement, the number is here. Where it is taste, it
says so and gives the counter-argument.

The findings are ranked by what a user loses, not by how much code they touch.

> **Status.** Tiers 1 and 2 are **implemented**; §5 records what each fix taught,
> including two places where the first attempt was worse than the second and one
> measurement that was simply wrong. Tier 3 is unchanged by decision. Tier 4 is
> measurement, and one of its entries exists to *stop* a refactor.

> **Reading convention.** Tiers 1 and 2 state the defects in the present tense
> because they preserve the probes that found them. They are not current API
> limitations. The current surface supplies `decompose`/`hash`, integer rounding,
> `widen`, `frexp`/`significand`/`exponent`, named refusals, callable `Op`, and
> normalized `similar`; the summary and §5 describe the shipped resolution.
> Their implementation is centralized in
> [`juliacompat.jl`](../../src/juliacompat.jl).

---

## Tier 1 — broken contracts found and fixed

`Binary{K,P,σ,δ} <: AbstractFloat`. Subtyping is a promise: Julia's generic code
assumes the `AbstractFloat`/`Real` interface is there, and reaches for it without
asking. These were the places the promise was not kept.

### 1.1 Before the fix: `hash` threw

The single highest-value fix in this document.

```julia
julia> hash(Binary8p4se(1.5))
ERROR: MethodError

julia> Dict(Binary8p4se(1.5) => 1)
ERROR: MethodError

julia> Set([Binary8p4se(1.5)])
ERROR: MethodError
```

**Cause.** `Base.hash(::Real, ::UInt)` is defined in terms of `Base.decompose`,
and:

```
hasmethod(Base.decompose, Tuple{Binary8p4se})  →  false
hasmethod(Base.decompose, Tuple{Dyadic})       →  true
```

The package defined `decompose` for its *internal* carrier (`Dyadic`, added in
Stage 7 so gate G6 could classify non-finites) and not for the type users
actually hold. A value that printed, compared, sorted, and did arithmetic could
therefore not be a dictionary key — the first thing anyone writing a
quantization histogram or a code-point frequency table will try.

**Fix.** `decompose` returns `(num, pow, den)` with the value equal to
`num · 2^pow / den`. A P3109 datum *is* exactly `S · 2^Q`, and the engine already
computes that triple:

```julia
function Base.decompose(v::Binary)
    d = decode(v)
    isnan(d)  && return (0, 0, 0)
    isinf(d)  && return (signbit(d) ? -1 : 1, 0, 0)
    T = typeof(v)
    r = round_to_precision(precision(T), expbias(T), NearestTiesToEven(), d, 0, 0)
    (Int(r.sign) * Int(r.S), Int(r.Q), 1)
end
```

Three properties make this the right implementation rather than merely a working
one:

* **It is exact by construction.** The datum is a code point; `round_to_precision`
  on an exact datum is pure extraction, not rounding — the same fact T1 asserts
  over all 7 602 160 code points.
* **It reuses the engine.** No second derivation of the significand/exponent
  split to drift from the first (invariant 7's spirit).
* **`hash`/`isequal` consistency comes free, and P3109 makes it easier than
  IEEE.** There is one NaN and no negative zero, so the two hazards that make
  float hashing subtle in Base do not exist here.

Note the shape of the bug: the internal type got the method, the public type did
not. That is the same asymmetry as §11 M44 — the per-head wrappers were fixed and
the shared implementation beneath them was not.

### 1.2 Before the fix: the rounding family was absent

```
round  floor  ceil  trunc      →  MethodError
```

These are `AbstractFloat` staples and they are *meaningful* here: rounding a
`Binary8p4se` to an integer value is a well-defined datum-set question. Their
absence means `round.(A)` fails on an array of small floats, which is an ordinary
thing to write.

They also raise a genuine design question the package should answer explicitly
rather than by omission: **`round(x::Binary)` under which ρ?** The defensible
answer is the one the package already uses for `Base` verbs — the session default
projection — with `RoundingMode` arguments mapping through the existing
`projmode` shim.

### 1.3 Before the fix: `widen`, `frexp`, `significand`, and `exponent`

`widen(T)` is used by Base's accumulation paths. `frexp`/`significand`/`exponent`
are the standard decomposition trio, and the package computes all three
internally.

*A correction, since the first draft of this document got it wrong.* `exponent`
looked like a deliberate refusal — Julia prints "This error has been manually
thrown, explicitly" — but that hint is about `Base.exponent`'s own internals, not
about this package: `methods(Base.exponent)` showed a `SmallFloats` entry only for
the internal `Dyadic` carrier. **There was no package refusal here at all**, which
matters because it changes the fix from "make the other two refuse alike" to
"implement all three".

All three are now implemented. `exponent` is exact for every finite nonzero
datum. `significand` and `frexp` are exact too, with one honest exception in
§5.2.

### 1.4 Refusals are inconsistent, and one style is clearly better

The first draft of this section read `rem`'s error as a well-made package
refusal and held it up as the model. **It is not — it comes from Base's promotion
machinery**, which happens to name the type on its way to failing. Tracing the
backtrace put the throw at `Base.promotion:641`, not anywhere in `src/`.

The corrected finding is stronger. **The package had no deliberate-refusal
mechanism anywhere in its Base-verb surface**: every absence, intended or not,
produced an identical bare `MethodError`, so nothing in the API could distinguish
"we thought about this and declined" from "we forgot".

**This matters more than it looks.** §11 M44's whole lesson was that the suite
cannot tell a deliberate absence from a defect, and neither can a user. A package
this careful about stating what it does not cover should state it in the error
too.

Now one `_unsupported(f, T, why)` helper carries every deliberate refusal, and
three things use it: `rem`/`mod` (the draft defines no remainder, and the exact
one is generally not a datum), `round(x, RoundFromZero)` and
`round(x, RoundNearestTiesUp)` (no draft μ), and `significand` on the one format
whose binade `[1, 2)` is truncated by its `Inf` encoding. Each says which and
why, and each names an alternative.

---

## Tier 2 — idiomatic reshaping that shipped

### 2.1 The operation register is callable, so `map` and broadcast work

Today the array path has its own verb:

```julia
vmap!(dest, Val(:Add), T, ρ, A, B)
```

`vmap` exists for a real reason — `map` cannot express `(operation, result
format, projection)` — but the cost is that users must learn a second word for
something Julia already has two words for.

A callable struct closes the gap without giving anything up:

```julia
map(Op(:Add, T, ρ), A, B)
Op(:Exp, T, ρ).(A)
```

`Op{name,FR,RHO}` is a singleton, so it specializes exactly as the `Val(:Add)`
route does, and `vmap!` stays the in-place table-aware kernel underneath. This is
additive: nothing existing changes meaning.

**The call methods are generated from `OP_REGISTRY`, one per operation, and that
is a performance decision.** The obvious single body —
`getfield(SmallFloats, name)(FR, RHO(), xs...)` — is a module lookup Julia will
not reliably fold, so the operation would resolve at *run* time, turning a
specialized call dynamic on exactly the array path this type exists to serve.
Generating per operation also means a new registry entry gains a callable with no
edit (invariant 7).

Measured, with the format entering as a type parameter: **`Op` allocates zero**,
and where the direct call allocates — a rung-2 or rung-3 `Exp` escalating into
the MPFR ladder — `Op` allocates exactly the same. It adds nothing. §5.3 records
how the first attempt at that measurement was wrong.

### 2.2 `similar` normalizes the abstract format where Julia permits

Measured, and silent:

```
isbitstype(eltype(Vector{Binary{8,4,true,true}}(undef, 3)))  →  false
isbitstype(eltype(Vector{Binary8p4se}(undef, 3)))            →  true
```

Nothing errors — every operation still returns the right answer, because the
package normalizes the abstract format at each entry point. You lose the entire
performance story and are told nothing. `similar(a, T)` already normalizes;
`similar(a)` on an already-abstract array propagated the abstraction, so an
abstractly-typed array stayed abstract through every `similar` in the package.

It now normalizes — through **three** methods rather than one, for a reason that
is a fact about Julia dispatch rather than about this package. See §5.1.

This stops the abstraction *propagating*; it cannot stop it *arising*, because
`Vector{Binary{8,4,true,true}}(undef, n)` is a constructor call with no hook.
That entry is documented in the user guide's performance section instead.

### 2.3 `reinterpret` is sanctioned and range-checked

```julia
julia> reinterpret(UInt8, Binary8p4se(1.5))
0x44

julia> reinterpret(Binary8p4se, 0x44)
Binary8p4se(1.5 ≡ 0x44)
```

`Binary` is `isbits`, so Julia's generic `reinterpret` supplied the basic
operation. It is *the* idiomatic Julia spelling for "same bits, different
type"; the package now documents it and installs a more-specific checked input
method.

The current method makes it the sanctioned bit-level route alongside
`T(::Unsigned)` and `rawvalue`, and rejects high bits that violate the
representation invariant. The output direction needs no additional check
because valid `Binary` values already satisfy that invariant.

(The user guide already documents the *other* half of this: reinterpreting a
`Float16` as a `Binary16p11se` silently changes the value, because the biases
differ by one.)

---

## Tier 3 — departures I would keep

Each of these looks un-Julian and is right anyway.

### 3.1 The CamelCase operation register

52 exported functions named `Add`, `Multiply`, `Exp` — Julia reserves CamelCase
for types. Keep them. They are the draft's §3.2 names, and a conformance
implementation that renamed the standard's operations would be harder to audit
against the standard, which is the package's entire purpose.

The idiomatic path already exists beside them: `a + b`, `exp(x)`, `fma(a,b,c)`
all work and use the session default projection. So the split is
**`CamelCase` = explicit projection, `Base` verb = ambient projection**, which is
a real distinction worth two spellings. It should be stated in exactly those
words in the user guide.

### 3.2 `T(0x02)` is a code point, `T(2)` is the value 2.0

Overloading the constructor on integer *signedness* is unusual. It is also
invariant 2, it is checked exhaustively, and the alternative — a separate
constructor name — loses the property that `Unsigned` means code point *at every
width*, which is what makes `codepoint`/`rawvalue` composable across the
`Code8`/`Code16` seam.

### 3.3 `Base.codepoint` extended to floats

`Base.codepoint` is about characters. Extending it here is legal (the package
owns `Binary`) but semantically odd. The source comment says it avoids an export
clash, which is a real consideration. Keep — but the oddity deserves a line in
the docs rather than only in a source comment.

### 3.4 `DefaultProjection!` and friends

`!` conventionally marks argument mutation, and these mutate process-global
state instead. But they *do* mutate, the `!` warns, and the scoped alternatives
(`with_default_projection`) exist. Keep. What was missing — and was added this
session — is the warning that the setters are process-global and leak across
modules, which had silently invalidated three examples in the user guide.

---

## Tier 4 — performance-tips items

### 4.1 Keyword arguments are free here; do not "fix" them

The spec register takes `; rng, R`, and keyword arguments have a reputation.
Measured, warm, behind a barrier:

```
Add(T, ρ, x, y)          0.19 ns/call, 0 allocations
Add(T, ρ, x, y; R = 0)   0.21 ns/call, 0 allocations
```

Within noise. Modern Julia specializes keyword methods properly. **Removing them
would be a refactor with no measured benefit** — worth recording precisely so
nobody spends a day on it.

### 4.2 The vararg-length lesson generalizes

`apply_op`'s wide route took `xs...` with no length parameter; its two splat
calls compiled to `Core._apply_iterate` and boxed every carrier value crossing
them — 304 bytes per warm binary call on `Float128`, 592 on `Dyadic`, while every
*component* of the same call measured zero (§11 M46). `Vararg{Any,N}` fixed it.

The general rule for this codebase: **an untyped `...` in a `@noinline` function
on a hot path is a boxing site until measured otherwise.** Worth a grep whenever
a new route is added.

### 4.3 Specialization dominates everything

Measured three independent times: G10 is 99.8 % compilation, T1 98 %, Tρ 99.3 %.
`Binary{K,P,σ,δ}` is a distinct type per format and every method recompiles for
each.

The practical consequence, which cost real wall clock before it was understood:
**only the format and operation axes move the clock, because only they multiply
specializations. Value axes are free, and tiering them buys nothing.** Cutting
`Tρ`'s R loop 5× changed its runtime by under 2 %.

### 4.4 `isapprox` has a surprising default here, and it is correct

```julia
julia> isapprox(Binary8p4se(1.5), Binary8p4se(2.0))
true
```

Because `eps(Binary8p4se) = 0.125`, the default `rtol = √eps` is about 0.35.
That is the right answer for a 4-bit significand and a shocking one for a reader
carrying `Float64` intuitions. Document it; do not change it.

---

## 5. What implementing it taught

Three of the fixes were wrong the first time in ways worth keeping, because each
is a general trap rather than a local slip.

### 5.1 A more specific element type loses to a fixed dimension

`similar` was first written as one method:

```julia
Base.similar(a::Array{T,N}) where {T<:Binary,N} = ...   # never fires
```

It never ran. Base defines `similar(a::Vector{T})` and `similar(a::Matrix{T})`
with the **dimension fixed**, and in Julia's specificity ordering a fixed
dimension outranks a bounded element type. `which(similar, Tuple{Vector{...}})`
pointed straight at `Base.array.jl:372`.

So there are three methods now — `AbstractArray`, `Vector`, `Matrix` — and the
comment says why, because the failure mode is silent. **A method that does not
fire is worse than a method that is absent**: the absent one shows up as a
`MethodError`, and the shadowed one shows up as nothing at all.

### 5.2 Ask the format, not the value

`significand` must return the same type (Base's contract), and the significand of
a datum is not always a datum of its own format — `Binary3p2se` spends the code
that would carry `1.5` on `Inf`.

The first implementation checked *per value*, by projecting and decoding back to
see whether the round trip was exact. That is two engine calls on every call, on
a path where the answer never depends on the value.

Whether a format can hold every significand is a property of `(P, B, δ)`:
`significand(x) ∈ [1, 2)` needs the binade `e = 0` fully populated, which an
extended format truncates only when that binade is also its top one.
`_binade0_complete(T)` is a pure function of the type parameters, constant-folds
to a literal `true` for all but the degenerate formats, and costs nothing on the
path that succeeds. **Static where the question is static.**

### 5.3 The benchmark harness was the thing being measured

A first probe put `Op`'s scalar call at 48 bytes per call and looked like §11
M46's vararg-boxing defect returning. It was the harness: the format entered
through a **non-`const` global**, which is the ~1 µs dynamic-dispatch trap
CLAUDE.md's performance rules name in so many words. Rebuilt with the format as a
type parameter, `Op` allocates zero.

This is the third time in this work that a measurement post-mortem has been the
finding rather than the code. The benchmark doctrine exists because of the first
two; this one says it applies to *ad-hoc probes* as much as to
`benchmarking/`, and that a number which merely confirms a suspicion deserves the
same scrutiny as one that contradicts it.

### 5.4 And one the compiler caught

`round(v::T, r::RoundingMode) where {T<:Binary}` — generic in the mode, specific
in the type — is **ambiguous** with three of Base's per-mode `AbstractFloat`
methods. `Test.detect_ambiguities` said so on the first suite run.

Enumerating the modes fixes it and buys something better: the list of methods
*is* the statement of which Julia rounding modes have a P3109 counterpart,
checked by the compiler rather than asserted in a comment. The two that do not —
`RoundFromZero` and `RoundNearestTiesUp` — refuse by name through `_unsupported`
rather than inheriting Base's fallback, which would have computed on the carrier
and projected a result the draft never defined.

---

## Summary

| # | item | verdict |
|---|---|---|
| 1.1 | `Base.decompose` missing ⇒ `hash` throws ⇒ no `Dict`/`Set` | **done** — `Base.decompose`, §5 |
| 1.2 | `round`/`floor`/`ceil`/`trunc` absent | **done** — `round`/`floor`/`ceil`/`trunc`, per-mode |
| 1.3 | `widen`, `frexp`, `significand` absent | **done** — all three implemented; `exponent` was never refused (§1.3) |
| 1.4 | refusal style inconsistent (bare `MethodError` vs named `ErrorException`) | **done** — `_unsupported`, used by four refusals |
| 2.1 | callable `Op` so `map`/broadcast work | **done** — registry-generated, zero allocation |
| 2.2 | `similar(a)` propagates abstract eltype | **done** — three methods; §5.1 |
| 2.3 | `reinterpret` works, undocumented, ungated | **done** — checked against invariant 3 |
| 3.1 | CamelCase operation register | keep — draft names |
| 3.2 | `Unsigned` = code point | keep — invariant 2 |
| 3.3 | `Base.codepoint` on floats | keep — document |
| 3.4 | `DefaultX!` mutating globals | keep — scoped forms exist |
| 4.1 | keyword arguments | **leave alone — measured free** |

The Tier 1 items share a shape worth naming. Every one is a place where
`Binary <: AbstractFloat` promises an interface the package does not supply, and
the failure surfaces at a *user's* call site rather than the package's. Gate G10
exists to catch exactly this class — that the call returns at all — but it sweeps
`OP_REGISTRY` and the veneers the package chose to implement. **Extending G10's
veneer list to the full `AbstractFloat`/`Real` interface would have caught every
Tier 1 item**, and is the cheapest way to keep them caught.
