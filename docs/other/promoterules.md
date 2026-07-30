# Promotion rules between two P3109 formats

*What `promote_rule(Binary{Kₐ,Pₐ,σₐ,δₐ}, Binary{Kᵦ,Pᵦ,σᵦ,δᵦ})` could be, what it
should be, and why the two are not the same answer.*

Every quantitative claim below is measured against the shipped 504-format grid,
not derived on paper. Where a rule is conservative or a count is a sample, it
says so.

---

## 1. The question, stated precisely

Julia's promotion machinery answers: *given a value of type `A` and a value of
type `B`, what single type holds both so an operation can proceed?* For
`Int` and `Float64` the answer is `Float64` and nobody thinks about it again.

For two P3109 formats the question is sharper, because this package's whole
premise is that **a format is a datum set**, and an operation's result is the
projection of the mathematically exact value into a *named* set. So promotion
between formats can only mean one thing:

> **The promotion target of `A` and `B` is a format whose datum set contains
> both — so that moving a value into it is exact, and no rounding happens before
> the operation the user actually asked for.**

Anything weaker is not promotion, it is a silent conversion with a rounding step
nobody wrote. That would violate the package's first invariant (`project` is the
only producer of a code point) by rounding somewhere else.

This document works out whether such a target exists, what it is when it does,
and what to do when it does not.

---

## 2. The parameters, and which of them is the range axis

A format is `Binary{K,P,σ,δ}` — bitwidth `K`, precision `P` (significand bits
including the implicit one), signedness `σ`, domain `δ` (extended = has ±Inf,
finite = does not). From `formats.jl`:

```julia
expbias(Binary{K,P,σ,δ})      = σ ? 2^(K-P-1) : 2^(K-P)
expbitwidth(Binary{K,P,σ,δ})  = (σ ? K-1 : K) - (P-1)
trailingsigbits(...)          = P - 1
```

Two facts do the work.

**The exponent bias depends on `(K, P, σ)` and not on `δ`.** Write

```
E := K − P − σ        (σ read as 0 or 1)          so    B = 2^E
```

`E` is the *range axis*. `P` is the *resolution axis*. `K` is not an axis at
all — it is the budget the other two spend:

```
K = P + E + σ
```

That single identity is the source of every difficulty below. **You cannot buy
resolution and range at the same `K`.** Raising `P` by one lowers `E` by one and
divides the representable range by a factor of `2^(2^…)` — the bias halves, so
the range shrinks *exponentially*.

**`δ` costs one magnitude code.** An extended format spends its top magnitude
code point on `Inf`; a finite format spends it on a finite value. Measured:

| format | K | P | E | B | max finite | min positive |
|---|---|---|---|---|---|---|
| `Binary8p4se` | 8 | 4 | 3 | 8 | 224 | 0.0009765625 |
| `Binary8p4sf` | 8 | 4 | 3 | 8 | **240** | 0.0009765625 |
| `Binary8p4ue` | 8 | 4 | 4 | 16 | 53248 | 3.8147e-6 |
| `Binary8p4uf` | 8 | 4 | 4 | 16 | **57344** | 3.8147e-6 |
| `Binary9p4se` | 9 | 4 | 4 | 16 | 57344 | 3.8147e-6 |

Note the last two rows: `Binary9p4se` and `Binary8p4uf` have identical finite
magnitudes. The signed format spent its extra bit on the sign; the unsigned one
spent it on range. That is the grid working as designed, and it is also why
"promote to the wider `K`" is not a rule — `K` alone tells you nothing.

---

## 3. The containment order

Define `A ⊒ B` ("`A` contains `B`") to mean: every datum of `B` — every finite
value, and `±Inf` if `B` has them — is a datum of `A`.

### 3.1 A sufficient rule, stated at the value level

```julia
A ⊒ B  ⟸  precision(A)      ≥ precision(B)
       ∧  issigned(A)       ≥ issigned(B)
       ∧  (isextended(A) ∨ ¬isextended(B))
       ∧  maxfinite(A)      ≥ maxfinite(B)
       ∧  minpositive(A)    ≤ minpositive(B)
```

Two of these are worth a sentence.

