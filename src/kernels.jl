# ===== kernels.jl — array kernels (design §8, architecture §7)
#
# Two hot-loop shapes, written once and instantiated by the registry:
#   Shape A (gather):  out[i] = tbl[key(a[i]…)]   — pure ρ, table affordable
#   Shape B (compute): per-element scalar path    — everything else
# The table getter is @noinline and called ONCE per array call, hoisted out of
# the loop; loop bodies index a local `Memory` with no dict lookups, locks, or
# global loads per element.
#
# **Every arity chooses between the shapes; none assumes Shape A.** Ternary has
# worked this way since the bitwidth policy landed; unary and binary joined it
# under K ≤ 16, where a 16×16 binary table would be 2^32 entries. The choice is
# made by `table_for` / `_ternary_table_for` and is a *policy* decision, never a
# correctness one: invariant 6 says a table entry is one trip through
# `_scalar_code`, and Shape B calls that same scalar path per element. The two
# shapes cannot disagree; `test/gates_shape.jl` measures that rather than
# assuming it.

"""
    vmap!(dest, Val(op), fr, ρ, A[, B[, C]]; rng) -> dest
    vmap(op, fr, ρ, A...; rng)

Elementwise draft operation over arrays of `Binary` values, projecting into `fr`
under ρ. Pure ρ runs the Shape-A gather whenever a table exists or the ternary
bitwidth policy grants one; stochastic specializations (and untabled ternary
signatures) run the scalar path per element (each element drawing its own R).
"""
function vmap! end

# ---- Shape A: unary gather
function vmap!(dest::AbstractArray{FR}, ::Val{op}, ::Type{FR}, ρ::ProjSpec,
               A::AbstractArray{F1}) where {op,FR<:Binary,F1<:Binary}
    axes(dest) == axes(A) || throw(DimensionMismatch("dest and A must share axes"))
    if isstochastic(ρ)
        return _vmap_scalar!(dest, Val(op), FR, ρ, A)
    end
    tbl = table_for(op, FR, F1, ρ)                       # hoisted; @noinline
    # Shape B when policy declines a table. Same answer by invariant 6 — a table
    # entry is one trip through `_scalar_code`, which is what this loop calls per
    # element — so the branch trades speed only. `_vmap_scalar!` is reused rather
    # than duplicated: under pure ρ its `_drawR` returns 0 without touching the rng.
    tbl === nothing && return _vmap_scalar!(dest, Val(op), FR, ρ, A)
    @inbounds for i in eachindex(dest, A)
        dest[i] = rawvalue(FR, tbl[Int(codepoint(A[i])) + 1])
    end
    dest
end

# ---- Shape A: binary gather, index = (c1 << K2) | c2
function vmap!(dest::AbstractArray{FR}, ::Val{op}, ::Type{FR}, ρ::ProjSpec,
               A::AbstractArray{F1}, B::AbstractArray{F2}) where {op,FR<:Binary,F1<:Binary,F2<:Binary}
    axes(dest) == axes(A) == axes(B) || throw(DimensionMismatch("dest, A, B must share axes"))
    if isstochastic(ρ)
        return _vmap_scalar!(dest, Val(op), FR, ρ, A, B)
    end
    tbl = table_for(op, FR, F1, F2, ρ)
    tbl === nothing && return _vmap_scalar!(dest, Val(op), FR, ρ, A, B)
    K2 = bitwidth(F2)
    @inbounds for i in eachindex(dest, A, B)
        dest[i] = rawvalue(FR, tbl[(Int(codepoint(A[i])) << K2) + Int(codepoint(B[i])) + 1])
    end
    dest
end

# ---- ternary: Shape-A gather where the policy grants a table (eager K≤6 band,
# adaptive K=7 band — see tables.jl), Shape-B compute otherwise. The pure-ρ
# compute loop is deterministic per element, so it threads for long arrays;
# stochastic ρ stays sequential (single rng stream, reproducible draws).
"""Minimum element count before the pure-ρ ternary compute loop threads."""
const THREAD_MIN_ELEMS = Ref(1 << 15)
"""Master switch for threaded ternary compute loops."""
const THREADED_KERNELS = Ref(true)

