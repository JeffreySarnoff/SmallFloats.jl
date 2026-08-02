# Control Rounding and Overflow

Use this workflow when a computation must name how between-grid values round
and how out-of-range values are handled. The result format and projection spec
should be visible in any code whose numerical policy matters.

## Select the result format

The result format is the first argument to a spec-named operation:

```julia
F = Binary8p4se
x, y = F(1.625), F(1.75)
```

Do not rely on cross-format promotion to choose a destination. Convert operands
explicitly before combining formats.

## Select a deterministic projection

Projection specs combine one rounding mode with one saturation mode. The
predefined names use `ROUND_SATURATION`:

```julia-repl
julia> x, y = Binary8p4se(1.625), Binary8p4se(1.75);

julia> Add(Binary8p4se, RNE_SN, x, y)
Binary8p4se(3.5 ≡ 0x4e)
```

`RNE` is nearest, ties to even. `SN` is `SatNone`, the draft's
domain- and direction-dependent boundary policy. Use `SF` when the application
requires a finite clamp. Use `SP` when representable infinities should
propagate according to `SatPropagate`.

## Test a between-grid case

Choose a value that cannot be represented and compare the policies you intend
to support:

```julia
z = 1.6
[(ρ, decode(Convert(Binary8p4se, ρ, z))) for ρ in
 (RNE_SN, RNA_SN, RTP_SN, RTN_SN, RTZ_SN, RTO_SN)]
```

Do not infer a rounding mode from one ordinary value. Include a tie, a negative
value, and a value near a binade boundary in a policy test.

## Test positive and negative overflow

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)
Binary8p4se(Inf ≡ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)
Binary8p4se(224.0 ≡ 0x7e)
```

Repeat the check for a negative result and, if relevant, an unsigned result
format. Saturation behavior depends on domain, signedness, direction, and the
rounded classification; “overflow clamps” is not a sufficient policy
description.

## Keep policy local

Prefer explicit forms in libraries and experiments:

```julia
Multiply(F, RNE_SF, x, y)
```

For a scoped region of exploratory code, use a `with_default_*` combinator
rather than mutating a default and remembering to restore it. Process-global
setters are convenient at the REPL and shared by all tasks in the process.

## Validate the complete boundary

For small formats, enumerate all code points and test the operation under each
supported projection. At minimum assert:

- exact-grid inputs remain exact;
- ties land according to the named rule;
- positive and negative out-of-range results follow the selected saturation;
- NaN and infinity cases follow the operation's P3109 rows;
- scalar and array forms return the same code points.

## What can go wrong

!!! warning "SatNone does not mean finite clamp"
    `SatNone` means that neither of the two simplifying saturation policies was
    selected. It applies the draft's full boundary rows and can produce an
    infinity, an extremal finite value, or NaN depending on the case.

!!! warning "A default is state, not a declaration"
    A default setter changes process-global state. Name the projection in code
    that must be reproducible or safe under concurrency.

## Understand it

[Rounding and Saturation](concept_rounding_saturation.md) and
[The Exact-Then-Project Contract](concept_exact_then_project.md).

## Look it up

[Projection Specifications](reference_projections.md).
