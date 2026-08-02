# Reference: Format Names & Queries

Dry listing of the format naming grammar, the alias/type distinction, and every
format-query accessor. For narrative explanation, see the Mental Model page;
for a worked introduction, see the Quickstart and Tutorial 1: Values, Code
Points & Conversion.

## Naming grammar

```text
Binary K p P (s|u) (e|f)
       │   │  │     └─ extended (Inf) or finite domain
       │   │  └────── signed or unsigned
       │   └───────── significand precision, including the implicit bit
       └───────────── total bitwidth, 3 through 16
```

| Field | Values | Meaning |
|---|---|---|
| `K` | 3–16 | total bitwidth |
| `P` | 1–`K` | significand precision, including the implicit bit |
| `s`\|`u` | signed / unsigned | sign field present or absent |
| `e`\|`f` | extended / finite | domain includes ±Inf, or spends those code points on finite datums |

There are 504 legal `(K,P,SGN,EXT)` combinations, each with a draft-named
alias. 120 aliases at `K ≤ 8` are exported by `using SmallFloats`.

| Example alias | K | P | Signed | Domain |
|---|---|---|---|---|
| `Binary8p4se` | 8 | 4 | signed | extended |
| `Binary8p4sf` | 8 | 4 | signed | finite |
| `Binary6p3ue` | 6 | 3 | unsigned | extended |
| `Binary5p5uf` | 5 | 5 | unsigned | finite |
| `Binary16p6se` | 16 | 6 | signed | extended (opt-in export) |
| `Binary16p1uf` | 16 | 1 | unsigned | finite |

## `<:` versus `===`

- `Binary` is abstract; `Binary8p4se` is its concrete representation.
- `Binary8p4se <: Binary{8,4,true,true}` is `true`.
- `Binary8p4se === Binary{8,4,true,true}` is `false`. Use the alias, or
  `format(K, P, Σ, Δ)` for runtime parameters. See Tutorial 1: Values, Code
  Points & Conversion.

## `format()` and opt-in access

| Form | Scope | Result |
|---|---|---|
| `using SmallFloats` | exports 120 aliases, `K ≤ 8` | alias directly in scope |
| `using SmallFloats.Formats` | brings all 504 aliases into scope | alias directly in scope |
| `SmallFloats.Binary16p6se` | unexported, always reachable | alias by qualified path |
| `format(K, P, Σ, Δ)` | programmatic, runtime parameters | the alias for those parameters |
| `formatname(Binary{K,P,Σ,Δ})` | programmatic | `Symbol` of the alias name |

## Format query table

Every query accepts either a `Type` or a `value`; `bitwidth(x) ≡
bitwidth(typeof(x))`, and both fold to a literal constant.

| Query | Returns | Draft-named form | Teaching page |
|---|---|---|---|
| `bitwidth(T)` | `K` | `BitwidthOf(T)` | Cheat Sheet |
| `precision(T)` | `P` | `PrecisionOf(T)` | Cheat Sheet |
| `issigned(T)` | `Bool` | `SignednessOf(T)` | Cheat Sheet |
| `isextended(T)` | `Bool` | `DomainOf(T)` | Cheat Sheet |
| `expbias(T)` | exponent bias | `ExponentBiasOf(T)` | Cheat Sheet |
| `expbitwidth(T)` | exponent field width | — | Cheat Sheet |
| `trailingsigbits(T)` | trailing significand bits | — | Cheat Sheet |
| `MaxFiniteOf(T)` | largest finite value, typed | — | Cheat Sheet |
| `MinFiniteOf(T)` | smallest-magnitude finite value, typed | — | Cheat Sheet |
| `MinPositiveOf(T)` | smallest positive value, typed | — | Cheat Sheet |
| `MinNormalOf(T)` | smallest positive normal value, typed | — | Cheat Sheet |
| `MaxSubnormalOf(T)` | largest subnormal value, typed | — | Cheat Sheet |

Draft-named forms exist for every query in Group M, not only the four listed
above (`BitwidthOf`, `PrecisionOf`, `SignednessOf`, `DomainOf`,
`ExponentBiasOf`, and their neighbors); Julia-style and draft-named forms are
interchangeable.

## Value-and-type call forms

```julia
bitwidth(Binary8p4se)        # type form
x = Binary8p4se(1.6)
bitwidth(x)                  # value form, same answer, folds to 8
MaxFiniteOf(Binary8p4se)     # Binary8p4se(224.0 ≡ 0x7e)
MaxFiniteOf(x)               # same result
```

Where next: [Mental Model](mentalmodel.md),
[Tutorial 1: Values, Code Points & Conversion](tutorial1_values.md),
[How-To: Choose a Format](howto_choose_format.md).
