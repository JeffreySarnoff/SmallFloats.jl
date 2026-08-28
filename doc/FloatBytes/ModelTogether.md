# FloatBytes.jl — Internal Model

*A flexibly capable, correctness-first internal model derived from and improving
[`PlanTogether.md`](PlanTogether.md). Written 2026-08-04.*

This document is the implementation model for FloatBytes.jl. `PlanTogether.md`
explains what to build and in what order. This document defines the states,
transitions, invariants, and internal interfaces that keep the implementation
coherent while it grows.

The central design is:

```text
semantic intent       operational circumstances
      |                         |
      v                         v
   BoundCall -> SemanticKernel -> Prepared executor -> preflight -> commit
                        |
                        v
       exact evidence -> CodeRule -> resolve one entropy word -> UInt8
```

Semantic identity contains everything allowed to change a result byte.
Operational circumstances contain everything allowed to change only cost,
storage access, or scheduling. Mixing those two kinds of fact is the primary
source of semantic drift, cache-key errors, and Julia specialization growth; the
model makes the separation explicit.

---

## 1. Recommendation

Implement two deep internal modules:

1. **Semantic Model** binds a defined call, evaluates exact meaning, produces a
   projection rule, resolves entropy, and names the semantic revision.
2. **Execution Model** turns a compiled semantic kernel plus operational facts
   into an immutable prepared executor, validates a complete run, and commits
   bytes.

Assurance observes both through their interfaces. Byte Domain and Projection
remain deep modules inside Semantic Model; storage and machine-specific
execution remain adapters inside Execution Model.

The important internal operations are:

```julia
call     = bind_call(model, request)::BoundCall
kernel   = compile_semantics(model, call)::SemanticKernel
prepared = prepare(runtime, kernel, workload)::Prepared
execute!(destination, prepared, operands...; run_context)
```

For one logical value, the semantic composition is:

```julia
rule = semantic_rule(kernel, operand_codes...)::CodeRule
code = resolve(rule, entropy_word)::UInt8
```

`defined_code` remains a useful convenience and conformance seam:

```julia
defined_code(kernel, entropy_word, codes...) =
    resolve(semantic_rule(kernel, codes...), entropy_word)
```

It is not forced into every optimized loop. A deterministic byte table is a
materialization of `FixedCode` rules; a stochastic decision table is a
materialization of `ThresholdCode` rules. A certified direct law may bypass rule
construction only over the exact domain named by its certificate.

The external Julia interface stays small:

```julia
fromcode, quantize, apply, prepare, execute!
```

Most types in this document are private. Their purpose is to give implementation
and review one precise vocabulary, not to make callers assemble internal state.

---

## 2. Improvements over PlanTogether

This model retains PlanTogether's strongest decisions:

- one byte-wide primitive value;
- explicit code identity;
- one projection per logical result;
- a closed P3109 defined catalogue;
- cost-only prepared execution;
- indexed stochastic entropy;
- independent assurance;
- kernel-first optimization.

It makes the following corrections and refinements.

### 2.1 A sticky tail is policy-scoped evidence

`(window, exponent, tail::Bool)` can be sufficient evidence for several
deterministic rounding decisions. It does not generally preserve the exact
fractional distance needed for stochastic rounding. The existing W1 scripts
exercise nearest-ties-even; they do not establish every rounding family.

This is a concrete width mismatch, not merely a missing proof style. The current
projection vocabulary accepts `StochasticA/B/C{N}` for `1 <= N <= 60`, and
variant B evaluates an `N + 1` scaled predicate. A window whose retained tail
resolution is fixed at `G = 40` cannot, in general, determine all of those
cutoffs.

Accordingly:

- the 64-bit window is **sufficient rounding evidence for a proved policy
  family**, not an exact representation of every algebraic result;
- evidence carries a capability describing what it preserves;
- a stochastic call requires an exact cutoff or a rigorous enclosure that
  decides that cutoff for its declared entropy width;
- `Divide` and `Sqrt` retain quotient/remainder and root/remainder evidence,
  rather than reducing a remainder to one Boolean.
- Stage 4 proves stochastic sufficiency separately for every supported family
  and `N = 1:60`; it cannot inherit the deterministic 40-bit lemma.

### 2.2 Projection produces a rule before entropy is resolved

Separating `semantic_rule` from `resolve` reconciles four requirements:

- deterministic tables store one byte per input tuple;
- stochastic tables store reusable decision records rather than fake result
  bytes;
- exactly one logical entropy word is assigned per stochastic output, including
  exact and special results;
- different schedules resolve the same rule with the same indexed word.

### 2.3 Bulk execution has a preflight and a nonthrowing commit

PlanTogether requires an inconclusive projection to leave the destination
unchanged. A lazy rigorous evaluator inside a mutating element loop cannot keep
that promise. Prepared bulk execution therefore has two phases:

```text
preflight: validate or finish every fallible obligation
commit:    execute without semantic or resource failure
```

