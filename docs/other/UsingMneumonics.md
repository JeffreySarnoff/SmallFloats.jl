# Mnemonics for `Binary` signedness and domain parameters

*Design recommendation for making `Binary{K,P,SGN,EXT}` declarations readable
without changing the format lattice or colliding with Julia's integer types.*

> **Status:** proposed, not implemented. The filename retains the requested
> `Mneumonics` spelling; this document uses the standard spelling *mnemonics*.

## Decision

Add two small public namespaces containing qualified Boolean constants:

| P3109 axis | Mnemonic | Canonical value |
|---|---|---:|
| Signedness | `Signedness.Unsigned` | `false` |
| Signedness | `Signedness.Signed` | `true` |
| Domain | `Domain.Finite` | `false` |
| Domain | `Domain.Extended` | `true` |

Then both of these declarations denote the same format:

```julia
Binary{8,4,Signedness.Signed,Domain.Extended}
Binary{8,4,true,true}
```

More strongly, they are the same Julia type object:

```julia
Binary{8,4,Signedness.Signed,Domain.Extended} ===
    Binary{8,4,true,true}                              # true
```

The namespaces, rather than their members, should be exported by
`SmallFloats`. The four members should be public but deliberately qualified.
Consequently `using SmallFloats` introduces `Signedness` and `Domain`, but does
not introduce bindings named `Signed` or `Unsigned` into the caller's scope.

This is the recommended complete change. Symbols, enums, singleton marker
types, macros, and new `Binary` constructors are unnecessary.

## 1. Requirements and invariants

The change should satisfy all of the following:

1. Existing Boolean spellings remain supported permanently.
2. Mnemonic and Boolean spellings produce identical `Binary`, `Code8`, and
   `Code16` types—not merely equivalent types.
3. `SGN` and `EXT` remain `Bool` in every instantiated format.
4. The 504-format registry, generated aliases, dispatch, caches, and compiled
   specialization identities do not change.
5. `Base.Signed` and `Base.Unsigned` remain the abstract integer types and are
   neither replaced nor extended.
6. Static declarations and the runtime `format` function use the same
   vocabulary.
7. The mnemonic spelling has no lookup, allocation, initialization, or runtime
   normalization cost.

These requirements place the seam at the format-parameter interface. A caller
gets meaningful names; everything behind the seam continues to receive the
same two Boolean values it receives today.

## 2. Why Boolean constants are the correct representation

Julia permits immutable values such as `Bool` and `Symbol` as type parameters,
but it does not provide a hook that can normalize parameters while applying a
parametric type. For example:

```julia
Binary{8,4,:signed,:extended}
```

is a different parameterization from `Binary{8,4,true,true}`. A constructor
cannot repair this distinction: type application has already happened before a
datum constructor is called. The same problem applies to enum members and
singleton marker values.

A constant whose value is literally `true` or `false` has no such problem:

```julia
const mnemonic = true
Tuple{mnemonic} === Tuple{true}       # true
```

Julia substitutes the value of the constant as the type parameter. There is no
wrapper to normalize and no second family of types. Reflection also remains
honest:

```julia
Binary{8,4,Signedness.Signed,Domain.Extended}.parameters[3] === true
Binary{8,4,Signedness.Signed,Domain.Extended}.parameters[4] === true
```

This gives the caller readability while preserving implementation locality:
`checkformat`, `_NAMED`, `_formatname`, `reptype`, `issigned`, `isextended`, and
all methods parameterized by `S` and `E` remain unchanged.

## 3. Public interface

The preferred static spelling is:

```julia
using SmallFloats

F = Binary{8,4,Signedness.Signed,Domain.Extended}
U = Binary{8,4,Signedness.Unsigned,Domain.Finite}
```

The same constants work with the existing runtime format selector because they
already are `Bool`:

```julia
F = format(8, 4, Signedness.Signed, Domain.Extended)
F === Binary8p4se                                      # true
```

The qualified form is intentional. It makes the meaning of both axes visible,
and it prevents the P3109 names from competing with unrelated names in the
caller's module:

```julia
Signedness.Signed       # P3109 Boolean parameter value
Signed                  # Base.Signed abstract integer type

Signedness.Unsigned     # P3109 Boolean parameter value
Unsigned                # Base.Unsigned abstract integer type
```

Named format aliases remain the shortest spelling when one exists at the call
site:

```julia
Binary8p4se
```

The mnemonics primarily improve programmatic declarations, generated code,
format-family definitions, and explanations where the four parameters need to
be shown explicitly.

## 4. Implementation

### 4.1 Define two dependency-free namespaces

Place the definitions near `KMIN`, `KMAX`, and `KSPLIT` at the start of
`src/formats.jl`, before the `Binary` declaration:

