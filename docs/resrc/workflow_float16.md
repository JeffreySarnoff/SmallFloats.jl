# Interoperate with Float16 and BFloat16

Move data between SmallFloats formats and IEEE `Float16`/`BFloat16` without
silently changing its value by a factor of two.

## Ingredients

- `Convert(T, ρ, x)` — the only safe path between formats with different
  exponent bias.
- `datumsexact` to check whether the two datum sets permit an exact
  round trip.
- Never `reinterpret` across formats with different bias — see the warning below.

## Recipe

**1. Understand the mismatch before you touch either format.** The K ≤ 16 grid contains
two formats that look like `Float16` and `BFloat16` but are not — the
difference is the kind that produces correct-looking numbers rather than
errors:

| | `Binary16p11se` | `Float16` | `Binary16p8se` | `BFloat16` |
|---|---|---|---|---|
| precision `P` | 11 | 11 | 8 | 8 |
| exponent bias | **16** | **15** | **128** | **127** |
| largest finite | **65472** | **65504** | **3.3762e38** | **3.3895e38** |
| NaN encodings | **1** | **2046** | **1** | **2046** |
| negative zero | **no** | yes | **no** | yes |
| domain is a parameter | **yes** (`se`/`sf`) | no | **yes** | no |

P3109 defines the bias so the exponent range is symmetric about the format's
midpoint; IEEE-754 defines it as `2^(E-1) − 1`. The two differ by one, so
**every datum in the format is a factor of two away from its IEEE
counterpart** — `Binary16p11se` and `Float16` share a significand layout and
disagree on the value of every code point.

**2. Always convert — never reinterpret.** `Convert` is a real conversion:
`Float16(1.5)` becomes `Binary16p11se(1.5)`, unchanged in value:

```julia-repl
julia> using SmallFloats.Formats

julia> Convert(Binary16p11se, RNE_SF, Float16(1.5))    # a conversion: 1.5 ↦ 1.5
Binary16p11se(1.5 ≡ 0x4200)

julia> reinterpret(Binary16p11se, Float16(1.5))        # the SAME BITS: 1.5 ↦ 0.75
Binary16p11se(0.75 ≡ 0x3e00)
```

`Float16(1.5)` has the bit pattern `0x3e00`; read as a `Binary16p11se`, those
same bits denote **0.75**, because the exponent bias differs by one. Nothing
errors, nothing warns, and the answer is off by a factor of two.

**3. Check `datumsexact` when you need to know if the round trip is lossless.**
The package converts to and from both `Float16` and `BFloat16` exactly,
wherever the datum sets permit — `datumsexact` tells you where that holds so
you don't have to assume.

**4. Remember the other differences are draft decisions, not bugs.** A single
NaN encoding means there is no payload to propagate and no quiet/signalling
distinction — the 2045 code points IEEE spends on NaN payloads are ordinary
datums here. No negative zero means `-0.0` and `0.0` are the same code point.
The domain parameter (`e` for extended with ±Inf, `f` for finite) has no IEEE
analogue: `Binary16p11sf` spends the two infinity code points on finite
values instead. None of these need "fixing" before converting — `Convert`
already accounts for all of them.

## What can go wrong

!!! warning "`reinterpret` silently returns the wrong value, off by 2×"
    `reinterpret(Binary16p11se, Float16(1.5))` gives `0.75`, not `1.5` — the
    same bit pattern, read under a different exponent bias. This is the
    single most dangerous operation in cross-format interop: it never
    errors, so a pipeline that accidentally reinterprets instead of
    converting produces plausible-looking numbers that are systematically
    wrong by a factor of two. Always use `Convert`, never `reinterpret`,
    when moving between a SmallFloats format and `Float16`/`BFloat16`.

!!! note "If you want IEEE semantics, use Float16/BFloat16 directly"
    `Binary16p11se` and `Binary16p8se` are not drop-in replacements for
    `Float16`/`BFloat16` — they exist for the P3109 draft's own reasons
    (symmetric exponent range, single NaN, no negative zero, parametric
    domain). If your downstream consumer specifically needs IEEE bit
    patterns, keep the data in `Float16`/`BFloat16` and convert only at the
    SmallFloats boundary.

## see also

[Choose a Format](workflow_choose_format.md),
[Read & Export the Conformance Declaration](workflow_conformance.md).
