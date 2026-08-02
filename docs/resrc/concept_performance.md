# Performance Model

Performance advice for SmallFloats.jl is scattered across the manual,
the cheat sheet, and the technical examples because it applies at every
layer — construction, arithmetic, arrays, storage. This page pulls all of it
into one spine: the handful of decisions that determine whether your code
runs at scalar speed (tens of nanoseconds) or falls off a cliff into
microsecond dynamic dispatch.

## Pass formats statically

Every scalar entry point in the package — `Add`, `project`, a constructor —
fully specializes when the format type is known at compile time: through a
`const` binding, a type parameter, or an ordinary function argument. Under
that condition, a scalar `Add` runs at roughly 18–26 ns and `project` at
roughly 13 ns, with zero allocations.

The moment a format type is read from a **non-`const` global**, Julia can no
longer resolve the method at compile time, and every call pays for dynamic
dispatch instead — roughly 1 µs for a keyword call, a difference of nearly
two orders of magnitude for the identical computation:

!!! perf "The 60× benchmarking slowdown"
    The same benchmark, run with the format type `T` read from a
    non-`const` global instead of passed as a type parameter, measures
    around 1 µs — Julia's dynamic keyword dispatch overhead, not this
    package's arithmetic. Two real project post-mortems trace their
    "SmallFloats is slow" reports to exactly this mistake. The shipped
    `benchmarking/benchmarking.jl` asserts zero warm-path allocation before
    it believes any number it produces, and your own benchmarks should do
    the same:

    ```julia
    using Chairmarks, SmallFloats, Random
    using Statistics: median

    function bench_add(::Type{T}) where {T<:Binary}          # T: type parameter, not a global
        pool = [rawvalue(T, rand(UInt8)) for _ in 1:4096]
        @be (rand(pool), rand(pool)) (t -> Add(T, RNE_SN, t[1], t[2]))(_)
    end

    b = bench_add(Binary8p4se)
    (round(median(b).time * 1e9; digits=1), median(b).allocs)
    ```

    ```
    (16.3, 0.0)          # ns per full scalar Add, zero allocations
    ```

The fix, when a format genuinely has to come from a runtime value, is one
function barrier: write `f(::Type{T}, …) where {T}` and call into it once
the type is known, and everything inside specializes at full speed again.

Format operands entering `Chairmarks`-style benchmarks specifically must
come from the untimed `setup` phase, and if you retrieve an operation
function reflectively (`getfield(SmallFloats, op)`), pass it through an
argument barrier so it specializes too — the same discipline that makes the
benchmark trustworthy also makes ordinary calling code fast.

## Convenience forms are free at the initial default

`x + y`, `Exp(x)`, and `T(2.1)` all read the session default projection
through a speculation guard rather than a dynamic lookup. While the default
holds its initial value, the guard lets these calls compile against a
constant, so they are allocation-free with concretely inferred results — a
property pinned in the test suite, not an incidental benchmark result. The
moment you change the default, these same calls cross a function barrier
instead: one dynamic dispatch per call, with everything inside that barrier
still fully specialized. Code that must stay insensitive to whatever the
session default happens to be should name its projection explicitly —
`Add(T, ρ, x, y)` with a `const` `ρ` — rather than rely on the convenience
spelling in a hot loop.

## Bulk work belongs in array calls

The table-gather kernels that back array operations run roughly 50× faster
than the scalar path per element, because after the first call for a given
`(op, formats, ρ)` specialization, every later element is a single table
lookup rather than a full evaluation. That first call pays a one-time table
build: roughly 0.4 ms for a unary table, tens of milliseconds for an 8×8
binary table, up to a few milliseconds for a 2 MiB ternary table. Benchmark
warm calls separately from the first cold call, or the build cost will
dominate a measurement that is supposed to be about steady-state throughput.
Once warm, measured throughput is around 0.27 ns/element for unary gathers
and 0.5 ns/element for binary gathers.

### Ternary tiers scale with bitwidth

