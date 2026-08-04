# SmallFloats with maximum K = 10

## A correctness-preserving architectural revision for substantially higher performance

*Design plan written 2026-08-04 against SmallFloats.jl 0.4.0 and the current
K = 3:16 implementation. This is a proposal, not a record of completed work.
The retained IEEE P3109/D1 transliteration remains the semantic authority. The
scope decision in this document is that the package implements every legal
format for `3 <= K <= 10`, and deliberately does not implement wider formats.*

---

## 0. Verdict

`KMAX = 10` is not merely a smaller version of the present architecture. It is
a useful mathematical boundary that permits a simpler and faster architecture:

1. Every datum of every supported format is exactly representable as
   `Float64`.
2. Every fixed-arity scalar operation in the draft has at most two datum
   factors, and its finite algebraic intermediate stays within Float64's
   exponent range.
3. Every binary input domain contains at most `2^20` operand pairs, so a whole
   binary specialization is enumerable under the existing `2^22` κ budget.
4. Every unary result table is at most 2 KiB and every binary result table is at
   most 2 MiB when results use `UInt16` code units.
5. The full format lattice is only 192 formats and 69,616 code points.
6. A format's total-order key space is at most 1,025 values, so `UInt16` is
   sufficient everywhere.

These facts justify a deep reworking around four modules:

- a **Format Domain** module that owns representation and exact Float64 decode;
- a **Defined Evaluation** module with one internal `defined_code` interface;
- the existing **Projection** module, retained as the single semantic write
  path;
- an **Execution Engine** that selects direct-code, dense-table, row-table, or
  compute adapters strictly by cost.

The central architectural change is to stop treating storage width, datum
carrier, oracle rigor, and array execution as variants of one problem. At
`KMAX = 10` they have cleanly different answers:

```text
storage       UInt8 or UInt16             representation only
decoded datum Float64                     always exact
fixed scalar  Float64-first result protocol
composition   Float128 workspace or derived-precision MPFR when needed
projection    canonical integer engine    one semantic write path
bulk work     chosen by an execution plan cost only
```

This design should materially reduce source complexity, inference load,
method-instance growth, first-use latency, and wide-format scalar cost. It also
makes previously impossible binary tables merely optional, opening large bulk
throughput gains without changing a single result code point.

The plan is intentionally not “set `KMAX = 10` and delete some aliases.” That
would retain most of the complexity and capture little of the opportunity.

---

## 1. Scope and compatibility decision

### 1.1 Supported formats

For each K, the legal format count is `4K - 2`. The revised grid is:

| K | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | total |
|---:|---:|---:|---:|---:|---:|---:|---:|----:|------:|
| formats | 10 | 14 | 18 | 22 | 26 | 30 | 34 | 38 | **192** |
| code points across formats | 80 | 224 | 576 | 1,408 | 3,328 | 7,680 | 17,408 | 38,912 | **69,616** |

The 120 `K <= 8` formats retain their byte representation. The 72 formats at
K = 9 and K = 10 retain a two-byte representation.

### 1.2 This is a breaking scope change

Removing K = 11:16 eliminates 312 currently constructible format types. It
must therefore ship as a major-version change or as a separately named profile.
There are two responsible release choices:

- **Recommended:** make the next major release the K10 architecture and fail
  immediately, at format construction, for K > 10.
- **Compatibility profile:** keep the current release line as `SmallFloatsWide`
  or a maintenance branch and make this package the optimized K10 profile.

Do not retain nonfunctional K = 11:16 aliases that throw only when arithmetic
is attempted. A format either belongs to the implemented domain or it does not.
The error should state the supported range and point to the wide maintenance
line.

### 1.3 Semantics do not narrow with scope

For K = 3:10, retain all existing behavior:

- every legal `(K, P, SGN, EXT)` combination;
- every rounding and saturation specification;
- deterministic and stochastic projection;
- all scalar, array, block, scaled, packed, approximation, and conformance
  surfaces;
- the exact-result-then-project-once contract;
- named approximation only, with no approximate default path.

The supported set becomes smaller; the meaning of every retained code point is
unchanged.

---

## 2. The K = 10 envelope, proved once

The redesign should begin with a small machine-checked theorem file rather than
with deletions. Every optimization below depends on these bounds.

For a format `Binary{K,P,SGN,EXT}`, the exponent bias is

```text
signed:   B = 2^(K-P-1)
unsigned: B = 2^(K-P)
```

At `K <= 10`, the maximum is the unsigned P = 1 case:

```text
Bmax = 2^(10-1) = 512.
```

A finite datum has at most P significant bits, with `P <= 10`, greatest
magnitude below `2^B`, and least-positive step `2^(2-P-B)`. At the worst cell,
all finite datums therefore lie within Float64's exponent range and carry far
fewer than its 53 significand bits.

### 2.1 Consequences by expression shape

| expression | exponent requirement | significand requirement | carrier policy |
|---|---:|---:|---|
| one decoded datum | `B <= 512` | `P <= 10` | exact `Float64` |
| product of two datums | `sum(Bi) <= 1024` | `sum(Pi) <= 20` | exact finite product in `Float64` |
| quotient of two datums | span at most about 1022 binades | generally non-dyadic | CR Float64 estimate plus rigorous fallback |
| sum/FMA of datums | range fits; exact sum may need a tail | at most 20 head bits plus exponent spread | Float64 head plus residual/sticky or exact fallback |
| product of four datums | `sum(Bi) <= 2048` | `sum(Pi) <= 40` | exact `Float128` workspace |
| arbitrary reduction | grows with lane count and spread | grows with lane count | derived-precision accumulator |
| transcendental | output can be outside every fixed carrier | not algebraically bounded | enclosure protocol and MPFR ladder |

