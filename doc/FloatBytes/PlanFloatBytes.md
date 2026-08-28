# FloatBytes.jl

## A clean-sheet, byte-native implementation plan for 3 <= K <= 8

*Proposal written 2026-08-04. This document describes a new package, not a
refactor of SmallFloats.jl. SmallFloats is evidence and a differential oracle;
it is not the template. IEEE P3109/D1 remains the semantic authority for the
retained formats and operations.*

---

## 0. Recommendation

Build FloatBytes.jl around one fact: every supported value occupies exactly one
byte.

The public scalar type should be a one-byte, concrete `AbstractFloat`:

```julia
primitive type FloatByte{K,P,S,D} <: AbstractFloat 8 end
```

where `3 <= K <= 8`, `P` is the precision, `S` is signed or unsigned, and `D`
is finite or extended. The code point occupies the low K bits. There is no
second representation, no representation trait, no carrier lattice, and no
abstract-format/concrete-storage split.

The semantic center should be one private interface:

```julia
defined_code(signature, random_word, operand_codes...)::UInt8
```

It returns the defined result code for one complete operation specialization.
Scalar operations, table compilation, direct-compute array kernels, block
lanes, approximation measurement, and conformance checks all cross this seam.

Bulk performance should live behind prepared plans:

```julia
sig  = signature(Add, ResultFormat, RNE_SN, OperandFormats...)
plan = prepare(sig; execution=:auto)

apply(sig, x, y)
execute!(dest, plan, xs, ys)
```

The plan chooses an immutable unary or binary lookup table, a stochastic
decision table, a direct byte law, a specialized ternary kernel, a packed-tile
adapter, or an exact reduction adapter. Planning happens once. No registry
lookup, cache lock, symbol dispatch, format check, or strategy branch appears
inside the element loop.

The resulting architecture has five deep modules:

1. **Byte Domain** — the type, code identity, decode atlas, ordering, and format
   metadata;
2. **Projection** — the only implementation allowed to select an output code;
3. **Defined Semantics** — exact operation meaning and rigorous enclosures;
4. **Plan Compiler** — converts a semantic signature into an immutable execution
   plan;
5. **Assurance** — independent reference evaluation, exhaustive certification,
   approximation bounds, and conformance evidence.

Everything else is an adapter behind one of those interfaces.

This is not the smallest possible implementation. It is the smallest design
that simultaneously provides strong Julia interoperability, exact results,
high-throughput byte arrays, reproducible stochastic execution, packed and
block storage, and evidence that optimized adapters agree.

---

## 1. How the plan was reviewed and improved

Three radically different clean-sheet designs were developed before selecting
this one.

### 1.1 Design A: minimal semantic program

The first design exposed only `execute`, `execute!`, and `certify`, operating on
typed `Code`, `Format`, `Projection`, and `Program` descriptors. `Code` was not
a subtype of `Real`.

Its strengths were excellent depth, an unambiguous code/value distinction, and
one semantic path for scalar, arrays, blocks, and assurance. Its weakness was
that ordinary Julia numerical use became an adapter rather than the natural
surface. Arrays of `Code` would not participate naturally in promotion,
`AbstractFloat`, broadcasting, generic numeric algorithms, or display.

**Revision taken:** retain its single semantic seam and explicit code
construction, but make the scalar value a genuine one-byte `AbstractFloat`.

### 1.2 Design B: immutable semantic registry and plan compiler

The second design represented every operation, law, special rule, backend,
certificate, and storage layout in an immutable registry, then compiled registry
snapshots into typed plans.

Its strengths were extension, certificate invalidation, and clean separation of
semantics from execution. Its weakness was excess machinery for a package whose
defined operation catalogue and format family are fixed by a standard. A runtime
registry would add concepts, hashes, failure modes, and compilation work before
there is a second conforming operation catalogue that needs the seam.

**Revision taken:** use one declarative, build-time operation catalogue as the
single source of names, arities, special rules, factor counts, and generated
wrappers. Do not expose runtime registration for defined operations. Retain
immutable semantic digests for table artifacts and certificates.

### 1.3 Design C: raw-byte throughput engine

The third design made `UInt8` arrays the primary data model and put format,
operation, and projection only in prepared plans. This minimizes method
specialization and is ideal for large byte streams.

Its strengths were compilation locality, table-oriented throughput, and a very
small hot-loop vocabulary. Its weakness was safety: a `UInt8` carries no format
identity, so mixing formats is easy and scalar arithmetic needs ambient state or
an explicit plan everywhere.

**Revision taken:** public arrays contain one-byte `FloatByte` values, preserving
format identity in their element type. Dense execution obtains a zero-copy byte
view internally, so the loop retains the raw-byte design's throughput without
making untyped bytes the user's numeric model.

### 1.4 Final review: clarity

The combined design was revised to make five matters explicit:

- code construction is named `fromcode`; constructors never infer meaning from
  whether an integer happens to be unsigned;
- the fixed default used by Julia operators is immutable and documented;
- cold preparation, prepared scalar execution, and steady bulk execution have
  different performance contracts;
- stochastic entropy consumption is part of the interface, not hidden global
  state;
- a resource ceiling can return an inconclusive error, never an approximate
  defined result.

### 1.5 Final review: performance

The combined design was then revised for throughput:

- plans lower typed arrays to byte views once, outside loops;
- deterministic unary and binary work uses compact UInt8 tables;
- stochastic work may use precompiled decision records rather than recomputing
  the mathematical operation per element;
- structural operations may use certified byte laws;
- fixed-arity algebra and common block reductions use derived, fixed-size exact
  dyadic accumulators;
- packed execution uses caller-reusable tiles and fuses unpack/execute/repack;
- common tables may ship as checksummed artifacts;
- mutable defaults, runtime symbols, generic arrays, locks, and dictionaries are
  excluded from inner loops;
- performance gates include compilation, code size, cold build allocations, and
  memory traffic rather than timing only warm arithmetic.

The plan below is the result of those two review passes.

---

## 2. Product contract

### 2.1 Scope

FloatBytes implements every legal P3109 binary format with:

```text
3 <= K <= 8
```

For each K there are `4K - 2` legal combinations. The complete grid contains:

| K | 3 | 4 | 5 | 6 | 7 | 8 | total |
|---:|---:|---:|---:|---:|---:|---:|------:|
| formats | 10 | 14 | 18 | 22 | 26 | 30 | **120** |
| code points | 80 | 224 | 576 | 1,408 | 3,328 | 7,680 | **13,296** |

The package implements:

- the complete code lattice and draft decoding;
- deterministic and stochastic rounding;
- finite, propagating, and draft-directed saturation;
- the draft scalar operation catalogue;
- Julia numeric interoperability;
- dense, strided, packed, block, and scaled execution;
- exact reductions and dot products;
- explicit approximation with measured code distance;
- reproducible conformance records.

### 2.2 Non-goals

- K > 8 is not a dormant extension seam. It requires a different package or a
  future redesign.
- External subtyping of `FloatByte` is unsupported; it is a primitive type.
- Runtime registration of new defined operations is not supported initially.
- Approximate execution is never selected by a defined plan.
- Direct arithmetic on packed words is not a default strategy.
- Mutable session-wide rounding, result-format, or RNG defaults are not part of
  the performance interface.