*The `maxfinite`/`minpositive` comparisons are what make `δ` correct
automatically.* Stating the rule on `(P, E, σ, δ)` alone gets the extended/finite
interaction wrong: `Binary8p4se ⊒ Binary8p4sf` looks true parameter-wise (same
`P`, same `E`, same `σ`, extended ⊒ finite) and is **false**, because
`Binary8p4sf`'s 240 is not a `Binary8p4se` datum — that code point is `Inf`
there. Comparing the endpoints catches it without a special case.

*The rule is sound, not tight.* Measured over all 14 400 ordered pairs at
K ≤ 8:

```
UNSOUND (rule says contained, containment false):   0
conservative (containment true, rule says no):      6
```

All six misses have the same right-hand side and one cause, worked out in
§3.1.1: `Binary3p2se` realizes only powers of two, so `P = 1` formats contain it
despite having less precision. **For promotion, soundness is the property that
matters and tightness is not** — a rule that occasionally promotes to a slightly
larger format is harmless; one that occasionally loses a value is a defect.

#### 3.1.1 The tight form

The sufficient rule above refuses six containments that genuinely hold. All six
share the same right-hand side, and finding out *why* turns the loose rule into
an exact one.

Every one of the six is `X ⊒ Binary3p2se` for some `P = 1` format. The reason is
that `Binary3p2se`'s finite magnitudes are

```
{ 1/2, 1 }
```

— **both powers of two**, despite `P = 2`. A `P = 1` format's datums are exactly
`±2^k`, so it contains them.

Why that format and no other: `K = 3`, `P = 2`, signed, extended gives `E = 0`,
so `B = 1`. The subnormal step is `2^(1−B−P+1) = 2^-1`, contributing the single
subnormal `1/2`; the one normal binade `e = 0` would hold `1.0` and `1.5`, and
the code that *would* have carried `1.5` is spent on `Inf`. The second
significand value never gets a code point, so `P = 2` buys nothing.

Scanning all 504 formats for "every finite magnitude is a power of two despite
`P ≥ 2`" returns **exactly one format**: `Binary3p2se`. It is not the first
member of a class — it is the whole class, and naming it is more truthful than
inventing a predicate that happens to select it.

So the tight rule is the sufficient rule with one named exception:

```julia
A ⊒ B  ⟺  issigned(A)       ≥ issigned(B)
       ∧  (isextended(A) ∨ ¬isextended(B))
       ∧  maxfinite(A)      ≥ maxfinite(B)
       ∧  minpositive(A)    ≤ minpositive(B)
       ∧  (precision(A) ≥ precision(B)  ∨  B === Binary3p2se)
```

Verified by enumerating exact magnitude sets over all 154 formats at `K ≤ 9`:

```
pairs          23 716
unsound             0        (rule says contained, containment false)
conservative        0        (containment true, rule says no)
```

**Necessary and sufficient**, with no residue.

Three notes on using it.

*The `P` clause is doing real work and the exception does not weaken it.* Outside
`Binary3p2se`, `precision(A) ≥ precision(B)` is genuinely necessary: `B`'s
significand grid is finer than `A`'s in every binade both occupy, so some `B`
datum falls between two `A` datums.

*The endpoint comparisons are what make `δ` right.* They already encode
"extended spends its top magnitude code on `Inf`", which is why the rule needs no
separate clause for the finite/extended clash — and why the parameter-only
version of this rule (comparing `E` instead of the endpoints) is wrong.

*For promotion, prefer the loose form.* §6 argues against a `Binary`-valued
`promote_rule` at all, but if one is ever built, the sufficient rule is the
better basis: the tight form's exception buys one extra containment involving a
`K = 3` format nobody promotes to, at the cost of a named special case in a rule
that should be structural. The tight form's value is as a *statement about the
grid* — it says exactly where the resolution axis is load-bearing and where the
code budget has already collapsed it.

### 3.2 `⊒` is a partial order, not a total one

`Binary8p4se` and `Binary8p3se` are incomparable: the first has more resolution
(`P = 4`), the second more range (`E = 4`, max finite 49152 against 224).
Neither contains the other. That is not an edge case — it is the *typical*
relationship between two formats at the same `K`, and it is forced by
`K = P + E + σ`.

---

