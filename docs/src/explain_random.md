# Random Values: What the Draws Mean

`rand` and `randn` work on every SmallFloats format, in every setup a Julia
programmer already expects — implicit RNG, explicit RNG, arrays, in-place
fills, and a choice of projection. This page explains what the draws
actually mean statistically, since a floor-projected uniform and a
nearest-projected normal are subtly different guarantees, and why that
difference is the right default for each.

## What the draws mean

**`rand`** draws the real uniform distribution on `[0, 1)` at `Float64`
precision and *floor*-projects it onto the format's grid. Floor-projection
means each code point receives exactly the real measure of its interval —
the code point representing `0.25` gets drawn with probability proportional
to the width of the half-open interval it floor-covers, not the width
implied by rounding to nearest. This is what makes `rand` a correct discrete
approximation of the continuous uniform distribution rather than an
approximation biased toward the interval midpoints. The result is always in
`[0, 1)`; it never reaches `1.0`, matching the half-open convention every
other Julia numeric type uses for `rand`.

**`randn`** projects a standard-normal `Float64` draw round-to-nearest, and
combines that with `SatFinite` saturation. Rounding to nearest is the
natural choice for a normal draw, since there is no asymmetric floor/ceiling
convention to preserve the way there is for a uniform distribution. The
`SatFinite` half of the pairing matters more than it might look: tail draws
that land beyond `MaxFiniteOf(T)` clamp to the extremal finite datum rather
than escaping to `Inf` or `NaN`. `randn` never returns `±Inf` or `NaN` — a
guarantee that matters most for the smallest formats, where the finite range
is narrow enough that a naive Gaussian tail draw would routinely overflow.
`Binary3p1se`, for instance, has `MaxFinite = 1.0`; without the clamp, most
`randn` draws from a genuine standard normal would land outside the
format entirely.

`randn` also requires a signed format, since a negative draw is a normal
occurrence, not an edge case, and an unsigned format has nowhere to put one:

```julia-repl
julia> randn(Binary6p3ue)
ERROR: ArgumentError: randn requires a signed format; Binary6p3ue cannot represent negative draws
```

## Setup 1 — quick and implicit

With no RNG argument, draws come from Julia's task-local default generator
(a `Xoshiro`), and `Random.seed!` controls them exactly as it would for any
other numeric type:

```julia-repl
julia> Random.seed!(1234); rand(Binary8p4se)
Binary8p4se(0.3125 ≡ 0x32)

julia> Random.seed!(1234); rand(Binary8p4se)      # same seed, same draw
Binary8p4se(0.3125 ≡ 0x32)
```

## Setup 2 — an explicit RNG stream

Pass any `AbstractRNG` as the first argument for a reproducible stream that
is independent of global task-local state:

```julia-repl
julia> rand(Xoshiro(1), Binary8p4se)
Binary8p4se(0.0703125 ≡ 0x21)

julia> rand(Xoshiro(8), Binary8p4se, 4)
4-element Vector{Binary8p4se}:
 Binary8p4se(0.40625 ≡ 0x35)
 Binary8p4se(0.021484375 ≡ 0x13)
 Binary8p4se(0.75 ≡ 0x3c)
 Binary8p4se(0.28125 ≡ 0x31)
```

## Setup 3 — arrays and in-place

`rand(T, dims...)` and `randn(T, dims...)` build an `Array{T}` directly.
`rand!(A)` and `randn!(A)` fill an existing array in place, which costs one
byte per element at `K ≤ 8` and two above it — cheap enough to preallocate
once and reuse across a hot loop:

```julia-repl
julia> A = Vector{Binary8p4se}(undef, 3); randn!(Xoshiro(2), A)
3-element Vector{Binary8p4se}:
 Binary8p4se(-0.005859375 ≡ 0x86)
 Binary8p4se(1.75 ≡ 0x46)
 Binary8p4se(-1.0 ≡ 0xc0)

julia> randn(Xoshiro(3), Binary8p4se, 2, 3) |> typeof
Matrix{Binary8p4se}
```

Array draws feed directly into the storage layers when packing is the
eventual goal: `PackedVector(rand(Binary4p2se, n))` builds the packed
representation straight from a batch of draws.

## Setup 4 — choosing the projection

The scalar `::Type` forms take a `projection` keyword to land the draw under
any `ProjSpec` other than the defaults:

```julia-repl
julia> rand(Xoshiro(2), Binary8p4se; projection = RTP_SN)    # ceiling
Binary8p4se(0.0029296875 ≡ 0x03)

julia> randn(Xoshiro(6), Binary8p4se; projection = RTZ_SF) # toward zero
Binary8p4se(-1.875 ≡ 0xc7)

julia> rand(Xoshiro(4), Binary8p4se; projection = RSA_SN(8)) # stochastic
Binary8p4se(0.8125 ≡ 0x3d)
```

A stochastic projection draws its random bits from the *same* RNG the value
itself came from, so a seeded stream stays fully reproducible even when the
projection is stochastic. The defaults exist because they are the
contract-keepers: floor for `rand` guarantees the correct measure per code
point, and nearest-plus-`SatFinite` for `randn` guarantees no `±Inf`/`NaN`.
Opting into a different projection can break either guarantee — a ceiling
projection can produce exactly `1.0` from `rand`, and a `SatNone` or
`SatPropagate` projection can let `randn` return `±Inf` or `NaN` from a tail
draw. The array and `!` forms always use the defaults; if you need another
projection applied across an array, draw scalars explicitly:
`[rand(rng, T; projection = ρ) for _ in 1:n]`.

The tail-clamp guarantee is easiest to see on the smallest formats, where
the finite range is narrow enough that the difference between "clamp" and
"overflow" shows up on almost every draw — `Binary3p1se`, with `MaxFinite =
1.0`, is the canonical example, and is worked through with full transcripts
in the Understanding-track random-values walkthrough.

## Why floor for `rand` but nearest for `randn`

The asymmetry between the two default rounding choices is not an
inconsistency — each distribution has a different notion of what a
correct discrete sample means. A uniform distribution on `[0, 1)` assigns
probability mass in direct proportion to interval width, so the only
projection that reproduces the *right* distribution over code points is one
that maps each half-open sub-interval to the code point it floor-covers.
Rounding a uniform draw to the *nearest* code point instead would bias the
result toward interval midpoints, silently distorting the distribution measure.
A normal distribution has no such half-open convention to preserve — nearest
is simply the natural, unbiased choice, and the only extra concern is the
tails, which is where `SatFinite` earns its place in the pairing.

## Why this matters for the smallest formats

The finite range shrinks fast as bitwidth drops, and the safety net
`randn`'s `SatFinite` provides matters most exactly where the range is
tightest. A `Binary8p4se` array of `randn` draws will very rarely reach
`MaxFiniteOf` at all, because the finite range is wide relative to a
standard normal's typical spread. A `Binary3p1se` array is a different
story — with `MaxFinite = 1.0`, a meaningful fraction of an honest standard
normal's mass lies beyond the representable range, and every one of those
draws needs somewhere defined to land. `SatFinite` is what makes "somewhere
defined" mean the extremal finite value rather than `Inf` or `NaN`, so code
that consumes a `Binary3p1se` array of draws never has to check for
non-finite values it did not ask for.

## Go deeper

> Continue with **Random Draws & Reproducibility** (Understanding track) for
> the worked K = 3 tail-clamp comparison and the full set of seeded-stream
> experiments.