An unusual executor that cannot guarantee a nonthrowing commit must stage its
whole result in caller-approved workspace before copying it to the destination.

### 2.4 Exact reductions are the initial production authority

A restart window is not automatically an associative, mergeable reduction
state. Begin with a mechanically sized fixed-limb accumulator. Admit a windowed
restart executor only after proving its restart invariant, merge behavior, and
byte equivalence for every supported partition. The independent reduction
authority remains separately implemented `BigInt`/rational code.

### 2.5 Enumeration claims name every multiplied axis

`176,782,416` is the number of cross-format operand-code pairs. It is not the
number of binary semantic cases after multiplying by operations, result formats,
projection policies, and entropy decisions. Every exhaustive claim carries an
explicit `CoverageDomain` naming the axes it covers.

### 2.6 Table economics use comparable measurements

The 79.5 microsecond table build cited by PlanTogether used eight threads, while
its break-even comparison used serial execution. The starting estimate of about
three full-array passes is only a hypothesis. Preparation consumes explicit
workload hints and a same-machine, same-thread cost profile; it does not infer
"measured reuse" from a hidden mutable store.

### 2.7 Julia specialization is budgeted

Format, operation, projection, and layout do not all become type parameters by
default. A fact enters an executor type only when it changes generated machine
code enough to justify its compile and image cost. The model starts with
data-driven kernels behind one function barrier and promotes measured cases to
static kernels.

### 2.8 Context never changes ordinary operator meaning

Base operators use the immutable package default. If a scoped projection helper
is retained, it affects a separately named context-aware adapter such as
`apply_current`; it does not silently change `+`, `*`, or `exp`.

---

## 3. Model vocabulary

The names below are deliberately distinct.

| name | meaning | may affect result bytes? |
|:---|:---|:---:|
| `FloatByte` | one canonical encoded value with format identity in its type | yes |
| `FormatKey` | compact validated identity of a format | yes |
| `CallRequest` | untrusted requested meaning | potentially |
| `BoundCall` | validated and revision-bound semantic identity | yes |
| `SemanticKernel` | concrete evaluator plus rule-producing projector | yes |
| `CodeRule` | complete deterministic or entropy-dependent code decision | yes |
| `Workload` | layout, length, reuse, resources, and target machine | no |
| `Prepared` | immutable executable realization of a kernel | no |
| `RunContext` | runtime inputs and resources: entropy source, origin, workspace | entropy words may; resources may not |
| `Certificate` | evidence that an adapter preserves a named semantic domain | no |
| `SemanticTrace` | cold explanation of one result | no |
| `CoverageDomain` | exact scope of an assurance claim | no |

The governing law is:

> A `BoundCall`, operand codes, and logical entropy words completely determine
> result bytes. Layout, scheduling, workspace, machine target, and executor may
> change only cost. Changing the entropy input may of course change a stochastic
> result; changing how the same logical words are scheduled may not.

---

## 4. Immutable semantic root

The package has one immutable semantic root rather than a mutable registry:

```julia
struct SemanticRevision
    draft_id::UInt32
    model_version::UInt16
    catalogue_digest::NTuple{32,UInt8}
    semantics_digest::NTuple{32,UInt8}
end

struct SemanticModel{F,O,P}
    revision::SemanticRevision
    formats::F
    operations::O
    projections::P
end
```

The fields are illustrative. Callers do not inspect them. The model owns:

- the 120-format P3109 lattice;
- code layouts, biases, specials, order, and decode;
- operation arities and semantic families;
- special-value rows;
- projection and saturation families;
- entropy contracts;
- semantic revisioning.

The catalogue is closed for P3109-defined operations. It generates names,
arity checks, family dispatch, wrappers, test enumeration, and conformance
manifests. It stores metadata, not formulas or runtime expression trees.

### 4.1 Format names

Prefer unambiguous internal markers:

```julia
abstract type FormatSignedness end
struct SignedFormat   <: FormatSignedness end
struct UnsignedFormat <: FormatSignedness end

abstract type FormatDomain end
struct FiniteDomain   <: FormatDomain end
struct ExtendedDomain <: FormatDomain end

primitive type FloatByte{K,P,S<:FormatSignedness,D<:FormatDomain} <: AbstractFloat 8 end
```

`SignedFormat` and `UnsignedFormat` avoid visual confusion with Julia's
`Base.Signed` and `Base.Unsigned`. The longer names appear mostly in aliases and
diagnostics; they cost nothing in storage.

### 4.2 Compact keys

Cold model objects use compact values:

```julia
struct FormatKey
    bits::UInt8
    precision::UInt8
    flags::UInt8
end

struct OperationKey
    id::UInt16
    arity::UInt8
    family::UInt8
end

struct ProjectionKey
    rounding::UInt8
    saturation::UInt8
end
```

Every key is produced by validated lookup. Arbitrary bit patterns are not
executable model values.

---

## 5. Semantic identity

