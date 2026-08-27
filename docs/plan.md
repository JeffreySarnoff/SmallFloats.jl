# Plan: give SmallFloats documentation the ByteFloats flow without shrinking it

## Goal

Adopt the clarity, reader progression, and disciplined technical voice of the
ByteFloats documentation while retaining SmallFloats' fuller coverage: guided
workflows, concepts, separate reference pages, evidence pages, and
implementation notes.  This is a reorganization and rewrite plan, **not** an
11-page reduction or a textual port from ByteFloats.

The governing rule is simple: ByteFloats can supply the documentation approach,
but SmallFloats source is the authority for every technical claim.  Where the
two implementations differ, SmallFloats documentation must say what SmallFloats
does, why that design exists, and what a user or maintainer should do about it.

## What to carry over from ByteFloats

Carry over the **reader experience**, not merely ByteFloats' headings or its
facts.  Its prose succeeds because it is direct, technically specific, and
pleasantly assured: it tells the reader what matters, shows it in a small real
session, then explains the consequence before moving on.  It neither hides
complexity nor makes the reader assemble the argument alone.

Use these qualities consistently across the existing page set:

1. Give each page one job and name its intended reader at the start.  The
   ByteFloats guide pages make it clear whether they are for a new user, an API
   user, or a maintainer.
2. Establish the mental model before presenting the API.  Explain datum,
   code-point, exact evaluation, and projection before cataloguing functions.
3. Use a predictable progression: motivation and tour; everyday use; runnable
   examples; Julia integration; internals; maintenance and verification;
   docstring reference.
4. Make implementation claims concrete and bounded.  State the dispatch policy,
   carrier, cache/table policy, or verification evidence that makes a promise
   true; avoid vague claims such as “fast” or “exact” without the qualifying
   condition.
5. Pair important concepts with a short Julia session and a practical failure
   mode.  Keep the current SmallFloats workflows, but give them ByteFloats'
   compact “what this demonstrates / why it matters” framing.
6. End pages with a small, purposeful “See also” set.  Do not use links as a
   substitute for deciding where an explanation belongs.
7. Separate public guarantees from implementation details.  Public pages state
   the contract first; technical pages explain how the current implementation
   meets it and identify extension seams.

## Prose texture migration

The rewrite should let a reader feel that the SmallFloats manual and the
ByteFloats manual belong to the same family: inviting at the door, exact in the
middle, and candid about boundaries.  It should not read as an imposed template
or as ByteFloats with names changed.

### The desired voice

- Open a page with a clear proposition, not a filing label.  Prefer “A format is
  a finite set of exact datums” or “Projection is the only write path” to a
  heading followed by a catalogue of functions.
- Use an active subject and concrete verb.  “`decode` returns the format's exact
  datum carrier” is stronger and clearer than “decoding is provided through a
  carrier-based mechanism.”
- Let a compact REPL exchange establish the fact, then read the exchange with
  the user.  The explanation after the code should tell them what changed, what
  did *not* happen, and why the distinction is useful.
- Build a paragraph around one turn of thought: claim → reason → consequence.
  Use short paragraphs for a local fact and a short list only when the reader
  truly has choices or cases to compare.
- Be precise without becoming ceremonial.  The technical guide may name a
  dispatch policy or a proof obligation; the user guide should give that detail
  only when it changes a call, result type, performance expectation, or safe
  usage pattern.
- Make limitations legible and unembarrassed.  A good boundary statement says
  what is unsupported, why that boundary exists, and the correct alternative.
- Use emphasis sparingly to mark a contract or a trap, not to decorate every
  paragraph.  Prefer ordinary prose and a well-chosen example over a wall of
  warnings.

### Reusable page rhythm

Most user-facing pages should follow this rhythm, scaled to their subject:

1. **Promise.** One or two sentences say what the reader will be able to do or
   understand.
2. **Small proof.** A runnable example gives the reader a real object, result,
   or boundary case.
3. **Reading of the result.** Explain the semantic fact exposed by the example;
   do not leave code to carry the whole argument.
4. **Practical rule.** State the choice, trap, or next action in language a user
   can reuse.
5. **Route onward.** Link to the page that owns the next concept.

