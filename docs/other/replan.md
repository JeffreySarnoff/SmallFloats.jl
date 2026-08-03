# Replanning the SmallFloats.jl Documentation

Status: proposed documentation architecture and realization plan. This is a
plan for a deliberate rewrite, not a request to rename the present navigation
in place.

## Executive decision

The next manual should be organized around a reader's progress from **meaning**
to **control** to **scale** to **proof**:

1. understand what a format contains;
2. construct and inspect values without confusing values and code points;
3. understand exact computation followed by one projection;
4. choose the format and projection that express an application policy;
5. apply that policy to arrays, blocks, storage, and stochastic work;
6. inspect the API contract or implementation only when the task requires it;
7. verify claims with executable examples, conformance data, and benchmarks.

The current manual contains nearly all of the material needed to do this. Its
main problem is not missing information. It is that the same information is
introduced through several overlapping taxonomies and at several levels of
detail, so the reader must assemble the curriculum. The rewrite should make
that curriculum visible.

The recommended top-level navigation is:

1. **Start**
2. **Workflows**
3. **Concepts and Standard**
4. **Reference**
5. **Examples and Evidence**
6. **Internals and Contributing**
7. **Help**

Diátaxis remains useful as an editorial discipline—tutorial, task guide,
explanation, or reference—but it should no longer be the reader's primary map.
Readers do not arrive thinking “I need an explanation page.” They arrive
thinking “I need to quantize this tensor,” “why did this overflow to infinity?”
or “where is the exact signature of `Convert`?” The navigation should use
those intentions; page templates can enforce the Diátaxis distinctions behind
the scenes.

## What was reviewed

The review used `docs/src` as the source of truth and considered the navigation
in `docs/make.jl`, all Markdown page headings, representative pages from every
current section, the example and consistency tests, and the HTML/PDF build
arrangement.

At the time of review the manual has:

- 52 Markdown pages and about 51,000 words;
- 71 `julia-repl` blocks and 111 additional Julia code blocks;
- 51 admonitions and 35 pages with a See-also section;
- ten visible destinations at the first navigation level when Home is counted;
- five partly overlapping introductions: Home, Quickstart, Mental Model,
  Introducing P3109, and the first tutorial;
- a strong custom test that executes REPL examples, plus a targeted consistency
  test for format counts, the supported `K` range, exports, and type relations.

Those numbers are not goals to minimize. They explain the shape of the
problem: this is already a substantial manual and needs information
architecture, not another layer of prose.

## What should be preserved

The rewrite should retain the present manual's strongest characteristics.

### Exact claims are usually accompanied by evidence

The documentation prints concrete values and code points, shows projection
outcomes, distinguishes exhaustive from sampled verification, and explains
why an answer is trustworthy. That is unusually good numerical-software
documentation. The rewrite should make this evidence easier to find rather
than dilute it.

### The examples expose the package's real semantics

Examples show the `Unsigned`-means-code-point rule, explicit projection specs,
block staging, stochastic `R` sweeps, table warm-up, and κ measurement. These
are the exact places where a polished but shallow manual would fail.

### Surprises are named directly

Warnings about `Binary16p11se` versus `Float16`, abstract format types in
arrays, process-global defaults, cross-format promotion, and pre-block staging
are valuable. They should become a consistent “surprise / consequence / safe
choice” pattern.

### The internal design is documented as invariants

The engine, oracle, block, table, and verification pages explain why an
optimization is allowed, not only what source file contains it. This makes the
manual useful to maintainers and standards implementers.

### Documentation has executable gates

`test/docs_examples.jl` and `test/docs_consistency.jl` are the beginning of a
documentation product, not an afterthought. The new architecture should expand
those gates and use them to prevent the taxonomy and terminology from drifting
again.

## Problems the new plan must solve

### Too many maps compete for the same material

Getting Started, Tutorials, How-To, Explanations, Reference, Foundations,
Examples, Insights, and Support are all defensible categories. Together they
make the reader decide how the authors classified an answer before the reader
can find it. Several pages then explain the categories again.

The remedy is not merely fewer labels. It is a primary journey that describes
what readers are trying to accomplish, with a secondary page-type label when
useful.

### The first hour repeats rather than advances

Home, Quickstart, Mental Model, Introducing P3109, Values and Code Points, and
Projection each reintroduce formats, datums, code points, and projection. Some
repetition is pedagogically useful; this amount makes the reader wonder which
page is authoritative and delays arrays or an application workflow.

