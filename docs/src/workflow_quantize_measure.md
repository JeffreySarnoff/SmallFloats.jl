# Quantize and Measure a Tensor

Use this workflow to compare candidate formats on representative data and
produce the three measurements that should accompany a quantization choice:
root-mean-square error, maximum absolute error, and overflow or clamp rate.

Use a block workflow instead when the data contains groups with very different
scales and one bare element format cannot cover them economically.

## Prepare representative data

A quantizer can look excellent on synthetic unit-scale data and fail on the
tails of a real tensor. Prefer a stable sample from the actual model or signal.
The example uses a fixed seed only to make the documentation reproducible.

```julia
using SmallFloats, Random, Statistics

rng = Xoshiro(42)
w = randn(rng, 50_000) .* 0.25
```

## Project explicitly

Name the projection used for evaluation. `RNE_SF` makes the choice clear:
round to nearest, ties to even, and clamp outside the finite range.

```julia
F = Binary8p4se
q = [Convert(F, RNE_SF, x) for x in w]
back = decode.(q)
```

Using `F.(w)` is shorter and follows the session default. The explicit form is
better in an evaluation because the report remains meaningful if a default
changes elsewhere in the process.

## Measure error and boundary use

```julia
function quantization_report(::Type{F}, x; projection = RNE_SF) where {F}
    q = [Convert(F, projection, xi) for xi in x]
    y = decode.(q)
    finite = isfinite.(y)
    (
        format = formatname(F),
        rmse = sqrt(mean((x[finite] .- y[finite]).^2)),
        max_error = maximum(abs.(x[finite] .- y[finite])),
        nonfinite_rate = count(!isfinite, y) / length(y),
        boundary_rate = count(v -> abs(v) == decode(MaxFiniteOf(F)), y) / length(y),
    )
end

quantization_report(Binary8p4se, w)
```

RMSE describes aggregate damage. Maximum error catches a bad local miss.
Nonfinite and boundary rates reveal a range problem that an average can hide.
Under `SatFinite`, overflow becomes an extremal finite value rather than `Inf`,
so the boundary rate is the relevant companion metric.

## Compare candidates under the same policy

```julia
reports = [quantization_report(F, w) for F in
           (Binary8p5se, Binary8p4se, Binary8p3se, Binary8p2se)]
```

At fixed bitwidth, increasing `P` improves local resolution and reduces
exponent range. Compare formats on the same sample and projection. Do not mix a
format decision with a saturation-policy change in the same experiment.

Choose the narrowest format that satisfies an application threshold for all
reported metrics. Record the selected format and projection with the model or
dataset artifact.

## Validate the choice on held-out data

Repeat the report on data that did not participate in the choice. Also inspect
the worst few errors:

```julia
r = quantization_report(Binary8p4se, w)
q = [Convert(Binary8p4se, RNE_SF, x) for x in w]
err = abs.(w .- decode.(q))
worst = partialsortperm(err, 1:10; rev = true)
[(w[i], decode(q[i]), err[i]) for i in worst]
```

A satisfactory average does not excuse systematic failure on rare but
important values. If failures cluster by row or channel scale, move to
[Use Blocks for Dynamic Range](workflow_blocks.md).

## What can go wrong

!!! warning "MSE can hide the tail"
    Always report maximum error and boundary/nonfinite rate. A few saturated
    values can matter greatly while barely moving a global mean.

!!! warning "The constructor hides policy"
    `F.(x)` is valid, but it uses the current default projection. Use
    `Convert(F, ρ, x)` in experiments whose policy must be recorded.

!!! note "Packing is a later decision"
    First choose and validate the numerical format. Pack the resulting code
    points only after that choice; packing changes storage, not quantization.

## Next

[Pack Values for Storage](workflow_packed_storage.md) or
[Use Blocks for Dynamic Range](workflow_blocks.md).

## Understand it

[Format Anatomy](concept_format_anatomy.md) and
[Rounding and Saturation](concept_rounding_saturation.md).
