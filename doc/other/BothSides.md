# FloatBytes and IEEE P3109/D1 — The Best Case on Both Sides

*An adversarial standards-conformance analysis of the internal model described
in [`ModelTogether.md`](../FloatBytes/ModelTogether.md) and
[`ModelForUsers.md`](../FloatBytes/ModelForUsers.md), using
[`IEEE_D1.md`](../../docs/other/IEEE_D1.md) and its structural index
[`IEEE_D1.json`](../../docs/other/IEEE_D1.json) as the exclusive controlling
specification record.*

This is a legal-style argument about technical conformance. It is not an opinion
about copyright, patent, certification-mark, licensing, or other external legal
rights.

---

## 1. Question presented

Whether the FloatBytes internal model is a permissible and sufficiently faithful
implementation model for IEEE P3109/D1 when limited to P3109 formats with
`3 <= K <= 8`; and, separately, whether the model as presently documented is
enough to support a declaration that FloatBytes is a conforming implementation.

The two questions must not be collapsed:

1. **Architectural permissibility:** May a conforming implementation use
   `BoundCall`, typed evidence, `CodeRule`, prepared executors, lookup tables,
   fixed-limb accumulators, packed storage, and indexed entropy instead of
   literally implementing D1's auxiliary pseudocode?
2. **Conformance established:** Has the package actually shown that every
   specialization it supplies—and every specialization D1 requires it to
   supply—returns the D1-defined result for every possible operand value?

The supporting side has the stronger case on the first question. The challenging
side has the stronger case on the second until implementation and evidence exist.

---

## 2. Record and hierarchy of authority

### 2.1 Controlling record

For this analysis:

- [`IEEE_D1.md`](../../docs/other/IEEE_D1.md) controls substantive wording,
  definitions, formulas, ordered declarations, and normative force.
- [`IEEE_D1.json`](../../docs/other/IEEE_D1.json) controls the section inventory
  and source-line locations. It is an index of the Markdown specification, not a
  competing paraphrase.
- [`ModelTogether.md`](../FloatBytes/ModelTogether.md) and
  [`ModelForUsers.md`](../FloatBytes/ModelForUsers.md) are proposals and
  explanations. They cannot amend D1.

If a model statement conflicts with a D1 formula or ordered declaration, D1
prevails. If the model imposes an additional implementation guarantee without
changing D1 results, that addition is generally permissible but is not itself a
D1 requirement.

### 2.2 Normative force

