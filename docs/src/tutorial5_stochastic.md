# Tutorial 5: Stochastic Rounding

Tutorial 2 introduced the stochastic families — `StochasticA{N}`,
`StochasticB{N}`, `StochasticC{N}` — and showed one projection pinned exactly
with `R = 0` and `R = 255`. This tutorial builds the full picture: why
stochastic rounding is unbiased in expectation, how to audit that exhaustively
over every draw, how to make a stochastic stream reproducible, and the payoff
— an accumulator that keeps absorbing small updates where nearest rounding
stalls.

## Unbiasedness: nearest is not, stochastic is (on average)

Nearest rounding maps `0.30078125` to `0.3125` in `Binary8p4se` — every single
time. That's a systematic bias of about `+0.0117`. Stochastic rounding gets it
right *on average* instead of every time:

```julia
target = 0.30078125                       # ν = 3/16 of an ulp above 0.296875
σ = RSA_SN(16)                       # StochasticA{16} with SatNone
rng = Xoshiro(1)
m = mean(decode(Convert(Binary8p4se, σ, target; rng)) for _ in 1:200_000)
(decode(Binary8p4se(target)), m)
```

```
(0.3125, 0.300765)                        # RNE result vs stochastic mean ≈ target
```

Over 200,000 draws, the stochastic mean lands within noise of the true target,
`0.30078125` — while the deterministic result is stuck 0.0117 high on every
single call. This is the property that makes stochastic rounding matter for
accumulating many small contributions (gradients, activation statistics) in a
low-precision format.

## The R-sweep: auditing the distribution exactly

Every stochastic projection is a deterministic function of the draw `R`, so
its *distribution* is checkable exactly rather than just approximately by
sampling. For `x = 2 + 3/64` in `Binary8p4se` the fraction above the lower grid
point is `ν = 3/16` of an ulp, so `StochasticA{4}` — a 4-bit budget, 16
possible draws — must round up for exactly 3 of the 16 draws:

```julia
σ4 = RSA_SN(4)                  # ≡ ProjSpec(StochasticA{4}(), SatNone())
x = 2.0 + 3/64
count(decode(SmallFloats.project(Binary8p4se, σ4, x; R)) == 2.25 for R in 0:15)
```

```
3
```

Sweeping `R` over its whole range turns "is my stochastic pipeline unbiased?"
from a statistical question into an exhaustive one — this is the same pattern
the shipped test suite uses to verify every stochastic mode.

## Reproducibility

A stochastic projection needs random bits from somewhere, and you control the
source the same three ways as any other random draw in the package: implicitly
from the task-local RNG, from an explicit `rng` you pass in, or by fixing the
draw `R` itself (as in the sweep above and in Tutorial 2). For a reproducible
*stream* rather than one pinned draw, pass a seeded `rng`:

```julia-repl
julia> σ = RSA_SN();                 # ≡ ProjSpec(StochasticA{8}(), SatNone())

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); rng = Xoshiro(1))
Binary8p4se(2.0 ≡ 0x48)
```

Calling this again with a freshly-seeded `Xoshiro(1)` reproduces exactly the
same result, the same way `Random.seed!` and explicit `AbstractRNG` arguments
work for `rand`/`randn` elsewhere in the package. Prefer a seeded `rng` in
tests and anywhere else you need to replay a run; reach for explicit `R` only
when you need to force one specific draw, as in the sweep above.

The three controls compose the way you'd expect: no `rng` and no `R` draws
from the task-local generator (least reproducible, fine for exploration); an
explicit `rng` pins the whole stream (reproducible across a run, and the
right default for anything you'll re-run); explicit `R` pins one draw
exactly (the right tool for a unit test that checks one specific rounding
outcome). All three reach the same stochastic kernel — only the source of
randomness changes.

## The payoff: swamping and stall

Accumulate 400 gradient-style steps of `0.011` into a `Binary8p3se`
accumulator. Under nearest rounding, once the accumulator's magnitude dwarfs
the increment, every add rounds straight back to the accumulator — it
**stalls**, permanently. Stochastic rounding keeps absorbing the increments in
expectation instead:

```julia
function accumulate_demo(nsteps, g)
    σ = RSA_SN(16)
    rng = Xoshiro(11)
    acc_rne = Binary8p3se(0.0); acc_sto = Binary8p3se(0.0)
    for _ in 1:nsteps
        acc_rne = Add(Binary8p3se, RNE_SN, acc_rne, Convert(Binary8p3se, RNE_SN, g))
        acc_sto = Add(Binary8p3se, σ, acc_sto, Convert(Binary8p3se, σ, g; rng); rng)
    end
    (nsteps * g, decode(acc_rne), decode(acc_sto))
end
accumulate_demo(400, 0.011)
```

```
(4.4, 0.125, 5.0)   # exact sum, RNE accumulator (stalled!), stochastic accumulator
```

The exact sum after 400 steps is 4.4. The nearest-rounding accumulator gets
stuck at 0.125 — once the accumulator reaches a binade where the ulp exceeds
`0.011`, every subsequent `+0.011` rounds back to the same code point, and no
number of further steps will move it. The stochastic accumulator lands on 5.0
on this seed: noisy, but unbiased, and it never permanently stops moving the
way the nearest accumulator does. In practice you keep a wider accumulator
format when you can, and reach for stochastic rounding when you can't.

## Try it

Without running any code: for `StochasticA{N}` with a budget of `N` bits,
about what fraction of an ulp's worth of draws would you expect to round
*down* if the true value sits exactly at `ν = 1/4` of an ulp above the lower
grid point? Use the R-sweep logic above to reason it out, then check against
the pattern in that section.

<details>
<summary>Answer</summary>

By the same exhaustive logic as the `ν = 3/16` sweep above, a value sitting at
`ν = 1/4` of an ulp rounds up on the fraction of draws proportional to `ν`
itself — one quarter of the `2^N` possible draws round up, and the remaining
three quarters round down. `StochasticA` is unbiased precisely because that
fraction always equals `ν`, whatever binade or format you're in.

</details>

Where next: this completes the tutorial sequence. Continue with the
[How-To Guides](howto_choose_format.md); [Format Names & Queries](ref_formats.md)
and [Projection Specifications](ref_projections.md) hold the complete, dry
listings this sequence built intuition for.
