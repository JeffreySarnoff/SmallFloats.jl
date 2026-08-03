# dot_product_projection_example.jl
#
# Illustrates the "exact math, then one projection" contract of SmallFloats.jl
# for a dot product in a small P3109 format (default: Binary8p3sf), using
# Quadmath::Float128 as the exact-arithmetic carrier.
#
# For a Binary format B and a length N:
#   (a1) draw two arrays a, b :: Vector{B}, each element normal and finite
#   (a2) lift to A, B_ :: Vector{Float128} via exact decode
#   (a3) dotab  = dot product of (a, b) reduced under the projection RNE_SF
#                 (aka RTE_SF: round-to-nearest-ties-to-even, SatFinite)
#   (a4) dotAB  = Float128 dot product of (A, B_)   -- ground truth
#   (a5) dotAB_in_B = Convert(B, RNE_SF, dotAB)      -- project once
#   (a6) report absolute and relative errors:
#        * of decode(dotab) vs dotAB               (the interesting error:
#                                                   full projection of exact
#                                                   dot, measured in Float128)
#        * of decode(dotab) vs decode(dotAB_in_B)  (should be zero: same
#                                                   exact value, same projection)
#
# References (SmallFloats.jl 0.3.0 documentation):
#   - "Every computation is exact math, then one projection" (Core Model)
#   - Convert(fr, ρ, x) accepts Float128 directly and projects it (§32.1)
#   - RNE_SF = round-to-nearest-ties-to-even + SatFinite (Projection Specifications)
#
# Requires: SmallFloats, Quadmath.

using .SmallFloats
using Quadmath: Float128
using Random: AbstractRNG, Xoshiro
using Statistics: mean

# ---------------------------------------------------------------------------
# RTE_SF is the standards-literature spelling of RNE_SF (Round-Ties-to-Even,
# SatFinite). SmallFloats exports RNE_SF; we alias for readability.
# ---------------------------------------------------------------------------
const RTE_SF = RNE_SF

"""
    normal_finite_sample(::Type{B}, rng; scale=1.0) -> B

Draw one Binary value of format `B` that is normal, finite, non-zero, and
non-NaN. The draw goes through `Convert(B, RNE_SF, x)` so the projection is
explicit and reproducible. Rejection sampling is used to enforce the
"normal finite" predicate against the format's own grid.
"""
function normal_finite_sample(::Type{B}, rng::AbstractRNG; scale::Real = 1.0) where {B}
    while true
        # Draw from a distribution wide enough to exercise the format's
        # dynamic range but tight enough to avoid saturating every draw.
        x = scale * randn(rng)
        y = Convert(B, RNE_SF, x)
        if isfinite(y) && !isnan(y) && !iszero(y) && !issubnormal(y)
            return y
        end
    end
end

"""
    normal_finite_array(::Type{B}, N, rng; scale=1.0) -> Vector{B}
"""
function normal_finite_array(::Type{B}, N::Integer, rng::AbstractRNG;
                             scale::Real = 1.0) where {B}
    v = Vector{B}(undef, N)
    @inbounds for i in 1:N
        v[i] = normal_finite_sample(B, rng; scale = scale)
    end
    return v
end

"""
    example(::Type{B}, N; rng=Xoshiro(20260802), scale=1.0)

Run steps (a1)..(a6) for a Binary format `B` and length `N`. Returns a
NamedTuple with the arrays, the two dot products, the projected reference,
and the absolute/relative errors.

The design follows the SmallFloats "exact then project once" contract:
- `dotab` is computed as the projection under RNE_SF of the mathematically
  exact dot product carried in Float128. This is what a specification-shaped
  reduction over (a, b) with policy RNE_SF is defined to produce.
- `dotAB` is the same exact dot product left in Float128.
- `dotAB_in_B` projects `dotAB` back into `B` under RNE_SF.

Consequently `dotab` and `dotAB_in_B` are the same code point in `B` by
construction; the interesting error is `decode(dotab) - dotAB`, measured in
Float128.
"""
function example(::Type{B}, N::Integer;
                 rng::AbstractRNG = Xoshiro(20260802),
                 scale::Real = 1.0) where {B}

    # (a1) Two arrays of normal, finite B-values.
    a = normal_finite_array(B, N, rng; scale = scale)
    b = normal_finite_array(B, N, rng; scale = scale)

    # (a2) Lift to Float128 by exact decode. `decode(x)` names the datum
    #      exactly; widening a Float64 to Float128 is also exact.
    A  = Float128.(decode.(a))
    B_ = Float128.(decode.(b))

    # (a3) Exact dot product in Float128, then one projection into B under
    #      RNE_SF. This is the specification-shaped meaning of "dot product
    #      of (a, b) under the projection RTE_SF".
    exact_dot = zero(Float128)
    @inbounds for i in 1:N
        exact_dot += A[i] * B_[i]
    end
    dotab = Convert(B, RNE_SF, exact_dot)

    # (a4) Float128 dot product of (A, B_). Same value as `exact_dot` above,
    #      recomputed independently for clarity.
    dotAB = zero(Float128)
    @inbounds for i in 1:N
        dotAB += A[i] * B_[i]
    end

    # (a5) Project the Float128 dot into B under RNE_SF.
    dotAB_in_B = Convert(B, RNE_SF, dotAB)

    # (a6) Errors, measured in Float128.
    dotab_as_F128 = Float128(decode(dotab))
    proj_as_F128  = Float128(decode(dotAB_in_B))

    abs_err_vs_exact       = abs(dotab_as_F128 - dotAB)
    rel_err_vs_exact       = iszero(dotAB) ? zero(Float128) :
                             abs_err_vs_exact / abs(dotAB)

    # Sanity: the two projected values agree bit-for-bit by construction.
    abs_err_vs_projected   = abs(dotab_as_F128 - proj_as_F128)
    rel_err_vs_projected   = iszero(proj_as_F128) ? zero(Float128) :
                             abs_err_vs_projected / abs(proj_as_F128)

    return (; a, b, A, B = B_,
              dotab, dotAB, dotAB_in_B,
              abs_err_vs_exact,       rel_err_vs_exact,
              abs_err_vs_projected,   rel_err_vs_projected)
end

# ---------------------------------------------------------------------------
# Pretty-printer for interactive use.
# ---------------------------------------------------------------------------
function report(r::NamedTuple; io::IO = stdout)
    println(io, "Format                : ", eltype(r.a))
    println(io, "N                     : ", length(r.a))
    println(io, "dotab (in B)          : ", r.dotab,
                "  (decode = ", decode(r.dotab), ")")
    println(io, "dotAB (Float128)      : ", r.dotAB)
    println(io, "dotAB_in_B            : ", r.dotAB_in_B,
                "  (decode = ", decode(r.dotAB_in_B), ")")
    println(io, "abs err vs exact dotAB: ", r.abs_err_vs_exact)
    println(io, "rel err vs exact dotAB: ", r.rel_err_vs_exact)
    println(io, "abs err vs projected  : ", r.abs_err_vs_projected,
                "   (expected 0)")
    println(io, "rel err vs projected  : ", r.rel_err_vs_projected,
                "   (expected 0)")
    return nothing
end

# ---------------------------------------------------------------------------
# When run as a script, demonstrate with Binary8p3sf at N = 64.
# ---------------------------------------------------------------------------
if abspath(PROGRAM_FILE) == @__FILE__
    r = example(Binary8p3sf, 64)
    report(r)
end