[D1 §1.2](../../docs/other/IEEE_D1.md#12-word-usage) supplies its own rule of
construction:

- **shall** is mandatory and permits no deviation for conformance;
- **should** is recommended, not mandatory;
- **may** grants permission within the standard;
- **can** states possibility or capability.

The operative conformance rule is
[§4.6](../../docs/other/IEEE_D1.md#46-conformance-declarations): for every
operation specialization an implementation supplies, it **shall compute the same
result** as the defined specialization for **all possible operand values**. D1
permits any proof method, including direct computation.

The mandatory floor is separately stated in
[§4.5](../../docs/other/IEEE_D1.md#45-conforming-implementations). An
implementation cannot avoid those required specializations by describing its
operation catalogue as selective.

### 2.3 Normative text versus informative material

Sections 1–5 contain the operative definitions and requirements. Annexes A–H
are expressly marked informative. They can illuminate purpose and sensible
accuracy reporting, but cannot displace a contrary mandatory rule.

For example, Annex E recommends error bounds for approximate reductions. The
defined block reductions remain the exact operations specified in §5.3 unless an
implementation supplies a separately named and properly declared approximate
specialization under §4.4.

---

## 3. Undisputed propositions

The strongest arguments share the following starting points.

1. D1 defines formats for every integer `K > 2`, subject to its precision,
   signedness, and domain rules. A package may deliberately support only
   `3 <= K <= 8`, but it must not describe that subset as the entire universe of
   D1 formats.
2. A P3109 floating-point value is a code point associated with a format. The
   datum is the closed-extended-real value obtained by decoding it.
3. D1 generally defines numeric floating-result operations by decoding operands,
   applying ordered auxiliary declarations over closed extended reals, and
   projecting to the result format. Comparisons, predicates, metadata, and some
   direct code-point operations have other result paths.
4. Where D1 invokes Projection, it applies rounding, then saturation, then
   encoding. Those stages
   have observable interactions at subnormal and finite-range edges.
5. The first matching declaration in an ordered operation definition controls.
   Special-value rows cannot be treated as an unordered collection.
6. D1's auxiliary functions are specification devices. Under §4.7.1, a
   conforming implementation is not required to expose or literally implement
   them.
7. Approximate implementations are permitted only under §4.4's naming and
   declaration rules. An undeclared approximation is not a defined operation.
8. Storage layout, cache policy, thread count, SIMD width, and table strategy are
   not operation parameters in D1. Holding semantic operands and random input
   fixed, those choices cannot change a defined result.

---

# Part I — The strongest argument supporting the model

## 4. Statement of the supporting position

The FloatBytes model is not merely compatible with D1; its central separations
are unusually well fitted to D1's own distinction between defined behavior and
implementation method. D1 establishes a function from operation parameters and
operand code points—plus `N` and `R` for stochastic rounding—to result code
points. FloatBytes binds precisely those semantic facts, then permits execution
strategy to vary only behind byte-equivalence obligations.

The model should therefore be approved as a conformable architecture, subject
to completing the mandatory specialization matrix and the certificates it
already requires.

## 5. D1 regulates results, not internal machinery

The supporting side begins with D1's clearest implementation-freedom language.

[Section 4.1](../../docs/other/IEEE_D1.md#41-general) states that code-point
integer operations may be performed in any equivalent manner, explicitly naming
shifts and masks as examples. More broadly, it calls the operation definitions
"specifications of behavior." [Section
4.7.1](../../docs/other/IEEE_D1.md#471-general) then says that the auxiliary
operations used in those definitions are not themselves required of a
conforming implementation.

That text defeats an objection based solely on structural difference. D1 does
not require a runtime object representing the closed extended reals, a literal
call to `omegaDecode`, or separate functions named `omegaRoundToPrecision`,
`omegaSaturate`, and `omegaEncode`. It requires equivalent results.

`SemanticKernel`, integer evidence, lookup tables, and direct code laws are
therefore lawful in principle. The correct inquiry is byte equivalence, exactly
the inquiry made by the model's Assurance section.

## 6. BoundCall accurately models an operation specialization

D1 §2.1 defines an operation as a set of specializations parameterized by such
facts as format, projection specification, and constants such as block size.
D1 §4.3 gives every operation a parameter list, operands, result, and ordered
behavior.

The model's `BoundCall` captures:

- semantic revision;
- operation and arity;
- operand formats in order;
- result format;
- rounding and saturation;
- stochastic decision family, word width, and slot count;
- defined versus explicitly approximate meaning.

That is the right conceptual analogue of a D1 specialization. Conversely, the
model excludes array layout, CPU, cache state, threading, workspace, and reuse
from semantic identity. D1 does not list those as operation parameters.

The model's governing law—`BoundCall`, operand codes, and logical entropy words
determine bytes, while valid execution choices determine only cost—is thus a
direct implementation of D1's behavioral framing.

## 7. One-byte storage does not contradict a K-bit format

D1 defines bitwidth as the minimum number of bits required to encode a value and
defines code points as integers from `0` through `2^K - 1`. It does not require a
programming language to use a physically packed K-bit scalar object for every
calculation.

A byte-wide host carrier for `3 <= K <= 8` preserves every code point and its
format association. Requiring high bits above K to be zero is a valid canonical
storage invariant. Providing packed storage for memory-sensitive use further
preserves the standard's compact-format purpose without imposing bit extraction
on all scalar arithmetic.

The explicit `fromcode` constructor is likewise permissible. D1 distinguishes
code points from datums; naming the code-identity operation makes that distinction
harder to misuse.

## 8. Typed evidence is an equivalent method of real evaluation

D1 operations are behaviorally expressed through closed extended reals. That
does not require an implementation to approximate those reals with a host float.
For finite P3109 datums, exact dyadic integers, exact quotient/remainder records,
integer-root remainders, and rigorous enclosures are natural equivalent methods.

The model improves the original one-bit-tail thesis by asking a more exact
question: what evidence is sufficient for this particular projection policy?
That is more faithful to D1 than declaring a preferred carrier and hoping it is
wide enough.

Examples:

- deterministic addition may use a certified window that preserves every
  comparison needed by the named deterministic modes;
- stochastic addition retains enough residual information to decide D1's exact
  scaled predicate;
- division retains the divisor and remainder rather than an inexact quotient;
- square root retains the integer-root remainder;
- elementary functions refine directed enclosures until projection is uniquely
  determined.

Nothing in D1 privileges binary64, MPFR, or any other intermediate format. If
the evidence yields the same result code for every operand, §4.6 is satisfied.

## 9. CodeRule is valid partial evaluation of D1 projection

The strongest conceptual feature of the model is the split:

```text
exact evidence -> CodeRule -> resolve(R) -> result code
```

For deterministic modes, `CodeRule` is a fixed code. For stochastic modes, the
rule stores the exact decision threshold and the two possible projected codes.

This is not a new rounding rule. It curries D1's existing rule. In
[§4.7.4](../../docs/other/IEEE_D1.md#474-rounding-to-precision), each stochastic
variant defines `RoundAway` by a finite comparison involving the fractional
position `nu`, the declared bit count `N`, and an unsigned integer `R` with
`0 <= R < 2^N`. Once `nu` and the projection context are fixed, the result is a
threshold decision in `R`.

The model therefore may precompute that threshold without preselecting a random
result. A stochastic decision table stores the defined function of `R`; it does
not store one sampled answer.

The model also correctly moved indexed-versus-sequential entropy generation out
of semantic identity. D1 specifies the supplied integer `R` and expressly does
not specify random-bit quality. An indexed generator is an additional
reproducibility guarantee, not a change to D1, provided the same supplied `R`
produces the same D1 result.

Assigning a logical entropy slot even when a special or exact result ignores `R`
is similarly permissible. D1 fixes the result, not stateful generator
advancement between calls.

## 10. The model preserves projection order

D1 §4.7.3 defines projection in the order:

```text
RoundToPrecision -> Saturate -> Encode
```

The model's single-projection invariant and evidence-to-rule design can preserve
that order exactly. `CodeRule` is not necessarily the output of rounding alone;
it is the fully compiled result of the specified rounding, saturation, and
encoding for each possible `R` decision.

This is particularly valuable at overflow edges. The model requires a direct
law or table to agree with the complete semantic path, not merely with a
nearest-neighbor quantizer. Its domain-scoped certificate prevents a shortcut
proved for one saturation mode from leaking into another.

## 11. Ordered special rows remain authoritative

The model classifies code-point specials before finite evaluation and assigns
special-value behavior to the semantic kernel. That matches D1's use of
auxiliary operations to handle nonfinite values explicitly and immediately.

The closed operation catalogue can preserve D1 §4.3.2's first-match rule by
associating each operation family with one reviewed ordered row program. Tables
then compile those results; they do not reinterpret the rows.

Because each table entry is compared with the independent reference and the
full `defined_code` path, an incorrect row order is detectable over the finite
code lattice.

## 12. Exact reductions are a conservative reading of §5.3

D1 block reductions decode scale and elements, form the real sum or product,
and project once. D1 does not specify intermediate rounding for a defined block
reduction. Exact fixed-limb accumulation therefore implements the defined
operation more directly than a host-format sequential accumulator would.

For finite operands:

- exact multiplication produces the D1 real product;
- exact addition produces the D1 real sum;
- merging exact accumulator states changes grouping but not the real value;
- Projection is applied once to the final value.

The model's refusal to ship a restart-window reduction until its merge behavior
is proved is legally prudent. It avoids converting an optimization hypothesis
into a conformance premise.

Special values remain subject to the ordered `omegaMultiply` and `omegaAdd`
rules. The model already requires a certificate over specials and partitions
before claiming a reordered executor equivalent.

## 13. Defined and approximate operations are properly separated

D1 §4.4 requires an approximate implementation to:

- be identified as approximate under a different name;
- declare `kappa` for the operation specialization;
- treat NaN and infinity mismatch as specified;
- cover all finite-result operands, optionally through disjoint subsets;
- state `kappa` for each relevant specialization.

The model makes approximate and defined calls disjoint types and prevents
defined preparation from selecting an approximate adapter. Its certificate
records semantic and candidate digests, metric, special behavior, and whether
the claim is exhaustive, proved, or sampled.

That separation is stronger than a mutable "fast math" flag and closely tracks
D1's naming and declaration requirements. The model correctly states that a
sampled estimate cannot satisfy an exhaustive or proved claim.

## 14. Prepared execution strengthens the proof story

Prepared execution is not a D1 concept, but it supports conformance:

- all semantic facts are frozen before execution;
- table identity includes the semantic revision;
- adapter selection is cost-only;
- fallible rigorous work finishes before output mutation;
- thread and storage changes are compared in logical code order;
- certificates name exact domains instead of using a global `certified=true`.

D1 §4.6 allows conformance to be attested by direct computation. For
`K <= 8`, exhaustive tables and pair domains make that unusually practical.
The model's `CoverageDomain` prevents an enumeration over operand pairs from
being misdescribed as coverage of every operation, result format, policy, and
random word.

## 15. Limiting K does not defeat conformance

D1 §4.6 recognizes that an implementation supplies a subset of operation
specializations. D1 §4.5 establishes a mandatory core using
`Binary4p2sf`, `Binary8p4se`, and `Binary8p3se`, plus a nonempty selected set of
external formats. Every P3109 format in that mandatory core lies inside
`3 <= K <= 8`.

Accordingly, a package need not implement `K > 8` to be conforming, so long as
it:

- does not claim those formats;
- supplies the complete mandatory §4.5 matrix;
- reports the additional `K <= 8` specializations it actually supplies;
- returns the defined result for every supplied specialization.

Supporting all 120 legal P3109 formats in the selected K range exceeds the
minimum format set; it does not create a duty to implement every possible
operation specialization over them unless the package declares that support.

## 16. Supporting-side conclusion

The architecture should be upheld. D1's text expressly permits equivalent
implementation, and the model establishes a disciplined equivalence structure:

```text
D1 operation parameters
  -> BoundCall
  -> exact or rigorous evidence
  -> exact D1 projection rule
  -> cost-only prepared executor
  -> result code
```

The remaining obligations are implementation and proof obligations, not defects
in the model's legal theory.

---

# Part II — The strongest argument challenging the model

## 17. Statement of the challenging position

The model is an intelligent architecture, but it is not a conformance showing.
Its strongest phrases—"semantic authority," "exact," "complete," and
"exhaustive"—are promises about code that does not yet exist or proofs whose
domains remain incomplete. D1 §4.6 does not ask whether an architecture is
capable of producing the right answer. It requires that every supplied
specialization actually produce the same defined result for every operand.

The proper disposition is therefore to deny any present conformance declaration
without prejudice, require an explicit mandatory matrix, and treat every
shortcut as unadmitted until its exact D1 domain is proved.

## 18. A model document cannot attest implementation behavior

D1 allows any proof method, but it still requires proof of an implemented
mapping. `ModelTogether.md` defines proposed types, phases, errors, and gates. It
does not itself provide:

- executable operation definitions;
- complete tables;
- exhaustive result digests;
- proof certificates;
- an implemented conformance query;
- a release manifest of supplied specializations.

The model's internal invariants are valuable, but reciting the conformance rule
inside an architecture document is not attestation under §4.6. Until the
implementation and evidence exist, the most that can be said is "designed for
conformance."

## 19. The mandatory §4.5 floor is not yet made explicit enough

The model emphasizes a closed P3109 operation catalogue and broad `K <= 8`
coverage, but D1 conformance turns on a precise specialization matrix, not on
operation-name coverage.

Section 4.5 requires, among other things:

- `F4 = {Binary4p2sf}`;
- `F8 = {Binary8p4se, Binary8p3se}`;
- a **nonempty** implementation-selected
  `FX subset {binary32, binary16, BFloat16}`;
- all required conversions among the indicated sets;
- specified Negate, Abs, Recip, Add, Subtract, Multiply, FMA, FAA, extrema,
  comparisons, predicates, next operations, and format queries;
- ScaledAdd, ScaledSubtract, and ScaledMultiply using `Binary8p1uf` scale factors;
- the mandated policy `(NearestTiesToEven, SatNone)`.

The model's user guide discusses promotion to `Float64`. That is not a substitute
for selecting a nonempty D1 `FX`: binary64 is not among the three choices in
§4.5. Nor does ordinary Julia promotion establish the required P3109 `Convert`,
FMA, FAA, Recip, or scaled specializations.

D1 §3.2 also says the formats defined by the document shall use its `Binary`
naming scheme. `FloatByte{...}` may remain an internal Julia representation, but
the public aliases, specialization manifest, diagnostics, and conformance query
must identify standard formats by their D1 names such as `Binary8p4se`.

Before conformance is claimed, the model needs a normative conformance manifest
whose rows are generated directly from §4.5 and whose absence fails the release.

## 20. A closed operation catalogue can still omit required specializations

An operation identifier such as `Add` is not one specialization. Its operand
formats, result format, and projection specification are parameters. D1 §4.6
allows a subset beyond the mandatory floor, but every supplied tuple incurs the
all-operands exact-result obligation.

Thus statements such as "the full defined catalogue" are ambiguous and
potentially misleading. They may mean:

1. every operation name in D1 is known;
2. every operation family has some implementation;
3. every legal specialization over `K <= 8` is implemented;
4. every mandatory §4.5 specialization is implemented.

Those are different claims by orders of magnitude. A legal conformance report
must enumerate specializations, not merely names.

## 21. UInt8 CodeRule is not a universal D1 outcome

The model's deepest seam is expressed as
`defined_code(... )::UInt8`. That is well shaped for one projected P3109 result
when `K <= 8`, but D1's complete operation system has heterogeneous results:

- comparisons and predicates return Boolean values (§§4.12–4.13);
- `Class` returns an enumeration (§4.13.1);
- format-level and projection-specification operations return integers,
  enumerations, or format values (§§4.14–4.15);
- NextGreaterThan and NextLessThan return code points through direct ordered
  code arithmetic rather than `omegaProject` (§4.16);
- block conversions return a scale factor plus a sequence (§5.2);
- mandatory §4.5 specializations can return `binary16`, `BFloat16`, or
  `binary32`, whose encodings do not fit a P3109 `UInt8` result.

Accordingly, "every defined result is projected exactly once" is too broad.
The legally accurate rule is:

> Every result for which D1 specifies `omegaProject` is projected exactly once;
> every direct, Boolean, enumeration, metadata, external-format, or multi-result
> operation follows its own D1 result definition without an invented
> projection.

The internal model needs a broader outcome algebra, conceptually:

```text
DefinedOutcome = ProjectedCodeRule
               | DirectCode
               | ExternalCode
               | BooleanResult
               | EnumerationResult
               | IntegerResult
               | MultipleResults
```

This need not enlarge the ordinary user interface. It does mean that
`CodeRule -> UInt8` is one deep internal seam, not the universal semantic type
for the standard in its entirety.

## 22. The stochastic support claim is narrower than D1's formulas

D1 §4.7.4 defines stochastic variants using operation parameters `N` and `R`.
It states `0 <= R < 2^N`, but the controlling D1 text supplied here does not set
an upper limit of 60 on `N`.

The model adopts `N = 1:60` from the current implementation vocabulary. That is
permissible as a declared subset of optional stochastic specializations, but it
cannot be described as complete D1 stochastic support. The conformance manifest
must say exactly which `N` values and variants are supplied.

Moreover, `ThresholdCode` is correct only if its construction reproduces all
three D1 predicates:

- floor of `nu * 2^N` for StochasticA;
- floor of `nu * 2^(N+1)` and the odd `2R+1` term for StochasticB;
- nearest-ties-even integer rounding of `nu * 2^N` for StochasticC.

It must also preserve D1's special `CodeIsEven` rule when `P = 1`, the subnormal
definition of `Q`, and the subsequent saturation behavior. Calling every rule a
threshold does not prove those details.

The model's rule that every stochastic logical output owns one entropy word is
an added stream protocol. D1 says random bits are supplied for stochastic
rounding but does not regulate state advancement for a result whose early
special row ignores `R`. The added protocol is lawful only if presented as a
FloatBytes reproducibility guarantee, not as a D1 mandate.

## 23. The ordered definitions cannot be reduced to generic classification

D1 §4.3.2 makes first-match order controlling. Many operations distinguish
closely related nonfinite cases. For example, FMA has ordered NaN, zero-times-
infinity, conflicting-infinity, signed-infinity, and finite rows.

A generic "classify specials, then evaluate finite" design is not yet enough.
The semantic catalogue must preserve:

- each row's order;
- operand asymmetry;
- exact guard conditions;
- the result format's projection after the auxiliary result;
- the single-NaN and no-negative-zero model;
- each operation's exceptional differences, such as Divide by zero yielding
  NaN rather than infinity.

Generated row programs create another possible failure point: a catalogue can
drift from the source even when every executor agrees with that catalogue. The
independent reference must be separately transcribed from D1, and the operation
manifest must demonstrate that every D1 row is represented.

## 24. CodeRule must prove the complete Project composition

D1's result is not simply one of the two nearest finite codes. The defined
composition is:

```text
RoundToPrecision(P, B, mode)
  -> Saturate(min, max, saturation mode, rounding mode, signedness, domain)
  -> Encode(format)
```

Saturation can yield finite extrema, infinity, or NaN depending on direction,
domain, and signedness. Rounding precedes saturation, and D1 expressly notes the
observable consequence above maximum finite.

A `ThresholdCode(lower, upper, cutoff)` representation is admissible only if
"lower" and "upper" mean the final encoded results after all of those rows, not
merely adjacent pre-saturation values. The proof must include:

- normal/subnormal transition;
- zero/minimum-positive transition;
- maximum-finite overflow interval;
- unsigned negative results;
- finite versus extended domains;
- all three saturation modes;
- infinities and NaN;
- `P = 1` parity.

Until that proof exists, `CodeRule` is a promising intermediate representation,
not a conformance fact.

## 25. Window evidence remains conditional

The revised model correctly withdraws the claim that one 40-bit window decides
every stochastic mode. But even its narrower deterministic claim remains a
stage gate. The cited W1 scripts check nearest-ties-even and do not, by
themselves, establish every deterministic policy, every cross-format result
format, or every remaining FMA domain.

The phrase "exact evidence" must therefore be used carefully. A window plus
directional residue may be decision-sufficient without being an exact value.
Its certificate must name:

- operation family;
- operand and result formats;
- deterministic policies covered;
- saturation modes;
- special rows;
- exponent-gap and cancellation cases.

When the certificate does not cover a call, semantic compilation must use an
exact fixed-limb or rigorous fallback. It cannot infer coverage from the fact
that a narrower or wider-spread sample happened to pass.

## 26. Reordered reductions require a D1-specific proof

D1 §5 defines `reduce` as a left fold and defines block reductions through
ordered auxiliary `omegaAdd` and `omegaMultiply`, followed by one projection.
For finite real values, an exact merge tree has the same mathematical sum or
product. That establishes much, but not the entire operation domain.

The proof must also cover:

- decoded scale factors of zero, infinity, and NaN;
- element NaNs and infinities;
- products such as zero times infinity;
- mixtures of positive and negative infinity;
- the exact first-match behavior of the auxiliary operation;
- stochastic projection of the final result;
- arbitrary supported block size;
- block element order where a special rule could make order observable.

An exact finite accumulator is not itself a representation of NaN and signed
infinities. The reduction executor needs a separately proved special-state fold
whose merge is equivalent to D1's specified reduce order.

The model's partition-independent invariant is an additional promise. It may be
kept only after proving it does not alter the D1 result. Otherwise the executor
must preserve the specified logical fold or be declared approximate with
`kappa`.

## 27. Approximation certificates must satisfy D1's complete kappa rule

The model distinguishes sampled, proved, and exhaustive certificates, which is
good. The challenge is that a sampled estimate is not enough to declare the D1
`kappa` required by §4.4.

For each approximate specialization, the declaration must:

- cover every operand producing a finite defined result, either globally or by
  a covering union of disjoint subsets;
- use `kappa = NaN` if NaN classification ever mismatches;
- use `kappa = infinity` if infinity matching fails after NaNs match;
- require approximate finite outputs to remain in the result format's finite
  value set;
- count value steps exactly as D1 defines them;
- handle multiple results under D1's maximum rule;
- use a different operation name.

A sampled certificate may guide engineering or be reported as an estimate, but
cannot discharge those mandatory declarations. The model should make it
impossible to publish a D1 approximate conformance declaration from a sampled
certificate type.

## 28. Julia conveniences are not D1 operation declarations

Base operators, constructors, broadcasting, and promotion are useful adapters,
but they do not substitute for named D1 specializations.

Potential confusion includes:

- same-format `x + y` with an implicit result format versus D1's explicitly
  parameterized `Add<fx,fy,fr,rho>`;
- `Float64` promotion versus a required result in `binary32`, `binary16`, or
  `BFloat16`;
- Julia `min`, sorting, or `nextfloat` semantics versus D1's several extrema,
  NaN-first `TotalOrder`, and distinct NextGreaterThan/NextLessThan end rows;
- host negative zero and NaN payloads versus D1's one zero and one NaN.

The model wisely places explicit `apply` beneath conveniences, but conformance
tests and reports must target the D1 specialization names and parameters, not
infer coverage from Julia method presence.

## 29. Unsafe fabricated values narrow the safe claim

D1 operands are valid code points in the declared format. A K-bit P3109 value
cannot have nonzero bits above K. Julia `reinterpret` can fabricate such a byte
inside a byte-wide primitive type.

This does not by itself violate D1, because the fabricated value is outside the
defined operand set. But documentation must not claim that every inhabitant of
the Julia primitive type is a D1 floating-point value. Only values produced by
safe constructors or validated at the raw-byte ingress carry that guarantee.

The model now makes this trust distinction. The implementation must preserve it
at every array, packed-storage, artifact, and foreign-memory entrance.

## 30. The conformance query is only recommended, but still important

D1 §4.6 recommends a user-queryable declaration of supplied operation
specializations using string representations. Because FloatBytes intentionally
supports a rich subset rather than every D1 specialization, omitting that query
would make the support claim difficult to audit.

This is not a mandatory defect—the operative word is "recommended"—but it is a
strong practical reason to make the live conformance manifest part of the first
release rather than a later reporting feature.

## 31. Challenging-side conclusion

The architecture may proceed, but no conformance declaration should issue until
all of the following are true:

- the mandatory matrix is executable;
- a nonempty D1 external-format set is selected;
- each supplied specialization is enumerated;
- every defined specialization is attested over all operands;
- stochastic scope and predicates are exact;
- block reorderings are proved equivalent;
- approximate declarations satisfy the complete D1 `kappa` rule;
- all reports identify the exact semantic revision and coverage domain.

The burden belongs to the implementation making the claim. Architectural
intent does not shift it.

---

# Part III — Replies and disposition

## 32. Supporting side's reply

The challenge mostly identifies conditions the model already imposes. It does
not show that `CodeRule`, exact evidence, prepared execution, or fixed-limb
reduction are forbidden. To the contrary:

- the model expressly makes certificates domain-specific;
- sampled claims cannot authorize defined execution;
- stochastic windows require a separate W1-S proof;
- reductions start exact and mergeable;
- preflight prevents partial publication of inconclusive tables;
- executor selection is cost-only;
- conformance is derived from live catalogues and digests.

The missing mandatory matrix and external-format selection belong in the
implementation roadmap. They are curable omissions, not reasons to reject the
internal model.

The `UInt8` objection likewise narrows rather than defeats the model. The
supporting side can treat `CodeRule` as the deep seam for projected P3109
results, keep Boolean and metadata operations in Byte Domain, and add an
external/multiple-result outcome adapter. D1 itself uses different result kinds;
faithful internal plurality is preferable to forcing them through one byte.

## 33. Challenging side's reply

Calling an omission "curable" concedes that present conformance is not shown.
The model's correctness architecture is valuable only if release gates are tied
to D1's actual mandatory tuples and formulas. A system can have perfect internal
agreement among kernel, table, packed executor, and trace while all of them share
one mistranscribed special row.

The independent reference, mandatory matrix, and source-to-catalogue audit are
therefore conditions precedent, not later polish.

## 34. Neutral findings

### Finding 1 — Architectural permissibility

**For the model.** D1 is explicitly behavioral and permits equivalent methods.
Nothing in D1 requires its auxiliary operations to be present as runtime
functions. The model's types and execution phases are permissible.

### Finding 2 — Semantic/operational separation

**For the model.** The separation is faithful and useful. Operation, formats,
projection, and stochastic word parameters may determine bytes; storage and
scheduling may not.

### Finding 3 — CodeRule

**Conditionally for the model.** Currying D1's stochastic predicates into an
exact rule of `R` is valid. Admission requires proof of all rounding,
saturation, encoding, subnormal, parity, and special cases for the declared
domain.

### Finding 4 — Universal outcome claim

**For the challenge.** `CodeRule -> UInt8` is valid only for projected P3109
results in the selected K range. It cannot represent all mandatory external,
Boolean, enumeration, metadata, direct-code, or multiple-result operations. The
model requires a broader outcome algebra and a projection invariant scoped to
operations that D1 actually projects.

### Finding 5 — K restriction and byte carrier

**For the model.** `3 <= K <= 8` contains every mandatory P3109 format in §4.5,
and a byte carrier can hold each code point. The package must state that larger
D1 formats are unsupported and distinguish physical storage width from K.

### Finding 6 — Stochastic scope

**For the challenge.** D1 does not establish the model's `N <= 60` cap. That cap
must be declared as implementation scope, not attributed to D1. Indexed entropy
is an added reproducibility contract.

### Finding 7 — Reductions

**Conditionally for the model.** Exact fixed-limb finite accumulation is a
strong realization of the defined real reduction. Reordering and merging require
a separate proof over D1's nonfinite and ordered-row behavior.

### Finding 8 — Approximation

**For the model's structure, for the challenge on proof.** Defined and
approximate paths are correctly separated. Only a complete D1 `kappa`
declaration—not a sampled estimate—can support an approximate conformance claim.

### Finding 9 — Mandatory conformance floor

**For the challenge.** The current model documents do not enumerate or implement
the complete §4.5 matrix and do not select a nonempty `FX`. Float64 promotion is
not a substitute.

### Finding 10 — Present conformance status

**For the challenge.** A design document cannot prove all-operand behavior of an
unimplemented specialization.

## 35. Disposition

The motion to reject the FloatBytes internal model as inconsistent with D1 is
**denied**. The architecture is capable of conforming and, in several respects,
is unusually well designed to preserve and attest D1 behavior.

Any motion to declare FloatBytes presently conforming on the strength of the
model documents alone is **denied without prejudice**. Conformance may be
declared after the conditions in §36 are satisfied by executable evidence.

This split is not diplomatic compromise. It follows from two express D1 rules:

1. implementation method may vary when behavior is equivalent; and
2. every supplied specialization must actually return the defined result for
   every operand.

---

## 36. Conditions precedent to a defensible conformance declaration

### 36.1 Freeze the controlling revision

- Record the D1 document identity and digests of both ground-truth files.
- Put the semantic revision in every table, plan, artifact, certificate, error,
  and conformance report.
- Fail closed on a revision mismatch.

### 36.2 Generate the mandatory matrix directly from §4.5

- Include every required P3109 format and specialization.
- Select at least one of `binary32`, `binary16`, or `BFloat16` for `FX`.
- Include required external conversions and results.
- Include required scaled operations with `Binary8p1uf` scale factors.
- Pin `(NearestTiesToEven, SatNone)` for the mandatory rows.
- Use D1 §3.2 format names in the public conformance manifest and query.

### 36.3 Model every D1 result kind

- Scope `CodeRule` to projected P3109 floating results.
- Add typed outcomes for direct codes, external encodings, Booleans,
  enumerations, integers, format values, and multiple results.
- Apply the one-projection invariant only where the D1 operation definition
  invokes Projection.
- Ensure mandatory external results retain their full 16- or 32-bit encoding.

### 36.4 Publish the supplied-specialization manifest

For every supplied specialization, report:

- D1 operation name;
- all operation parameters;
- operand and result formats;
- projection specification;
- block size or stochastic `N` where applicable;
- defined or approximate status;
- semantic digest and evidence scope.

### 36.5 Preserve source order

- Represent every ordered pattern declaration.
- Audit source-to-catalogue completeness independently.
- Test overlapping special patterns specifically, not only random codes.

### 36.6 Prove Projection as a composition

- Verify RoundToPrecision, then Saturate, then Encode.
- Cover P=1 parity, subnormals, extrema, unsigned negatives, infinities, NaN,
  all declared rounding modes, and all declared saturation modes.
- For stochastic rules, exhaust or prove the exact D1 predicates for every
  declared variant and `N`.

### 36.7 Prove every executor against semantics and independent authority

- Compare code identity, never a numerical tolerance.
- Include tables, direct laws, dense, generic, packed, threaded, SIMD, and block
  executors over their precise domains.
- Prevent a certificate for one policy or layout from authorizing another.

### 36.8 Prove block and scaled operations separately

- Cover BlockDecode and BlockProject special scale rows.
- Cover exact reduce initialization (`0` for add, `1` for multiply).
- Cover dot-product product rows before addition.
- Prove any reordered merge equivalent to D1's defined fold for specials as well
  as finite reals.
- Project only where the D1 block definition projects.

### 36.9 Enforce D1 approximation declarations

- Use a distinct name.
- Compute or prove complete `kappa` coverage.
- Apply D1's NaN and infinity escalation rules.
- Reject sampled estimates as conformance bounds.
- Publish any additional error metric only in addition to, not instead of,
  `kappa`.

### 36.10 Distinguish valid code trust

- Safe construction validates `0 <= code < 2^K`.
- Foreign and packed bytes are validated once before trusted execution.
- Unsafe reinterpretation is documented outside the conformance interface.
- High bits above K never enter a defined operation.

### 36.11 Make conformance queryable

- Provide the §4.6-recommended specialization query.
- Generate it from the live manifest rather than copied documentation.
- Make unavailable, approximate, sampled, and exact/proved statuses distinct.

---

## 37. Issue matrix

| issue | D1 rule | model position | strongest result |
|:---|:---|:---|:---|
| alternative internal arithmetic | §§4.1, 4.7.1 | typed evidence and kernels | permitted if result-equivalent |
| byte-wide carrier for K<8 | §§2.1, 3.1 | canonical low-K code in UInt8 | permitted; K is encoding minimum, not mandatory host allocation |
| explicit code constructor | §§2.1, 3.1 | `fromcode` | permitted and clarifying |
| internal `FloatByte` name | §3.2 | byte-wide Julia representation | permissible internally; public conformance names must use D1 `Binary` scheme |
| one projection | §4.7.3 and operation definitions | evidence -> rule -> code | exactly once where D1 invokes Project; zero invented projections elsewhere |
| universal UInt8 result | §§4.12–4.16, 5.2; §4.5 | `defined_code::UInt8` | insufficient for complete D1 result kinds; add typed outcome algebra |
| stochastic decision tables | §4.7.4 | threshold rule resolved by R | permitted if exact for A/B/C predicate and declared N |
| `N <= 60` | §4.7.4 | supported implementation range | optional scope limit, not a D1 limit |
| indexed RNG | §4.7.4 notes/details | schedule-independent entropy adapter | additional guarantee; D1 specifies R, not its quality |
| deterministic result table | §§4.1, 4.6 | compiled semantics | permitted after all-entry equality |
| SIMD/threading/packing | §4.6 | cost-only adapters | permitted if logical bytes do not change |
| exact reduction merge | §5.3 | fixed-limb associative state | conditionally permitted; prove special-state equivalence |
| restart reduction | §§4.6, 5.3 | deferred adapter | not admitted without complete certificate |
| approximate execution | §4.4 | disjoint approximate call | structurally sound; complete kappa declaration still required |
| sampled certificate | §§4.4, 4.6 | estimate only | cannot establish defined or kappa conformance |
| Base operator convenience | operation-specific clauses | fixed same-format adapter | allowed, but not a substitute for D1 specialization surface |
| mandatory external formats | §4.5 | not yet selected in model | blocking condition for conformance |
| full operation catalogue | §§4.3–4.6 | closed metadata source | insufficient without specialization manifest |
| conformance query | §4.6 | live conformance record planned | recommended and strongly advisable |

---

## 38. Final statement

The best supporting argument is that FloatBytes adopts D1's actual legal form:
semantic behavior is fixed, implementation method is free, and every optimized
method is admitted only by exact equivalence. `CodeRule`, prepared execution,
and fixed-limb arithmetic are not evasions of the standard; they are ways to
make its finite functions explicit and testable.

The best opposing argument is that architecture and vocabulary cannot satisfy a
shall-clause. The package must still select its mandatory external format set,
implement the exact §4.5 specialization matrix, preserve every ordered row and
projection detail, delimit optional stochastic support, and attest every
supplied specialization over all operands. Until then, the model supports a
future conformance case but is not itself that case.

The sound final position is therefore:

> **The model is D1-permissible; conformance remains an evidence-dependent
> release property.**
