# Glossary

One line per term, with the chapter that develops it.

| Term | Meaning | Chapter |
|:--|:--|:--|
| datum | One exact value in a format's finite set. | [Values](values.md) |
| code point | The integer naming a datum; what a value stores. | [Values](values.md) |
| code unit | The storage word for code points: `UInt8` at `K ≤ 8`, `UInt16` above. | [Values](values.md) |
| format | A finite datum set with an encoding: `Binary{K,P,SGN,EXT}`. | [Values](values.md) |
| alias | The concrete named subtype (`Binary8p4se`) code should use. | [Values](values.md) |
| binade | The span between consecutive powers of two; datum spacing doubles per binade. | [Values](values.md) |
| ulp | The datum spacing at a given magnitude (unit in the last place). | [Values](values.md) |
| projection | The single rounding-plus-saturation step from exact result to code point. | [Computing](computing.md) |
| `ProjSpec` | A named (rounding mode, saturation mode) pair, e.g. `RNE_SN`. | [Computing](computing.md) |
| `SatNone` | The draft's full boundary rows — not "no saturation". | [Computing](computing.md) |
| stochastic mode | Rounding whose landing depends on a random draw `R`; a defined distribution. | [Computing](computing.md) |
| session default | One of five process-global settings behind `+` and friends. | [Computing](computing.md) |
| datum carrier | The exact type `decode` returns: `Float64`, `Float128`, or dyadic. | [Values](values.md) |
| promotion carrier | Where `Binary` + ordinary number lands: `Float64`, or `BigFloat` for wide formats. | [Computing](computing.md) |
| defined result | The draft-required code point for an operation, format, and spec. | [Assurance](assurance.md) |
| table | A cached finite operation, entries produced by the scalar path. | [Data at Scale](data.md) |
| block / scale | `B` elements sharing one scale; each lane is `scale × element`. | [Data at Scale](data.md) |
| span filter | The integer test proving a `Float128` accumulation is exact. | [Data at Scale](data.md) |
| `PackedVector` | Storage at true bit width; compute unpacks internally. | [Data at Scale](data.md) |
| κ (kappa) | A registered approximation's measured worst-case error, in code points. | [Assurance](assurance.md) |
| total order | The draft's complete ordering; the single NaN sorts first. | [Values](values.md) |
| exhaustive | Checked over every member of the input space, as opposed to sampled. | [Assurance](assurance.md) |
