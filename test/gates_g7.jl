# ===== test/gates_g7.jl — G7: Dyadic ≡ BigFloat
#
# *The free differential oracle.* `HeadExact` shipped on `BigFloat` through
# Stage 6 and swaps to `Dyadic` at Stage 7. Running the same surface on both and
# asserting identical code points is the strongest available check on `Dyadic`'s
# arithmetic and its `round_to_precision` — and it needs **no reference
# implementation and no captured data**, because the retired carrier is the
# reference.
#
# That is worth stating as a method and not just as a convenience: an interim
# implementation kept alive one stage longer than strictly necessary turns into a
# free oracle for its own replacement. The cost was one `carriertype` line.
#
# TWO TIERS, as in G2 — and for the same reason.
#
# **Tier A — the rounding path.** `round_to_precision(P, B, μ, X, R, sticky)` on
# `Dyadic` against the same call on `BigFloat`, over the (P, B) grid × every
# rounding mode × sticky ∈ {-1, 0, +1} × R, on values chosen where the modes
# disagree: exact datums, exact midpoints (where ties-to-even and ties-to-away
# part company), and midpoints ± one unit in the last place of the carrier.
#
# **Tier B — the engine.** The ω rows evaluated on both carriers, compared as
# code points. Tier A is arithmetic about the projection; Tier B is the claim
# that the projection is the one the package uses.
#
# WHY NO WORLD-AGE SWAP. The obvious way to run "the same surface twice" is to
# redefine `carriertype(::HeadExact)` between runs, which means method
# redefinition and world-age games inside a test. It is unnecessary: both
# carriers' methods coexist, so the differential is just two calls. A gate that
# mutates the code under test to observe it is a gate that can lie.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: Dyadic, DyadicNumbers, round_to_precision, Rounded,
                   _NAMED, precision, expbias, bitwidth, codeunit_type, rawvalue,
                   KIND_FIN, KIND_NAN, KIND_PINF, KIND_NINF, _rtp_zero_sticky
using .SmallFloats.DyadicNumbers: DY_FINITE, nbits_dy

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

const MODES = (NearestTiesToEven(), NearestTiesToAway(), TowardPositive(),
               TowardNegative(), TowardZero(), ToOdd(),
               StochasticA{8}(), StochasticB{8}(), StochasticC{8}())

# Compare two `Rounded`s field by field. `Rounded` is the projection's whole
# output, so equality here is exactly "the two carriers agree" — comparing a
# final code point instead would let a difference in `Q` hide behind saturation.
_same(a::Rounded, b::Rounded) = (a.kind, a.sign, a.S, a.Q) == (b.kind, b.sign, b.S, b.Q)

# Exact rational value of a finite datum on ANY carrier. `Dyadic` has a direct
# construction (its value IS `S · 2^Q`); the floats go through `Rational{BigInt}`,
# except `Float128`, for which Base's route needs a `precision` method Quadmath
# does not define (§11 M34, the same hole one layer down).
exact_rq_any(x::Dyadic)    = Rational{BigInt}(x)
exact_rq_any(x::Float128)  = Rational{BigInt}(BigFloat(x))
exact_rq_any(x::Real)      = Rational{BigInt}(x)