- GPU execution is not promised until a real second execution adapter exists and
  passes the same assurance interface.
- A precision or time ceiling never licenses a guessed defined result.

### 2.3 Observable promise

Every defined operation means:

```text
decode operands exactly
    -> evaluate one mathematical operation exactly or enclose it rigorously
    -> project exactly once under the requested policy and random word
    -> return one canonical byte code
```

Table lookup, direct byte law, SIMD, threading, packing, plan caching, and
artifacts may change the cost. They may not change the code.

---

## 3. Mathematical envelope

The K <= 8 restriction is an implementation theorem and should be encoded in
tests before optimized code is written.

For a format with precision P and exponent bias B:

```text
signed:   B = 2^(K-P-1)
unsigned: B = 2^(K-P)
```

The maximum is `B = 128`, at unsigned K = 8, P = 1.

### 3.1 Datum facts

- Every datum has at most eight significant bits.
- Every datum is exactly representable in Float32 and Float64.
- The largest finite magnitude is at most `2^126` in the extremal P = 1
  unsigned format.
- The least positive datum is `2^-127`, exactly representable as a Float32
  subnormal and comfortably representable in Float64.
- The complete Float64 decode atlas occupies only `13,296 * 8 = 106,368` bytes.
- A Float32 twin occupies 53,184 bytes.

Float32 datum exactness does not make Float32 a universal operation carrier.
Products in extreme unsigned formats leave its exponent range, directed modes
can observe pre-rounding, and stochastic modes require the exact discarded
fraction. Float64 is the ordinary evaluator head; Float32 execution requires a
per-signature proof or explicit approximation certificate.

### 3.2 Fixed expression facts

The standard scalar catalogue has at most two datum factors in any monomial.
Scaled fixed-arity operations contain at most four. Therefore:

```text
two factors:  sum(Bi) <= 256, sum(Pi) <= 16
four factors: sum(Bi) <= 512, sum(Pi) <= 32
```

Float64 has ample range and precision for each fixed product. It is not an exact
sum carrier when terms have widely separated exponents. The finite K8 envelope
instead lets each fixed algebraic signature derive a small, statically sized
integer accumulator from its factor count and exponent span. This preserves the
entire discarded fraction needed by directed and stochastic projection without
heap allocation. Divisions and square roots require ratio/remainder reasoning;
transcendentals require enclosures. Arbitrary reductions derive their width
from length and exponent span before execution.

### 3.3 Finite-domain facts

| specialization | maximum entries | UInt8 result bytes |
|---|---:|---:|
| unary | 256 | 256 B |
| binary | 65,536 | 64 KiB |
| ternary | 16,777,216 | 16 MiB |

Every deterministic unary and binary specialization is safe to materialize.
Not every such table is worth retaining, so the aggregate store remains
byte-bounded. Maximum-width ternary tables are safe in memory but generally poor
cache and build investments; they require a plan decision.

### 3.4 Envelope gate

Add one exhaustive build gate proving across all 120 formats:

1. legality and count of every format;
2. exactly `2^K` canonical codes;
3. high bits zero for every safely constructed value;
4. Float32 and Float64 decode exactness;
5. code/decode/order round trips;
6. two- and four-factor range and precision bounds;
7. table-size and index arithmetic bounds;
8. `sizeof(FloatByte{...}) == 1`;
9. concrete inference of format metadata;
10. absence of any production path whose carrier selection depends on K.

These premises must be machine-checked because almost every performance
decision relies on them.

---

## 4. Public interface

### 4.1 Format and value types

Use descriptive type parameters rather than Boolean flags in user-facing
printing:

```julia
abstract type Signedness end
struct Signed   <: Signedness end
struct Unsigned <: Signedness end

abstract type DomainKind end
struct Finite   <: DomainKind end
struct Extended <: DomainKind end

primitive type FloatByte{K,P,S<:Signedness,D<:DomainKind} <: AbstractFloat 8 end
```

Examples:

```julia
const Binary8p4se = FloatByte{8,4,Signed,Extended}
const Binary5p2uf = FloatByte{5,2,Unsigned,Finite}
```

All 120 aliases live in `FloatBytes.Formats`. Export a deliberately small common
set from `FloatBytes`; programmatic code should use `format(K,P,S,D)` or the
parameterized type.

### 4.2 Code identity is explicit

Do not repeat the SmallFloats rule in which `UInt8` means code and other integers
mean numeric value. The meaning of a constructor argument should not depend on
its machine integer type.

```julia
fromcode(::Type{T}, code::Integer)::T
codepoint(x::FloatByte)::UInt8
isvalid(::Type{T}, code::Integer)::Bool
```

`fromcode` validates `0 <= code < 2^K`. The unchecked bitcast is private and may
be called only after a proof local to the caller.

Numeric construction is separate:

```julia
quantize(::Type{T}, value, policy; entropy=nothing)::T
T(value::Real)  # fixed documented default only
decode(x::FloatByte)::Float64
```

Every `T(value::Real)` argument, including every integer width, has numeric
meaning. Raw identity always uses `fromcode`.

A primitive bitstype can be fabricated with `reinterpret`; such a value may
contain nonzero high bits when K < 8. Document `reinterpret` into `FloatByte` as
unsafe. Public operations may use debug assertions, but hot loops rely on the
canonical-value invariant just as they rely on array element types.

### 4.3 Operation tags and signatures

Operations are singleton values generated from a closed declarative catalogue:

```julia
const Add      = Operation{:Add,2}()
const Exp      = Operation{:Exp,1}()
const FMA      = Operation{:FMA,3}()
const Convert  = Operation{:Convert,1}()
```

An immutable signature names the complete defined function:

```julia
sig = signature(Add, ResultFormat, policy, OperandFormat1, OperandFormat2)
```

Its interface includes:

- operation and arity;
- result and operand formats;
- projection policy;
- stochastic bit consumption;
- semantic revision;
- whether an in-place same-index traversal is safe;
- whether direct-code and table adapters are certified.

The common scalar spelling is:

```julia
z = apply(Add, ResultFormat, RNE_SN, x, y)
z = apply(sig, x, y)
```

Prepared execution is:

```julia
plan = prepare(sig; execution=:auto)
z = apply(plan, x, y)
execute!(dest, plan, xs, ys)
```

`prepare` is optional for correctness and valuable for repeated work. It makes
cold cost and execution choice explicit without forcing every scalar caller to
learn planning.

### 4.4 Array interface

```julia
execute!(dest, plan, sources...; entropy=nothing, workspace=nothing)
execute(plan, sources...; entropy=nothing)  # allocating convenience
```

The dense adapter supports `Array`, `Memory`, and simple strided arrays. A
generic `AbstractArray` adapter validates axes and traversal, then delegates or
falls back outside the hot module.

Array error behavior:

- incompatible axes: `DimensionMismatch` before mutation;
- wrong element format: `ArgumentError` before mutation;
- unsafe overlapping traversal: `AliasingError` or an explicit scratch plan;
- stochastic plan without entropy: `EntropyRequiredError`;
- missing or undersized workspace: `WorkspaceError` before mutation;
- unsupported storage: `UnsupportedExecutionError`, never silent scalarization
  with surprising allocation.

