# `Dyadic` ↔ `Rational`: exact bridge and implementation record

*Converting the rung-3 carrier to and from Julia's `Rational`, exactly, with
every edge named.*

Every claim about Julia's behaviour below was **run**, not recalled. The
surprises are in §1 and §3.2, and one of them made the code already in the
package wrong.

> **Status: implemented.** `dyadic_to_rational`, `rational_to_dyadic` and
> `isdyadic` are in `src/dyadic.jl`, exported from `DyadicNumbers`, with
> `Rational{T}(::Dyadic)` and `Dyadic(::Rational)` as aliases rather than
> duplicate bodies. §1's defect is fixed. §10 records what implementing it
> found — including two holes the design did not predict.
>
> **Current boundary.** `Dyadic` is an internal `Real`, not a public promotion
> target and not an `AbstractFloat`. The bridge is exported from the internal
> `SmallFloats.DyadicNumbers` module for exact-or-refuse conversion and for the
> rational differential tests. Finite values and +/-Inf round-trip exactly; NaN
> and non-dyadic finite rationals refuse. The current implementation and tag
> invariants are in [`src/dyadic.jl`](../../src/dyadic.jl).

---

## 1. The pre-implementation defect (fixed)

Before this bridge was implemented, `src/dyadic.jl` had one direction:

```julia
function Base.Rational{BigInt}(x::Dyadic)
    isfinite_dy(x) || throw(InexactError(:Rational, Rational{BigInt},
        "a non-finite Dyadic has no rational value"))
    n = BigInt(x.S)
    x.Q >= 0 ? (n << x.Q) // BigInt(1) : n // (BigInt(1) << (-x.Q))
end
```

It had been written for gate G7, where only finite datums arise, and its non-finite
policy was chosen from the premise *"a rational cannot represent infinity"*.

**That premise is false, and Base disagrees with it:**

```julia
julia> Rational{BigInt}(Inf)
1//0

julia> 1//0, -(1//0)
(1//0, -1//0)

julia> isinf(1//0)
true

julia> 0//0
ERROR: ArgumentError: invalid rational: zero(BigInt)//zero(BigInt)
```

Julia's `Rational` **does** carry ±∞ as `±1//0`. Only `0//0` — the NaN slot — is
rejected. So the package converts `Dyadic(Inf)` by throwing while
`Rational{BigInt}(Inf)` returns `1//0`, and a caller who writes generic code over
`Real` gets different behaviour from the two.

The corrected policy falls out of Base rather than being invented:

| input | Base's answer for `Float64` | what `Dyadic` should do |
|---|---|---|
| finite | the exact rational | the exact rational |
| `+Inf` | `1//0` | `1//0` |
| `−Inf` | `-1//0` | `-1//0` |
| `NaN` | `ArgumentError` (via `0//0`) | throw — but say *why* |

This is the third time in this work that a "cannot represent" premise turned out
to be untested (§11 M44's `Float16`, `morejulian.md` §5.3's error hint). The rule
worth extracting: **before writing a refusal, run the thing you are refusing on
the type Base would use.**

---

## 2. The value model, and where the edges are

```julia
struct Dyadic <: Real
    S::Int128        # signed significand
    Q::Int64         # value = S · 2^Q  (finite kind only)
    kind::UInt8      # DY_FINITE | DY_POSINF | DY_NEGINF | DY_NAN
end
```

The tag comes **last**, not first, and that is a layout decision rather than a
stylistic one: `S` needs 16-byte alignment, so a leading `UInt8` costs 15 bytes
of padding and a 40-byte struct, while a trailing one lands in `Q`'s slack for
32 bytes. Positional construction is therefore `Dyadic(S, Q, kind)`.

Two properties of the representation drive everything:

**`S` is deliberately not normalized.** `dyadic.jl`'s docstring says so: it is
not reduced after each operation because the only consumer, `round_to_precision`,
realigns anyway. So `Dyadic(3, -1)` and `Dyadic(6, -2)` are the *same value* with
different fields, and `==` compares values. Any conversion must therefore be a
function of the **value**, never of the fields — and the round-trip laws in §5
are stated on values for that reason.

**`Int128`'s range is asymmetric, and `abs` wraps.** Measured:

```julia
julia> abs(typemin(Int128))
-170141183460469231731687303715884105728        # still negative
```

