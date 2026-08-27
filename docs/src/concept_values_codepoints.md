# Values, Code Points, and Conversion

This page develops the identity of a `Binary` value: how it is constructed,
read, stepped, classified, and converted. Read [First Session](first_session.md)
first if the distinction between datum and code point is new.

## Three ways in, two ways out

A `Binary` value is an immutable wrapper around a code point. There are three
constructors and two accessors:

```julia-repl
julia> x = Binary8p4se(1.6)              # construct from a Real: projects (rounds)
Binary8p4se(1.625 ⇆ 0x45)

julia> Binary8p4se(0x45)                 # construct from a UInt8 CODE POINT (validated)
Binary8p4se(1.625 ⇆ 0x45)

julia> Convert(Binary8p4se, RNE_SN, 3)   # explicit conversion, any mode
Binary8p4se(3.0 ⇆ 0x4c)

julia> decode(x)                          # the exact datum, on the format's carrier
1.625

julia> codepoint(x)                       # the code point (extends Base.codepoint)
0x45
```

`decode` never rounds — it is a lookup from name to meaning. Construction from a
`Real` is the only place rounding happens on the way in.

## Important: `Unsigned` means code point, at every width

The First Session already showed you `Binary8p4se(0x02)` and `Binary8p4se(2)`
landing on different values. The rule generalizes to every integer width and
every format, and it is worth stating as a standalone hazard because it never
raises an error — it just silently gives you the wrong datum if you meant a
number:

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ⇆ 0x02), Binary8p4se(2.0 ⇆ 0x48))
```

!!! warning "`Unsigned` means code point — at every width"
    `T(0x02)` constructs code point `0x02`; `T(2)` projects the numeric value
    two. Signedness of the integer type is what distinguishes them, so the rule
    holds for `UInt8`, `UInt16` and any other `Unsigned`: `Binary16p6se(0x0002)`
    is code point 2, not the value 2.0. Use `Convert` when intent should be
    unmistakable.

    Out-of-range codes throw for K < 8 (`Binary5p3sf(0x20)` is an error).
    Round-tripping is `T(codepoint(x)) === x` — see [What is, and is not, a
    round-trip here](#What-is,-and-is-not,-a-round-trip-here) for the direction
    that does *not* invert. The unchecked constructor is an internal kernel
    primitive rather than part of the exported interface.

## `Convert` versus `convert`

`Convert` (capitalized, from the spec-named register) is the explicit projection
you saw above: `Convert(T, ρ, value)`, numeric for every integer. Base's lowercase
`convert` is a different, narrower operation that Julia's promotion machinery
calls, and it is value-preserving on `Unsigned` input rather than code-point
reading:

```julia-repl
julia> Binary8p4se(0x02)
Binary8p4se(0.001953125 ⇆ 0x02)
```

Keep the two apart: `T(x::Unsigned)` reads a code point; `Convert(T, ρ, x)` always
projects a numeric value, whatever its type. When you want projection and the
argument might be an `Unsigned`, reach for `Convert`, not the constructor.

## What is, and is not, a round-trip here

`decode` and `codepoint` are not inverses of each other — both are read-only
accessors on the same `x`, one returning the datum, the other the identity it
is stored under. Neither writes a code point, so neither can undo the other.

The actual inverse pair is the code-point constructor and `codepoint`
(stated above): `T(codepoint(x)) === x`, exact for every valid code point.
The other direction fails on purpose — `codepoint(T(v))` for a `Real v` is
not an inverse of anything, because `T(v)` *projects* `v` to the nearest
datum first, so you recover that datum's code point, not a code point that
would reconstruct `v`. Only the code-point round-trip is exact both ways; the
`Real` round-trip loses information by design, every time construction
rounds.

`decode` is **always exact**, but the type it returns is a property of the
format, not of the package: `Float64` for the 432 formats whose exponent range it
holds, `Float128` or an exact dyadic carrier for the other 72. `Float64(x)`
always returns a `Float64` and rounds where the datum does not fit.

## Enumerating a whole format

Small formats are small enough to look at in full. `Binary4p2se` has 16 code
points, sorted here by the draft's total order — which places the single NaN
**first**, below −Inf (§4.12.1), not last as `Float64` sorting does:

```julia-repl
julia> decode.(sort(Binary4p2se.(0x00:0x0f)))      # broadcast the code-point constructor
16-element Vector{Float64}:
 NaN
 -Inf
  -2.0
  -1.5
  -1.0
  -0.75
  -0.5
  -0.25
   0.0
   0.25
   0.5
   0.75
   1.0
   1.5
   2.0
  Inf
