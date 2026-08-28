# Reading the FloatBytes Internal Model

*User information for [`ModelTogether.md`](ModelTogether.md).*

`ModelTogether.md` describes how FloatBytes.jl keeps one numerical meaning while
supporting different storage forms, rounding policies, stochastic execution,
and performance strategies. This guide explains how to read that model without
requiring knowledge of its implementation internals.

---

## 1. The short version

FloatBytes treats every operation in two stages:

```text
What result is correct?       How should this workload run?
         |                               |
         v                               v
   semantic kernel                 prepared executor
         |                               |
         +------------ exact code -------+
```

The first stage is allowed to determine bytes. The second is allowed to change
only speed, allocation, storage access, and scheduling.

Five ideas explain almost the whole model:

1. A `FloatByte` value is one byte, but its Julia type says which P3109 format
   the byte belongs to.
2. A `BoundCall` completely names an operation's meaning: operation, operand and
   result formats, projection policy, entropy contract, and semantic revision.
3. Evaluation produces enough exact evidence to construct a `CodeRule`.
4. A prepared executor chooses an efficient way to realize that same rule over
   scalar, dense, packed, threaded, or reduction storage.
5. Independent assurance checks code identity, not approximate numerical
   closeness.

If you retain one sentence, retain this one:

> Changing a prepared executor may change cost; it may never change result
> bytes.

---

## 2. Which document should I read?

| question | read |
|:---|:---|
| Why is FloatBytes limited to `3 <= K <= 8`? | `PlanTogether.md` §§1–2 |
| What is the implementation roadmap? | `PlanTogether.md` §§14–19 |
| What states and transitions should the code implement? | `ModelTogether.md` §§3–11 |
| How does exact or stochastic projection work? | `ModelTogether.md` §§7–8, 12 |
| How do tables, packed storage, or reductions fit? | `ModelTogether.md` §§13–15 |
| How can an optimization be admitted safely? | `ModelTogether.md` §§10, 17 |
| What errors and guarantees should a caller expect? | this guide §§8–10 |

The model improves several claims in the plan. Where they differ, use
`ModelTogether.md` for implementation details, especially stochastic evidence,
transactional bulk execution, exact reductions, and verification scope.

---

## 3. A plain-language walk through one operation

Suppose `x` and `y` are values in the same eight-bit format and you request
nearest-even addition.

1. FloatBytes binds the request to the current semantic revision. Nothing about
   array size, CPU, or thread count is included in this meaning.
2. It compiles an addition kernel that understands the operand format and the
   nearest-even projection.
3. For a scalar call, the kernel classifies special codes, evaluates the finite
   sum, constructs a fixed result rule, and returns its byte.
4. For a large array, preparation may choose the same integer kernel or a
   verified lookup table.
5. Before writing an array result, FloatBytes validates shapes, aliasing,
   workspace, code trust, and entropy requirements.
6. The executor then enters a small byte loop. It does not reconsider formats,
   rounding policy, or execution strategy per element.

The scalar and array routes are permitted to have different costs. Assurance
requires their bytes to agree for the same logical inputs.

---

## 4. Terms you will encounter

### `FloatByte`

A one-byte primitive numerical value. The type parameters identify its format;
the stored byte is its code point.

Use numeric construction when you mean a number and `fromcode` when you mean an
encoded code point:

```julia
x = T(1.25)             # numeric conversion under the documented default
y = fromcode(T, 0x2a)   # explicit code identity
codepoint(y)             # returns UInt8
```

Raw `reinterpret` into `FloatByte` is unsafe because it can fabricate nonzero
high bits for formats narrower than eight bits.

### `BoundCall`

The complete immutable meaning of one operation. It includes every fact allowed
to affect bytes and excludes every fact that should affect only performance.

Users normally create it indirectly through `apply` or `prepare`.

### exact evidence

Internal information sufficient to make the requested projection decision. It
may be an exact dyadic value, quotient and remainder, integer-root remainder,
rigorous enclosure, or a proved finite window.