Each concept should have one canonical definition, one first demonstration,
and intentional later retrieval practice. Repetition should add a decision or
new context, not restate a definition.

### Page purposes are mixed

Quickstart teaches display customization and block quantization after the
reader's first addition. Quantize a Tensor also teaches packing and an
independent exhaustive verifier. Operations and Arrays moves from public array
calls into cache construction and internal table machinery. These are all good
subjects, but each page makes several promises at once.

The new rule is: one page, one reader promise. A page may contain prerequisites
and failure modes, but it should not quietly become another kind of page.

### Detail arrives before the reader has a decision to make

The current writing often explains an implementation mechanism immediately
after a first API example. This is intellectually satisfying to an implementer
and expensive for a practitioner. For example, a reader can use `Exp` on an
array before learning cache byte counts, ternary tiers, or how tables inherit
scalar exactness.

Use progressive disclosure: outcome first, contract second, mechanism third,
proof fourth. Link down the stack instead of presenting the whole stack on
first contact.

### Cross-page vocabulary has drifted

Current pages contain residual names such as User Guide, Technical Guide,
Technical Examples, How-Tos, How-To, Specifics, and Reference. Some references
are plain prose rather than links. This is a symptom of manually maintained
navigation language.

There are also claims that contradict another sentence on the same page. The
sorting tutorial currently says NaN sorts last, shows output with NaN last,
then says the single NaN is smallest and therefore sorts first. The performance
explanation repeats the NaN-last claim while the mental model, formal
foundation, cheat sheet, glossary, and other pages say NaN first. A successful
build does not detect this class of contradiction.

The rewrite needs canonical terminology and canonical semantic facts, plus
tests for the highest-risk statements.

### Navigation endings do not express a learning decision

Most pages finish with a flat See-also list. The links are often relevant, but
they do not distinguish “continue the sequence,” “perform the task,” “understand
why,” and “look up the contract.” A reader has to infer the relation.

Replace undifferentiated link lists with a small, typed exit:

- **Next:** the next step in this route;
- **Use it:** the task guide that applies the idea;
- **Understand it:** the deeper conceptual or standard page;
- **Look it up:** the precise reference page.

Not every page needs all four.

### HTML and PDF are not interchangeable reading environments

The manual is built as both a site and a long PDF. HTML-only disclosure
widgets, extremely wide tables, raw anchor assumptions, and links that make
sense only in a sidebar weaken the PDF. Conversely, repeating navigation prose
on every page makes the website heavy.

Every proposed pattern must have an explicit PDF behavior. Critical content
must never exist only in a collapsed HTML element.

## Readers and the jobs they bring

The new manual should acknowledge four audiences without creating four copies
of the documentation.

| Reader | Immediate job | What earns trust | Route after the common start |
|---|---|---|---|
| ML or numerical practitioner | choose a format, quantize data, measure damage | runnable workflows, failure modes, metrics | Workflows → Examples |
| Julia library user | understand constructors, promotion, arrays, defaults | exact API contracts and Julia conventions | Concepts → Reference |
| standards or conformance reader | understand P3109 semantics and deviations from IEEE 754 | normative vocabulary, draft links, exhaustive claims | Concepts and Standard → Evidence |
| maintainer or contributor | change an operation without breaking exactness | invariants, source seams, proof obligations, gates | Internals and Contributing |

All four should share the same first 15 minutes. Forking before the common
model would reproduce the current duplication.

## The comprehension model

The curriculum should grow understanding through six thresholds. A reader
should not need the next threshold to use the previous one.

### Threshold 1: identity

**Question:** What is stored?

A format is a finite set of exact datums. A value stores one code point that
names one datum. `decode` reveals the datum; `codepoint` reveals the identity.
An `Unsigned` constructor argument is a code point, not a numeric value.

**Evidence:** one small format shown in full; one value/code-point round trip.

**Reader can now:** construct, inspect, enumerate, and avoid the most common
constructor error.

### Threshold 2: projection

**Question:** How does a requested real value become a stored value?

Every write computes or receives a mathematical value and applies one
projection. Projection is rounding policy plus saturation policy. Construction,
conversion, and operations share this path.

**Evidence:** one between-grid value and one overflow under two specs.

**Reader can now:** predict ordinary results and select explicit policy.

### Threshold 3: format choice

**Question:** Which datum set should the application use?

Teach `K`, `P`, signedness, and domain as a budget with observable consequences,
not as a naming grammar alone. The decision is driven by sign needs, meaningful
infinities, range, resolution, and measured error on representative data.

