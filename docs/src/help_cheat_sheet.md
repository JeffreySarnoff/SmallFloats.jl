# Cheat Sheet

A compact reference for the SmallFloats.jl operations you are most likely to
write. For semantics and explanation, follow the links out of each section; for
implementation detail, see [Insights](internals_architecture.md).

## Start here

```julia
using SmallFloats
using Random: Xoshiro

T = Binary8p4se
ρ = RNE_SN

x = T(1.6)
y = T(0.25)
z = Add(T, ρ, x, y)
```

The explicit operation shape is always:

```julia
OperationName(result_format, projection_spec, operands...; rng, R)
```

For same-format operands under the default projection, ordinary Julia syntax is
available:

```julia
z == x + y
exp(x)
fma(x, y, z)
```

## Format names

```text
Binary K p P (s|u) (e|f)
       │   │  │     └─ extended (Inf) or finite domain
       │   │  └────── signed or unsigned
       │   └───────── significand precision, including the implicit bit
       └───────────── total bitwidth, 3 through 16
```

Examples:

| Name | Meaning |
|:---|---|
| `Binary8p4se` | 8-bit, precision 4, signed, extended |
| `Binary8p4sf` | 8-bit, precision 4, signed, finite |
| `Binary6p3ue` | 6-bit, precision 3, unsigned, extended |
| `Binary5p5uf` | 5-bit, precision 5, unsigned, finite |
| `Binary16p6se` | 16-bit, precision 6, signed, extended (opt-in export) |
| `Binary16p1uf` | 16-bit, precision 1, unsigned, finite — the MX scale shape |

The alias is the *representation* of the parametric format, related by `<:` and
**not** by `===`:

```julia
Binary8p4se <: Binary{8, 4, true, true}    # true
Binary8p4se === Binary{8, 4, true, true}   # FALSE — `Binary` is abstract
format(16, 6, true, true)                  # the alias, from runtime parameters
```

`using SmallFloats` exports the 120 aliases at K ≤ 8. For the other 384:
`using SmallFloats.Formats`, or `SmallFloats.Binary16p6se`, or `format(...)`.

Useful format queries:

```julia
bitwidth(T)       # K
precision(T)      # P
issigned(T)
isextended(T)
expbias(T)
expbitwidth(T)
trailingsigbits(T)

MaxFiniteOf(T)
MinFiniteOf(T)
MinPositiveOf(T)
MinNormalOf(T)
MaxSubnormalOf(T)
```

Every query above also takes a **value** instead of a type — `bitwidth(x)` ≡
`bitwidth(typeof(x))` — and folds to the same constant:

```julia
x = Binary8p4se(1.6)
bitwidth(x)       # 8
MaxFiniteOf(x)    # Binary8p4se(224.0 ≡ 0x7e)
```

## Values and code points

```julia
x = T(1.6)                    # numeric value: project into T
x = Convert(T, ρ, 1.6)       # explicit projection

c = codepoint(x)              # the code point, in the format's storage unit
x = T(c)                      # an Unsigned means validated CODE POINT
x = T(c)                      # checked code-point construction (`c::Unsigned`)

d = decode(x)                 # the exact datum, on the format's own carrier
```

!!! warning "`Unsigned` means code point — at every width"
    `T(0x02)` constructs code point `0x02`; `T(2)` projects the numeric value
    two. Signedness of the integer type is what distinguishes them, so the rule
    holds for `UInt8`, `UInt16` and any other `Unsigned`: `Binary16p6se(0x0002)`
    is code point 2, not the value 2.0. Use `Convert` when intent should be
    unmistakable.

    `codepoint` returns the format's *storage unit* — `UInt8` at K ≤ 8,
    `UInt16` above — and that is `codeunit_type(T)`. A code-point argument is
    range-checked against `2^K` whatever its width, so passing a wider
    `Unsigned` than necessary is lossless and safe.

    `convert` is the deliberate exception and is value-preserving:
    `Binary8p4se(0x02)` is code point 2, while `convert(Binary8p4se, 0x02)` is
    the value 2.0. Promotion, `similar` and `fill` depend on that.

