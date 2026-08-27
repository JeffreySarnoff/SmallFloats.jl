# Julia Compatibility Register

`Binary` values speak ordinary Julia. The **Base register**
(`src/juliacompat.jl`) maps every draft operation that has a Base counterpart
onto its Base name, so generic Julia code — and your fingers — can use the
spellings they already know. Every method there is exactly one same-format
spec-register call under the session default projection; there is no third
semantics: `x + y` *is* `Add(x, y)`, which *is*
`Add(T, DefaultProjection(), x, y)`.

## Using the overloads

```julia-repl
julia> x, y, z = Binary8p4se(1.6), Binary8p4se(0.25), Binary8p4se(2.0);

julia> x + y                       # Add
Binary8p4se(1.875 ⇆ 0x47)

julia> exp(y)                      # Exp — a 256-byte table lookup once warm
Binary8p4se(1.25 ⇆ 0x42)

julia> atan(y, x)                  # ArcTan2, in Base's (y, x) argument order
Binary8p4se(0.15625 ⇆ 0x2a)

julia> fma(x, y, z)                # FMA — one rounding; muladd is the same op
Binary8p4se(2.5 ⇆ 0x4a)

julia> sincos(y)                   # composite: (Sin(y), Cos(y)) componentwise
(Binary8p4se(0.25 ⇆ 0x30), Binary8p4se(1.0 ⇆ 0x40))
```

Because the veneers follow the session default projection, changing it changes
them (see [Session Defaults](concept_session_state.md)):

```julia-repl
julia> Binary8p4se(200.0) * Binary8p4se(2.0)     # RNE_SN: overflow → Inf
Binary8p4se(Inf ⇆ 0x7f)

julia> DefaultProjection!(RTZ_SF);

julia> Binary8p4se(200.0) * Binary8p4se(2.0)     # now clamps to MaxFinite
Binary8p4se(224.0 ⇆ 0x7e)

julia> DefaultProjection!(RNE_SN)                # restore: this setter is PROCESS-wide
(NearestTiesToEven, SatNone)
```

Code that must be insensitive to the session default names its projection:
`Multiply(T, RNE_SN, x, y)`.

!!! warning "Restore what you set"
    `DefaultProjection!` mutates state shared by every module in the process, and
    nothing scopes it for you — it changes `T(x::Real)` construction too, so a
    later `Binary8p4se(1.1)` would truncate rather than round to nearest. The
    `with_default_projection` combinator reads the configured projection; it
    does not scope mutation. Prefer explicit forms such as
    `Convert(T, ρ, x)` in library code. Every example after this point assumes the pristine
    `(NearestTiesToEven, SatNone)`, which is why the demonstration above puts it
    back.

## The mapping

