# ===== test/gates_g2.jl — G2: `bigprec` sufficiency
#
# *Protects:* the latent truncation that `_BIGP = 2200` becomes once B > 1024.
#
# A truncated "exact" BigFloat is the worst failure mode this package has
# available. It is not an exception and not a wrong-looking number: it is a
# plausible result, indistinguishable from the correct one without an
# independent reference. Every other gate here compares two things the package
# computes; this one has to compare against arithmetic the package cannot do.
#
# ---------------------------------------------------------------------------
# TWO TIERS, AND THE DIFFERENCE MATTERS
# ---------------------------------------------------------------------------
#
# **Tier A — the bound.** `bigprec(Fs…) ≥ spread + max Pᵢ + 1` for every format
# in the grid, with the spread *measured from the lattice* rather than taken
# from the closed form. Enumerable over all 504 formats, so it is enumerated.
# This tier is green from birth: `bigprec` was written correct in Stage 4 and
# merely left unwired. It proves the FORMULA.
#
# **Tier B — the engine.** The same witness driven through the shipped
# evaluation path and compared against `Rational{BigInt}`. This tier is the
# gate. It proves the formula is the one the package USES.
#
# Keeping them apart is the whole discipline. A G2 containing only Tier A
# passes on the day it is written and demonstrates nothing — the exact failure
# the plan's "write it red and watch it fail" exists to prevent. Whenever this
# file is edited, check that Tier B still reaches `apply_op`; a Tier B that
# quietly stopped exercising the engine looks identical to one that passes.
#
# ---------------------------------------------------------------------------
# WHY THE RED HAD TO WAIT FOR RUNG 3  (§11 M31)
# ---------------------------------------------------------------------------
#
# `_BIGP` is consumed by `_bigsum2`/`_bigfma`/`_bigsum3`, whose signatures are
# `Float64`. Float64's own exponent span is 2 097 bits, so `2200` is sufficient
# **by 49 bits** for every operand pair those functions can currently receive.
# The constant is not wrong today; it becomes wrong the moment a datum from a
# B = 32 768 format reaches them, and that requires rung-3 evaluation to exist.
#
# So the honest sequence is not "G2 red → fix". It is:
#
#   1. wire rung 3 the way one would without this gate — `_BIGP` untouched;
#   2. run G2; Tier B goes red on a **wrong datum**, not on a MethodError;
#   3. replace `_BIGP` with `bigprec`; Tier B goes green.
#
# Step 1 is not scaffolding for the test. It is the naive implementation, and
# the red is the evidence that writing it naively is wrong. A red obtained from
# the stage-refusal `ArgumentError` would have proved only that Stage 6 had not
# happened yet (§11 M28's lesson, one layer up: a refusal is not a disagreement).
#
# The recorded red is in [§11 M31](../docs/other/implementextensions.md).

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using SmallFloats: _NAMED, bigprec, expbias, precision, bitwidth, rawvalue,
                   codeunit_type, rung, HeadExact, roundingmode, saturationmode

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

include("refimpl.jl")     # Rational{BigInt} oracle; shares no code with the engine.
# NOTE: `refimpl`'s `refproject` still encodes by an O(2^K) scan typed `UInt8`,
# so it is K ≤ 8 only. G2 does not call it for the wide witness — it compares
# DATUMS via `refround`, which is K-generic (`P`/`B` are plain `Int`, the value
# is a rational). Widening the encode scan belongs with `refimpl`'s promotion to
# the shipped suite at Stage 8; doing it here would be a change no assertion in
# this file exercises.

# The retired constant, as a literal rather than an import. It no longer exists
# in `src/`, but "how much of the grid did it fail to cover" is this gate's own
# justification and has to survive its removal — otherwise the only surviving
# record that `bigprec` was necessary is a comment.
const _RETIRED_BIGP = 2200

# ---------------------------------------------------------------------------
# lattice-measured spread
# ---------------------------------------------------------------------------
# The exponent distance between a format's largest finite magnitude and its
# smallest positive one, obtained by DECODING EVERY CODE POINT. The closed form
# (`2B + P`) is what `bigprec` is derived from, so using it here would compare a
# formula against itself. A function barrier per format keeps the loop
# specialized on the carrier.
function lattice_spread(::Type{T}) where {T<:Binary}
    U = codeunit_type(T)
    hi = nothing; lo = nothing
    for c in 0:((1 << bitwidth(T)) - 1)
        d = decode(rawvalue(T, U(c)))
        (isfinite(d) && !iszero(d)) || continue
        a = abs(d)
        (hi === nothing || a > hi) && (hi = a)
        (lo === nothing || a < lo) && (lo = a)
    end
    hi === nothing && return 0
    Base.exponent(hi) - Base.exponent(lo)
end