Technical pages should use a companion rhythm: **invariant → mechanism → why
this mechanism is safe → evidence → extension seam**.  This is the ByteFloats
technical-guide strength worth preserving: performance machinery is described
as an implementation of a stated semantic obligation, never as a competing
definition of the result.

### Controlled use of ByteFloats-style devices

Adopt these devices where they earn their place:

| Device | How to use it in SmallFloats | Guardrail |
|---|---|---|
| A short “why this exists” opening | Use it on the introduction, core model, rounding, and technical-guide landing page to connect exactness with real format-selection or research mistakes. | Do not reuse byte-format examples if a wide-format counterexample makes the point more honestly. |
| Bold design promises | Use three or four promises on Home and concise guarantees at the start of a major guide. | Each promise needs a source/test/ledger authority and an explicit scope. |
| Thirty-second tour | Show construction, explicit projection, and one array or format query in a single coherent transcript. | Include a SmallFloats-only observable fact, such as abstract-format versus representation or a wide-format route. |
| “The rule to remember” sentence | Use after a subtle distinction such as `Unsigned` code-point construction, carrier conversion, or explicit projection. | It must be literally correct for both Code8 and Code16, or name its narrower scope. |
| Contrastive sentence | Explain the tempting but wrong mental model, then state the correct one: “A code point names a datum; it is not a bit-pattern reinterpretation.” | Do not frame a source implementation detail as a language guarantee. |
| Layer map and tables | Use tables to make relationships inspectable: layer → responsibility → invariant; format class → representation → carrier → policy. | Do not use tables merely to repeat surrounding prose. |
| Closing checklist | Use in workflows, extension guides, verification, and benchmarking. | A checklist item must be observable or testable, not aspirational. |

### Sentence-level editing pass

After technical correctness review, make a dedicated texture pass over every
rewritten page:

- Replace throat-clearing (“This section will discuss…”, “It should be noted…”)
  with the proposition itself.
- Replace unexplained noun piles with a sentence that establishes their
  relationship before naming all of them.
- Turn an isolated source-file reference into a reader-facing reason for opening
  that file.
- Follow a dense derivation with one plain-language consequence and, where
  useful, one code-point-level example.
- Preserve the recurring SmallFloats vocabulary and terms of art, but normalize
  its cadence: one strong sentence first, qualifications immediately after, and
  links only once the reader knows why they would follow them.
- Read adjacent pages in sequence, not one at a time.  Their openings, repeated
  explanations, transitions, and level of confidence must sound continuous.

This pass is editorial, not cosmetic.  If simplifying a sentence uncovers an
uncertain technical claim, return it to Gate 2 and repair the claim rather than
polishing around it.

## Target reader flow and navigation

Keep the existing authored pages, but reshape `docs/pages.jl` and `index.md` so
the top-level route reads as a coherent manual rather than a file taxonomy:

1. **Home** — concise promise, a thirty-second REPL tour, scope (`K = 3:16`),
   and a documentation map that describes what each section is for.
2. **Introduction and first use** — retain `install_and_verify.md`,
   `first_session.md`, and `core_model.md` as the on-ramp.  Make their hand-off
   explicit: install; construct and inspect one value; understand the model.
3. **User guide: concepts and workflows** — retain the concept pages and task
   workflows, ordered from format choice and values through projection, arrays,
   blocks, packing, conformance, and approximation.  Add short section landing
   text in the home page and, if useful, a `user_guide.md` overview page rather
   than merging the detailed pages.
4. **Examples** — retain the gallery, applied, verification, and performance
   pages.  Make the gallery an actual index of runnable examples and organize
   the examples with the same Basic / General AI / ML / Deep Learning ladder
   used effectively in ByteFloats.
5. **Julia compatibility and reference** — keep the focused Julia compatibility
   page and the API-family reference pages.  Present the curated references
   before the public/internal docstring indices.
6. **Technical guide** — retain the individual implementation pages, but give
   them an explicit technical-guide landing page or section introduction that
   supplies the architecture/layer map and reading order.
7. **Technical examples and maintenance** — retain custom verification,
   benchmarking, and operation-extension pages.  Present them as recipes for
   maintainers, with the same closing checklists and evidence requirements that
   ByteFloats uses.
8. **Help and design notes** — retain troubleshooting, glossary, cheat sheet,
   and standard/design notes as support material; link to them from the relevant
   earlier pages instead of making them the primary learning route.

