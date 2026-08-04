# Function Tables and Array Kernels

## Function Tables

For pure specs, unary and binary operations are **finite functions** — 256 or 65 536
entries — so the kernel layer materializes them once per `(op, formats, ρ)` into a
locked cache (`Dict{TableKey, Memory{UInt8}}`, double-checked locking, builds outside
the lock) and serves every later array call as a gather: Shape-A, one load per
element, measured 0.13 ns/elem unary and 0.25 ns/elem binary. Tables are built
*through the scalar path*, so they inherit its bit-exactness; the suite asserts
table ≡ scalar over every entry.

Builds are **parallel** above `TABLE_BUILD_MIN_ENTRIES`, partitioned over the
outer code loop so each task writes a contiguous, disjoint span of the
preallocated `Memory`. Nothing about the cache changes: the build already ran
outside the lock, with a racing duplicate build documented as benign. Only pure
ρ is ever tabulated, `_scalar_code` holds no mutable state, and MPFR escalation
reaches `setprecision`/`setrounding` through their *function* forms, which are
`ScopedValue`-backed on Julia 1.12 and therefore task-local — the three facts the
parallelism rests on, and the reason the package floors at 1.12.

The fill loops are separate functions (`_fill_unary!`, `_fill_binary!`,
`_fill_ternary!`) taking `Val(op)` as an **argument**, and that is load-bearing
rather than tidiness. `_build_*` receives `op` as a runtime `Symbol`, so a
`Val(op)` constructed in the same function body is type-unstable and every
entry pays a dynamic dispatch; passing it across a barrier makes `op` a type
parameter of the callee and specializes the whole scalar path. Measured on a
64 K-entry `Multiply` table: **445 µs → 64 µs**.

Ternary (`FMA`, `FAA`, `Clamp`) is a finite function too — 2^(K1+K2+K3) entries —
but that count spans four orders of magnitude across the 3–16 bitwidth range (512 B
at K=3, 16 MiB at K=8), so one policy doesn't fit the whole range. A separate
`TernaryKey → TernaryEntry` cache (`_ternary_table_for`, in `tables.jl`) tiers by
Σ bitwidth:

- **Eager** (≤ 18 bits, all `K ≤ 6` combinations, ≤ 256 KiB): builds and caches
  on the first array call.
- **Adaptive** (≤ 21 bits, the `K = 7` band, up to 2 MiB): accumulates a
  per-signature element count across calls and builds only once a signature has
  processed enough elements to amortize the build; a byte-bounded LRU eviction
  (`TERNARY_CACHE_BYTES`) guards against many hot signatures coexisting.
- **Compute** (`K = 8`, 16+ MiB — a table is never worth it): `vmap!` runs
  Shape-B, the fully specialized scalar pipeline per element.

Every ternary table entry, eager or adaptive, is still built *through the scalar
path* — the tiering changes when/whether the cache exists, never what it contains.
Stochastic calls of any arity always take Shape-B, with the RNG resolved once per
array rather than per element.

### Shape-B threads at every arity

`Threads.@threads` is a property of the **pure-ρ compute loop**, not of the
ternary tier that first needed it. `_vmap_compute!` covers unary and binary as
well, gated by `THREADED_KERNELS` and `THREAD_MIN_ELEMS` through the single
`_should_thread` predicate. Above `K = 8` this is the case that matters: a
binary table would be `2^(K1+K2)` entries, `table_for` declines, and Shape-B is
the only array path the format has — measured at roughly 6× on 8 threads for a
65 536-element `Binary16p8se` `Add`.

Stochastic ρ stays sequential, and that requirement is carried by *which
function you are in* rather than by a branch: `_vmap_scalar!` keeps the
stochastic traffic and never threads, because one rng stream is reproducible
only in index order. The suite pins threaded and sequential results as
**identical code points in identical order**, not as agreement within a
tolerance — a threading change that altered a result is a defect no timing would
reveal.

## Sorting

Ordering runs on **integer order keys**: a sign-magnitude fold into an unsigned
type wide enough for the format's `2^K + 1` keys (`UInt16` at K ≤ 8, wider above),
monotone with the total order. Key `0` is reserved for the single NaN, which the
draft orders below −Inf (§4.12.1); every datum key is therefore ≥ 1.
Same-format `TotalOrder`, `isless`, and the numeric comparisons are key
comparisons (~1 ns); since a format has at most `2^K + 1` distinct keys, vectors
sort with an **O(n) counting sort** installed via `Base.Sort.defalg` (forward and
reverse orderings; anything exotic falls back to the stock algorithm).

## Source and gates

`src/tables.jl` owns table keys, construction, cache policy, and ternary tiers;
`src/kernels.jl` owns gather and scalar-loop execution. A change is complete
only when table entries agree with scalar results over their full affordable
domain, cold and warm behavior are measured separately, stochastic calls
bypass pure tables, and cache byte accounting remains correct.

## Continue through the implementation

[Encoding and Decoding](internals_encoding_decoding.md),
[Oracle and Rigor Classes](internals_oracle.md),
[Verification Sessions](examples_verification.md).