function vmap!(dest::AbstractArray{FR}, ::Val{op}, ::Type{FR}, ρ::ProjSpec,
               A::AbstractArray{F1}, B::AbstractArray{F2}, C::AbstractArray{F3};
               rng::MaybeRNG=nothing) where {op,FR<:Binary,F1<:Binary,F2<:Binary,F3<:Binary}
    axes(dest) == axes(A) == axes(B) == axes(C) || throw(DimensionMismatch("operand axes must match"))
    if !isstochastic(ρ)
        tbl = _ternary_table_for(op, FR, F1, F2, F3, ρ, length(dest))  # hoisted; @noinline
        if tbl !== nothing
            K2, K3 = bitwidth(F2), bitwidth(F3)
            @inbounds for i in eachindex(dest, A, B, C)
                idx = ((Int(codepoint(A[i])) << K2 | Int(codepoint(B[i]))) << K3) +
                      Int(codepoint(C[i])) + 1
                dest[i] = rawvalue(FR, tbl[idx])
            end
            return dest
        end
        inds = eachindex(dest, A, B, C)
        if THREADED_KERNELS[] && Threads.nthreads() > 1 &&
           length(inds) >= THREAD_MIN_ELEMS[] && inds isa AbstractUnitRange
            Threads.@threads for i in inds
                @inbounds dest[i] = apply_op(Val(op), FR, ρ, 0,
                                             decode(A[i]), decode(B[i]), decode(C[i]))
            end
            return dest
        end
        @inbounds for i in inds
            dest[i] = apply_op(Val(op), FR, ρ, 0, decode(A[i]), decode(B[i]), decode(C[i]))
        end
        return dest
    end
    rr = _resolve_rng(rng)
    @inbounds for i in eachindex(dest, A, B, C)
        R = _drawR(ρ, rr, nothing)
        dest[i] = apply_op(Val(op), FR, ρ, R, decode(A[i]), decode(B[i]), decode(C[i]))
    end
    dest
end
function _vmap_scalar!(dest, ::Val{op}, ::Type{FR}, ρ::ProjSpec, A;
                       rng::MaybeRNG=nothing) where {op,FR<:Binary}
    rr = _rng_for(ρ, rng)                       # hoisted: resolved once per call
    @inbounds for i in eachindex(dest, A)
        dest[i] = apply_op(Val(op), FR, ρ, _drawR(ρ, rr, nothing), decode(A[i]))
    end
    dest
end
function _vmap_scalar!(dest, ::Val{op}, ::Type{FR}, ρ::ProjSpec, A, B;
                       rng::MaybeRNG=nothing) where {op,FR<:Binary}
    rr = _rng_for(ρ, rng)
    @inbounds for i in eachindex(dest, A, B)
        dest[i] = apply_op(Val(op), FR, ρ, _drawR(ρ, rr, nothing), decode(A[i]), decode(B[i]))
    end
    dest
end
# stochastic entry points that thread the caller's rng through the Shape-A dispatchers
function vmap!(dest::AbstractArray{FR}, v::Val, ::Type{FR}, ρ::ProjSpec,
               A::AbstractArray{<:Binary}, B::AbstractArray{<:Binary}, rng::MaybeRNG) where {FR<:Binary}
    isstochastic(ρ) ? _vmap_scalar!(dest, v, FR, ρ, A, B; rng) : vmap!(dest, v, FR, ρ, A, B)
end
function vmap!(dest::AbstractArray{FR}, v::Val, ::Type{FR}, ρ::ProjSpec,
               A::AbstractArray{<:Binary}, rng::MaybeRNG) where {FR<:Binary}
    isstochastic(ρ) ? _vmap_scalar!(dest, v, FR, ρ, A; rng) : vmap!(dest, v, FR, ρ, A)
