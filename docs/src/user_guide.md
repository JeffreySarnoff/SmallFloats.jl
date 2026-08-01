# User Guide

Everything you need to use SmallFloats.jl, in the order you'll need it. All transcripts in
this guide are captured from real sessions against the shipped package.

## Formats and format queries

The parametric type `Binary{K,P,SGN,EXT}` defines a format: bitwidth `K ∈ 3:16`,
precision `P` (significand bits including the implicit bit), `SGN::Bool` for
signed/unsigned, `EXT::Bool` for extended (with ±Inf) versus finite. Every legal
combination — **504 formats** — has a draft-named alias. `using SmallFloats`
exports the **120 at K ≤ 8**; the rest are one opt-in away:

```julia-repl
julia> Binary8p4se <: Binary{8,4,true,true}      # `<:`, not `===` — see below
true

julia> formatname(Binary{6,3,true,false})
:Binary6p3sf

julia> SmallFloats.Binary16p6se                  # always reachable, unexported
Binary16p6se

julia> format(16, 6, true, true)                 # programmatic, runtime params
Binary16p6se

julia> using SmallFloats.Formats                 # …or bring all 504 into scope

julia> Binary16p6se
Binary16p6se
```

`Binary8p4se === Binary{8,4,true,true}` is **`false`**, and the distinction is the
draft's own: a *format* is a datum set and an encoding, while the width of the
machine word carrying a code point is a representation choice below the standard's
level of description. `Binary` is abstract; `Binary8p4se` is its concrete
representation and is what an array element type or a constructor target needs.
Use the alias, or `format(K, P, Σ, Δ)` when the parameters are runtime values.

The suffix reads: `p4` precision 4, `s`/`u` signed/unsigned, `e`/`f` extended/finite.

Format introspection follows the draft's Group M, with both Julia-style and
draft-named accessors:

```julia-repl
julia> bitwidth(Binary8p4se), precision(Binary8p4se), expbias(Binary8p4se)
(8, 4, 8)

julia> MaxFiniteOf(Binary8p4se)
Binary8p4se(224.0 ≡ 0x7e)

julia> MinPositiveOf(Binary8p4se)
Binary8p4se(0.0009765625 ≡ 0x01)
```

Also available: `MinFiniteOf`, `MinNormalOf`, `MaxSubnormalOf`, `expbitwidth`,
`trailingsigbits`, `issigned`, `isextended`, and the draft-named forms
(`BitwidthOf`, `PrecisionOf`, `ExponentBiasOf`, …).

Each of these accepts a **value** as well as a type — the answer is a pure
function of the format's type parameters, so `bitwidth(x)` and
`bitwidth(typeof(x))` are the same query and both fold to a literal:

```julia-repl
julia> x = Binary8p4se(1.6);

julia> BitwidthOf(x), PrecisionOf(x), SignednessOf(x), DomainOf(x)
(8, 4, true, true)

julia> MaxFiniteOf(x)
Binary8p4se(224.0 ≡ 0x7e)
```

## `Binary16p11se` is not `Float16`, and `Binary16p8se` is not `BFloat16`

The K ≤ 16 grid contains two formats that look like the IEEE-754 `binary16` and
the bfloat16 used in machine learning. **They are not those types**, and the
differences are the kind that produce correct-looking numbers rather than errors.

| | `Binary16p11se` | `Float16` | `Binary16p8se` | `BFloat16` |
|---|---|---|---|---|
| precision `P` | 11 | 11 | 8 | 8 |
| exponent bias | **16** | **15** | **128** | **127** |
| largest finite | **65472** | **65504** | **3.3762e38** | **3.3895e38** |
| NaN encodings | **1** | **2046** | **1** | **2046** |
| negative zero | **no** | yes | **no** | yes |
| domain is a parameter | **yes** (`se`/`sf`) | no | **yes** | no |

The bias is the trap. P3109 defines the bias so that the exponent range is
symmetric about the format's midpoint; IEEE-754 defines it as `2^(E-1) − 1`. The
two differ by one, so **every datum in the format is a factor of two away from
its IEEE counterpart** — `Binary16p11se` and `Float16` share a significand layout
and disagree on the value of every code point.

That is why the largest finites differ: 65472 is `(2^11 − 1) · 2^5`, one ulp
short of `Float16`'s 65504, because the top code point of an extended format is
`Inf` rather than a finite value. Converting between them is a conversion, never
a reinterpretation:

```julia-repl
julia> using SmallFloats.Formats

julia> Convert(Binary16p11se, RNE_SF, Float16(1.5))    # a conversion: 1.5 ↦ 1.5
Binary16p11se(1.5 ≡ 0x4200)

julia> reinterpret(Binary16p11se, Float16(1.5))        # the SAME BITS: 1.5 ↦ 0.75
Binary16p11se(0.75 ≡ 0x3e00)
```

The second line is the trap in one expression. `Float16(1.5)` has the bit pattern
`0x3e00`; read as a `Binary16p11se` those same bits denote **0.75**, because the
exponent bias differs by one. Nothing errors, nothing warns, and the answer is
off by a factor of two. Always convert.

The remaining rows are draft decisions rather than accidents. A single NaN
encoding means there is no payload to propagate and no quiet/signalling
distinction; the 2045 code points IEEE spends on NaN payloads are datums here.
No negative zero means `-0.0` and `0.0` are the same code point, so a sign-symmetric
format has an odd number of finite values. And the domain parameter — `e` for
extended (with ±Inf), `f` for finite — has no IEEE analogue at all: `Binary16p11sf`
spends the two infinity code points on finite values instead.

If you want IEEE semantics, use `Float16` and `BFloat16`; the package converts to
and from both, exactly where the datum sets permit (`datumsexact`).

## Values

A value is an immutable wrapper around its code point — **one byte at K ≤ 8, two
above it**. The storage unit is `codeunit_type(T)`, a property of the
*representation*; the code point occupies the low `K` bits and the high bits are
maintained zero. Four ways in, two
ways out:

```julia-repl
julia> x = Binary8p4se(1.6)              # construct from a Real: projects (rounds)
Binary8p4se(1.625 ≡ 0x45)

julia> Binary8p4se(0x45)                 # construct from a UInt8 CODE POINT (validated)
Binary8p4se(1.625 ≡ 0x45)

julia> rawvalue(Binary8p4se, 0x45)       # same, unchecked — the kernel-internal route
Binary8p4se(1.625 ≡ 0x45)

julia> Convert(Binary8p4se, RNE_SN, 3)   # explicit conversion, any mode
Binary8p4se(3.0 ≡ 0x4c)

julia> decode(x)                          # the exact datum, on the format's carrier
1.625

julia> codepoint(x)                       # the code point (extends Base.codepoint)
0x45
```

`decode` is **always exact**, but the type it returns is a property of the
format: `Float64` for 432 formats, `Float128` for 64, and an exact dyadic carrier
for the 8 widest-range formats. `datumcarrier(T)` names it; `Float64(x)` always
returns a `Float64` and rounds where the datum does not fit.

!!! note "Unsigned means code point; signed integers mean value"
    Every `Unsigned` argument has code-point semantics — mirroring `Char(0x41)`
    and working at both storage widths. Other `Real`s, including signed
    integers, construct by projecting the numeric value; `Convert` is numeric
    for **all** integers:

    ```julia-repl
    julia> Binary8p4se(0x02), Binary8p4se(2)
    (Binary8p4se(0.001953125 ≡ 0x02), Binary8p4se(2.0 ≡ 0x48))
    ```

    Out-of-range codes throw (`Binary5p3sf(0x20)` is an error). A wider unsigned
    argument is accepted when its numeric code point fits, so
    `Binary16p6se(UInt32(2))` is valid and checked. Round-tripping is
    `T(codepoint(x)) === x`.

`Convert` accepts `Binary` values (any format), `Float16/32/64`, `Float128`,
`Integer`, and `BigFloat` — types whose values it can project *exactly*.
`Float128` projects directly, preserving all 113 significand bits: a value that
sits a hair above a rounding midpoint converts correctly where staging through
`Float64` would round it onto the midpoint first and then break the tie the wrong
way. For other `Real`s, convert explicitly first (e.g. `Binary8p4se(Float64(π))`)
and own the double rounding; `Rational` inputs throw with that guidance rather
than double-round silently.

Every format has exactly one NaN and no negative zero; extended formats add ±Inf:

```julia-repl
julia> Binary8p4se(1e9)                   # overflow under the default spec → +Inf
Binary8p4se(Inf ≡ 0x7f)

julia> Binary8p4se(-0.0)                  # no −0: projects to the single zero
Binary8p4se(0.0 ≡ 0x00)

julia> isnan(Binary8p4se(NaN)), isfinite(Binary8p4se(2.0))
(true, true)
```

Standard predicates (`isnan`, `isinf`, `isfinite`, `iszero`, `signbit`, `issubnormal`),
`zero`/`one`/`eps`/`typemin`/`typemax`, and stepping via `NextGreaterThan` /
`NextLessThan` (the draft's Next operations; `nextfloat`/`prevfloat` alias them) all
work:

```julia-repl
julia> NextGreaterThan(Binary8p4se(1.0))
Binary8p4se(1.125 ≡ 0x41)

julia> Class(Binary8p4se(0.01))           # draft classification
ClassPosNormal::FPClass = 0x06
```

## Random values

The Random API works on every format, in every setup Julia programmers expect.

**What the draws mean.** `rand` draws the real uniform on [0, 1) at Float64 and
floor-projects it onto the format's grid, so each code point receives exactly
the real measure of its interval; results are always in [0, 1). `randn`
projects a standard-normal Float64 draw round-to-nearest with `SatFinite`, so
tail draws beyond `MaxFiniteOf(T)` clamp to the extremal finite datum — `randn`
never returns ±Inf or NaN, which matters for tiny-range formats (`Binary3p1se`
has `MaxFinite = 1.0`). `randn` requires a signed format; an unsigned format
throws:

```julia-repl
julia> randn(Binary6p3ue)
ERROR: ArgumentError: randn requires a signed format; Binary6p3ue cannot represent negative draws
```

**Setup 1 — quick and implicit.** No rng argument: draws come from Julia's
task-local default generator (a `Xoshiro`), and `Random.seed!` controls them
exactly as for any other type:

```julia-repl
julia> Random.seed!(1234); rand(Binary8p4se)
Binary8p4se(0.3125 ≡ 0x32)

julia> Random.seed!(1234); rand(Binary8p4se)      # same seed, same draw
Binary8p4se(0.3125 ≡ 0x32)
```

**Setup 2 — an explicit rng stream.** Pass any `AbstractRNG` first, for
reproducible streams independent of global state:

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

**Setup 3 — arrays and in-place.** `rand(T, dims...)` / `randn(T, dims...)`
build `Array{T}`; `rand!(A)` / `randn!(A)` fill an existing array (one byte per
element at K ≤ 8, two above — cheap to preallocate and reuse):

```julia-repl
julia> A = Vector{Binary8p4se}(undef, 3); randn!(Xoshiro(2), A)
3-element Vector{Binary8p4se}:
 Binary8p4se(-0.005859375 ≡ 0x86)
 Binary8p4se(1.75 ≡ 0x46)
 Binary8p4se(-1.0 ≡ 0xc0)

julia> randn(Xoshiro(3), Binary8p4se, 2, 3) |> typeof
Matrix{Binary8p4se}
```

Feed array draws straight into the storage layers when that is the goal:
`PackedVector(rand(Binary4p2se, n))`.

**Setup 4 — choosing the projection.** The scalar `::Type` forms take a
`projection` keyword to land the draw under any `ProjSpec`:

```julia-repl
julia> rand(Xoshiro(2), Binary8p4se; projection = RTP_SN)    # ceiling
Binary8p4se(0.0029296875 ≡ 0x03)

julia> randn(Xoshiro(6), Binary8p4se; projection = RTZ_SF) # toward zero
Binary8p4se(-1.875 ≡ 0xc7)

julia> rand(Xoshiro(4), Binary8p4se; projection = RSA_SN(8)) # stochastic
Binary8p4se(0.8125 ≡ 0x3d)
```

A stochastic projection draws its random bits from the *same* rng, so seeded
streams stay reproducible. The defaults are the contract-keepers (floor for
`rand`, nearest + `SatFinite` for `randn`); opting out can produce `1.0` from
`rand` or ±Inf/NaN from `randn`. The array and `!` forms always use the
defaults — for arrays under another projection, draw scalars:
`[rand(rng, T; projection = ρ) for _ in 1:n]`. Worked transcripts, including
the K = 3 tail-clamp comparison: [User Examples](@ref).

## Projection specifications

Every rounding decision in the package is governed by a `ProjSpec`, the pair of a
**rounding mode** and a **saturation mode**. Both are zero-size singleton types, so a
`ProjSpec` costs nothing and fully specializes every call it reaches.

Rounding modes: `NearestTiesToEven`, `NearestTiesToAway`, `TowardPositive`,
`TowardNegative`, `TowardZero`, `ToOdd`, and the stochastic families
`StochasticA{N}`, `StochasticB{N}`, `StochasticC{N}` with a random-bit budget
`1 ≤ N ≤ 60`. Saturation modes: `SatFinite`, `SatPropagate`, `SatNone`.

```julia-repl
julia> ρ = ProjSpec(TowardPositive(), SatFinite())
(TowardPositive, SatFinite)

julia> RTP_SF === ρ                # every pairing is also predefined
true
```

### Predefined specs

Every deterministic (rounding, saturation) pairing is exported as a constant, named
`R<mode>_Sat<mode>`:

| | `SatFinite` | `SatPropagate` | `SatNone` |
|---|---|---|---|
| `NearestTiesToEven` | `RNE_SF` | `RNE_SP` | `RNE_SN` |
| `NearestTiesToAway` | `RNA_SF` | `RNA_SP` | `RNA_SN` |
| `TowardPositive` | `RTP_SF` | `RTP_SP` | `RTP_SN` |
| `TowardNegative` | `RTN_SF` | `RTN_SP` | `RTN_SN` |
| `TowardZero` | `RTZ_SF` | `RTZ_SP` | `RTZ_SN` |
| `ToOdd` | `RTO_SF` | `RTO_SP` | `RTO_SN` |

The stochastic families are parameterized by the random-bit budget `N`, so their
predefined forms are *constructors* rather than constants: `RSA_*` for
`StochasticA`, `RSB_*` for `StochasticB`, `RSC_*` for `StochasticC`, each crossed
with the three saturation modes. Call them with the budget — or without, for the
default `N = 8` (`SmallFloats.DEFAULT_RBITS`):

```julia-repl
julia> RSA_SN()                      # StochasticA with the default N = 8
(StochasticA[8], SatNone)

julia> RSC_SF(16) === ProjSpec(StochasticC{16}(), SatFinite())
true
```

`RNE_SN` is the package's *initial* default spec. `default_projspec` reads the
session default (see **Session defaults** below), so every Base-register operator,
the same-format convenience methods, and `T(x::Real)` construction follow
`DefaultProjection()` — `RNE_SN` until you change it.

Rounding chooses the neighbor; saturation decides what out-of-range results become.
Watch all three interact on an overflowing product in `Binary8p4se`
(`MaxFinite = 224`):

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)       # overflow → ±Inf
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)     # overflow → MaxFinite
Binary8p4se(224.0 ≡ 0x7e)

