# Mnemonic constants for the `SGN` and `EXT` format parameters

*Status: design document, revision 2, written 2026-08-01 against the working
tree at `8dd74e5`. No code changed. Revision 1 proposed four exported
full-word constants (`SignedFormat`, `UnsignedFormat`, `FiniteFormat`,
`ExtendedFormat`); review found them longer than wanted, and this revision
replaces the spelling with a namespace of single letters — `Fmt.U`, `Fmt.S`,
`Fmt.F`, `Fmt.E` — while keeping revision 1's tag-type mechanics unchanged
underneath. Every load-bearing claim below was **run** in a scratch session
against Julia 1.12.6, not assumed; §6 lists what was measured.*

---

## 0. Verdict up front

Add one exported namespace module, `Fmt`, holding **four singleton constants**
over **two axis tag types**, and teach `format` to accept them:

```julia
format(8, 4, Fmt.S, Fmt.E) === Binary8p4se     # mnemonic spelling
format(8, 4, true,  true)  === Binary8p4se     # unchanged, still supported
format(8, 4, Fmt.S, true)  === Binary8p4se     # mixed forms too
```

| constant | axis | meaning | `Bool` value | format-name letter |
|---|---|---|---|---|
| `Fmt.U` | Signedness (`SGN`, Σ) | Unsigned | `false` | the `u` in `Binary8p4ue` |
| `Fmt.S` | Signedness (`SGN`, Σ) | Signed | `true` | the `s` in `Binary8p4se` |
| `Fmt.F` | Domain (`EXT`, Δ) | Finite | `false` | the `f` in `Binary8p4sf` |
| `Fmt.E` | Domain (`EXT`, Δ) | Extended | `true` | the `e` in `Binary8p4se` |