end
function vmap!(dest::AbstractArray{FR}, v::Val, ::Type{FR}, ρ::ProjSpec,
               A::AbstractArray{<:Binary}, B::AbstractArray{<:Binary},
               C::AbstractArray{<:Binary}, rng::MaybeRNG) where {FR<:Binary}
    vmap!(dest, v, FR, ρ, A, B, C; rng)      # the ternary method handles both ρ kinds
end

@inline function vmap(op::Symbol, fr::Type{<:Binary}, ρ::ProjSpec, As::AbstractArray...;
                      rng::MaybeRNG=nothing)
    dest = similar(first(As), fr)
    # Stochastic ρ appends rng as a trailing *positional* argument, selecting the
    # rng-threading vmap! methods above; pure ρ takes the plain Shape-A/B methods.
    isstochastic(ρ) ? vmap!(dest, Val(op), fr, ρ, As..., rng) : vmap!(dest, Val(op), fr, ρ, As...)
end

# ---- registry-generated array surface for the spec register:
#      Op(fr, ρ, A::AbstractArray...) mirrors the scalar signature
for op in OP_REGISTRY
    op.name === :Convert && continue
    name = op.name
    if op.arity == 1
        @eval $name(fr::Type{<:Binary}, ρ::ProjSpec, A::AbstractArray{<:Binary};
                    rng::MaybeRNG=nothing) = vmap($(QuoteNode(name)), fr, ρ, A; rng)
    elseif op.arity == 2
        @eval $name(fr::Type{<:Binary}, ρ::ProjSpec, A::AbstractArray{<:Binary},
                    B::AbstractArray{<:Binary}; rng::MaybeRNG=nothing) =
            vmap($(QuoteNode(name)), fr, ρ, A, B; rng)
    else
        @eval $name(fr::Type{<:Binary}, ρ::ProjSpec, A::AbstractArray{<:Binary},
                    B::AbstractArray{<:Binary}, C::AbstractArray{<:Binary};
                    rng::MaybeRNG=nothing) = vmap($(QuoteNode(name)), fr, ρ, A, B, C; rng)
    end
end
# Convert has no ω-semantics (registry group :conv) so the loop above skips it;
# its array form still rides the Shape-A gather — the :Convert table is built by
# _scalar_code's bare-projection branch. Under stochastic ρ `vmap` takes the
# per-element scalar path instead, drawing one R per element.
#
# `rng` is threaded like every other array operation's. Without it this was the
# one bulk surface that could not be given an owned stream — which is exactly
# what `defaults.jl`'s entropy decision tells callers to do, having removed the
# session-wide RNG for being a global that stochastic results should not depend
# on. It is forwarded, not defaulted differently: pure ρ never resolves it.
Convert(fr::Type{<:Binary}, ρ::ProjSpec, A::AbstractArray{<:Binary};
        rng::MaybeRNG=nothing) = vmap(:Convert, fr, ρ, A; rng)

# ---- Float32/Float64 surface: bulk exact ωDecode and external-array ingestion

"""
    decode!(dest::AbstractArray{Float32}, A::AbstractArray{<:Binary}) -> dest
    decode!(dest::AbstractArray{Float64}, A::AbstractArray{<:Binary}) -> dest

**Exact** bulk ωDecode into an external float array.

Exactness is the whole contract here — it is what distinguishes `decode!` from
`Float32.(A)`, which rounds like any other Julia conversion — so the destination
element type is **gated on the format**, not assumed. `datumsexact(X, F)` decides
it, and a format whose datums do not all fit `X` raises rather than silently
rounding a bulk array. Every K ≤ 8 format passes both gates, so this is a new
refusal only for formats that did not exist before the K ≤ 16 extension.

Where the gate passes and `K ≤ KSPLIT`, the implementation is unchanged: a
Shape-A gather of the (narrowed) constant decode table."""
function decode!(dest::AbstractArray{Float32}, A::AbstractArray{F}) where {F<:Binary}
    axes(dest) == axes(A) || throw(DimensionMismatch("dest and A must share axes"))
    datumsexact(Float32, F) || throw(ArgumentError(
        "decode! promises exactness, and not every datum of $(formatname(F)) is " *
        "representable in Float32 (P=$(precision(F)), B=$(expbias(F))). Use " *
        "`Float32.(A)` and own the rounding, or decode to $(datumcarrier(F))"))
    _decode_f32!(decodepolicy(F), dest, A)
