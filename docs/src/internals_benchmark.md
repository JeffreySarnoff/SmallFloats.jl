# Benchmark Correctly

Recorded after two measurement post-mortems: a benchmark closure over any
non-`const` global measures Julia's dispatch machinery, not the code under
test — and it distorts *ratios*, not just absolutes, because dispatch cost
varies with call shape (a dynamic keyword call costs ~1 µs; a dynamic
positional call far less; six unresolved interior sites cost six times one).

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
(round(median(b).time * 1e9; digits=1), median(b).allocs)
```

```
(16.3, 0.0)          # ns per full scalar Add, zero allocations
```

!!! warning "The 60× benchmarking slowdown"
    The same call with `T` read from a non-`const` global measures ~1 µs — Julia's
    dynamic keyword dispatch, not this package. Two project post-mortems trace to
    exactly this mistake; the shipped `benchmarking/benchmarking.jl` asserts
    specialization (zero warm-path allocation) before it believes any number, and
    so should yours.

## Continue through the implementation

[Verification Strategy](internals_verification.md),
[Verify Custom Code](internals_verify_custom.md),
[Verification Sessions](examples_verification.md) — whose
*Benchmarking without measuring the dispatcher* is the complete version of the
snippet above, with the two measurement post-mortems that produced it.