**Evidence:** a candidate comparison table with RMSE, maximum error, and
overflow/clamp fraction.

**Reader can now:** justify a format rather than copy `Binary8p4se` from an
example.

### Threshold 4: execution at scale

**Question:** How does the same semantic contract apply to arrays and blocks?

Public array calls preserve scalar semantics. Blocks add a shared scale; they
do not change the one-final-projection rule. Packed storage changes storage,
not computation.

**Evidence:** one array operation, one block reconstruction, one staging
failure, and one storage calculation.

**Reader can now:** build an application pipeline without learning the oracle
or cache implementation.

### Threshold 5: controlled nondeterminism and approximation

**Question:** Which deviations are intentional, and how are they controlled?

Stochastic rounding is exact with respect to a random draw and reproducible
with an explicit source. Approximate kernels are opt-in and have measured κ;
they are not alternate default semantics.

**Evidence:** exhaustive `R` sweep, seeded replay, κ rejection example.

**Reader can now:** distinguish stochastic policy from implementation error and
declared approximation from defined behavior.

### Threshold 6: mechanism and proof

**Question:** Why is the implementation entitled to claim exactness and speed?

Only here introduce carrier rungs, interval rigor classes, symbolic sticky,
table construction, span filters, generated dispatch, gate tiers, and benchmark
doctrine.

**Evidence:** invariants linked to tests, source entry points, and conformance
records.

**Reader can now:** review or change the implementation.

## Proposed information architecture

### 1. Start

This section gets a reader from no package to a correct mental model. It should
contain four pages only.

1. **Home** — one-sentence purpose, a 60-second example, three trust claims,
   compatibility warnings, and route cards. Do not describe the complete
   navigation taxonomy.
2. **Install and Verify** — requirements, installation, smoke test, supported
   platform note, and how to pin a revision.
3. **First Session** — construct two values, inspect datum and code point, add
   explicitly and conveniently, apply one array operation, then stop. Target:
   700–900 words.
4. **Core Model** — the five-part visual followed by one short section per
   idea. No full application workflow and no internal carrier discussion.

The present Quickstart material on display styles moves to Reference. Its block
example moves to the block workflow. The present Mental Model becomes the
canonical conceptual definition rather than another tour of the API.

### 2. Workflows

These are outcome-oriented and independently usable after Core Model. Order
them by the likelihood that a practitioner needs them.

1. **Choose a Format**
2. **Quantize and Measure a Tensor**
3. **Control Rounding and Overflow**
4. **Run Operations over Arrays**
5. **Use Blocks for Dynamic Range**
6. **Make Stochastic Work Reproducible**
7. **Pack Values for Storage**
8. **Interoperate with Float16 and BFloat16**
9. **Read and Export Conformance**
10. **Register an Approximation**

Each workflow begins with a concrete desired outcome and ends with a validation
check. Quantize and Measure must not also teach packing and exhaustive custom
verification; those become links to Pack Values and Verify Custom Code.

### 3. Concepts and Standard

This section explains behavior without becoming an API catalog.

1. **P3109 in One Chapter** — the standard's vocabulary, value model,
   operations, projection, blocks, and the most important IEEE 754 differences.
2. **Format Anatomy** — parameters, aliases, representation types, range versus
   precision, signedness, and finite versus extended domain.
3. **Values, Code Points, and Conversion** — identity, constructors, raw values,
   stepping, and conversion semantics.
4. **The Exact-Then-Project Contract** — the one-write-path guarantee and what
   “exact” means, without implementation detail beyond the contract.
5. **Rounding and Saturation** — independent axes, named specs, deterministic
   and stochastic modes, boundary outcomes.
6. **Julia Numeric Behavior** — promotion refusal, ordinary-number carriers,
   Base overloads, sorting, equality, and conversion conventions.
7. **Session State and Reproducibility** — process-global defaults,
   default-consumption combinators, explicit local policy, RNGs, display policy,
   and concurrency implications.
8. **Performance Model** — specialization, warm tables, array calls, storage,
   and what not to benchmark.
9. **Defined, Stochastic, and Approximate** — three distinct sources of result
   variation and how each is declared or measured.
10. **Formal Code-Point Algebra** — a deliberately advanced foundation, linked
    after the intuitive model rather than presented as a parallel entrance.

### 4. Reference

Reference pages answer “what is the contract?” They do not persuade, narrate a
workflow, or repeat the implementation rationale.

