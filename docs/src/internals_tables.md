# Function Tables and Array Kernels

## Function Tables

For pure specs, unary and binary operations are **finite functions** — 256 or 65 536
entries — so the kernel layer materializes them once per `(op, formats, ρ)` into a
locked cache (`Dict{TableKey, Memory{UInt8}}`, double-checked locking, builds outside
the lock) and serves every later array call as a gather: Shape-A, one load per
element, measured 0.27 ns/elem unary and 0.5 ns/elem binary. Tables are built
*through the scalar path*, so they inherit its bit-exactness; the suite asserts
table ≡ scalar over every entry.

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
  Shape-B, the fully specialized scalar pipeline per element, optionally split
  across `Threads.@threads` for long enough arrays (each ternary draw is
  independent under a fixed, non-stochastic ρ, so lanes cannot interact).

Every ternary table entry, eager or adaptive, is still built *through the scalar
path* — the tiering changes when/whether the cache exists, never what it contains.
Stochastic calls of any arity always take Shape-B, with the RNG resolved once per
array rather than per element.

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
