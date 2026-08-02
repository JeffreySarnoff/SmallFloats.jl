# Benchmarking SmallFloats.jl

This directory contains the reproducible performance suite for SmallFloats.jl.
The main entry point, [`benchmarking.jl`](benchmarking.jl), measures scalar
operations, projection modes, array kernels, table construction, sorting,
blocks, conversions, and packed storage, then writes a Markdown report.

Use this guide to regenerate the report, understand what each number measures,
and compare runs without accidentally benchmarking Julia's dispatcher or a
different operand distribution.

[Current report](benchmark_report.md) ·
[Published performance evidence](../docs/src/examples_performance.md) ·
[Benchmarking methodology](../docs/src/internals_benchmark.md)

## Quick start

Run commands from the repository root. The benchmark suite has its own Julia
environment in `benchmarking/Project.toml`.

Prepare or refresh that environment:

```sh
julia --project=benchmarking -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
```

Generate a candidate report without overwriting the checked-in baseline:

```sh
julia --project=benchmarking benchmarking/benchmarking.jl \
    benchmarking/benchmark_report.candidate.md
```

The suite is intentionally comprehensive and can take several minutes. Runtime
depends on the host, Julia version, thread count, and whether compilation caches
are warm. For rapid feedback, run the deadline-aware companion with an approximate
wall-clock budget:

```sh
julia --project=benchmarking benchmarking/faster_benchmarking.jl 30s \
    benchmarking/faster_benchmark_report.md
```

The duration accepts bare seconds or `ms`, `s`, `m`, and `h` suffixes. The fast
runner includes dependency loading, compilation, setup, sampling, and report
generation in its budget; only Julia process startup precedes its timer. It first
samples one case from every major area, adds broader coverage at 12, 30, and 60
seconds, and uses remaining time to refine completed measurements. An in-progress
compilation or table build cannot be interrupted, so the limit is approximate.
This representative report is deliberately not a replacement for the full report
contract when accepting or publishing a baseline.

To exercise the threaded ternary-kernel comparison, start Julia with more than
one thread:

```sh
julia --threads=auto --project=benchmarking benchmarking/benchmarking.jl \
    benchmarking/benchmark_report.threaded.md
```

The report header records the CPU, logical CPU count, Julia thread count, Julia
version, Chairmarks version, and whether Float128 paths were enabled. Keep that
header when sharing results.

## Output behavior

The final command-line argument is the Markdown output path. If it is omitted,
the script writes `benchmark_report.md` in the current working directory. The
parent directory must already exist, and an existing file at the destination is
replaced.

The generator writes Markdown only. The checked-in `benchmark_report.pdf`,
`domain_ops.csv`, and `safe_domain_ops.csv` are separate retained artifacts; the
current Julia generator does not update them. Do not assume their timestamp or
measurement context matches the Markdown report.

From a Julia session started at the repository root, the equivalent call is:

```julia
include("benchmarking/benchmarking.jl")
generate_report("benchmarking/benchmark_report.candidate.md"; seed=2026)
```

The default seed is 2026. It makes operand selection reproducible; it cannot
remove scheduler, frequency-scaling, thermal, or operating-system noise.

## Measurement contract

The harness enforces four rules before its numbers are worth reading:

- format types cross function barriers as type parameters, never as unresolved
  globals;
- operands are selected in Chairmarks' untimed setup, so generation cost is not
  charged to the operation;
- values vary at runtime, preventing constant folding;
- a specialization preflight aborts when paths that must be allocation-free
  allocate.

The last rule is deliberately narrower than “all arithmetic must allocate
nothing.” Exact selection operations and narrow-spread `Add`/`FMA` calls must be
allocation-free. Some arithmetic inputs legitimately escalate to MPFR because
their exponent spread exceeds the hardware carrier; those allocations are real
work and are reported rather than rejected.

If the preflight fails, fix the specialization or benchmark barrier before
interpreting any timing. The guide in
[Benchmark Correctly](../docs/src/internals_benchmark.md) shows the minimal
pattern and the common dynamic-dispatch failure mode.

## Read the report in this order

1. **Read the header.** Confirm host, Julia version, threads, Float128 setting,
   and Chairmarks version before comparing with another run.
2. **Choose the relevant section.** Scalar latency, bulk array throughput,
   table construction, sorting, and block operations answer different
   questions.
3. **Check the operand class.** A scalar operation's timing can change sharply
   when NaN, infinity, or out-of-domain inputs take short special rows.
4. **Read minimum, median, and allocations together.** A faster row that changed
   operand class or began allocating is not the same result.
5. **Prefer ratios within one run.** Absolute nanoseconds are host-specific;
   comparisons made under one process and one environment are more portable.

## What the columns mean

- **min** is the least interrupted observed time and the best estimate of the
  operation's lower-bound cost on that run.