No existing substantive page is to be deleted merely to imitate the ByteFloats
table of contents.  A page may be split, merged, or gain a landing page only
when that improves ownership and the rewritten destination preserves its
technical content.

## Page ownership map

The following map makes “better flow” actionable without collapsing the manual.
It identifies the *one* page that teaches a concept fully; other pages should
link to it and state only the local consequence.  This is the primary defence
against duplicate explanations drifting apart.

| Reader need | Primary teaching pages | Supporting pages and their limited role |
|---|---|---|
| Get running and understand one value | `install_and_verify.md`, `first_session.md`, `core_model.md` | `index.md` routes; the cheat sheet only recalls syntax. |
| Understand the P3109 model and formats | `concept_p3109.md`, `concept_format_anatomy.md`, `concept_values_codepoints.md` | `concept_codepoint_algebra.md` is the formal derivation; format reference is lookup-only. |
| Choose and apply a projection | `concept_rounding_saturation.md`, `concept_exact_then_project.md`, `workflow_rounding_overflow.md` | projection reference gives signatures and tables; workflows give recipes. |
| Select a format and quantize data | `workflow_choose_format.md`, `workflow_quantize_measure.md` | applied examples supply realistic data; performance material supplies measurement discipline. |
| Use Julia values safely | `concept_julia_numeric.md`, `reference_julia_compat.md`, `workflow_float16.md` | troubleshooting records failure symptoms and remedies. |
| Use arrays, blocks, and storage | `workflow_arrays.md`, `workflow_blocks.md`, `workflow_packed_storage.md` | the array/block/storage reference is API lookup; internals explain implementation. |
| Reproduce or assess results | `workflow_stochastic.md`, `workflow_conformance.md`, `workflow_approximation.md`, `concept_defined_stochastic_approximate.md` | verification sessions prove the method; conformance reference gives exact API. |
| Find a runnable example | `examples_gallery.md` | applied, verification, and performance pages contain the executable narrative and evidence. |
| Understand implementation | `internals_architecture.md` followed by codec, projection, oracle, tables, blocks, and verification pages | each page owns one layer; it must link forward and back to the layer map. |
| Extend or assess implementation work | `internals_add_operation.md`, `internals_verify_custom.md`, `internals_benchmark.md` | the technical pages provide invariants; these pages provide the procedure/checklist. |
| Look up a name or recover from a problem | API-family references, `help_cheat_sheet.md`, `help_troubleshooting.md`, `help_glossary.md` | none should become a second tutorial. |

Add short **Purpose**, **Prerequisites**, and **Next step** blocks to the top or
bottom of every substantive guide/workflow page.  They should be prose and
links, not a boilerplate template: an API reference, a worked workflow, and an
internal design page require different detail.

## Editorial contract

Every rewritten page must meet these rules:

- Lead with the outcome for its reader, then establish the smallest vocabulary
  needed to use or understand it.
- Distinguish a **semantic guarantee** (“defined result is exact then projected
  once”) from a **current mechanism** (“Code8 uses a generated decode table”).
  The former belongs in user material; the latter belongs in technical material.
- State scope directly beside a claim: format class, signedness/domain where
  relevant, carrier, rounding/saturation policy, and whether an observation is
  measured or derived.
- Make every code block either runnable as written or label it deliberately as
  pseudocode.  REPL output must be regenerated after source changes.
- Use one canonical term per concept: *format* for the abstract mathematical
  format, *representation* for `Code8`/`Code16`, *code point* for the stored
  unsigned value, and *datum carrier* for `decode`'s exact result type.
- Treat current benchmark numbers as evidence with provenance, never as a
  language-level guarantee.  Keep the benchmarking doctrine next to the data.

## Claim ledger and review gates

Create `docs/src/claim_ledger.md` during implementation.  It is an internal
documentation-maintenance artifact, not a user guide.  Each row records: claim
identifier; exact prose location; source/test/measurement authority; scope;
last verification date; and reviewer status.  The ledger must cover every row
in the implementation-difference audit below and every numerical performance
claim.

Use four gates; do not move on when a gate fails.

