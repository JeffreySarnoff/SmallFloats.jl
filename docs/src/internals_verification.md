# Verification Strategy

The doctrine in one sentence: **enumerate rather than sample wherever the
input space allows it, and where it does not, say "sampled" in so many
words.** The formats are finite, so most correctness questions here are
theorems checkable by exhaustion rather than statistics — and a tier the
caller asks for is honoured, never downgraded, because a gate that quietly
runs less than it was told to is worse than no gate.

## What Is Verified

The suite combines exhaustive finite-domain gates with explicitly sampled axes.
The final roll-call is the authoritative record for a run: it names the selected
`quick`, `default`, or `release` tier, the units compared by every gate, and
whether each gate was exhaustive or sampled. Major coverage includes:

- formats against an independent draft transliteration (14 679);
- ordering over all 2.5 M same-format pairs plus Next-op edge tables (7.6 M);
- unary, divide, and ternary operations against high-precision reference paths,
  with the exact format/input coverage reported by their gates;
- stochastic R-sweeps with directed-asymptote pins;
- table ≡ scalar over every entry, including the ternary tiers (eager and
  adaptive) against the scalar path;
- the sticky-head `FMA`/`FAA` escalation against the MPFR reference across every
  rounding-mode family and adversarial cancellation cases;
- blocks against a from-scratch reference composition;
- Float128 carrier ≡ Float64 carrier, and Float128-first ≡ MPFR differential
  builds;
- the mask rounding core ≡ the generic core over datums and reachable
  sums/products at boundary stochastic budgets N ∈ {45, 60};
- packed round-trips, and κ/conformance behavior.

Deterministic **specialization regressions** (concrete inferred return types at the
public entry points, zero warm-path allocation) stand in for timing assertions.

## The Approach to Benchmarking

Correctness is asserted here; timing methodology belongs to [Benchmark
Correctly](internals_benchmark.md), which records the four measurement
post-mortems and the rules `benchmarking/benchmarking.jl` enforces
structurally. The division matters: a gate that fails means a wrong answer, a
benchmark that misleads means a wrong decision, and conflating them is how a
harness bug gets filed as a performance regression.

## Deliberate limitations

No implicit cross-format arithmetic exists. Arithmetic with an ordinary Julia
number promotes to the format's public promotion carrier, which may be wider
than `Float64`; callers who want a particular result format must name it and a
projection explicitly. There is no in-place packed arithmetic. Threading is
opt-in for pure Shape-B compute loops at every arity, only above the configured
size cutoff and when `Threads.nthreads() > 1`; stochastic paths remain
sequential to preserve RNG-stream order.
`Irrational`/`Rational` inputs to `Convert` are rejected rather than
double-rounded silently. The `Float128` machinery never changes results — disabling
it (`SmallFloats_Float128=disable`) is a tested no-op semantically.

## Reading a verification result

Treat the roll-call label as part of the result. **Exhaustive** means every
member of the stated finite domain was checked. **Sampled** means the report
must also state the generator, seed, sample count, and why that sample addresses
the risk. A pass without its domain and method is not a portable claim.

The gate files under `test/` own correctness assertions; benchmark scripts own
timing methodology. Documentation examples are checked separately so a green
package test cannot conceal stale printed output.

## See also

[Function Tables and Array Kernels](internals_tables.md),
[Benchmark Correctly](internals_benchmark.md),
[Verify Custom Code](internals_verify_custom.md).
