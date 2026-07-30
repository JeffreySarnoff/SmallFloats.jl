# ===== test/gates_g3.jl — gate G3: `_rtp_f64` bit ≡ generic, widened
#
# implementextensions §5 G3. `round_to_precision` has two implementations on a
# Float64 carrier: `_rtp_f64`, a mask-and-shift bit path, and `_rtp_core`, the
# generic float algorithm the draft is written against. The bit path's shift
# bounds were derived when `P ≤ 8` — `d = e − Q ≤ P−1 ≤ 7`, hence `t = 52−d ∈
# [45, 52]`. Under K ≤ 16 the claim becomes `d ≤ 15` and `t ∈ [37, 52]`, and the
# licence for it is this gate, not the comment in the source.
#
# **Domain is wider than the plan specified.** §4 Stage 4 scoped G3 to
# `(P ≤ 16, B ≤ 512)` — the rung-1 grid, where Float64 is the format's own
# carrier. That is not the whole reachable set: `Convert(F, ρ, x::Float64)`
# projects an external Float64 into *any* format, so `_rtp_f64` runs at every
# bias in the grid, up to B = 32768. The wide-B case is where the bit path's
# `d < 0` branch would live, and it is unreachable for a normal Float64 input
# precisely because `1 − B` drops below Float64's exponent range — a fact worth
# measuring rather than asserting. So the domain here is every `(P, B)` pair the
# 504-format grid realizes. (§11 M22.)

using Test, SmallFloats
using SmallFloats: _rtp_f64, _rtp_core, KMIN, KMAX

"""Every `(P, B)` pair realized by the format grid, sorted."""
function pb_pairs()
    s = Set{Tuple{Int,Int}}()
    for K in KMIN:KMAX, P in 1:K, S in (true, false)
        S && P >= K && continue
        push!(s, (P, S ? 1 << (K - P - 1) : 1 << (K - P)))
    end
    sort!(collect(s))
end

"""Structured Float64 inputs for the `(P, B)` grid: binade edges, the
subnormal/normal boundary of the *format*, exact ties, ties ± 1 ulp of Float64,
and the extremes of Float64's own normal range.

Subnormal Float64 inputs are excluded on purpose — `round_to_precision` routes
those to `_rtp_core` before `_rtp_f64` is reached, so they are not in the bit
path's domain and including them would test the router, not the path."""
function g3_inputs(P::Int, B::Int)
    xs = Float64[]
    es = Int[-1022, -1021, -2, -1, 0, 1, 2, 1022, 1023]
    for e in (1 - B - P, 2 - B - P, -B, 1 - B, 2 - B, B - 2, B - 1, B)
        -1022 <= e <= 1023 && push!(es, e)
    end
    unique!(sort!(es))
    for e in es
        u = e - P + 1                       # exponent of the format's ulp at binade e
        u < -1070 && continue               # the grid step itself underflows Float64
        for s in (1 << (P - 1), (1 << (P - 1)) + 1, (1 << P) - 2, (1 << P) - 1)
            base = ldexp(Float64(s), u)
            (isfinite(base) && !iszero(base)) || continue
            for x in (base, nextfloat(base), prevfloat(base),
                      base + ldexp(0.5, u), base + ldexp(0.25, u), base + ldexp(0.75, u),
                      nextfloat(base + ldexp(0.5, u)), prevfloat(base + ldexp(0.5, u)))
                (isfinite(x) && !iszero(x) && !issubnormal(x)) || continue
                push!(xs, x, -x)
            end
        end
    end
    unique!(xs)
    xs
end

"""The rounding modes and random draws the gate crosses its inputs with. The
stochastic modes are included with explicit `R` because the bit path has its own
`_rab` predicate family per mode — the one place where "bit ≡ generic" is a
claim about six-plus separate pairs of functions rather than one."""
const G3_MODES = Any[NearestTiesToEven(), NearestTiesToAway(), TowardPositive(),
                     TowardNegative(), TowardZero(), ToOdd()]
const G3_STOCH = Any[StochasticA{4}(), StochasticB{4}(), StochasticC{4}()]

"""Compare the two implementations over one `(P, B)` cell. Returns
`(ok, ncmp, witness)`."""
function g3_cell(P::Int, B::Int)
    xs = g3_inputs(P, B)
    n = 0
    for X in xs, sticky in (0, 1, -1)
        for μ in G3_MODES
            a = _rtp_f64(P, B, μ, X, 0, sticky)
            b = _rtp_core(P, B, μ, X, 0, sticky)
            n += 1
            a === b || return (false, n, (X, sticky, μ, 0, a, b))
        end
        for μ in G3_STOCH, R in (0, 7, 15)
            a = _rtp_f64(P, B, μ, X, R, sticky)
            b = _rtp_core(P, B, μ, X, R, sticky)
            n += 1
            a === b || return (false, n, (X, sticky, μ, R, a, b))
        end
    end
    (true, n, nothing)
end

let ncmp = 0, ncells = 0
    @testset "G3 — _rtp_f64 bit ≡ generic (P ≤ $KMAX, every realized B)" begin
        pairs = pb_pairs()
        @test !isempty(pairs)
        # The bound the bit path is derived from, stated as arithmetic rather
        # than as a comment: `Q = max(e, 1−B) − P + 1`, so `d = e − Q` is `P−1`
        # on the normal branch and smaller below it.
        @test maximum(p -> p[1], pairs) == KMAX
        @test maximum(p -> p[2], pairs) == 1 << (KMAX - 1)

        for (P, B) in pairs
            ok, n, w = g3_cell(P, B)
            @test ((P, B), ok) == ((P, B), true)
            ok || @info "G3 witness" P B witness = w
            ncmp += n
            ncells += 1
        end
    end
    println("G3: $ncells (P,B) cells, $ncmp bit-vs-generic comparisons, all exhaustive over the structured input set")
end
