# Exact Block Reductions

A block reduction has to add `B` products exactly and round **once**. The
textbook way to do that is a *superaccumulator* — a fixed-point register wide
enough to hold every representable product without loss, typically hundreds of
bits, updated per lane. SmallFloats.jl does not have one, and does not need one.

This page explains what it does instead, why that is exact rather than
merely accurate, and where the two guards that make it exact actually live.

## The problem

A block is `(scale, elements)` — one scale factor shared by `B` elements
(draft §5):

```julia-repl
julia> b = Block(Binary8p1uf(0.5), (Binary8p4se(80.0), Binary8p4se(-0.375),
                                    Binary8p4se(-5.5), Binary8p4se(2.25)));

julia> scaleformat(b), elemformat(b), blocksize(b)
(Binary8p1uf, Binary8p4se, 4)
```

Reducing it means summing the four *lane values* `scale × elementᵢ`. Do that
lane by lane in the result format and every partial sum rounds:

```julia-repl
julia> SmallFloats.blockdecode(b)              # the exact lane values
(40.0, -0.1875, -2.75, 1.125)

julia> BlockReduceAdd(Binary8p4se, RNE_SN, b)  # exact sum 38.1875, projected ONCE
Binary8p4se(40.0 ≡ 0x6a)

julia> lanes = SmallFloats.blockdecode(b);

julia> foldl((a, v) -> Add(Binary8p4se, RNE_SN, a, Convert(Binary8p4se, RNE_SN, v)),
             lanes; init = zero(Binary8p4se))  # rounding at every step
Binary8p4se(36.0 ≡ 0x69)
```

One code point apart, from four lanes. The exact sum is 38.1875; the ulp in
`[32, 64)` is 4, so the neighbours are 36 and 40 and the correct answer is 40.
Accumulated rounding lands on 36 — not catastrophically wrong, but *not the
defined result*, and the error grows with `B`.

So the reduction must be exact before it is projected. The question is what to
accumulate in.

## Step 1: decode each lane exactly

`blockdecode` produces `ωMultiply(decode(s), decode(xᵢ))` per lane, exactly, on
a carrier chosen from **both** formats.

That last point is the whole content of the function, and it prevents a subtle
misapplication. A block's scale and element formats are independent, and what
has to fit is their *product*. The carrier rule is `ΣBᵢ ≤ emax`, so two formats
that are each comfortable alone can compose into a lane product that is not: a
`Binary16p1uf` scale reaches `2^32768`. Selecting the carrier from either
format's own rung would overflow to `±Inf` — a plausible-looking special value
rather than an error, which is the worst available failure mode. The carrier is
therefore keyed on `rung(Val(:Multiply), FS, FE)`.

## Step 2: accumulate exactly — two strategies

Once the lanes are exact, the sum must be too. There are two ways to get there,
and the package tries the cheap one first.

### The fast path: a span filter

`Float128` carries a 113-bit significand. A sum of `B` values is exactly
representable in it when

```text
(lane significand bits) + (exponent span) + ⌈log₂B⌉  ≤  113
```

— the significand bits of the widest lane, plus the number of binades the lanes
straddle, plus the carries from adding `B` of them. Every term is an *integer*,
and the exponent span is one pass over the lanes. So the package computes the
span and decides:

| reduction | shipped guard |
|:---|:---|
| `BlockReduceAdd` | `span + ⌈log₂B⌉ ≤ 92` |
| `BlockDotProduct` | `span + ⌈log₂B⌉ ≤ 76` |

If the guard passes, a plain `Float128` accumulation **is** the exact answer —
no rounding occurs at any step, so there is nothing to be careful about. The dot
product's budget is tighter because each of its terms is a product of *four*
datums (two scales, two elements) rather than two.

### Why the filter is sound

The guards look generous against the worst case you would compute on paper. Two
`Binary16p11se` datums multiply to 22 significand bits, which leaves 91 for
`span + ⌈log₂B⌉` — one less than the 92 the sum guard admits.

The resolution is that **lane width and exponent span are anti-correlated, not
independent.** A datum only reaches the bottom of a format's exponent range by
being *subnormal*, and a subnormal datum carries proportionally fewer
significand bits. In `Binary16p11se`, full 11-bit significands exist only at
exponents −15…15; below that, every bit of extra reach costs a bit of width.
The two quantities in the inequality cannot both be maximal.

