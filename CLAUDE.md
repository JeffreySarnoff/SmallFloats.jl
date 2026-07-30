# SmallFloats.jl — working doctrine

*Reconstituted 2026-07-29 during Stage 0 of the K ≤ 16 extension
([docs/other/implementextensions.md](docs/other/implementextensions.md) §1 C9):
the original doctrine file was not carried over by the rename from
`ByteFloats.jl`, so invariants 1–7 are restored from the statements in
`src/` and from [docs/other/extendingK.md §10](docs/other/extendingK.md).
Invariants 8–10 are new and belong to the extension.*

A conforming, performance-oriented implementation of the IEEE P3109 draft
standard. Bit-exact defined results on every default path; approximate fast
paths exist only behind the explicit κ registry, never substituted silently.

---

## Architectural invariants

These are review criteria. A change that breaks one is wrong even if the suite
is green — the suite is how they are checked, not what makes them true.

**1. One write path.** `project` — `ωRoundToPrecision → ωSaturate → ωEncode` —
is the only producer of a code point. `encode` creates the bits; nothing else
does. Every new carrier and every new operation enters through the engine.

**2. Code point vs value.** `Unsigned` is the one argument-type class meaning
*code point*, at every bitwidth and for every format; every other `Real` means
*value*. `T(0x08)` and `T(8.0)` are different things by design, and `T(8)` is
the value 8.0 — signedness of the integer type is what distinguishes them. A
code-point argument is range-checked against `2^K` regardless of its width. The
format's storage unit, `codeunit_type(T)` (`UInt8` for K ≤ 8, `UInt16` for
9 ≤ K ≤ 16), is the type `codepoint` returns and the type `rawvalue` — the
unchecked kernel route — requires; it is an implementation detail of the
*representation*, never of the *meaning*.

*`convert` is the deliberate exception and is value-preserving:
`Binary8p4se(0x02)` is code point 2, while `convert(Binary8p4se, 0x02)` is the
value 2.0. Promotion, `similar`, and `fill` depend on that.*

**3. Representation invariant.** The code point occupies the low `K` bits of
the storage unit; the high bits are maintained zero. Constructors check it;
`rawvalue` assumes it.

**4. Stochastic ρ is never tabulable.** A stochastic result is a distribution
over the random draw `R`, not a function of the operands. Table builders reject
it loudly rather than sampling one draw.

**5. Nothing approximate is reachable from the default API.** Approximate
kernels live in their own registry, retrieved only by explicit name. Every
declared κ is *verified by exhaustive enumeration at registration time*;
understated declarations are rejected. κ is a measured property, not a promise
— and where the input space is too large to enumerate, `measure_kappa` reports
`exhaustive = false` and the conformance report says so.

**6. A table entry IS the defined result.** Every entry comes from one trip
through the oracle-backed scalar path, so there is no residual correctness
reasoning at a use site. Declining to build a table means running that same
scalar path per element — never a different answer.

**7. Registry-driven codegen.** `OP_REGISTRY` is the single source from which
the spec register, the same-format convenience methods, the Base veneers, the
`Block*`/`Scaled*` variants, the table enumeration, the exhaustive test sets,
and `conformance()` are generated. No hand-written per-format or per-operation
variants anywhere — a variant that cannot be written unevenly cannot diverge.

**8. Format types are propagated, never rebuilt.** A method that received a
format type or a value uses *that* type; it never re-forms `Binary{K,P,S,E}`
from destructured parameters. Rebuilding yields the abstract format, which is
not a valid array element type and not a valid constructor target — and, in a
`Ref{Type{<:Binary}}`, it stores silently. `Binary{K` appearing in a method
**body** (as opposed to a signature) is a defect; grep enforces it.

**9. Policy is dispatch, never a branch.** The evaluation carrier, the storage
unit, the decode policy, the order-key type, and the table cache are singleton
tags or concrete types reached by dispatch. No code path computes one into a
variable and branches on it, and no trait returns a `Type` from a ternary.
Where the condition is a function of static parameters, put it behind a `Val`
and dispatch on that; where it coincides with the representation seam,
dispatch on `Code8`/`Code16` directly. Adding a format or an operation changes
which method is selected, never which branch is taken.

**10. No construct materializes `2^ΣK` elements without a byte budget.**
Constant-tuple tables are permitted only where the tuple length is bounded by
256 (selected by `decodepolicy`). Every `Memory`-backed table is allocated
through the one byte-budget policy in `tables.jl`, which returns `nothing`
rather than attempting an impossible allocation. Table index arithmetic runs in
`Int` and asserts `ΣK ≤ 48`.

---

## Layer order

`include` order is load-bearing and is stated in exactly one place — the
comment at the top of `src/SmallFloats.jl`. **Changing the order means changing
that comment in the same commit.**

```
formats → projspec → defaults → decode_encode → project → ops_scalar
        → juliacompat → oracle → tables → kernels → blocks → packed
        → approx → rand
```

(`fma128.jl` and `faa128.jl` are vendored `Float128` modules and load first.)

---

## Performance rules

- Format types enter through `const` bindings, type parameters, or function
  arguments. A **non-`const` global** format type forces dynamic dispatch on
  every call — measured at ~1 µs per scalar keyword call. That is Julia
  semantics, not package overhead; one function barrier
  (`f(::Type{T}, args...) where {T}`) restores full speed.
- Traits are pure functions of type parameters and must constant-fold. A trait
  that leaks a `Union` into a hot path costs the zero-allocation property.
- The table getter is `@noinline` and called **once per array call**, hoisted
  out of the loop. Loop bodies index a local `Memory` — no dict lookups, locks,
  or global loads per element.