```julia
abstract type ExactnessClass end
struct DefinedCall <: ExactnessClass end
struct ApproximateCall{C} <: ExactnessClass end

struct EntropyContract
    kind::UInt8               # none or stochastic
    word_bits::UInt8
    slots::UInt8
end

struct BoundCall{N,E<:ExactnessClass}
    revision::SemanticRevision
    operation::OperationKey
    operands::NTuple{N,FormatKey}
    result::FormatKey
    projection::ProjectionKey
    entropy::EntropyContract
end
```

A `BoundCall` contains every fact permitted to change a code:

- semantic revision;
- operation and arity;
- operand formats in logical order;
- result format;
- rounding and saturation policy;
- stochastic decision family, word width, and slot count;
- defined versus explicitly approximate meaning.

It excludes:

- array axes and strides;
- packed versus byte storage;
- thread count and chunking;
- CPU features;
- cache state;
- expected reuse;
- workspace addresses;
- benchmark-derived costs.

Those are operational facts. The entropy *words* are explicit runtime inputs,
like operand codes; indexed versus sequential generation and its algorithm
version belong to the recorded entropy input, not to the mathematical function
from words to codes. Putting operational facts into a semantic digest would
create false semantic identities; omitting a semantic fact would allow stale
tables or certificates.

### 5.1 Binding

```julia
bind_call(model, request)::BoundCall
```

Binding validates arity, legal formats, result-format rules, projection support,
entropy requirements, exactness class, and revision. It returns an immutable
call or throws before compilation.

No arbitrary `BoundCall` constructor is part of the internal interface.

---

## 6. Canonical codes and trust

The package can guarantee canonical bytes only across interfaces it controls.
Julia permits unsafe `reinterpret` and concurrent mutation, so distinguish byte
storage from storage whose canonical-code invariant has been established.

Conceptually:

```julia
struct CheckedCode{F}
    value::UInt8
end

struct TrustedCodes{F,A}
    storage::A
end
```

These witnesses may erase at compilation. They mark where validation occurred.

Trusted inputs include:

- values produced by `fromcode`, numeric quantization, or Projection;
- typed `FloatByte` arrays not exposed to concurrent unsafe mutation;
- tables built and verified by the package;
- packed storage decoded by a checked adapter.

Foreign bytes require one validation pass at ingress. Validation checks high
bits and any storage invariants before a hot loop. Per-element revalidation is
not inserted into a trusted executor.

`reinterpret` into `FloatByte` and concurrent mutation through an aliased raw
byte view are outside the safe interface. Diagnostics should say so plainly.

---

## 7. Exact evidence algebra

Defined Semantics does not return a universal floating carrier. It returns the
smallest evidence that preserves every decision required by the bound call.

The conceptual closed set is:

```text
SpecialEvidence       exact special kind, sign, and payload
ExactDyad{L}           signed fixed-limb integer times a power of two
WindowEvidence{R}      retained window plus typed residual evidence
ExactRatio{L}          exact numerator, denominator, exponent, and sign
RootEvidence{L}        integer root, exact remainder, scale, and sign
RigorousEnclosure{T}   directed endpoints, openness, precision, provenance
CertifiedFinalCode{C}  final code plus domain-scoped equivalence certificate
```

This is a model algebra, not a runtime abstract field. Each concrete semantic
kernel returns a statically known evidence type so projection inlines without a
tag switch.

### 7.1 Evidence capabilities

Every evaluator declares what its evidence proves:

```text
ExactValue                 full mathematical value
ExactCutoff{N}             enough to decide an N-bit stochastic threshold
DeterministicRounding      enough for named deterministic policies
DirectedSidedness          exact relation to the retained anchor
EnclosedValue              rigorous interval, refinable until a rule agrees
FinalCode                  code already selected over a certified domain
```

Compilation computes the call's required capability. It may select an evaluator
only when the evaluator's capability entails that requirement.

Examples:

- nearest-even `Add` may use a proved window with guard/round/sticky evidence;
- stochastic-16 `Add` needs the exact 16-bit cutoff and therefore retains more
  residual information or uses `ExactDyad`;
- `Divide` uses quotient and exact remainder;
- `Sqrt` uses integer root and exact remainder;
- an elementary function refines an enclosure until both endpoints produce the
  same `CodeRule`.

There is no fallback from insufficient evidence to a guess. Preparation chooses
a stronger evaluator or reports an unsupported/resource error.

### 7.2 The window theorem, correctly scoped

The W1 scripts establish evidence for nearest-ties-even over their enumerated
domains. The production theorem should be split:

```text
W1-D(policy family, format domain, operation family)
    WindowEvidence is sufficient for the named deterministic projections.

W1-S(entropy width, format domain, operation family)
    The richer residual representation decides the exact stochastic cutoff.
```

Each certificate names its domain. Passing W1-D does not imply W1-S.
W1-S must cover all declared stochastic families and every supported
`N = 1:60`; variant B's `N + 1` predicate is included explicitly.

### 7.3 Fixed-limb fallback