This distinction is load-bearing. “All datums fit Float64” does **not** mean
“every operation can be naïvely evaluated in Float64.” Addition can lose a
sticky tail, a scaled multiply can contain four factors, a long reduction can
need arbitrary precision, and a transcendental still needs a rigorous
enclosure. The redesign removes wide *datum carriers*, not rigor.

### 2.2 New standing gate: the K10 envelope

Add a generated/exhaustive gate that proves, for all 192 formats:

1. `P <= 10`;
2. `B <= 512`;
3. every decoded datum is exactly representable in Float64;
4. every non-special datum round-trips through `Float64 -> project` exactly;
5. every two-factor finite product is representable without exponent overflow
   or underflow and with at most 20 significant bits;
6. every four-factor finite product fits Float128's exponent range and carries
   at most 40 significant bits;
7. `2^K + 1 <= typemax(UInt16)`;
8. `K1 + K2 <= 20` for every binary signature;
9. integer index arithmetic used by all supported arities cannot overflow
   `Int` before a materialization budget refuses the request.

These are architecture premises, not comments. The gate should fail before a
future change to K, P, operation factor counts, or representation can silently
invalidate them.

---

## 3. Correctness invariants for the revised architecture

The following invariants survive the current design and govern every stage:

1. **One semantic write path.** A defined result is exact or rigorously
   enclosed, then projected exactly once by `RoundToPrecision -> Saturate ->
   Encode`.
2. **Code point and numeric value remain distinct constructor meanings.** Every
   `Unsigned` constructor argument denotes a code point and is range checked;
   other `Real` inputs denote numeric values.
3. **Representation is exact.** The low K bits hold the code point and all high
   storage bits remain zero.
4. **Stochastic operations are never tables.** Their result depends on R and
   seeded arrays consume draws in index order.
5. **Approximation is explicit.** The default operation path never substitutes
   a κ-approximate implementation.
6. **Execution policy cannot change an answer.** Direct-code, dense-table,
   partial-table, sequential-compute, threaded-compute, and packed adapters
   return identical code points in identical order.
7. **The operation registry is the single source of operation name, arity,
   rigor class, factor count, and generated public surfaces.**
8. **Format types are propagated, never reconstructed from loose parameters in
   a hot path.**
9. **Every hot trait has one concrete inferred result per concrete format.**
10. **No object proportional to an unapproved `2^sum(K)` is materialized.**

The K10 architecture adds five invariants:

11. **Decoded-datum closure.** `decode(v)::Float64` exactly for every supported
    `v`.
12. **Workspace is selected from expression shape, not format storage.** A
    wider workspace is an evaluator implementation detail, never the type of a
    stored or decoded datum.
13. **Fast code laws are certified.** A direct code-point transformation exists
    only with an exhaustive equivalence gate against the defined evaluator.
14. **Planning is observationally silent.** Cache state, input length, input
    distribution, thread count, and prior calls may change cost but not output.
15. **Published tables are complete and immutable.** A racing or interrupted
    build may waste work but can never expose a partially initialized table.

---

## 4. The revised module architecture

The current architecture exposes representation traits, carrier heads, result
kinds, table policies, and kernel shapes across several neighboring files. The
K10 revision should deepen these modules: callers learn fewer concepts, while
the implementation hides more behavior behind each interface.

### 4.1 Layer map

| layer | proposed owner | interface | implementation hidden behind it |
|---|---|---|---|
| format domain | `formats.jl`, `codec.jl` | `format`, `codepoint`, `decode`, Group M queries | Code8/Code16, masks, exact decode banks, keys |
| projection policy | `projspec.jl`, `defaults.jl` | `ProjSpec`, explicit/default policy | singleton dispatch, RNG bit budgets |
| projection | `project.jl` | `project`, `project_interval` | rounding core, sticky protocol, saturation, encoding |
| defined evaluation | `evaluate.jl`, `oracle.jl` | private `defined_code`, `defined_value` | code laws, Float64 exact kernels, residuals, Float128 filters, MPFR |
| execution engine | `execution.jl` plus private files | `vmap`, `vmap!` | plan selection, caches, gathers, SIMD, threading, packed tiles |
| composition | `blocks.jl` | block/scaled/reduction operations | Float128 workspace, derived accumulators |
| approximation/conformance | `approx.jl` | existing public registry and reports | exhaustive binary measurement, sampling only where declared |

The public interface need not be made smaller in this major release. The large
gain comes from making the internal interfaces smaller and preventing execution
policy from leaking into semantic modules.

### 4.2 Dependency direction

```text
Format Domain ──────────────┐
Projection Policy ──────────┼──> Defined Evaluation ──> Projection
                            │             ▲                 ▲
                            │             │                 │
                            └──> Execution Engine ──────────┘
                                      ▲
                                      │
                              Blocks / Packed adapters
```

All dependencies are in-process pure computation or bounded in-memory state.
No public adapter interface is warranted. Internal adapters are real because
there are multiple execution implementations: direct-code, dense gather,
row-gather, and compute.

The deletion test for the Execution Engine is decisive: delete it and table
budgets, cache lifecycle, threading, packed traversal, and strategy selection
would reappear across every arity. It earns a deep interface.

---

## 5. Format Domain: two representations, one exact datum type

### 5.1 Retain Code8 and Code16

Keep:

```julia
struct Code8{K,P,S,E}  <: Binary{K,P,S,E}; x::UInt8;  end
struct Code16{K,P,S,E} <: Binary{K,P,S,E}; x::UInt16; end
```

Do not unify all formats on UInt16. That would double array and result-table
bandwidth for the established K <= 8 formats and degrade the fastest path in
order to simplify a cold trait.

Do not introduce a packed 10-bit scalar representation. Julia scalar types
occupy whole bytes; bit packing belongs in `PackedVector`, where its extraction
cost can be amortized over tiles.

### 5.2 Collapse datum carrier selection