- Warm scalar paths allocate zero. This is pinned as a deterministic
  regression, not asserted by timing.
- Cold, per-signature code (table builders, conformance reporting, κ
  measurement) is left to specialize. Do not reach for `@nospecialize` there —
  its whole value is specialization; compile latency is managed through the
  precompile workload's contents.

---

## Verification doctrine

The suite **enumerates rather than samples** wherever the input space allows
it — ≈ 8.9 M assertions today. Read precisely, that is a theorem with a
hypothesis (`K ≤ 8` ⇒ every specialization's input space is ≤ 2^24 points), so
under the K ≤ 16 extension it is restated rather than stretched: see
[docs/other/implementextensions.md §6](docs/other/implementextensions.md).
The rule that does not change: **where enumeration is affordable it is
mandatory, and where it is not, the output says "sampled" in so many words.**

Standing gates: G1 `_DE_*` thresholds · G2 `bigprec` sufficiency ·
G3 `_rtp_f64` bit ≡ generic · G4 rung-selection equivalence · G5 K ≤ 8 golden
non-regression · G6 carrier-lift exactness · G7 `HeadExact` carrier swap ·
G8 representation invariant at every K · G9 trait folding ·
G10 surface totality at every rung.

**G10 is the one gate that is broad rather than deep, and it exists because the
other nine are deep rather than broad.** Every one of them compares two answers,
so each is silent about a path that throws instead of answering and about a path
no test calls at all. Six Stage 7 defects lived in exactly that blind spot — a
`Class` that compared a `Dyadic` datum against a `Float64` literal, a
`_bp_element` annotated `::Float64`, a `Float16` conversion that was simply never
written — and all six survived a green suite. G10 asserts only that the call
returns and that a declared result type holds, over every registry operation on
every surface. A shallow gate earns its place by being total; do not deepen it,
and do not narrow it.

G5 runs in three tiers, selected by `ENV["SMALLFLOATS_G5"]`: **`fast`** (~1 min;
exhaustive over all 120 formats for everything a type refactor can move),
**`lazy`** (~4 min, **the default** and the routine stage-exit gate), **`full`**
(~11 min, required at the Stage 2 exit and at release — Stage 2 changes the type
of every value in the package, which is the one place a defect could be
format-specific rather than systematic).

G10 runs in two tiers, selected by `ENV["SMALLFLOATS_G10"]`: **`rep`** (~1 m 45 s,
**the default**) probes one representative of each realized
`(rung, P == 1?, code unit)` class plus all eight rung-3 formats; **`full`**
(~6 min, the stage-exit and release tier) probes all 72 formats above rung 1.
The block surface is enumerated by `(FS, FE)` *shape* at both tiers, and that is
exhaustive rather than sampled — `blockdecode`'s carrier is
`rung(Val(:Multiply), FS, FE)` and depends on the formats through nothing else.
G10's cost is ~99% specialization, not evaluation, so the format count is the
only lever there is.

A tier the caller asks for is **honoured, never downgraded**: a gate that
quietly runs less than it was told to is worse than no gate. G5's format list
stays `K ≤ KSPLIT` as the grid widens — the oracle's digests are statements
about the 120 formats that existed when it was captured, and widening the list
would invalidate every one of them rather than strengthen the gate.

Deterministic **specialization regressions** (concrete inferred return types at
the public entry points, zero warm-path allocation) stand in for timing
assertions.

`ENV["SmallFloats_Float128"] = "disable"` must produce **bit-identical**
results. Every `Float128` path fronts a complete MPFR path with identical
semantics; the switch trades speed only, never results.

JET: a new filter in the package analysis requires a **concrete-call gate**
proving the real path is clean. A filter without one hides a defect.

---

## Benchmark doctrine

Recorded after two measurement post-mortems: a benchmark closure over any
non-`const` global measures Julia's dispatch machinery, not the code under
test — and it distorts *ratios*, not just absolutes.

- Format types enter as type parameters, never as globals.
- Operands come from untimed setup.
- Reflectively retrieved functions pass through argument barriers to
  specialize.
- A preflight **aborts the run** if warm scalar paths allocate. Under the
  extension this is per-*operation class*, not per-head — the K ≤ 8 phrasing
  ("`HeadF64` and `HeadF128` are zero-allocation unconditionally") was measured
  false and was never a statement about the head. The **exact selections** are
  zero at every rung, unconditionally, and that is what the regression pins:
  they return an operand, so there is nothing for them to escalate into.
  **Arithmetic** allocates exactly when the operand spread exceeds the carrier's
  exact range and the evaluation escalates to MPFR — which happens at rung 1 too
  (a `Binary16p6se` add can span 1024 binades). The **enclosure ladder** allocates
  at rungs 2 and 3 by construction. See §11 M46 for the measured table; pinning
  arithmetic to zero would be pinning a falsehood.

Vary one binding per variant; verify specialization before believing a number.

---

## Deliberate limitations

No implicit cross-format arithmetic (promotion is to the format's promotion
carrier, explicitly). No in-place packed arithmetic. Threading is opt-in and
narrow. `Irrational`/`Rational` inputs to `Convert` are rejected rather than
double-rounded silently. Subtyping `Binary` is **not** a supported extension
point: package methods assume `codepoint`/`rawvalue` semantics and the
representation invariant, neither of which an outside subtype can be held to.

---

## Work in progress

The K ≤ 16 extension is staged in
[docs/other/implementextensions.md](docs/other/implementextensions.md) §4.
Read §1 (findings) before touching `formats.jl`, `oracle.jl`, or `defaults.jl`.


