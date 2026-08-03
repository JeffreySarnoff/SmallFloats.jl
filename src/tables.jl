# ===== tables.jl — table lifecycle for pure-ρ specializations (design §7.3/§8.3, architecture §7)
#
# Any *pure* (non-stochastic) specialization of a unary or binary operation is a
# total function on 2^K / 2^(K1+K2) code points. The builder walks every input
# through the scalar path (oracle-backed), so a table entry IS the defined
# result — no residual correctness reasoning at use sites. Stochastic ρ is never
# tabulable (the result is a distribution over R); builders reject it loudly.
#
# Cache: value-keyed Dict under a ReentrantLock; kernels fetch via a @noinline
# getter once per array call (hoisted), then index a local `Memory`.
#
# ---- what K ≤ 16 changes here (implementextensions §4 Stage 5) ---------------
#
# **Two caches, not one.** A table entry is a *result code point*, so its width
# is `codeunit_type(fr)`. One `Dict` holding both widths would have to be typed
# `Dict{TableKey,Union{Memory{UInt8},Memory{UInt16}}}`, and then `get_table`
# returns a `Union` — which puts a type check inside every hot loop and costs
# the zero-allocation property the whole array design rests on. The cache is
# therefore selected by DISPATCH on the result representation (invariant 9),
# never by a branch on K.
#
# **Two budgets, answering different questions.** They are separate because
# their units are different and so are their failure modes:
#
#   · `TABLE_MAX_BITS` is *memory* — invariant 10. `2^ΣK` entries at K = 16 is
#     8 GiB for a binary table and 512 TiB for a ternary one. The budget's job
#     is to return `nothing` rather than attempt an impossible allocation, and
#     it is expressed in **bits** and compared as bits: computing `1 << ΣK` to
#     find out whether `1 << ΣK` is too large overflows silently at ΣK ≥ 64.
#   · `TABLE_EAGER_BITS` is *time*. Building a table costs one scalar trip per
#     entry, so entry count — not bytes — is what bounds it. **Measured**, not
#     assumed: ~1 µs/entry across the operation catalogue (a 65 536-entry K = 16
#     `Exp` table builds in 0.085 s), which makes a 2^24-entry table tens of
#     seconds of first-call latency rather than the fraction of a second the
#     largest table today costs. An earlier draft of this comment said ~200 µs
#     and concluded "an hour"; that figure is the *rigorous MPFR ladder* cost
#     from the golden capture, and the ordinary path almost never reaches the
#     ladder because the Float64 and Float128 filters resolve first. The
#     conclusion survives, three orders of magnitude smaller.
#
# **Conditional Shape A.** Where a budget declines, the kernels run the scalar
# path per element instead of refusing. That is safe for a stated reason, not by
# inspection: invariant 6 says a table entry is one trip through `_scalar_code`,
# and the fallback calls exactly that function per element. Declining to build a
# table changes speed and nothing else — never the answer. The suite asserts it
# (`test/gates_shape.jl`) rather than leaving it as a reading of this comment.

"""Value key for the table cache: op + format parameters + ρ parameters (all values,
so the cache itself is type-stable and non-allocating to query)."""
struct TableKey
    op::Symbol
    fr::NTuple{4,Int}          # result format (K, P, signed, extended)
    f1::NTuple{4,Int}          # first operand format
    f2::NTuple{4,Int}          # second operand format; (0,0,0,0) for unary
    rm::Symbol                 # rounding-mode type name
    sm::Symbol                 # saturation-mode type name
end

_fkey(::Type{<:Binary{K,P,S,E}}) where {K,P,S,E} = (K, P, Int(S), Int(E))
_rmname(ρ::ProjSpec) = nameof(typeof(roundingmode(ρ)))
_smname(ρ::ProjSpec) = nameof(typeof(saturationmode(ρ)))

# One cache per result code unit. Both are concrete in their value type, which
# is the entire point (see the header): `tablecache` is reached by dispatch on
# the result representation, so the type of what comes back is decided at
# compile time and the hot loop indexes a concrete `Memory`.
const TABLE_CACHE8  = Dict{TableKey,Memory{UInt8}}()
const TABLE_CACHE16 = Dict{TableKey,Memory{UInt16}}()
const TABLE_LOCK = ReentrantLock()