"Exact evidence" does not always mean that the whole mathematical value is
stored. It means the retained information is proved sufficient for the specific
projection policy.

### `CodeRule`

The result of projection before stochastic entropy is resolved.

- `FixedCode` means the result byte is already determined.
- `ThresholdCode` means one declared entropy word chooses exactly between the
  neighbouring result codes.

This distinction is why a stochastic lookup is a decision table rather than an
ordinary result-byte table.

### `Prepared`

An immutable executable choice. It owns any table or other immutable resource,
records workspace and entropy requirements, and exposes `PlanTraits` for
inspection.

A prepared executor cannot change numerical meaning.

### semantic digest

A compact identity derived from the draft revision, format catalogue, operation
meaning, projection rules, and entropy contract. Tables, executors,
certificates, and reports carry it so stale material cannot silently run.

### coverage domain

The exact set covered by a verification claim: formats, code tuples,
operations, result formats, policies, entropy words, layouts, and partitions.

"Exhaustive" applies only to the named domain.

---

## 5. Deterministic and stochastic calls

### Deterministic

For nearest, directed, odd, and other deterministic policies, projection
produces one `FixedCode`. A unary table can therefore store one byte for each
input code.

### Stochastic

A stochastic result depends on both exact numerical position and one logical
entropy word. A single sticky bit usually cannot preserve that probability.
FloatBytes therefore retains exact residual or cutoff evidence for the declared
word width.

Indexed stochastic execution identifies a word by:

```text
seed + stream + invocation + logical result index + projection slot
```

Changing thread count, chunks, SIMD width, or packed layout does not change the
logical index. Results are reproducible across those execution shapes.

Exact and special stochastic results still own a logical word. The word is
ignored, but keeping the slot prevents input data from shifting the entropy
sequence of later results.

`SequentialEntropy(rng)` is supported for conventional RNG use, but it chooses
a sequential executor because mutable consumption order is observable.

---

## 6. Why prepare an operation?

You do not need to prepare occasional scalar arithmetic. Preparation matters
when work repeats or storage is nontrivial.

Conceptually:

```julia
call = signature(Add, ResultFormat, policy, OperandFormats...)
plan = prepare(call; layout=:dense, count=length(xs), reuse=:many)
execute!(dest, plan, xs, ys)
```

Preparation can:

- validate the complete call;
- choose direct computation or a table;
- finish rigorous unary table construction;
- choose dense, generic, packed, or reduction traversal;
- select indexed or sequential entropy handling;
- determine workspace and alias rules;
- choose threading or SIMD when certified and worthwhile;
- expose its assumptions through `plan_traits(plan)`.

Preparation is not an optimizer that may alter answers. It chooses among
byte-equivalent realizations.

Useful traits include executor kind, workspace bytes, entropy origin, alias
rules, expected allocations, preparation cost, estimated break-even, and
certificate identity.

---

## 7. Performance expectations

FloatBytes is designed around a cold/hot split.

Cold work may include request validation, table construction, rigorous MPFR
enclosures, cost selection, certificate checks, and error construction.

Warm execution should contain only byte loads, a concrete finite or special
kernel, projection-rule resolution, and byte stores. It should not perform
catalogue lookup, mutable-default lookup, table admission, or strategy choice.

The fastest realization depends on the workload:

| workload | likely starting choice |
|:---|:---|
| ordinary finite algebra over dense bytes | integer compute kernel |
| deterministic unary elementary function | 256-byte lookup table |
| stochastic operation | exact rule kernel plus indexed entropy |
| unusual Julia array | generic traversal |
| exact dot/reduction | fixed-limb exact accumulator |
| packed memory-bound data | tiled unpack/execute/repack, if measured useful |

Tables are not automatically faster. Build time, cache size, element count,
reuse, thread count, and CPU all matter. `prepare` uses explicit workload facts;
it does not promise that a 64 KiB binary table always wins.

