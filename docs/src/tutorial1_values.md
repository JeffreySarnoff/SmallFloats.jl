# Tutorial 1: Values, Code Points & Conversion

This tutorial assumes the Quickstart: you've seen `Binary8p4se(1.6)` project onto
`1.625 ≡ 0x45`, you've seen an `Unsigned` argument mean code point rather than
number, and you've seen `Add(T, ρ, x, y)` alongside plain `+`. Here we slow down
and go through every way a value gets made, read, stepped, and classified.

## Four ways in, two ways out

A `Binary` value is an immutable wrapper around a code point. There are four
constructors and two accessors:

```julia-repl
julia> x = Binary8p4se(1.6)              # construct from a Real: projects (rounds)
Binary8p4se(1.625 ≡ 0x45)

julia> Binary8p4se(0x45)                 # construct from a UInt8 CODE POINT (validated)
Binary8p4se(1.625 ≡ 0x45)

julia> rawvalue(Binary8p4se, 0x45)       # same, unchecked — the kernel-internal route
Binary8p4se(1.625 ≡ 0x45)

julia> Convert(Binary8p4se, RNE_SN, 3)   # explicit conversion, any mode
Binary8p4se(3.0 ≡ 0x4c)

julia> decode(x)                          # the exact datum, on the format's carrier
1.625

julia> codepoint(x)                       # the code point (extends Base.codepoint)
0x45
```

`decode` never rounds — it is a lookup from name to meaning. Construction from a
`Real` is the only place rounding happens on the way in.

## Important: `Unsigned` means code point, at every width

The Quickstart already showed you `Binary8p4se(0x02)` and `Binary8p4se(2)`
landing on different values. The rule generalizes to every integer width and
every format, and it is worth stating as a standalone hazard because it never
raises an error — it just silently gives you the wrong datum if you meant a
number:

```julia-repl
julia> Binary8p4se(0x02), Binary8p4se(2)
(Binary8p4se(0.001953125 ≡ 0x02), Binary8p4se(2.0 ≡ 0x48))
```

!!! warning "`Unsigned` means code point — at every width"
    `T(0x02)` constructs code point `0x02`; `T(2)` projects the numeric value
    two. Signedness of the integer type is what distinguishes them, so the rule
    holds for `UInt8`, `UInt16` and any other `Unsigned`: `Binary16p6se(0x0002)`
    is code point 2, not the value 2.0. Use `Convert` when intent should be
    unmistakable.

    Out-of-range codes throw for K < 8 (`Binary5p3sf(0x20)` is an error); the range
    check costs nothing measurable — 2.1 ns, identical to unchecked `rawvalue`.
    Round-tripping is `T(codepoint(x)) === x`.

## `Convert` versus `convert`

`Convert` (capitalized, from the spec-named register) is the explicit projection
you saw above: `Convert(T, ρ, value)`, numeric for every integer. Base's lowercase
`convert` is a different, narrower operation that Julia's promotion machinery
calls, and it is value-preserving on `Unsigned` input rather than code-point
reading:

```julia-repl
julia> Binary8p4se(0x02)
Binary8p4se(0.001953125 ≡ 0x02)
```

Keep the two apart: `T(x::Unsigned)` reads a code point; `Convert(T, ρ, x)` always
projects a numeric value, whatever its type. When you want projection and the
argument might be an `Unsigned`, reach for `Convert`, not the constructor.

## The decode / codepoint round-trip

`decode` and `codepoint` are inverses by construction — that round-trip is a
format's identity:

```julia-repl
julia> x = Binary8p4se(1.6)
Binary8p4se(1.625 ≡ 0x45)

julia> codepoint(x)
0x45

julia> decode(x)
1.625
```

`decode` is **always exact**, but the type it returns is a property of the
format, not of the package: `Float64` for the 432 formats whose exponent range it
holds, `Float128` or an exact dyadic carrier for the other 72. `Float64(x)`
always returns a `Float64` and rounds where the datum does not fit.

## Enumerating a whole format

Small formats are small enough to look at in full. `Binary4p2se` has 16 code
points, sorted here by the total order (single NaN last):

```julia
decode.(sort(Binary4p2se.(0x00:0x0f)))      # broadcast the code-point constructor
```

```
[-Inf, -2.0, -1.5, -1.0, -0.75, -0.5, -0.25, 0.0,
  0.25, 0.5, 0.75, 1.0, 1.5, 2.0, Inf, NaN]
```

That listing *is* the format: one NaN, no negative zero, subnormal spacing near
zero, binades doubling outward. This is a good way to build intuition for a
format before committing to it.

## Stepping and classification

Stepping moves to the adjacent code point; classification names what kind of
datum you're holding:

```julia-repl
julia> NextGreaterThan(Binary8p4se(1.0))
Binary8p4se(1.125 ≡ 0x41)

julia> Class(Binary8p4se(0.01))           # draft classification
ClassPosNormal::FPClass = 0x06
```

`NextGreaterThan`/`NextLessThan` are the draft's Next operations; `nextfloat` and
`prevfloat` alias them, so both spellings work. Standard predicates apply too:
`isnan`, `isinf`, `isfinite`, `iszero`, `signbit`, `issubnormal`:

```julia-repl
julia> Binary8p4se(1e9)                   # overflow under the default spec → +Inf
Binary8p4se(Inf ≡ 0x7f)

julia> Binary8p4se(-0.0)                  # no −0: projects to the single zero
Binary8p4se(0.0 ≡ 0x00)

julia> isnan(Binary8p4se(NaN)), isfinite(Binary8p4se(2.0))
(true, true)
```

## `zero`, `one`, `eps`, `typemax`

The usual numeric-type vocabulary works on every format too — `zero`, `one`,
`eps`, `typemin`, `typemax` — alongside the predicates and stepping operations
above; they answer from the format's own grid, not from any IEEE assumption
about it.

## Try it

Using only what this tutorial covered: what does `decode(Binary8p4se(0x01))`
return, and how is it different from `decode(Binary8p4se(1))`? Work it out
before checking.

<details>
<summary>Answer</summary>

`Binary8p4se(0x01)` reads code point 1 — the smallest positive subnormal for
this format, `0.0009765625` (shown as `MinPositiveOf(Binary8p4se)` in the User
Guide). `Binary8p4se(1)` projects the numeric value one onto the nearest datum,
`1.0`. Same digit, two different constructors, two very different answers — the
pitfall from this tutorial in miniature.

</details>

Where next: [Tutorial 2, Projection: Rounding & Saturation](tutorial2_projection.md) picks up right where
`Convert(T, ρ, value)` left off — the full 6×3 grid of rounding and saturation
modes, and how session defaults change what plain `+` does. For the complete,
dry listing of format queries and accessors, see [Format Names & Queries](ref_formats.md).