`typemin(Int128)` is a legitimate significand — `nbits_dy` reports 128 for it and
handles it correctly — so any range check written as `abs(n) <= typemax(Int128)`
is wrong on exactly one input. §4 uses two-sided bounds instead.

---

## 3. `dyadic_to_rational`

### 3.1 Signature

```julia
dyadic_to_rational(x::Dyadic)                      -> Rational{BigInt}
dyadic_to_rational(::Type{T}, x::Dyadic)           -> Rational{T}
```

`BigInt` is the default because it is the only integer type that cannot fail: `Q`
reaches ±32 768 at `Binary16p1uf`, so the denominator `2^-Q` needs ~32 768 bits.
A narrow `T` is offered because a caller who knows their exponents are small
should not pay for `BigInt`, and because the reference oracle in `test/refimpl.jl`
is `Rational{BigInt}` specifically — naming the type at the call site documents
which is intended.

### 3.2 Edge cases, all of them

| case | condition | result | note |
|---|---|---|---|
| finite nonzero | `kind = FINITE`, `S ≠ 0` | `S · 2^Q` exactly | §3.3 |
| zero | `S = 0`, any `Q` | `0//1` | `Q` is irrelevant — a value function, not a field one |
| `+Inf` | `kind = POSINF` | `one(T)//zero(T)` | matches `Rational(Inf)` |
| `−Inf` | `kind = NEGINF` | `-one(T)//zero(T)` | matches `Rational(-Inf)` |
| `NaN` | `kind = NAN` | **throw** `InexactError` | `Rational` has no NaN; `0//0` is an `ArgumentError` in Base, but `InexactError` is the better verb for a *conversion* that cannot represent its input |
| `S = typemin(Int128)` | — | exact | works because the value goes through `BigInt(S)` before anything else |
| narrow `T`, `Q` large | `2^|Q| ∉ T` | **throw** `OverflowError` | must be *checked*, not left to wrap |

### 3.3 Algorithm, and why not `//`

The obvious body is `BigInt(S) // (BigInt(1) << -Q)`. It is correct and it does a
**gcd** it does not need.

`//` reduces by `gcd(num, den)`. Here `den` is a power of two, so the gcd is
`2^min(trailing_zeros(S), -Q)` — computable with one instruction instead of
Euclid's algorithm. Normalizing the power of two directly and constructing with
`Base.unsafe_rational` skips the reduction:

```julia
function dyadic_to_rational(::Type{T}, x::Dyadic) where {T<:Integer}
    x.kind == DY_NAN    && throw(InexactError(:dyadic_to_rational, Rational{T},
                                              "NaN has no rational value"))
    x.kind == DY_POSINF && return Base.unsafe_rational(one(T), zero(T))
    x.kind == DY_NEGINF && return Base.unsafe_rational(-one(T), zero(T))
    iszero(x.S)         && return Base.unsafe_rational(zero(T), one(T))

    n, q = BigInt(x.S), Int(x.Q)
    tz = trailing_zeros(n)                 # the whole reducible part
    if q >= 0
        Base.unsafe_rational(T(n << q), one(T))          # integral: den = 1
    else
        k = min(tz, -q)                                  # cancel, don't gcd
        Base.unsafe_rational(T(n >> k), T(BigInt(1) << (-q - k)))
    end
end
```

Three things this gets right that the naive version does not:

* **The reduction is exact and cheap.** After cancelling `k` factors of two the
  numerator is odd or the denominator is 1, which is precisely `Rational`'s
  normalization invariant — so `unsafe_rational` is safe here in the strict
  sense: the invariant is established, not skipped.
* **`Q ≥ 0` never builds a denominator.** The value is an integer; `n << q` is
  the whole answer.
* **The `T` conversions are where narrow types fail loudly.** `T(n << q)` throws
  `InexactError` from `BigInt` conversion when the result does not fit, which is
  the behaviour a caller wants — but see §3.4.

### 3.4 One correction to that sketch

`T(n)` on a `BigInt` throws `InexactError`, not `OverflowError`, and the message
will name `BigInt` rather than the shift that produced it. For a conversion whose
whole purpose is exactness, the error should say which side overflowed:

```julia
_fit(::Type{T}, n::BigInt, what) where {T<:Integer} =
    typemin(T) <= n <= typemax(T) ? T(n) :
        throw(OverflowError("dyadic_to_rational: the $what needs " *
                            "$(ndigits(n; base=2)) bits, which Rational{$T} " *
                            "cannot hold; use Rational{BigInt}"))
_fit(::Type{BigInt}, n::BigInt, _) = n         # the total case, no check
```