The public and internal facts become:

```julia
datumcarrier(::Type{<:Binary}) = Float64
promotecarrier(::Type{<:Binary}) = Float64
decode(v::Binary)::Float64
```

The `HeadF64`/`HeadF128`/`HeadExact` lattice is no longer a format trait.
`Float128` remains in the oracle and composition implementation, but it no
longer appears as the decoded type of a format.

This removes:

- carrier joins for ordinary scalar operands;
- `lift` on the ordinary path;
- mixed-carrier vararg machinery;
- format-level promotion to Float128 or BigFloat;
- wide-carrier special constants for decode;
- the need for `Dyadic` as a datum representation;
- wide-format precompile representatives selected by carrier rung.

The result should be a much smaller inference graph. The steady-state scalar
path already specializes away much of the current trait machinery, so the
largest expected wins are lower first-use latency, fewer method instances, and
less code to compile. Runtime improvement is still expected for K = 9:10
because decode no longer participates in a carrier union.

### 5.3 Use UInt16 order keys everywhere

Every format has at most 1,024 code points plus the NaN sentinel. One
`UInt16` order-key implementation suffices for both Code8 and Code16.

This does not require widening Code8 storage. It merely makes the comparison
currency uniform and removes the current Code16 `UInt32` branch. The extra
integer width on K <= 8 comparisons is normally free on modern CPUs and should
be confirmed by the comparison/sort benchmark.

If benchmarking shows a regression, keep representation-specific key widths
behind the same interface; do not expose the distinction again.

### 5.4 Replace generated-vs-computed decode with a measured decode bank

The complete decoded lattice is only 69,616 Float64 values, or 556,928 bytes.
The K = 9:10 portion is 56,320 values, or 450,560 bytes. This changes the
materialization decision fundamentally: the whole supported decode domain is
smaller than one present K = 16 format's conceptual table.

Evaluate three decode adapters:

1. **Existing split:** generated tuple for Code8, arithmetic decode for Code16.
2. **Per-format immutable bank:** one lazily initialized `Memory{Float64}` per
   concrete format.
3. **Atlas:** one immutable concatenated Float64 array plus a compile-time
   format offset; decode is `atlas[offset(F) + code + 1]`.

The atlas is the preferred candidate because it avoids `2^K` generated syntax,
keeps a single ground truth, and adds less than 0.6 MiB of raw data. Its seam is:

```julia
@inline decode_code(::Type{F}, c::Unsigned)::Float64 where {F<:Binary}
```

`decode(v)` becomes a veneer over `decode_code(typeof(v), codepoint(v))`.
Table builders and compute kernels call `decode_code` directly and stop
constructing temporary `Binary` values solely to decode them.

Do not select the atlas merely because it is small. Benchmark hot scalar decode,
sequential array decode, random-code decode, package image size, load time, and
first use. Computed bit assembly may beat a load for Code8; the final adapter may
therefore remain representation-specific behind the single interface.

### 5.5 Format identities

Generate exactly 192 aliases. `using SmallFloats` may reasonably export all of
them in the new major release: 72 opt-in wide names is a much smaller collision
surface than the current 384. This is a user-interface decision, not a hot-path
one; qualify it with a compatibility review before changing exports.

---

## 6. Defined Evaluation: one deep semantic seam

### 6.1 New internal interface

Make the currency at the semantic/execution seam a code point:

```julia
defined_code(::Val{op}, ::Type{FR}, rho::ProjSpec, R::Int,
             args::Vararg{CodeArg,N}) -> codeunit_type(FR)

defined_value(::Val{op}, ::Type{FR}, rho::ProjSpec, R::Int,
              xs::Vararg{Float64,N}) -> FR
```

`CodeArg` contains a statically known format type and its unsigned code. The
concrete implementation may be a small isbits wrapper or simply arity-specific
arguments; do not allocate tuples in the hot path.

`defined_code` does exactly one of two things:

1. apply a certified direct code law and return its code; or
2. decode codes, call the defined evaluator, project once, and return the code.

All of these consumers use the same interface:

- public scalar operation veneers;
- dense table builders;
- partial row builders;
- direct-compute array kernels;
- κ measurement;
- conformance differential checks.

This is the most important deepening in the plan. Today the same semantic route
is assembled by several callers from `rawvalue`, `decode`, `apply_op`, and
`codepoint`. Centralizing it gives high leverage and makes the interface itself
the test surface.

### 6.2 Retain the result protocol, reduce its carrier dimension

The oracle still needs result kinds, but their meaning becomes simpler:

| result kind | meaning | action |
|---|---|---|
| `Float64` | exact finite/special result or safe head | project directly |
| `Float128` | exact fixed-width result or filter result | project directly or use bracket |
| `StickyF{Float64/Float128}` | exact head plus tail direction | project with sticky |
| `BigExactF` | deferred exact result at derived precision | evaluate then project |
| `EncloseF` | Float64/Float128 estimates plus rigorous MPFR enclosure | agreement ladder |
| `Enclose128F` | CR Float128 bracket plus fallback | interval agreement |

Remove `Dyadic` from the result union unless a benchmark demonstrates a K10
workload where it materially outperforms the smaller protocol. A custom exact
carrier is no longer needed for datum range. Keeping it speculatively would
preserve code, compilation, and proof burden for a case outside the new scope.

The MPFR fallback remains. Correct rounding, not representability of operands,
is why it exists.

### 6.3 Arity-specific entry points

No hot implementation should use an unconstrained splat. Generate or write
arity-1, arity-2, and arity-3 `defined_code` and evaluator methods from the
operation registry. This gives Julia fixed tuples and concrete result unions.

The registry row should own:

```text
name, arity, semantic class, factor count, direct-code-law tag, table hint
```

The last two fields are performance metadata only. Removing them must never
change a result.