julia> Multiply(Binary8p4se, RTZ_SN, w, two)
Binary8p4se(224.0 ≡ 0x7e)   # SatNone + directed-toward-zero clamps finite
```

!!! note
    `SatNone` is not "no saturation handling": it is the draft's row set in which
    nearest modes overflow to ±Inf (or NaN for finite formats) while directed modes
    that point away from the overflow clamp to the extremal finite value.

### Stochastic rounding

Stochastic modes consume `N` random bits per projection. You control the source three
ways — implicitly (task-local RNG), by passing an `rng`, or by fixing the draw `R`
itself, which makes single projections exactly reproducible and is the right tool for
tests:

```julia-repl
julia> σ = RSA_SN();                 # ≡ ProjSpec(StochasticA{8}(), SatNone())

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); rng = Xoshiro(1))
Binary8p4se(2.0 ≡ 0x48)

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 0)
Binary8p4se(2.0 ≡ 0x48)      # smallest draw: rounds down

julia> Add(Binary8p4se, σ, Binary8p4se(2.0), Binary8p4se(0.03125); R = 255)
Binary8p4se(2.25 ≡ 0x49)     # largest draw: rounds up
```

The exact fraction here is 1/8 of an ulp, so over all 256 draws exactly 32 round up —
`StochasticA` is unbiased in expectation. `R` must lie in `0:2^N-1`.

### Session defaults

Seven session-wide defaults are readable as `DefaultX()` and settable as
`DefaultX!(v)`:

| default | initial value | setter accepts |
|---|---|---|
| `DefaultType` | `Binary8p2se` | any fully-parameterized `Binary` type |
| `DefaultReturnType` | `Binary8p2se` | any fully-parameterized `Binary` type |
| `DefaultRoundingMode` | `NearestTiesToEven()` | mode instance or type |
| `DefaultSaturationMode` | `SatNone()` | mode instance or type |
| `DefaultProjection` | `RNE_SN` | a `ProjSpec`, or `(mode, sat)` |
| `DefaultRNG` | the `Xoshiro` type | RNG type or instance |
| `DefaultRbits` | `8` | `Int` in `1:60` |

The projection default and its components are kept coherent in both directions:
setting `DefaultRoundingMode!` or `DefaultSaturationMode!` rebuilds
`DefaultProjection` around the change, and setting `DefaultProjection!` directly
decomposes it back into both components — so
`DefaultProjection() === ProjSpec(DefaultRoundingMode(), DefaultSaturationMode())`
always holds.

```julia-repl
julia> DefaultRoundingMode!(TowardZero())
TowardZero()