Random values (uniform [0,1) floor-projected; normal round-to-nearest,
tails clamped to MaxFinite; `randn` signed formats only):

```julia
rand(T); rand(T, dims); rand!(A)      # uniform on [0, 1)
randn(T); randn(T, dims); randn!(A)   # standard normal, always finite
rand(Xoshiro(1), T)                   # explicit rng as usual

rand(rng, T;  projection=RTP_SN)   # scalar forms: land under any ProjSpec
randn(rng, T; projection=RTZ_SF) # (stochastic ρ draws R from same rng)
```

Classification and stepping:

```julia
isnan(x); isinf(x); isfinite(x); iszero(x)
signbit(x); issubnormal(x)
Class(x)
NextGreaterThan(x); NextLessThan(x)
nextfloat(x); prevfloat(x)
TotalOrder(x, y)
```

## Projection specifications

A projection specification is `(rounding mode, saturation mode)`:

```julia
ρ = ProjSpec(TowardPositive(), SatFinite())
roundingmode(ρ)
saturationmode(ρ)
```

### Deterministic projections

| Rounding | `SatFinite` | `SatPropagate` | `SatNone` |
|:---|---|---|---|
| nearest, ties even | `RNE_SF` | `RNE_SP` | `RNE_SN` |
| nearest, ties away | `RNA_SF` | `RNA_SP` | `RNA_SN` |
| toward +∞ | `RTP_SF` | `RTP_SP` | `RTP_SN` |
| toward −∞ | `RTN_SF` | `RTN_SP` | `RTN_SN` |
| toward zero | `RTZ_SF` | `RTZ_SP` | `RTZ_SN` |
| round to odd | `RTO_SF` | `RTO_SP` | `RTO_SN` |

`RNE_SN` is the package-wide default. Saturation modes mean:

| Mode | Out-of-range behavior |
|:---|---|
| `SatFinite` | clamp everything to the finite range |
| `SatPropagate` | preserve representable infinities; clamp other overflow |
| `SatNone` | apply the draft's domain-, signedness-, and direction-dependent rows |

### Stochastic projections

Constructors are grouped by stochastic variant:

| Variant | `SatFinite` | `SatPropagate` | `SatNone` |
|:---|---|---|---|
| A | `RSA_SF(N)` | `RSA_SP(N)` | `RSA_SN(N)` |
| B | `RSB_SF(N)` | `RSB_SP(N)` | `RSB_SN(N)` |
| C | `RSC_SF(N)` | `RSC_SP(N)` | `RSC_SN(N)` |

`N` is the random-bit budget, `1 ≤ N ≤ 60`. Omitting it uses `N = 8`.

```julia
σ = RSA_SN(8)

Add(T, σ, x, y; rng=Xoshiro(1))  # reproducible stream
Add(T, σ, x, y; R=17)            # exact draw, ideal for tests

isstochastic(σ)                   # true
nrandbits(σ)                      # 8
```

For an `N`-bit mode, explicit `R` must be in `0:(2^N - 1)`.

### Session defaults

Read with `DefaultX()`, set with `DefaultX!(v)`:

```julia
DefaultType()            # Binary8p2se     DefaultType!(Binary8p4se)
DefaultReturnType()      # Binary8p2se     DefaultReturnType!(Binary8p3se)
DefaultRoundingMode()    # NearestTiesToEven()
DefaultSaturationMode()  # SatNone()
DefaultProjection()      # RNE_SN
```

Setting a rounding/saturation component rebuilds `DefaultProjection`; setting
`DefaultProjection!` directly updates both components. Always:
`DefaultProjection() === ProjSpec(DefaultRoundingMode(), DefaultSaturationMode())`.