1. **Formats and Value Queries**
2. **Projection Specifications**
3. **Operation Catalog**
4. **Arrays, Blocks, and Packed Storage**
5. **Defaults, Randomness, and Display**
6. **Julia Compatibility Register**
7. **Conformance and Approximation Registry**
8. **Public API Index**
9. **Internal API Index**

Every entry should provide, in a stable order: signature, availability/export
status, return type, semantic contract, exceptions, mutation/allocation note,
and one minimal example only if the signature is otherwise ambiguous.

Generated docstrings remain useful, but they follow the curated family index.
They are not a substitute for it. Remove references to obsolete section names
such as User Guide and Technical Examples.

### 5. Examples and Evidence

Examples should be scenarios, not a second tutorial track.

1. **Example Gallery** — cards filtered by Basic, AI, ML, Deep Learning,
   Verification, and Internals; each says what decision the example helps make.
2. **Applied Sessions** — complete, runnable public-API scenarios.
3. **Verification Sessions** — exhaustive quantizer checks, κ audits, fused
   kernel truth comparisons, and algebra checks.
4. **Performance Evidence** — benchmark report plus a short interpretation
   guide explaining cold/warm, exhaustive/sampled, and current environment.

The examples should be backed by canonical scripts under `docs/examples/`.
Documentation pages should include or generate from those scripts rather than
copying the same scenario into a tutorial, workflow, and gallery.

### 6. Internals and Contributing

This section starts with the package's invariants and then follows the data
path.

1. **Architecture and Invariants**
2. **Encoding and Decoding**
3. **Projection Engine**
4. **Oracle and Rigor Classes**
5. **Function Tables and Array Kernels**
6. **Exact Block Reductions**
7. **Verification Strategy**
8. **Add an Operation**
9. **Verify Custom Code**
10. **Benchmark Correctly**

Each implementation page names the public promise, internal invariant, source
entry points, proof obligation, relevant tests, and safe extension seam. This
turns the section into a maintenance map rather than an implementation essay.

### 7. Help

1. **Troubleshooting** — symptom, cause, fix, verification, deeper link.
2. **Cheat Sheet** — retrieval only; no unique normative facts.
3. **Glossary** — short canonical definitions with clickable definition links.
4. **Standard and Design Notes** — status-labelled links to the draft map,
   rationales, and development records.

The benchmark report belongs under Examples and Evidence, though Help may link
to it. The glossary's “See” column should contain real links, not names a reader
must search for.

## Page contracts

Every page should declare its mode to its author even if the mode is not shown
prominently to readers.

### Start or learning page

1. one-sentence promise;
2. prerequisites;
3. one running example;
4. alternating action and explanation;
5. a checkpoint that asks the reader to predict or modify something;
6. a short recap in the vocabulary just learned;
7. a typed exit.

Do not introduce an API merely because it is adjacent. Do not explain an
internal mechanism unless it changes the reader's next action.

### Workflow page

1. outcome in imperative voice;
2. “Use this when” and “Do not use this when”;
3. inputs and assumptions;
4. shortest correct procedure;
5. validation metrics or assertions;
6. failure modes, each with a diagnostic;
7. variations;
8. links to concept and reference contracts.

Ingredients lists are useful only when they describe actual prerequisites. A
list that merely repeats function names should become a compact API note.

### Concept page

1. claim in plain language;
2. intuition or visual model;
3. formal statement;
4. one boundary case;
5. consequences for users;
6. relationship to P3109 and Julia, clearly distinguished;
7. links to workflows and reference.

### Reference page

Use tables and stable subsections. Keep prose local to a contract. Put rationale
in Concepts and Standard and implementation in Internals.

### Internal page

1. public promise;
2. invariant;
3. data/control flow;
4. source map;
5. why the optimization is sound;
6. failure modes;
7. tests and evidence;
8. extension seam.

### Example page

1. scenario and question;
2. reproducibility preamble (version, seed, defaults, imports);
3. complete runnable code;
4. selected output;
5. interpretation, including what the result does not prove;
6. next decision.

## Style and tone

### Voice

Use calm, direct, technically confident prose. Address the reader as “you” in
instructions and use declarative language for contracts. Avoid both marketing
superlatives and apologetic hedging.

Prefer:

> `Convert` computes a value and projects it once under the spec you provide.

Over:

> You can think of `Convert` as basically a very accurate conversion helper.

Separate three kinds of statement visibly:

- **P3109 defines** — normative semantics;
- **SmallFloats.jl guarantees** — implementation contract;
- **we recommend** — application or performance advice.

Do not slide between them in one paragraph.

### Information order

Lead with the consequence, then the mechanism:

> Pass a concrete alias as an array element type; the abstract format boxes
> elements and prevents specialization.

Only then explain why `Binary{K,P,SGN,EXT}` is abstract. Readers should not need
to finish a design rationale to discover the safe action.

### Terminology

Maintain a small controlled vocabulary file for at least:

- format, representation, datum, code point, code unit;
- operation, exact result, projection, rounding, saturation;
- defined result, stochastic result, approximate result, κ;
- block, scale, element, represented value;
- datum carrier, promotion carrier, rung, rigor class.

Use one term for one concept. Do not alternate between “code,” “code point,”
and “bit pattern” unless the distinction is intentional. Use `NaN`, `Inf`,
`Float16`, and named projection constants consistently.

### Headings

- Tasks use verbs: “Choose a Format,” “Pack Values for Storage.”
- Concepts use noun phrases: “The Projection Contract.”
- Reference uses API families: “Projection Specifications.”
- Internals name a mechanism or invariant: “Exact Block Reductions.”
- Use sentence case consistently.
- A heading must tell the reader what changes by reading the section; avoid
  generic headings such as “More details.”

### Paragraphs and emphasis

Target two to five sentences per paragraph and one logical move per paragraph.
Use bold for a decision or invariant, not for general excitement. Prefer lists
for alternatives or procedures, not for prose that happens to have three
sentences.

### Admonitions

Give each type a fixed meaning:

- `!!! warning` — likely silent wrong result or invalid interpretation;
- `!!! danger` — data loss, non-reproducibility, or an unsupported operation;
- `!!! tip` — optional ergonomic improvement;
- `!!! note` — scope or terminology clarification;
- `!!! perf` — performance behavior that does not change semantics.

Every warning should include the safe alternative. Avoid repeating the same
warning verbatim on several pages; state it canonically once and use a short
linked reminder elsewhere.

### Code and output

- Use `julia-repl` only when output is part of the lesson.
- Use `julia` for complete scripts or fragments where output would distract.
- Every ellipsis must be visibly editorial, never something the reader might
  paste.
- Every random example names a seed unless nondeterminism is the subject.
- Every example that changes process-global state restores it or uses a scoped
  form.
- Use one default display style within teaching pages. Teach display policy in
  Reference, not during the first computation.
- Prefer one stable house format (`Binary8p4se`) for continuity, then introduce
  another format only because its changed property matters.

## Visual language

The five-part graphic should become the visual grammar for the manual rather
than an isolated illustration.

Use a consistent mapping:

- navy: datum sets, exact values, and exact math;
- teal: stored values, code points, and defined results;
- gold: policy choices such as rounding and saturation;
- dashed teal: explicit optional approximation;
- solid arrows: value/data flow;
- converging arrows: policy inputs;
- numbered circles: learning sequence, not arbitrary decoration.

Create a small set of reusable diagrams:

1. the five-part whole;
2. format budget (`K` divided among sign, exponent, and significand);
3. datum lattice with between-grid projection;
4. rounding × saturation decision matrix;
5. array path (public call → table or scalar kernel, same result contract);
6. block path (scale × elements → exact reduction → one projection);
7. defined versus stochastic versus approximate result provenance;
8. implementation layers and verification gates.

All diagrams should be native SVG with named layers and unique object IDs, with
a PNG fallback for the PDF pipeline. They need descriptive alt text, readable
text at the site's content width, and no meaning conveyed by color alone.
Captions should state the inference the reader should make, not repeat the
title.

## Cross-linking and retrieval

### Typed exits

Use consistent labels at page ends. A learning sequence has exactly one Next
link. Other links are classified by purpose. This turns cross-links into a
concept graph rather than a bag of related pages.

### Definition links

The first use of a specialized term on a page links to its canonical concept
or glossary anchor. Later uses on that page do not. Glossary entries link back
to canonical definitions and relevant API reference.

### API links

Function names link to docstrings or curated reference entries. Narrative
links use descriptive text (“projection specification contract”), never “here.”

### Stable URLs

Do not rename every source file merely to match the new labels. First reorganize
the navigation and rewrite in place. Where consolidation removes a page, keep a
short redirect/stub for at least one release or configure an explicit redirect.
Preserving incoming links is more valuable than cosmetic filename symmetry.

## Single sources of truth

The rewrite should reduce facts that can drift without turning prose into a
templating project.

### Generate volatile tables and counts

Generate or test:

- legal `K` range;
- total, exported, and opt-in format counts;
- operation counts and names;
- predefined projection grid;
- default settings;
- format query tables;
- benchmark environment metadata.