### 6.4 Certified direct code laws

Some operations do not need decode, oracle evaluation, or projection when the
result and operand formats satisfy a static guard. Candidates include:

- exact selections whose result is one operand;
- same-format `Abs` and signed `Negate`;
- same-format min/max families after their NaN rules are applied;
- code-point stepping and classification already expressed in the code domain;
- exact same-format copies and certain sign operations.

Do not scatter these as local special cases. Define an internal adapter:

```julia
code_law(::Val{op}, ::Type{FR}, ::Type{F1}, ...) -> NoCodeLaw() | CodeLawTag()
apply_code_law(tag, rho, R, codes...) -> result_code
```

A law is admissible only if:

1. its guard is static;
2. it handles NaN, infinity, signedness, and domain explicitly;
3. the exact mathematical result is already a datum of `FR`, so projection is
   provably the identity;
4. every rounding/saturation mode gives the same code under that guard;
5. an exhaustive test compares it with the ordinary evaluator over the whole
   guarded input domain.

The direct law is an adapter behind `defined_code`, not a second semantics.
This can reduce common scalar operations to masks, comparisons, and one raw
construction.

### 6.5 Float64-first arithmetic kernels

Retain and tighten the current exactness techniques:

- exact two-factor multiplication in Float64 under the K10 envelope;
- `2sum`/residual handling for addition and subtraction;
- FMA/FAA head-plus-sticky results for wide exponent separation;
- CR division and square-root estimates with interval fallback;
- faithful Float64 transcendental estimates guarded by two-sided projection;
- Float128 filters before MPFR where they reduce fallback frequency.

The important reformulation is that none of these are selected by a format
carrier head. They are selected by operation class and realized operands inside
the Defined Evaluation module.

### 6.6 Keep projection independent

Do not fold rounding or saturation into operation-specific kernels. The current
projection module is already deep: it accepts an exact value, sticky value, or
enclosure and returns one code point. Preserve that locality.

Fast code laws are the only bypass, and their proof obligation is exactly that
projection would be the identity. All other optimizations terminate at
`project`.

---

## 7. Composition: wide workspace without wide datum carriers

### 7.1 Fixed scaled and block expressions

A scaled binary operation can contain four original datum factors. At K10:

```text
sum(Bi) <= 4 * 512 = 2048
sum(Pi) <= 4 * 10  = 40
```

This exceeds Float64's exponent range but is comfortably inside Float128's
range and precision. Therefore:

- decode every scale and element to Float64;
- widen all factors to Float128 before a product that can contain more than two
  factors;
- evaluate the fixed algebraic expression without first forming an overflowing
  Float64 subproduct;
- project the exact Float128 result once.

The workspace choice belongs to the composition implementation, not to
`datumcarrier(F)`.

### 7.2 Fuse expression shape

Do not implement `ScaledMultiply` as two independently rounded or potentially
overflowing scale products followed by another multiplication. Build the
mathematical expression in the workspace:

```julia
Float128(s1) * Float128(x1) * Float128(s2) * Float128(x2)
```

with operation-specific special-value handling matching the draft. Fusing is
both faster and easier to reason about because the result is projected once and
no intermediate is mistaken for a datum.

### 7.3 Reductions

Reduction length is unbounded, so KMAX alone cannot make every reduction fit a
fixed significand. Use a tiered accumulator hidden behind the block module:

1. Float128 exact accumulator when integer width/span analysis proves it fits;
2. sticky accumulator for a provably negligible tail where the rounding mode
   permits the existing proof;
3. derived-precision BigFloat accumulator otherwise.

The accumulator decision may inspect format parameters and block length before
the loop. It must not inspect values repeatedly if a single cheap exponent-span
pass can decide the tier.

Preserve exact special-value algebra before the finite reduction.

### 7.4 Dyadic disposition

Recommended default: remove `Dyadic` from package load and production dispatch.
Move its rational bridge to test/reference support if it remains useful as an
independent oracle.

Before deletion, benchmark it against Float128 and derived-precision BigFloat on
the retained block/reduction workload. Keep it only if it wins materially in a
reachable K10 path and can sit wholly behind the accumulator interface. “It was
needed for K16” is not sufficient reason.

---

## 8. Execution Engine: strategy is cost, never semantics

### 8.1 Interface

The external seam remains the existing array interface:

```julia
vmap(op, fr, rho, arrays...; rng=nothing)
vmap!(dest, Val(op), fr, rho, arrays...; rng=nothing)
```

Internally, one planner chooses an adapter once per array call:

```julia
plan = execution_plan(Val(op), fr, rho, operand_formats, length(dest), cache_state)
execute!(plan, dest, arrays..., rng)
```

`execution_plan` returns a concrete singleton or small isbits plan. The branch
occurs outside the element loop. Plan types include:

- `DirectCodePlan`;
- `DenseGatherPlan`;
- `RowGatherPlan`;
- `SequentialComputePlan`;
- `ThreadedComputePlan`;
- `PackedTilePlan` wrapping one of the above.

The plan is private. Users should not need to understand it to get good
performance.

### 8.2 One policy for every arity

Replace the separate unary/binary and ternary policy stories with one table
policy expressed in three independent quantities:

1. **materialization safety:** bytes of the completed immutable table;
2. **build cost:** number and class of defined evaluations;
3. **expected reuse:** observed elements relative to the domain size.

The arity-specific fill and gather loops remain separate for performance, but
their policy comes from one module.

### 8.3 Recommended default bands

Start from conservative bands, then tune from measurements:

| domain size | initial adapter | rationale |
|---:|---|---|
| unary, at most `2^10` entries / 2 KiB | eager dense table | tiny, cache resident |
| binary `sum(K) <= 16` | eager dense table | preserves the established 65,536-entry ceiling |
| binary `17 <= sum(K) <= 20` | adaptive dense or row table | feasible, but build and LLC cost need amortization |
| ternary `sum(K) <= 18` | eager dense table | preserve current successful band |
| ternary `19 <= sum(K) <= 21` | adaptive dense table | preserve current adaptive band |
| larger ternary | compute | up to 2 GiB at 10+10+10; not a cache |

For a K10-by-K10 operation, a dense result table is 2 MiB. It is a valid
option, not an automatic win. Random gathers may miss private caches, while a
simple compute kernel may remain in registers. The planner must be benchmark
driven.

### 8.4 Amortization rule

Use “domain equivalents processed” as the first adaptive signal:

```text
reuse = cumulative_elements / domain_entries
```

This is more stable across operations than a raw element threshold: expensive
operations cost more to build, but they also save more per gathered element.
Begin building only after at least one domain equivalent has been computed, and
require measured break-even evidence before selecting a larger default.

Keep the counters approximate and off the hot element loop: update once per
array call. Overflow should saturate.

### 8.5 Dense table lifecycle

- Build outside the cache lock.
- Partition by contiguous outer-code ranges for parallel construction.
- Publish only the fully initialized immutable `Memory`.
- Resolve racing builders with first-publisher-wins; discard the duplicate.
- Bound the cache by bytes with LRU or CLOCK eviction.
- Keep UInt8-result and UInt16-result payload stores concrete, even if metadata
  is unified.
- Report build count, hit count, eviction count, bytes, and declined signatures
  through conformance/performance introspection.

### 8.6 Partial row tables

Quantized ML data are often highly skewed: zero, small integers, saturation
endpoints, and a few activation levels dominate. A full 2 MiB binary table may
be wasteful when only a handful of first-operand codes occur.

Prototype a row-table adapter:

- one row fixes operand 1 and enumerates all `2^K2` operand-2 codes;
- a K10 row is only 2 KiB of UInt16 results;
- scan an input tile or reuse a small histogram to identify hot rows;
- build rows through `defined_code` and publish immutable rows;
- create a local row-pointer directory once per array call;
- use compute for cold rows without a per-element dictionary lookup.

This design can offer near-dense-table throughput on skewed inputs while using
orders of magnitude less memory and build time. It must remain experimental
until uniform, Zipf, sparse-zero, and application traces demonstrate a win.

Never put a lock, dictionary lookup, or cache-state branch inside the element
loop.

### 8.7 SIMD and threading

Use distinct loops rather than one heavily branched loop:

- dense gathers: `@inbounds @simd` only if LLVM demonstrates safe vector gathers;
- direct code laws: vectorize masks/comparisons aggressively;
- compute: specialize by operation and arity, with the planner selecting
  sequential or threaded once;
- stochastic: sequential by default to preserve draw order;
- table builds: parallel because entries are pure and independent.

For small element types, false sharing and task overhead can dominate. Determine
thread thresholds separately for direct, gather, and compute adapters rather
than retaining one global `THREAD_MIN_ELEMS` for unlike work.

### 8.8 Aliasing and destination layout

Add explicit alias analysis at the array-call seam. Same-shape in-place
operations may be safe when each output depends only on same-index inputs; table
build and plan selection must finish before writes begin. Unsupported overlap
should use a bounded tile scratch or throw clearly, not silently corrupt input.

Specialize contiguous `Vector`/`Memory` loops separately from generic
`AbstractArray` traversal. The generic adapter preserves coverage; the dense
adapter earns throughput.

---

## 9. Packed storage reformulation

At K = 9 and K = 10, `PackedVector` saves 43.75% and 37.5% respectively against
UInt16 storage. That makes it useful rather than ceremonial.

Retain the rule “store packed, compute unpacked,” but deepen the adapter:

1. unpack code points into a `UInt16` tile, not a `Vector{F}` unless construction
   is proven free;
2. pass code buffers directly to `defined_code` or a gather plan;
3. avoid creating `SubArray` views in the inner tiled path;
4. size tiles from L1 capacity and table working set, not from the historical
   constant 256 alone;
5. fuse unpack + row histogram when considering a row-table plan;
6. for direct code laws, operate on unpacked integers and construct only final
   results;
7. add `vmap!` into a packed destination where the result format matches and
   measured demand justifies it, using a separate output tile to keep writes
   simple and deterministic.

Do not attempt arithmetic directly across packed word boundaries. The extra
proof and instruction complexity is unlikely to beat tiled integer extraction,
especially when tables or SIMD code laws are available after unpacking.

---

## 10. Scalar and bulk performance opportunities by class

| operation class | scalar implementation | bulk priority |
|---|---|---|
| classification, order, stepping | direct code arithmetic | SIMD direct-code loop |
| exact selections/sign operations | certified code law where guarded | direct-code or tiny table |
| unary transcendental | Float64 estimate -> Float128 filter -> MPFR | always-small unary table |
| add/subtract | Float64 2sum/sticky protocol | dense/row table or specialized compute |
| multiply | exact Float64 product under K10 envelope | dense/row table; SIMD compute candidate |
| divide/sqrt | CR estimate plus interval protocol | table for hot signatures |
| FMA/FAA | residual/sticky evaluator | existing ternary bands, compute above them |
| scaled fixed arity | fused Float128 workspace | specialized compute; table only if domain small |
| reductions | analyzed Float128 or derived precision | chunked/threaded reduction with exact merge |
| stochastic | same evaluator with explicit R | sequential deterministic stream; optional counter RNG only as a separately specified interface |

### 10.1 Do not optimize already-free veneers

Traits such as `bitwidth`, `precision`, and `codeunit_type` fold for concrete
formats. Rewriting them for aesthetic simplicity is not a throughput project.
Prioritize measured costs:

- decode on Code16;
- first-use compilation;
- untabled K9/K10 binary arrays;
- packed tile overhead;
- block/reduction allocations;
- dynamic format use without a function barrier;
- cache construction and eviction behavior.

### 10.2 Preserve function barriers

Runtime format selection should cross exactly one barrier into a method where
the format is a type parameter. The revised modules should never make a runtime
`Symbol` or `DataType` lookup part of an element loop.

### 10.3 Specialize deliberately

The reduced 192-format grid makes specialization cheaper, but 52 operations and
many projection modes can still create a large Cartesian product. Specialize
hot arithmetic and loop bodies; keep cache metadata, reporting, and cold policy
logic value-keyed. Do not precompile the whole grid.

The precompile workload should cover:

- one Code8 representative;
- one K10 maximum-bias representative;
- one K10 maximum-precision representative;
- one unary table, one binary table, one compute ternary;
- one block/scaled Float128 workspace;
- one enclosure fallback.

That covers implementation shapes rather than format names.

---

## 11. Alternatives considered

### 11.1 Minimal surgery

Set `KMAX = 10`, remove aliases above it, leave the carrier lattice and current
table policies intact.

**Rejected as the final design.** It is the lowest-risk first migration stage,
but it preserves carrier joins, Dyadic load, UInt32 keys, computed wide decode,
and compute-only K10 binary arrays after their original reasons have vanished.
It captures compatibility scope reduction without architectural leverage.

### 11.2 Precompute everything

Materialize every operation table for every format and projection because the
domain is now “small.”

**Rejected.** One specialization may be small; their Cartesian product is not.
For example, a single K10 binary UInt16 table is 2 MiB. Multiplying that by
operations, result/operand formats, and projection modes is untenable. Laziness,
reuse evidence, and byte-bounded eviction remain necessary.

### 11.3 UInt16 for every format

Use one concrete representation and one cache payload type.

**Rejected by default.** It simplifies representation code but doubles memory
traffic for K <= 8, where the package already has excellent gather throughput.
The two representations are a real seam with two justified adapters.

### 11.4 Float64 only, including composition and rigor

Delete Float128 and MPFR because all datums fit Float64.

**Incorrect.** Exact sums can require a tail, scaled expressions can contain
four factors, reductions have unbounded length, and transcendental correctness
still requires enclosure. Operand representability is not result rigor.

### 11.5 One universal dynamic kernel

Interpret operation symbols, arity, formats, and projection policy at runtime to
reduce compilation.

**Rejected.** It trades bounded compile work for dynamic dispatch in every
element. The correct compromise is value-keyed cold metadata feeding a concrete
plan and specialized hot loop.

### 11.6 Recommended hybrid

Use two storage adapters, one exact datum type, one defined-code seam, several
private execution adapters, and a retained rigorous oracle ladder. This gives
depth and locality without sacrificing the type specialization on which Julia
throughput depends.

---

## 12. Verification doctrine

### 12.1 Golden preservation

Before refactoring, capture code-point digests for every retained K = 3:10
public operation exercised by the current suite. Keep the existing K <= 8
golden unchanged and add a K9/K10 golden from the current conforming
implementation.

Every semantic refactor must be byte-identical against these digests. A golden
does not replace the independent reference; it separates behavior preservation
from reference correctness.

### 12.2 Exhaustive domains

The revised suite can afford stronger claims:

- full format/code lattice: 69,616 points;
- full order-key and decode/encode laws for every format;
- every unary code law over every guarded format;
- every binary code law over every guarded signature selected for the law;
- every built table over every entry;
- every `measure_kappa` binary registration over at most `2^20` inputs;
- `f32_exact` over every binary signature under its present `2^20` budget.

Do not claim that every operation across every pair of the 192 formats and every
projection is cheap. Factor the suite by engine parameter tuples, operation
class, representative signatures, and exhaustive adapter-equivalence gates.

### 12.3 Adapter equivalence matrix

For every execution adapter that applies to a signature, compare code points:

```text
defined evaluator
    == direct code law
    == dense table
    == row table
    == sequential compute
    == threaded compute
    == packed-tile execution
```

Comparison is exact identity in identical order. Tolerance has no role.

### 12.4 Independent reference

Retain the `Rational{BigInt}`/MPFR reference path and ensure it shares no decode,
rounding, saturation, table, or direct-code implementation with production.
Moving Dyadic into test support is acceptable only if it remains independent
of the implementation under test.

### 12.5 Stochastic verification

For each stochastic family:

- enumerate its actual R domain at small N;
- pin boundary N values including the maximum supported budget;
- verify one draw per projected element;
- verify seeded sequential array order;
- verify that no table or parallel plan is selected;
- verify direct code laws are used only where output is independent of R.

### 12.6 Static-performance gates

Keep deterministic gates for:

- concrete inferred return types;
- zero warm-path allocation on ordinary scalar and array adapters;
- no dynamic dispatch inside element loops;
- no dictionary lookup or lock inside element loops;
- bounded table-size arithmetic before allocation;
- no partially published tables;
- JET concrete-call coverage for every plan type.

Timing belongs in benchmarks, not pass/fail unit tests.

---

## 13. Benchmark and tuning program

Performance work is accepted only from like-for-like measurements with static
format arguments, untimed setup, warm/cold separation, allocation checks, and
recorded Julia/CPU/thread configuration.

### 13.1 Baseline first

Before Stage 1, record:

- package load and precompile time;
- first scalar call for K8, K9, and K10;
- warm scalar calls by operation class;
- Code8 table decode versus Code16 computed decode;
- cold build and warm gather by table size;
- sequential and threaded compute arrays;
- packed pack/unpack/vmap;
- block/scaled/reduction paths;
- method-instance count or a stable proxy for compiled-code volume;
- cache footprint and eviction behavior.

### 13.2 Required workload distributions

Array benchmarks must include:

- uniform random code points;
- sequential codes;
- all-zero and single-valued inputs;
- sparse-zero mixtures;
- Zipf/skewed code frequencies;
- alternating extrema and special values;
- representative ML activation/weight traces when available.

Uniform random alone systematically undervalues row caching and overstates the
cache cost users may see.

### 13.3 Target outcomes

These are design acceptance targets, to be calibrated after the baseline rather
than treated as invented absolute nanoseconds:

1. No retained K <= 8 warm scalar or gather regression greater than 5%.
2. Zero allocations on ordinary K9/K10 scalar, dense-gather, direct-code, and
   compute loops.
3. At least 2x lower first-use latency for a representative K10 operation after
   removal of wide carrier specialization.
4. K9/K10 decode within 20% of Code8 decode, or a documented reason the atlas
   loses and computed decode is retained.
5. At least 3x warm throughput improvement before enabling any adaptive K10
   binary table by default.
6. Demonstrated amortization of table build within the configured reuse
   threshold.
7. Direct-code kernels materially faster than the evaluator path and never
   slower than dense gather on their intended workload.
8. Packed K9/K10 bulk operations improve end-to-end bandwidth after including
   unpack/repack cost, not merely extraction microbenchmarks.
9. Lower package image/method-instance footprint after deleting the carrier
   lattice and K11:16 formats.

If an optimization misses its target, remove it. A dormant strategy still costs
interface knowledge, tests, compilation, and maintenance.

---

## 14. Migration plan

Every stage is independently revertible, compiles, and passes the full suite.
No stage both changes semantics and optimizes an unverified path.

### Stage 0 — Freeze evidence

1. Record the repository revision, Julia version, dependency versions, CPU, and
   thread count.
2. Capture K3:10 golden digests from the current implementation.
3. Run the current default and release verification tiers.
4. Produce the performance baseline in section 13.
5. Add the K10-envelope gate and watch it pass before relying on it.

**Exit:** reproducible semantic and performance baselines exist.

### Stage 1 — Narrow scope only

1. Set `KMAX = 10`.
2. Generate only 192 format aliases.
3. Remove K11:16 precompile workloads and test expectations.
4. Add an immediate, documented error for wider format requests.
5. Leave the existing carrier and evaluator machinery otherwise intact.

**Exit:** all retained golden digests are unchanged. This stage proves that the
scope change itself is separate from the architecture change.

### Stage 2 — Collapse the datum carrier

1. Make every decode return exact Float64.
2. Make promotion carrier uniformly Float64.
3. Replace ordinary scalar `rung`/`joinhead`/`lift` composition with direct
   Float64 evaluation.
4. Keep old and new paths temporarily available to the differential gate.
5. Exhaustively compare them across the 69,616-point lattice and operation
   representatives.

**Exit:** code-point identity, concrete inference, and zero allocation hold.

### Stage 3 — Isolate composite workspace

1. Route scaled/fixed four-factor expressions through fused Float128 workspaces.
2. Route reductions through the analyzed accumulator interface.
3. Differentially compare against the current HeadF128/HeadExact implementation
   and the independent reference.
4. Remove format-carrier joins from `blocks.jl`.

**Exit:** all block/scaled/reduction gates are exact and allocation profiles are
recorded.

### Stage 4 — Remove obsolete wide-carrier machinery

1. Delete `HeadF128`/`HeadExact` as datum heads and their lift/join machinery.
2. Remove Dyadic from production load if the Stage 3 benchmark justifies it.
3. Retain Float128 as an oracle/composition implementation detail.
4. Simplify result unions and finish dispatch.
5. Update the precompile workload around implementation shapes.

**Exit:** lower first-use and method-instance measurements; all goldens green.

### Stage 5 — Introduce `defined_code`

1. Add arity-specific code-based semantic entry points.
2. Route scalar veneers, current table builders, compute kernels, κ measurement,
   and `f32_exact` through them.
3. Remove duplicated `rawvalue -> decode -> apply_op -> codepoint` assembly.
4. Test solely through the new interface plus independent reference.

**Exit:** deleting an old assembly helper does not force semantic logic into any
caller—the deletion test for module depth passes.

### Stage 6 — Codec optimization

1. Implement and benchmark the decode atlas against current strategies.
2. Select the winning adapter by representation if necessary.
3. Uniformize order keys to UInt16 if comparison benchmarks are neutral.
4. Remove obsolete generated decode machinery only after image/load benchmarks.

**Exit:** decode target met, or measured evidence records why the existing
adapter remains.

### Stage 7 — Unified Execution Engine

1. Introduce concrete plan types and one planner.
2. Move unary, binary, and ternary cost policy behind it.
3. Preserve existing eager/adaptive bands initially.
4. Consolidate cache metadata and byte accounting while retaining concrete
   payload stores.
5. Split thread thresholds by adapter.

**Exit:** every old adapter-equivalence gate passes through the new interface;
no hot-loop regression.

### Stage 8 — Adaptive K9/K10 binary tables

1. Add byte-bounded LRU storage for large binary tables.
2. Count reuse once per call.
3. Benchmark K9/K10 dense tables under all distributions.
4. Enable only signatures meeting the 3x warm-throughput and amortization
   targets.
5. Add cache observability.

**Exit:** substantially faster repeated bulk workloads with bounded memory and
unchanged results.

### Stage 9 — Certified code kernels

For each candidate operation, one at a time:

1. write the static guard;
2. write an exhaustive equivalence test first;
3. implement the law behind `defined_code`;
4. add scalar and SIMD bulk benchmarks;
5. keep only measured wins.

**Exit:** each retained law has an explicit proof domain, exact gate, and
performance result.

### Stage 10 — Packed and row-table experiments

1. Change packed tiles to integer-code buffers.
2. Fuse unpack with execution adapters.
3. Prototype row caching behind the planner.
4. Test uniform and skewed distributions.
5. Promote only winning experiments to default policy.

