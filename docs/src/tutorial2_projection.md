# Tutorial 2: Projection: Rounding & Saturation

Tutorial 1 covered how a value gets made — `T(x)` projects, `T(c::Unsigned)`
reads a code point, `decode`/`codepoint` round-trip exactly. This tutorial is
about the projection step itself: what the six rounding modes and three
saturation modes do, and how to choose one without leaving a footgun for the
rest of your session.

## One value, every rounding mode

`2.30078125` sits between the `Binary8p4se` grid points 2.25 and 2.5 (ulp =
0.25 in `[2, 4)`). Run it through all six deterministic rounding modes, with
`SatNone`:

```julia
using SmallFloats

for μ in (NearestTiesToEven(), NearestTiesToAway(), TowardPositive(),
          TowardNegative(), TowardZero(), ToOdd())
    v = Convert(Binary8p4se, ProjSpec(μ, SatNone()), 2.30078125)
    println(rpad(string(typeof(μ)), 20), " → ", decode(v))
end
```

```
NearestTiesToEven    → 2.25
NearestTiesToAway    → 2.25
TowardPositive       → 2.5
TowardNegative       → 2.25
TowardZero           → 2.25
ToOdd                → 2.25
```

(`ToOdd` keeps 2.25 because its significand is already odd; try 2.05 to see it
move.)

That loop is the whole rounding half of a `ProjSpec` laid out at once: nearest
(two tie-breaking rules), the two directed-toward-infinity modes, toward zero,
and round-to-odd. Cross those six against the three saturation modes
(`SatFinite`, `SatPropagate`, `SatNone`) and you have the full deterministic
grid — 18 predefined constants, each named `R<mode>_Sat<mode>` (`RNE_SN`,
`RTZ_SF`, and so on), plus three stochastic rounding families layered on top.
`RNE_SN` is the package's default, which is why `+` agreed with
`Add(T, RNE_SN, ...)` in the Quickstart.

## The overflow triptych

Saturation only shows its hand when a result falls outside the format's range.
`Binary8p4se` tops out at `MaxFinite = 224`; multiply 200 by 2 (exact product
400) under three specs:

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)       # overflow → ±Inf
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)     # overflow → MaxFinite
Binary8p4se(224.0 ≡ 0x7e)

julia> Multiply(Binary8p4se, RTZ_SN, w, two)
Binary8p4se(224.0 ≡ 0x7e)   # SatNone + directed-toward-zero clamps finite
```

Read the three rows as two separate axes moving one at a time. Row 1 to row 2
holds rounding fixed (`RNE`) and switches saturation (`SN` → `SF`): same
overflow, but `SatFinite` clamps to the extremal finite value instead of going
to infinity. Row 1 to row 3 holds saturation fixed (`SN`) and switches
rounding (`RNE` → `RTZ`): a directed mode that points *away* from the overflow
lands on the finite extreme even under `SatNone`.

!!! note
    `SatNone` is not "no saturation handling": it is the draft's row set in which
    nearest modes overflow to ±Inf (or NaN for finite formats) while directed modes
    that point away from the overflow clamp to the extremal finite value.

## Session defaults, used safely

Every `ProjSpec` above was named explicitly as the second argument. But `+`,
`exp`, and `T(x)` all read a *session default* instead — `DefaultProjection()`,
which starts at `RNE_SN`. You will often want to explore under a different
default without touching the rest of your session. Do that with
`with_default_projection`, which sets the default for the duration of a block
and restores it afterward, even if the block throws:

```julia
with_default_projection(RTZ_SF) do
    Binary8p4se(1e9)          # clamps, inside this block only
end
```

Outside that block, `DefaultProjection()` is exactly what it was before you
called it. This is the form to reach for by default — `with_default_type` and
`with_default_returntype` follow the same shape for the other two session
defaults.

Sometimes you do want to change the default for the rest of a script or REPL
session — for instance, to make every later construction saturate instead of
overflowing to infinity. That's what `DefaultProjection!` is for, and it comes
with a hazard the safe form above doesn't have:

!!! warning "The session defaults are process-global and they stay set"
    `DefaultProjection!` and its siblings mutate state shared by every module in
    the process. Nothing scopes them for you: set one in a script, a notebook
    cell, or a REPL session and *every* later `T(x::Real)`, `a + b` and `Exp(x)`
    follows it until something sets it back.

If you do call it, restore the default explicitly when you're done:

```julia-repl
julia> x, y = Binary8p4se(200.0), Binary8p4se(2.0);

julia> x * y                              # RNE_SN: overflow → +Inf
Binary8p4se(Inf ≡ 0x7f)

julia> DefaultProjection!(RTZ_SF);

julia> x * y                              # now clamps to MaxFinite
Binary8p4se(224.0 ≡ 0x7e)

julia> DefaultProjection!(RNE_SN)         # restore before moving on — see below
(NearestTiesToEven, SatNone)

julia> Multiply(Binary8p4se, RNE_SN, x, y)   # explicit ρ is unaffected
Binary8p4se(Inf ≡ 0x7f)
```

The last line is the important contrast: naming `ρ` explicitly, as in every
`Op(T, ρ, ...)` call so far, is never affected by the session default in either
direction. The default only governs the convenience forms (`x * y`, bare
`T(x)`, `Exp(x)`).

## First contact with stochastic rounding

Everything above has been deterministic: the same operands under the same
`ProjSpec` always give the same code point. The rounding-mode list also
includes stochastic families — `StochasticA{N}`, `StochasticB{N}`,
`StochasticC{N}` — whose outcome depends on `N` random bits drawn per
projection. You can pin that draw explicitly with the `R` keyword, which makes
a single stochastic projection exactly reproducible:

```julia-repl
julia> σ = RSA_SN();                 # ≡ ProjSpec(StochasticA{8}(), SatNone())

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); rng = Xoshiro(1))
Binary8p4se(2.0 ≡ 0x48)

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 0)
Binary8p4se(2.0 ≡ 0x48)      # smallest draw: rounds down

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 255)
Binary8p4se(2.25 ≡ 0x49)     # largest draw: rounds up
```

The exact fraction here is 1/8 of an ulp, so over all 256 draws exactly 32
round up — `StochasticA` is unbiased in expectation. `R` must lie in
`0:2^N-1`. That's as far as stochastic rounding goes in this tutorial; Tutorial
5 is entirely about it.

## Try it

Using `with_default_projection`, compute `Binary8p4se(1e9)` under `RTP_SF`
(toward positive infinity, clamp to finite) without disturbing the session
default, then confirm the default is still `RNE_SN` afterward.

<details>
<summary>Answer</summary>

```julia
with_default_projection(RTP_SF) do
    Binary8p4se(1e9)
end
```

gives `Binary8p4se(224.0 ≡ 0x7e)` (clamped to `MaxFinite`, since `RTP` points
toward the overflow and `SatFinite` clamps). Immediately after the block,
`DefaultProjection()` is back to `RNE_SN` — the whole point of the combinator
over calling `DefaultProjection!` by hand.

</details>

Where next: [Tutorial 3, Operations & Arrays](tutorial3_arrays.md) builds on the explicit `Op(T, ρ,
...)` shape from this tutorial and extends it to arrays, table-backed kernels,
and sorting. For the complete grid of predefined `ProjSpec` constants, see
[Projection Specifications](ref_projections.md).