- **median** shows the center of the measured samples and includes ordinary
  scheduler and cache variation.
- **allocs** is the median allocation count. Zero is expected for warm paths
  whose implementation contract is allocation-free; nonzero can be legitimate
  for MPFR escalation, table construction, blocks, or container creation.
- **per element** or **per lane** normalizes a bulk call. Compare it only when
  the array or block size in the row is the same.

The report prints minimum before median intentionally. Neither replaces the
other: use minimum to study the kernel and median to judge run-to-run stability.

## Scalar operand classes

Unary, binary, and ternary operations each appear under four operand classes.
They are ordered from the most domain-focused view to the uniform-code-point
view:

| Order | Report heading | Operand population | Best use |
|:---|---|---|---|
| 1 | Safe args | Finite operands inside the operation's safe domain | Compare the cost of doing in-domain work without NaN fast-row dilution |
| 2 | No NaN, Inf args | All finite operands, including zeros and subnormals | See the effect of finite but possibly out-of-domain inputs |
| 3 | No NaN args | Every code point except NaN; infinities remain | Isolate the contribution of the NaN operand row |
| 4 | All code points | Uniform sampling over the complete code space | Model the historical uniform-code-point workload, including specials |

“Safe args” is the best first table when asking how expensive an operation is
on inputs where it performs its main computation. It is not universally the
right workload model. If an application naturally contains special values or
out-of-domain inputs, compare against the table whose operand population
matches that application.

Eleven argument-restricted operations use explicit predicates from
`_SAFE_DOMAINS` in `benchmarking.jl`: `Sqrt`, `RSqrt`, `Log`, `Log2`,
`LogOnePlus`, `Recip`, `Divide`, `ArcSin`, `ArcCos`, `ArcCosh`, and `ArcTanh`.
Every other operation uses finite operand tuples whose defined oracle result is
not NaN. This oracle-derived fallback keeps newly registered operations from
silently inheriting an unrelated hand-written domain.

The middle classes require care. Removing NaN or infinity from the operands
does not remove NaN results: for example, a negative finite input to `Sqrt`
still takes an out-of-domain special row. Comparing all four tables shows how
much a uniform sweep is influenced by those rows.

## Other report sections

- **Core primitives** measures decode, ordering, classification, stepping, and
  projection over all code points.
- **Sensitivity studies** compares selected operations across formats and
  projection specifications.
- **Array kernels** measures warm table gathers and scalar compute loops per
  element.
- **Ternary bitwidth tiers** exposes eager, adaptive, compute, and threaded
  policy choices against scalar-loop baselines.
- **Sorting** compares the package's counting sort with Julia's comparison sort.
- **Table builds** separates cold construction from a warm cache hit; JIT
  compilation is pre-warmed while the table cache is evicted per cold sample.
- **Block and scaled operations** reports both total work and per-lane cost.
- **Conversions and packed storage** separates scalar conversion from bulk
  packing and unpacking.

Unless its note says otherwise, a non-scalar sampled section uses the complete
code-point pool, including NaN and infinities. Table construction enumerates its
input code space rather than sampling it.

## Compare two runs fairly

Keep these fixed whenever the goal is regression detection:

- package commit and benchmark script;
- Julia and Chairmarks versions;
- CPU model, power policy, and thermal conditions;
- Julia thread count and `SmallFloats_Float128` setting;
- report seed and operand class;
- operation, format, projection, and collection size.

Generate the candidate beside the baseline, then inspect both the metadata and
the changed rows:

```sh
diff -u benchmarking/benchmark_report.md \
    benchmarking/benchmark_report.candidate.md
```

Do not infer a regression from one noisy median. Look for a coherent shift in
minimum and median, rerun it, and check whether allocations or operand context
changed. For bulk kernels, compare throughput and total time together.

## Accept and publish a new baseline

When a candidate was generated under an intentional, recorded environment:

1. verify the report header and preflight outcome;
2. inspect every changed section, not only the expected row;
3. rerun surprising changes before accepting them;
4. replace `benchmarking/benchmark_report.md` with the accepted candidate;
5. update `docs/src/examples_performance.md` deliberately if the new evidence
   should appear in the maintained manual;
6. rebuild the documentation and PDF, then review their generated diffs.

The performance page is not automatically overwritten by the benchmark script.
That separation prevents an exploratory run from silently becoming published
documentation.

## Dyadic carrier microbenchmarks

[`benchmark_dyadics.jl`](benchmark_dyadics.jl) is a separate focused suite for
the exact dyadic carrier. It prints results to standard output and does not
participate in `generate_report`:

```sh
julia --project=benchmarking -O3 benchmarking/benchmark_dyadics.jl
```

Use it when changing dyadic layout or arithmetic kernels; use
`benchmarking.jl` for package-level performance evidence.