**Exit:** packed end-to-end and skewed-input targets met; otherwise experimental
code removed.

### Stage 11 — Documentation and release

1. Rewrite public format counts/ranges and conformance output.
2. Replace the carrier-lattice explanation with datum/workspace/rigor axes.
3. Document the breaking scope decision and wide-line migration.
4. Regenerate benchmark evidence and examples.
5. Run docs, Aqua, JET, default, release, golden, and differential suites.

**Exit:** source, tests, conformance, manual, and benchmark report describe the
same architecture.

---

## 15. File disposition

| current file | proposed action |
|---|---|
| `formats.jl` | set KMAX 10; retain Code8/Code16; reduce traits; generate 192 aliases |
| `carriers.jl` | dissolve format carrier lattice; retain only reusable workspace/exactness utilities in evaluator/composition owners |
| `dyadic.jl` | remove from production or move behind reduction/reference interface if benchmarks justify it |
| `decode_encode.jl` | become `codec.jl`; add `decode_code`; evaluate atlas; UInt16 keys |
| `project.jl` | preserve as deep projection module; simplify accepted carrier union where possible |
| `ops_scalar.jl` | own result protocol and public veneers; call `defined_code`/`defined_value` |
| `oracle.jl` | organize by rigor class and Float64-first evaluation, not carrier head |
| `tables.jl` | split private storage/build implementation under unified Execution Engine policy |
| `kernels.jl` | arity-specific execution adapters selected by concrete plans |
| `blocks.jl` | fused Float128 workspace and analyzed reduction accumulator |
| `packed.jl` | integer-code tiles feeding the Execution Engine |
| `approx.jl` | exhaustive binary κ under K10; code-based enumeration |
| `SmallFloats.jl` | shorter include graph, revised precompile shapes, revised format exports/docs |
| `test/wide_ops.jl` | replace K16 carrier tests with K10-envelope and Code16 tests |
| gate suite | add defined-code and adapter-equivalence matrices; retain independent reference |

Physical filenames are less important than ownership. Do not create a forest of
one-function files. The objective is a few deep modules with small interfaces
and strong locality.

---

## 16. Risks and mitigations

| risk | consequence | mitigation |
|---|---|---|
| “fits Float64” is overgeneralized | incorrect rounding or overflow in composition | K10 envelope gate separated by expression factor count; retain rigorous result protocol |
| direct code law mishandles a special value | silent semantic fork | static guard plus exhaustive whole-domain equivalence before activation |
| 2 MiB table hurts cache | bulk regression despite faster lookup | adaptive policy; compare dense, row, and compute on several distributions |
| decode atlas increases image/load time | faster loop, worse user latency | measure raw decode, image size, load, and TTFX together; retain computed adapter if needed |
| runtime planner becomes expensive | array-call overhead or unstable inference | plan once outside loop; concrete plan types; JET concrete-call gates |
| cache telemetry changes behavior | irreproducible performance or races | telemetry affects cost only; output equivalence and concurrency stress tests |
| removing Dyadic slows rare exact paths | block/reduction regression | benchmark reachable K10 cases before deletion; retain only behind a deep accumulator interface if it wins |
| Float128 dependency is removed too aggressively | more MPFR allocation and lower throughput | retain it for four-factor workspace and enclosure filters |
| specialization remains excessive | high first-use latency | precompile implementation shapes; value-key cold metadata; measure method instances |
| narrower scope surprises users | source breakage | major release, immediate errors, migration guide, maintained wide line if warranted |

---

## 17. Completion criteria

The K10 revision is complete only when all of the following are true:

1. Exactly 192 formats exist and every one passes exhaustive lattice laws.
2. Every retained K <= 8 golden digest is unchanged.
3. K9/K10 goldens from the pre-refactor implementation are unchanged.
4. `decode(v)::Float64` is exact for every supported code point.
5. No format-level carrier join or Dyadic datum path remains.
6. Fixed four-factor composition is range-safe and exact in its selected
   workspace; reductions retain derived-precision correctness.
7. Scalar, table, row-table, compute, threaded, and packed adapters agree by
   code point wherever each applies.
8. Every binary κ measurement is exhaustive under the default budget.
9. Table allocation is bounded before size construction and published tables
   are immutable and complete.
10. Stochastic seeded order is unchanged.
11. No K <= 8 hot-path benchmark regresses by more than the accepted tolerance.
12. At least the first-use, K9/K10 decode, and repeated bulk throughput goals
    show substantial measured improvement.
13. Removed strategies and types are actually deleted rather than retained as
    dormant compatibility branches.
14. Conformance reports execution coverage and sampled/exhaustive status
    truthfully.
15. The manual describes the revised architecture in the same vocabulary as the
    source and tests.

---

## 18. Final recommendation

Adopt K = 10 as an architectural premise, not just a range check.

The best design is:

```text
two compact storage representations
one exact decoded datum type
one deep defined-code semantic seam
one unchanged projection authority
one rigorous Float64-first oracle with Float128/MPFR behind it
one composition-owned wide workspace
one cost-only execution planner with multiple private adapters
```

The most certain improvements are reduced compilation, smaller method and test
surfaces, exact binary κ measurement, simpler Code16 evaluation, and tiny unary
tables. The largest throughput opportunity is adaptive K9/K10 binary execution:
dense tables for genuinely hot signatures, partial rows for skewed data, and
specialized compute otherwise. Certified code-domain kernels offer a second
orthogonal gain for structural operations.

The discipline that makes the reworking safe is simple: semantic optimization
lives behind `defined_code`; execution optimization lives behind
`execution_plan`; both are tested through their interfaces against the same
independent defined result. Anything that cannot meet that shape is either not
deep enough or not yet proven.
