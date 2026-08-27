# SmallFloats.jl

*An exact, policy-visible Julia implementation of the IEEE P3109 small binary
formats, from 3- through 16-bit code points.*

In an 8-bit format almost every operation rounds: most numbers you construct,
and most sums and products you form, are not among the format's few hundred
values. The question that decides a small-float experiment is therefore not
*whether* rounding happened but *where, and under which policy* — and that is
exactly what most implementations hide. SmallFloats.jl keeps it visible: the
finite datum set, the rounding/saturation policy as a named argument, and the
one projection that turns each exact result back into a code point. All 504
legal formats are supported, byte-sized `Code8` representations and wider
`Code16` representations alike, without the storage difference ever entering
the arithmetic semantics.

```julia-repl
julia> using SmallFloats

julia> x = Binary8p4se(1.6)                 # construction projects a value
Binary8p4se(1.625 ⇆ 0x45)

julia> Add(Binary8p4se, RNE_SN, x, Binary8p4se(1.75))
Binary8p4se(3.5 ⇆ 0x4e)                     # exact sum, then one projection

julia> T = format(16, 6, true, true)        # a wider format is an ordinary format
Binary16p6se

julia> codeunit_type(T), SmallFloats.datumcarrier(T)
(UInt16, Float64)
```

The last line is an implementation-facing fact with a user-facing consequence:
the code point of a wide format need not fit in a byte, and `decode` returns
the exact carrier selected for the format rather than promising `Float64` in
every case. The value model itself stays the same.

## The promises

- **Defined results are exact, then projected once.** Construction, conversion,
  scalar operations, tables, and kernels all agree on `RoundToPrecision →
  Saturate → Encode` — one rounding, at the end. No path rounds twice, so no
  result drifts quietly from the draft's defined answer.
- **Policy is visible.** A `ProjSpec` names rounding and saturation in the call
  itself, so a line of code produces the same bits in every session that runs
  it — repeatability never depends on ambient state.
- **Approximation is declared and measured.** Approximate kernels are opt-in,
  retrieved by name, and carry a code-point error bound κ measured by
  exhaustive enumeration at registration time; a declaration that understates
  the measurement is rejected.
- **Representation does not weaken the datum contract.** `Code8` and `Code16`
  select storage, decode, and table policies; both represent the draft's finite
  datum sets exactly, so widening a format changes cost, never meaning.

## Documentation map

**New here?** Start with [Installation](install_and_verify.md), take the
[First Session](first_session.md), then read the [Core Model](core_model.md).
Those three pages establish the vocabulary used everywhere else.

**Using the package?** Follow the [User Guide](user_guide.md) through formats,
values, projection, arrays, blocks, storage, reproducibility, and Julia
interoperability. Use the [Cheat Sheet](help_cheat_sheet.md) only when you
already know the distinction you are looking up.

**Choosing or evaluating a format?** Begin with [Choose a
Format](workflow_choose_format.md), then [Quantize and Measure a
Tensor](workflow_quantize_measure.md). [Example Gallery](examples_gallery.md)
routes to runnable basic, AI, machine-learning, and deep-learning sessions.

**Maintaining or extending SmallFloats?** Read the [Technical
Guide](technical_guide.md). It follows a datum through representation, codec,
projection, oracle, tables, blocks, verification, and benchmarking before
pointing to the extension checklists.

**Looking up a contract?** The [Formats and Values](reference_formats_values.md),
[Projection Specifications](reference_projections.md), [Operation
Catalog](reference_operations.md), and [Julia Compatibility
Register](reference_julia_compat.md) are curated references. The public and
internal API indices are docstring inventories, not substitutes for the guides.

## Code point or number?

An `Unsigned` argument names a stored code point directly. Any other `Real`
argument is treated as a number and rounded to the format's nearest datum under
the active projection policy.

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ⇆ 0x02), Binary8p4se(2.0 ⇆ 0x48))
```

The same digit, two questions, answers a factor of 1024 apart — and neither
call is an error. `Convert(T, ρ, x)` projects whatever the argument's integer
type. [Values, Code Points, and Conversion](concept_values_codepoints.md) has
the complete rule.
