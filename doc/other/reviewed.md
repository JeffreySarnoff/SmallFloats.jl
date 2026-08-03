# Review of SmallFloats.jl

## Scope

This is a static review of the package source, documentation, test design, and checked-in benchmark reports. Tests and benchmarks were deliberately not executed: the review accepts the stated fact that the tests pass and uses the published benchmark results as the performance evidence.

The review considers the package as a numerical library, a Julia interface, and a maintainable research implementation of IEEE P3109 draft arithmetic.

## Executive conclusion

SmallFloats.jl has an unusually strong numerical core. Its central contract—compute an exact mathematical result and project it exactly once—is clear, pervasive, and supported by a carefully layered implementation. The format representation, projection engine, oracle protocol, operation registry, table kernels, and block arithmetic are deep modules: each exposes a relatively compact interface while hiding substantial numerical machinery. This gives the implementation high leverage without scattering rounding policy across the package.

The common-format performance reported for the package is excellent, and the verification strategy is much more rigorous than is typical for a package at version 0.3.0. The principal weaknesses are not in the arithmetic design. They are contradictions between documented session controls and their implementation, several stale sources of package truth, an oversized and occasionally hazardous public interface, incomplete continuous integration and release hygiene, and benchmark coverage that does not yet substantiate the full K=3:16 design space.

My overall assessment is: technically impressive and credible as a research-grade numerical implementation, but not yet as operationally polished as its arithmetic core. The next release should preserve the core design and concentrate on making every public claim mechanically true, reducing state and interface ambiguity, and publishing reproducible evidence across all carrier rungs.

## Architecture and numerical design

The source has a coherent dependency direction. Format definitions and representation support the codec; the codec and exact carriers support projection; projection supports scalar operations; the operation registry supplies array, table, block, and scaled families. This structure has strong locality: a change to encoding, projection, or an operation family has an identifiable home.

The strongest architectural decisions are:

- `project` is the single semantic write path. Its sequence—round to precision, saturate, encode—makes double rounding and accidental host-float conversion easier to rule out.
- `ProjSpec` carries rounding and saturation policy in types. The compiler can specialize deterministic calls and remove stochastic machinery when it is unused.
- The oracle/result-kind protocol distinguishes exact, sticky, and enclosing results instead of forcing all operations through one approximate carrier.
- Tables are generated through the same scalar semantics as direct calls, while kernels have a fallback with the same contract. This is a high-leverage seam between semantic correctness and execution strategy.
- The operation registry generates scalar, array, block/scaled, export, and conformance surfaces from a common description. This reduces family-by-family drift.
- Cache construction accounts for result code-unit width and table size in bits, with locking and bounded ternary storage. The implementation treats table policy as an engineering constraint rather than assuming every finite domain should be materialized.
- The package deliberately avoids implicit promotion between formats. That is a defensible numerical choice: format conversion remains visible at the call site.

The large `oracle.jl` and `dyadic.jl` files are not inherently a design problem. They contain deep implementation rather than collections of unrelated shallow wrappers. Any future split should follow a real seam—such as exact arithmetic versus enclosure construction—not a file-size target.

## Correctness and verification

The verification design is a major strength. It includes independent `Rational`/`BigInt` references, differential checking between carrier rungs, golden digests, exhaustive and explicitly sampled roll-call axes, Aqua and JET checks, documentation examples, and interface consistency checks. The test documentation is unusually candid about axes that are sampled rather than exhaustive. Accepting the stated passing status, this is persuasive evidence for the implemented cases.

There are, however, important gaps between the passing suite and the live interface:

### Session RNG and stochastic-bit defaults are ineffective

`src/defaults.jl` stores `_DEFAULT_RNG` and `_DEFAULT_RBITS`, and their getters and setters are documented as session controls. Production stochastic calls do not consume them:

- `_resolve_rng` in `src/ops_scalar.jl` falls back to `Random.default_rng()`.
- RNG-free `rand` and `randn` methods in `src/rand.jl` also use `Random.default_rng()`.
- Stochastic projection constructors without an explicit bit count use the compile-time `DEFAULT_RBITS` constant.

The setters therefore appear to change state without changing arithmetic behavior. Existing checks establish that the stored values round-trip, but not that they affect stochastic operations. This is the most important interface/implementation defect found in the review.

### The conformance version is stale

`conformance()` constructs a package identification string containing `SmallFloats.jl 0.1.0`, while `Project.toml` declares version 0.3.0. A conformance report intended to be live truth must not duplicate version metadata manually.

### Rounding taxonomy has two sources of truth

The abstract hierarchy places `ToOdd` under `FaithfulRoundingMode`, but the legacy `RoundingModes_Directed` union includes `ToOdd`. The newer type hierarchy and older union classification disagree. Code should derive behavioral classification from one taxonomy.

### Draft identity is too weak

The implementation records a draft revision date, but a changing standards draft needs a precise identity: revision, document identifier, or content hash, plus an explicit inventory of interpretation decisions. A date alone is not sufficient to reproduce a conformance claim.

## Performance evidence

The checked-in full benchmark report was generated with Julia 1.12.6 on an Alder Lake target using one Julia thread. Its methodology is sound: setup is kept out of timed regions, runtime values inhibit constant folding, allocation counts are recorded, operand classes are separated, and cold table construction is distinguished from warm lookup.

For the measured formats, the results are strong:

| Operation | Reported median or representative result |
|---|---:|
| Decode | about 1.6 ns |
| `order_key` | about 1.6–1.8 ns |
| Deterministic projection | about 6.7 ns |
| Stochastic projection | about 7.1 ns |
| Safe scalar `Add` | about 9.0 ns |
| Safe scalar `Multiply` | about 7.4 ns |
| Safe scalar `Divide` | about 18.3 ns |
| Safe scalar `FMA` | about 9.6 ns |
| Unary table gather | about 0.13 ns/element |
| Binary table gather | about 0.26 ns/element |
| Ternary compute kernel | about 15.5 ns/element |
| Counting sort, 65,536 elements | about 157 us, versus about 1.37 ms for comparison sort |

