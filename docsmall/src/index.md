# SmallFloats.jl

*A compact guide to the package. The
[full manual](https://JeffreySarnoff.github.io/SmallFloats.jl) covers
workflows, complete reference tables, and implementation detail.*

SmallFloats.jl implements the IEEE P3109 draft standard, *Arithmetic Formats
for Machine Learning*. It provides all 504 legal formats at bitwidths 3
through 16, with bit-exact defined results and explicit control over rounding
policy.

In formats this small, most operations round: the numbers you construct and
the results you compute are usually not representable. The package makes the
rounding visible and controllable rather than implicit. Three definitions
carry the whole model:

- A **format** is a finite set of exact values, called *datums*, each named
  by an integer *code point*.
- A **value** stores one code point. Reading the datum back with `decode` is
  always exact.
- An **operation** decodes its operands, computes the exact mathematical
  result, and applies one *projection* — a rounding choice plus a saturation
  choice — to produce the result code point.

Each chapter of this guide develops part of that model.

## Installation

Requires Julia 1.12 or later. The package is not yet registered; install by
URL:

```
pkg> add https://github.com/JeffreySarnoff/SmallFloats.jl
```

`Quadmath` (`Float128`) is a hard dependency. It is used only inside exact
oracle and fallback paths, never anywhere it could change a result.

## A first check

```julia-repl
julia> using SmallFloats

julia> Binary8p4se(1.6) + Binary8p4se(0.25)
Binary8p4se(1.875 ⇆ 0x47)

julia> conformance() !== nothing
true
```

The first line exercises the projection engine: 1.6 is not representable, so
construction rounds it to 1.625, and the sum lands exactly on 1.875. The
second line confirms the conformance machinery is available. Values in this
guide display as `value ⇆ code point`, showing both halves of every result.

## What the package guarantees

Four properties distinguish the package. They are stated plainly here and
developed in the chapters that follow.

**No hidden rounding.** An operation computes its exact mathematical result
and rounds it exactly once. There is no intermediate precision to
accumulate error inside an operation, and no fast path that substitutes a
different answer: the code point you receive is the one the standard
defines, every time.

**Reproducible policy.** The rounding rule is not something you must
remember about the session — it can be written into each call. Code that
names its rule produces identical results in every session, on every
machine.

**No silent approximation.** Faster, inexact implementations exist only if
you register one, by name. Registration measures the implementation's
worst-case error over every input and rejects any declared bound that
understates the measurement. Nothing approximate can be reached by
accident.

**One behavior at every size.** All 504 formats, from 3 bits to 16, follow
the same rules. A wider format costs more storage; it never means something
different.

## Contents

[Formats and Values](values.md): the format space, construction, and the
code-point rule. [Computing](computing.md): the projection contract and the
policy choices. [Data at Scale](data.md): choosing a format, arrays, blocks,
packed storage, and IEEE interop. [A Worked Example](worked_example.md): the
chapters composed into one measured quantization task.
[Assurance](assurance.md): conformance export, measured approximation, and
verification. Three lookups close the guide:
[Quick Reference](reference.md), [Troubleshooting](troubleshooting.md)
(symptom-indexed), and a [Glossary](glossary.md).