Keep explanations handwritten. Generate facts, not voice.

### Canonical example corpus

Place complete scenarios in `docs/examples/` with a small manifest containing
title, audience, concepts, public/internal status, seed, and source page. A
scenario may be rendered in more than one index, but its code and expected
output have one owner.

### Semantic assertions

Extend documentation tests beyond stale literal searches. High-risk assertions
should execute directly, including:

- NaN's position in total order and `sort`;
- constructor versus `convert` behavior for `Unsigned`;
- alias subtyping versus identity;
- default projection and display policy;
- `Float16`/`Binary16p11se` non-equivalence;
- saturation examples used throughout the manual;
- block staging claims;
- κ understatement rejection.

The goal is not to machine-check prose. It is to encode facts already repeated
often enough that contradiction is predictable.

## Build and quality gates

Add a documentation lint stage before HTML/PDF rendering.

1. every `docs/src/*.md` page is either in navigation or explicitly excluded;
2. no duplicate page appears in navigation;
3. all local links and anchors resolve;
4. typed Next links form no accidental cycle and every sequenced page has one;
5. obsolete section names are forbidden outside migration notes;
6. page titles are unique;
7. glossary See cells contain links;
8. every image has alt text and both SVG/PNG assets when required by PDF;
9. all `julia-repl` examples execute and compare output;
10. complete `julia` examples execute where practical, not merely parse;
11. source facts agree with package constants;
12. HTML and PDF both build; PDF link, overflow, and missing-glyph gates pass.

For code fragments that cannot execute alone, mark them explicitly as
`julia-fragment` (or with metadata) rather than inferring from the fence type.
That lets the test harness distinguish deliberately partial code from a missed
test opportunity.

## Realization map for the current pages

This is a content migration map, not a mandate to rename every file.

| Current material | Action | Target role |
|---|---|---|
| `index.md` | rewrite and shorten | Home and route selection |
| `installation.md` | retain, add verification and version policy | Install and Verify |
| `quickstart.md` | cut display and blocks; end after first array operation | First Session |
| `mentalmodel.md` | make the five-part visual primary; remove duplicated API tour | Core Model |
| `fifteenminutes.md` | retain only standard orientation and IEEE contrasts | P3109 in One Chapter |
| `tutorial1_values.md` | split task material from concept definitions | Values concept + format workflow |
| `tutorial2_projection.md` | retain as learning chapter; remove reference tables | Control Rounding and Overflow |
| `tutorial3_arrays.md` | keep public array behavior; move cache internals down-stack | Run Operations over Arrays |
| `tutorial4_blocks.md` | keep one staged end-to-end scenario | Use Blocks for Dynamic Range |
| `tutorial5_stochastic.md` | retain; unify RNG guidance with stochastic how-to | stochastic concept + workflow |
| format/tensor/block/stochastic how-tos | narrow to one outcome each | Workflows |
| packed/Float16/conformance/approximation how-tos | retain and standardize template | Workflows |
| seven explanation pages | consolidate overlaps into nine concept chapters above | Concepts and Standard |
| `formal_codepoints.md` | retain as advanced endpoint | Formal Code-Point Algebra |
| curated `ref_*.md` pages | normalize entry schema and names | Reference |
| `ref_external.md`, `ref_internal.md` | update family links; remove obsolete prose labels | API indices |
| `examples_index.md` | rebuild from example manifest | Example Gallery |
| applied/internal example pages | generate from or include canonical scripts | Examples and Evidence |
| architecture/engine/oracle/tables/blocks pages | reorder by data path and add source/test maps | Internals |
| verification page | expand into evidence map with exhaustive/sampled labels | Verification Strategy |
| add/verify/benchmark pages | retain, add contributor checklists and PR gates | Contributing |
| `cheatsheet.md` | remove unique explanations; make retrieval-only | Help |
| `troubleshooting.md` | retain symptom-first structure; make all destinations links | Help |
| `glossary.md` | shorten definitions and link every See entry | Help |
| `benchmarks.md` | keep generated; add interpretation front matter | Performance Evidence |
| `papers_index.md` | retain status labels and clarify normative versus historical | Standard and Design Notes |

## Migration sequence

### Phase 0: establish a trustworthy baseline

- Resolve known semantic contradictions before moving prose.
- Record current page URLs, inbound links, word counts, and example ownership.
- Add link/anchor and navigation-coverage lint.
- Add semantic tests for sorting/NaN and the other repeated high-risk facts.