For `K <= 8`, fixed-arity finite algebra has a bounded exponent span. Derive a
small `ExactDyad{L}` from the bound call when a one-word evaluator cannot provide
the required evidence. This is a correctness-preserving fallback, not a carrier
ladder selected by runtime data.

The selection is made once during semantic compilation. The element loop never
asks whether it should widen.

---

## 8. From evidence to CodeRule

Projection has one conceptual interface:

```julia
project_rule(result_format, projection, entropy_contract, evidence)::CodeRule
```

`CodeRule` is a closed set:

```julia
struct FixedCode
    code::UInt8
end

struct ThresholdCode{N}
    lower::UInt8
    upper::UInt8
    cutoff::UInt64
    sense::UInt8
end
```

For deterministic projection, `project_rule` returns `FixedCode`. For a
stochastic family it returns an exact finite-word decision such as
`ThresholdCode{N}`. The rule includes saturation and special handling; resolving
it requires no mathematical recomputation.

```julia
resolve(rule::FixedCode, word)::UInt8 = rule.code
resolve(rule::ThresholdCode{N}, word)::UInt8 = # exact declared comparison
```

The executor obtains exactly one word for every stochastic logical output before
resolution. A `FixedCode` ignores the word, but its logical slot still exists.
This keeps indexing, slicing, replay, and composition independent of data.

### 8.1 Why this seam is deep

Deleting `CodeRule` would spread stochastic cutoff arithmetic into scalar
execution, decision tables, threads, SIMD, packed tiles, conformance, and traces.
With it, those callers learn one small rule-resolution interface while Projection
owns neighbour selection, saturation, ties, residual comparisons, and entropy
mapping.

### 8.2 Elementary enclosures

For an enclosure, Projection derives a rule from each directed endpoint under
the same call. If the rules are identical, that rule is rigorous. Otherwise the
elementary evaluator raises precision and retries.

For stochastic projection, equality means equality of the full threshold rule,
not merely equality of lower and upper result codes.

---

## 9. Semantic kernels

```julia
struct SemanticKernel{Evaluator,Projector,SpecialRows}
    evaluator::Evaluator
    projector::Projector
    special_rows::SpecialRows
    call_digest::SemanticDigest
end
```

The actual representation should use concrete fields and only the type axes
that improve generated code. Its interface is:

```julia
semantic_rule(kernel, codes...)::CodeRule
defined_code(kernel, entropy_word, codes...)::UInt8
explain(kernel, entropy_word, codes...)::SemanticTrace
```

`explain` is cold and diagnostic. It records classification, decoded datums,
evidence, neighbouring codes, the rule, entropy word, and final code. It may be
instrumented and allocate. It is never the independent authority and never
appears in an executor loop.

### 9.1 Special rows

Special-value behavior is selected from code points before finite unpacking.
The common finite predicate should be tiny and predictable. Complex special-row
handling may be a cold `@noinline` branch.

Zero remains on the finite path where the standard permits it. Do not pay an
exceptional-path call for the most common datum merely because zero has a name.

### 9.2 Dynamic and static kernels

Start with:

```text
DynamicKernel
    format constants stored in compact isbits fields;
    compiled by operation family, projector family, and loop shape.

StaticKernel{...}
    selected constants promoted to type parameters;
    admitted only for measured scalar or dense wins.
```

A cold function barrier converts value IDs into one concrete kernel. Runtime
integer masks and shifts are not semantic branches. This starting point avoids a
default Cartesian product of 120 formats × operations × policies × layouts.

Record kernel speed, first-call latency, method instances, native-code bytes,
invalidations, and package image size before promoting a static variant.

---

## 10. Operational model

Operational facts are gathered in a preparation request:

```julia
struct Workload
    layout::LayoutModel
    count::Int
    reuse::ReuseHint
    latency_or_throughput::Preference
    resources::ResourceBudget
    target::MachineTarget
end

struct PrepareRequest{K,W}
    kernel::K
    workload::W
end
```

The operational model may choose:

- direct compute versus compiled table;
- dense versus generic storage access;
- sequential versus threaded traversal;
- byte versus packed tiles;
- dynamic versus admitted static kernel;
- fixed-limb workspace placement;
- SIMD width and tail strategy.

It may not reinterpret the call, change projection evidence, alter entropy word
identity, or substitute approximation.

### 10.1 Adapter offers

Execution extension uses one internal seam:

```julia
offer(adapter, kernel, workload)::Union{Decline,ExecutorOffer}
materialize(offer)::Prepared
```

An offer contains:

- exact applicability domain;
- concrete executor builder;
- semantic digest;
- equivalence certificate or construction proof;
- estimated preparation and execution cost;
- required workspace and alignment;
- alias and ordering contract;
- supported entropy sources;
- compile/image cost class.

Avoid a mutable registry. Core and loaded Julia extensions contribute an
immutable tuple of candidate adapters. Preparation evaluates offers, rejects
uncertified or inapplicable ones, and chooses by cost only.

One implementation remains private experimentation. Two demonstrated adapters
justify keeping the seam.

### 10.2 Prepared executor