The two-sided comparison is deliberate — `abs(n) <= typemax(T)` is the form that
`typemin(Int128)` defeats (§2).

---

## 4. `rational_to_dyadic`

### 4.1 The precondition that defines the function

A `Rational` is representable as a `Dyadic` **iff its denominator is a power of
two**. `1//3` is not a dyadic rational and no `Dyadic` holds it. This is not an
overflow question and no wider type fixes it.

So the conversion has a genuine partiality, and the package's doctrine decides
what to do with it: **refuse, never round.** Rounding `1//3` into a `Dyadic`
would be a rounding performed outside `project`, which invariant 1 forbids.

That argues for two entry points, not one:

```julia
isdyadic(q::Rational)          -> Bool          # can this convert exactly?
rational_to_dyadic(q::Rational) -> Dyadic       # exact or throws
```

`isdyadic` is what lets a caller branch without exception handling, and it is the
honest counterpart to a partial conversion. (Julia has no `tryconvert`; the
predicate is the idiomatic substitute.)

### 4.2 Edge cases, all of them

| case | condition | result |
|---|---|---|
| zero | `num = 0`, `den ≠ 0` | `DYADIC_ZERO` |
| dyadic finite | `den = 2^k`, `num` fits `Int128` | `Dyadic(num >> tz, tz − k)` |
| `+∞` | `num > 0`, `den = 0` | `DYADIC_POSINF` |
| `−∞` | `num < 0`, `den = 0` | `DYADIC_NEGINF` |
| `0//0` | — | unreachable: Base rejects it at construction |
| **non-dyadic** | `den` not a power of two | **throw** `InexactError` naming the denominator |
| numerator too wide | `num >> tz` outside `Int128` | **throw** `InexactError` — `S` is `Int128` and that is the type's limit |
| `num = −2^127` | — | representable; the check must be two-sided (§2) |
| unreduced input | e.g. `unsafe_rational(2, 4)` | still correct: the power-of-two test and the `tz` strip do not assume reduction |
| `den = 1` | integer-valued | `Q = tz(num)`, `S = num >> tz` |

Note the last two rows together: the algorithm never relies on `Rational`'s
reduction invariant, so it stays correct on a hand-built unreduced value. That is
cheap insurance and it removes a premise.

### 4.3 Algorithm

```julia
isdyadic(q::Rational) = iszero(denominator(q)) || ispow2(denominator(q))

function rational_to_dyadic(q::Rational)
    n, d = numerator(q), denominator(q)
    iszero(d) && return n > 0 ? DYADIC_POSINF : DYADIC_NEGINF
    iszero(n) && return DYADIC_ZERO
    ispow2(d) || throw(InexactError(:rational_to_dyadic, Dyadic,
        "denominator $d is not a power of two; $q is not a dyadic rational " *
        "and no Dyadic represents it exactly"))
    k  = trailing_zeros(d)                  # d == 2^k, so log2 by one instruction
    nb = BigInt(n)
    tz = trailing_zeros(nb)
    s  = nb >> tz
    typemin(Int128) <= s <= typemax(Int128) || throw(InexactError(
        :rational_to_dyadic, Dyadic,
        "the significand needs $(ndigits(s; base=2)) bits; Dyadic's is Int128"))
    Dyadic(Int128(s), Int64(tz - k))
end
```

`ispow2(d)` works for `BigInt` as well as machine integers (checked), and
`trailing_zeros` is defined for `BigInt` (checked) — so a `Rational{BigInt}` with
a 32 768-bit denominator converts without a `log2` or a loop.

**`Q` cannot overflow `Int64` in practice and should still be checked.** `tz − k`
is bounded by the bit lengths of the operands; reaching ±2^63 would need an
integer with 9.2 × 10^18 bits. The check costs one comparison and turns an
impossible-but-silent wrap into a stated refusal, which is the same trade §11 M48
made for `project_interval`'s ceiling.

---

## 5. The round-trip laws, stated on values

Because `S` is unnormalized (§2), the natural-looking law is **false**:

```julia
rational_to_dyadic(dyadic_to_rational(x)) === x        # FALSE — fields differ
```

`Dyadic(6, -2)` round-trips to `Dyadic(3, -1)`: same value, different fields.
What holds is:

1. **Value round trip.** For every `Dyadic` `x`:
   `rational_to_dyadic(dyadic_to_rational(x)) == x` — using `==`, which
   `dyadic.jl` defines on values via `cmp_dy`. True for the non-finites too,
   under the §1 policy.
2. **Rational round trip is an identity.** For every dyadic `q`:
   `dyadic_to_rational(rational_to_dyadic(q)) == q`, because both sides are
   reduced and `Rational` is canonical.

   **`==`, not `===`, and the difference is not pedantry.** `Rational{BigInt}`
   is backed by heap-allocated `BigInt`s, and `===` on those is *object
   identity* — two structurally equal values compare `false`. Running it:

   ```julia
   dyadic_to_rational(DYADIC_POSINF) === Rational{BigInt}(Inf)   # false
   dyadic_to_rational(DYADIC_POSINF)  == Rational{BigInt}(Inf)   # true
   ```

   `===` is correct only for an `isbits` target such as `Rational{Int}`. The
   first draft of this document specified `===` and §9 records what running it
   showed.
3. **Normalizing idempotence.** `rational_to_dyadic ∘ dyadic_to_rational` is the
   canonical-form function on `Dyadic`: it maps every representation of a value
   to the one with odd `S` (or `S = 0`). Applying it twice changes nothing.

Law 2 is the one to lean on in the suite: `Rational` is canonical, so it pins
both the value *and* the reduction. Law 1 needs `==` on `Dyadic` (which compares
values, via `cmp_dy`) and law 3 is a fixed-point check on the fields. All three
are cheap; all three were run (§9).

---

## 6. API shape

Two questions, answered separately.

**Should these be constructors?** Julia's convention for exact numeric
conversion is the constructor: `Rational{BigInt}(x)` and `Dyadic(q)`. Both should
exist, and both should be *the named functions' aliases* rather than duplicate
implementations:

```julia
Base.Rational{T}(x::Dyadic) where {T<:Integer} = dyadic_to_rational(T, x)
Dyadic(q::Rational) = rational_to_dyadic(q)
```

The existing `Base.Rational{BigInt}(::Dyadic)` is then replaced by the general
one — and gains the corrected ±Inf behaviour of §1 in the process, which is the
actual bug fix.

**Should they be exported?** No. `Dyadic` itself is not exported from
`SmallFloats` — it is `SmallFloats.DyadicNumbers.Dyadic`, an internal carrier —
so exporting its conversions would advertise a type users are not given. They
belong in `DyadicNumbers`' export list, where `Dyadic` already is, and reach
users through `Rational{BigInt}(x)` if a `Dyadic` ever escapes.

---

## 7. What the tests must cover

Mapped to the existing gates rather than invented:

* **Every edge in §3.2 and §4.2**, one assertion each. These are enumerable and
  finite; there is no reason to sample.
* **Law 2 (`===`) over the T1 lattice.** Every code point of every format decodes
  to a datum; at rung 3 that datum is a `Dyadic`. Round-tripping each through
  `Rational{BigInt}` is 7 602 160 exact identities and costs one pass — the same
  shape as T1's other properties, and it belongs in the same loop for the same
  reason (the cost is specialization, not iteration).
* **Law 1 on unnormalized inputs specifically.** Build `Dyadic(S << j, Q - j)`
  for several `j` and assert all round-trip to the same value. This is the law
  that a fields-based implementation would break, so it is the one worth
  targeting.