The convenience methods (`a + b`, `Exp(x)`, `T(2.1)`) **do** consult
`DefaultProjection`, so changing it changes their results globally. They read it
through a speculation guard: allocation-free while the default holds its initial
value, one dispatch per call after you change it. Explicit forms
(`Add(T, ρ, x, y)`) are unaffected by the session default.

Consume a default via the combinators — never by computing on a bare
`DefaultX()` read. No dispatch while the default is unchanged, one barrier
dispatch after a change; zero-alloc when `f`'s result type doesn't depend on
the default (a default-typed result boxes once at escape):

```julia
with_default_type((T, x) -> T(x), 1.5)          # Binary8p2se(1.5 ≡ 0x41)
with_default_projection((ρ, x, y) -> Add(T, ρ, x, y), x, y)
with_default_returntype(f, args...)              # f(DefaultReturnType(), args...)
```

## Scalar operation catalog

```julia
# explicit result format and projection
Add(T, ρ, x, y)
FMA(T, ρ, x, y, z)
Convert(T, ρ, external_value)

# same-format default-projection convenience
Add(x, y)
FMA(x, y, z)
```

| Arity | Operations |
|:---|---|
| Unary | `Abs`, `Negate`, `Sqrt`, `RSqrt`, `Recip`, `Exp`, `Exp2`, `ExpMinusOne`, `Log`, `Log2`, `LogOnePlus`, `Softplus`, `Sin`, `Cos`, `Tan`, `ArcSin`, `ArcCos`, `ArcTan`, `Sinh`, `Cosh`, `Tanh`, `ArcSinh`, `ArcCosh`, `ArcTanh`, `SinPi`, `CosPi`, `TanPi`, `ArcSinPi`, `ArcCosPi`, `ArcTanPi` |
| Binary | `CopySign`, `Add`, `Subtract`, `Multiply`, `Divide`, `Hypot`, `ArcTan2`, `ArcTan2Pi`, `Maximum`, `Minimum`, `MaximumNumber`, `MinimumNumber`, `MaximumMagnitude`, `MinimumMagnitude`, `MaximumMagnitudeNumber`, `MinimumMagnitudeNumber`, `MinimumFinite`, `MaximumFinite` |
| Ternary | `FMA`, `FAA`, `Clamp` |
| Conversion | `Convert` |

Common Base spellings under the session projection (initially `RNE_SN`) —
the full register is in [Julia Compatibility](reference_julia_compat.md):

```julia
x + y; x - y; x * y; x / y
-x; abs(x); inv(x); sqrt(x)
exp(x); exp2(x); expm1(x)
log(x); log2(x); log1p(x)
sin(x); cos(x); tan(x)
asin(x); acos(x); atan(x); atan(y, x)
sinh(x); cosh(x); tanh(x)
min(x, y); max(x, y); clamp(x, y, z)
fma(x, y, z); muladd(x, y, z)
```

## Arrays

Every registered operation has elementwise array methods:

```julia
A = T.([1.0, 1.5, 2.0])
B = T.([0.25, 0.5, 0.75])

C = Add(T, ρ, A, B)
E = Exp(T, ρ, A)
F = FMA(T, ρ, A, B, C)

C = vmap(:Add, T, ρ, A, B)
vmap!(C, Val(:Add), T, ρ, A, B)
```

Operands and destination must have matching axes. For table-eligible K ≤ 8
formats, deterministic unary/binary operations use cached result tables and
affordable ternary signatures may also use tables. Wider signatures compute
directly. Stochastic operations always compute each element and consume one draw
per projection.

```julia
table_bytes()
empty_tables!()
```

## Blocks and scaled operations

```julia
FS = Binary8p1uf
FE = Binary8p4se

b = Block(FS(4.0), FE(1.5), FE(-0.75), FE(2.0), FE(0.5))

blocksize(b)
scaleformat(b)
elemformat(b)

ConvertFromBlock(T, ρ, b)
BlockReduceAdd(T, ρ, b)
BlockReduceMultiply(T, ρ, b)
BlockDotProduct(T, ρ, b, b)
```