```julia
struct Prepared{Kernel,Executor,EntropyPlan,WorkspacePlan}
    semantic_digest::SemanticDigest
    kernel::Kernel
    executor::Executor
    entropy::EntropyPlan
    workspace::WorkspacePlan
    traits::PlanTraits
end
```

`Prepared` is opaque and immutable. Its concrete executor owns tables and other
immutable resources strongly.

`PlanTraits` reports:

- executor family and semantic digest;
- supported layouts and exact alias rules;
- workspace bytes, alignment, and initialization;
- entropy source and logical-origin requirements;
- parallelism and ordering;
- preparation cost and estimated break-even;
- allocation behavior;
- whether staging is required;
- certificate and artifact identities.

Traits are observability, not knobs that change an existing plan.

### 10.3 Initial executor set

Begin with three:

```text
DenseCompute       concrete semantic kernel over trusted byte views
UnaryLookup        deterministic 256-byte rule materialization
GenericArray       correctness path for unusual axes, strides, and views
```

Add `BinaryLookup`, `StochasticDecision`, `PackedTile`, `ExactReduction`, direct
byte laws, SIMD, and threaded variants one at a time. Each must show a real
second adapter, exhaustive equivalence over its declared domain, and a measured
end-to-end win.

Executor names never enter semantic identity.

---

## 11. Preparation, preflight, and commit

Preparation is a state transition, not a partially configured object:

```text
CallRequest
  -> bind_call
BoundCall
  -> compile_semantics
SemanticKernel
  -> gather offers / choose by cost / materialize resources
Prepared
```

There is no executable intermediate state.

Execution is transactional at the interface:

```text
Prepared + arrays + RunContext
  -> preflight
ValidatedRun
  -> commit!
Completed
```

Preflight validates before the first destination write:

- element formats and code trust;
- shapes, axes, strides, and logical order;
- alias safety;
- workspace size, alignment, and ownership;
- entropy source compatibility;
- logical origin and index range;
- thread/ordering restrictions;
- semantic revision and artifact integrity when applicable.

Commit contains no catalogue lookup, strategy choice, cache lock, dictionary,
symbol dispatch, fallible table construction, rigorous precision escalation, or
error formatting. Its loop sees a concrete executor and raw trusted byte views.

If a commit can encounter a resource limit, it is not ready to commit. Finish
the work in preparation, stage output, or decline the offer.

---

## 12. Entropy model

Two entropy adapters are real:

```julia
IndexedEntropy(seed, stream, invocation, algorithm_version)
SequentialEntropy(rng)
```

Indexed entropy maps:

```text
(algorithm version, seed, stream, invocation,
 logical output index, projection slot) -> N-bit word
```

Logical index is independent of thread, tile, SIMD lane, packed word, and
physical array offset. A subarray execution supplies its logical origin.

Sequential entropy consumes a conventional stream in logical order and admits
only sequential executors. This is rejected during offer selection or preflight,
not branched upon per element.

The bound call, not the executor, owns word width and slot count. Changing the
counter algorithm requires a new entropy algorithm version in the run record,
but does not change the semantic function from an explicit word to a code.

---

## 13. Table model

Tables are compiled rules.

```text
deterministic table     input tuple -> UInt8 FixedCode
stochastic table        input tuple -> compact ThresholdCode{N}
```

The statement "unary tables are at most 256 bytes" applies only to
deterministic result tables. A stochastic unary rule table is larger and
specific to its entropy width and stochastic family.

Every table identity contains:

- complete semantic digest;
- operand and result formats;
- operation and projection;
- entropy contract;
- table encoding version;
- dimensions and index order;
- content checksum.

A checksum detects corruption. The semantic digest detects staleness. Both are
required.

Construction is private until every entry is decided and validated. Publication
is atomic, and a prepared executor owns the immutable table strongly.

### 13.1 Admission

- deterministic unary tables are the initial default;
- stochastic rule tables require measured value over direct rule construction;
- binary tables consume an explicit reuse hint or caller-forced policy;
- ternary tables start declined;
- artifact packs remain deferred until measured cold cost justifies them.

Cost profiles compare preparation and execution under the same thread count,
machine, cache state, and harness. `PlanTraits` exposes the estimate and the
assumptions behind it.

No table store defines semantics. If a shared bounded store is added, it is only
an operational accelerator; plans remain valid after eviction because they own
their tables.

---

## 14. Storage model

Storage adapters map physical representation to canonical logical code order.

Initial adapters:

- dense one-byte typed arrays;
- generic Julia arrays;
- checked foreign byte spans;
- packed vectors;
- block structure-of-arrays.

Every adapter declares:

- element format and code-trust source;
- logical axes and origin;
- read/write and alias rules;
- alignment and stride;
- workspace requirements;
- canonical tail/padding behavior;
- whether traversal preserves entropy index identity.

Dense typed arrays lower to byte views once. Packed execution uses reusable
tiles and fuses unpack, one defined operation, and repack. `K = 8` is an identity
byte view. Storage fusion may not remove a required intermediate projection.