```julia
"""
    Signedness

Mnemonic Boolean values for the `SGN` parameter of `Binary`:
`Signedness.Unsigned === false` and `Signedness.Signed === true`.
The members are qualified so they do not conflict with `Base.Unsigned` and
`Base.Signed`.
"""
baremodule Signedness
    public Unsigned, Signed

    "Unsigned P3109 format (`SGN == false`)."
    const Unsigned = false

    "Signed P3109 format (`SGN == true`)."
    const Signed = true
end

"""
    Domain

Mnemonic Boolean values for the `EXT` parameter of `Binary`:
`Domain.Finite === false` and `Domain.Extended === true`.
"""
baremodule Domain
    public Finite, Extended

    "Finite P3109 domain (`EXT == false`)."
    const Finite = false

    "Extended P3109 domain (`EXT == true`)."
    const Extended = true
end
```

`baremodule` is appropriate because these namespaces are only vocabulary. They
need `Core` syntax but no implicit `Base` imports. It also makes their lack of
implementation dependencies explicit. The package requires Julia 1.12, so the
`public` declaration is available.

The members are marked public for documentation and compatibility purposes but
are not exported from their namespaces. A caller should qualify them even if
explicit import syntax could technically bypass that convention.

### 4.2 Export only the namespaces

Change the format export in `src/SmallFloats.jl` from:

```julia
export Binary
```

to:

```julia
export Binary, Signedness, Domain
```

Do not export `Signed`, `Unsigned`, `Finite`, or `Extended` from
`SmallFloats`. In particular, do not import or extend `Base.Signed` or
`Base.Unsigned`; the mnemonic values are ordinary constants reached through
different, qualified bindings.

### 4.3 Update the existing format documentation

Revise the `Binary` docstring to describe both spellings:

```julia
Binary{K,P,SGN,EXT}

SGN is `false`/`Signedness.Unsigned` or
`true`/`Signedness.Signed`. EXT is `false`/`Domain.Finite` or
`true`/`Domain.Extended`.
```

Prefer mnemonic spellings in explanatory examples. Retain selected Boolean
examples wherever the representation invariant itself is being discussed.
This distinction teaches both the public vocabulary and the underlying fact
that the canonical parameters remain `Bool`.

### 4.4 Make no normalization changes

The following should not change:

```julia
function checkformat(K, P, SGN, EXT)
    (K isa Int && P isa Int && SGN isa Bool && EXT isa Bool) || ...
    # ...
end

function format(K::Int, P::Int, S::Bool, E::Bool)
    # ...
end
```

Keeping these signatures Boolean-only protects the canonical representation.
The mnemonic constants already satisfy them, so an adapter or parsing layer
would add interface and error modes without adding capability.

## 5. Collision analysis

The unsafe design is:

```julia
export Signed, Unsigned
```

Those names already denote `Base.Signed` and `Base.Unsigned` in an ordinary
Julia session. Exporting competing bindings would create import conflicts for
`using SmallFloats`; attempting to reuse the Base bindings would be worse,
because they are abstract types rather than the required Boolean parameter
values.

The recommended design avoids both problems:

- `SmallFloats.Signedness.Signed` and `Base.Signed` are distinct qualified
  bindings.
- `using SmallFloats` exports only the namespace `Signedness`, not its member
  `Signed`.
- No method is added to a Base type or function.
- No binding in `Base` is assigned, replaced, or overloaded.

Qualification is therefore part of the interface invariant, not incidental
verbosity.

## 6. Alternatives considered

### 6.1 Top-level renamed constants

For example:

```julia
const SignedFormat = true
const UnsignedFormat = false
const ExtendedDomain = true
const FiniteDomain = false
```

This preserves type identity and is technically sound. It is not preferred
because it adds four generic names to every `using SmallFloats` caller and
encodes the two conceptual axes less cleanly than `Signedness.Signed` and
`Domain.Extended`.

Uppercase spellings such as `SIGNED` and `EXTENDED` avoid the exact Base
collision but retain the namespace-pollution problem and do not explain which
axis each value belongs to.

### 6.2 Symbols

Symbols are attractive for runtime configuration:

```julia
format(8, 4, :signed, :extended)
```

They are wrong for the stated goal because the corresponding direct type
spelling creates a noncanonical parameterization:

```julia
Binary{8,4,:signed,:extended}   # not Binary{8,4,true,true}
```

One could add a separate symbol parser only to `format`, but the mnemonic Bool
constants already work there and also work in direct type syntax. Symbol
support would therefore add spellings, validation, and error cases without
adding a use case. It should be reconsidered only if a future interface must
parse configuration values supplied as data.

### 6.3 Enums or singleton marker types

