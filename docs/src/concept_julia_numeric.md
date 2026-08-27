# Julia Numeric Behavior

Mixing two `Binary` formats in an arithmetic expression fails. Mixing a
`Binary` value with an ordinary Julia number succeeds, but the result is not
a `Binary` value. Both behaviors are deliberate, and this page explains the
reasoning behind each, along with why the obvious third option — a
`promote_rule` that produces a wider `Binary` format automatically — was
considered and rejected.

## Mixed `Binary` formats: deliberate failure, not silent widening

Adding two values from different formats does not silently pick a format
wide enough to hold both and round into it. It fails, with an error that
names the problem:

```julia-repl
julia> x = Binary8p4se(1.5);

julia> x + Convert(Binary8p4se, RNE_SN, Binary5p3sf(1.0))
Binary8p4se(2.5 ⇆ 0x4a)
```

The line above only works because the `Binary5p3sf` value was converted
*explicitly* first. Without that conversion, `x + y` for `x::Binary8p4se`
and `y::Binary5p3sf` raises a `promotion ... failed to change` error rather
than silently choosing some third format to compute in. This is not a gap in
the promotion machinery — it's the package's stated position that mixing
formats is a decision the caller makes explicitly, with `Convert`, never one
the package makes for you by picking a resolution.

## `Binary` with ordinary numbers: promotes to the promotion carrier

Combining a `Binary` value with an ordinary Julia number — an `Int`, a
`Float64` — does not fail, but it does not produce a `Binary` value either.
It promotes to the format's **promotion carrier**, an ordinary float type,
and the result is that ordinary float:

```julia-repl
julia> x + 2.0
3.5
```

For 432 of the 504 formats — the ones whose exponent range and precision fit
inside a `Float64` without rounding — that carrier is `Float64`, which is
what the example above returns. For the other 72, the carrier is `BigFloat`:
a `Float64` cannot hold a `Binary16p1uf` datum exactly, and promoting into
`Float64` anyway would silently turn a perfectly finite value into `±Inf`
with no P3109 operation anywhere in sight. `promotecarrier(T)` names the
target carrier for any format, so the promotion is queryable rather than a
fact you have to remember.

If you actually want the result back in the original format, project it
back explicitly — the package will not do this step for you, for the same
reason it won't guess which format to promote two mixed `Binary` values
into:

```julia
Convert(Binary8p4se, RNE_SN, decode(x) + 2.0)
```

## Why widen is not another format

It's tempting to think the fix for mixed-format arithmetic is obvious:
define a `promote_rule` between two `Binary` types that picks the smallest
format containing both operands' datum sets, the way `promote_type(Int,
Float64)` picks `Float64`. A companion internal study worked this out in
detail, and the answer is that this rule cannot be built soundly. Formats
trade precision for range inside a fixed bit budget — raising precision by
one bit necessarily removes an exponent bit — so two formats at the same
bitwidth are usually *incomparable*: neither
contains the other's datum set. Measured over the full 504-format grid, a
"smallest format containing both" answer exists for only about 60% of
format pairs; the other 40% have no common format at all within the K ≤ 16
grid, so any `Binary`-valued rule would have to fall back to something else
for those pairs anyway.

Worse, even where the smallest containing format does exist, picking it
pairwise is not associative — because Julia's `promote_type(a, b, c)`
reduces pairwise, a non-associative rule would make the *result format*
depend on the order the operands happened to appear in a `+` chain, which is
exactly the kind of instability the package refuses to ship. And even in the
cases where the rule is well-defined, it is often surprising on its own
terms: two formats that agree on everything except whether they carry
infinities do not promote to either input's own bitwidth — they need one bit
more, because the wider format has to hold both the finite format's largest
value *and* an infinity code point, and at the narrower width there is no
code point left for both. A silent promotion landing in a format the user
never named, at a width neither operand has, is the wrong kind of
convenience for a package whose entire premise is that you choose your
result format. The full argument, with the exact percentages and the
associativity counterexample, is worked out in the promotion-rules study
(docs/other/promoterules.md in the repository).

## Why this differs from `Int`/`Float64` promotion

It helps to be precise about what makes format promotion a different
problem from ordinary numeric promotion. `promote_type(Int, Float64)`
works because the target, `Float64`, is fixed in advance and holds every
`Int` exactly (up to 2^53) — the rule never has to ask "which format
contains both operands" because there is only one plausible answer and it
never runs out of room. Two `Binary` formats have no such fixed universal
target: the format space is a lattice of finite datum sets, not a single
always-sufficient supertype, and which format contains which shifts with
every combination of precision, range, signedness, and domain. The
question `promote_type` answers for ordinary numbers is trivial; the same
question for two arbitrary `Binary` formats is a genuine combinatorial
problem, and the promotion-rules study exists because that problem was
worked out in full rather than assumed away.

## Explicit `Convert` as the answer

Given that no automatic rule is both sound and predictable, the package's
answer is to make the choice explicit every time: `Convert(T, ρ, x)` moves
any value into the format `T` you name, under the projection `ρ` you choose.
There is no ambiguity about which format the computation happens in, no
order-dependence, and no case where the rule silently falls back to a
carrier for some inputs and a `Binary` format for others. The lattice of
which format contains which is real and occasionally useful to know
explicitly, but it belongs in a query you call when you want the answer, not
in an operator that decides for you every time two formats meet.

This is the same philosophy that governs every other write path in the
package: one explicit projection, chosen by the caller, rather than a rule
that infers intent from context. A `promote_rule` between two `Binary`
formats would be exactly the kind of implicit rounding decision the rest of
the design goes out of its way to avoid — it would round somewhere other
than inside `project`, which is the one invariant the whole package is built
not to break. Treating cross-format arithmetic as a decision you make
explicitly, rather than a convenience the library infers, is not a
limitation bolted on around an otherwise-automatic feature; it is the same
rule that governs rounding modes, saturation modes, and result formats
applied consistently to one more place where an implicit choice could have
hidden.

## What this buys you as a caller

The practical upshot is that a `Binary` expression never surprises you
about which format it computed in. If every operand in an expression shares
a format, the result is that format, under whatever projection was in play.
If you mix in an ordinary number, the result predictably drops to the
promotion carrier, and you can query `promotecarrier(T)` in advance to know
which carrier that will be. And if you try to mix two different `Binary`
formats without converting, the error fires immediately rather than letting
a silently-widened result propagate three functions deeper before something
notices the format changed. All three outcomes are things you can predict
from the types alone, before running anything — which is the actual goal a
promotion rule is supposed to serve, achieved here by refusing the one case
that could not serve it honestly.

## See also

[Values, Code Points, and Conversion](concept_values_codepoints.md) gives the
constructor and `Convert` rules. [Julia Compatibility Register](reference_julia_compat.md)
lists the complete Base surface.