---

## 15. Reductions and blocks

The initial defined reduction state is exact and mergeable:

```text
derive limb width from call + reduction length
    -> accumulate exact fixed-limb state
    -> merge exact states associatively
    -> normalize once
    -> produce evidence
    -> project once
```

Preparation derives width from minimum and maximum product exponent,
significand bits, factor count, and carry bits. It chooses an isbits fixed-limb
state, caller-owned wider workspace, or a cold fallback before execution.

Thread partitioning and merge order cannot change bytes.

A restart-window reduction is an optional later adapter. Its certificate must
cover termination, signed residuals, repeated cancellation, partitioning, merge
trees, policies, and entropy widths. It is not its own independent authority.

Blocks use structure-of-arrays byte storage by default. Small static tuples may
be admitted below a measured compilation and allocation threshold.

---

## 16. Approximation and non-P3109 extensions

Defined and approximate calls are disjoint types. A defined preparation request
cannot solicit or accept an approximate offer.

An approximate call names:

- its own semantic revision;
- candidate implementation digest;
- related defined call;
- metric and certificate;
- exhaustive, proved, or sampled scope;
- special-value mismatch policy.

Non-P3109 formats use separate public names and a separate format model. They may
reuse exact evaluators and execution adapters but do not enter the P3109 lattice,
aliases, or conformance claims.

New execution, storage, entropy, and evaluator adapters may improve cost. They
cannot define a new result for an existing P3109 call. New user-defined
operations live in a namespaced model revision rather than mutating the standard
catalogue.

---

## 17. Assurance model

Assurance records claims, not Boolean confidence flags.

```julia
struct CoverageDomain
    formats
    operand_codes
    operations
    result_formats
    projections
    entropy_words
    layouts
    partitions
end

struct EquivalenceCertificate
    semantic_digest
    candidate_digest
    coverage::CoverageDomain
    authority_digest
    method                 # exhaustive, proved, sampled
end
```

A sampled claim cannot satisfy a proved or exhaustive requirement. A certificate
for nearest-even same-format `Add` cannot authorize stochastic cross-format Add.

### 17.1 Independent authorities

1. `reference/` implements rational/BigInt and directed MPFR reasoning without
   importing production semantics.
2. Version-pinned SmallFloats provides a second differential adapter during
   construction.

Production `SemanticTrace` diagnoses mismatches but is not an authority. It
shares the model being checked.

### 17.2 Equivalence chain

For the exact domain named by each claim:

```text
independent authority
  == semantic_rule + resolve
  == defined_code
  == deterministic or decision table
  == direct certified law
  == dense / generic / threaded / SIMD / packed / reduction executor
```

Equality means code identity in logical order. For stochastic work it also means
the same rule and the same logical entropy word.

### 17.3 Revised gates

- **W1-D**: deterministic window sufficiency over a named domain.
- **W1-S**: stochastic cutoff sufficiency for a named entropy width and domain.
- **W2**: reduction width, exact merge, and any optional restart proof.
- **W3**: zero allocation on each declared prepared commit path.
- **G9**: facts intended to fold do fold.
- **G10**: every catalogue operation on every declared surface returns with its
  declared type.
- **TX**: every execution failure occurs before destination mutation, or through
  an explicitly staged executor.
- **REV**: plans, tables, artifacts, certificates, errors, and conformance all
  carry the same semantic revision.

Release reports spell out the cross-product covered. "Full binary" and "full
ternary" are not accepted without enumerated axes and case count.

---

## 18. Error model

Errors are phase-specific and carry the semantic digest where one exists.

Binding and semantic compilation:

```text
InvalidFormatError
UnsupportedCallError
PolicyNotDefinedError
EntropyContractError
EvidenceCapabilityError
SemanticRevisionMismatch
```

Preparation and materialization:

```text
ResourceLimitError
InconclusiveProjectionError
ArtifactMismatchError
UncertifiedAdapterError
ProgramSizeError
```

Execution preflight:

```text
InvalidCodeError
ShapeError
AliasingError
WorkspaceError
EntropyRequiredError
EntropyOriginError
UnsupportedExecutionError
```

Internal defects:

```text
InternalInvariantError
CatalogueMismatchError
CertifiedLawMismatchError
```

Error rendering uses only robust primitive fields. `show` for model values and
errors must not invoke semantic evaluation, table access, or fragile user code.

Bulk commit does not throw these ordinary errors. If an unexpected internal
defect occurs, partial mutation is possible and is reported as such; the model
does not disguise memory or compiler failure as transactional success.

---

## 19. Performance model

The model recognizes five common paths:

| class | default realization |
|:---|:---|
| deterministic finite algebraic | dense integer kernel plus deterministic projector |
| unary elementary | fully prepared 256-byte deterministic table |
| stochastic | exact rule kernel plus indexed entropy; decision table only if measured |
| special or rigorous construction | cold path completed before publication/commit |
| unusual arrays | generic traversal using the same semantic kernel |