| Gate | Entry condition | Required evidence | Exit condition |
|---|---|---|---|
| 1. Information architecture | Page ownership map accepted | proposed `pages.jl` tree, index documentation map, old-to-new link map | every current page has an owner and no reader route depends on an orphan page |
| 2. Semantic rewrite | A page is selected for rewrite | relevant source/docstrings/tests and claim-ledger rows are open | prose distinguishes public contract from implementation and all code/output has been checked |
| 3. Consistency audit | All planned prose is drafted | repository search results, ledger review, duplicate-concept review | every implementation-sensitive match is classified “correct as scoped”, rewritten, or removed |
| 4. Rendered release | Source review has passed | fresh local and CI-layout HTML builds, link reports, and PDF validation when available | artifacts render, links and anchors resolve, and a human has sampled the key reader routes |

The link map is required even if filenames are retained: navigation changes can
break cross-links and PDF anchors without changing a filename.

## Content work by documentation layer

### Home, introduction, and core model

Rewrite `index.md` with the ByteFloats home-page pattern: one-sentence scope,
three-to-four design promises, a short executable tour, then a documentation
map organized by reader goal.  Preserve the SmallFloats claims that distinguish
it: all 504 legal formats, abstract format versus concrete representation, and
exact-then-project semantics.

Tighten `first_session.md` and `core_model.md` so they introduce concepts once
and then link forward.  The core model should remain the semantic source for:

- one NaN and one zero;
- datums versus code points;
- exact evaluation followed by one projection;
- explicit rounding and saturation policy; and
- declared, measured approximation.

### User concepts, workflows, and cheat sheet

Keep the detailed concepts and workflows.  Rewrite their openings so each says
the prerequisite, desired outcome, shortest correct procedure, validation step,
and likely trap.  This preserves the current useful task orientation while
making it read as one guided user manual.

Rewrite `help_cheat_sheet.md` in ByteFloats' compact lookup style, but retain
wide-format facts: `Unsigned` means a code point at every width, the code unit
is not always `UInt8`, and callers must not assume `decode` always yields
`Float64`.

### Examples, evidence, and performance

Retain the current example depth.  Give `examples_gallery.md` the role of the
ByteFloats technical/user-example table of contents: each entry names the
audience, demonstrates one contract, and links to the runnable section.

Review every fixed timing, storage-size, and table-size statement in
`examples_performance.md`, `concept_performance.md`, and workflow pages.
Publish measurements with format, policy, Julia version, hardware context, and
whether the path is `Code8`/table or `Code16`/compute.  Do not carry forward a
ByteFloats byte-only timing or table-size assertion as a SmallFloats generality.

### Technical guide and maintenance material

Make `internals_architecture.md` the technical-guide entry point.  Add a layer
map and explicit reading order, then retain the existing focused pages for codec,
projection, oracle, tables/kernels, blocks, verification, custom verification,
benchmarks, and adding operations.  The architectural landing page should
distinguish stable public invariants from current optimization choices.

Use the ByteFloats maintenance-page pattern in `internals_add_operation.md`:
universal duties first, worked examples by arity/layer, then a closing checklist
covering oracle semantics, projection, tables, conformance, tests, docs, and
benchmarks.  Preserve SmallFloats-specific extension gates for representations
and carriers.

## Mandatory implementation-difference rewrite audit

Before the new navigation is published, audit all `docs/src/**/*.md` and rewrite
every implementation-sensitive statement below.  The listed pages are starting
points, not an exhaustive exclusion list.

