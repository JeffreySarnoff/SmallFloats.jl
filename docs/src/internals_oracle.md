# Oracle and Rigor Classes

Every operation's defined result is computed by `ωeval`, which returns one of five
result kinds; `apply_op` fast-splits the common one and finishes the rest:

| kind | meaning | finished by |
|:---|---|---|
| `Float64` | exact (specials; representable arithmetic) | direct `project` |
| `Dyadic` | exact at rung 3: an `Int128` significand and an `Int64` exponent, `isbits` | direct `project` (dyadic carrier) |
| `Float128` | exact by **width analysis** | direct `project` (Float128 carrier) |
| `StickyF` | wide-spread `FMA`/`FAA` tail: head value (`Float64` or `Float128`) + tail sign | direct `project` with `sticky` set — no allocation |
| `BigExactF` | exact at a precision **derived from the operands** — `bigprec`, not a constant (wide-spread tail for `Add`; the near-impossible `FAA` distillation miss) | `project` on `BigFloat` |
| `Enclose128F` | correctly-rounded Float128 **bracket** | sticky agreement, MPFR fallback |
| `EncloseF` | MPFR directed enclosure `f(prec)`, optional Float128 pre-filter `fq`, optional eager Float64 estimate `yd` | three-stage: `yd` → `fq` → interval protocol |

## The Dyadic↔Rational bridge

The dyadic carrier converts to and from `Rational` **exactly**, and that bridge
is the cleanest way to reason about a rung-3 value:

```julia
using SmallFloats.DyadicNumbers: dyadic_to_rational, rational_to_dyadic, isdyadic

dyadic_to_rational(x)          # Rational{BigInt}, exact — a Dyadic IS S·2^Q
rational_to_dyadic(3 // 4)     # exact, or throws
isdyadic(1 // 3)               # false — no Dyadic represents it
```

Three properties are worth knowing. The infinities convert (`±1//0`, matching
`Rational{BigInt}(Inf)`) and NaN does not, because `Rational` has no NaN slot.
A non-dyadic rational is **refused rather than rounded** — rounding it here would
be a rounding outside `project`. And the round trip is a law about *values*, not
fields: `Dyadic`'s significand is deliberately unnormalized, so `6·2⁻²` and
`3·2⁻¹` are the same value and round-trip to the canonical one.

The full design, with every edge case and the three laws, is in
`other/dyadic_rational.md`.

## The two rigor classes

Two **rigor classes** govern every non-`Float64` path, and their arguments are never
mixed:

**Class R (unconditional)** rests on two facts that hold without any accuracy
assumption:

- **Width analysis.** Sums of decoded datums are *exactly representable* in
  `Float128` whenever operand bits + exponent spread fit 113 bits — checked in
  advance by integer exponent arithmetic (`Add` at ΔE ≤ 100, `FMA` ≤ 92, `FAA`
  span ≤ 98). Beyond the threshold, `Add` escalates to the exact MPFR path — at a
  precision **derived from the operands** by `bigprec`, not the retired 2200-bit
  constant, which was ample at K ≤ 8 and insufficient for 50 of the 504 formats
  (gate G2 measures this) — while
  `FMA`/`FAA` take a non-allocating **sticky-head** shortcut: past that spread the
  smaller term is provably too small (by construction of the threshold) to affect
  anything but the tail direction of the larger one, so the result is
  `StickyF(head, sign)` — no `BigFloat` involved. `FAA`'s three-term case runs a
  bounded Float128 2sum-distillation (Priest-style, ≤ 6 sweeps) to find that
  head/tail split directly; the residual `BigExactF` MPFR fallback exists only for
  the near-impossible case the distillation doesn't converge.
- **IEEE correct rounding.** Division and `sqrt` are correctly rounded at *every*
  binary width, by mandate. `Divide`/`Recip` therefore use the **Float64**
  quotient directly: it is within half an ulp of truth, so it serves as
  `EncloseF`'s eager `yd` estimate with no Float128 arithmetic on the path at all.
  `Sqrt`/`RSqrt` use the **Float128** CR result: an inexact nearest-CR value `q`
  brackets the truth in the *open* interval `(prevfloat(q), nextfloat(q))`.
  Exactness itself is detected by an `fma` residual test.

**Class E (envelope-conditional).** Faithful-but-not-CR evaluations stand in for an
enclosure only inside a generous envelope, resolved by the two-sided sticky gate.
Two stages, cheapest first:

- *Float64 stage:* for operations whose Float64 libm is faithful (≤ 1 ulp ≈ 2⁻⁵²
  relative — the exp/log families, the hyperbolics, forward trig inside the
  |x| ≤ 10¹⁵ reduction window, `atan`, `asinh`, the softplus composition), the
  eager estimate `yd` carries envelope `E = |yd|·2⁻⁴⁵`, ≥ 2⁷ slacker than any
  faithful-libm error (measured margin on this machine: ≥ 2⁶·⁶).
- *Float128 stage:* libquadmath's estimate `y = fq()` carries `E = |y|·2⁻⁹⁰`, at
  least 2¹⁸ slacker than any published libquadmath bound.

In both stages, if the sticky-projected endpoints agree, that code point is the
answer; if not, the next stage (ultimately the MPFR ladder) decides. An envelope
failure can therefore only cost speed, never correctness — unless both endpoints
agree *and* the envelope is wrong, which the differential-build tests rule out
empirically by building every standard table twice (Float128-first and pure-MPFR)
and byte-diffing, and which the exhaustive oracle cross-check re-verifies per
operation against the 3072-bit protocol.

## The interval protocol

**The interval protocol** (`project_interval`) is the termination backbone: evaluate
the MPFR enclosure at precision `p`; if `lo == hi` the value is exactly
representable — project it; otherwise project `lo` with `sticky = +1` and `hi` with
`sticky = −1`; agreement (projection is monotone at fixed `R`) yields the answer;
disagreement doubles `p`, clamped to the `maxprec` ceiling (**derived from the
format**, `max(4096, bigprec(T) + 64)` — a flat 4096 was ample at K ≤ 8 and could
not decide `ArcCosPi` at `Binary15p2ue` under a directed or stochastic rule,
honored exactly even when it is not a power-of-two multiple of the 256-bit start).
Termination requires that the enclosure not be chasing a value the grid can
actually hit — which is why the π-scaled operations carry **Niven peels**: for
dyadic arguments, `tan(πr)` takes rational values only at the quarter-integers
(±1) and `atan2/π` only on the diagonals (±¼, ±¾); those cases are answered
exactly before any enclosure is built, and Niven's theorem proves the peel set
complete.

## Source and gates

The operation registry and ω evaluation live in `src/oracle.jl`; exact dyadic
carriers and their rational bridge live in `src/dyadic.jl`, with carrier-rung
selection in `src/carriers.jl`. Changes here must preserve enclosure containment,
termination, and agreement with a wider independent path. The gate and tier
files under `test/` record whether each check is exhaustive or sampled.

## Continue through the implementation

[Encoding and Decoding](internals_encoding_decoding.md),
[Function Tables and Array Kernels](internals_tables.md),
[Add an Operation](internals_add_operation.md).