That argument is easy to get wrong, so it is checked rather than trusted: an
audit over wide format pairs admitted **17 040** sums and **16 479** dot
products through the guards and compared every one against exact `BigFloat`
truth. Zero were inexact.

!!! note "Two guards, not one"
    The span filter is about the **significand**. It says nothing about whether
    the lanes *fit in `Float128` at all* — and at rung 3 they do not, because a
    `Binary16p1uf` scale reaches `2^32768`, which is `Inf` in `Float128` before
    any accumulation begins.

    So the accumulator is selected by the **head** as well: `_f128acc` answers
    `false` for `HeadExact` unconditionally. Width and range are independent
    conditions and both must hold. An earlier version checked only the width,
    and the exponent condition was a premise nobody had stated.

### The fallback: precision derived from the formats

When either guard fails, an exact `BigFloat` accumulation takes over at a
precision **derived from the block's two formats and its length** — never a
constant:

```text
sums     2(B_S + B_E + P_S + P_E) + 64 + ⌈log₂B⌉
products B(P_S + P_E) + 128
```

Two different formulas because two different analyses. For a sum, the lanes
straddle `2(B_S + B_E)` binades and each carries `P_S + P_E` significand bits,
plus carries. For a product reduction the exponent merely shifts, but the
significand is the *sum* over lanes.

Both replaced magic numbers, and the history is the reason they are written out.
The product form was `16B + 128`, where `16 = 8 + 8` is `P_S + P_E` with `P = 8`
hardcoded — correct at K ≤ 8 and understating by up to 2× above it. Its sibling
`_REDPREC = 2400` was ample through `B ≈ 512` and silently truncating above.
Both failure modes produce a plausible wrong number rather than an error, which
is exactly the class of defect this package treats as unacceptable.

## Step 3: project once

Whichever path produced it, the exact result meets the projection engine exactly
once. `ωBlockProject` follows the draft's special rows for the scale (NaN, `0`,
`±Inf`), then divides each element result by the scale through a cheapest-first
cascade:

```text
exact Float64 quotient  →  correctly rounded Float128
                        →  bracket / pre-filter  →  MPFR interval
```

mirroring the scalar quotient group's rigor arguments. Each rung is tried only
if the one before it cannot decide the code point.

!!! tip "P = 1 scales divide exactly, for free"
    A `P = 1` format has no stored significand bits, so every datum is `±2^e`.
    Dividing by a power of two is exact, and the first rung of the cascade
    always succeeds — the draft calls this out in its own NOTE. This is why the
    MX-style scale format `Binary16p1uf` is not just conventional but cheap:
    the whole enclosure ladder collapses to one correctly rounded division.

## Why no superaccumulator

A superaccumulator is the right answer when you cannot inspect the data — a
fixed register sized for the worst case, paid for on every lane. Here the data
*is* inspectable: one integer pass over the lane exponents answers the question
the accumulator width was insuring against, and answers it exactly. The common
case then runs in hardware `Float128`, and the uncommon case gets arbitrary
precision sized to the actual formats.

A register-resident superaccumulator remains a tracked optimization for the
Phase-3 work — as a *speed* change on the fallback path, not a correctness one.

## Source and gates

`src/blocks.jl` owns block construction, scale/element operations, span
filtering, exact reductions, and `BlockVector`. Review changes against three
obligations: decoded lane values are exact, the chosen accumulator covers the
proven span, and exactly one final projection occurs. Compare fused reductions
with a deliberately wider reference, including mixed scales and special values.

## See also

- [Blocks and Scaled Operations](reference_arrays_blocks_storage.md) — the API contract.
- [Working with Blocks](workflow_blocks.md) — the task-oriented guide.
- [Blocks for Dynamic Range](workflow_blocks.md) — when to reach
  for one.
- [Oracle and Rigor Classes](internals_oracle.md) — where the enclosure cascade
  comes from.
- [Proving your fused kernel exact](examples_verification.md#Proving-your-fused-kernel-exact:-BlockDotProduct-vs-512-bit-truth)
  — `BlockDotProduct` against 512-bit truth.
- [Add an Operation](internals_add_operation.md) — adding block variants.
