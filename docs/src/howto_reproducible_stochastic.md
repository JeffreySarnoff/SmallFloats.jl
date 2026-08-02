# How-To: Get Reproducible Stochastic Results

Make stochastic-rounding code reproducible — across runs, and inside test
suites — by fixing the entropy source.

## Ingredients

- An explicit `AbstractRNG` (e.g. `Xoshiro(seed)`) passed as `rng`.
- An explicit `R` (the raw stochastic draw) for tests that must be
  bit-exact.
- `DefaultRNG!` if you want the implicit (no-`rng`-argument) forms to be
  reproducible too.
- The `projection` keyword on scalar `rand`/`randn` forms.

## Recipe

**1. Prefer an explicit rng stream over the task-local default.** Passing any
`AbstractRNG` first gives a stream independent of global state:

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

If you rely on the implicit task-local generator instead, `Random.seed!`
controls it exactly as for any other type:

```julia-repl
julia> Random.seed!(1234); rand(Binary8p4se)
Binary8p4se(0.3125 ≡ 0x32)

julia> Random.seed!(1234); rand(Binary8p4se)      # same seed, same draw
Binary8p4se(0.3125 ≡ 0x32)
```

**2. A stochastic projection draws from the same rng as the value draw.**
One underlying `Float64` draw, landed on the grid four different ways — the
seed fixes the draw, the projection decides the landing:

```julia-repl
julia> rand(Xoshiro(2), Float64)                # the underlying uniform draw
0.0022505868897625403

julia> rand(Xoshiro(2), Binary8p4se)            # default: floor (stays in [0,1))
Binary8p4se(0.001953125 ≡ 0x02)

julia> rand(Xoshiro(2), Binary8p4se; projection = RTP_SN)   # ceiling
Binary8p4se(0.0029296875 ≡ 0x03)

julia> rand(Xoshiro(2), Binary8p4se; projection = RNE_SN)   # nearest
Binary8p4se(0.001953125 ≡ 0x02)

julia> rand(Xoshiro(2), Binary8p4se; projection = RSA_SN(8))  # stochastic
Binary8p4se(0.001953125 ≡ 0x02)
```

Because the stochastic projection draws its random bits from the *same* rng
as the uniform draw, seeded streams stay reproducible end to end — you do not
need a second seed for the rounding decision.

**3. For a test, fix the raw draw `R` instead of an rng.** This makes a single
projection exactly reproducible without depending on an RNG's internal
algorithm at all — the right tool when you want to test both edges of a
stochastic rounding decision deterministically:

```julia-repl
julia> σ = RSA_SN();                 # ≡ ProjSpec(StochasticA{8}(), SatNone())

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); rng = Xoshiro(1))
Binary8p4se(2.0 ≡ 0x48)

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 0)
Binary8p4se(2.0 ≡ 0x48)      # smallest draw: rounds down

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 255)
Binary8p4se(2.25 ≡ 0x49)     # largest draw: rounds up
```

**4. Set `DefaultRNG!` if you want implicit calls to be reproducible too.**
`DefaultRNG` is one of the six session defaults (initial value: the `Xoshiro`
type); set it once at the top of a script or test file if you want every
call that doesn't name an rng to still be controlled by your seed.

## What can go wrong

!!! warning "Array and `!` forms always use the defaults"
    `rand(T, dims)`, `randn!(A)`, and friends always use the default
    projection (floor for `rand`, nearest + `SatFinite` for `randn`) — there
    is no `projection` keyword on the array forms. For arrays under another
    projection, draw scalars explicitly:
    `[rand(rng, T; projection = ρ) for _ in 1:n]`.

!!! note "R must lie in `0:2^N-1`"
    For an `N`-bit stochastic mode, an out-of-range explicit `R` is a
    contract violation, not a silently wrapped value — pick `R` from the
    mode's actual bit budget (`RSA_SN(8)` takes `R ∈ 0:255`).

!!! warning "Nearest/ceiling can return exactly 1.0 from `rand`"
    The default floor projection is the contract-keeper for `rand`: it
    guarantees results stay in `[0, 1)`. Opting into `RTP_SN` or `RNE_SN` can
    return exactly `1.0` (mass near the top rounds up) — only opt out of the
    default if your code can tolerate that.

## Where next

[How-To: Choose a Format](howto_choose_format.md)
[How-To: Quantize a Tensor or Model](howto_quantize_tensor.md)