The letters are not an invention: they are exactly the suffix letters of the
draft §3.2 format names the package already generates
(`_formatname`, [`formats.jl:381`](../../src/formats.jl#L381) —
`S ? "s" : "u"`, `E ? "e" : "f"`). `format(8, 4, Fmt.S, Fmt.E)` reads as the
name `Binary8p4se` it constructs, capitalized.

Three properties, all preserved from revision 1:

- **`Bool` stays canonical and still works.** The type parameters of
  `Binary{K,P,SGN,EXT}` do not change; every trait keeps returning `Bool`;
  `format(K, P, true, true)` is untouched. The mnemonics exist only at the
  input boundary and lower to `Bool` before anything else sees them.
- **Axis safety.** `Fmt.S`/`Fmt.U` and `Fmt.E`/`Fmt.F` carry their axis in
  their *type*, so the transposition `format(8, 4, Fmt.E, Fmt.S)` is a
  `MethodError` — where the all-`Bool` spelling silently builds the
  transposed format whenever both parameters happen to be legal.
- **Zero cost.** The tags are zero-size isbits singletons; the delegation
  compiles away entirely (§6 shows the tags are absent from the generated
  code of a call that uses them). No hot path is touched at all.

This is the house pattern — singleton tags selected by dispatch, never a
branch on a runtime value (invariant 9; compare the rounding modes,
[`projspec.jl:9-23`](../../src/projspec.jl#L9)) — combined with the house's
existing opt-in-namespace precedent (`SmallFloats.Formats`,
[`SmallFloats.jl:132`](../../src/SmallFloats.jl#L132)).

---

## 1. The constraint, stated precisely

"Do not override or overload `Base.Signed`/`Base.Unsigned`" decomposes into
three distinct failure modes, and a design has to dodge all three:

1. **Type piracy / overload** — adding methods that mention only Base types.
   No candidate design does this; listed for completeness.
2. **Shadowing by definition** — `const Signed = …` inside `SmallFloats`
   would be legal and self-contained, but then `SmallFloats.Signed` and bare
   `Signed` denote different things in one codebase.
3. **Export collision** — `export Signed` is the actively breaking form:
   after `using SmallFloats`, every use of bare `Signed` — including the
   ubiquitous `x isa Signed` — fails with an ambiguity error at first use.

The namespace resolves all three *structurally* rather than by careful word
choice: the only exported binding is `Fmt`, a name Base does not use, and the
axis words (`Signedness`, `Domain`) plus the four letters live inside it,
reachable only qualified. Nothing named `Signed`, `Unsigned`, `Finite`, or
`Extended` is created anywhere, exported or not.

*(Also checked: the single letters would be unacceptable as exported names —
bare `U`, `S`, `E`, `F` would collide with half the ecosystem's type
variables. Inside a namespace they collide with nothing: `Fmt` does not
export them, and `using SmallFloats.Fmt` brings in only the binding `Fmt`
itself.)*

---

## 2. The design space

Six designs. `Σ` abbreviates Signedness, `Δ` Domain.

| design | call site | Base clash | swap-safe | length | verdict |
|---|---|---|---|---|---|
| A. bare `Bool` consts | `format(8,4,SIGNED,EXTENDED)` | `Signed` collides; `SIGNED` shouts | no | long | rejected |
| B. namespace of `Bool` consts | `format(8,4,Signedness.Signed,Domain.Extended)` | none (qualified) | **no** | longest | rejected: no axis identity, and the length problem at its worst |
| C. exported full-word singletons | `format(8,4,SignedFormat,ExtendedFormat)` | none | yes | long | revision 1's choice; rejected on length in review |
| D. `Symbol`s | `format(8,4,:signed,:extended)` | none | runtime-checked only | medium | rejected: stringly-typed, typos surface at runtime, no tab-completion of the closed set |
| E. `@enum` | `format(8,4,SignedFmt,ExtendedFmt)` | avoidable | yes | medium | rejected: no gain over tags, plus `Int`-backed machinery |
| F. **namespace of singleton tags** | `format(8,4,Fmt.S,Fmt.E)` | none | **yes** | **shortest** | **chosen** |

F is B's namespace carrying C's tag types instead of raw `Bool`s — it keeps
the swap protection that made revision 1 reject B, and the namespace both
solves C's length complaint and deletes its export-collision analysis (four
exported words shrink to one exported module name). The only property lost
relative to B is that the constants are no longer literally `Bool`s and so
cannot be written in `Binary{K,P,·,·}` type position; §7.1 explains why that
is a feature here, not a loss.

---

## 3. The design

### 3.1 The namespace and the tags

In `formats.jl`, immediately above `format`
([`formats.jl:399`](../../src/formats.jl#L399)):

```julia
# ---- mnemonic axis tags (docs/other/MneumonicUse.md)
#
# Input-boundary sugar over the Bool parameters, never a new value domain: the
# tags lower to Bool at the `format` boundary and nothing downstream sees them
# (§6 of the design doc shows the generated code with the tags erased).
#
# A namespace module rather than four exported words: the single exported
# binding is `Fmt`, so the axis vocabulary cannot collide with Base.Signed /
# Base.Unsigned or with anything else, and the call site reads as the format
# name it constructs — format(8, 4, Fmt.S, Fmt.E) ≙ Binary8p4se.
#
# Two tag TYPES, not one, so each letter carries its axis in its type and a
# swapped argument order is a MethodError rather than a wrong format — the
# mistake the all-Bool signature cannot catch.

"""
    Fmt

Namespace for the format-axis mnemonics accepted by [`format`](@ref):

| constant | axis | meaning | as `Bool` |
|---|---|---|---|
| `Fmt.U` | Signedness | Unsigned | `false` |
| `Fmt.S` | Signedness | Signed   | `true`  |
| `Fmt.F` | Domain     | Finite   | `false` |
| `Fmt.E` | Domain     | Extended | `true`  |

The letters are the draft §3.2 format-name suffix letters, capitalized:
`format(8, 4, Fmt.S, Fmt.E) === Binary8p4se`. `Bool(tag)` recovers the raw
parameter. The axis types are `Fmt.Signedness` and `Fmt.Domain`, for generic
signatures. `Fmt` exports nothing; all access is qualified.
"""
module Fmt

"""
    Fmt.Signedness{Σ}

Axis tag for the `SGN` parameter of `Binary{K,P,SGN,EXT}`; instances
`Fmt.U` (`Σ = false`) and `Fmt.S` (`Σ = true`)."""
struct Signedness{Σ}
    Signedness{Σ}() where {Σ} = (Σ isa Bool || throw(ArgumentError(
        "Fmt.Signedness parameter must be Bool")); new{Σ}())
end

"""
    Fmt.Domain{Δ}

Axis tag for the `EXT` parameter of `Binary{K,P,SGN,EXT}`; instances
`Fmt.F` (`Δ = false`) and `Fmt.E` (`Δ = true`)."""
struct Domain{Δ}
    Domain{Δ}() where {Δ} = (Δ isa Bool || throw(ArgumentError(
        "Fmt.Domain parameter must be Bool")); new{Δ}())
end

"P3109 Signedness `Unsigned`: no sign bit; the `u` in `Binary8p4ue`."
const U = Signedness{false}()
"P3109 Signedness `Signed`: a sign bit; the `s` in `Binary8p4se`."
const S = Signedness{true}()
"P3109 Domain `Finite`: no infinities in the datum set; the `f` in `Binary8p4sf`."
const F = Domain{false}()
"P3109 Domain `Extended`: ±∞ (or +∞ if unsigned) in the datum set; the `e` in `Binary8p4se`."
const E = Domain{true}()

# `Bool` is how the tags lower at the API boundary. These are methods on a
# Base function whose signatures mention Fmt types — the ordinary extension
# pattern, not piracy (§1 mode 1).
Base.Bool(::Signedness{Σ}) where {Σ} = Σ
Base.Bool(::Domain{Δ})     where {Δ} = Δ

# Print as the qualified constant, not as `Signedness{true}()`.
Base.show(io::IO, ::Signedness{Σ}) where {Σ} = print(io, Σ ? "Fmt.S" : "Fmt.U")
Base.show(io::IO, ::Domain{Δ})     where {Δ} = print(io, Δ ? "Fmt.E" : "Fmt.F")

end # module Fmt
```

### 3.2 The `format` methods

Three delegating methods beside the existing canonical one
([`formats.jl:410`](../../src/formats.jl#L410)), which is unchanged:

```julia
# Mnemonic and mixed spellings, all lowering to the canonical Bool method.
# Mixed forms exist because generic code often holds one axis as a Bool from a
# trait (`issigned(T)`) while naming the other; forcing all-or-nothing would
# push callers back to hand-converting, which is where the swap comes back.
format(K::Int, P::Int, s::Fmt.Signedness, d::Fmt.Domain) =
    format(K, P, Bool(s), Bool(d))
format(K::Int, P::Int, s::Fmt.Signedness, E::Bool) = format(K, P, Bool(s), E)
format(K::Int, P::Int, S::Bool, d::Fmt.Domain)     = format(K, P, S, Bool(d))
```

### 3.3 Export

One name, in the Group M export block beside `format`
([`SmallFloats.jl:143`](../../src/SmallFloats.jl#L143)):

```julia
export Fmt
```

---

## 4. Algorithmic content: one bijection, stated once

The entire semantic payload is the bijection between the axis letters and the
`Bool` parameters, and it is the *same* bijection `_formatname` already
encodes in the letter-producing direction
([`formats.jl:381`](../../src/formats.jl#L381)):

```
_formatname:  (S::Bool, E::Bool)  ↦  letters   (S ? 's' : 'u', E ? 'e' : 'f')
Fmt:          letters             ↦  Bool      U ↦ false, S ↦ true, F ↦ false, E ↦ true
```

so for every format the round trip is an identity:
`format(K, P, Fmt-letters-of(name)) === format(K, P, issigned(T), isextended(T)) === T`.
That identity over **all 504 formats** is the core test (§8). There is no
other algorithm here — deliberately. The mnemonics add no representation, no
state, and no decision procedure; they are a spelling of two booleans.

---

## 5. Julia mechanics, in full

Each mechanism the design leans on, and why it behaves as claimed:

1. **Module as namespace.** `Fmt.U` is resolved at lowering time to a
   `GlobalRef` of a `const` binding; the compiler treats it as the constant
   singleton value itself. There is no dictionary lookup and no dynamic
   `getproperty` call at runtime for a `const` module binding — the reference
   folds during inference, the same mechanism that makes `Base.pi` free.
2. **Zero-size singleton tags.** `Signedness{Σ}` has no fields; each concrete
   instantiation is a singleton with `sizeof == 0` and `isbits == true`
   (verified). Passing one is passing nothing at all after specialization —
   it selects a method and vanishes.
3. **Value type parameters.** `Σ` is a `Bool` *value* used as a type
   parameter, the same device `Binary{K,P,SGN,EXT}` itself uses. `Bool(tag)`
   returns the parameter — a compile-time constant per concrete tag type, so
   it folds to a literal (`ret i8 1`, verified).
4. **Inner-constructor validation.** `Fmt.Signedness{1}()` throws
   `ArgumentError` (verified) — the same guard style `checkformat` applies to
   the `Binary` parameters and `StochasticA{N}` applies to `N`
   ([`projspec.jl:33-36`](../../src/projspec.jl#L33)). The tag types can
   therefore only ever be inhabited at `Bool` parameters, which is what makes
   `Bool(tag)`'s inferred return type concrete (`@inferred` passes,
   verified).
5. **Dispatch tiling, no ambiguity.** The four `format` methods partition the
   `(Σ-slot, Δ-slot)` argument space as
   `{Bool, Fmt.Signedness} × {Bool, Fmt.Domain}` — four disjoint cells, one
   method each. `Test.detect_ambiguities` over the defining module is empty
   (verified); the Aqua gate in `test/quality.jl` re-checks this on every
   run. The transposed call `(Fmt.Domain, Fmt.Signedness)` lies in no cell:
   `MethodError` (verified).
6. **Extending `Base.Bool` and `Base.show` from inside `Fmt`.** Both methods
   mention an `Fmt`-owned type in their signature, so this is the ordinary
   non-piratical extension pattern; Aqua's piracy check stays green by
   construction.
7. **`using SmallFloats.Fmt` is harmless.** `Fmt` exports nothing, so that
   statement brings in only the binding `Fmt` — the letters never enter a
   caller's namespace unqualified. There is no spelling under which `U`, `S`,
   `E`, `F`, `Signedness`, or `Domain` leak.

---

## 6. Performance: measured, and why there is nothing left to measure

The doctrine's benchmark rules make one demand here: the mnemonics must not
cost anything anywhere, because `format` sits beside paths that are pinned
zero-allocation. Three measured facts close the question (scratch session,
Julia 1.12.6, the §3 code verbatim):

1. **`Bool(Fmt.S)` compiles to `ret i8 1`.** The lowering is a constant
   return; there is no branch, no load, no call.
2. **The tags are erased from callers.** For a wrapper
   `g() = format′(8, 4, Fmt.S, Fmt.E)` the generated LLVM of `g` contains no
   reference to `Signedness` or `Domain` at all (string-searched the
   `code_llvm` output; verified) — after inlining, the tag path IS the Bool
   path.
3. **`@inferred Bool(Fmt.S)` passes** — a concrete inferred return type, the
   same specialization regression the suite already pins for the public
   entry points.

And structurally, three reasons no throughput number can move:

- **The hot paths never see the tags.** Type parameters stay `Bool`; traits
  (`issigned`, `isextended`, `SignednessOf`, `DomainOf`,
  [`formats.jl:298-315`](../../src/formats.jl#L298)) keep returning `Bool`,
  preserving gate G9's constant-folding property; no kernel, table, decode,
  or projection signature changes. The tags exist in exactly four `format`
  methods and nowhere else.
- **`format` is documented reflection.** Its own docstring: "deliberately a
  `Dict` lookup: this path is reflection, it is not performance-sensitive."
  The static zero-cost routes — the aliases and `reptype` — are untouched,
  and the guidance to prefer them where the parameters are static is
  unchanged.
- **No new `Union` anywhere.** The performance rules forbid traits leaking
  `Union`s into hot paths; the delegating methods take concrete tag types,
  not `Union{Bool, Fmt.Signedness}` arguments, precisely so every method has
  concrete argument types and specializes independently. (This is also why
  §3.2 spells three methods rather than one `Union`-typed method.)

Compile-time cost: two tiny types, four singletons, seven one-line methods.
Nothing warrants a precompile-workload entry; `format` itself is not in the
workload today.

---

## 7. Hazards, named and guarded

### 7.1 Type-parameter position

`Binary{8, 4, Fmt.S, Fmt.E}` is *spellable* — isbits singleton instances are
legal type parameters — and denotes a different abstract type than
`Binary{8, 4, true, true}` (verified). This is not new exposure:
`Binary{8, 4, :signed, 1}` has the same property today. The existing guard
catches it at first concrete use — `checkformat` rejects any non-`Bool`
`SGN`/`EXT` ([`formats.jl:100-102`](../../src/formats.jl#L100)) when a
`Code8`/`Code16` is constructed — and invariant 8 already brands hand-spelled
`Binary{…}` in method bodies a defect, with `format(K,P,Σ,Δ)` as the
advertised route. The `format` docstring gains one sentence: *the mnemonics
are argument values, not type parameters.*

Losing type-position use relative to raw-`Bool` constants is deliberate: a
constant that worked there would have to *be* a `Bool`, which is exactly what
forfeits swap safety (§2, design B).

### 7.2 The name `Fmt` itself

One exported binding. Base exports no `Fmt`; the package has no existing
`Fmt` binding (grepped at `8dd74e5`); it does not collide with the exported
*function* `format` or the `Formats` namespace module — three distinct names.
Collision with third-party packages is possible in principle for any exported
name; a one-word module used qualified everywhere is the smallest imaginable
surface, and a user who does hit a collision writes `SmallFloats.Fmt.S`.

### 7.3 Mistyped letters

`Fmt.X` is an `UndefVarError` naming `Fmt` at first use — a loud, early,
correctly-located failure. Compare design D, where `:signd` is a runtime
value error only if validation catches it.

---

## 8. Implementation and verification plan

1. §3.1 module + §3.2 methods in `formats.jl` above `format`; §3.3 export;
   one-sentence additions to the `format` and `Binary` docstrings
   ([`formats.jl:22-23`](../../src/formats.jl#L22)) beside the existing
   `Bool` encoding note.
2. Tests, formats section of the suite — **enumerated, not sampled** (the
   grid is 504 formats; the sweep is trivial):

   ```julia
   @testset "Fmt mnemonics ≡ Bool parameters, whole grid" begin
       for T in values(SmallFloats._NAMED)
           K, P = bitwidth(T), PrecisionOf(T)
           Σ, Δ = issigned(T), isextended(T)
           s = Σ ? Fmt.S : Fmt.U
           d = Δ ? Fmt.E : Fmt.F
           @test format(K, P, s, d) === T === format(K, P, Σ, Δ)
           @test format(K, P, s, Δ) === T            # mixed forms
           @test format(K, P, Σ, d) === T
       end
       @test_throws MethodError format(8, 4, Fmt.E, Fmt.S)    # swap refused
       @test Bool(Fmt.S) && !Bool(Fmt.U) && Bool(Fmt.E) && !Bool(Fmt.F)
       @test @inferred(Bool(Fmt.S)) === true                  # G9-style folding
       @test repr(Fmt.S) == "Fmt.S" && repr(Fmt.F) == "Fmt.F"
       @test_throws ArgumentError Fmt.Signedness{1}()         # tag guard
       @test sizeof(Fmt.S) == 0 && isbits(Fmt.S)
   end
   ```

3. Aqua (ambiguities, piracy, undefined exports) runs in the suite and gates
   the §5 claims mechanically.
4. Docs: one example beside the `Bool` spelling in the README/format docs so
   the letters are discoverable without reading this file.

---

## 9. Naming record

`Fmt.U`/`Fmt.S`/`Fmt.F`/`Fmt.E` were chosen because the letters are already
the package's own vocabulary — the draft §3.2 format-name suffixes every user
reads in `Binary8p4se` — so the mnemonic is learned once, not twice. The axis
types are `Fmt.Signedness` and `Fmt.Domain`: inside the namespace the natural
words are safe (nothing is exported, so they can never collide with
`Base.Signed`/`Base.Unsigned` or shadow anything), which is what revision 1's
exported spellings `FormatSignedness`/`FormatDomain` were contorting to
avoid. The existing trait aliases `SignednessOf`/`DomainOf`
([`formats.jl:314-315`](../../src/formats.jl#L314)) stay as they are.

Revision 1's four exported full words are recorded in §2 as design C:
correct, clash-free, and rejected purely on length. If a future reader wants
self-describing constants back, C is the fallback — its analysis in this
file's git history remains valid.