| Topic | Do not describe SmallFloats as ByteFloats | Required SmallFloats wording/content | Primary pages to rewrite |
|---|---|---|---|
| Supported domain | A byte-only `K = 3:8` implementation with 120 formats | `K = 3:16`, 504 legal formats; 120 small aliases exported by default and wider formats available deliberately | `index.md`, `core_model.md`, `concept_p3109.md`, `concept_format_anatomy.md`, cheat sheet, format reference |
| Representation | Every value stores a `UInt8` code point | `Code8` and `Code16` are concrete representations selected by `reptype`; use `codeunit_type(F)` where storage width matters | format anatomy, values/codepoints, codec internals, references, packed-storage workflow |
| Decode result | `decode(::Binary)::Float64` universally | `decode` returns `datumcarrier(typeof(v))`; explain exact carrier selection and explicit `Float64(decode(x))` when rounding is wanted | core model, values/codepoints, exact-then-project, codec internals, Julia compatibility, cheat sheet |
| Decode implementation | A generated `2^K` Float64 tuple lookup for every format | `Code8` uses a generated lookup; `Code16` uses computational decode by `decodepolicy`; a wide constant tuple is intentionally refused | codec internals, performance model, architecture, benchmark/evidence pages |
| Finite datum construction | Float64 bit assembly is universally valid | Code8/Float64 retains bit assembly; wide and non-Float64 carrier paths use carrier-generic construction (`ldexp`) to preserve range and exactness | codec internals, technical landing page, exact-then-project |
| Special values and zero | Bare Float64 special literals are adequate | Describe carrier-generic NaN/infinity/zero handling and the single-zero datum invariant | codec internals, oracle, core model |
| Encode contract | Always returns `UInt8`; ByteFloats' local canonical-SQ check is part of the behavior | `encode` returns `codeunit_type(F)` and relies on its documented datum-set/caller precondition.  Do not claim a runtime `canonical_SQ` diagnostic unless it is restored in source | projection engine, codec internals, add-operation guide, internal API reference |
| Order and sort | NaN-last `typemax(UInt16)` sentinel and byte-only keys | NaN is smallest in the draft total order; `nan_order_key(F) == 0`; keys use `orderkeytype(F)` (`UInt32` for Code16), and counting sort has a size gate | core model, code-point algebra, values/codepoints, codec internals, arrays/performance pages |
| Tables and kernels | Every result code is `UInt8`; byte-only table budgets and K=8 compute boundary | Tables store `codeunit_type(fr)` and table admission/budget decisions must be expressed for `K ≤ 16`; describe the actual SmallFloats table and threaded compute policies | technical tables, arrays workflow, performance model, architecture, benchmarks |
| Exact arithmetic/oracle | Only ByteFloats' Float64/Float128/BigFloat story | Preserve the SmallFloats carrier ladder and Dyadic↔Rational bridge, including where carriers are exact and where interval/MPFR fallback is required | exact-then-project, oracle, architecture, verification |
| Julia integration | Promotion and conversion always lead to Float64 | Describe the SmallFloats promotion carrier and any type/range gate before giving conversion examples | Julia numeric concept, Julia compatibility reference, Float16 workflow |
| Packed/block storage | Byte-sized element assumptions | State storage in terms of `codeunit_type`, bitwidth, `PackedVector`, and `BlockVector`; recheck examples with wide formats | packed-storage and block workflows, storage reference, technical blocks |
| Verification evidence | ByteFloats assertion counts, exhaustive domains, or benchmark values | State the current SmallFloats gates and distinguish exhaustive Code8 checks from applicable wide-format equivalence/boundary tests; do not copy stale counts | verification strategy, evidence pages, installation/verification, add-operation guide |

Perform a repository-wide wording search before each review pass for at least:
`UInt8`, `Float64`, `256`, `2^K`, `table lookup`, `generated`, `Code8`,
`Code16`, `carrier`, `NaN`, `typemax`, `K ≤ 8`, and `byte`.  Each match should
be confirmed as either a deliberately Code8-local statement or rewritten to be
representation- and carrier-correct.

Also search for unqualified performance language (`fast`, `zero allocation`,
`constant time`, `single load`, `exhaustive`, `all formats`, `always`, and
`never`).  These words are useful only when their code path, scope, and evidence
are recorded in the claim ledger.  A phrase that is true for `Code8` must not
silently become a statement about all `Binary` values.

## Execution sequence and milestones

### Milestone A — inventory and information architecture

1. Make a page inventory with reader, purpose, owner, inbound/outbound links,
   stale implementation claims, and destination in the Page Ownership Map.
2. Draft the revised `pages.jl` hierarchy, index documentation map, and link
   map.  Do this before prose edits; it prevents every page from independently
   choosing a different navigation story.
3. Decide whether section landing pages are needed.  Add one only when it
   provides a real route/summary; do not add empty navigation pages.
4. Pass Gate 1 before changing page prose.

### Milestone B — semantic spine and everyday use

1. Rewrite `index.md`, installation, first session, and core model as a single
   contiguous reader route.
2. Rewrite the concept and workflow pages in the order implied by the ownership
   map.  Preserve recipe detail, but replace repeated theory with a short local
   reminder and a link to the canonical explanation.