The hot loop contains:

```text
trusted UInt8 load(s)
  -> predictable special predicate
  -> concrete finite kernel or special row
  -> concrete rule resolution
  -> trusted UInt8 store
```

It does not contain format validation, operation IDs, policy selection, mutable
default lookup, adapter search, cache admission, certificate lookup, table build,
precision escalation, or error construction.

### 19.1 What is measured

Measure separately:

- bind and semantic compile;
- preparation and materialization;
- first call and warm scalar;
- warm bulk commit;
- table build/load and amortization;
- workspace allocation versus reuse;
- method instances and invalidations;
- native-code and package-image bytes;
- CPU cache and memory traffic;
- parallel efficiency and entropy cost.

A nanosecond improvement that causes an unacceptable first-call or image-size
regression is not automatically a win.

### 19.2 Type-versus-value rule

Use a type parameter only when it removes a measured branch, enables a measured
instruction sequence, or fixes an isbits layout such as accumulator limb count.
Keep revision IDs, catalogue IDs, sizes, digests, and most format metadata as
values behind the preparation function barrier.

Executor families, not every semantic call, are the main unit of specialization.

---

## 20. Worked traces

### 20.1 Dense deterministic Add

```text
CallRequest(Add, T8p4se, T8p4se -> T8p4se, nearest-even)
  -> BoundCall with semantic digest D
  -> compile DynamicKernel(AddFamily, DeterministicProjector)
  -> DenseCompute offer wins
  -> Prepared(D, DenseCompute, no entropy, no workspace)
  -> preflight shapes, formats, aliasing, trusted byte views
  -> commit each lane:
       classify -> window/exact evidence -> FixedCode -> store
```

Assurance compares every applicable code pair with the rational authority. If a
mismatch occurs, `explain` prints the evidence and rule without becoming the
authority.

### 20.2 Threaded stochastic FMA

```text
CallRequest(FMA, T8p4se^3 -> T8p4se, stochastic-16)
  -> BoundCall(D, entropy slots=1, width=16)
  -> compile exact-product evaluator + probability-preserving residual projector
  -> threaded DenseCompute offer wins for the declared length
  -> Prepared freezes indexed-entropy adapter and origin requirements
  -> logical index 37:
       exact evidence -> ThresholdCode{16}(lo, hi, cutoff)
       indexed_word(..., origin + 37, slot=0)
       resolve -> store
```

Changing thread count, chunks, SIMD width, or packed tiling cannot change index
37. An exact or special result still owns and discards index 37's word.

### 20.3 Unary Exp

```text
BoundCall(Exp, deterministic)
  -> elementary kernel
  -> UnaryLookup offer
  -> enumerate at most 256 inputs privately
  -> refine each enclosure until both endpoints yield the same FixedCode
  -> validate, checksum, publish immutable table
  -> Prepared owns table
  -> commit is one byte lookup per lane
```

If any entry remains inconclusive under the resource budget, no plan is
published and no destination has been touched.

For stochastic Exp, the table entry is a `ThresholdCode`, endpoint agreement
includes its cutoff, and admission is separately measured.

### 20.4 Exact dot product

```text
BoundCall(Dot, length B, project once)
  -> derive product exponent span and accumulator width L
  -> ExactReduction{L} offer
  -> preflight workspace and partition plan
  -> each thread accumulates exact limbs
  -> merge exact states
  -> one evidence value -> one CodeRule -> one result code
```

Partitioning changes cost only.

---

## 21. Model invariants

These are review criteria and executable assertions where practical.

1. A `BoundCall` contains every fact allowed to change result bytes.
2. Operational facts never enter semantic meaning; entropy words remain explicit
   runtime inputs rather than operational choices.
3. Each logical defined result is projected exactly once.
4. `CodeRule` is the only ordinary output of Projection.
5. Every evaluator provides evidence sufficient for its bound projection and
   entropy contract.
6. Sticky-only evidence is never admitted for a stochastic cutoff unless a
   named theorem proves sufficiency for that exact family and width.
7. One stochastic logical output owns exactly the declared number of words,
   independent of value and schedule.
8. Safe constructors and trusted buffers contain canonical codes; arbitrary raw
   reinterpretation is untrusted.
9. A prepared executor is immutable, semantically closed, and owns its resources.
10. Executor selection changes cost only.
11. Every ordinary failure happens before commit; otherwise execution stages.
12. Tables are immutable compiled rules and never define semantics.
13. A direct law is usable only inside its certificate's exact domain.
14. Exact reduction states merge associatively and project once.
15. Defined and approximate calls cannot share a preparation route.
16. Every artifact, table, plan, certificate, error, and conformance record names
    its semantic revision.
17. A sampled claim cannot satisfy an exhaustive or proved requirement.
18. Hot loops read no mutable global state.
19. Facts enter Julia types only for measured code-generation or layout benefit.
20. `show` and diagnostics do not depend on the computation that failed.

---

## 22. Suggested implementation ownership