**Exit criterion:** the current manual is internally consistent even though its
architecture is still old.

### Phase 1: install the new map

- Change top-level navigation to the seven proposed routes.
- Rewrite Home around reader jobs and route cards.
- Add page-type metadata and typed exit components/conventions.
- Preserve filenames and anchors where possible.

**Exit criterion:** every current page has one intentional place and every old
top-level label has one documented successor.

### Phase 2: rebuild the common start

- Rewrite First Session and Core Model together.
- Use the same `Binary8p4se` values across both so the second page deepens the
  first rather than restarts it.
- Move display, block, cache, and conformance detail to their proper pages.
- User-test the route with someone who knows Julia but not P3109.

**Exit criterion:** a new reader can explain datum, code point, projection, and
explicit spec and can run a scalar and array operation in 15 minutes.

### Phase 3: rebuild workflows

- Apply the workflow page contract to each task.
- Split packing and custom verification out of the tensor workflow.
- Merge duplicated stochastic reproducibility material around one canonical
  example.
- Add validation checks and “do not use when” guidance.

**Exit criterion:** every workflow has one outcome, one runnable path, and one
verification method.

### Phase 4: separate concepts from reference

- Consolidate definitions into canonical concept pages.
- Remove narrative rationale from reference tables.
- Make the P3109/SmallFloats/Julia distinction explicit on every relevant page.
- Build the terminology registry and link glossary entries.

**Exit criterion:** a concept has one canonical definition and an API family has
one canonical contract table.

### Phase 5: single-source examples and evidence

- Create `docs/examples/` and its manifest.
- Move complete scenarios there without changing results.
- Generate or include applied and verification pages.
- Expand the test harness from parsing complete scripts to executing them.

**Exit criterion:** no runnable scenario has manually copied source in multiple
pages.

### Phase 6: rebuild internals as a maintainer map

- Add public promise, invariant, source map, proof, tests, and extension seam to
  each internal page.
- Cross-link contributor checklists to exact gates.
- Label exhaustive and sampled evidence at the point of each claim.

**Exit criterion:** a contributor can locate the write path, make one scoped
change, and identify all required gates from the documentation alone.

### Phase 7: visual and PDF pass

- Add the reusable diagram set and captions.
- Apply a restrained Documenter stylesheet: readable line length, consistent
  figure treatment, route cards, and responsive tables.
- Review every page in HTML and PDF, not only generated-source diffs.
- Remove migration stubs only under a stated URL policy.

**Exit criterion:** all quality gates pass and a visual review covers every PDF
page changed by the restructure.

## Definition of done for each rewritten page

A page is done only when:

- its reader, job, prerequisites, and page mode are explicit to the author;
- its opening states the outcome or question;
- it contains no definition owned by another page unless the repetition is a
  one-sentence reminder linked to the owner;
- all code is classified as executable example or intentional fragment;
- examples pass in a clean session with defaults restored;
- warnings include a safe action;
- P3109 requirements, package guarantees, and advice are distinguishable;
- API names and local links resolve;
- its typed exit is intentional;
- images are accessible and render in HTML and PDF;
- the page passes a source diff check, automated gates, and human reading at
  normal documentation width.

## Review of the initial plan

The first version of this proposal was a simpler consolidation: reduce the
manual to Start, Guides, Concepts, Reference, Internals, and Help; merge repeated
pages; and shorten everything. That direction was insufficient. It was reviewed
against the actual corpus and improved in the following ways.

### Improvement 1: preserve examples as evidence, not decoration

The initial consolidation would have buried applied and verification sessions
inside workflows or internals. That loses one of this manual's distinctive
strengths: readers can inspect complete scenarios and the evidence behind
claims. The refined plan gives Examples and Evidence an explicit route while
removing its duplicate teaching role.

### Improvement 2: retain Diátaxis as a page contract

Dropping Tutorials/How-To/Explanations from navigation could accidentally make
pages less disciplined. The refined plan separates navigation from authorship:
reader jobs determine where a page lives; a page contract determines how it is
written.

### Improvement 3: create one common start before audience branches

Separate practitioner, standard, and contributor entrances would repeat the
core semantics. The refined plan has all readers cross the same identity and
projection thresholds, then branches them by job.

### Improvement 4: do not optimize for the smallest page count

Merging everything would produce long mixed-purpose chapters. The refined plan
sets one promise per page and permits more pages when the promises genuinely
differ. Reduction comes from eliminating duplicated definitions and examples,
not from concatenation.