FloatBytes also budgets compilation: first-call latency, method instances,
invalidations, native-code size, and package image size matter alongside
nanoseconds per element.

---

## 8. Failure and destination safety

Bulk work is split into preflight and commit.

Preflight can reject:

- an unsupported operation/format/policy combination;
- invalid raw code bytes;
- incompatible shapes or axes;
- unsafe aliasing;
- missing or undersized workspace;
- missing entropy or an invalid logical origin;
- a sequential RNG request combined with threaded execution;
- a stale or corrupt table/certificate;
- a rigorous construction that cannot decide within its resource budget.

These failures occur before the first destination write.

After preflight, the ordinary commit path does not perform work that can become
inconclusive. A rare executor unable to guarantee this must stage its complete
result before copying it to the destination.

Unexpected process, memory, compiler, or internal invariant failures cannot be
made transactionally safe by a numerical package; they are reported distinctly
from supported runtime errors.

---

## 9. Correctness and verification

FloatBytes compares exact code identity:

```text
independent reference
    == semantic kernel
    == lookup/direct implementation
    == dense/generic/threaded/SIMD/packed/reduction execution
```

The primary independent reference uses rational/BigInt logic and directed MPFR
intervals without importing production semantics. SmallFloats is a second,
version-pinned differential source during construction.

The model distinguishes:

- **exhaustive** — every case in a stated finite domain was checked;
- **proved** — a stated theorem/certificate covers the domain;
- **sampled** — selected cases were measured.

A sampled result is never presented as an exhaustive bound. Large numbers such
as 176 million code pairs describe only the axes explicitly counted; operations,
result formats, policies, and entropy may multiply the actual semantic domain.

Diagnostic `explain` traces are useful when a mismatch occurs, but they are not
independent evidence because they share production implementation.

---

## 10. Approximation

Defined and approximate calls are separate. Ordinary `apply`, Base arithmetic,
and defined prepared execution cannot silently select an approximate kernel.

An approximate executor must be explicitly requested and carry a certificate
naming:

- the related defined call and semantic revision;
- candidate implementation digest;
- metric and maximum observed/proved code distance;
- special-value behavior;
- exhaustive, proved, or sampled scope.

This lets users choose a measured approximation without weakening the meaning of
defined FloatBytes operations.

---

## 11. Cross-format arithmetic and promotion

Implicit FloatByte-to-FloatByte promotion is deliberately avoided. There is no
obvious canonical result format for two different P3109 formats.

- Same-format Base arithmetic uses the immutable documented default policy.
- Explicit `apply` names a result format and policy.
- Mixed Julia numeric arithmetic promotes to Float64, which represents every
  FloatByte datum exactly.
- Projecting a Float64 result back to FloatByte is explicit.

A scoped context, if provided, affects only a separately named context-aware
adapter. It does not silently change ordinary Base operator meaning.

---

## 12. Raw bytes, packed data, and trust

A typed FloatByte array is already one byte per element. Dense execution can
obtain a zero-copy byte view once and then operate on raw bytes internally.

Foreign `UInt8` storage must be checked before it becomes trusted. For `K < 8`,
nonzero high bits are invalid. The package does not repeat that check inside a
trusted hot loop.

Packed storage saves memory for `K < 8`, but packing and unpacking have costs.
FloatBytes uses reusable tiles and admits packed execution based on end-to-end
measurements. For `K = 8`, packed storage is simply a byte view.

Unused tail bits in packed storage are zeroed so equality and hashing are stable.

---

## 13. Reading the diagrams

An arrow means a valid state transition, not necessarily a function call.

```text
CallRequest -> BoundCall
```

means validation succeeded and semantic revision was frozen. An invalid request
does not produce a half-valid `BoundCall`.

```text
evidence -> CodeRule -> UInt8
```

means evaluation and projection are distinct. The first arrow chooses
neighbouring code behavior; the second resolves deterministic or entropy-based
choice.

```text
Prepared -> preflight -> commit
```

means no destination mutation happens until all ordinary failures have been
excluded.

