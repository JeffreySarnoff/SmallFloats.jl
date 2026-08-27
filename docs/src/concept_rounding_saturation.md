# Rounding and Saturation

A projection answers two independent questions about one exact result.
Rounding: *which neighbor*, when the exact value lies between datums?
Saturation: *what may the result become*, when it lies beyond them or hits a
special boundary case? This page develops each axis separately, then the one
place they interact.

## Projection is a product of policies

```text
exact result → rounding decision → saturation decision → code point
```

SmallFloats represents the pair as `ProjSpec(rounding, saturation)`. A name
like `RNE_SN` is `ProjSpec(NearestTiesToEven(), SatNone())` — a convenient
value, not a fused algorithm. The independence matters in both directions:
changing saturation never changes how an in-range value rounds (`RNE_SN` and
`RNE_SF` agree on every result inside the finite range), while changing
rounding can decide whether the range boundary is even reached — the First
Session's exact product 384 becomes `Inf` under `RNE_SN` but stops at 224
under `RTZ_SN`, because a mode directed toward zero never crosses the
boundary at all.

## Deterministic rounding modes

The deterministic modes answer different questions at the same pair of
neighboring datums:

| Family | Decision |
|:---|:---|
| nearest, ties to even | nearest datum; a tie selects the even code lattice choice |
| nearest, ties away | nearest datum; a tie increases magnitude |
| toward positive | least representable datum not below the exact value |
| toward negative | greatest representable datum not above the exact value |
| toward zero | neighbor no farther from zero |
| to odd | select the odd endpoint when discarded information is nonzero |

Directed rounding describes order, not simply “up” or “down” in magnitude.
For a negative exact value, toward positive moves toward zero while toward
negative moves away from zero.

## Stochastic rounding modes

Stochastic modes make the landing a function of the exact fractional position
and a finite random draw. The distribution is part of the mode's definition.
Project 2 + 3/64 into `Binary8p4se` under `RSA_SN(4)`: the value sits three
sixteenths of the way from 2.0 to the next datum, 2.25, and exactly 3 of the
16 possible draws round upward. The landing probability equals the fractional
position. With an explicit draw `R` the projection is deterministic, so the
whole distribution can be tested one draw at a time.

The mode's random-bit budget determines the draw range. An `N`-bit mode accepts
`R ∈ 0:(2^N - 1)`; out-of-range draws are contract violations rather than
silently wrapped values.

## Saturation modes

`SatFinite` clamps results to the finite range. `SatPropagate` preserves
representable infinities under its contract and handles other overflow by its
policy. `SatNone` applies the draft's full domain-, sign-, direction-, and
operation-dependent rows.

The name `SatNone` is easy to misread. It does not mean “do nothing” and it
does not mean “never saturate.” It means neither simplifying policy was
selected.

## Rounding and range interact

An exact positive result beyond the largest finite datum is not yet an
overflow. `RoundToPrecision` runs first and knows nothing about range — it
rounds to the target precision and leaves 384 at 384. Saturation then
classifies the out-of-range result *with the rounding mode passed in*: under
`RNE_SN` the draft's rows send 384 to `Inf`, while under `RTZ_SN` the
toward-zero direction forces the finite extreme, 224. Two specs with the same
saturation mode, different boundary outcomes — and saturation itself never
rounds; it only consults the direction.

This is why the package projects once through a combined spec rather than
rounding in one call and clamping in another. Separating them operationally
would introduce an extra representable intermediate and could change the
defined result.

## Construction, conversion, and operations share projection

`T(x)`, `Convert(T, ρ, x)`, and `Op(T, ρ, operands...)` all end at the same
projection engine. Their difference is how the exact input to projection is
obtained and whether the policy is implicit or explicit.

That shared path supports a useful reasoning rule: once you know the exact
mathematical value and the `ProjSpec`, you can reason about construction,
conversion, scalar operations, and array table entries in the same way.

## Consequences for users

- Name `ρ` in reusable numerical code.
- Test ties and both signs when selecting a rounding policy.
- Test both range boundaries and special values when selecting saturation.
- Record stochastic bit budget and entropy source.
- Do not emulate a spec with a sequence of Base rounding and clamp calls.

## What this leaves open

Knowing what the two axes decide is not yet knowing that your choice is
right: a single test value cannot distinguish the two nearest modes, and a
positive one cannot distinguish toward-zero from toward-negative.
[Control Rounding and Overflow](workflow_rounding_overflow.md) is the
procedure — which cases to test, and why one value is never enough. If your
policy is stochastic, its result varies by design, and pinning that variation
so a run is reproducible is [Make Stochastic Work
Reproducible](workflow_stochastic.md). For the complete grid of predefined
names, [Projection Specifications](reference_projections.md).