## 4. The join, and the cases asked about

If a promotion target exists, the natural one is the **least upper bound**: the
smallest format containing both. Taking the componentwise maximum of the axes:

```
P⊔ = max(Pₐ, Pᵦ)
E⊔ = max(Eₐ, Eᵦ)
σ⊔ = σₐ ∨ σᵦ
δ⊔ = δₐ ∨ δᵦ            (extended if either is, because Inf must be held)
K⊔ = P⊔ + E⊔ + σ⊔
```

with one correction. **If either input is `finite` and already sits at the
join's `(P⊔, E⊔)`, its top magnitude collides with the join's `Inf` code.** The
join then needs one more binade of range:

```
if δ⊔ = extended and (∃ input X: δ_X = finite ∧ P_X = P⊔ ∧ E_X = E⊔)
    E⊔ += 1
```

That bump fires for **25 784 of the 254 016 ordered pairs** (10.1 %).

### 4.1 The cases in the question, worked

Taking `Binary8p4se` as the reference and varying one axis at a time:

| relationship | example pair | join | in the grid? |
|---|---|---|---|
| identical | `8p4se ⊔ 8p4se` | `Binary8p4se` | yes — the identity |
| **δ differs**, K P σ equal | `8p4se ⊔ 8p4sf` | **`K=9`** `p4se` *(+1 range bump)* | yes |
| **σ differs**, K P δ equal | `8p4se ⊔ 8p4ue` | **`K=9`** `p4se` | yes |
| **σ and δ differ** | `8p4se ⊔ 8p4uf` | **`K=10`** `p4se` *(+1 bump)* | yes |
| **P differs**, K equal | `8p4se ⊔ 8p3se` | **`K=9`** `p4se` | yes |
| **K differs**, P equal | `8p4se ⊔ 9p4se` | **`K=9`** `p4se` | yes |
| both at K = 16 | `16p11se ⊔ 16p8se` | `K=19` `p11se` | **no — off the grid** |

**Read the second and third rows again.** Two formats that agree on `K`, `P` and
signedness and differ *only* in whether they carry infinities do **not** promote
to anything at their own width. They need `K + 1`. Likewise two formats
differing only in signedness. There is no smaller answer: the join must hold
`Binary8p4sf`'s 240 *and* an `Inf`, and at `K = 8` there is no code point left
for both.

This is the single most counter-intuitive consequence of the design, and it is
not a defect in the grid — it is `K = P + E + σ` being an equality.

---

## 5. Three walls

### 5.1 The join often does not exist

Measured over all 254 016 ordered pairs of the 504 formats:

```
join exists inside the K ≤ 16 grid:   151 742   (59.7 %)
join does NOT exist:                  102 274   (40.3 %)
```

**Two out of five format pairs have no common format at all.** Every pair
involving a high-`P` format and a high-`E` format falls off the grid, because
the join needs `P⊔ + E⊔ + σ⊔` bits and those are additive while the grid caps
`K` at 16. `Binary10p10ue ⊔ Binary10p1se` needs `K = 19`.

A `promote_rule` must be **total** — it must answer for every pair. So a
Binary-valued rule would have to return a `Binary` for 59.7 % of pairs and
something else (a carrier) for the other 40.3 %.

### 5.2 The join is not associative

This is the decisive one. Julia computes `promote_type(a, b, c)` by pairwise
reduction, so the rule **must** be associative or the answer depends on argument
order. Measured over all 262 144 triples at `K ≤ 6`:

```
(Binary3p1se ⊔ Binary3p1sf) ⊔ Binary3p2se  =  K5p2
 Binary3p1se ⊔ (Binary3p1sf ⊔ Binary3p2se) =  K4p2
```

The `+1` range bump is the culprit: whether it fires depends on whether a finite
input is *currently* at the maximum, which changes as the fold proceeds. Bracket
left and you pay the bump then widen; bracket right and the widening absorbs it.

Removing the bump does not rescue associativity — it makes the rule *unsound*
instead, which is worse. The non-associativity is intrinsic to a lattice where
`δ` competes with range for the same code point.

### 5.3 The answer is surprising even when it exists