3. Update the cheat sheet only after the public terminology and call examples
   are stable.
4. For every changed example, run it in the documentation environment or add a
   focused doctest/script that proves its result and displayed type.
5. Pass Gate 2 for this route before moving to another layer.

### Milestone C — reference, examples, and technical narrative

1. Align curated references, Julia compatibility, and docstring indexes with
   the final public terminology and source signatures.
2. Make the example gallery a reliable route into applied, verification, and
   performance evidence; re-run every example that reports values, code points,
   types, allocation, or timing.
3. Build the technical narrative from `internals_architecture.md` outward:
   codec → projection → oracle → tables/kernels → blocks → verification.
4. Rewrite maintenance pages last, after their underlying invariants and
   technical vocabulary have settled.

### Milestone D — audit, render, and release

1. Apply the implementation-difference audit while rewriting, then repeat it as
   a clean-room review using only the claim ledger and search results.
2. Update `docs/pages.jl`, `index.md`, page titles, and `See also` blocks in the
   same change set.  Keep links stable where practical; otherwise update every
   inbound link and verify its rendered target.
3. Pass Gates 3 and 4.  Fix source, not generated HTML, when a link or rendered
   structure is wrong.
4. Reconcile the final ledger, page inventory, and generated artifacts; remove
   only temporary review files, retaining the claim ledger if it is useful for
   future source changes.

## Risks and controls

| Risk | Control |
|---|---|
| ByteFloats prose is copied with byte-only assumptions | Require an open audit/ledger row before adapting any codec, order, table, carrier, or performance explanation. |
| A helpful simplification erases wide-format behavior | Include a `Code8` versus `Code16` example wherever representation changes observable behavior. |
| Detail survives but becomes hard to discover | Enforce the page-ownership map, section landing text, and one explicit next step per guide. |
| Concepts are explained inconsistently in several pages | Link to the semantic owner; allow only a one-paragraph local recap elsewhere. |
| Static REPL output or benchmark claims rot | Execute examples; tie measured claims to a script, environment, date, and source revision in the ledger. |
| Navigation works in Markdown but fails after rendering | Test both flat local URLs and CI pretty URLs, including fragments, against a fresh build directory. |
| PDF and HTML diverge | Build both from the same `docs/src`/`pages.jl` tree and validate the PDF as a release artifact when its toolchain is available. |

## Acceptance criteria

The work is complete only when all of the following are true:

- A newcomer can follow Home → first session → core model → a workflow without
  encountering unexplained implementation vocabulary.
- The Home, user route, examples, and technical route each have a recognisable
  narrative voice: a proposition, a small demonstration, an explanation of its
  consequence, and a purposeful next step rather than a sequence of inventories.
- Adjacent rewritten pages read as one manual.  They neither re-teach the same
  concept at full length nor abruptly change from reader-facing prose into a
  source-file tour without warning.
- A user can find format, conversion, projection, array, block, storage,
  conformance, and compatibility guidance from the documentation map.
- A maintainer can follow the technical-guide order from architecture through
  codec, projection, oracle, tables, verification, benchmarking, and extension.
- No page generalizes a ByteFloats-only fact (`UInt8`, universal Float64 decode,
  universal tuple decode, NaN-last ordering, or byte-only table policy) to
  SmallFloats.
- Code examples run in the current SmallFloats project and their displayed types
  and order semantics match source.
- The Documenter site builds with `DOCS_PDF=skip` into a fresh local build
  directory, and `docs/check_links.py` passes for both local flat URLs and CI
  pretty URLs.
- The full documentation build regenerates and validates the PDF when the PDF
  toolchain is available; inspect the rendered HTML/PDF rather than treating a
  Markdown-only review as completion.
- A final editorial read-through has checked the key routes as continuous prose,
  with particular attention to transitions, sentence rhythm, meaningful
  examples, and candid boundaries.

## Deliverables

The implementation of this plan should include the revised source pages and
navigation, updated runnable examples and references, a claim-audit checklist
or issue list recording each implementation-sensitive rewrite, and validated
HTML/PDF artifacts.  The plan deliberately does not prescribe deletion of the
existing SmallFloats detail; its success measure is a clearer path through that
detail and technically faithful prose at every implementation boundary.