* **The non-finite policy against `Base`.** Assert
  `dyadic_to_rational(DYADIC_POSINF) == Rational{BigInt}(Inf)` — comparing to
  Base rather than to a literal, so the test tracks Base if Base ever changes.
  (`==`, per law 2's note.)
* **`isdyadic` agrees with `rational_to_dyadic`'s success** over a structured set
  of rationals: powers of two, non-powers, negatives, zero, `±1//0`.

G10 should gain `Rational` in its veneer list for the same reason it gained
`hash`: it is a conversion generic code reaches for.

---

## 8. Summary

| decision | choice | why |
|---|---|---|
| ±Inf | `±1//0`, matching Base | `Rational` **does** carry infinities; the current code's refusal is a defect |
| NaN | throw `InexactError` | `Rational` has no NaN slot; `0//0` is rejected by Base too |
| default target | `Rational{BigInt}` | the only total choice — `Q` reaches ±32 768 |
| narrow target | offered, **checked** two-sided | `abs(typemin(Int128))` wraps |
| reduction | strip trailing zeros, not `gcd` | the denominator is a power of two, so the gcd is one instruction |
| non-dyadic input | refuse, never round | rounding outside `project` violates invariant 1 |
| partiality | `isdyadic` predicate beside the throwing conversion | Julia has no `tryconvert`; a predicate is the idiomatic substitute |
| round trip | stated on **values**, not fields | `S` is deliberately unnormalized |
| export | no — `DyadicNumbers` only | `Dyadic` is not a public type |

The single most important line in this document is §1's: the conversion already
in the package threw where Base returns `1//0`, and it did so because a plausible
claim about `Rational` was never run.

---

## 9. The design was executed before it was written down

Every algorithm in §3.3, §3.4 and §4.3 was implemented and run against the edge
tables. Results:

```
finite 1.5            3//2      ok        +Inf                  1//0      ok
unnormalized 6·2^-2   3//2      ok        -Inf                 -1//0      ok
zero Q=5              0//1      ok        NaN                  InexactError
integral 3·2^4       48//1      ok        non-dyadic (1//3)    InexactError
typemin(Int128)                 ok        narrow overflow      OverflowError
laws 1-3: all hold             unreduced input: correct
isdyadic over (1//3, 3//4, 0//1, 1//0, 5//1) = (false, true, true, true, true)
```

Two things the run changed.

**`===` became `==` in law 2** — see §5. `Rational{BigInt}` is `BigInt`-backed
and `===` is object identity, so the law as first written was false for the
default target type and true only for `isbits` ones. A design document that
specifies the wrong comparison would have propagated straight into the test that
was supposed to check it.

**The `typemin(Int128)` row passed for a reason worth keeping.** It works because
the algorithm converts to `BigInt` *before* touching the sign — had it computed
`abs(S)` first, as a range check naturally wants to, it would have wrapped
silently (§2). The two-sided bound in `_fit` is what makes that safe, and it is
the same shape of error as the `abs(n) <= typemax(T)` idiom this document warns
against.

---

## 10. What implementing it found

The design held: every algorithm in §3.3, §3.4 and §4.3 went in unchanged, and
the edge tables passed on the first run — 102 assertions in
`test/dyadic_rational.jl`. Two things the design did *not* predict, both
surfaced by putting law 1 into T1's lattice-wide sweep.

### 10.1 `Rational{BigInt}(::Float128)` does not exist

Law 1 was first written as "convert the datum to `Rational`, convert back". That
errored on **all 64 rung-2 formats**:

```
MethodError: no method matching _precision_with_base_2(::Type{Float128})
```

`Rational{BigInt}(x::AbstractFloat)` routes through `precision(::Float128)`,
which Quadmath does not define — the hole §11 M35 recorded and `refimpl.jl`
carries a note about. Going through the datum's own carrier tests *Base's gap*
rather than this bridge.

The corrected probe converts to `Dyadic` first (`dyadic_from` is exact at every
carrier) and round-trips *that*. It is also the more honest test: law 1 is a
statement about the bridge, and the carrier is incidental to it.

### 10.2 `dyadic_from` was not total over the carriers

With the probe corrected, 8 errors remained — the rung-3 formats, where the datum
**is already a `Dyadic`** and `dyadic_from(::Dyadic)` had no method.

`dyadic_from` was total over the *float* carriers and not over `CarrierValue`, so
any generic "put this datum in exact form" call had a hole at exactly the rung
the carrier exists for. One identity row fixes it, and the idempotence is correct
independently of this test.

Both are the same shape as §11 M44's finding, which is worth noting because it
keeps recurring: **a function that is total over the types you were thinking
about is not total.** The rung-3 carrier is the one that gets forgotten, because
it is the one that arrived last.

### 10.3 Where the tests landed

* `test/dyadic_rational.jl` — the §3.2 and §4.2 edge tables, the narrow-target
  overflow checks, `isdyadic` against the conversion's success, and all three
  laws including the unnormalized-input case law 1 exists to catch. 102
  assertions, exhaustive over the enumerable edges.
* `tier_t1.jl` — law 1 over **all 7 602 160 code points**, inside T1's existing
  single pass. A separate sweep would have paid the 504-format specialization
  twice for the same points, which is T1's whole reason for being one loop.
* `gatelog.jl` — registered as `D↔Q`, so the roll-call names it and a run that
  skips it fails.