### 4.5 Julia operators

Base operators are an ergonomic adapter, not the semantic interface:

```julia
x + y
exp(x)
fma(x, y, z)
```

They require same-format operands and use one immutable package policy, proposed
as nearest-ties-even plus draft `SatNone`. There is no mutable global projection
default in the core package. Callers needing another result format or policy use
`apply` explicitly.

A separate optional `DynamicContext` adapter may provide task-scoped exploratory
defaults. Its documentation must state that explicit signatures are the
performance interface and that context lookup happens outside hot loops.

---

## 5. Architectural invariants

1. **One projection.** A logical defined result is projected exactly once.
2. **One-byte identity.** Every canonical `FloatByte` occupies one byte and has
   zero high bits beyond K.
3. **Named code construction.** `fromcode` is the only safe code-identity input;
   numeric constructors always mean numeric value.
4. **Exact decode.** Every canonical value decodes exactly to Float32 and
   Float64; `decode` returns Float64 by default.
5. **Semantics before execution.** Operation meaning cannot depend on storage,
   table state, thread count, SIMD width, or plan choice.
6. **Projection owns codes.** Only Projection and a certified final-code adapter
   may choose a result code.
7. **Certified collapse.** A direct byte law or final-code kernel exists only
   with an exhaustive equivalence certificate for its applicability domain.
8. **Immutable prepared plans.** A plan never observes mutable policy after
   construction.
9. **No hot metadata.** Inner loops contain no registry lookup, format
   validation, symbol dispatch, dictionary lookup, cache lock, or strategy
   branch.
10. **Tables are compiled semantics.** Every entry comes from the same defined
    seam or a certified equivalent; tables never define behavior.
11. **Complete publication.** A table becomes visible only after full immutable
    construction and checksum validation.
12. **Indexed stochastic meaning.** A stochastic logical output consumes exactly
    one N-bit word identified independently of scheduling.
13. **Defined and approximate plans are disjoint types.** A defined request can
    never select approximation.
14. **Exact reductions are order-independent.** Thread partitioning and merge
    order cannot change a result code.
15. **Inconclusive is not approximate.** If rigorous projection cannot be
    decided within an explicit resource limit, execution throws an
    `InconclusiveProjectionError` without mutating the output element.
16. **Closed defined catalogue.** The standard operation list has one source;
    wrappers, arities, tables, tests, and conformance are derived from it.

---

## 6. Deep module architecture

```text
                         Julia adapters
                    constructors / Base / arrays
                               |
                               v
Byte Domain -------> Defined Signature -------> Plan Compiler
     |                       |                       |
     |                       v                       v
     +--------------> Defined Semantics       Execution adapters
                             |                 code / LUT / decision /
                             v                 compute / packed / block
                         Projection <-----------------+
                             |
                             v
                         result code

Assurance independently observes Byte Domain, Defined Semantics, Projection,
and every Execution adapter.
```

All dependencies are in-process computation. There is no reason for public
ports. Internal seams exist only where at least two adapters are real.

### 6.1 Byte Domain module

Interface:

```julia
fromcode, codepoint, decode, decode32, format, metadata,
classify, totalorder, nextup, nextdown
```

Implementation hidden behind it:

- primitive bitcasts and canonical-code validation;
- format descriptor atlas;
- masks, special codes, extrema, and order transforms;
- exact Float32/Float64 decode atlases;
- display names and parse metadata;
- byte views over dense arrays.

The module is deep because deleting it would spread bit layout, validity,
decode, ordering, and naming into projection, operations, tables, display, and
tests.

### 6.2 Projection module

Interface:

```julia
project_code(result_format, policy, projection_input, random_word)::UInt8
project_interval(result_format, policy, enclosure, random_word)::UInt8
```

Implementation hidden behind it:

- exact neighbor selection;
- midpoint and directed comparisons;
- all stochastic decision predicates;
- saturation and special-value rows;
- normal/subnormal encoding;
- symbolic sidedness at asymptotes;
- precision escalation agreement.

Projection is the semantic authority for output codes. It should not know about
arrays, caches, plans, or operation names.

### 6.3 Defined Semantics module

Interface:

```julia
evaluate_exact(operation, exact_operands...)::ProjectionInput
defined_code(signature, random_word, operand_codes...)::UInt8
```

`defined_code` is the main internal seam. It decodes, evaluates, and projects.
The lower `evaluate_exact` interface is private to semantic-family tests and
the plan compiler.

Implementation hidden behind it:

- special-value decision tables;
- bounded exact-dyadic add, product, FMA, FAA, and conversion;
- quotient/remainder projection inputs;
- exact selection and sign rules;
- square-root bracketing;
- transcendental range reduction and directed enclosures;
- result protocol specialization.

### 6.4 Plan Compiler module

Interface:

```julia
prepare(signature; execution=:auto, cache=default_store())::ExecutionPlan
plan_traits(plan)::PlanTraits
workspace_spec(plan)::WorkspaceSpec
```

Implementation hidden behind it:

- semantic artifact lookup and validation;
- direct-code certificate lookup;
- table admission and construction;
- CPU feature and storage inspection;
- cost model and thread thresholds;
- aliasing classification;
- concrete executor selection;
- workspace sizing.

The planner is cost-only. A different plan may never change a result.

### 6.5 Assurance module

Interface:

```julia
verify(signature_or_plan; scope=:standard)::VerificationReport
certify(candidate, signature; scope=:exhaustive)::Certificate
conformance(subject)::ConformanceRecord
```

Implementation hidden behind it:

- independent rational and MPFR reference adapters;
- exhaustive domain traversal;
- code-distance measurement;
- certificate and artifact digests;
- exhaustive-versus-sampled labels;
- differential execution across adapters;
- provenance and version reporting.

Assurance is separate from execution so production speed does not depend on
test machinery, while both speak the same immutable signatures and codes.

---

## 7. Byte Domain implementation

### 7.1 Primitive representation

```julia
@inline codepoint(x::T) where {T<:FloatByte} = reinterpret(UInt8, x)
@inline _unsafe_fromcode(::Type{T}, c::UInt8) where {T<:FloatByte} =
    reinterpret(T, c)
```

Safe construction validates once. Internal callers name their proof:

- table entry already certified;
- code masked by format mask;
- code loaded from an array with canonical element type;
- projection returned a canonical code.

Avoid a generic public `rawvalue`. An unsafe primitive with broad visibility
invites callers to bypass the only invariant that makes byte kernels safe.

### 7.2 Descriptor atlas

The grid is fixed and small. Assign each legal format a dense `FormatID` and
build immutable descriptors containing:

```text
K, P, signedness, domain, bias,
code mask, sign mask, trailing mask,
NaN and infinity codes,
finite extrema, order transform,
decode offsets, display name
```

For a statically known `FloatByte` type, metadata functions constant-fold from
type parameters. Prepared value-keyed plans use `FormatID` to avoid creating a
method specialization for every metadata query.

This hybrid is deliberate:

- scalar syntax benefits from type specialization;
- plan preparation and cache keys benefit from compact values;
- hot bulk loops have already resolved both and use neither.

### 7.3 Decode atlas

Benchmark three implementations:

1. direct Float64 bit assembly;
2. per-format immutable tuples;
3. one concatenated immutable atlas indexed by a folded offset.

The entire Float64 atlas is about 104 KiB and the Float32 twin about 52 KiB.
The atlas is the preferred starting point because it avoids large generated
syntax while remaining L2-resident as a whole and L1-resident per active
format.

Selection requires measurements of:

- random and sequential scalar decode;
- bulk decode;
- constant-code folding;
- package image size;
- load time and first use;
- native-code size.

Do not keep multiple production decode implementations after the winner is
known. The independent reference decoder remains in Assurance.

### 7.4 Ordering and sorting

Use a `UInt16` monotone order key: at most 256 datum keys plus one NaN sentinel.
Classification and next operations should operate directly on codes.

For sorting, provide:

- counting sort for sufficiently long same-format dense vectors;
- Base comparison sort below the measured break-even;
- an optional caller-owned `SortWorkspace` for repeated zero-allocation sorts.

The 257-counter scratch is small. Do not hide a shared mutable scratch buffer
whose concurrency semantics are harder than the allocation it saves.

---

## 8. Projection and exact-result protocol

### 8.1 Projection inputs

Use a small internal protocol rather than a universal BigFloat:

```text
ExactDyad{L}   signed fixed-limb significand and binary exponent
ExactRatio{L}  fixed-limb numerator, denominator, and binary exponent
Special        NaN, positive infinity, negative infinity, exact zero
Enclosure      directed lower/upper bounds with provenance
```

The concrete representations may be several specialized types. They should not
escape the module interface.

### 8.2 Algebraic operations

- Multiply and fixed products use widened integers and exponents; K8 bounds make
  these compact and exact.
- At signature preparation, derive the limb count for every fixed expression
  from its minimum exponent, maximum exponent, factor count, significand bits,
  and carry bits. Select a concrete `ExactDyad{L}` evaluator.
- Add/Subtract, FMA, and FAA align terms into that fixed accumulator. Even a
  widely separated low term is retained exactly, so cancellation, directed
  rounding, and stochastic cutoffs see its magnitude rather than only its sign.
- A proven Float64 or head-tail filter may return early when projection is
  unambiguous, but the fixed accumulator is the allocation-free authority for
  difficult finite cases.
- Divide produces quotient/remainder information sufficient for every rounding
  and stochastic predicate; it need not create an inexact Float64 quotient.
- Square root uses integer square-root and remainder logic where profitable, or
  a certified bracket.
- Min/max/sign/selection families return exact operands or specials.

Float64 remains a useful optimized implementation, but it is not the semantic
type. Any Float64 shortcut must prove that its `ProjectionInput` matches the
integer implementation.

### 8.3 Transcendentals

Use a Ziv-style rigorous loop:

1. handle all exact and special cases symbolically;
2. produce a directed enclosure at modest precision;
3. project the lower endpoint with positive sidedness and the upper endpoint
   with negative sidedness under the same policy and random word;
4. return when both projections agree;
5. otherwise increase precision and repeat.

Float64 libm and optional Float128 estimates may be used as early filters only
when an envelope is justified and endpoint agreement is checked. MPFR through
function-scoped precision and rounding is the final in-process implementation.

Asymptotes retain symbolic sidedness: numerically reaching `1` does not erase
the distinction between exact `1` and `1-ε`.

If a caller supplies a precision ceiling and the enclosure remains undecided,
throw `InconclusiveProjectionError` with the signature, operand codes,
precisions, and final enclosure. Never return a midpoint or approximate code.

### 8.4 Certified byte laws

Candidate laws include classification, stepping, exact selection, same-format
absolute value, signed negation, sign copying, and some conversions.

Each law declares a static applicability predicate and is activated only after:

- exhaustive enumeration of its whole input domain;
- every supported deterministic policy in scope;
- special-value and format-domain cases;
- comparison against `defined_code` and the independent reference;
- a benchmark demonstrating a material win.

A law that returns a final code has a stronger proof obligation than a law that
returns an exact projection input. Keep the narrowest bypass possible.

---

## 9. Defined operation catalogue

The defined catalogue is closed, immutable source data. One row contains:

```text
operation tag
arity
semantic family
special-rule family
maximum monomial factors
symmetry/selection laws
table eligibility
direct-code candidate
Base wrapper name
block/scaled eligibility
verification tier
```

From this source generate:

- singleton operation values;
- arity-specific `apply` methods;
- public named wrappers where desired;
- Base adapters;
- plan signature validation;
- table compiler dispatch;
- block/scaled entry points;
- conformance declarations;
- test manifests.

Do not generate semantic formulas from strings or expression trees at runtime.
Each semantic family is ordinary reviewed Julia code. The catalogue prevents
lists and surfaces from drifting; it does not replace implementation with a
meta-language.

Third-party custom defined operations are deferred. A custom candidate may be
certified as an approximation or exact external plan, but it is not silently
added to the standard conformance claim.

---

## 10. Plan Compiler and execution adapters

### 10.1 Plan classes

```text
DirectCodePlan
UnaryTablePlan
BinaryTablePlan
StochasticDecisionPlan
TernaryTablePlan
TernaryComputePlan
DenseComputePlan
PackedTilePlan
ExactReductionPlan
GenericArrayPlan
```

Plans are immutable. A table plan owns a strong reference to its immutable
table, so eviction from the shared store cannot invalidate a running plan.

### 10.2 Dense byte lowering

A `Vector{FloatByte{...}}` already occupies one byte per element. The dense
adapter obtains a byte view once and runs a loop over `UInt8` storage. Result
construction is therefore not repeated per element.

The hot table loop is conceptually:

```julia
@inbounds @simd for i in eachindex(out, a, b)
    index = Int((UInt16(abytes[i]) << K2) | UInt16(bbytes[i])) + 1
    outbytes[i] = table[index]
end
```

Parenthesize index arithmetic explicitly in production code. Mixed-format
compact tables use the actual K2 stride; fixed 256-byte row strides are a
separate benchmark candidate, not an assumption.

### 10.3 Generic array adapter

Generic axes, offset indices, unusual strides, and views are handled by a
separate adapter. It may use typed scalar access and remain slower. This keeps
the dense loop small and lets its performance contract be precise.

The planner may copy to a tile only when the cost model predicts amortization
and aliasing permits it. It reports the chosen strategy through `plan_traits`.

### 10.4 Threading

Use different thresholds for:

- byte copy/direct law;
- unary gather;
- binary gather;
- ternary compute;
- packed tiles;
- exact reductions.

Table gathers are often limited by cache or memory bandwidth; threading them at
small sizes is counterproductive. Calibrate thresholds per CPU class and allow
explicit overrides at plan preparation.

Threaded deterministic execution must produce identical bytes. Exact reduction
adapters merge exact accumulators, so their result is independent of partition
and merge order.

### 10.5 SIMD