julia> DefaultProjection()               # followed the component
(TowardZero, SatNone)

julia> DefaultProjection!(RNA_SF)
(NearestTiesToAway, SatFinite)

julia> DefaultRoundingMode(), DefaultSaturationMode()   # followed the projection
(NearestTiesToAway(), SatFinite())

julia> DefaultProjection!(RNE_SN)        # restore: these setters are PROCESS-wide
(NearestTiesToEven, SatNone)
```

!!! warning "The session defaults are process-global and they stay set"
    `DefaultProjection!` and its siblings mutate state shared by every module in
    the process. Nothing scopes them for you: set one in a script, a notebook
    cell, or a REPL session and *every* later `T(x::Real)`, `a + b` and `Exp(x)`
    follows it until something sets it back.

    Prefer [`with_default_projection`](@ref) (and `with_default_type`,
    `with_default_returntype`), which restore on exit even if the body throws:

    ```julia
    with_default_projection(RTZ_SF) do
        Binary8p4se(1e9)          # clamps, inside this block only
    end
    ```

    Every example below assumes the pristine `(NearestTiesToEven, SatNone)`,
    which is why each demonstration above restores it explicitly.

`DefaultProjection` is not merely advisory: `default_projspec` reads it, so the
same-format convenience methods (`a + b`, `Exp(x)`, …), the Base-register
operators, and `T(x::Real)` construction all follow it.

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

!!! warning "Changing the default is a global semantic change"
    Every caller of the convenience forms — including code in other packages —
    sees it. Library code that needs a specific projection should name it
    explicitly rather than rely on the session default.

Following the default costs nothing while it holds its initial value: the
convenience forms consume it through the same speculation guard as the
`with_default_*` combinators, so they compile against the constant and stay
allocation-free with concretely inferred results (pinned in the test suite).
Once you change the default they cross a function barrier instead — one dynamic
dispatch per call, everything inside still specialized. The explicit forms
`Add(T, ρ, x, y)` are unaffected either way.

To *consume* a default in your own code without paying dynamic-dispatch costs,
go through the `with_default_*` combinators — `with_default_type`,
`with_default_returntype`, `with_default_projection` — which call
`f(default, args...)`:

!!! note "There is no accumulator default"
    `DefaultAccumulatorType` existed through v0.1.0 and was removed. The
    wide-precision accumulator in a reduction is not a preference: the span
    filter measures the operands and picks the cheapest carrier that is
    *provably exact* for them, so both branches return the defined result. A
    knob overriding that would make `BlockDotProduct` inexact from the default
    API. To trade speed for nothing else, set
    `ENV["SmallFloats_Float128"] = "disable"`, which is bit-identical by
    construction.

```julia-repl
julia> with_default_type((T, x) -> T(x), 1.5)
Binary8p2se(1.5 ≡ 0x41)
```

While a default still holds its initial value, the combinator's call is
statically compiled against that constant — no dynamic dispatch. After the
default is changed it crosses a function barrier: one dynamic dispatch at
entry, everything inside fully specialized.

Allocation contract: when `f`'s result type does not depend on the default —
`with_default_projection` with the formats fixed by the caller is the normal
shape — the call is zero-allocation with a concretely inferred result (pinned
in the test suite). When the result's type *is* the default
(`with_default_type` used as a constructor), the value is computed on the
specialized path but boxes once where it escapes — the irreducible cost of a
runtime-chosen type.

## Scalar operations: the two registers

**The spec-named register** exposes every draft operation under its draft name with an
explicit result format and spec: `Op(fr, ρ, operands...)`. Operands may be any
formats; the result format is the first argument. The catalog:

- **30 unary** — `Abs`, `Negate`, `Sqrt`, `RSqrt`, `Recip`, `Exp`, `Exp2`,
  `ExpMinusOne`, `Log`, `Log2`, `LogOnePlus`, `Softplus`, the trig/hyperbolic
  families, and the π-scaled families;
- **18 binary** — `Add`, `Subtract`, `Multiply`, `Divide`, `CopySign`, `Hypot`,
  `ArcTan2`, `ArcTan2Pi`, and the eight Minimum/Maximum variants plus the Finite
  variants;
- **3 ternary** — `FMA`, `FAA`, `Clamp`;
- **`Convert`** — the one operation that also accepts non-`Binary` operands.

**The Base register** makes each format an ordinary Julia number under its *default*
spec (`RNE_SN`): `+ - * /`, `fma`, `exp`, `log`, `sqrt`, `min`, `max`, `abs`,
`atan(y, x)`, `sinpi`, `inv`, comparisons, and friends — same-format operands
only. Mixed `Binary` formats deliberately fail promotion; convert operands to a
chosen format explicitly.

```julia-repl
julia> exp(Binary8p4se(0.25))                       # Base register
Binary8p4se(1.25 ≡ 0x42)

