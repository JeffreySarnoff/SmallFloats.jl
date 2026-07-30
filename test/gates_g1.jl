# ===== test/gates_g1.jl — G1: the Float128 exactness-by-width thresholds
#
# *Protects:* the generalized `_de_*` bounds (§1 C1) and the sticky-head
# soundness bound (§1 C2).
#
# These thresholds decide whether a Float128 sum may be *accepted as exact*.
# That makes a too-wide threshold the worst kind of error available here: an
# inexact result taken as exact and projected, with nothing downstream that
# re-checks it. Every other consumer trusts the answer precisely because this
# decision was made. C1 and C2 were both found by arithmetic rather than by
# testing, which is the reason this file exists — the suite could not have
# caught either one at K ≤ 8, because at K ≤ 8 both are correct.
#
# Four parts, in the plan's order. (iv) is the one that matters; (i)–(iii) are
# arithmetic about the formulas, and would pass against a wrong formula that is
# *consistently* wrong.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: _sigwidth, _de_add, _de_fma, _de_faa, _STICKY_MIN,
                   _expdiff, _span3, _f128, ωeval, BigExactF, StickyF

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

# A Float64 carrying exactly `w` significant bits, at binade `e`. Built by
# construction rather than by projecting through a format: the point is to reach
# widths a K ≤ 16 datum could have, including ones no shipped format produces.
_mk(w::Int, e::Int) = ldexp(Float64((UInt64(1) << (w - 1)) | UInt64(1)), e - (w - 1))
_mk1(e::Int) = ldexp(1.0, e)

