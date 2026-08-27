# Defined, Stochastic, and Approximate Results

Two runs disagree — is that a defect? Three reasons are legitimate: the policy
changed, the policy itself requests randomness, or a named approximation was
selected. Anything else is a defect. The provenance test at the end of this
page decides which case you are in.

## Defined result

A defined result is the value required by the selected operation, result
format, and projection specification. For a deterministic spec, the same
inputs always produce the same code point.

```julia-repl
julia> x, y = Binary8p4se(1.625), Binary8p4se(1.75);

julia> Add(Binary8p4se, RNE_SN, x, y)
Binary8p4se(3.5 ⇆ 0x4e)
```

The exact sum is 3.375. `RNE_SN` determines the one permitted landing. The
scalar path, array path, and any cached function table must agree on code point
`0x4e`.

## Stochastic defined result

A stochastic projection is still defined. Its additional input is a random
draw. Once that draw is fixed, the result is deterministic and testable.

```julia
σ = RSA_SN(4)
x = 2.0 + 3/64
[codepoint(SmallFloats.project(Binary8p4se, σ, x; R)) for R in 0:15]
```

For this value, exactly 3 of the 16 draws round upward. The distribution is
part of the stochastic mode's contract. Passing an explicit `R` tests one
point in that contract; passing a seeded RNG reproduces a stream of draws.

The result varies because policy requests variation, not because the
implementation is imprecise.

## Approximate result

An approximate result comes from an implementation registered as intentionally
different from the defined operation. It is reachable only by name through the
approximation registry.

The registry records κ, the maximum distance in code points between the
approximate and defined results over the measured input domain. Registration
measures that distance and rejects a claimed bound that is too small.

```julia
κ, exhaustive = measure_kappa(candidate, :Tanh, Binary8p4se,
                              (Binary8p4se,), RNE_SN)
register_approx!(:fast_tanh, :Tanh, Binary8p4se,
                 (Binary8p4se,), RNE_SN, candidate; κ)
```

The pair `(κ, exhaustive)` matters. κ says how far the implementation moved;
the Boolean says whether the measurement covered the complete finite input
space.

## The provenance test

When two runs differ, ask these questions in order:

1. Did the operation, result format, or projection specification change?
2. Is the projection stochastic, and did the draw or RNG stream change?
3. Did the call explicitly select a registered approximation?
4. Did process-global defaults change between calls?

If all answers are no, a changed code point is a defect. This decision rule is
more useful than treating every difference as “floating-point noise.”

## Consequences for experiments

- Record the result format and projection spec with an experiment.
- Record the RNG algorithm and seed for stochastic work.
- Record approximation name, declared κ, measured κ, and whether measurement
  was exhaustive.
- Export `conformance_dict()` with artifacts that need an auditable numerical
  contract.
- Compare code points when verifying conformance; compare decoded application
  metrics when evaluating usefulness. They answer different questions.

## Use it

[Make Stochastic Work Reproducible](workflow_stochastic.md),
[Register an Approximation](workflow_approximation.md), and
[Read and Export Conformance](workflow_conformance.md).

## See also

[Projection Specifications](reference_projections.md) and
[Conformance and Approximation Registry](reference_conformance.md).