end
@inline function _decode_f32!(::TableDecode, dest, A::AbstractArray{F}) where {F<:Binary}
    tbl = _decode_table32(F)
    @inbounds for i in eachindex(dest, A)
        dest[i] = tbl[Int(codepoint(A[i])) + 1]
    end
    dest
end
@inline function _decode_f32!(::ComputeDecode, dest, A::AbstractArray{F}) where {F<:Binary}
    @inbounds for i in eachindex(dest, A)
        dest[i] = Float32(decode(A[i]))          # exact: the gate above says so
    end
    dest
end

function decode!(dest::AbstractArray{Float64}, A::AbstractArray{F}) where {F<:Binary}
    axes(dest) == axes(A) || throw(DimensionMismatch("dest and A must share axes"))
    # The gate is `datumsexact`, NOT `datumcarrier(F) === Float64`, and the
    # difference is instructive: 454 formats have Float64-exact datums but only
    # 432 are rung 1. The B = 1024 band — 22 formats — decodes exactly into
    # Float64 and still needs `Float128` to *compute* in, because a product of
    # two of its datums leaves Float64's range even though each operand sits
    # inside it. `datumcarrier` answers a question about arithmetic; this
    # function asks a question about representation, and using the arithmetic
    # trait here would refuse 22 formats for which the promise holds.
    datumsexact(Float64, F) || throw(ArgumentError(
        "decode! promises exactness, and not every datum of $(formatname(F)) is " *
        "representable in Float64 (P=$(precision(F)), B=$(expbias(F))). Use " *
        "`Float64.(A)` and own the rounding, or decode to $(datumcarrier(F))"))
    _decode_f64!(decodepolicy(F), dest, A)
end
@inline function _decode_f64!(::TableDecode, dest, A::AbstractArray{F}) where {F<:Binary}
    tbl = _decode_table(F)
    @inbounds for i in eachindex(dest, A)
        dest[i] = tbl[Int(codepoint(A[i])) + 1]
    end
    dest
end
@inline function _decode_f64!(::ComputeDecode, dest, A::AbstractArray{F}) where {F<:Binary}
    @inbounds for i in eachindex(dest, A)
        # `Float64(...)` is the identity for a rung-1 format and an exact
        # narrowing for the B = 1024 band, which the gate above has already
        # established. It is never a rounding here.
        dest[i] = Float64(decode(A[i]))
    end
    dest
end

"""External float element types whose widening to the Float64 carrier is exact."""
const ExactExternalFloat = Union{Float16,Float32,Float64,BFloat16}

"""
    Convert(fr, ρ, A::AbstractArray{<:Union{Float16,Float32,Float64,BFloat16}}; rng) -> Array{fr}

Bulk ingestion: exact widening per element, then projection under ρ. Unlike the
Binary-array Convert (a Shape-A table gather), external inputs are not
enumerable, so this is a Shape-B loop; stochastic ρ draws per element."""
function Convert(fr::Type{<:Binary}, ρ::ProjSpec, A::AbstractArray{<:ExactExternalFloat};
                 rng::MaybeRNG=nothing)
    dest = similar(A, fr)
    rr = _rng_for(ρ, rng)                       # hoisted: resolved once per call
    @inbounds for i in eachindex(dest, A)
        dest[i] = project(fr, ρ, Float64(A[i]); R=_drawR(ρ, rr, nothing))
    end
    dest
end
