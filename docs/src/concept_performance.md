# Performance Model

Nothing in this package makes a result faster by making it different. Tables,
carrier selection, packing, and threading all schedule the same
exact-then-project computation; the code point never depends on which one ran.
That narrows performance work to two questions, in order: can Julia see the
format and projection at compile time, and does your signature qualify for a
table? Get the first wrong and you measure dynamic dispatch — roughly a
microsecond per call, swamping the operation entirely. The second decides
whether an array call gathers from memory or computes per element.

## Pass formats and policies statically

Give scalar code a concrete format type and, in a hot path, a concrete
projection specification. A function barrier is enough when a format arrives
at run time:

```julia
function add_one(::Type{T}, ρ, x, y) where {T<:Binary}
    Add(T, ρ, x, y)
end
```

This does not require every application to hard-code its format. It gives Julia
a point at which the type has become known, so calls inside the barrier can
specialize. A benchmark that reads a format from a non-`const` global measures
dynamic dispatch as well as the operation and cannot be used to compare codec,
projection, or carrier paths.

## Let the signature choose the array shape

For a pure projection, an array operation may be a Shape-A table gather or a
Shape-B scalar compute loop. Ask the package which one applies:

```julia-repl
julia> table_policy(:Add, Binary8p4se, Binary8p4se, Binary8p4se, RNE_SN)
(shape = :A, entries = 65536, bytes = 65536, reason = "within the 2^16-entry build band")
```

Read the answer as a budget decision. A same-format binary `Add` needs one
entry per operand pair — 256 × 256 = 65 536 entries at one byte each — which
fits the build band, so it gathers. A unary `Exp` on the same format needs 256
entries and fits easily. Change one format to `Code16` and the entry count
grows by 256×, which is what the budget exists to refuse.

The first Shape-A call may build a table; later calls can reuse it. Benchmark
cold construction and warm use separately. Shape B is not an error or a less
correct mode: it runs the same defined scalar semantics once per element and
may thread for long, pure-spec arrays.

Representation alone does not determine the shape. A `Code16` unary or
mixed-width signature can fit the current budget, while a larger or stochastic
signature may compute. Conversely, an all-`Code8` ternary signature can become
too large for an eager table. Use `table_policy`, not a K-only rule of thumb.

## Stochastic work preserves order

Stochastic projection consumes an RNG stream in index order. The corresponding
array paths stay sequential so a seeded run does not depend on thread
scheduling. Pass an explicit RNG when reproducibility is part of the
experiment; use a pure projection when independent per-element computation is
the desired performance case.

## Store packed; compute unpacked

`PackedVector{F}` stores code points at `bitwidth(F)` bits per element when
that saves space. It is useful for bandwidth and persistence, not an invitation
to perform arithmetic directly on packed bits. Kernels unpack the working data
they need and preserve the ordinary scalar/array semantics. `BlockVector`
provides the analogous layout for collections of same-shaped blocks.

## Sorting and measurement discipline

SmallFloats has a representation-aware counting-sort path for sufficiently
large homogeneous vectors; short inputs deliberately use the stock algorithm
because key-space setup can cost more than comparison sorting. NaN is first in
the forward P3109 total order and last under reverse order.

Treat timings, allocation counts, and thread scaling as measurements with a
scope, not universal package properties. Record the format, operation,
projection, input shape, Shape A/B decision, Julia version, thread count,
hardware, and cold/warm state. [Performance Evidence](examples_performance.md)
holds recorded results; [Benchmark Correctly](internals_benchmark.md) explains
how to obtain new ones without measuring dispatch or cache setup by accident.

## Do not use `@fastmath`

`@fastmath` is not a SmallFloats optimization strategy. The package's value is
that each defined result follows its stated semantic path, including NaN,
single-zero, and projection rules. If a workload is slow, make types static,
use an appropriate array call, inspect `table_policy`, or reduce storage
pressure with `PackedVector`; do not relax the semantics you are trying to
study.

## See also

[Function Tables and Array Kernels](internals_tables.md),
[Performance Evidence](examples_performance.md), and
[Benchmark Correctly](internals_benchmark.md).