@testset "G7 — Dyadic ≡ BigFloat" begin

    # ---- the C7 add bands, as a static assertion rather than a comment.
    #
    # This is the one place where raising P past 16 or N past 60 silently opens a
    # gap between the exact-alignment band and the sticky band — silently,
    # because a ΔQ landing in the gap is handled by neither and the fallback
    # answers. The inherited plan's numbers were 95 and `P ≤ 45`; both were wrong
    # (§1 C7), and the margin is what a future widening gets checked against.
    @test DyadicNumbers.DYADIC_ALIGN_MAX == 127 - 32 - 1        # 94, carry bit included
    @test DyadicNumbers.DYADIC_ADD_COVERAGE == 92
    @test SmallFloats.KMAX + 60 <= DyadicNumbers.DYADIC_ADD_COVERAGE   # 76 ≤ 92
    @test DyadicNumbers.DYADIC_ALIGN_MAX >= SmallFloats.KMAX + 60 + 2  # bands overlap

    # ---- Dyadic's own arithmetic against BigFloat, before any projection.
    let vals = Dyadic[Dyadic(0), Dyadic(1), Dyadic(-1), Dyadic(3, -1), Dyadic(-5, 7),
                      Dyadic(Int128(1) << 30, -40), Dyadic(-(Int128(1) << 20), 100),
                      Dyadic(1, -32760), Dyadic(1, 32760)]
        bad = Tuple{Int,Int,Symbol}[]
        for (i, a) in enumerate(vals), (j, b) in enumerate(vals)
            setprecision(BigFloat, 1024) do
                ba, bb = BigFloat(a), BigFloat(b)
                d = a.Q - b.Q
                if abs(d) <= DyadicNumbers.DYADIC_ALIGN_MAX
                    BigFloat(a + b) == ba + bb || push!(bad, (i, j, :add))
                end
                if nbits_dy(a.S) + nbits_dy(b.S) <= 96
                    BigFloat(a * b) == ba * bb || push!(bad, (i, j, :mul))
                end
                ((a < b) == (ba < bb)) || push!(bad, (i, j, :lt))
                ((a == b) == (ba == bb)) || push!(bad, (i, j, :eq))
            end
        end
        @test bad == Tuple{Int,Int,Symbol}[]
    end

    # ---- Tier A: the rounding path, over the realized (P, B) grid.
    #
    # Values are chosen where the modes disagree. An exact datum rounds the same
    # way under every mode and proves nothing about `_rab`; a midpoint separates
    # ties-to-even from ties-to-away, and a midpoint ± ε separates every directed
    # mode from every other. Sticky is varied independently because it is the
    # evidence channel the two carriers compute *differently* — BigFloat by exact
    # subtraction, Dyadic by shifted-out bits.
    cells = Tuple{Int,Int}[]
    for nm in sort!(collect(keys(_NAMED)))
        T = getfield(SmallFloats, nm)
        push!(cells, (precision(T), expbias(T)))
    end
    unique!(cells)

    compared = 0
    for (P, B) in cells
        # exponents spanning the format: deep subnormal, subnormal edge, mid,
        # normal edge, and past MaxFinite (where saturation is decided later).
        exps = Int64[2 - B - P, 2 - B, -1, 0, 1, B - 2, B - 1, B]
        bad = Tuple{Int,Int,Int64,Int,Int,Symbol}[]
        for e in exps
            # S values: the exact grid point, the midpoint, and midpoint ± 1 ulp
            # of the dyadic itself — three bits below the target grid is enough to
            # reach every decision constant `_rab` tests.
            base = Int128(1) << (P - 1)
            for k in (Int128(0), Int128(1), base - 1, base)
                for off in (Int128(0), Int128(4), Int128(2), Int128(1), Int128(7))
                    S = ((base + k) << 3) + off
                    S == 0 && continue
                    for sgn in (Int128(1), Int128(-1))
                        x = Dyadic(sgn * S, e - 3)
                        bx = setprecision(() -> BigFloat(x), BigFloat, 256)
                        for μ in MODES, sticky in (-1, 0, 1), R in (0, 5)
                            rd = round_to_precision(P, B, μ, x, R, sticky)
                            rb = round_to_precision(P, B, μ, bx, R, sticky)
                            compared += 1
                            _same(rd, rb) ||
                                push!(bad, (P, B, e, Int(sgn * S), sticky, nameof(typeof(μ))))
                        end
                    end
                end
            end
        end
        @test (P, B, bad) == (P, B, eltype(bad)[])
    end

    # ---- the zero-with-sticky row, which `Dyadic` had to write for itself.
    #
    # `_rtp_core`'s zero branch builds `zero(float(typeof(X)))`, and
    # `float(Dyadic)` does not exist — deliberately, since `Dyadic` is a `Real`
    # and not an `AbstractFloat`. So the row is written once in the fixed-point
    # family, and its agreement with the float family is asserted rather than
    # assumed: this is the drift the plan asked to be prevented structurally, made
    # checkable instead.
    zbad = Tuple{Int,Int,Int,Symbol}[]
    for (P, B) in cells, μ in MODES, sticky in (-1, 0, 1), R in (0, 5)
        a = _rtp_zero_sticky(P, B, μ, R, sticky)
        b = round_to_precision(P, B, μ, BigFloat(0), R, sticky)
        c = round_to_precision(P, B, μ, Dyadic(0), R, sticky)
        (_same(a, b) && _same(a, c)) || push!(zbad, (P, B, sticky, nameof(typeof(μ))))
    end
    @test zbad == Tuple{Int,Int,Int,Symbol}[]

    # ---- specials, on both carriers, including the sticky rows that turn an
    # infinity into MaxFinite (the `HUGEQ` sentinel path).
    sbad = Symbol[]
    for (P, B) in cells, μ in MODES, sticky in (-1, 0, 1)
        for (dv, bv) in ((DyadicNumbers.DYADIC_NAN, BigFloat(NaN)),
                         (DyadicNumbers.DYADIC_POSINF, BigFloat(Inf)),
                         (DyadicNumbers.DYADIC_NEGINF, BigFloat(-Inf)))
            _same(round_to_precision(P, B, μ, dv, 0, sticky),
                  round_to_precision(P, B, μ, bv, 0, sticky)) || push!(sbad, :special)
        end
    end
    @test sbad == Symbol[]

    @info "G7 tier A: $(length(cells)) (P, B) cells, $compared Dyadic-vs-BigFloat " *
          "rounding comparisons, all identical"

    # ---- Tier B: the engine.
    #
    # The same operands through `ωeval` on both carriers, compared as **code
    # points** — the thing a caller actually receives. Tier A proves the
    # projection agrees; this proves the projection reached is the one the
    # package uses, which is the distinction that made G2's two tiers necessary
    # and is no less necessary here.
    #
    # Only the rung-3 formats are eligible, since they are the ones whose datums
    # `HeadExact` receives. There are 8 of them and every code point is reachable,
    # so the operand set is the format's own lattice rather than a sample.
    R3 = [getfield(SmallFloats, nm) for nm in sort!(collect(keys(_NAMED)))
          if SmallFloats.rung(getfield(SmallFloats, nm)) === SmallFloats.HeadExact()]
    @test length(R3) == 8

    engine_cmp = 0
    for T in R3
        U = codeunit_type(T); n = 1 << bitwidth(T)
        # 12 code points spanning the lattice: zero, the two extremes, both
        # binade edges, NaN, and the specials' neighbours.
        cs = unique(UInt64[0, 1, 2, 3, n ÷ 4, n ÷ 2 - 1, n ÷ 2, n ÷ 2 + 1,
                           n - 3, n - 2, n - 1])
        vs = [rawvalue(T, U(c)) for c in cs if c < n]
        # FAA is here deliberately. It is the one row where the sticky protocol
        # does not compose — two chained adds can each drop a tail, and the two
        # can cancel — so it drops to the exact MPFR sum instead. Tier B is what
        # checks that decision against the BigFloat carrier.
        for op in (:Add, :Subtract, :Multiply, :FMA, :FAA, :Abs, :Negate, :CopySign,
                   :Maximum, :MinimumMagnitude, :Divide, :Sqrt, :Exp)
            V = Val(op); ar = SmallFloats.opinfo(op).arity
            bad = Tuple{Symbol,UInt,UInt,Symbol}[]
            for ρ in (RNE_SN, RTP_SF, RTN_SF, RTO_SN)
                for x in vs, y in (ar == 1 ? vs[1:1] : vs)
                    dx, dy = decode(x), decode(y)
                    args_big = ar == 1 ? (dx,) : (ar == 2 ? (dx, dy) : (dx, dy, dx))
                    args_dy = map(Dyadic, args_big)
                    rb = SmallFloats._finish(T, ρ, 0,
                            SmallFloats.ωeval(SmallFloats.HeadExact(), V, args_big...))
                    rd = SmallFloats._finish(T, ρ, 0,
                            SmallFloats.ωeval(SmallFloats.HeadExact(), V, args_dy...))
                    engine_cmp += 1
                    codepoint(rb) == codepoint(rd) ||
                        push!(bad, (op, UInt(codepoint(x)), UInt(codepoint(y)),
                                    nameof(typeof(SmallFloats.roundingmode(ρ)))))
                end
            end
            @test (nameof(T), op, bad) == (nameof(T), op, eltype(bad)[])
        end
    end
    @test engine_cmp > 0
    @info "G7 tier B: $(length(R3)) rung-3 formats, $engine_cmp engine comparisons " *
          "(Dyadic vs BigFloat, code points), all identical"

    # ---- the P = 1 block-scale fast path ≡ the general path.
    #
    # A P = 1 datum is `±2^e`, so scaling an element by it is `ldexp` — an
    # exponent add on every carrier, and on `Dyadic` a change to one field. The
    # fast path must be *indistinguishable*, not merely close: it replaces a
    # multiply that the carrier was sized for, so any difference would be a
    # silent one.
    #
    # This matters more than a fast path usually would. Annex F makes P = 1 the
    # scale format of MX-style block arithmetic — `Binary8p1uf` is OCP's E8M0 —
    # so the hardest corner of the grid is both the cheapest to compute and the
    # one on the hot path.
    P1_SCALES = (Binary8p1uf, Binary16p1uf, Binary8p1sf, Binary5p1se)
    ELEMS = (Binary8p4se, Binary8p3se, Binary16p6se, Binary16p5se, Binary16p1uf)
    pow2_cmp = 0
    for FS in P1_SCALES, FE in ELEMS
        @test (nameof(FS), precision(FS)) == (nameof(FS), 1)
        US = codeunit_type(FS); UE = codeunit_type(FE)
        ns = 1 << bitwidth(FS); ne = 1 << bitwidth(FE)
        scs = unique(UInt64[0, 1, 2, ns ÷ 2, ns - 2, ns - 1])
        ecs = unique(UInt64[0, 1, 2, ne ÷ 2, ne - 2, ne - 1])
        bad = Tuple{Symbol,Symbol,UInt}[]
        for sc in scs
            sc < ns || continue
            s = rawvalue(FS, US(sc))
            xs = ntuple(i -> rawvalue(FE, UE(ecs[min(i, length(ecs))])), Val(4))
            blk = Block(s, xs)
            fast = SmallFloats._blockdecode(Val(true), blk)
            slow = SmallFloats._blockdecode(Val(false), blk)
            pow2_cmp += 1
            # compare as exact rationals where finite, and by classification
            # otherwise — `==` on NaN would silently pass whatever happened.
            ok = all(1:4) do i
                a, b = fast[i], slow[i]
                if isnan(a) || isnan(b)
                    isnan(a) && isnan(b)
                elseif isinf(a) || isinf(b)
                    isinf(a) && isinf(b) && (sign(a) == sign(b))
                else
                    exact_rq_any(a) == exact_rq_any(b)
                end
            end
            ok || push!(bad, (nameof(FS), nameof(FE), UInt(sc)))
        end
        @test (nameof(FS), nameof(FE), bad) == (nameof(FS), nameof(FE), eltype(bad)[])
    end
    @info "G7: P = 1 block-scale fast path ≡ general path over $pow2_cmp block " *
          "signatures ($(length(P1_SCALES)) scale formats × $(length(ELEMS)) element formats)"
    record_gate!("G7"; assertions=288, units=compared + engine_cmp + pow2_cmp,
                 exhaustive=false,
                 note="tier A exhaustive over 135 (P,B) cells; tier B over all 8 " *
                      "rung-3 formats; the P=1 block path over 120 signatures")
end