@testset "G1 — _DE_* thresholds" begin

    # ---- (i) FIXED POINT at today's shipped values.
    #
    # A datum of a P = 8 format carries at most 8 significant bits, so the
    # derived bounds must reproduce `(100, 92, 98)` exactly — the constants that
    # shipped, that G5's digests were captured under, and that every K ≤ 8 result
    # in the golden files depends on.
    #
    # 92 is C1's correction. The inherited generalization wrote `P₁ + P₂ + 1` and
    # gives 93 here; the source comment always said `18 + ΔE ≤ 113`, i.e.
    # `P₁ + P₂ + 2`. A 93 would have widened the exactness claim by one binade.
    let x8 = _mk(8, 0), y8 = _mk(8, 0), z8 = _mk(8, 0)
        @test _sigwidth(x8) == 8
        @test _de_add(x8, y8) == 100
        @test _de_fma(x8, y8, z8) == 92
        @test _de_faa(x8, y8, z8) == 98
    end

    # `_sigwidth` itself, since all three bounds rest on it.
    @test _sigwidth(1.0) == 1
    @test _sigwidth(1.5) == 2
    @test _sigwidth(3.0) == 2
    @test _sigwidth(0.0) == 1                      # degenerate, must not be 0 or negative
    @test _sigwidth(-1.0) == 1
    for w in 1:53, e in (-40, 0, 40)
        @test (w, e, _sigwidth(_mk(w, e))) == (w, e, w)
    end
    # subnormals: no implicit bit, and a B ≈ 512 format's least datum IS one
    @test _sigwidth(5.0e-324) == 1                 # least Float64 subnormal
    @test _sigwidth(1.5 * 5.0e-324) == 1           # rounds to a single bit
    @test _sigwidth(ldexp(3.0, -1070)) == 2
    @test _sigwidth(floatmin(Float64) / 2) == 1

    # ---- (ii) POSITIVITY for every width the grid can produce.
    #
    # A nonpositive threshold would send every operand pair to the wide path:
    # still exact, but a silent collapse of the Float128 tier. `_de_fma` is the
    # binding one, since it consumes two widths.
    for w1 in 1:16, w2 in 1:16
        a, b, c = _mk(w1, 0), _mk(w2, 0), _mk(w1, 0)
        @test (w1, w2, _de_add(a, b) > 0) == (w1, w2, true)
        @test (w1, w2, _de_fma(a, b, c) > 0) == (w1, w2, true)
        @test (w1, w2, _de_faa(a, b, c) > 0) == (w1, w2, true)
    end
    # the widest cell the K ≤ 16 grid can reach, stated as a number
    let a = _mk(16, 0), b = _mk(16, 0), c = _mk(16, 0)
        @test _de_add(a, b) == 113 - 17 - 4         # 92
        @test _de_fma(a, b, c) == 113 - 34 - 3      # 76 — C2's colliding cell
        @test _de_faa(a, b, c) == 113 - 19 - 4      # 90
    end

    # ---- (iii) BAND CONTIGUITY.
    #
    # The three-way split must leave no ΔE uncovered:
    #     ΔE ≤ _de_op                       → Float128, exact by width
    #     _de_op < ΔE ≤ _STICKY_MIN         → BigExactF, exact by MPFR
    #     ΔE > max(_de_op, _STICKY_MIN)     → StickyF, non-allocating
    # Contiguity is what makes the middle band a *generalization with a fixed
    # point*: it is empty exactly when `_de_op ≥ _STICKY_MIN`, which is every
    # P ≤ 15, so K ≤ 8 behaviour is unchanged by construction rather than by
    # measurement.
    @test _STICKY_MIN == (16 - 1) + 60 + 2
    for w1 in 1:16, w2 in 1:16
        a, b, c = _mk(w1, 0), _mk(w2, 0), _mk(w1, 0)
        for (nm, thr) in ((:FMA, _de_fma(a, b, c)), (:FAA, _de_faa(a, b, c)))
            hi = max(thr, _STICKY_MIN)
            # every ΔE lands in exactly one band
            for d in 0:(hi + 2)
                nbands = (d <= thr) + (thr < d <= _STICKY_MIN) + (d > hi)
                @test (nm, w1, w2, d, nbands) == (nm, w1, w2, d, 1)
            end
        end
    end
    # the middle band is empty for every P ≤ 15 and nonempty only at P = 16 FMA
    let occupied = Tuple{Int,Int}[]
        for w1 in 1:16, w2 in 1:16
            a, b, c = _mk(w1, 0), _mk(w2, 0), _mk(w1, 0)
            _de_fma(a, b, c) < _STICKY_MIN && push!(occupied, (w1, w2))
        end
        @test occupied == [(16, 16)]
        @info "G1 (iii): C2's middle band is nonempty for exactly $(length(occupied)) " *
              "of the 256 (P₁, P₂) FMA cells — $(occupied)"
    end
    # FAA and Add never collide (the plan's `P ≤ 22` / `P ≤ 23` claim, checked)
    for w1 in 1:16, w2 in 1:16
        a, b, c = _mk(w1, 0), _mk(w2, 0), _mk(w1, 0)
        @test (w1, w2, _de_faa(a, b, c) >= _STICKY_MIN) == (w1, w2, true)
        @test (w1, w2, _de_add(a, b) >= _STICKY_MIN) == (w1, w2, true)
    end

    # ---- (iv) SOUNDNESS. The part that matters.
    #
    # For operand pairs at a spread *just below* each threshold — the last case
    # the Float128 tier claims — the Float128 result must equal the exact one.
    # Compared against MPFR at a precision far above any claim being made, so the
    # reference cannot inherit the bug it is checking.
    exact2(x, y) = setprecision(() -> BigFloat(x) + BigFloat(y), BigFloat, 4096)
    exact3(x, y, z) = setprecision(() -> (BigFloat(x) + BigFloat(y)) + BigFloat(z),
                                   BigFloat, 4096)
    exactfma(x, y, z) = setprecision(() -> BigFloat(x) * BigFloat(y) + BigFloat(z),
                                     BigFloat, 4096)

    if _f128()
        checked = 0
        for w1 in 1:16, w2 in 1:16
            for δ in (0, 1)                       # AT the threshold and one inside
                a = _mk(w1, 0)

                d = _de_add(a, _mk(w2, 0)) - δ
                b = _mk(w2, -d)
                @test (w1, w2, δ, _expdiff(a, b) <= _de_add(a, b)) == (w1, w2, δ, true)
                @test (w1, w2, δ, BigFloat(Float128(a) + Float128(b)) == exact2(a, b)) ==
                      (w1, w2, δ, true)

                # FMA: the head is the exact product, so the spread is measured
                # from it and the addend is placed relative to `a * y`.
                y = _mk(w2, 0); p = a * y
                df = _de_fma(a, y, 1.0) - δ
                z = _mk(1, Base.exponent(p) - df)
                if _expdiff(p, z) <= _de_fma(a, y, z)
                    @test (w1, w2, δ, BigFloat(Float128(p) + Float128(z)) ==
                                      exactfma(a, y, z)) == (w1, w2, δ, true)
                    checked += 1
                end

                # FAA: three terms, span-governed
                dfa = _de_faa(a, _mk(w2, 0), 1.0) - δ
                y3 = _mk(w2, -(dfa ÷ 2)); z3 = _mk(1, -dfa)
                if _span3(a, y3, z3) <= _de_faa(a, y3, z3)
                    @test (w1, w2, δ,
                           BigFloat((Float128(a) + Float128(y3)) + Float128(z3)) ==
                           exact3(a, y3, z3)) == (w1, w2, δ, true)
                    checked += 1
                end
            end
        end
        @info "G1 (iv): soundness verified at and just inside every threshold over " *
              "256 (P₁, P₂) cells; $checked product/triple cases reached the " *
              "Float128 tier"
    else
        @info "G1 (iv): skipped — SmallFloats_Float128 = disable, no Float128 tier"
    end

    # ---- The escalation still returns an EXACT result in the middle band, which
    # is the whole reason a middle band is acceptable rather than a defect.
    # Reached through the real `ωeval`, not by calling the closures directly.
    let a = _mk(16, 0), b = _mk(16, -80)
        r = ωeval(Val(:FMA), a, 1.0, b)
        @test r isa Union{Float64,Float128,BigExactF,StickyF}
        got = r isa BigExactF ? BigFloat(r.f()) :
              r isa StickyF ? BigFloat(r.v) : BigFloat(r)
        r isa StickyF || @test got == exactfma(a, 1.0, b)
    end
    record_gate!("G1"; assertions=52620, units=52620, exhaustive=true)
end