julia> Exp(Binary8p4se, RNE_SN, Binary8p4se(0.25))   # identical, explicit
Binary8p4se(1.25 ≡ 0x42)
```

Semantics highlights (all per the draft): `x/0 → NaN` for every `x` including ±Inf;
`Recip(±Inf) = 0`; `0·∞ → NaN`; a NaN operand generally propagates, except the
`*Number`/`*Finite` extremum variants which prefer non-NaN (and finite) operands;
trig of ±Inf is NaN; the π-scaled family reduces exactly mod 2 first.

## Arrays, kernels, and sorting

Every operation has array methods — `Op(fr, ρ, A)`, `Op(fr, ρ, A, B)`,
`Op(fr, ρ, A, B, C)` — plus the generic `vmap` / `vmap!`.

(In that line `Op` stands for any operation name — `Add`, `Exp`, and so on. There
is also a *type* called [`Op`](@ref), introduced below, which turns an operation
into a callable so `map` and broadcast work directly.)

```julia-repl
julia> A = Binary8p4se.(randn(Xoshiro(7), 4) .* 2)
4-element Vector{Binary8p4se}:
 Binary8p4se(-0.875 ≡ 0xbe)
 Binary8p4se(4.0 ≡ 0x50)
 Binary8p4se(-3.25 ≡ 0xcd)
 Binary8p4se(2.25 ≡ 0x49)

julia> Exp(Binary8p4se, RNE_SN, A)
4-element Vector{Binary8p4se}:
 Binary8p4se(0.40625 ≡ 0x35)
 Binary8p4se(56.0 ≡ 0x6e)
 Binary8p4se(0.0390625 ≡ 0x1a)
 Binary8p4se(9.0 ≡ 0x59)
