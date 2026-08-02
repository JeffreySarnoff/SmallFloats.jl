# Rounding and Saturation

A projection answers two independent questions. Rounding chooses a neighbor
when an exact value lies between datums. Saturation chooses the permitted
result when the rounded value lies outside the format's range or belongs to a
special boundary case.

## Projection is a product of policies

```text
exact result → rounding decision → saturation decision → code point
```

SmallFloats represents the pair as `ProjSpec(rounding, saturation)`. Names such
as `RNE_SN` are convenient values, not fused algorithms. The independence is
important: changing saturation must not silently change how in-range values
round, and changing rounding can alter which side of a boundary is reached.

## Deterministic rounding modes

The deterministic modes answer different questions at the same pair of
neighboring datums:

| Family | Decision |
|---|---|
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

Stochastic modes make the landing a function of both the exact fractional
position and a finite random draw. They are defined distributions. With an
explicit draw `R`, a stochastic projection is deterministic and can be tested
exhaustively.

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

Suppose an exact positive result lies just beyond the largest finite datum.
Toward zero may land back on that finite datum before saturation classifies the
result, while nearest may cross into overflow. Consequently two specs with the
same saturation mode can produce different boundary outcomes.

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

## Use it

[Control Rounding and Overflow](workflow_rounding_overflow.md) and
[Make Stochastic Work Reproducible](workflow_stochastic.md).

## Look it up

[Projection Specifications](reference_projections.md).