SIMD is an adapter, not a slogan. AVX2 has no general byte gather from a 64 KiB
table. Several independent scalar loads may win. Low-K tables may admit shuffle
kernels; AVX-512 VBMI changes the available strategies.

Add a SIMD plan only when:

- it is exhaustive-code equivalent;
- CPU feature detection happens at preparation;
- tail handling is tested at every short length;
- unaligned and aliased cases are specified;
- it beats the generic dense plan on supported CPUs.

An algebraic Float32 SIMD kernel belongs in a defined plan only where exhaustive
certification proves exact output codes for the complete signature. Otherwise it
is an explicit approximate plan with measured κ.

### 10.6 Fusion

Permit fusion of storage transformations and execution:

```text
unpack -> one defined operation -> repack
decode -> external Float32/Float64 output
external exact input -> quantize -> pack
```

Do not fuse two defined arithmetic operations across a mandated intermediate
projection. `Exp(Add(x,y))` and a fused real `exp(x+y)` are different defined
programs when Add's result must first be a FloatByte.

---

## 11. Table compiler and store

### 11.1 Deterministic result tables

Every deterministic unary and binary plan is eligible:

```text
unary  <= 256 bytes
binary <= 64 KiB
```

Build compact tables in operand-linear order by calling `defined_code` for every
entry. Arity-specific builders avoid dynamic splats. Decode tables and reusable
oracle scratch are hoisted outside loops.

Build requirements:

- allocate the result table once;
- no closure or heap allocation per entry;
- parallelize large expensive builds by contiguous outer-code rows;
- use task-local rigorous scratch;
- publish only after completion and checksum;
- allow benign duplicate racing builds, with one published winner;
- never hold a global cache lock during semantic evaluation.

### 11.2 Table store

Keys contain compact IDs and semantic identity:

```text
draft revision
semantic engine revision
operation ID
result and operand FormatIDs
projection ID
table layout version
```

Use a byte-bounded LRU or CLOCK store. Unary tables may have a protected tiny
class because evicting a 256-byte object rarely saves meaningful space. Binary
and stochastic decision records share the main byte budget.

Cache observability includes hits, misses, builds, build time, evictions,
resident bytes, artifact loads, and declined ternary materializations.

### 11.3 Artifact-backed tables

Provide an optional standard table pack for the most common formats, operations,
and immutable default policy. Each binary artifact contains a header, semantic
digest, dimensions, layout, and checksum.

Artifact tables are accelerators, not authorities. Loading rejects any identity
or checksum mismatch and falls back to local compilation. The independent suite
re-verifies shipped artifacts entry-for-entry.

Do not ship the Cartesian product of 120 formats, all operations, all result
formats, and all policies. Select the pack from measured use profiles and keep
its size a release metric.

### 11.4 Ternary policy

Initial policy:

| combined K | entries | initial strategy |
|---:|---:|---|
| <= 18 | <= 256 KiB | eager table |
| 19–21 | <= 2 MiB | adaptive after reuse evidence |
| 22–24 | 4–16 MiB | compute unless explicitly requested or strongly amortized |

The thresholds are starting hypotheses. Benchmark cold build, warm lookup,
cache residency, and actual reuse before freezing defaults.

Prototype partial slabs for skewed ternary inputs only after the basic compute
plan is optimized. A slab fixes one or two operand codes and tabulates the
remaining dimension. It must use a local pointer directory so no dictionary
lookup occurs per element.

---

## 12. Stochastic execution

### 12.1 Entropy is explicit

The core stochastic interface requires an entropy adapter. There are two real
adapters:

1. `IndexedEntropy(seed, stream, invocation)` maps logical output index and draw
   slot to a stable counter-based word. It supports parallel, SIMD, packed, and
   tiled execution with schedule-independent results.
2. `SequentialEntropy(rng::AbstractRNG)` consumes a conventional stream in
   logical index order and therefore selects a sequential plan.

The defined contract consumes exactly one N-bit word per logical output for a
stochastic signature, including exact and special results. Fixed consumption
makes slicing, replay, and composition auditable.

The indexed key includes:

```text
algorithm version, seed, stream, invocation, logical index, projection slot
```

Counter reuse across different plans must require an explicit shared stream;
the convenience constructor derives a stream ID from the semantic signature.

### 12.2 Decision tables

A stochastic operation is not an input-only result table, but its expensive
mathematics can still be compiled. For unary and binary signatures, build a
decision table whose entry contains:

```text
lower result code
upper result code
exact/special flag
certified cutoff representation for the selected stochastic family and N
```

At execution, the adapter performs one indexed draw and one cutoff comparison.
For transcendental operations the table compiler raises enclosure precision
until the required N-bit cutoff is decided exactly.

Decision records are larger than result bytes and belong under a separate
admission budget. Compare them with direct compute before enabling by default.

### 12.3 Reproducibility gates

For the same signature, entropy identity, inputs, and logical origin, verify
identical bytes across:

- scalar execution;
- one and many threads;
- different chunk sizes;
- dense and packed storage;
- SIMD and generic loops;
- subarray calls with adjusted origins;
- table and decision-table implementations.

---

## 13. Blocks, scaled operations, and reductions

### 13.1 Storage

Use structure-of-arrays storage for many blocks:

```julia
struct BlockBytes{SF,EF,B}
    scales::Vector{SF}
    elements::Vector{EF}  # contiguous block-major lanes
end
```

Scalar `Block` values may use an `NTuple{B,EF}` for small static B. The execution
interface views both as logical scale-plus-lane data; semantics do not depend on
layout.

### 13.2 Exact fixed-size superaccumulators

K8 bounds make allocation-free exact reductions practical. Products of two
datums span a finite exponent window and carry at most 16 significant bits;
scaled products carry at most 32. For a known block length B, derive the number
of accumulator limbs from:

```text
minimum product exponent
maximum product exponent
maximum significand bits
ceil(log2(B)) carry bits
```

Use an isbits `StaticAccumulator{L}` backed by an `NTuple{L,UInt64}` or an
equivalent mutable stack workspace. Addition and merge are exact. Threaded dot
products merge exact accumulators and project once.

If the derived width exceeds the supported static ceiling, use a caller-owned
limb workspace or a BigInt cold adapter. The plan reports this before execution.

### 13.3 Fixed scaled operations

Represent decoded finite inputs internally as compact dyadics. Scaling by a
FloatByte scale becomes integer-significand multiplication plus exponent
addition; no Float128 carrier is needed. Form the complete mathematical
expression before projection.

Special-value algebra is handled before the finite fast path. Never round a
scale product and then feed that rounded value into the next operation unless
the standard explicitly requires that projection.

### 13.4 Performance target

The current SmallFloats evidence shows block dot products allocating heavily.
FloatBytes should make the common finite block/dot/reduce path zero allocation
with supplied destination/workspace, then optimize cycles per lane. Exactness
and allocation are release gates; timing is benchmark tuned.

---

## 14. Packed storage

```julia
struct PackedBytes{K}
    words::Vector{UInt64}
    length::Int
end
```

The format belongs to the view or plan; K determines the physical packing.
For typed user storage, provide `PackedVector{T<:FloatByte}` as the safe adapter.

Execution policy:

1. use explicit reusable UInt8 input/output tiles;
2. unpack codes, execute the selected byte plan, and repack in one traversal;
3. fuse histogram or slab selection only when the plan needs it;
4. specialize aligned K values where measured;
5. keep generic cross-word extraction as the correctness adapter;
6. make K = 8 an identity byte view rather than doing shifts for no saving.

Direct packed-word arithmetic is admitted only with exhaustive equivalence and a
measured end-to-end win. Microbenchmarking extraction alone is insufficient.

Alias behavior and partial final words must be explicit. Unused tail bits are
zeroed deterministically so packed equality and hashing are stable.

---

## 15. Approximation and conformance

### 15.1 Approximation is plan-local

An approximate implementation is an explicitly named `ApproxPlan` tied to one
defined signature and one certificate:

```julia
candidate = approximate(:hardware_exp, signature)
certificate = certify(candidate, signature; scope=:exhaustive)
plan = prepare(candidate, certificate)
```

There is no mutable global registry consulted by defined execution. A caller
must possess and pass the approximate plan.

The certificate records:

- semantic and candidate digests;
- formats and policy;
- metric and maximum code distance κ;
- NaN/infinity mismatch status;
- exhaustive or sampled domain;
- generator, seed, and sample count when sampled;
- toolchain identity.

For unary and binary K8 domains, exhaustive certification is the default and is
required for a conformance κ bound. A sampled ternary result is an estimate and
must not be described as a proved bound.

### 15.2 Conformance records

`conformance(subject)` returns immutable data containing:

- package and semantic revisions;
- retained draft identity and digest;
- supported format and operation catalogues;
- projection and entropy policies;
- plan type and execution adapter;
- artifact/certificate digests;
- exhaustive and sampled verification claims;
- optional dependency/backend versions.

Reporting is derived from live catalogues and immutable plan data, not copied
strings.

---

## 16. Julia interoperability

Implement the expected `AbstractFloat` surface deliberately:

- `zero`, `one`, `typemin`, `typemax`, `floatmin`, `floatmax`, `eps`;
- `iszero`, `isfinite`, `isinf`, `isnan`, `signbit`, classification;
- comparison, `isless`, total order, hashing, and equality;
- conversion to and from Float16, Float32, Float64, BigFloat, and integers;
- promotion with external numeric types to a host type that represents every
  datum exactly;
- parsing and stable display;
- `rand` and `randn` with their distributions documented separately from
  stochastic rounding;
- `reinterpret(UInt8, array)` zero-copy behavior where Julia permits it;
- `broadcast`, `similar`, and array allocation with concrete element types.

Promotion should prefer Float64 for mixed arithmetic. It is exact for every
datum and avoids pretending that a cross-format FloatByte join is canonical.
Projecting back remains explicit.

Do not overload raw unsigned constructors as code identity. Do not use mutable
defaults to make Base operators context-sensitive. Predictable Julia behavior is
part of performance because it keeps inference stable.

---

## 17. Verification architecture

### 17.1 Independent authority

Build an independent reference from the draft using:

- `Rational{BigInt}` for finite dyadic formats and algebraic operations;
- separately coded special-value tables;
- explicit projection-cell comparisons;
- directed MPFR intervals for transcendental operations.

It must not call production decode, projection, special rules, operation
kernels, or table indexing. SmallFloats K3:8 is a second differential adapter,
not the primary authority.

### 17.2 Verification tiers

**T1 — Byte lattice, exhaustive.** All 13,296 codes: validity, decode, encode,
class, order, next, display/parse, Float32/Float64 exactness.

**T2 — Projection cells, exhaustive by parameter tuple.** Every format grid
edge, midpoint, adjacent representable value, saturation edge, exact point,
special kind, rounding mode, and selected stochastic words.

**T3 — Semantic families.** Exhaustive unary inputs and binary inputs per
representative/equivalence class; exact rational differential for algebraic
families; rigorous interval differential for elementary families.

**T4 — Tables and plans.** Entry-for-entry equality for every materialized unary,
binary, ternary, and stochastic decision table. Dense, generic, packed, direct,
SIMD, threaded, and block adapters compare bytes with scalar `defined_code`.

**T5 — Stochastic.** Exhaust all random words at tractable N, pin maximum N
edges, and compare logical-index reproducibility across execution shapes.

**T6 — Blocks and reductions.** Independent exact sums/products across block
sizes, cancellation, exponent extremes, specials, scaling, thread partitions,
and accumulator-width transitions.

**T7 — Assurance failure injection.** Corrupt artifacts, stale digests,
insufficient workspaces, invalid codes, unavailable optional adapters,
inconclusive enclosures, alias violations, and sampled certificates.

**T8 — Julia interface.** Inference, allocations, promotion, generic algorithms,
array creation, parsing, hashing, and documentation examples.

### 17.3 Adapter equivalence

For every applicable plan:

```text
independent reference
    == defined_code
    == direct byte law
    == locally compiled table
    == artifact table
    == dense execution
    == generic execution
    == SIMD execution
    == threaded execution
    == packed execution
```

The comparison is code identity in identical logical order. Numerical tolerance
is not evidence for a finite code function.

### 17.4 Static performance gates

Test deterministically that prepared hot paths have:

- concrete inferred result types;
- zero warm allocations where promised;
- no dynamic dispatch inside loops;
- no lock/dictionary/symbol lookup inside loops;
- bounded table size before allocation;
- strong table lifetime while plans exist;
- workspace validation before destination mutation;
- no invalidation explosion from loading optional extensions.

Timing remains in the benchmark suite.

---

## 18. Performance program

### 18.1 Evidence baseline

The current SmallFloats K8 paths provide useful comparison evidence on the
recorded reference machine:

| case | current evidence |
|---|---:|
| decode | about 1.3 ns |
| scalar Add | about 9.4 ns median |
| scalar Multiply | about 7.4 ns median |
| unary table gather | about 0.14 ns/element |
| binary table gather | about 0.26 ns/element |
| ternary FMA compute | about 15.4 ns/element |
| 256-entry Exp table build | about 31 microseconds, 257 allocations |
| 65,536-entry Add table build | about 15.8 milliseconds, roughly 459,000 allocations |
| block dot, B = 32 | about 1.24 microseconds, 66 allocations |

Machine, Julia version, thread count, and harness discipline must accompany any
comparison. These numbers are baselines, not portable promises.

### 18.2 Measurement states

Report separately:

1. package load and precompile;
2. first semantic scalar call;
3. cold plan preparation;
4. cold local table compilation;
5. artifact-backed preparation;
6. prepared scalar execution;
7. warm bulk execution;
8. cache eviction/rebuild;
9. rigorous fallback frequency and precision;
10. workspace allocation versus reuse.

Mixing these states produces meaningless averages.

### 18.3 Benchmark inputs

Use:

- uniform random codes;
- sequential codes;
- all zero and constant codes;
- sparse zeros;
- Zipf/skewed values;
- alternating extrema and special values;
- cancellation-heavy arithmetic;
- exact versus enclosure-triggering inputs;
- contiguous, strided, offset, packed, and aliased layouts;
- realistic activation, weight, and block traces where available.

### 18.4 Initial targets