Every scalar operation except `Convert` has generated block and scaled forms:

```julia
BlockAdd(T, ρ, b1, b2, result_scale)
BlockExp(T, ρ, b, result_scale)

ScaledAdd(T, ρ, scale1, x1, scale2, x2)
ScaledExp(T, ρ, scale, x)
```

Quantize against a supplied or automatically selected scale:

```julia
ConvertToBlock(FS, FE, ρ, values_tuple, scale)
ConvertToBlockMaxAbsFinite(FS, FE, scale_ρ, element_ρ, values_tuple)
```

`BlockVector` stores many equal-shape blocks in a structure-of-arrays layout.

## Packed storage

```julia
v = Binary5p2se.([0.5, 1.0, 1.5, 2.0])
pv = PackedVector(v)

pv[2]
pv[2] = Binary5p2se(0.75)
collect(pv)

out = vmap(:Exp, Binary5p2se, ρ, pv)
```

`PackedVector` stores each code point in exactly `bitwidth(F)` bits. Computation
unpacks tiles internally; packed arithmetic is deliberately not in-place.

## Conformance and approximations

```julia
conformance()
conformance_dict()
conformance_report()
draft_revision()
draft_identity()

κ, exhaustive = measure_kappa(fn, :Exp, T, (T,), ρ)
register_approx!(:fast_exp, :Exp, T, (T,), ρ, fn; κ)
impl = approx(:fast_exp)
kappa(impl)
kappa_measured(impl)
list_approx()
unregister_approx!(:fast_exp)
```

Approximate implementations are never substituted into the default API.

## Common missteps

| Misapplication | Correct pattern |
|:---|---|
| Treating an `Unsigned` as a number | `T(Int(c))` for a numeric integer; `T(c::Unsigned)` for a code point — at every width |
| `Vector{Binary{K,P,Σ,Δ}}(undef, n)` | **Silently boxes every element** — the abstract format is not `isbits`. Use `Vector{Binary8p4se}` or `Vector{format(K,P,Σ,Δ)}`. `similar` normalizes; `Vector{…}(undef, n)` cannot be intercepted |
| Silently mixing formats | Convert explicitly: `Convert(T, ρ, x)` |
| Assuming `SatNone` always clamps | Choose `SatFinite` when clamping is required |
| Expecting IEEE division-by-zero | P3109 semantics here define `x / 0 → NaN` |
| Expecting negative zero | Every format has one zero; `T(-0.0) === zero(T)` |
| Expecting `sort` to put NaN last | The draft's total order puts the single NaN **first**, below −Inf (§4.12.1) — the opposite end from `Float64` |
| Passing a `Rational` | Convert explicitly to an exact supported carrier or knowingly to `Float64` |
| Reproducibility with stochastic rounding | Supply a seeded `rng`, or an explicit `R` in tests |
| Using the internal unchecked constructor | Prefer validated `T(c::Unsigned)` outside kernels |

Symptom-first versions of these, with the error text you would actually see, are
in [Troubleshooting](help_troubleshooting.md).

## Performance checklist

- Keep format types and projection specs in `const` bindings, function arguments,
  or type parameters.
- Put code using runtime-selected formats behind a function barrier.
- Expect the first deterministic array call for a specialization to build a table;
  benchmark warm calls separately.
- Use `PackedVector` when storage bandwidth matters more than direct byte access.
- Use `table_bytes()` to inspect cache footprint and `empty_tables!()` to reset it.
- Do not replace explicit projection semantics with `@fastmath`.

The reasoning behind each is in the [Performance Model](concept_performance.md);
the measurement rules are in
[Verification Strategy](internals_verification.md).

---

For worked applications, continue to the [Examples Index](examples_gallery.md).
For correctness and benchmark methodology, continue to
[Architecture](internals_architecture.md).