The hot scalar paths report zero allocations. Warm table hits are also fast. This supports the package's claim that the typed rounding policy and exact semantics need not impose material overhead on common small formats.

The report also identifies the best optimization targets:

- Cold binary table construction incurs roughly 458,000 to 995,000 allocations in the reported cases.
- `BlockAdd` and `ConvertToBlockMaxAbsFinite` retain dozens to more than one hundred allocations.
- Packed-vector `vmap` is fast per element but reports 773 allocations, suggesting avoidable view or scratch-management overhead.

The evidence has limits. The format-sensitivity section covers formats with K at most 8 even though the implementation supports K through 16 and uses three carrier rungs. It therefore does not quantify wide-format scalar, kernel, block, compilation, or first-call behavior. The report also uses one thread and does not record a commit SHA and dirty-tree state. Differences between the fast and full reports for block dot product further show why environment and exact workload metadata matter.

## Public interface and usability

The README and goal-oriented documentation are excellent introductions. They explain the exact-project model, show the `===` identity trap, describe supported format families, and state important limitations. The `Formats` namespace is a useful response to the unavoidable breadth of 504 P3109 formats.

The top-level interface is nevertheless very large: format aliases, operation families, block/scaled variants, approximation controls, defaults, cache controls, and introspection are all readily visible. Some breadth is intrinsic, but a few exports expose implementation or invite misuse:

- `Binary` is exported although external subtyping is explicitly unsupported. It should be presented as a dispatch/query type, not an extension seam.
- `rawvalue` is public while also described as an unchecked kernel route. Unsigned construction means a code point, whereas signed integer construction means a numeric value. That distinction is powerful but easy to misuse.
- `DEFAULT_SHOW_STYLE` exposes a mutable `Ref` instead of a behavioral getter/setter interface.
- Process-global mutable defaults are awkward in concurrent or compositional code. The implementation's `with_default_*` functions are consumption combinators only, although parts of the documentation incorrectly described nonexistent scoped mutation/restore semantics.

The callable operation objects are a particularly good interface: they provide a typed, extensible common vocabulary without reducing operations to symbols. Future organization should build on them rather than introduce a weak symbol-based dispatcher.

## Documentation quality and drift

Documentation breadth is a strength, but several pages no longer agree with the implementation or each other:

- `internals_verification.md` says sampling is never necessary and cites about 8.9 million assertions, while the current roll-call documents sampled axes and newer material cites a substantially larger campaign.
- `test/README.md` reads as a historical, first-person review note and gives old check counts rather than serving as a current test guide.
- `concept_session_state.md` says there are six defaults but lists seven.
- `internals_oracle.md` points to the removed `src/dyadic3.jl`.
- The module performance note contains older scalar and projection timings than the current full benchmark report.
- The architecture map omits live `show.jl` and `carriers.jl` layers.

The documentation consistency check covers selected literals, but not these claims. Passing documentation checks therefore should not be interpreted as proof that all prose is current.

## Maintenance, dependencies, and release readiness

The runtime dependency set is small and appropriate. The code has extensive invariant commentary, and its type-driven structure makes important paths navigable. Some comments retain historical plan numbers and postmortem narrative; preserving that reasoning in design records while keeping source comments focused on the current contract would improve locality.

Repository and release hygiene lag behind the implementation:

- No GitHub Actions workflows are present.
- No release tags are present in the inspected repository state.
- The README says the package is unregistered.
- Hundreds of generated LaTeX/PDF build intermediates are tracked under `docs/pdf/build`, including logs, page images, minted output, and large compiler products.
- Julia compatibility is limited to 1.12. This may be a deliberate consequence of the implementation, but it narrows adoption and should be an explicit product decision.

The test tiers already described by the package are suitable for CI: a default pull-request gate, a slower scheduled/release gate, and documentation/conformance publication. The absence of automation is therefore a delivery gap rather than a missing verification design.

## Findings by priority

| Priority | Finding | Consequence |
|---|---|---|
| High | Configurable default RNG and stochastic-bit count are not consumed by stochastic operations | Public controls silently do nothing |
| High | `conformance()` reports package version 0.1.0 for a 0.3.0 package | Published conformance identity is false |
| High | No continuous integration despite a sophisticated tiered suite | Regressions are not automatically blocked on supported environments |
| Medium | Faithful/directed rounding hierarchy conflicts with a legacy union | Classification can diverge as dispatch evolves |
| Medium | Documentation contains stale counts, paths, timings, and state descriptions | Users cannot reliably distinguish current contract from history |
| Medium | Benchmark coverage omits representative K>8 carrier rungs and reproducibility metadata | Performance claims do not cover the full supported format space |
| Medium | Unchecked representation construction and mutable implementation state are public | Misuse and compatibility burden are more likely |
| Medium | Generated PDF build products are versioned | Repository weight and review noise grow without preserving source value |
| Low | Historical commentary is mixed into live implementation notes | Current invariants are harder to scan |
| Low | Julia 1.12-only compatibility and no tagged/registered release | Adoption is narrower than the technical maturity would otherwise support |

## Verdict

The package should not be redesigned from scratch. Its deepest modules—the exact carrier/oracle machinery, one-step projection, typed projection specification, registry, and table/kernel seam—are the right foundation. The improvement opportunity is to make the surrounding package as exact as its arithmetic: one source of truth for every public fact, no inert controls, reproducible evidence, clearer representation interfaces, and automated release gates.