Ratio gates on the same machine take precedence over absolute times.

1. Preserve unary and binary warm gather throughput within 10% of the current
   implementation.
2. Prepared scalar unary lookup at or below 2 ns and binary lookup at or below
   3 ns, zero allocation.
3. Direct-code structural scalar operations materially faster than current
   scalar evaluation and no slower than prepared lookup.
4. Reduce maximum binary table-build allocations from hundreds of thousands to
   fewer than 1,000 initially, then pursue a result-table plus bounded-scratch
   allocation profile.
5. Improve cold binary table build by at least 4x before considering the table
   compiler complete.
6. Make common finite block dot/reduce paths zero allocation and at least 3x
   faster than the current evidence.
7. Improve maximum-width ternary compute by at least 1.5x or document that the
   rigorous evaluator, rather than loop structure, is the floor.
8. Counter-based stochastic bulk execution must scale across threads without
   changing bytes; target at least 60% parallel efficiency before memory
   saturation.
9. Packed execution with reused workspace should achieve at least 80% of the
   measured unpack -> byte-plan -> pack roofline.
10. Package load, first call, method-instance count, invalidations, native-code
    size, and artifact footprint are release metrics with recorded ceilings.

An optimization that misses its target is deleted. Dormant adapters still cost
tests, compilation, and maintainer knowledge.

### 18.5 Reporting

Every bulk result reports:

- cycles and nanoseconds per element;
- elements per second;
- bytes read and written;
- table and active working-set size;
- likely cache level;
- allocation count and bytes;
- threads and parallel efficiency;
- CPU model and ISA;
- cold/prepared/warm state.

---

## 19. Dependencies and extensions

Core dependencies should be minimal:

- Julia `Random`, `SHA`, threading primitives, and `BigInt`/`BigFloat`;
- `PrecompileTools` only if measured first-use benefit exceeds image cost.

Optional package extensions may provide:

- Float128 filters through Quadmath;
- BFloat16 interoperability;
- architecture-specific SIMD;
- stable external RNG adapters;
- GPU execution after it satisfies Assurance;
- artifact table packs.

MPFR is an in-process implementation detail while it is the sole rigorous
transcendental implementation. Do not expose a hypothetical backend seam.
Float128 is an accelerator in this design, never the meaning of a datum and
never a correctness dependency.

Optional extensions may improve cost only. The core fallback remains complete
and bit-identical.

---

## 20. Source layout

```text
FloatBytes.jl/
├── Project.toml
├── src/
│   ├── FloatBytes.jl
│   ├── domain.jl
│   ├── formats.jl
│   ├── policies.jl
│   ├── projection.jl
│   ├── result_protocol.jl
│   ├── semantics.jl
│   ├── operations/
│   │   ├── algebraic.jl
│   │   ├── selection.jl
│   │   ├── elementary.jl
│   │   └── conversion.jl
│   ├── signatures.jl
│   ├── planning.jl
│   ├── tables.jl
│   ├── execution/
│   │   ├── dense.jl
│   │   ├── generic.jl
│   │   ├── stochastic.jl
│   │   └── threaded.jl
│   ├── blocks.jl
│   ├── packed.jl
│   ├── approximation.jl
│   ├── conformance.jl
│   └── julia_adapters.jl
├── ext/
│   ├── FloatBytesQuadmathExt.jl
│   ├── FloatBytesBFloat16Ext.jl
│   └── FloatBytesSIMDExt.jl
├── reference/
│   ├── draft_model.jl
│   ├── rational_projection.jl
│   └── interval_oracle.jl
├── test/
│   ├── lattice.jl
│   ├── projection.jl
│   ├── semantics.jl
│   ├── plans.jl
│   ├── stochastic.jl
│   ├── blocks.jl
│   ├── packed.jl
│   ├── assurance.jl
│   └── julia_interface.jl
├── benchmark/
│   ├── baseline.jl
│   ├── scalar.jl
│   ├── tables.jl
│   ├── arrays.jl
│   ├── stochastic.jl
│   ├── blocks.jl
│   └── packed.jl
└── docs/
```

These are ownership suggestions, not a mandate for many shallow files. Merge
files when their interfaces and knowledge move together. Preserve the five deep
modules even if their implementations span different physical files.

---

## 21. Implementation stages

Every stage produces a green, reviewable package. Optimization begins only
after independent defined behavior exists.

### Stage 0 — Charter and evidence

1. Freeze the retained draft text and digest.
2. Record SmallFloats K3:8 code-point goldens and performance evidence.
3. Write the FloatBytes public contract, error taxonomy, and non-goals.
4. Create benchmark and verification manifests before production code.
5. Implement the K8 envelope gate as a standalone script/test.

**Exit:** scope, authority, baselines, and measurable targets are reproducible.

### Stage 1 — Independent reference

1. Implement format validation and decoding from the draft in `reference/`.
2. Implement exact rational projection independently.
3. Implement special-value rows independently.
4. Generate a compact golden corpus for all 13,296 codes and all projection
   edges.
5. Differentially compare with SmallFloats and resolve every disagreement
   against the draft rather than choosing a side by majority.

**Exit:** a slow, clear authority exists that production cannot accidentally
call.

### Stage 2 — Byte Domain

1. Add the primitive type and explicit `fromcode`.
2. Add metadata, masks, aliases, code identity, classification, and ordering.
3. Add the candidate decode atlas.
4. Exhaustively compare production domain behavior with the independent model.
5. Pin one-byte layout, concrete inference, and no-allocation scalar access.

**Exit:** every format and code point exists correctly; no arithmetic yet.

### Stage 3 — Projection

1. Define the projection-input protocol.
2. Implement nearest, directed, odd, and stochastic decisions.
3. Implement saturation and encoding.
4. Add signature-derived fixed-limb exact dyad and ratio support.
5. Exhaustively compare projection cells and random-word decisions with the
   independent model.

**Exit:** Projection is the only production code-producing implementation and
is independently verified.

### Stage 4 — Minimal semantic spine

Implement representative operations from every semantic family:

- Convert;
- Abs/Negate;
- Add/Multiply;
- Divide/Sqrt;
- FMA/FAA;
- Minimum/Maximum;
- Exp/Log/Sin.

Add `defined_code`, signatures, and scalar `apply`. Use the rigorous enclosure
loop for elementary operations.

**Exit:** the architecture proves it can express exact, sticky, ratio, special,
selection, and enclosure results before the full catalogue is added.

### Stage 5 — Julia scalar interface

1. Add fixed-policy numeric constructors.
2. Add conversions, promotion, display, parsing, equality, hashing, and Base
   operations.
3. Add `Formats` aliases and documentation.
4. Establish scalar inference, allocation, and timing baselines.

**Exit:** FloatBytes works as a small Julia float without mutable context.

### Stage 6 — Table compiler and prepared plans

1. Implement compact unary and binary table builders through `defined_code`.
2. Implement immutable tables, semantic keys, strong plan ownership, and the
   byte-bounded store.
3. Implement `prepare`, prepared scalar lookup, and dense byte execution.
4. Eliminate per-entry allocation from common table builds.
5. Add artifact format and verifier, but ship no large pack yet.