```

For pure (non-stochastic) specs on K ≤ 8 formats, unary and binary array calls
run as **table gathers**: the first call builds and caches a 256-byte (unary) or
64 KiB (binary) result table for that exact `(op, formats, ρ)` specialization.
On the recorded host, warm gathers take 0.13 ns/element unary and 0.26
ns/element binary. Wider formats compute directly because their complete tables
are not affordable.

Ternary operations (`FMA`, `FAA`, `Clamp`) ride the same gather whenever the three
operand bitwidths keep the table affordable, tiered by `K1 + K2 + K3`:

- **Eager** (up to 256 KiB; every all-`K ≤ 6` signature): built on the first
  array call, like unary/binary.
- **Adaptive** (up to 2 MiB; the `K = 7` band): built only once a signature has
  processed enough elements to earn its build, in a byte-bounded, LRU-evicted
  cache.
- **Compute** (`K = 8`; a 16 MiB table stops being a cache win): the scalar
  pipeline runs per element, optionally threaded for long arrays.

Any ternary signature containing a format above K = 8 also computes directly;
the three tiers above describe the table-eligible K ≤ 8 region.

Every table entry — eager or adaptive — is built through the scalar path, so it is
bit-identical by construction. Stochastic calls always run the scalar pipeline per
element (each element draws its own random bits).

Inspect or reset the cache — unary/binary and ternary alike — with `table_bytes()`
and `empty_tables!()`. The ternary policy thresholds and the threading cutoff are
internal `Ref`s (`SmallFloats.TERNARY_EAGER_BITS` and neighbors in `tables.jl` and
`kernels.jl`) for the rare case you need to tune them.

Sorting is special-cased: values compare through integer order keys, and vectors of
`Binary` sort with an **O(n) counting sort** installed as the default algorithm —
about 8× the stock comparison sort at 64 K elements, `rev=true` included. `sort(A)`
just works; NaN sorts last (first under `rev=true`), matching Base's conventions.
`TotalOrder(x, y)` exposes the draft's total order directly (single NaN largest).

### `map`, broadcast, and the `Op` callable

`vmap!` is the in-place, table-aware kernel and is what you want when you have a
destination to fill. When you want Julia's own array verbs, bind the operation,
result format and projection into an [`Op`](@ref) and use it as a function:

```julia-repl
julia> A = Binary8p4se.([1.5, 0.25]); B = Binary8p4se.([0.25, 1.5]);

julia> map(Op(:Add, Binary8p4se, RNE_SN), A, B)
2-element Vector{Binary8p4se}:
 Binary8p4se(1.75 ≡ 0x46)
 Binary8p4se(1.75 ≡ 0x46)

julia> Op(:Exp, Binary8p4se, RNE_SN).(A)
2-element Vector{Binary8p4se}:
 Binary8p4se(4.5 ≡ 0x51)
 Binary8p4se(1.25 ≡ 0x42)
```

`Op` is a singleton type — the operation, format and projection all live in its
type parameters — so a call specializes exactly as `Add(Binary8p4se, RNE_SN, x, y)`
does and allocates nothing beyond the array `map` itself builds.

## Blocks and scaled operations

A `Block{B,FS,FE}` is a scale in format `FS` and `B` elements in format `FE`; its
represented values are `scale × element` (the MX-style scheme). Construct directly or
quantize a tuple with the draft's algorithm, which picks the scale from the maximum
finite |element| and projects each element against it:

```julia-repl
julia> b = Block(Binary8p1uf(4.0), Binary8p4se(1.5), Binary8p4se(-0.75),
                 Binary8p4se(2.0), Binary8p4se(0.5))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(4.0 ≡ 0x82), (…))

julia> ConvertFromBlock(Binary8p3se, RNE_SN, b)   # decode scale×elem, project
(Binary8p3se(6.0 ≡ 0x4a), Binary8p3se(-3.0 ≡ 0xc6), Binary8p3se(8.0 ≡ 0x4c), Binary8p3se(2.0 ≡ 0x44))

julia> BlockReduceAdd(Binary8p4se, RNE_SN, b)     # exact Σ scale·xᵢ, then project
Binary8p4se(13.0 ≡ 0x5d)

julia> ConvertToBlockMaxAbsFinite(Binary8p1uf, Binary8p4se, RNE_SN, RNE_SN,
           (Binary8p4se(100.0), Binary8p4se(-12.0), Binary8p4se(0.5), Binary8p4se(3.0)))
Block{4, Binary8p1uf, Binary8p4se}(Binary8p1uf(64.0 ≡ 0x86), (…))
```

Every scalar operation lifts to blocks (`BlockAdd`, `BlockExp`, …, taking blocks and
a result scale) and to the scaled form `ScaledOp` (`ScaledAdd(fr, ρ, s1, x1, s2, x2)`
— block size 1). Reductions: `BlockReduceAdd`, `BlockReduceMultiply`, and
`BlockDotProduct(fr, ρ, bx, by)`, whose lane products and accumulation are **exact**
before the single final projection — there is no hidden intermediate rounding.
`ConvertToBlock(fs, fr, ρ, xs, s)` quantizes against a scale you supply.
`BlockVector` stores many same-shape blocks in structure-of-arrays layout.

## Packed storage

For memory-bound work, `PackedVector{F}` stores code points at `bitwidth(F)` bits
per element (a `Binary5p2se` vector at 5 bits/element instead of 8):

```julia-repl
julia> v = Binary5p2se.(rand(Xoshiro(3), 6) .* 4);