```text
src/
  FloatBytes.jl

  semantic_model/
    revision.jl          SemanticRevision and digests
    catalogue.jl         closed format/operation/projection sources
    calls.jl             CallRequest, BoundCall, binding
    domain.jl            FloatByte, formats, decode, order, trust
    evidence.jl          exact evidence and capabilities
    evaluation.jl        semantic families and special rows
    projection.jl        CodeRule construction and resolution
    kernels.jl           semantic compilation and defined_code
    trace.jl             cold SemanticTrace

  execution_model/
    workload.jl          operational facts and resource budgets
    offers.jl            adapter offer interface and cost choice
    prepared.jl          Prepared, PlanTraits, ownership
    preflight.jl         validation and ValidatedRun
    dense.jl             DenseCompute
    unary_tables.jl      deterministic rule materialization
    generic.jl           unusual Julia arrays
    entropy.jl           indexed and sequential adapters
    reductions.jl        fixed-limb exact accumulators
    packed.jl            checked storage and tiling

  assurance/
    claims.jl            CoverageDomain and certificates
    equivalence.jl       adapter comparisons
    conformance.jl       live reports

reference/
  independent format, rational projection, BigInt reduction, MPFR interval code
```

This is ownership, not a requirement for many shallow files. Merge files when
their knowledge moves together. Preserve the two deep model interfaces and the
independent authority even if physical layout changes.

---

## 23. Implementation sequence for the model

1. Define `SemanticRevision`, compact keys, `CallRequest`, `BoundCall`, and
   binding errors.
2. Define canonical-code trust and the byte-domain atlas.
3. Define evidence capabilities, `CodeRule`, and deterministic `resolve`.
4. Implement independent projection tests before operation kernels.
5. Compile one deterministic algebraic family into a dynamic kernel.
6. Add `Prepared`, preflight/commit, `DenseCompute`, and `GenericArray`.
7. Add deterministic unary rule compilation and `UnaryLookup`.
8. Add exact residuals, `ThresholdCode`, and indexed/sequential entropy.
9. Prove W1-D and W1-S separately; admit one-word windows only within their
   certificates.
10. Add quotient/root evidence and the rest of the algebraic catalogue.
11. Add rigorous elementary rule compilation and transactional publication.
12. Add fixed-limb exact reductions.
13. Add adapter offers one at a time: threads, packed, binary tables, SIMD, and
    any proven restart reduction.
14. Add approximation only after defined preparation is structurally closed.
15. Review type/value placement and delete static variants that do not repay
    their compile cost.

Each step leaves one executable state transition and green interface-level
tests. Avoid temporary public constructors for half-built internal objects.

---

## 24. Open experiments, not open semantics

The following remain measurements:

1. Dynamic versus static kernels for common scalar and dense calls.
2. Atlas versus per-format decode tables.
3. Binary table break-even at equal build/use thread counts and cache states.
4. Whether stochastic decision tables repay their larger footprint.
5. Thread thresholds for compute, lookup, packed, and exact reduction.
6. Whether packed storage wins on real memory-bound workloads.
7. Whether a restart reduction can beat fixed limbs after full certification.

None changes what a `BoundCall` means, how entropy words are identified, or what
code is correct. They can therefore be settled late without redesigning the
semantic model.

The following are not experiments:

- exact projection once;
- evidence sufficient for the selected policy;
- semantic/operational separation;
- schedule-independent indexed entropy;
- preflight before commit;
- exact merge before reduction projection;
- explicit approximation;
- independent authority.

---

## 25. The model in one page

```text
SemanticModel(revision)
  |
  +-- bind_call(CallRequest)
  |       operation + formats + projection + entropy + exactness
  |       -> BoundCall and semantic digest
  |
  +-- compile_semantics(BoundCall)
          special rows + concrete evaluator + concrete projector
          -> SemanticKernel
                |
                +-- semantic_rule(codes...)
                |       exact evidence -> CodeRule
                |
                +-- defined_code(word, codes...)
                        CodeRule -> resolve -> canonical UInt8

ExecutionModel
  |
  +-- prepare(kernel, workload)
  |       immutable adapter offers -> cost-only choice -> Prepared
  |
  +-- preflight(Prepared, arrays, RunContext)
  |       trust + shape + alias + workspace + entropy + revision
  |       -> ValidatedRun
  |
  +-- commit!(ValidatedRun)
          concrete byte loop, no semantic choice, no ordinary failure

Assurance
  independent authority + CoverageDomain + equivalence certificates + traces
```

This model is flexible because semantic family, evidence, projection policy,
entropy, storage, execution, and assurance scope are separate axes with explicit
composition rules. It remains deep because ordinary callers do not assemble
those axes: they state a call, optionally prepare it, and execute it.

The central performance move is not a particular table or integer trick. It is
that preparation resolves every flexible choice once, then hands the hot loop a
concrete kernel over trusted bytes. The central correctness move is not merely
"use exact arithmetic." It is that every evaluator must produce evidence strong
enough for the exact projection contract it is asked to satisfy.