"""The unary/binary table cache holding results of format `fr`."""
@inline tablecache(::Type{<:Code8})  = TABLE_CACHE8
@inline tablecache(::Type{<:Code16}) = TABLE_CACHE16
@inline tablecache(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    tablecache(reptype(Binary{K,P,S,E}))

# ---- ternary tables (bitwidth-specific FMA/FAA/Clamp optimization) -----------
# A pure-ρ ternary specialization is a total function on 2^(K1+K2+K3) code
# points. That is 512 B at K=3 and 256 KiB at K=6 — cheap, cache-friendly, built
# eagerly on first array use — but 2 MiB at K=7 (built only for demonstrably hot
# signatures, LRU-evicted under a byte budget) and 16 MiB at K=8 (never built;
# the compute kernel with the sticky-head escalation serves that band).

"""Value key for a ternary table: op + result + three operand formats + ρ."""
struct TernaryKey
    op::Symbol
    fr::NTuple{4,Int}
    f1::NTuple{4,Int}
    f2::NTuple{4,Int}
    f3::NTuple{4,Int}
    rm::Symbol
    sm::Symbol
end
mutable struct TernaryEntry{U<:Unsigned}
    const tbl::Memory{U}
    tick::Int                  # LRU stamp (monotone; larger = more recent)
end

const TERNARY_CACHE8  = Dict{TernaryKey,TernaryEntry{UInt8}}()
const TERNARY_CACHE16 = Dict{TernaryKey,TernaryEntry{UInt16}}()
const TERNARY_USE   = Dict{TernaryKey,Int}()   # cumulative elements seen (adaptive band)
const TERNARY_TICK  = Ref(0)

"""The ternary table cache holding results of format `fr`."""
@inline ternarycache(::Type{<:Code8})  = TERNARY_CACHE8
@inline ternarycache(::Type{<:Code16}) = TERNARY_CACHE16
@inline ternarycache(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    ternarycache(reptype(Binary{K,P,S,E}))

"""K1+K2+K3 up to which a ternary table is built eagerly on first array call
(default 18 bits = 256 KiB — covers every all-K≤6 signature)."""
const TERNARY_EAGER_BITS = Ref(18)
"""K1+K2+K3 up to which a ternary table may be built adaptively once the
signature has processed `TERNARY_BUILD_ELEMS[]` elements (default 21 bits = 2 MiB
— the K=7 band). Above this, ternary ops always run the compute kernel."""
const TERNARY_ADAPTIVE_BITS = Ref(21)
"""Cumulative element count at which an adaptive-band signature earns its table."""
const TERNARY_BUILD_ELEMS = Ref(2_000_000)
"""Byte budget for the ternary cache; least-recently-used tables evict first."""
const TERNARY_CACHE_BYTES = Ref(32 * 1024 * 1024)

# ---- the two budgets ---------------------------------------------------------

"""
Hard ceiling on a single table, as `log2(bytes)` — the byte budget invariant 10
requires. 25 = 32 MiB.

Compared **as bits**. Computing `1 << ΣK` in order to decide whether `1 << ΣK`
is too large is exactly the bug the budget exists to prevent: at ΣK = 64 the
shift wraps to zero and the impossible allocation looks free.
"""
const TABLE_MAX_BITS = Ref(25)

"""
Largest table the package will *build*, as `log2(entries)`. 16 = 65 536 entries.

A bound on **time**, not memory: a table costs one scalar trip per entry, at a
measured ~1 µs/entry, so this band caps first-call latency at ~0.1 s while
2^24 entries would be tens of seconds — regardless of how comfortably 32 MiB
fits in RAM.

16 is not a guess — it is exactly the largest table the K ≤ 8 grid already
builds (a binary 8×8 table, 65 536 entries), so **no K ≤ 8 decision changes**
and G5 stays byte-identical by construction. It also admits the case that
matters most at wide K: a unary table for a K = 16 format is 2^16 entries,
the same count, now 128 KiB instead of 64 KiB because the entries are `UInt16`.
"""
const TABLE_EAGER_BITS = Ref(16)

@inline _sumK() = 0
@inline _sumK(F::Type{<:Binary}, rest::Vararg{Type{<:Binary}}) = bitwidth(F) + _sumK(rest...)
"""`log2` of the bytes a table over `Fs` with results in `fr` would occupy."""
@inline tablebits(::Type{fr}, Fs::Vararg{Type{<:Binary},N}) where {fr<:Binary,N} =
    _sumK(Fs...) + trailing_zeros(sizeof(codeunit_type(fr)))
"""Would this table fit the byte budget? (Memory, not build time.)"""
@inline within_byte_budget(::Type{fr}, Fs::Vararg{Type{<:Binary},N}) where {fr<:Binary,N} =
    tablebits(fr, Fs...) <= TABLE_MAX_BITS[]

@noinline function _refuse_over_budget(op::Symbol, ::Type{fr},
                                       Fs::Vararg{Type{<:Binary},N}) where {fr<:Binary,N}
    throw(ArgumentError(
        "a table for $op⟨$(formatname(fr)); $(join(map(formatname, Fs), ", "))⟩ would be " *
        "2^$(_sumK(Fs...)) entries of $(sizeof(codeunit_type(fr))) byte(s) = " *
        "2^$(tablebits(fr, Fs...)) bytes, over the 2^$(TABLE_MAX_BITS[])-byte budget. " *
        "Array kernels fall back to the scalar path automatically; `get_table` does " *
        "not, because its contract is to return a table"))
end

# ---- cache accounting --------------------------------------------------------
#
# Every consumer of the caches goes through these. That is not tidiness: with
# the caches split, a consumer that names one of them directly under-reports by
# exactly the half it forgot, silently — and one of the consumers is
# `conformance()`, whose whole job is to state truthfully what this package has
# specialized. Same failure class as §11 M9.

_bytes_of(d::Dict{TableKey,<:Memory}) =
    sum(t -> length(t) * sizeof(eltype(t)), values(d); init=0)
_bytes_of(d::Dict{TernaryKey,<:TernaryEntry}) =
    sum(e -> length(e.tbl) * sizeof(eltype(e.tbl)), values(d); init=0)

"""Total bytes currently held by every table cache."""
table_bytes() = lock(TABLE_LOCK) do
    _bytes_of(TABLE_CACHE8) + _bytes_of(TABLE_CACHE16) +
    _bytes_of(TERNARY_CACHE8) + _bytes_of(TERNARY_CACHE16)
end
"""Number of cached unary/binary specializations, both code units."""
table_count() = lock(() -> length(TABLE_CACHE8) + length(TABLE_CACHE16), TABLE_LOCK)
"""Number of cached ternary specializations, both code units."""
ternary_count() = lock(() -> length(TERNARY_CACHE8) + length(TERNARY_CACHE16), TABLE_LOCK)
"""Keys of every cached unary/binary specialization, in a deterministic order."""
table_keys() = lock(() -> vcat(collect(keys(TABLE_CACHE8)), collect(keys(TABLE_CACHE16))),
                    TABLE_LOCK)

"""
    table_policy(op, fr, f1[, f2[, f3]], ρ) -> (; shape, entries, bytes, reason)

Which shape an array call on this signature will take, and why — `:A` for the
table gather, `:B` for the per-element scalar path.

§4 Stage 5 item 6: "this signature is running the compute kernel" should be
*discoverable*, not inferred from a benchmark that came out slower than expected.
Reads the same predicates the kernels do, so it cannot drift from them.
"""
function table_policy(op::Symbol, ::Type{fr}, Fs::Vararg{Any}) where {fr<:Binary}
    ρ = last(Fs)
    fs = Base.front(Fs)
    bits = _sumK(fs...)
    entries = bits >= 63 ? typemax(Int) : 1 << bits
    bytes = tablebits(fr, fs...) >= 63 ? typemax(Int) : 1 << tablebits(fr, fs...)
    reason =
        isstochastic(ρ) ? "stochastic ρ is a distribution over R, never a table (design §5.4)" :
        !within_byte_budget(fr, fs...) ? "over the 2^$(TABLE_MAX_BITS[])-byte budget" :
        length(fs) == 3 ?
            (bits <= TERNARY_EAGER_BITS[] ? "ternary eager band" :
             bits <= TERNARY_ADAPTIVE_BITS[] ? "ternary adaptive band: needs $(TERNARY_BUILD_ELEMS[]) elements first" :
             "beyond the ternary adaptive band") :
        bits <= TABLE_EAGER_BITS[] ? "within the 2^$(TABLE_EAGER_BITS[])-entry build band" :
                                     "over the 2^$(TABLE_EAGER_BITS[])-entry build band"
    granted = !isstochastic(ρ) && within_byte_budget(fr, fs...) &&
              (length(fs) == 3 ? bits <= TERNARY_ADAPTIVE_BITS[] : bits <= TABLE_EAGER_BITS[])
    (; shape = granted ? :A : :B, entries, bytes, reason)
end

"""Drop every cached table and adaptive counter (they rebuild lazily on next use)."""
empty_tables!() = lock(TABLE_LOCK) do
    empty!(TABLE_CACHE8); empty!(TABLE_CACHE16)
    empty!(TERNARY_CACHE8); empty!(TERNARY_CACHE16); empty!(TERNARY_USE)
    nothing
end

# One table entry = one trip through the scalar path. Convert is the sole op with
# no ω-semantics (registry group :conv): it is a bare projection of the decoded
# operand, so it bypasses apply_op. R = 0 is safe: stochastic ρ never reaches here.
#
# Not restricted to `Float64` operands: `project` is carrier-generic (§1 C10), so
# a `Convert` table is buildable for a rung-2 or rung-3 format today, and it
# would be arbitrary to refuse one. Every other operation reaches `apply_op`,
# which refuses a wide carrier by method until Stage 6 — so the restriction
# lands where it is true instead of one layer above it.
@inline function _scalar_code(op::Val{name}, fr::Type{<:Binary}, ρ::ProjSpec, xs...) where {name}
    name === :Convert ? codepoint(project(fr, ρ, xs[1])) :
                        codepoint(apply_op(op, fr, ρ, 0, xs...))
end

# Every datum of an operand format, indexable by `code + 1`. The `TableDecode`
# row is the constant tuple the K ≤ 8 builders already used; the `ComputeDecode`
# row materializes the same values for a wide operand, which has no such tuple
# (invariant 10) but can still appear inside an affordable table — a 7×9 binary
# signature is 2^16 entries and perfectly buildable.
@inline _operand_datums(::Type{F}) where {F<:Binary} = _opdat(decodepolicy(F), F)
@inline _opdat(::TableDecode, ::Type{F}) where {F<:Binary} = _decode_table(F)
@inline _opdat(::ComputeDecode, ::Type{F}) where {F<:Binary} =
    [decode(rawvalue(F, codeunit_type(F)(c))) for c in 0:(1 << bitwidth(F)) - 1]

function _build_unary(op::Symbol, ::Type{fr}, ::Type{f1}, ρ::ProjSpec) where {fr<:Binary,f1<:Binary}
    K1 = bitwidth(f1)
    U1 = codeunit_type(f1)
    tbl = Memory{codeunit_type(fr)}(undef, 1 << K1)
    V = Val(op)
    for c in 0:(1 << K1) - 1
        tbl[c + 1] = _scalar_code(V, fr, ρ, decode(rawvalue(f1, U1(c))))
    end
    tbl
end

function _build_binary(op::Symbol, ::Type{fr}, ::Type{f1}, ::Type{f2},
                       ρ::ProjSpec) where {fr<:Binary,f1<:Binary,f2<:Binary}
    K1, K2 = bitwidth(f1), bitwidth(f2)
    U1 = codeunit_type(f1)
    tbl = Memory{codeunit_type(fr)}(undef, 1 << (K1 + K2))
    V = Val(op)
    X2 = _operand_datums(f2)
    for c1 in 0:(1 << K1) - 1
        x1 = decode(rawvalue(f1, U1(c1)))
        base = c1 << K2
        for c2 in 0:(1 << K2) - 1
            tbl[base + c2 + 1] = _scalar_code(V, fr, ρ, x1, X2[c2 + 1])
        end
    end
    tbl
end

"""
    get_table(op, fr, f1, [f2,] ρ) -> Memory{codeunit_type(fr)}

Fetch (building and caching on first use) the complete result table for the pure-ρ
specialization `op⟨fr; f1[, f2]⟩ under ρ`: entry `c + 1` (unary) or
`(c1 << K2) + c2 + 1` (binary) holds the result code point for those operand
code points. Throws for stochastic ρ, and throws when the table would exceed the
byte budget — its contract is to return a table, so it says so rather than
returning `nothing`. Callers that can fall back want `table_for`.

`@noinline` by design: kernels call this once per array operation and index the
returned table in their hot loop.
"""
function get_table end

"""Stochastic ρ is a distribution over R, never a table (design §5.4)."""
@inline _check_tabulable(ρ::ProjSpec) =
    isstochastic(ρ) && throw(ArgumentError("stochastic ρ $ρ is not tabulable (design §5.4)"))


# Double-checked pattern: probe under lock, build OUTSIDE the lock (builds may run
# MPFR escalations), insert under lock; a racing duplicate build is benign and rare.
# Written once here so the unary and binary fetches cannot acquire the lock, probe,
# or insert differently from one another.
function _cached_table(::Type{fr}, key::TableKey,
                       build::F)::Memory{codeunit_type(fr)} where {fr<:Binary,F}
    cache = tablecache(fr)
    t = lock(() -> get(cache, key, nothing), TABLE_LOCK)
    t !== nothing && return t
    built = build()
    lock(() -> get!(cache, key, built), TABLE_LOCK)
end

@noinline function get_table(op::Symbol, ::Type{fr}, ::Type{f1},
                             ρ::ProjSpec)::Memory{codeunit_type(fr)} where {fr<:Binary,f1<:Binary}
    _check_tabulable(ρ)
    within_byte_budget(fr, f1) || _refuse_over_budget(op, fr, f1)
    key = TableKey(op, _fkey(fr), _fkey(f1), (0, 0, 0, 0), _rmname(ρ), _smname(ρ))
    _cached_table(fr, key, () -> _build_unary(op, fr, f1, ρ))
end
@noinline function get_table(op::Symbol, ::Type{fr}, ::Type{f1}, ::Type{f2},
                             ρ::ProjSpec)::Memory{codeunit_type(fr)} where {fr<:Binary,f1<:Binary,f2<:Binary}
    _check_tabulable(ρ)
    within_byte_budget(fr, f1, f2) || _refuse_over_budget(op, fr, f1, f2)
    key = TableKey(op, _fkey(fr), _fkey(f1), _fkey(f2), _rmname(ρ), _smname(ρ))
    _cached_table(fr, key, () -> _build_binary(op, fr, f1, f2, ρ))
end

"""
    table_for(op, fr, f1[, f2], ρ) -> Union{Nothing,Memory{codeunit_type(fr)}}

The kernel-facing gate for unary and binary specializations: the table if policy
grants one, `nothing` if the caller should run the scalar path per element.

Separate from `get_table` on purpose — **one name per question.** `get_table`'s
contract is "return the table", so it throws when it cannot honour that, and
that is what the suite, `conformance` and the precompile workload want.
`table_for` asks the different question "should there be a table at all", and
answers `nothing` without prejudice. Its `Union` return costs nothing because
kernels call it once per array operation and branch outside the loop.
"""
@noinline function table_for(op::Symbol, ::Type{fr}, ::Type{f1},
                             ρ::ProjSpec)::Union{Nothing,Memory{codeunit_type(fr)}} where {fr<:Binary,f1<:Binary}
    isstochastic(ρ) && return nothing
    (_sumK(f1) <= TABLE_EAGER_BITS[] && within_byte_budget(fr, f1)) || return nothing
    get_table(op, fr, f1, ρ)
end
@noinline function table_for(op::Symbol, ::Type{fr}, ::Type{f1}, ::Type{f2},
                             ρ::ProjSpec)::Union{Nothing,Memory{codeunit_type(fr)}} where {fr<:Binary,f1<:Binary,f2<:Binary}
    isstochastic(ρ) && return nothing
    (_sumK(f1, f2) <= TABLE_EAGER_BITS[] && within_byte_budget(fr, f1, f2)) || return nothing
    get_table(op, fr, f1, f2, ρ)
end

# ---- ternary build / fetch / policy ------------------------------------------

function _build_ternary(op::Symbol, ::Type{fr}, ::Type{f1}, ::Type{f2}, ::Type{f3},
                        ρ::ProjSpec) where {fr<:Binary,f1<:Binary,f2<:Binary,f3<:Binary}
    K1, K2, K3 = bitwidth(f1), bitwidth(f2), bitwidth(f3)
    U1 = codeunit_type(f1)
    tbl = Memory{codeunit_type(fr)}(undef, 1 << (K1 + K2 + K3))
    V = Val(op)
    X2, X3 = _operand_datums(f2), _operand_datums(f3)
    for c1 in 0:(1 << K1) - 1
        x1 = decode(rawvalue(f1, U1(c1)))
        for c2 in 0:(1 << K2) - 1
            x2 = X2[c2 + 1]
            base = ((c1 << K2) | c2) << K3
            for c3 in 0:(1 << K3) - 1
                tbl[base + c3 + 1] = _scalar_code(V, fr, ρ, x1, x2, X3[c3 + 1])
            end
        end
    end
    tbl
end

_tkey(op::Symbol, fr, f1, f2, f3, ρ::ProjSpec) =
    TernaryKey(op, _fkey(fr), _fkey(f1), _fkey(f2), _fkey(f3), _rmname(ρ), _smname(ρ))

# Cache probe that also refreshes the LRU stamp — a hit must always count as a
# use, so both the direct fetch and the adaptive gate go through this one path.
function _ternary_probe(::Type{fr}, key::TernaryKey) where {fr<:Binary}
    lock(TABLE_LOCK) do
        e = get(ternarycache(fr), key, nothing)
        e === nothing ? nothing : (e.tick = (TERNARY_TICK[] += 1); e.tbl)
    end
end

# Insert under the byte budget, evicting least-recently-used ternary tables first.
# The new table is always inserted (even if alone it exceeds the budget: the caller
# earned it; the budget then simply holds this one table).
function _ternary_insert!(::Type{fr}, key::TernaryKey,
                          tbl::Memory{U}) where {fr<:Binary,U<:Unsigned}
    lock(TABLE_LOCK) do
        cache = ternarycache(fr)
        e = get(cache, key, nothing)
        e !== nothing && return e.tbl                        # racing duplicate build
        budget = TERNARY_CACHE_BYTES[]
        newbytes = length(tbl) * sizeof(U)
        # Eviction spans BOTH ternary caches — the byte budget is a statement
        # about memory held, and memory does not care which code unit holds it.
        while !isempty(cache) &&
              _bytes_of(TERNARY_CACHE8) + _bytes_of(TERNARY_CACHE16) + newbytes > budget
            victim = argmin(k -> cache[k].tick, keys(cache))
            delete!(cache, victim)
        end
        cache[key] = TernaryEntry{U}(tbl, TERNARY_TICK[] += 1)
        tbl
    end
end

"""
    get_table(op, fr, f1, f2, f3, ρ) -> Memory{UInt8}

Ternary form: entry `((c1 << K2 | c2) << K3) + c3 + 1` holds the result code
point. Builds unconditionally (policy lives in `_ternary_table_for`); pure ρ only.
"""
@noinline function get_table(op::Symbol, ::Type{fr}, ::Type{f1}, ::Type{f2}, ::Type{f3},
                             ρ::ProjSpec)::Memory{codeunit_type(fr)} where {fr<:Binary,f1<:Binary,f2<:Binary,f3<:Binary}
    _check_tabulable(ρ)
    within_byte_budget(fr, f1, f2, f3) || _refuse_over_budget(op, fr, f1, f2, f3)
    key = _tkey(op, fr, f1, f2, f3, ρ)
    t = _ternary_probe(fr, key)
    t !== nothing && return t
    _ternary_insert!(fr, key, _build_ternary(op, fr, f1, f2, f3, ρ))   # build outside the lock
end

# ---- Float32 carrier-exactness trait (enumeration-backed, memoized) ----------
# Answers: is `op` computed on Float32-decoded operands *exact* for every finite
# operand pair of (f1, f2)? When true, a Float32 intermediate is a legitimate
# exact carrier — every ρ (directed, stochastic) remains correct, because the
# projection engine receives the same value it would have from Float64. The
# authority is enumeration against a 300-bit oracle, not analytic bounds
# (measured contents of the gate: Multiply 118/120 same-format signatures,
# Add/Subtract 88/120 — pinned in the suite).
const F32_EXACT_CACHE = Dict{Tuple{Symbol,NTuple{4,Int},NTuple{4,Int}},Bool}()

_f32op(op::Symbol) = op === :Add ? (+) : op === :Subtract ? (-) :
                     op === :Multiply ? (*) : throw(ArgumentError(
                         "f32_exact is defined for Add/Subtract/Multiply, got :$op"))

"""
Largest `2^(K1+K2)` operand-pair count `f32_exact` will enumerate.

A bound on **time**, not memory: each pair costs two decodes and two 300-bit
`BigFloat` operations, so the pair count — not any byte figure — is what governs
it. The same distinction `TABLE_EAGER_BITS` draws against `TABLE_MAX_BITS`.

The floor is `2^16`, the largest K ≤ 8 signature (8 + 8), so **no answer that
existed before the K ≤ 16 extension can change** — the fixed-point argument
`TABLE_EAGER_BITS` makes for itself. `2^20` above it admits every signature
through K1 + K2 = 20 while keeping the worst case seconds rather than hours;
`2^32` (two K = 16 formats) is four billion pairs and is what this exists to
refuse.
"""
const F32_EXACT_MAX_PAIRS = Ref(1 << 20)

@noinline _refuse_f32_enumeration(op::Symbol, ::Type{f1}, ::Type{f2},
                                  ΣK::Int) where {f1<:Binary,f2<:Binary} =
    throw(ArgumentError(
        "f32_exact(:$op, $(formatname(f1)), $(formatname(f2))) would enumerate " *
        "2^$ΣK operand pairs against a 300-bit oracle, over the " *
        "$(F32_EXACT_MAX_PAIRS[])-pair budget. This is a cost refusal, not a " *
        "statement about the formats — raise `SmallFloats.F32_EXACT_MAX_PAIRS[]` " *
        "to ask for it anyway"))

"""
    f32_exact(op, f1, f2) -> Bool

True iff `op ∈ (:Add, :Subtract, :Multiply)` on Float32-decoded operands is
exact for every finite pair of (f1, f2) datums — checked once by exhaustive
enumeration against a 300-bit BigFloat oracle, then cached. When true, a
Float32 intermediate is an exact carrier under every projection mode.

Defined at **every** bitwidth. A signature whose pair count exceeds
`F32_EXACT_MAX_PAIRS[]` raises rather than enumerating; that is a cost refusal
naming the budget, never a statement about the formats."""
function f32_exact(op::Symbol, f1::Type{<:Binary}, f2::Type{<:Binary})::Bool
    key = (op, _fkey(f1), _fkey(f2))
    c = lock(() -> get(F32_EXACT_CACHE, key, nothing), TABLE_LOCK)
    c !== nothing && return c
    # BEFORE the screen: an unknown operation is a caller error regardless of
    # the formats, and must report as one rather than as `false`.
    g = _f32op(op)
    ok = if !(datumsexact(Float32, f1) && datumsexact(Float32, f2))
        # Provably false without enumerating, by witness rather than by
        # plausibility. `datumsexact` can fail in exactly two ways here, and
        # each exhibits a pair on which `op` is inexact:
        #
        #   range     — some datum `x` has `Float32(x) = ±Inf32`, so for any
        #               nonzero finite datum `y` the Float32 result is
        #               non-finite while the exact one is finite;
        #   underflow — the step `2^(2−P−B)` lies below Float32's least
        #               subnormal, so the smallest positive datum `d` has
        #               `Float32(d) = 0.0f0`: `0 + Float32(y) ≠ d + y` and
        #               `0 · Float32(y) ≠ d·y` for nonzero `y`.
        #
        # There is no third way, because the trait's remaining condition is
        # `P ≤ precision(X)` and `P ≤ KMAX = 16 < 24`. **That is what makes this
        # sound, and it is exactly what would stop being true if `KMAX` were
        # raised past 24** — a precision-only failure has no witness, and this
        # screen must be deleted rather than adjusted if that day comes.
        false
    else
        # `1 << ΣK` is safe here and is deliberately NOT how `tablebits` decides
        # the same kind of question: ΣK ≤ 32 for two K ≤ 16 formats, while a
        # ternary table's ΣK reaches 48 and must be compared in bits. Different
        # bound, different spelling — do not unify them.
        ΣK = bitwidth(f1) + bitwidth(f2)
        (1 << ΣK) <= F32_EXACT_MAX_PAIRS[] || _refuse_f32_enumeration(op, f1, f2, ΣK)
        # The code unit comes from the operand format, not from `UInt8`. This is
        # `measure_kappa`'s finding A1 in its second location: `UInt8(c)` is a
        # *checked* conversion, so at K ≥ 9 this raised `InexactError` — an error
        # about the representation, where the caller's error was about the
        # format — before the enumeration began.
        U1, U2 = codeunit_type(f1), codeunit_type(f2)
        setprecision(BigFloat, 300) do
            for c1 in zero(U1):U1((1 << bitwidth(f1)) - 1),
                c2 in zero(U2):U2((1 << bitwidth(f2)) - 1)
                x = decode(rawvalue(f1, c1)); y = decode(rawvalue(f2, c2))
                (isfinite(x) & isfinite(y)) || continue
                BigFloat(g(Float32(x), Float32(y))) == g(BigFloat(x), BigFloat(y)) ||
                    return false
            end
            true
        end
    end
    lock(() -> (F32_EXACT_CACHE[key] = ok), TABLE_LOCK)
    ok
end

"""
    _ternary_table_for(op, fr, f1, f2, f3, ρ, nelems) -> Union{Nothing,Memory{UInt8}}

The kernel-facing policy gate, called once per array operation with the call's
element count. Eager band (Σ Kᵢ ≤ `TERNARY_EAGER_BITS[]`): fetch/build now.
Adaptive band (≤ `TERNARY_ADAPTIVE_BITS[]`): return the cached table if present,
otherwise accumulate `nelems` against the signature and build only once it has
earned `TERNARY_BUILD_ELEMS[]`. Beyond the adaptive band (the K=8 territory):
always `nothing` — the compute kernel is the right tradeoff there.
"""
@noinline function _ternary_table_for(op::Symbol, ::Type{fr}, ::Type{f1}, ::Type{f2},
                                      ::Type{f3}, ρ::ProjSpec,
                                      nelems::Int)::Union{Nothing,Memory{codeunit_type(fr)}} where {fr<:Binary,f1<:Binary,f2<:Binary,f3<:Binary}
    isstochastic(ρ) && return nothing
    # The byte budget is the outer bound (invariant 10); the eager/adaptive
    # bands below are the *build-cost* policy inside it. Both must pass, and
    # they are not redundant: 3 × K = 7 is 2^21 entries — inside the adaptive
    # band, and at a UInt16 result 4 MiB, comfortably inside the byte budget —
    # while 3 × K = 16 is 2^48 entries and fails the byte budget long before
    # any band is consulted.
    within_byte_budget(fr, f1, f2, f3) || return nothing
    SB = _sumK(f1, f2, f3)
    SB <= TERNARY_EAGER_BITS[] && return get_table(op, fr, f1, f2, f3, ρ)
    SB <= TERNARY_ADAPTIVE_BITS[] || return nothing
    key = _tkey(op, fr, f1, f2, f3, ρ)
    hit = _ternary_probe(fr, key)
    hit !== nothing && return hit
    n = lock(() -> (TERNARY_USE[key] = get(TERNARY_USE, key, 0) + nelems), TABLE_LOCK)
    n >= TERNARY_BUILD_ELEMS[] || return nothing
    _ternary_insert!(fr, key, _build_ternary(op, fr, f1, f2, f3, ρ))
end
