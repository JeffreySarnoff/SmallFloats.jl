# Choose a Format

Pick a `Binary{K,P,SGN,EXT}` format that fits a specific tensor, signal, or quantity.

## Ingredients

- A sample of the data (or a plausible generator for it) so you can measure damage
  before committing.
- `formatname`, `MaxFiniteOf`, `decode` for inspecting candidates.
- `RNE_SF` (or another `ProjSpec`) to project a sample through each candidate.

## Recipe

**1. Enumerate the format before committing.** Small formats are small enough to
look at in full. Sorting `Binary4p2se`'s 16 code points shows the subnormal
spacing, the binade structure, and the dynamic range in one line:

```julia
decode.(sort(Binary4p2se.(0x00:0x0f)))
```

```
[-Inf, -2.0, -1.5, -1.0, -0.75, -0.5, -0.25, 0.0,
  0.25, 0.5, 0.75, 1.0, 1.5, 2.0, Inf, NaN]
```

**2. At fixed bitwidth, precision trades against range.** For a unit-scale
Gaussian tensor, RMSE roughly doubles per lost significand bit while
`MaxFinite` grows explosively — spend bits on precision unless the data's
magnitude actually needs the range:

```julia
rng = Xoshiro(7); x = randn(rng, 50_000)
for F in (Binary8p5se, Binary8p4se, Binary8p3se, Binary8p2se)
    back = [decode(Convert(F, RNE_SF, xi)) for xi in x]
    println(rpad(formatname(F), 12), " rmse = ", round(sqrt(mean((x .- back).^2)); sigdigits=3),
            "   maxfinite = ", decode(MaxFiniteOf(F)))
end
```

```
Binary8p5se  rmse = 0.0133   maxfinite = 15.0
Binary8p4se  rmse = 0.0266   maxfinite = 224.0
Binary8p3se  rmse = 0.0528   maxfinite = 49152.0
Binary8p2se  rmse = 0.103    maxfinite = 2.147483648e9
```

If your data's dynamic range genuinely exceeds one binade's reach at your
precision budget, don't buy that range with a wider element — get it from a
block scale instead.

**3. Bounded-in-[0,1] quantities want unsigned.** A membership degree, a
probability, a normalized score — anything that is never negative — is a job
for an unsigned finite format, not a signed one spending a code on a sign it
never uses. `Binary8p6uf` gives a [0, 15.5] range at 1/32 resolution near 1:

```julia
F = Binary8p6uf
membership(x, a, b, c, d) = clamp(min((x - a) / (b - a), 1.0, (d - x) / (d - c)), 0.0, 1.0)
warm = F(membership(26.0, 15, 20, 24, 28))   # membership of 26 °C in "warm"
hot  = F(membership(26.0, 24, 30, 100, 101)) # … and in "hot"

(decode(warm), decode(hot),
 decode(Minimum(F, RNE_SN, warm, hot)),      # warm AND hot
 decode(Maximum(F, RNE_SN, warm, hot)),      # warm OR hot
 decode(Multiply(F, RNE_SF, warm, hot)))   # product t-norm
```

```
(0.5, 0.3359375, 0.3359375, 0.5, 0.16796875)
```

**4. Pick finite (`f`) when `Inf` would be meaningless.** If nothing in your
domain should ever legitimately produce or consume an infinity — a scale
factor, a bounded score, a probability-like quantity — a finite-domain format
spends the code points IEEE-style formats give to ±Inf on two more finite
datums instead. Reach for `e` (extended) only when overflow-to-infinity is a
real outcome you want to detect downstream.

!!! warning "An unsigned format is not free precision"
    Going unsigned doubles your positive-side resolution only if the quantity
    truly never needs a sign. Do not use an unsigned format for anything that
    can legitimately go negative (gradients, residuals, log-odds) — projecting
    a negative `Real` into an unsigned format is not a sign flip, it is a
    domain violation and produces a different failure than you likely intend.
    Reach for the fuzzy-inference example above only when the quantity is
    already bounded in `[0, ∞)` by construction.

## What can go wrong

!!! warning "Enumeration intuition does not scale past small K"
    `decode.(sort(F.(0x00:...)))` is a genuine format-choice tool for `K` small
    enough to print — beyond roughly `K = 8` the code-point space is too large
    to eyeball, so switch to the RMSE/MaxFinite sweep instead.

!!! note "RMSE alone hides overflow"
    A format can have a low RMSE on the bulk of your data and still overflow
    its tails to `Inf`. Always check `count(isinf, back) / length(back)`
    alongside RMSE and max error — see Quantize a Tensor or Model for
    the full three-number check.

## see also

[Quantize a Tensor or Model](howto_quantize_tensor.md),
[Use Blocks to Track Dynamic Range](howto_blocks_dynamic_range.md).