Dashed or prose-described alternatives are implementation choices. They do not
imply different numerical semantics.

---

## 14. Questions to ask during review

When reviewing a change, ask:

1. Does this fact belong to semantic identity or operational circumstances?
2. What exact evidence does this evaluator preserve?
3. Is that evidence sufficient for this projection and entropy width?
4. Is projection occurring exactly once?
5. Can this failure happen after destination mutation begins?
6. Does an optimized adapter name its exact applicability and certificate?
7. Is an exhaustive claim explicit about every axis it covers?
8. Does this type parameter materially improve generated code or layout?
9. Can changing threads, tiles, or storage change logical entropy identity?
10. If this module were deleted, would its knowledge spread across callers?

These questions are often more useful than asking whether one benchmark became
faster.

---

## 15. Frequently asked questions

### Is `CodeRule` visible in normal use?

No. It is an internal model value. Users receive `FloatByte` results or prepared
executors.

### Why not use Float64 for every operation?

Float64 represents every individual datum exactly, but does not by itself retain
all information needed after arithmetic, especially for directed and stochastic
projection. Integer evidence and rigorous enclosures make the required decision
explicit.

### Why not table every operation?

Unary deterministic tables are tiny. Binary and ternary tables can cost more to
build and more cache capacity than their saved arithmetic repays. The model lets
preparation choose without making tables the source of semantics.

### Does stochastic execution produce the same bytes on every run?

With the same indexed entropy identity, inputs, semantic revision, and logical
origin, yes—even if scheduling changes. A sequential external RNG follows its
own stream state and therefore uses sequential execution.

### Can an optimization use hardware floating point?

Yes, if its exact applicability domain is certified byte-for-byte. Otherwise it
must be requested as an explicit approximate executor.

### Can a prepared executor become stale?

Its semantic digest and owned resources make staleness detectable. Loading an
artifact or certificate from another semantic revision is rejected.

### Why is the reduction design conservative?

Exact mergeability is what makes results independent of thread partitioning.
Fixed-limb accumulators provide that property directly. Faster restart windows
may be added after proving the same behavior.

### Does `K <= 8` mean every path is a single UInt64 operation?

No. It makes very compact evidence possible, but stochastic residuals,
quotients, square roots, elementary functions, and long reductions still need
their appropriate exact or rigorous representations.

---

## 16. Practical reading paths

### Package user

Read this guide §§1, 3, 5–8, 10–12. You mainly need to understand explicit code
construction, preparation, stochastic identity, and error timing.

### Numerical reviewer

Read `ModelTogether.md` §§5–8, 12, 15, 17, and 21. Focus on evidence capability,
projection rules, entropy, reduction mergeability, and coverage domains.

### Performance implementer

Read `ModelTogether.md` §§9–14, 18–20, and 24. Focus on function barriers,
preflight/commit, adapter offers, table admission, and type-versus-value budgets.

### Julia interface maintainer

Read `PlanTogether.md` §§4, 12 and `ModelTogether.md` §§4–6, 10–11, 18. Preserve
explicit code identity, fixed Base behavior, concrete arrays, robust `show`, and
phase-specific errors.

### Assurance maintainer

Read `ModelTogether.md` §§7–8, 16–18, 20–21. Treat every certificate as a claim
over a named domain, and keep production traces separate from independent
authority.

---

## 17. Final mental model

```text
You state meaning once:
    operation + formats + projection + entropy

FloatBytes proves what evidence that meaning requires:
    exact dyad | exact remainder | rigorous enclosure | certified law

Projection compiles the evidence into a code decision:
    FixedCode | ThresholdCode

Preparation chooses how to run it:
    compute | lookup | generic | packed | threaded | exact reduction

Preflight makes the run safe:
    codes + shapes + aliasing + workspace + entropy + revision

Commit moves bytes:
    same meaning, no further choices
```

That is the purpose of the model: flexibility is resolved before the hot loop,
and every flexible route is required to preserve one explicit numerical meaning.
