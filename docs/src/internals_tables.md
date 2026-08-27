# Function Tables and Array Kernels

Tables are a cache for defined scalar semantics, not a second arithmetic
implementation. For a pure projection specification, a unary or binary
operation is a finite function on code points. When the policy admits that
function, SmallFloats builds it through the scalar path once and gathers from it
thereafter. When the policy declines it, the kernel calls that same scalar path
per element. The choice changes cost; it must never change a code point.

## Two representations, two concrete caches

A table entry is a result code point. `Code8` results therefore use
`Memory{UInt8}` and `Code16` results use `Memory{UInt16}`. The package keeps
separate caches rather than a `Union`-typed cache, so the representation is
chosen by dispatch before the hot loop indexes its local memory.

```text
pure ρ + admitted table  → Shape A: gather from Memory{codeunit_type(fr)}
stochastic ρ or declined table → Shape B: compute one defined scalar result
```

The branch happens once per array call, not once per element. `table_policy`
reports the chosen shape, estimated entries and bytes, and the reason; it is the
right diagnostic when an array call takes the compute path.

## Admission is a resource policy

The table policy has separate limits for memory and build time. The byte budget
accounts for the result code-unit width, so a `Code16` table with the same
number of entries as a `Code8` table occupies twice the storage. The eager
build limit bounds first-call latency rather than pretending that every table
that fits in RAM is useful to build.

Unary and binary pure-spec tables are admitted only within both limits. Ternary
tables have a third, reuse-sensitive policy:

- **Eager band.** Small ternary signatures build on their first array call.
- **Adaptive band.** Medium signatures accumulate use and build only after they
  have processed enough elements to amortize construction; the cache is
  byte-bounded and least-recently-used tables may be evicted.
- **Compute band.** Larger signatures remain Shape B.

These are current policy knobs, not semantic limits. `table_policy` and the
cache-accounting API expose them so a benchmark or application can report what
actually happened instead of inferring it from a timing.

## Why Shape A and Shape B agree

One table entry is one call through `_scalar_code`. Shape B reaches that same
defined scalar route with the element's decoded operands. The table builders and
compute kernels are therefore two scheduling strategies for the same operation,
and the verification gates compare them wherever a table is affordable.

This matters most outside the byte-sized sweet spot. A `Code16` format can still
participate in an affordable unary or mixed-width table; it is not categorically
“compute only.” Conversely, a byte format can take Shape B when its arity,
signature, projection, or cache policy makes a table unsuitable. Describe the
actual signature and `table_policy` result, never a broad K-only slogan.

## Threading and stochastic calls

Large pure-spec table builds partition independent output regions. Pure Shape-B
loops may also thread when the index set, element count, and runtime thread
configuration meet the kernel policy. The safety argument is concrete: each
pure entry is independent, and exact fallback state is task-local.

Stochastic projection remains sequential. It consumes one RNG stream in index
order, and preserving a seeded experiment's result takes priority over a
scheduler-dependent speedup.

## Sorting belongs to the same performance story

Same-format comparisons use integer order keys, not decoded floating values.
The key type is representation-aware (`UInt16` for `Code8`, `UInt32` for
`Code16`) and reserves zero for the NaN that P3109 orders first. Counting sort
is available when the input is large enough to amortize its key-space setup;
smaller inputs use Base's ordinary sort. This is another policy decision whose
semantics are the total order, not a timing claim.

## Evidence and extension seam

`src/tables.jl` owns keys, budgets, cache lifecycle, and table construction;
`src/kernels.jl` owns Shape-A gathering and Shape-B execution. A change is
complete only when it preserves concrete code-unit storage, byte accounting,
scalar/table equivalence, stochastic ordering, and the relevant threaded versus
sequential result checks. Record cold build, warm hit, and compute-path results
separately in [Performance Evidence](examples_performance.md).

## See also

[Technical Guide](technical_guide.md),
[Encoding and Decoding](internals_encoding_decoding.md),
[Performance Model](concept_performance.md), and
[Verification Sessions](examples_verification.md).