**Exit:** table build and warm execution targets pass; every entry matches the
independent reference.

### Stage 7 — Full defined catalogue

Add remaining operations family by family. Each operation supplies:

- special behavior;
- exact/enclosure implementation;
- projection interaction;
- unary/binary/ternary table policy;
- verification tier;
- scalar and bulk benchmarks;
- conformance metadata.

**Exit:** the retained standard catalogue is complete and generated surfaces
cannot drift.

### Stage 8 — Stochastic plans

1. Implement indexed and sequential entropy adapters.
2. Specify the stable counter algorithm and stream derivation.
3. Implement stochastic decision records for unary and binary signatures.
4. Add parallel and tiled stochastic execution.
5. Prove logical-index reproducibility across adapters.

**Exit:** stochastic execution is exact, explicit, reproducible, and fast.

### Stage 9 — Ternary, direct-code, SIMD, and threading optimization

1. Establish optimized ternary compute as the baseline.
2. Add table/adaptive bands from measurements.
3. Add one certified code law at a time.
4. Add SIMD only on CPUs and signatures where it wins.
5. Tune per-plan thread thresholds.

**Exit:** every retained adapter has evidence, a performance win, and exact byte
equivalence. Losing experiments are removed.

### Stage 10 — Blocks and reductions

1. Implement Block and structure-of-arrays BlockBytes.
2. Implement derived static superaccumulators.
3. Add scaled fixed expressions without intermediate projection.
4. Add exact threaded reduction merge.
5. Add fallback workspace for exceptional widths.

**Exit:** common finite block paths allocate zero and meet throughput targets;
all paths match the independent reference.

### Stage 11 — Packed execution

1. Implement PackedVector and canonical tail bits.
2. Add reusable byte tiles.
3. Fuse unpack/execute/repack.
4. Add aligned specialized adapters only when measured.
5. Verify aliasing, offsets, short tails, and stochastic origins.

**Exit:** packed end-to-end targets pass without a second semantic path.

### Stage 12 — Approximation and conformance

1. Implement candidate certification and κ measurement.
2. Require explicit ApproxPlan selection.
3. Implement immutable conformance records and reports.
4. Add artifact/certificate failure injection.
5. Verify that defined preparation cannot select an approximate adapter.

**Exit:** approximation is evidence-bearing and structurally absent from defined
plans.

### Stage 13 — Optimization review and release

1. Run the full benchmark matrix on at least x86-64 and AArch64.
2. Review every internal seam with the deletion test.
3. Delete adapters that have only one implementation or no measured win.
4. Review every public name and error mode for clarity.
5. Measure load, TTFX, method instances, invalidations, code size, cache memory,
   and artifact footprint.
6. Run all exhaustive, differential, static-analysis, docs, and package-quality
   gates.

**Exit:** the release is smaller in concepts than its implementation, faster in
measured workloads, and independently correct.

---

## 22. Risks and mitigations

| risk | failure | mitigation |
|---|---|---|
| primitive reinterpret creates invalid high bits | undefined semantic input | explicit `fromcode`; private unsafe path; exhaustive canonical construction tests |
| fixed-limb kernel mishandles span or cancellation | wrong directed/stochastic result | mechanically derive and assert width; independent rational differential; exponent-gap and cancellation tests |
| table becomes semantic authority | stale or wrong results | semantic digest, checksum, entry differential, local rebuild fallback |
| plan store evicts a live table | invalid memory reference | immutable GC-owned table held strongly by plan |
| operation catalogue becomes a meta-language | opaque implementation | catalogue stores metadata only; semantic families remain ordinary functions |
| prepared plans create too many specializations | TTFX/code-size regression | executor types vary by actual loop shape; IDs remain values; measure method instances |
| generic array support contaminates dense loop | throughput regression | separate adapter and interface tests |
| indexed RNG repeats streams | correlated stochastic results | versioned key derivation; explicit stream/invocation; collision tests and documentation |
| decision tables become too large | cache pressure | separate byte budget; compare compute; plan-local admission |
| optional Float128 changes answers | semantic divergence | endpoint agreement only; core MPFR fallback; differential on/off builds |
| static accumulator too narrow | plausible wrong reduction | width derived and checked before execution; independent BigInt differential |
| fusion removes a mandated projection | different defined program | fusion whitelist limited to storage transforms around one signature |
| raw byte view violates aliasing | input corruption | preflight alias classification; scratch or refusal before mutation |
| performance plan overfits one CPU | regressions elsewhere | x86-64/AArch64 matrices; ISA-specific adapters optional and removable |
| rigorous loop does not decide under ceiling | temptation to guess | explicit inconclusive error and unmodified destination |
| sampled approximation called a bound | false conformance claim | certificate type distinguishes estimate from exhaustive/proved bound |

---

## 23. Completion criteria

FloatBytes 1.0 is complete only when:

1. exactly 120 legal formats and 13,296 canonical codes are implemented;
2. every value is one byte and every safe construction maintains zero high bits;
3. all code/value, decode, order, class, next, and parse/display laws pass
   exhaustively;
4. Projection is independently verified across all policies and critical cells;
5. every defined operation reaches one `defined_code` seam;
6. deterministic unary and binary tables match that seam entry-for-entry;
7. dense, generic, direct, SIMD, threaded, packed, block, artifact, and
   stochastic adapters match the independent reference wherever applicable;
8. Base operators use a fixed documented policy and explicit `apply` supports
   every result format and policy;
9. stochastic logical-index results do not change with threads, tiling, SIMD, or
   packing;
10. common prepared scalar and array paths allocate zero;
11. common block reductions allocate zero and merge exactly;
12. table-build allocation and time targets show substantial improvement over
    the recorded SmallFloats evidence;
13. no approximate implementation is reachable from a defined plan;
14. every conformance or κ claim states exhaustive, proved, or sampled scope;
15. load time, first use, code size, method count, cache bytes, and artifact size
    meet recorded release ceilings;
16. all losing experimental adapters have been deleted;
17. documentation, manifests, source catalogues, and tests report the same
    semantic revision and supported surface.

---

## 24. Final architecture in one page

```text
FloatByte{K,P,S,D}
    one concrete byte, safe code identity, ordinary Julia scalar use

Signature
    immutable operation + formats + projection + stochastic contract

defined_code
    decode -> exact/enclosed semantics -> one projection -> UInt8

Prepared plan
    immutable cost choice, strong table/workspace ownership, no semantic choice

Execution adapters
    direct byte law | unary/binary LUT | stochastic decision | ternary compute/LUT
    dense | generic | threaded | packed | block | exact reduction

Assurance
    independent rational/MPFR authority -> exhaustive certificates -> conformance
```

The design is intentionally asymmetric:

- scalar values carry rich format identity in their type;
- bulk loops discard that richness once, operate on bytes, and regain typed
  results without per-element construction;
- expensive rigor is paid during semantic evaluation or table compilation;
- prepared execution pays only the irreducible byte movement, lookup, random
  comparison, or exact reduction work.

That asymmetry is the principal performance opportunity created by K <= 8. It
keeps FloatBytes a good Julia number without forcing Julia's type and dispatch
machinery into every byte of a large tensor.
