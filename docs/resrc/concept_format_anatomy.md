# Format Anatomy

Every value in SmallFloats.jl belongs to a *format*, and a format is a Julia
type. This page explains what that type actually is, why the package draws a
hard line between the abstract idea of a format and the concrete type your
code uses, and why that line matters for both correctness and speed.

## The parametric type

Every format is an instance of the same four-parameter type:

```julia
Binary{K,P,SGN,EXT}
```

`K` is the bitwidth, `3 ≤ K ≤ 16`. `P` is the precision — significand bits,
including the implicit bit. `SGN` is a `Bool`: signed or unsigned. `EXT` is a
`Bool`: extended (the domain includes ±Inf) or finite (it does not). Every
legal combination of these four parameters is a distinct format, and the
package ships all of them: **504 formats** in total.

That is the whole parameter space. There is no fifth axis, and — this is the
detail that trips people up when they start comparing formats — `K` is not an
independent budget. It is spent entirely by the other three:
`K = P + E + SGN` where `E` is the exponent width implied by `K`, `P`, and
`SGN`. Raising precision by one bit necessarily lowers exponent range,
because there is nowhere else in the word for the extra bit to come from.

## `<:`, not `===`

`Binary{K,P,SGN,EXT}` is an abstract type. It is not what a value's type
actually is, and it is not what you should write as an array element type or
a constructor target. The concrete type is a *representation* — a
draft-named alias like `Binary8p4se` — related to the abstract format by
subtyping, not equality:

```julia-repl
julia> Binary8p4se <: Binary{8,4,true,true}      # `<:`, not `===` — see below
true

julia> formatname(Binary{6,3,true,false})
:Binary6p3sf

julia> SmallFloats.Binary16p6se                  # always reachable, unexported
Binary16p6se

julia> format(16, 6, true, true)                 # programmatic, runtime params
Binary16p6se

julia> using SmallFloats.Formats                 # …or bring all 504 into scope

julia> Binary16p6se
Binary16p6se
```

`Binary8p4se` is a concrete subtype of `Binary{8,4,true,true}`, but the two type
objects are distinct. The distinction is not an implementation accident; it
comes from the draft's own vocabulary. A
*format* is a datum set and an encoding — an abstract description of which
values exist and how they are named. A *representation* is a specific choice
of machine word that carries a code point: how many bits, what storage unit,
what bit layout. That choice sits below the level of description the
standard cares about. `Binary` names the format; `Binary8p4se` is the
representation you actually compute with.

The suffix on an alias reads directly: `p4` is precision 4, `s`/`u` is
signed/unsigned, `e`/`f` is extended/finite. `Binary8p4se` is 8-bit,
precision 4, signed, extended — read the name and you have the four
parameters without consulting a table.

## Why 504 formats, and why only 120 are exported

Every legal `(K, P, SGN, EXT)` combination at `K ∈ 3:16` gets an alias,
because the whole point of the package is that formats are cheap to have —
each one is 256 (or fewer) code points and a handful of type-parameter
queries, not a hand-written implementation. But 504 identifiers is more than
any one script needs in scope at once, so `using SmallFloats` exports only
the **120 aliases at K ≤ 8** — the sizes people actually reach for most:
sub-byte and byte-sized formats for quantization, embeddings, and packed
storage.

The other 384 (`K` from 9 to 16) are one opt-in away. You never need to
define anything to reach them — they already exist as bindings, just not
exported ones:

- `SmallFloats.Binary16p6se` — fully qualified, always available regardless
  of what's exported.
- `using SmallFloats.Formats` — brings every one of the 504 aliases into
  scope at once.
- `format(K, P, SGN, EXT)` — the programmatic route, for when the parameters
  are runtime values rather than something you can spell as a literal type
  name.

## Format introspection

Every format answers a fixed set of queries about its own structure, drawn
from the draft's Group M, in both a Julia-flavored spelling and the
draft-named form:

```julia-repl
julia> bitwidth(Binary8p4se), precision(Binary8p4se), expbias(Binary8p4se)
(8, 4, 8)

julia> MaxFiniteOf(Binary8p4se)
Binary8p4se(224.0 ≡ 0x7e)

julia> MinPositiveOf(Binary8p4se)
Binary8p4se(0.0009765625 ≡ 0x01)
```

`MinFiniteOf`, `MinNormalOf`, `MaxSubnormalOf`, `expbitwidth`,
`trailingsigbits`, `issigned`, `isextended`, and their draft-named
counterparts (`BitwidthOf`, `PrecisionOf`, `ExponentBiasOf`, …) round out the
set.

The important property of every one of these queries is that it is a pure
function of the type parameters — nothing about a particular value changes
the answer — so it works identically whether you hand it a type or a value:

```julia-repl
julia> x = Binary8p4se(1.6);

julia> BitwidthOf(x), PrecisionOf(x), SignednessOf(x), DomainOf(x)
(8, 4, true, true)

julia> MaxFiniteOf(x)
Binary8p4se(224.0 ≡ 0x7e)
```

`bitwidth(x)` and `bitwidth(typeof(x))` are the same query, and both fold to
a compile-time literal — there is no runtime cost to asking a value what
kind of format it lives in.

!!! perf "The abstract format as an array element type"
    Because `Binary{K,P,Σ,Δ}` is abstract, declaring an array with it as the
    element type gives you a non-`isbits` element type, and every element is
    boxed:

    ```julia-repl
    julia> isbitstype(eltype(Vector{Binary{8,4,true,true}}(undef, 3)))
    false

    julia> isbitstype(eltype(Vector{Binary8p4se}(undef, 3)))
    true
    ```

    Nothing about this errors. Every operation still returns the right
    answer, because the package normalizes the abstract format at every
    constructor and entry point it can see. What you silently lose is the
    entire performance story: table gathers, zero-allocation scalar calls,
    specialized dispatch — all of it depends on the element type being
    concrete. This is the sharper edge of the type distinction above: comparing
    the concrete alias with the abstract format makes their different roles
    visible, while the abstract-array mistake costs you real performance and
    says nothing at all.

    `similar(a, T)` normalizes the request for you, but `Vector{T}(undef,
    n)` cannot be intercepted at the call site. Always spell the alias, or
    use `format(K, P, Σ, Δ)` when the parameters are runtime values.

## Go deeper

> Continue with **Values, Code Points & Conversion** (Insights track)
> for how a `Binary` value stores a code point, how `decode` recovers the
> exact datum, and the four ways to construct one.
