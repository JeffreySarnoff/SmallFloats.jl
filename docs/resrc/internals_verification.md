# Verification Strategy

## What Is Verified

The value sets are small enough that sampling is never necessary, so the suite
enumerates — ≈ 8.9 M assertions in all:

- formats against an independent draft transliteration (14 679);
- ordering over all 2.5 M same-format pairs plus Next-op edge tables (7.6 M);
- every unary operation on every input against a 3072-bit protocol run; divide
  and the ternaries exhaustively;
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
*ratios*, not just absolutes, because dispatch cost varies with call shape (a dynamic
keyword call costs ~1 µs; a dynamic positional call far less; six unresolved interior
sites cost six times one).

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

## see also

[Tables, Kernels & Sorting](internals_tables.md),
[Benchmark Correctly](internals_benchmark.md),
[Verify Custom Code](internals_verify_custom.md).