@testset "G2 — bigprec sufficiency" begin

    fmts = [getfield(SmallFloats, nm) for nm in sort!(collect(keys(_NAMED)))]

    # ---- Tier A: the bound, over the whole grid, spread taken from the lattice.
    insufficient = 0
    spreads = Dict{DataType,Int}()
    for T in fmts
        sp = lattice_spread(T)
        spreads[T] = sp
        need = sp + precision(T) + 1          # exact sum of two datums of T
        @test (nameof(T), bigprec(T) >= need) == (nameof(T), true)
        @test (nameof(T), bigprec(T, T) >= need) == (nameof(T), true)
        _RETIRED_BIGP < need && (insufficient += 1)
    end
    # The point of the gate, stated as a number: the constant `bigprec` replaces
    # is NOT sufficient across this grid. If this ever reads 0, either the grid
    # shrank or `_BIGP` was raised instead of removed — both make Tier B vacuous.
    @test insufficient > 0
    @info "G2 tier A: $(length(fmts)) formats, spread measured from the lattice; " *
          "the retired _BIGP = $_RETIRED_BIGP was insufficient for $insufficient of them"

    # Mixed-format pairs: the join must cover the wider operand, not the result.
    for T in fmts, S in (Binary8p4se, Binary16p1uf, Binary16p8se)
        need = max(spreads[T], spreads[S]) + max(precision(T), precision(S)) + 1
        @test (nameof(T), nameof(S), bigprec(T, S) >= need) ==
              (nameof(T), nameof(S), true)
    end

    # ---- The witness (plan §3.3), confirmed against the lattice rather than assumed.
    W = Binary16p1uf
    @test expbias(W) == 32768
    @test precision(W) == 1
    @test rung(W) === HeadExact()
    @test Base.exponent(maxfinite_datum(W)) == 32766
    @test Base.exponent(decode(MinPositiveOf(W))) == -32767
    @test spreads[W] == 65533
    @test bigprec(W) >= 65533 + 1 + 1
    @test _RETIRED_BIGP < 65533 + 1 + 1          # the truncation, as a fact about numbers

    # ---- Tier B: the engine.
    #
    # Operands: a mid-range datum and the least positive one, so the exact sum is
    # strictly between two representable values and NO saturation is involved —
    # a red here can only be about precision. Under TowardPositive a residual of
    # any size promotes the result to the next datum; at 2 200 bits the residual
    # is 30× below the rounding position and vanishes, so the truncated engine
    # returns the operand unchanged.
    let a = W(1.0), b = MinPositiveOf(W), ρ = RTP_SF
        da, db = decode(a), decode(b)
        @test Base.exponent(da) == 0 && Base.exponent(db) == -32767

        exact = exact_rq(da) + exact_rq(db)                     # the ω-semantics, exactly
        sgn, S, Q = refround(precision(W), expbias(W), roundingmode(ρ), 0, exact)
        want = sgn * RQ(S) * pow2r(Q)               # the defined result, as a rational
        # in range, so ωSaturate is the identity and the code point follows the datum
        @test datum_rq(MinFiniteOf(W)) <= want <= datum_rq(MaxFiniteOf(W))
        @test want == RQ(2)                         # 1.0 promoted one binade (P = 1)

        got = Add(W, ρ, a, b)
        @test exact_rq(decode(got)) == want
        @test got === W(2.0)
    end

    # Subtract and FMA reach the same wide-spread tail by different routes.
    let a = W(1.0), b = MinPositiveOf(W), one_ = W(1.0)
        exact = exact_rq(decode(a)) - exact_rq(decode(b))
        sgn, S, Q = refround(precision(W), expbias(W), TowardNegative(), 0, exact)
        @test exact_rq(decode(Subtract(W, RTN_SF, a, b))) == sgn * RQ(S) * pow2r(Q)

        exact3 = exact_rq(decode(a)) * exact_rq(decode(one_)) + exact_rq(decode(b))
        sgn3, S3, Q3 = refround(precision(W), expbias(W), TowardPositive(), 0, exact3)
        @test exact_rq(decode(FMA(W, RTP_SF, a, one_, b))) == sgn3 * RQ(S3) * pow2r(Q3)
    end

    # FMA's worst case, where `bigprec`'s margin is thinnest — and the reason it
    # is nonetheless sufficient, which is not obvious and is worth pinning.
    #
    # The product carries 2P significand bits, so the exact sum needs
    # `spread + 2P + 1`, not `spread + P + 1`. That is still under `bigprec`
    # because its `+64` slack covers `P + 1` for every P ≤ 63. What bounds the
    # SPREAD is subtler: a product may be enormous, but if `|p|` exceeds
    # MaxFinite then so does `p + z` (a datum `z` cannot cancel it without being
    # comparable in magnitude, which makes the spread small), so both the exact
    # and any truncated evaluation land in the same saturation row. The spread
    # can only reach its maximum when the result is IN range — and there it is
    # bounded by the format's own spread, which is what `bigprec` is built from.
    #
    # Here `p = 2^32765` is the largest product that still leaves room for a
    # TowardPositive promotion without saturating: needed 65 535 bits, available
    # 65 602. Margin 67.
    let x = W(ldexp(BigFloat(1), 16383)), y = W(ldexp(BigFloat(1), 16382)),
        z = MinPositiveOf(W)
        @test Base.exponent(decode(x)) == 16383 && Base.exponent(decode(y)) == 16382
        exact = exact_rq(decode(x)) * exact_rq(decode(y)) + exact_rq(decode(z))
        sgn, S, Q = refround(precision(W), expbias(W), TowardPositive(), 0, exact)
        want = sgn * RQ(S) * pow2r(Q)
        @test want == datum_rq(MaxFiniteOf(W))         # promoted, still in range
        # Compared as a CODE POINT, not as a rational. The datums here have
        # ~32 800-bit numerators, and `@test a == b` on those prints both in
        # full: one failing row buried the other five under 30 000 digits. A
        # gate whose red is unreadable costs more than it pays. The rational
        # comparison is still made — it is the line above, against a reference
        # datum small enough to print — and this line ties the engine to it.
        @test FMA(W, RTP_SF, x, y, z) === MaxFiniteOf(W)
    end

    let V = Binary16p1sf                            # B = 16384, rung 3 as well
        @test rung(V) === HeadExact()
        a, b = V(1.0), MinPositiveOf(V)
        exact = exact_rq(decode(a)) + exact_rq(decode(b))
        sgn, S, Q = refround(precision(V), expbias(V), TowardPositive(), 0, exact)
        @test exact_rq(decode(Add(V, RTP_SF, a, b))) == sgn * RQ(S) * pow2r(Q)
    end

    # ---- RUNG 2 must be covered separately, and the reason is a defect this
    # gate did not catch when it only exercised rung 3.
    #
    # `bigprec` reads each operand's significand width. `Base.precision(v)` looks
    # like the way to get it — and Quadmath defines `precision(::Type{Float128})`
    # but **no value method**, so every rung-2 escalation was a `MethodError`.
    # Rung 3 could not reveal it: `BigFloat` *does* have a value method, and it
    # is the one where the per-value precision is what you actually want. Two
    # carriers, one of which happens to support the sloppy spelling.
    #
    # `Binary16p4se` has B = 2048: rung 2 by `2B = 4096 ≤ 16384`, and wide enough
    # that the retired constant was genuinely insufficient — which the assertion
    # below states rather than assumes, so this row cannot quietly become a
    # restatement of a case 2200 bits already covered.
    let U = Binary16p4se
        @test rung(U) === SmallFloats.HeadF128()
        @test expbias(U) == 2048
        a = U(ldexp(BigFloat(1), 1000)); b = MinPositiveOf(U)
        @test Base.exponent(decode(a)) == 1000
        realized = 1000 - Base.exponent(decode(b)) + precision(U) + 1
        @test realized > _RETIRED_BIGP            # would have truncated
        @test bigprec(U) >= realized              # does not

        exact = exact_rq(decode(a)) + exact_rq(decode(b))
        sgn, S, Q = refround(precision(U), expbias(U), TowardPositive(), 0, exact)
        want = sgn * RQ(S) * pow2r(Q)
        @test want > exact_rq(decode(a))                # the residual survives rounding
        @test exact_rq(decode(Add(U, RTP_SF, a, b))) == want

        # every Group A row at this rung, so a missing one is a failure and not a
        # silently untested carrier
        for (op, f) in ((:Subtract, () -> Subtract(U, RTN_SF, a, b)),
                        (:Multiply, () -> Multiply(U, RNE_SN, a, b)),
                        (:FMA, () -> FMA(U, RTP_SF, a, U(1.0), b)),
                        (:FAA, () -> FAA(U, RTP_SF, a, b, b)))
            @test (op, f() isa U) == (op, true)
        end
    end

    # ---- Non-regression at rung 1: the formats G5 pins must be untouched by the
    # switch from a constant to a function. `refproject`'s encode scan is K ≤ 8,
    # so here it is safe to use the reference end to end.
    for T in (Binary8p4se, Binary8p3se, Binary6p3se), ρ in (RNE_SN, RTP_SF)
        for ca in 0x00:0x0f, cb in 0x00:0x0f
            x, y = T(ca), T(cb)
            r = refop2(:Add, x, y)
            r isa Float64 && isnan(r) && continue
            @test codepoint(Add(T, ρ, x, y)) == refproject(T, ρ, r)
        end
    end
    record_gate!("G2"; assertions=4088, units=4088, exhaustive=false,
                 note="tier A sweeps all 504 formats' spreads; tier B's engine " *
                      "comparison is over the wide witnesses, not the whole grid")
end
