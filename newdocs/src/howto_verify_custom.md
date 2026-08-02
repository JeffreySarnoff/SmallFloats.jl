# Verify Custom Code

Trust, then verify — these patterns turn "is my code exact?" into an
enumeration. Formats are small enough that "test on a few points" is never
necessary; the recipes below enumerate the input space (or, where the space is
too large to enumerate, sweep it exhaustively along the dimension that matters)
and compare against an independently computed reference. Several examples use
unexported internals (`SmallFloats.round_to_precision`, `SmallFloats.project`,
…); those are stable enough to learn from but are not covered by
semantic-versioning guarantees.

## Verify a quantizer

Here every in-range datum of `Binary8p3se` is projected into `Binary8p4se` and
checked against a brute-force nearest search under 256-bit arithmetic
(distance agreement; the draft's tie rule is the projection engine's job and
is pinned elsewhere in the suite):

```julia
using SmallFloats

function ref_nearest_distance(::Type{T}, x) where {T}
    fins = [v for v in (rawvalue(T, UInt8(c)) for c in 0:255) if isfinite(decode(v))]
    minimum(abs(setprecision(() -> BigFloat(decode(v)) - BigFloat(x), BigFloat, 256))
            for v in fins)
end

function verify_quantizer()
    ok = true
    for c in 0x00:0xff
        x = decode(rawvalue(Binary8p3se, c))
        (isfinite(x) && abs(x) <= decode(MaxFiniteOf(Binary8p4se))) || continue
        got = Convert(Binary8p4se, RNE_SN, x)
        ok &= abs(decode(got) - x) == Float64(ref_nearest_distance(Binary8p4se, x))
    end
    ok
end
verify_quantizer()
```

```
true
```

This pattern — enumerate the inputs, compare against an independently written
reference — is how the entire package is tested, and it is available to *your*
quantization code at trivial cost.

## Prove a fused kernel

The block layer promises *one* projection with exact lane arithmetic. Trust,
then verify — against big-float truth, over random blocks with mixed scales
and an honest special-value mix:

```julia
using SmallFloats, Random

rng = Xoshiro(5)
mk() = Block(Binary8p1uf(2.0^rand(rng, -3:3)),
             ntuple(_ -> rawvalue(Binary8p4se, UInt8(rand(rng, 0:255))), 32))

function verify_dots(trials)
    for _ in 1:trials
        bx, by = mk(), mk()
        lx = [decode(bx.s) * decode(v) for v in bx.x]
        ly = [decode(by.s) * decode(v) for v in by.x]
        (any(!isfinite, lx) || any(!isfinite, ly)) && continue
        truth = setprecision(() -> sum(BigFloat(lx[i]) * BigFloat(ly[i]) for i in 1:32),
                             BigFloat, 512)
        got = BlockDotProduct(Binary8p4se, RNE_SN, bx, by)
        ref = setprecision(() -> SmallFloats.project(Binary8p4se, RNE_SN, truth), BigFloat, 512)
        codepoint(got) == codepoint(ref) || return false
    end
    true
end
verify_dots(200)
```

```
true
```

The same shape verifies any custom fused kernel you write: compose the truth in
`BigFloat`, project once, compare code points.

## Audit stochastic rounding

Every stochastic projection is a deterministic function of the draw `R`, so its
*distribution* is checkable exactly. For `x = 2 + 3/64` in `Binary8p4se` the
fraction is ν = 3/16 of an ulp, so `StochasticA{4}` must round up for exactly 3
of the 16 draws:

```julia
σ4 = RSA_SN(4)                  # ≡ ProjSpec(StochasticA{4}(), SatNone())
x = 2.0 + 3/64
count(decode(SmallFloats.project(Binary8p4se, σ4, x; R)) == 2.25 for R in 0:15)
```

```
3
```

Sweeping `R` like this turns "is my stochastic pipeline unbiased?" from a
statistical question into an exhaustive one — the pattern the shipped test
suite uses.

## Applying monotonicity

Decision and ranking systems consume scores through *order*. If scores are
produced in one format and compared in another, the conversion must be
monotone — and formats are small enough to prove it by enumeration rather than
trust it. Walk every `Binary8p3se` datum in total order and check that its
`Binary8p4se` image never goes backward on the integer order keys:

```julia
using SmallFloats
using SmallFloats: order_key

function monotone_conversion(::Type{From}, ::Type{To}) where {From,To}
    prev = nothing
    for v in sort(From.(0x00:UInt8(2^bitwidth(From) - 1)))
        isnan(decode(v)) && continue
        g = Convert(To, RNE_SN, v)
        prev !== nothing && order_key(g) < order_key(prev) && return false
        prev = g
    end
    true
end
monotone_conversion(Binary8p3se, Binary8p4se)
```

```
true
```

Run this for every `(From, To, ρ)` triple your system actually uses; it is a few
hundred integer comparisons per triple. A ranking pipeline whose conversions all
pass this audit cannot invert a preference by changing formats — a guarantee no
amount of spot-testing provides.

## Measuring Approximation

Search under a compute budget often wants a cheap, approximate evaluation
function. The κ registry turns "how approximate?" into a *measured* code-point
bound — and code-point bounds compose into a decision rule: **if two defined
evaluations differ by more than 2κ code points along the total order, the
approximate evaluator cannot invert their comparison.** Verify the rule
exhaustively for a κ = 2 evaluator:

```julia
using SmallFloats: order_key

fast(x) = (r = Exp(Binary8p4se, RNE_SN, x);
           isfinite(decode(r)) ? NextGreaterThan(NextGreaterThan(r)) : r)
κ, exhaustive = measure_kappa(fast, :Exp, Binary8p4se, (Binary8p4se,), RNE_SN)

function margin_audit(fast, κ)
    codes = [rawvalue(Binary8p4se, UInt8(c)) for c in 0:255]
    safe = violations = 0
    for a in codes, b in codes
        da, db = Exp(Binary8p4se, RNE_SN, a), Exp(Binary8p4se, RNE_SN, b)
        (isnan(decode(da)) || isnan(decode(db))) && continue
        codedistance(da, db) > 2κ || continue
        safe += 1
        (order_key(fast(a)) < order_key(fast(b))) ==
            (order_key(da) < order_key(db)) || (violations += 1)
    end
    (safe, violations)
end
(κ, exhaustive, margin_audit(fast, κ)...)
```

```
(2.0, true, 49522, 0)
```

49,522 operand pairs clear the 2κ margin, and the approximate evaluator agrees
with the defined ordering on every one of them — zero violations, exhaustively.
Inside the margin, comparisons are genuinely undecidable at this κ; a search can
treat sub-margin comparisons as ties to expand, or escalate those few nodes to
the exact evaluator. Either way the pruning is *provably* sound, with κ measured
at registration rather than promised.

## see also

[Add an Operation](howto_add_operation.md),
[Benchmark Correctly](howto_benchmark.md),
[Internals Recipes](under_recipes.md).