| Base spelling | draft operation |
|:---|:---|
| `+` `-` `*` `/`, unary `-` | `Add`, `Subtract`, `Multiply`, `Divide`, `Negate` |
| `abs`, `inv`, `sqrt` | `Abs`, `Recip`, `Sqrt` |
| `exp`, `exp2`, `expm1`, `log`, `log2`, `log1p` | `Exp`, `Exp2`, `ExpMinusOne`, `Log`, `Log2`, `LogOnePlus` |
| `sin`, `cos`, `tan`, `asin`, `acos`, `atan` | `Sin`, `Cos`, `Tan`, `ArcSin`, `ArcCos`, `ArcTan` |
| `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` | `Sinh`, `Cosh`, `Tanh`, `ArcSinh`, `ArcCosh`, `ArcTanh` |
| `sinpi`, `cospi`, `tanpi` | `SinPi`, `CosPi`, `TanPi` |
| `atan(y, x)` | `ArcTan2` (Base's argument order) |
| `copysign`, `hypot` | `CopySign`, `Hypot` |
| `min`, `max` | `Minimum`, `Maximum` (NaN-propagating, exactly Base's float semantics) |
| `fma`, `muladd` | `FMA` (both: one rounding) |
| `clamp` | `Clamp` |
| `sincos`, `sincospi`, `minmax` | componentwise composites of the draft ops |

The mapping is a declarative partition over the op lists, and the test suite
asserts it is exhaustive: every operation is either mapped above or listed in
`_NO_BASE_COUNTERPART`. Adding an operation to the registry forces an explicit
decision here.

## What is *not* mapped, and why

**Draft operations with no Base spelling** — call them by their draft names:
`RSqrt`, `Softplus`, `ArcSinPi`/`ArcCosPi`/`ArcTanPi`/`ArcTan2Pi` (Base has
only the `sinpi` family), the NaN-ignoring/magnitude/finite extremum families
(`MinimumNumber`, `MaximumMagnitude`, `MinimumFinite`, …; Base has no
NaN-ignoring pair), and `FAA` (no Base fused add-add).

```julia-repl
julia> min(Binary8p4se(NaN), x)          # Base semantics: NaN propagates
Binary8p4se(NaN ⇆ 0x80)

julia> MinimumNumber(Binary8p4se(NaN), x)   # the NaN-ignoring draft op
Binary8p4se(1.625 ⇆ 0x45)
```

**Mixed `Binary` formats** — deliberately a `promotion ... failed to change`
error, never a silent widening. Mixing formats is an explicit `Convert`:

```julia-repl
julia> x + Convert(Binary8p4se, RNE_SN, Binary5p3sf(1.0))
Binary8p4se(2.5 ⇆ 0x4a)
```

**`Binary` with ordinary numbers** — promotes to the format's **promotion
carrier** through the rules in `formats.jl`, so the result is an ordinary float,
not a re-projected `Binary`.

For the 432 formats at rung 1 that carrier is `Float64`, which is what the
example below shows. The 64 rung-2 formats promote to `Float128`; the 8 rung-3
formats promote to `BigFloat`. `Float64` cannot hold a `Binary16p1uf` datum, and
promoting into it would return `±Inf` from a perfectly finite value with no
P3109 operation involved. `promotecarrier(T)` names the target.

```julia-repl
julia> x + 2.0
3.625
```

Project it back explicitly when that is what you mean:
`Convert(Binary8p4se, RNE_SN, decode(x) + 2.0)`.

## The rest of the Base surface

Beyond arithmetic, `Binary` integrates where the other layers provide it:
predicates and constants (`isnan`, `isfinite`, `signbit`, `zero`, `one`,
`eps` in both its type and value forms, `typemin`/`typemax`,
`floatmin`/`floatmax`), comparisons and `isless`
on integer order keys, `sort` via an O(n) counting sort (which places the single
NaN **first**, below −Inf, per the draft's total order — not last as `Float64`
sorting does),
`nextfloat`/`prevfloat` as the draft Next operations, `codepoint`, and
`rand`/`randn` (see [Random Values](concept_session_state.md)). All of it goes through the same
projection engine and decode tables as the draft-named API.

### The `AbstractFloat` contract

`Binary <: AbstractFloat`, and generic Julia code reaches for that interface
without asking. The routinely used numeric contracts are implemented, while
operations with no P3109 meaning refuse explicitly:

| verb | behaviour |
|:---|:---|
| `hash`, `Base.decompose` | exact — a datum is `S · 2^Q`, so `Dict` keys and `Set` elements work |
| `round`, `floor`, `ceil`, `trunc` | **one** rounding: the integer value is formed exactly on the carrier and projected once, under the session default's saturation |
| `round(x, r::RoundingMode)` | `RoundNearest`, `RoundNearestTiesAway`, `RoundUp`, `RoundDown`, `RoundToZero` |
| `exponent`, `significand`, `frexp` | exact; `DomainError` on zero and the non-finites, as in Base |
| `eps(x)` | the ulp **at** `x`, and always exactly a datum of `x`'s own format — see below |
| `ldexp(x, n)` | exact: scaling by a power of two moves the exponent field and nothing else |
| `widen` | the format's promotion carrier — see [No Automatic Promotion](concept_julia_numeric.md) for why it is not another format |
| `reinterpret` | both directions, and the incoming one is **checked** against the representation invariant |

`eps` has both forms: `eps(T)` is the constant `2^(1-P)`, and `eps(x)` is the
spacing of the lattice at `x`. The second is always representable — the ulp is
`2^Q` with `2−P−B ≤ Q ≤ e_max−P+1`, and every power of two in a format's range
is a datum for every `P ≥ 1` — so it is exact rather than a projected
approximation, and it does not vary with the session projection. In the
subnormal band the spacing is constant, and at zero it is the least positive
datum.

```julia-repl
julia> hash(Binary8p4se(1.5)) == hash(Binary8p4se(1.5))
true

julia> Base.decompose(Binary8p4se(1.5))          # 12 · 2^-3 = 1.5, exactly
(12, -3, 1)

julia> floor(Binary8p4se(1.6)), ceil(Binary8p4se(1.1))
(Binary8p4se(1.0 ⇆ 0x40), Binary8p4se(2.0 ⇆ 0x48))

julia> eps(Binary8p4se(1.5)), eps(Binary8p4se(64.0))   # the lattice widens
(Binary8p4se(0.125 ⇆ 0x28), Binary8p4se(8.0 ⇆ 0x58))

julia> ldexp(Binary8p4se(1.5), 2), ldexp(Binary8p4se(1.5), -2)
(Binary8p4se(6.0 ⇆ 0x54), Binary8p4se(0.375 ⇆ 0x34))

julia> reinterpret(Binary8p4se, 0x44)            # checked, unlike `rawvalue`
Binary8p4se(1.5 ⇆ 0x44)
```

**Refusals name themselves.** Where a Base verb has no draft counterpart, the
error says which and why rather than surfacing as a bare `MethodError` that
cannot be told apart from an oversight:

```julia-repl
julia> rem(Binary8p4se(1.5), Binary8p4se(2.0))
ERROR: ArgumentError: rem is not defined for Binary8p4se: the draft defines no remainder; …
```

That covers `rem`/`mod`, `round` under `RoundFromZero` and `RoundNearestTiesUp`
(no draft μ), and `significand` on the one format whose binade `[1, 2)` is
truncated by its `Inf` encoding.
