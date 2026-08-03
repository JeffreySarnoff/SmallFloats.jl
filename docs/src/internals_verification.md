# Verification Strategy

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

Recorded after two measurement post-mortems: a benchmark closure over any non-`const`
global measures Julia's dispatch machinery, not the code under test — and it distorts
*ratios*, not just absolutes, because dispatch cost varies with call shape.

The rules the shipped `benchmarking/benchmarking.jl` enforces structurally:

- format types enter as type parameters, never as globals;
- operands come from untimed setup;
- functions retrieved reflectively pass through argument barriers to specialize;
- a preflight aborts the run if warm scalar paths allocate — including the
  wide-spread `FMA`/`FAA` sticky-head path.

The table-build section reports both the cold build (cache evicted per sample) and
the steady-state warm cache hit, since callers amortize the former through the
latter. Vary one binding per variant; verify specialization before believing a
number.

## Deliberate limitations

No implicit cross-format arithmetic (promotion is to `Float64`, explicitly). No
in-place packed arithmetic. Threading is opt-in and narrow: only the untabled
ternary (`K = 8`) compute kernel threads, and only above a size cutoff and when
`Threads.nthreads() > 1`; every other kernel is single-threaded.
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

## Continue through the implementation

[Function Tables and Array Kernels](internals_tables.md),
[Benchmark Correctly](internals_benchmark.md),
[Verify Custom Code](internals_verify_custom.md).