julia> pv = PackedVector(v); sizeof(pv.data)
8                     # 6 × 5 bits = 30 bits → one 64-bit word

julia> pv[3] == v[3]
true
```

It is a full `AbstractVector{F}` (indexing, `collect`, iteration), and `vmap` accepts
it directly, unpacking cache-friendly tiles internally. The rule is *store packed,
compute unpacked*: there is deliberately no in-place packed arithmetic.

## Conformance and κ-approximate implementations

`conformance()` returns the live declaration — formats, operations, mode vocabulary,
the table specializations actually instantiated this session, and every registered
approximation. `conformance_report()` prints it; `conformance_dict()` returns a
plain nested `Dict` for JSON/TOML serialization.

The default API is bit-exact, always. If you *want* a faster inexact kernel, register
it — and the registry measures your honesty:

```julia-repl
julia> ftz = ftz_variant(:Exp, Binary8p4se, Binary8p4se, RNE_SF);  # Annex example

julia> impl = register_approx!(:my_fast_exp, :Exp, Binary8p4se, (Binary8p4se,),
                               RNE_SF, ftz);

julia> kappa(:my_fast_exp)      # measured max code-point deviation, verified exhaustively
4.0
```

Declaring `κ` smaller than the measured deviation throws; NaN-mismatching
implementations must be acknowledged with an explicit `κ = NaN`. Retrieve with
`approx(:my_fast_exp)`, list with `list_approx()`, and measure anything yourself with
`measure_kappa` / `codedistance`.

## Performance guidance

!!! warning "The abstract format as an array element type"
    `Binary{K,P,Σ,Δ}` is **abstract**, so an array declared with it has a
    non-`isbits` element type and boxes every element:

    ```julia-repl
    julia> isbitstype(eltype(Vector{Binary{8,4,true,true}}(undef, 3)))
    false

    julia> isbitstype(eltype(Vector{Binary8p4se}(undef, 3)))
    true
    ```

    Nothing errors — every operation still returns the right answer, because the
    package normalizes the abstract format at each constructor and entry point.
    You simply lose the entire performance story, silently. That makes this the
    sharper edge of the `===` distinction: the type comparison is visibly
    `false`, while this one costs you and says nothing.

    `similar(a, T)` normalizes the request; `Vector{T}(undef, n)` cannot be
    intercepted. Use the alias, or `format(K, P, Σ, Δ)` for runtime parameters.

- **Pass format types statically.** Through `const` bindings, type parameters, or
  function arguments, every entry point fully specializes and warm scalar paths
  allocate nothing. A format type read from a **non-`const`
  global** forces Julia's dynamic dispatch on every call (~1 µs for keyword calls);
  one function barrier `f(::Type{T}, …) where {T}` restores full speed.
- **The convenience forms are free at the initial default.** `x + y`, `Exp(x)`,
  and `T(2.1)` read the session default through a speculation guard, so they are
  allocation-free and concretely inferred while it holds its initial value. After
  you change the default they cost one dynamic dispatch per call; name ρ
  explicitly (`Add(T, ρ, x, y)` with a `const` ρ) in hot code that must be
  insensitive to the session default.
- **Bulk work belongs in array calls.** Table-eligible warm gathers are much
  faster than scalar calls; the first call per specialization pays a one-time
  build. The cost depends strongly on operation and table size, so use the dated
  [benchmark report](benchmarks.md) rather than a frozen rule of thumb.
- **Ternary array calls scale with bitwidth.** `K ≤ 6` operand formats table
  eagerly (~35× the scalar loop); `K = 7` tables adaptively once a signature is
  hot; `K = 8` runs the compute kernel, optionally threaded for long arrays
  (~4× at 4 threads) — no action needed, the array call picks the right path.
- **Stochastic array calls** run the scalar pipeline per element; pass an
  explicit `rng` for reproducibility.
- **Memory:** `PackedVector` for storage; `BlockVector` for many blocks.
- The reproducible benchmark suite lives at `benchmarking/benchmarking.jl` and generates
  a full markdown report for your machine.

## Environment switches

`ENV["SmallFloats_Float128"] = "disable"` (set before `using SmallFloats`) disables the internal
`Float128` fast paths in favor of pure MPFR — results are bit-identical (tested);
only build/oracle speed changes.
