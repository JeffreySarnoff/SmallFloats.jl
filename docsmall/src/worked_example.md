# A Worked Example

The preceding chapters in one task: choose a format for real data, quantize,
measure what the choice cost, and record what produced the numbers. The
pattern transfers directly to model weights, activations, or any signal.

## The data, and an explicit policy

A fixed seed makes the session reproducible; `RNE_SF` — nearest, ties to
even, clamp to finite — is named once and used throughout, so the report
stays meaningful even if a session default changes elsewhere:

```julia
using SmallFloats, Random, Statistics

rng = Xoshiro(42)
w = randn(rng, 50_000) .* 0.25        # a typical trained-weight scale
```

## Measure, with three numbers

One number is not enough evidence for a quantization choice. Aggregate error
can look fine while single values are badly wrong, and both can look fine
while the tails overflow. Report all three:

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

```
(format = :Binary8p4se, rmse = 0.0066, max_error = 0.0622,
 nonfinite_rate = 0.0, boundary_rate = 0.0)
```

Average damage is small, the worst single value is off by ten times the
average, and nothing overflowed — for this sample, range was never the
binding constraint.

## Compare candidates under one policy

Same sample, same projection, four formats — never change the data and the
policy in the same experiment:

```julia
for F in (Binary8p5se, Binary8p4se, Binary8p3se, Binary8p2se)
    r = quantization_report(F, w)
    println(rpad(String(r.format), 12), " rmse=", round(r.rmse; sigdigits=3),
            "  max=", round(r.max_error; sigdigits=3),
            "  nonfinite=", r.nonfinite_rate, "  boundary=", r.boundary_rate)
end
```

```
Binary8p5se  rmse=0.00356  max=0.0256  nonfinite=0.0  boundary=0.0
Binary8p4se  rmse=0.00662  max=0.0622  nonfinite=0.0  boundary=0.0
Binary8p3se  rmse=0.0132   max=0.0881  nonfinite=0.0  boundary=0.0
Binary8p2se  rmse=0.0261   max=0.162   nonfinite=0.0  boundary=0.0
```

RMSE roughly doubles per significand bit given up, exactly as the datum
spacing does. Every format holds this data without overflow, so the range
the lower-precision formats offer goes unused and `Binary8p5se` wins
outright. On wider-spread data the last two columns stop reading zero and
the ranking changes — which is what they are there to catch.

## Inspect the worst misses

```julia
q = [Convert(Binary8p4se, RNE_SF, x) for x in w]
err = abs.(w .- decode.(q))
worst = partialsortperm(err, 1:3; rev = true)
[(w[i], decode(q[i]), err[i]) for i in worst]
```

```
(-1.06279, -1.125, 0.06221)
(-1.06092, -1.0,   0.06092)
(-1.06967, -1.125, 0.05533)
```

The worst errors cluster just past 1.0, where `Binary8p4se`'s spacing widens
to 0.125 at the binade boundary — a structural property of the format, not
an unlucky sample. Knowing where the errors live says whether a different
format would help or the data needs rescaling. If failures cluster by row or
channel scale instead, use a block scale (see
[Data at Scale](data.md)).

## Record what produced the result

```julia
d = conformance_dict()          # formats, operations, specializations, approximations
rev = draft_revision()          # "IEEE P3109/D1, uploaded 2026-07-17"
```

Serialize `d` with any JSON or TOML writer and store it, the draft revision,
the chosen format, the projection name, and the seed beside the quantized
artifact. A later reader can then reproduce the numbers or explain a
difference without guessing what the session looked like.

## Next

[Assurance](assurance.md) covers the record-keeping used above in full: the
provenance test, measured approximation, and how the defined path itself is
verified.
