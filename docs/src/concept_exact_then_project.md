# The Exact-Then-Project Contract

Every number that enters a `Binary` format goes through the same pipeline,
regardless of whether it arrives via a constructor, an arithmetic operator,
or an explicit conversion. This page explains what that pipeline promises,
what "exact" means at each stage, and the handful of cases where the
contract refuses rather than bends.

## One write path

There is exactly one way a code point gets produced in SmallFloats.jl:

```
exact result  →  RoundToPrecision  →  Saturate  →  code point
```

The operation is computed *exactly* first — as exact real arithmetic, not as
a simulation of some intermediate low-precision format — and only then is
the result rounded to the target precision and, if it falls outside the
representable range, saturated according to the chosen saturation mode. This
holds for a scalar `Add`, for a fused `FMA` (one rounding, not two), and for
a full `BlockDotProduct` (every lane product and the accumulation exact,
projected once at the end). There is no second path that skips a step or
rounds twice; every code point the package ever produces came out of this
same pipeline.

The consequence worth sitting with: there is no accumulated rounding error
*inside* an operation. Rounding error exists only at the single boundary
where the exact result crosses into a code point — never before it.

## What "exact" means, per carrier

"Exact math" has to happen somewhere concrete, and the carrier it happens on
depends on the format. `decode(x)` always returns the format's exact datum,
never a rounded approximation of it — but the *type* it returns is a
property of the format, not a package-wide constant.

For 432 of the 504 formats, the datum's exponent range fits inside a
`Float64`, so `decode` returns a `Float64` and the exact arithmetic runs
there. For the other 72 — formats whose exponent range or precision a
`Float64` cannot hold without rounding — `decode` returns `Float128` or an
exact dyadic carrier instead, so no precision is lost representing the
datum in the first place. `datumcarrier(T)` names which carrier a given
format uses, and it is this carrier, not `Float64` universally, that the
exact-math half of the pipeline runs on.

This distinction matters because `Float64(x)` always returns a `Float64`
regardless of the format's own carrier, and rounds wherever the datum does
not fit — it is a display/interop convenience, not the internal computation
path. At the user level, `promotecarrier(T)` names the *promotion* carrier —
`Float64` for the 432 formats at the ordinary rung, `BigFloat` for the other
72 — which is the type an operation between a `Binary` value and an ordinary
number lands in.

## Symbolic sticky: projecting "just below" a number

Some values are not just numbers — they are the limit of a sequence
approaching a number from one side, and a directed rounding mode needs to
know which side to land the projection on. `tanh` approaching 1 as its
argument grows is the canonical case: the exact mathematical limit is 1, but
`tanh(x) < 1` for every finite `x`, so a correct projection under
`TowardNegative` must round *down from* 1, not treat 1 as an ordinary
carrier value sitting exactly on a code point.

The engine handles this with a `sticky` argument, `sticky ∈ {-1, 0, +1}`,
meaning "the true value is the carrier value plus an infinitesimal of this
sign." This lets `project` land exactly on the correct neighbor for
enclosure endpoints and asymptotes without inventing a fake carrier value
that isn't quite 1:

```julia-repl
julia> using SmallFloats: project

julia> project(Binary8p4se, ProjSpec(TowardNegative(), SatNone()), 1.0; sticky=-1)
Binary8p4se(0.9375 ⇆ 0x3f)     # == NextLessThan(1.0): the engine crossed the binade
```

Read this carefully: the carrier value passed in is `1.0`, exactly
representable in `Binary8p4se`. Without `sticky`, a directed-toward-negative
projection of an exactly-representable value is the identity — it would
return `1.0` unchanged. `sticky=-1` tells the engine that the true value sits
an infinitesimal *below* 1.0, so `TowardNegative` must move to the next
lower code point instead of stopping at 1.0 itself — and it does, crossing
the binade boundary down to `0.9375`, which is exactly `NextLessThan(1.0)`.
This is how the package gets asymptotic behavior like `tanh → 1⁻` exactly
right under every rounding mode, rather than approximately right under most
of them.

## Why `Rational` inputs are refused, not double-rounded

`Convert` accepts `Binary` values of any format, `Float16`/`Float32`/`Float64`,
`Float128`, any `Integer`, and `BigFloat` — every type whose values the
package can project *exactly* onto the carrier it needs. `Float128` in
particular projects directly, preserving all 113 significand bits, which
matters when a value sits just above a rounding midpoint: staging through
`Float64` first would round it onto the midpoint and then break the tie the
wrong way, a genuine double rounding that changes the answer.

`Rational` is conspicuously missing from that list, and that is deliberate
rather than an oversight. A `Rational{Int}` can represent a value that no
supported carrier holds exactly (a denominator that is not a power of two,
for instance), so converting it would require rounding once to reach a
carrier and again to reach the format — silently, with no record of it
having happened. That would put a second, invisible rounding step inside
what looks like a single conversion, which is exactly the guarantee the
one-write-path contract exists to prevent.

So `Convert` refuses `Rational` inputs outright, with an error that tells
you what to do about it: convert explicitly to a supported carrier first
(`Binary8p4se(Float64(π))` for irrational values, or `Binary8p4se(Float64(r))`
for a `Rational` `r`) and thereby own the double rounding as a choice you
made, not a default the package made for you.

## Why the contract is a single, named function

All of this — exact math, rounding, saturation, and the sticky adjustment
for asymptotic limits — lives behind one function, `project`, rather than
being reimplemented at each call site that needs a code point. That
centralization is what makes the "one write path" claim checkable rather
than aspirational: every operation in the package, from a scalar `Add` to a
table build to a block reduction, is required to produce its code point by
calling through `project`, and the test suite is able to assert this because
there is exactly one place the assertion needs to look. A second
hand-rolled rounding step anywhere in the codebase would be a bug by
definition, not a matter of style.

This is also why the table-gather performance strategy described elsewhere
in the documentation costs nothing in correctness. A cached table entry and
a fresh scalar computation are guaranteed identical precisely because both
routes go through `project` — the table is not a separate, hopefully-equivalent
fast path, it is the *same* path, memoized. Nothing about caching results
for speed introduces a second contract to keep in sync with the first.

The same reasoning extends to approximate kernels. When a registered
approximation replaces the default path for one operation, it is measured
against exactly this contract's output — the exact-math-then-project result
— rather than against some looser notion of "close enough." The projection
contract is not just how the default path stays correct; it is also the
fixed reference every deliberate approximation in the package is honestly
scored against.

That is what makes a declared κ a fact about the *difference* between two
functions, rather than a vague impression of "close enough" — both sides of
the comparison ultimately trace back to the same contract this page
describes.

## What this leaves open

The contract fixes *when* rounding happens — once, at the end — and says
nothing about *which way*. That is the projection's job, and it is two
independent choices rather than one: which neighbor a between-grid value lands
on, and what a result beyond the format's range becomes. [Rounding and
Saturation](concept_rounding_saturation.md) takes those two axes in turn and
shows the one case where they interact. Once you can name a policy,
[Control Rounding and Overflow](workflow_rounding_overflow.md) is the
procedure for testing that it does what you expect at the values where the
modes actually disagree.