Ternary operations (`FMA`, `FAA`, `Clamp`) ride the same table-gather
mechanism whenever the combined operand bitwidth keeps the resulting table
affordable, and the package picks the tier automatically — no action needed
on your part:

- **Eager** (up to 256 KiB; every all-`K ≤ 6` signature): built on the first
  array call, exactly like a unary or binary table.
- **Adaptive** (up to 2 MiB; the `K = 7` band): built only once a signature
  has processed enough elements to earn its build, held in a byte-bounded,
  LRU-evicted cache — so a signature used once in passing doesn't pay for a
  table it will never reuse.
- **Compute** (`K = 8`; a 16 MiB table stops being a cache win): the scalar
  pipeline runs per element instead, optionally threaded for long arrays
  (roughly 4× at 4 threads).

Every table entry, eager or adaptive, is built through the exact scalar
path, so a table lookup and the equivalent scalar call are bit-identical by
construction — the speed comes with no accuracy trade at all.

## Stochastic array calls are always per-element

Deterministic array operations use cached tables; stochastic ones cannot,
because each element needs its own independent random draw. Stochastic
array calls always run the scalar pipeline once per element, consuming one
draw per projection. Pass an explicit `rng` when you need the result
reproducible — the array and `!` forms always use whatever RNG you supply,
so this is the one lever available for controlling a stochastic array call's
output exactly.

## Memory: `PackedVector` and `BlockVector`

When storage bandwidth matters more than direct byte-level access,
`PackedVector{F}` stores code points at `bitwidth(F)` bits per element
rather than rounding up to a whole byte or word — a `Binary5p2se` vector at
5 bits/element instead of 8. It behaves as a full `AbstractVector{F}` for
indexing, `collect`, and iteration, and `vmap` accepts it directly,
unpacking cache-friendly tiles internally rather than materializing the
whole array. The governing rule is *store packed, compute unpacked*: there
is deliberately no in-place packed arithmetic, because computing directly on
sub-byte-packed bits would give up more in kernel complexity than it could
ever save in bandwidth. `BlockVector` is the analogous structure for many
same-shape `Block`s, holding them in a structure-of-arrays layout instead of
an array of individually-boxed blocks.

`table_bytes()` reports the current cache footprint across unary, binary,
and ternary tables alike; `empty_tables!()` resets it, which is useful both
for isolating a benchmark from a previous session's warm tables and for
freeing memory in a long-running process that has touched many format
specializations.

## Sorting: O(n) counting sort

Sorting is special-cased rather than falling through to Base's generic
comparison sort. `Binary` values compare through integer order keys, and a
vector of `Binary` values sorts with an **O(n) counting sort** installed as
the default algorithm — roughly 8× the stock comparison sort at 64K
elements, with `rev=true` supported at the same cost. `sort(A)` simply picks
this path up automatically. P3109's total order places the single NaN first
(last under `rev=true`), unlike Base's ordering for ordinary floating-point
NaNs.

## Do not use `@fastmath`

Every number in the performance model above depends on the one-write-path
contract: exact math, then exactly one projection. `@fastmath` exists in
Julia to relax IEEE semantics for speed — reordering operations, assuming no
NaNs, dropping distinctions the standard is careful about — and every one of
those relaxations is exactly the kind of silent rounding shortcut this
package's whole design refuses to take. Applying `@fastmath` to code using
`Binary` values does not make the arithmetic faster in any meaningful way,
because the actual bottleneck the sections above address is dispatch and
table-gather behavior, not floating-point instruction scheduling — but it
can silently invalidate the exactness guarantee that makes the table-gather
speedup safe to rely on in the first place. If a computation is slow, the
fix is one of the items above: static format types, a function barrier,
array calls instead of scalar loops, or `PackedVector` for memory pressure —
never `@fastmath`.

## Go deeper

> Continue with **Benchmarking Without Fooling Yourself** (Understanding
> track) for the full benchmark doctrine — Chairmarks setup discipline,
> argument barriers for reflectively-retrieved functions, and the warm/cold
> table-build measurement split.