```

That listing *is* the format: one NaN, no negative zero, subnormal spacing near
zero, binades doubling outward. This is a good way to build intuition for a
format before committing to it.

The one-liner generalizes to any of the 504 formats, in either storage order
or total order, as a complete `(code, value)` table. No projection is
involved: `decode` is exact and policy-free, so the table is a function of
the format alone.

```julia
function codetable(::Type{F}; by::Symbol = :code) where {F<:Binary}
    by in (:code, :value) || throw(ArgumentError("by must be :code or :value"))
    U = codeunit_type(F)                        # UInt8 at K ≤ 8, UInt16 above
    vals = [F(U(c)) for c in 0:(1 << bitwidth(F)) - 1]   # validated code-point constructor
    by === :value && sort!(vals)                # the draft's total order: NaN first
    [(code = codepoint(v), value = decode(v)) for v in vals]
end

function printcodetable(io::IO, ::Type{F}; by::Symbol = :code) where {F<:Binary}
    w = 2 * sizeof(codeunit_type(F))            # hex digits per code unit
    for r in codetable(F; by)
        println(io, "  0x", string(r.code; base = 16, pad = w), "  ", r.value)
    end
end

printcodetable(stdout, Binary4p2se)
```

```
  0x00  0.0
  0x01  0.25
  0x02  0.5
  0x03  0.75
  0x04  1.0
  0x05  1.5
  0x06  2.0
  0x07  Inf
  0x08  NaN
  0x09  -0.25
  0x0a  -0.5
  0x0b  -0.75
  0x0c  -1.0
  0x0d  -1.5
  0x0e  -2.0
  0x0f  -Inf
```

Storage order makes the layout visible — positives ascending from `0x00`,
the sign bit alone (`0x08`) naming the single NaN, negatives mirroring above
it. `by = :value` gives the sorted listing shown earlier. The value column is
the format's datum carrier, so the table stays exact for the 72 wide formats
too. The reverse table, value → code, *does* need a projection — it is
`codepoint(Convert(F, ρ, x))` over inputs of your choosing, one rounding per
entry.

## Stepping and classification

Stepping moves to the adjacent code point; classification names what kind of
datum you're holding:

```julia-repl
julia> NextGreaterThan(Binary8p4se(1.0))
Binary8p4se(1.125 ⇆ 0x41)

julia> Class(Binary8p4se(0.01))           # draft classification
ClassPosNormal::FPClass = 0x06
```

`NextGreaterThan`/`NextLessThan` are the draft's Next operations; `nextfloat` and
`prevfloat` alias them, so both spellings work. Standard predicates apply too:
`isnan`, `isinf`, `isfinite`, `iszero`, `signbit`, `issubnormal`:

```julia-repl
julia> Binary8p4se(1e9)                   # overflow under the default spec → +Inf
Binary8p4se(Inf ⇆ 0x7f)

julia> Binary8p4se(-0.0)                  # no −0: projects to the single zero
Binary8p4se(0.0 ⇆ 0x00)

julia> isnan(Binary8p4se(NaN)), isfinite(Binary8p4se(2.0))
(true, true)
```

## `zero`, `one`, `eps`, `typemax`

The usual numeric-type vocabulary works on every format too — `zero`, `one`,
`eps`, `typemin`, `typemax` — alongside the predicates and stepping operations
above; they answer from the format's own grid, not from any IEEE assumption
about it.

## What this leaves open

Every route in on this page that takes a `Real` rounds, and none of them said
by what rule. That rule is a *policy* you choose rather than a property of the
format: [The Exact-Then-Project Contract](concept_exact_then_project.md)
establishes that the rounding happens exactly once and at the end, and
[Rounding and Saturation](concept_rounding_saturation.md) develops the two
choices that decide where it lands. The query vocabulary used above —
`MaxFiniteOf`, `MinPositiveOf`, and the rest — is catalogued in
[Formats and Value Queries](reference_formats_values.md).
