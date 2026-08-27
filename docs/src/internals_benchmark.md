# Benchmark Correctly

The benchmark doctrine is the record of four measurement post-mortems. The
first two are about the *closure*: a closure over a non-`const` global
measures Julia's dispatch machinery as well as the code under test, and that
distortion changes ratios, not only absolute timings, because dispatch cost
varies with call shape. The other two are about the *harness*, and they are
below. Treat any quoted timing as a record of a particular format, policy,
machine, and benchmark harness.

## The rules

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

## Two ways the harness itself can lie

- **One variant per process, alternating, or nothing.** A harness that
  compiles several variants in one process is not a measurement. It reported
  an `add_sticky_dy` rewrite as a 1.87× *win*; alternating single-variant
  processes reversed the same comparison into a 31% *loss*. A related form:
  timing two kernels sequentially in one process let the first perturb the
  second into a 39% phantom regression on code that had not changed.
- **A loop that overwrites its accumulator measures dead-code elimination.**
  `z = f(xs[i])` leaves every iteration but the last dead, and whether the
  loop survives depends on whether the compiler can prove the body pure — so
  it compares *elimination* between implementations rather than work.
  Measured: a pure kernel under that loop reported 8 ns for 4096 elements.
  Reduce into an accumulator and end with `Base.donotdelete`;
  `benchmarking/benchmark_dyadics.jl` shows the pattern on every loop.

## Set up a measurement that is actually measuring your code

The package's benchmark doctrine, in one snippet (needs the `benchmarking/`
environment for Chairmarks). Format types enter as **type parameters**;
operands come from Chairmarks' *untimed* `setup`; and if you retrieve
functions reflectively (`getfield(SmallFloats, op)`), pass them through an
argument barrier so they specialize:

```julia
using Chairmarks, SmallFloats, Random
using Statistics: median

function bench_add(::Type{T}) where {T<:Binary}          # T: type parameter, not a global
    pool = [SmallFloats.rawvalue(T, rand(UInt8)) for _ in 1:4096]
    @be (rand(pool), rand(pool)) (t -> Add(T, RNE_SN, t[1], t[2]))(_)
end

b = bench_add(Binary8p4se)
round(median(b).time * 1e9; digits=1), median(b).allocs
```

Record that result with the Julia version, CPU/thread configuration, source
revision, operand pool, and projection. The value is evidence for that setup;
it is not the package's scalar-Add contract.

!!! warning "Do not benchmark unresolved globals"
    If `T` comes from a non-`const` global, the result includes dynamic dispatch
    and cannot fairly compare projection, carrier, table, or compute paths. The
    shipped `benchmarking/benchmarking.jl` checks specialization before it
    accepts a result; your benchmark should do the same.

## See also

[Verification Strategy](internals_verification.md),
[Verify Custom Code](internals_verify_custom.md),
[Verification Sessions](examples_verification.md) — whose
*Benchmarking without measuring the dispatcher* is the complete version of the
snippet above, with the measurement post-mortems that produced it.