Typed values would make illegal cross-axis arguments easier to reject, but they
would replace Boolean parameters rather than alias them. That would require a
format-lattice migration touching generated aliases, `if S`/`if E` branches,
method signatures, registries, caches, display, and downstream code. Supporting
both representations would be worse: it would create duplicate format
identities for the same P3109 format.

This cost is disproportionate to four binary labels. The existing Boolean
representation is compact, valid as a type parameter, and pervasive; qualified
Boolean constants add readability at its seam without exposing the rest of the
implementation to change.

### 6.4 A macro

A macro could rewrite mnemonic syntax to Booleans, but it would introduce a new
language construct for a substitution Julia constants already perform. It
would also be harder to compose in generated and ordinary Julia code. Reject
it.

### 6.5 Constructor or factory adapters

Julia cannot intercept `Binary{...}` type application, and `format` already is
the factory for runtime parameters. Adding `Binary(...)`, a second factory, or
normalization helpers would split one established interface into two shallow
ones. Reject them for this change.

## 7. Verification plan

Add a focused testset covering the interface rather than its implementation.

### 7.1 Truth table and types

```julia
@test Signedness.Unsigned === false
@test Signedness.Signed   === true
@test Domain.Finite       === false
@test Domain.Extended     === true

@test Signedness.Unsigned isa Bool
@test Signedness.Signed   isa Bool
@test Domain.Finite       isa Bool
@test Domain.Extended     isa Bool
```

### 7.2 Canonical identity

Test all four signedness/domain combinations, at both representation widths:

```julia
for (S_mnemonic, S) in ((Signedness.Unsigned, false),
                        (Signedness.Signed, true)),
    (E_mnemonic, E) in ((Domain.Finite, false),
                        (Domain.Extended, true))

    P = S ? 3 : 4
    @test Binary{8,P,S_mnemonic,E_mnemonic} === Binary{8,P,S,E}
    @test Binary{9,P,S_mnemonic,E_mnemonic} === Binary{9,P,S,E}
    @test reptype(Binary{8,P,S_mnemonic,E_mnemonic}) === format(8, P, S, E)
    @test reptype(Binary{9,P,S_mnemonic,E_mnemonic}) === format(9, P, S, E)
end
```

Also assert the concrete aliases for representative cells:

```julia
@test format(8, 4, Signedness.Signed, Domain.Extended) === Binary8p4se
@test format(9, 4, Signedness.Unsigned, Domain.Finite) ===
    SmallFloats.Binary9p4uf
```

### 7.3 Introspection and construction

```julia
F = Binary{8,4,Signedness.Signed,Domain.Extended}
@test issigned(F)
@test isextended(F)
@test F(1.5) == Binary8p4se(1.5)
```

The normal format sweep already exercises operations and storage once identity
is established; duplicating the arithmetic suite for the alternate spelling
would test past the interface.

### 7.4 Base-name safety

Test in a fresh nested module so the result reflects `using` behavior:

```julia
module MnemonicImportTest
using Test
using SmallFloats

@test Signed === Base.Signed
@test Unsigned === Base.Unsigned
@test Signedness.Signed === true
@test Signedness.Unsigned === false
end
```

Run the existing ambiguity and documentation checks as well. No new method is
expected, so any new method ambiguity is a release blocker.

## 8. Documentation and rollout

This is an additive change with no migration or deprecation period.

Update:

1. `src/formats.jl` docstrings for `Binary`, `Signedness`, and `Domain`;
2. the format introduction and cheat sheet in `docs/src`;
3. examples that explicitly teach the four parameters;
4. the external reference so the two namespaces are discoverable;
5. documentation-consistency tests to pin their public status and truth table.

Do not mechanically replace every `true` and `false` in implementation-oriented
documentation or source. Internal formulas such as `S ? ... : ...` should stay
Boolean because that is the canonical representation. The recommended editorial
rule is:

- use the mnemonics when explaining or choosing a P3109 Signedness or Domain;
- use Booleans when explaining the internal parameter representation;
- use named aliases such as `Binary8p4se` for ordinary datum construction.

## 9. Acceptance criteria

The feature is complete when all of the following hold:

- both mnemonic and Boolean examples compile;
- mnemonic and Boolean spellings are `===` for every tested format;
- all four mnemonic members have type `Bool`;
- `using SmallFloats` leaves `Signed` and `Unsigned` bound to their Base types;
- the format count remains 504 and every existing alias retains its identity;
- the full test suite, ambiguity checks, documentation examples, and Documenter
  build pass;
- no runtime parser, conversion, method, allocation, or new format identity was
  introduced.

The result is a small interface with high locality: callers gain the vocabulary
of P3109, while the implementation remains entirely Boolean.
