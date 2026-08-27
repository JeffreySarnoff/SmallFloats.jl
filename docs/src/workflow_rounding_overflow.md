# Control Rounding and Overflow

Two questions have to be answered before a computation is reproducible: where
a between-grid value lands, and what happens when a result leaves the format's
range. This workflow names both in the call rather than inheriting them from
session state, and then tests that the choice does what you expect at the
cases where the modes actually disagree.

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
Binary8p4se(3.5 ⇆ 0x4e)
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

1.6 sits between 1.5 and 1.625, closer to 1.625. Four modes land on 1.625
(both nearest modes, toward-positive, and to-odd); toward-negative and
toward-zero land on 1.5 — they agree here only because the value is positive.

That is why one value is not a policy test. This value is not a tie, so the
two nearest modes cannot be told apart by it, and it is positive, so
toward-zero and toward-negative cannot be told apart either. Include a tie, a
negative value, and a value near a binade boundary before concluding anything
about a mode.

## Test positive and negative overflow

```julia-repl
julia> w, two = Binary8p4se(200.0), Binary8p4se(2.0);

julia> Multiply(Binary8p4se, RNE_SN, w, two)
Binary8p4se(Inf ⇆ 0x7f)

julia> Multiply(Binary8p4se, RNE_SF, w, two)
Binary8p4se(224.0 ⇆ 0x7e)
```

Note that `w` holds 192.0, not 200 — 200 ties between 192 and 208 and
construction already rounded it. The exact product is therefore 384, past the
largest finite datum, 224.

Repeat the check for a negative result: `-192 × 2` gives `-Inf` under `RNE_SN`
and `-224.0` under `RNE_SF`, mirroring the positive case. Repeat it again for
an unsigned result format if you use one. Saturation behavior depends on
domain, signedness, direction, and the rounded classification; "overflow
clamps" is not a sufficient policy description.

## Keep policy local

Prefer explicit forms in libraries and experiments:

```julia
Multiply(F, RNE_SF, x, y)
```

The `with_default_*` combinators efficiently pass the current process-global
default to a function; they do not create a scope or restore anything. Use
explicit `T` and `ρ` arguments whenever numerical policy must be local.
Process-global setters are convenient for controlled REPL setup, but their
effects are persistent and shared by all tasks in the process.

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

## See also

[Projection Specifications](reference_projections.md).