`Binary8p4se + Binary8p4sf` would produce a `Binary9p4se` — a format the user
named nowhere, at a width neither operand has. Silently. In a package whose
stated purpose is that results land in a format you *chose*, that is the wrong
kind of convenience.

---

## 6. The design decision

**Do not define `promote_rule` between two `Binary` formats.** Keep the current
behaviour, in which promotion targets the format's *promotion carrier*:

```julia
Base.promote_rule(::Type{F}, ::Type{Float64}) where {F<:Binary} = promotecarrier(F)
```

and cross-format arithmetic remains explicit — the package's stated deliberate
limitation, now with a measured justification rather than a stylistic one:

1. **It cannot be total in `Binary`.** 40.3 % of pairs have no join.
2. **It cannot be associative.** Measured, at `K ≤ 6`, with a witness.
3. **It would round silently where a join does not exist**, or return a carrier
   for some pairs and a `Binary` for others — a rule whose *return type class*
   depends on the operands, which no amount of documentation makes predictable.
4. **It would answer a question the user did not ask**, in a format they did not
   name.

The carrier promotion has none of these problems: `promotecarrier(F)` is total,
associative (it is a float-widening lattice), exact for the format's datums, and
returns a type the user can reason about without consulting a table.

### 6.1 What to offer instead

The lattice is real and useful — it just should not be *implicit*. Expose it:

```julia
"""
    formatjoin(A, B) -> Type{<:Binary} | Nothing

The smallest P3109 format whose datum set contains every datum of both `A` and
`B`, or `nothing` when no format in the K ≤ 16 grid does.

Sound but not tight: it may return a format one step larger than strictly
necessary at degenerate sizes (measured: 6 of 14 400 pairs at K ≤ 8).
"""
formatjoin(::Type{<:Binary}, ::Type{<:Binary})

"""
    formatcontains(A, B) -> Bool

Whether every datum of `B` is a datum of `A` — i.e. `Convert(A, ρ, x)` is exact
for every `x::B`, under every ρ.
"""
formatcontains(::Type{<:Binary}, ::Type{<:Binary})
```

`formatjoin` returning `nothing` is the honest signal that 40.3 % of pairs need.
A caller who wants cross-format arithmetic writes:

```julia
J = formatjoin(A, B)
J === nothing ? Add(promotecarrier(A), ρ, x, y) : Add(J, ρ, Convert(J, ρ, x), Convert(J, ρ, y))
```

— three lines that say exactly what happens, instead of a promotion rule that
hides which of the two branches was taken.

---

## 7. Consistency with the standing invariants

| invariant | how this design respects it |
|---|---|
| **1. One write path** | No promotion introduces a rounding step: carrier promotion is exact for the format's datums, and `formatjoin` is defined by containment so the `Convert` into it is exact. |
| **2. Code point vs value** | Untouched — promotion moves *values*, never code points. |
| **5. Nothing approximate by default** | A silent join-or-round rule would be an approximation reachable from `+`. Refusing it keeps the default path exact. |
| **9. Policy is dispatch** | `promotecarrier` is a trait function of the type parameters and constant-folds; `formatjoin` is reflection and is explicitly not on a hot path. |
| **Deliberate limitation: no implicit cross-format arithmetic** | This document is that limitation's justification, restated as measurements rather than preference. |

---

## 8. Summary

- Promotion between formats can only mean **datum-set containment**; anything
  else is a hidden rounding.
- `K = P + E + σ` is an equality, so resolution and range trade off exactly, and
  two formats at the same `K` are usually **incomparable**.
- The join exists for only **59.7 %** of pairs, is **not associative**, and even
  where it exists it lands at `K + 1` or `K + 2` for the "nearly identical"
  cases — differing only in `σ`, or only in `δ`.
- Therefore: **no `promote_rule` between two `Binary` formats.** Promote to the
  carrier, which is total, associative and exact, and expose `formatjoin` /
  `formatcontains` for callers who want the lattice explicitly.

### Reproducing the numbers

The measurements come from enumerating exact datum sets as `Rational{BigInt}`:
soundness and the six conservative misses over `K ≤ 8` (14 400 pairs), the join
census over all 504 formats (254 016 pairs), and the associativity counterexample
over `K ≤ 6` (262 144 triples). None of it is sampled.
