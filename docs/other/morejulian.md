# More Julian

*Where this API departs from idiomatic Julia, which departures are defects,
which are deliberate and right, and what I would change.*

Everything below was **probed against the running package**, not read off the
source. Where a claim is a measurement, the number is here. Where it is taste, it
says so and gives the counter-argument.

The findings are ranked by what a user loses, not by how much code they touch.

---

## Tier 1 — broken contracts

`Binary{K,P,σ,δ} <: AbstractFloat`. Subtyping is a promise: Julia's generic code
assumes the `AbstractFloat`/`Real` interface is there, and reaches for it without
asking. These are the places the promise is not kept.

### 1.1 `hash` throws — `Binary` values cannot be `Dict` keys or `Set` elements

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

The package defines `decompose` for its *internal* carrier (`Dyadic`, added in
Stage 7 so gate G6 could classify non-finites) and never for the type users
actually hold. So a value that prints, compares, sorts, and does arithmetic
cannot be a dictionary key — which is the first thing anyone writing a
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

### 1.2 The rounding family is absent

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

### 1.3 `widen`, `frexp`, `significand` are absent; `exponent` refuses

`widen(T)` is used by Base's accumulation paths. `frexp`/`significand`/`exponent`
are the standard decomposition trio, and the package computes all three
internally.

`exponent` refuses deliberately (a hand-thrown `MethodError`), and that is a
reasonable call — for a `P = 1` unsigned format "the exponent" is the whole
value, and the draft's own accessor is `expbias`/`expbitwidth`. But then
`significand` and `frexp` should refuse *the same way*, and for the same stated
reason.

### 1.4 Refusals are inconsistent, and one style is clearly better

```
rem(x, y)         →  ErrorException: "rem not defined for Binary8p4se"    ← good
significand(x)    →  MethodError                                          ← bare
frexp(x)          →  MethodError                                          ← bare
x:y  (a range)    →  ErrorException                                       ← good
```

`rem` and `mod` refuse with a sentence naming the type. `significand` and `frexp`
give a bare `MethodError` that reads as an oversight — because it is
indistinguishable from one.

**This matters more than it looks.** §11 M44's whole lesson was that the suite
cannot tell a deliberate absence from a defect, and neither can a user. A
package this careful about stating what it does not cover should state it in the
error too. Recommendation: one `_unsupported(f, T)` helper, used by every
deliberate refusal, so "absent" and "refused" are visibly different.

---

## Tier 2 — idiomatic reshaping worth doing

### 2.1 Make the operation register callable, so `map` and broadcast work

Today the array path has its own verb:

```julia
vmap!(dest, Val(:Add), T, ρ, A, B)
```

`vmap` exists for a real reason — `map` cannot express `(operation, result
format, projection)` — but the cost is that users must learn a second word for
something Julia already has two words for.

A callable struct closes the gap without giving anything up:

```julia
struct Op{name,FR,RHO} end
Op(name::Symbol, ::Type{FR}, ρ) = Op{name,FR,typeof(ρ)}()
(::Op{name,FR,RHO})(xs...) where {name,FR,RHO} = <the existing scalar path>

# then, idiomatically:
map(Op(:Add, T, ρ), A, B)
Op(:Exp, T, ρ).(A)
```

`Op{name,FR,RHO}` is a singleton, so it specializes exactly as the `Val(:Add)`
route does — no dispatch cost, and `vmap!` stays as the in-place, table-aware
kernel underneath. This is additive: nothing existing changes meaning.

### 2.2 `similar` should normalize the abstract format everywhere

Measured, and silent:

```
isbitstype(eltype(Vector{Binary{8,4,true,true}}(undef, 3)))  →  false
isbitstype(eltype(Vector{Binary8p4se}(undef, 3)))            →  true
```

Nothing errors — every operation still returns the right answer, because the
package normalizes the abstract format at each entry point. You lose the entire
performance story and are told nothing. `similar(a, T)` already normalizes;
`similar(a)` on an already-abstract array propagates the abstraction. Making the
no-type form normalize too recovers one of the two ways in. `Vector{T}(undef, n)`
genuinely cannot be intercepted, which is why this is documented in the user
guide's performance section as well.

### 2.3 `reinterpret` already works — sanction it

```julia
julia> reinterpret(UInt8, Binary8p4se(1.5))
0x44

julia> reinterpret(Binary8p4se, 0x44)
Binary8p4se(1.5 ≡ 0x44)
```

`Binary` is `isbits` and one byte, so Julia's generic `reinterpret` applies. It
is *the* idiomatic Julia spelling for "same bits, different type", and it works
today without being documented or tested.

Two consequences. It should be **documented** as the sanctioned bit-level route
alongside `T(::Unsigned)` and `rawvalue`. And it should be **gated**, because
`reinterpret` bypasses the representation invariant — nothing stops
`reinterpret(Binary3p1se, 0xFF)` producing a value with high bits set, which
invariant 3 says cannot exist. Either constrain it or assert against it.

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

## Summary

| # | item | verdict |
|---|---|---|
| 1.1 | `Base.decompose` missing ⇒ `hash` throws ⇒ no `Dict`/`Set` | **fix — highest value** |
| 1.2 | `round`/`floor`/`ceil`/`trunc` absent | **fix** |
| 1.3 | `widen`, `frexp`, `significand` absent | **fix or refuse explicitly** |
| 1.4 | refusal style inconsistent (bare `MethodError` vs named `ErrorException`) | **fix — one helper** |
| 2.1 | callable `Op` so `map`/broadcast work | add (additive) |
| 2.2 | `similar(a)` propagates abstract eltype | add |
| 2.3 | `reinterpret` works, undocumented, ungated | document + gate |
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