### Improvement 5: preserve URLs during conceptual change

A clean new filename tree is attractive to maintainers and costly to users,
search results, and old reports. The refined plan reorganizes navigation first,
rewrites in place where practical, and requires redirects for actual removals.

### Improvement 6: treat PDF as a first-class product

The initial plan assumed site navigation and collapsible teaching devices. The
refined plan requires every device to have a PDF behavior, keeps critical
answers out of HTML-only disclosure, and places visual review in the migration
exit criteria.

### Improvement 7: test contradictions, not merely links

Link checking would not catch the current NaN-order contradiction. The refined
plan identifies a small, high-value semantic assertion suite derived from
facts repeated throughout the manual.

### Improvement 8: generate facts, not prose

Generating pages wholesale would make the manual harder to edit and could turn
style into a build-system problem. The refined plan generates volatile tables,
counts, and example output while keeping explanations authored and reviewed as
prose.

## Risks and mitigations

| Risk | Consequence | Mitigation |
|---|---|---|
| consolidation removes useful depth | advanced readers lose the reason behind guarantees | move depth down-stack; do not delete until target page exists |
| routes become another taxonomy | readers still cannot choose | test Home with task prompts; route cards name jobs, not document kinds |
| examples drift during migration | trust decreases despite cleaner prose | move without semantic edits first; execute before and after |
| custom generation becomes brittle | contributors avoid documentation work | keep tooling small, deterministic, and documented; generate only volatile facts |
| internal pages stale quickly | contributor map becomes actively harmful | name source/test ownership and add a release checklist trigger |
| PDF becomes too long | sequential readers cannot see priority | strong part structure, route introductions, and omission of web-only navigation prose |
| terminology registry becomes bureaucratic | authors work around it | limit it to genuinely confusable domain terms and automate only obvious variants |
| preserving URLs constrains better grouping | source tree remains historically named | separate navigation labels from filenames; revisit filenames only with redirects |

## Governance after the rewrite

Documentation ownership should follow the thing that can invalidate a page.

- changes to format parameters or aliases trigger Format Anatomy, Formats
  Reference, Home facts, and consistency tests;
- changes to projection or saturation trigger Core Model, projection workflow,
  projection reference, and semantic examples;
- changes to Base integration trigger Julia Numeric Behavior, compatibility
  reference, and troubleshooting;
- changes to arrays/tables/blocks trigger the corresponding workflow,
  performance concept, internal mechanism, and benchmarks;
- changes to stochastic APIs trigger reproducibility workflow and RNG/defaults
  reference;
- changes to approximation/conformance trigger provenance concept, workflow,
  registry reference, and verification examples.

Every release should run a documentation review checklist:

1. build HTML and PDF from a clean checkout;
2. run examples and semantic assertions;
3. verify public API/reference coverage;
4. inspect changed generated tables and benchmark provenance;
5. search for obsolete section names and unsupported version claims;
6. review visual diffs for changed PDF pages;
7. confirm redirects for removed pages;
8. read Home, First Session, and Core Model as a continuous route.

## Measures of success

The rewrite succeeds when readers can do the following, not merely when the
navigation matches this proposal.

- A Julia user reaches a successful operation in under five minutes.
- After 15 minutes, that user can explain datum versus code point and exact
  computation versus projection.
- A practitioner can choose a candidate format and report RMSE, maximum error,
  and overflow/clamp fraction without reading internals.
- A user can find a public signature or failure contract from Home in at most
  two navigation decisions.
- A contributor can trace an operation from public call through projection and
  identify its tests without searching the entire repository.
- No runnable example exists as divergent manual copies.
- No page uses an obsolete section name.
- High-risk semantic statements cannot contradict the implementation without a
  failing test.
- HTML and PDF present the same essential content and both pass their gates.

These outcomes should be checked with a small set of task-based reading tests,
not inferred from page count or word count. Ask readers to narrate what they
expect before running an overflow, choose between two formats, locate the
contract for a projection spec, and identify where they would add an operation.
Their wrong turns are documentation defects and should feed the next revision.

## Final recommendation

Do not begin by rewriting all 51,000 words. Begin by making the present facts
consistent, installing the new reader map, and rebuilding the common first 15
minutes. Those changes reveal which later pages are genuinely redundant and
which are valuable depth. Then move outward in the order readers learn:
workflows, concepts and reference, examples and evidence, internals, and only
then visual polish.

The organizing idea is simple: **the manual should perform the same discipline
as the implementation—one clear path to a defined result, with alternatives
explicit and evidence attached.**
