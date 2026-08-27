# Assurance

When two runs disagree, exactly three causes are legitimate: the policy
changed, the policy itself requests randomness, or a registered approximation
was selected. Anything else is a defect. This chapter provides the tools
that make that determination and the records that support it: the provenance
test, the measured-approximation registry, the exportable conformance
declaration, and a summary of how the defined path is verified.

## The provenance test

When two runs differ, check in order:

1. Did the operation, result format, or projection specification change?
2. Is the projection stochastic, and did the draw or RNG stream change?
3. Did the call explicitly select a registered approximation?
4. Did process-global defaults change between calls?

If all four answers are no, a changed code point is a defect and should be
reported as one. For experiments that must be reproducible, record the
result format, the projection specification, the RNG algorithm and seed, and
any approximation's name and measured bound alongside the results.

## Measured approximation

The default API never substitutes an approximation. A faster, inexact
kernel enters only through the registry, and the registry measures its
worst-case deviation — in code points along the total order, exhaustively
where the input space permits — rather than accepting a declared figure:

```julia-repl
julia> one4 = Binary8p4se(1.0);

julia> hardtanh(x) = Clamp(Binary8p4se, RNE_SN, x, Negate(one4), one4);

julia> κ, exhaustive = measure_kappa(hardtanh, :Tanh, Binary8p4se,
                                     (Binary8p4se,), RNE_SN)
(4.0, true)                # worst deviation: 4 code points, all 256 inputs checked
```

A declaration that understates the measurement is rejected, and no partial
registration state remains:

```julia-repl
julia> register_approx!(:hardtanh_act, :Tanh, Binary8p4se,
                        (Binary8p4se,), RNE_SN, hardtanh; κ=1)
ERROR: ArgumentError: declared κ = 1.0 understates measured κ = 4.0 — registration rejected
```

Registered with a truthful bound, the implementation is retrieved by name
(`approx`, `list_approx`), its κ is queryable, and it appears in the
conformance declaration automatically. Code-point bounds also support
decision rules: two defined results more than 2κ apart cannot have their
comparison inverted by the approximate evaluator, which makes pruning with a
cheap evaluator provably sound.

## The conformance declaration

`conformance()` returns a live statement of the session: formats,
operations, mode vocabulary, the table specializations built so far, and
every registered approximation. `conformance_dict()` is the plain-`Dict`
form for JSON or TOML export:

```julia
d = conformance_dict()
(d["package"], length(d["formats"]), length(d["operations"]),
 [s["op"] for s in d["cached_specializations"]])
```

```
("SmallFloats.jl 0.4.0", 504, 52, Any[])
```

The first three entries are package properties: 504 formats, 52 operations,
always. The fourth is session-dependent — empty here because this session
had made no array call yet — so snapshot the declaration after the work,
not at the top of a script. `draft_revision()` reports the implemented
draft revision (`IEEE P3109/D1, uploaded 2026-07-17`); include it with any
exported artifact.

## Verifying your own code

The same exhaustive method is available to application code, because format
input spaces are small enough to enumerate. A stochastic-rounding
distribution, for example, is checkable exactly rather than statistically:
the value 2 + 3/64 sits at fraction 3/16 of an ulp, so `StochasticA{4}`
must round it up for exactly 3 of the 16 draws —

```julia
σ4 = RSA_SN(4)
x = 2.0 + 3/64
count(decode(SmallFloats.project(Binary8p4se, σ4, x; R)) == 2.25 for R in 0:15)
```

```
3
```

Sweeping `R` turns a statistical question about bias into an exhaustive one.

Ordering guarantees are checkable the same way. Ranking and decision systems
consume scores through order, so a conversion between formats must be
monotone — and with a few hundred datums per format, that is provable by
walking every value in total order and confirming its image never goes
backward:

```julia
using SmallFloats: order_key

function monotone_conversion(::Type{From}, ::Type{To}) where {From,To}
    prev = nothing
    for v in sort(From.(0x00:UInt8(2^bitwidth(From) - 1)))
        isnan(decode(v)) && continue
        g = Convert(To, RNE_SN, v)
        prev !== nothing && order_key(g) < order_key(prev) && return false
        prev = g
    end
    true
end
monotone_conversion(Binary8p3se, Binary8p4se)
```

```
true
```

A ranking pipeline whose conversions all pass this audit cannot invert a
preference by changing formats. The same pattern — enumerate the inputs,
compare against an independently computed reference — verifies quantizers
and custom fused kernels; the full manual's Verify Custom Code page gives
worked recipes.

## How the defined path is verified

The test suite enumerates rather than samples wherever the input space
allows, and reports "sampled" explicitly where it does not. Because formats
are finite, most correctness claims are checked by exhaustion: every code
point of every format round-trips; cached tables compare entry-for-entry
with the scalar path; the optimized rounding core compares against the
generic one; and two independent high-precision references
(`Float128`-first and pure-MPFR builds) must agree bit-for-bit. Disabling
the `Float128` machinery (`ENV["SmallFloats_Float128"] = "disable"`) is
itself a tested equivalence: identical results, different speed.

Structurally, there is one write path. Every code point the package
produces passes through `RoundToPrecision → Saturate → Encode`, fed by
exact arithmetic on a carrier the format selects — `Float64` where exact,
`Float128` above it, an exact dyadic carrier for the widest formats, with
MPFR enclosures deciding the remainder. No second rounding routine exists,
and nothing approximate is reachable outside the registry. The full
manual's Technical Guide covers the architecture, the oracle's rigor
classes, and the verification gates in detail.

## Next

[Quick Reference](reference.md) collects the names and signatures from all
four chapters in brief.
