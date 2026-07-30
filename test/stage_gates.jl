# ===== test/stage_gates.jl — what is NOT implemented yet, asserted
#
# The K ≤ 16 extension lands in ten stages, and between them the package is
# genuinely partial: the 504-format grid exists from Stage 3, but the carriers
# and the wide decode path arrive in Stages 4–7. This file pins the *shape* of
# that partiality — that every unimplemented route fails loudly, immediately,
# and with a message naming the stage that will finish it.
#
# It is deliberately a test rather than a comment. An unimplemented path that
# throws is a design decision; an unimplemented path that returns a plausible
# wrong number is a defect, and the only difference between them is whether
# anything checks.
#
# **This file shrinks as the extension lands.** A row here becoming red because
# the operation started working is the expected way for it to die: delete the
# row in the same commit that implements it. A row going red because the
# *exception type or wording* drifted is a real failure — the messages are the
# user-facing contract of a staged release.

using Test, SmallFloats
using Quadmath: Float128
using SmallFloats: _NAMED, KMIN, KMAX, KSPLIT, rung, HeadF64, HeadF128, HeadExact,
                   decodepolicy, TableDecode, ComputeDecode, expbias, bitwidth

@testset "stage gates — unimplemented routes fail loudly" begin

    # ---- `rung` is TOTAL (invariant 9). A trait that throws over a third of its
    # domain is not a trait; the missing thing is the evaluator, not the answer.
    # Checked over all 504 formats, and against the §3.3 rung boundaries.
    for nm in sort!(collect(keys(_NAMED)))
        T = getfield(SmallFloats, nm)
        B = expbias(T)
        want = B <= 512 ? HeadF64() : B <= 8192 ? HeadF128() : HeadExact()
        @test (nm, rung(T)) == (nm, want)
    end
    # Every K ≤ 8 format is rung 1 — the premise that makes gating Stage 3's
    # arithmetic on the RESULT format alone complete (see oracle.jl).
    for nm in keys(_NAMED)
        T = getfield(SmallFloats, nm)
        bitwidth(T) <= KSPLIT && @test (nm, rung(T)) == (nm, HeadF64())
    end

    # ---- Group A arithmetic at every rung LANDED in Stage 6, and the two rows
    # that used to assert it refused went red by being implemented — the intended
    # way for a row here to die.
    #
    # Their replacement is the correction that made them die, which is worth an
    # assertion of its own. Stage 3 selected the carrier from the RESULT format as
    # a stand-in gate. `carriers.jl` states the opposite rule: the carrier is a
    # property of values in flight, never of the format being projected into. So
    # narrow operands with a wide result need no wide carrier at all, and refusing
    # them was always wrong — the exact sum of two Float64 datums is a Float64.
    x = Binary8p4se(1.0)
    @test Add(Binary16p2se, RNE_SatNone, x, x) === Binary16p2se(2.0)
    @test Multiply(Binary16p1uf, RNE_SatNone, Binary8p4se(1.5), Binary8p4se(0.5)) ===
          Binary16p1uf(0.75)

    # Same-format wide arithmetic reaches the evaluator by a DIFFERENT route, and
    # both are still covered. Above, the operands are narrow, so `apply_op`'s
    # `Float64` method is entered. Here they decode to `Float128` and take the
    # generic method, which joins the operands' heads and lifts onto the winner.
    # That gap was a `MethodError` for a whole stage (§11 M28) because no row
    # exercised this second route.
    let W2 = Binary16p5se, v = W2(0x0100), u = W2(1.5)   # B = 1024, rung 2
        @test rung(W2) === HeadF128()
        @test decode(v) isa Float128
        for f in (() -> Add(W2, RNE_SatNone, u, v), () -> Subtract(W2, RNE_SatNone, u, v),
                  () -> Multiply(W2, RNE_SatNone, u, v), () -> FMA(W2, RNE_SatNone, u, v, u),
                  () -> FAA(W2, RNE_SatNone, u, v, u))
            @test f() isa W2
        end
        # Mixed carriers: the operands decode to different types and no `ωeval`
        # row is written for a mixed pair. `lift` closes that, and the join is
        # what guarantees it never has to narrow.
        @test Add(W2, RNE_SatNone, u, Binary8p4se(1.5)) === W2(3.0)

        # The enclosure ladder LANDED at every rung, so the two rows that asserted
        # `Exp` and `Sqrt` still refused here went red by being implemented —
        # again the intended way for a row in this file to die.
        #
        # What replaces them is the property that made widening safe: at rungs 2
        # and 3 the `yd`/`fq` filters are dropped and the rigorous MPFR ladder
        # decides alone. `EncloseF.yd` is a `Float64` field and `fq` narrows to
        # `Float128`, so for a wide datum neither can even represent the operand;
        # dropping them is structural, not a tuning choice.
        for f in (() -> Exp(W2, RNE_SatNone, v), () -> Sqrt(W2, RNE_SatNone, v),
                  () -> Divide(W2, RNE_SatNone, u, v), () -> Hypot(W2, RNE_SatNone, u, v),
                  () -> SinPi(W2, RNE_SatNone, u), () -> Softplus(W2, RNE_SatNone, u))
            @test f() isa W2
        end
        # The ladder-only shape, asserted directly rather than inferred from the
        # result: a wide operand must produce an `EncloseF` with no filters.
        let r = SmallFloats.ωeval(SmallFloats.HeadF128(), Val(:Exp), decode(v))
            @test r isa SmallFloats.EncloseF
            @test r.fq === nothing
            @test isnan(r.yd)
        end
        # …while the Float64 tier keeps both filters, so this is a carrier
        # distinction and not a silent loss of the fast path.
        let r = SmallFloats.ωeval(Val(:Exp), 1.5)
            @test r isa SmallFloats.EncloseF
            @test r.fq !== nothing
            @test !isnan(r.yd)
        end
        # `Convert` was never refused, and legitimately so: it has no ω-semantics
        # to evaluate — it is a bare projection, and the projection engine is
        # carrier-generic already (§1 C10).
        @test decode(Convert(W2, RNE_SatNone, Binary8p4se(1.5))) == 1.5
    end

    # ---- Wide decode LANDED in Stage 4; what remains asserted is that the two
    # policies are still selected by the representation and that the `2^K`
    # constant table is still refused for `Code16` (invariant 10) even though
    # decoding itself now works.
    @test decodepolicy(Binary8p4se) === TableDecode()
    @test decodepolicy(Binary12p5se) === ComputeDecode()
    let e = try (SmallFloats._decode_table(Binary12p5se); nothing) catch e; e end
        @test e isa ArgumentError
        @test occursin("invariant 10", e.msg)
    end
    let e = try (SmallFloats._decode_table32(Binary12p5se); nothing) catch e; e end
        @test e isa ArgumentError
    end

    # ---- Array/table routes at wide K LANDED in Stage 5. This block used to
    # assert that they refused; those rows went red by being implemented, which
    # is exactly how a row in this file is meant to die. What replaces them is
    # the boundary that remains: an over-budget signature falls back to Shape B
    # rather than throwing, while `get_table` — whose contract is to *return a
    # table* — still throws, and now names the budget rather than a stage.
    let W = Binary12p5se, a = W(1.5), b = W(0.25)
        @test vmap!(similar([a, b]), Val(:Add), W, RNE_SatNone, [a, b], [b, a]) ==
              [Add(W, RNE_SatNone, a, b), Add(W, RNE_SatNone, b, a)]
        @test SmallFloats.table_for(:Add, W, W, W, RNE_SatNone) === nothing   # 24 bits > 16
        @test SmallFloats.table_for(:Exp, W, W, RNE_SatNone) isa Memory{UInt16}
        e = try (SmallFloats.get_table(:Add, Binary16p8se, Binary16p8se,
                                       Binary16p8se, RNE_SatNone); nothing) catch e; e end
        @test e isa ArgumentError
        @test occursin("budget", e.msg) && !occursin("Stage", e.msg)
    end

    # ---- Carrier-aware promotion (§2 R-E). `Binary ⋄ external` targets
    # `promotecarrier(F)`, not `Float64`.
    #
    # This is the one wide-K defect that was reachable from ordinary user code
    # with no P3109 operation involved at all: `x + 1.0` promoted a B = 32 768
    # datum into a carrier that cannot represent it. The result was not an error
    # — it was ±Inf from a perfectly finite value.
    @test promote_type(Binary8p4se, Float64) === Float64
    @test promote_type(Binary16p6se, Float64) === Float64      # rung 1 at K = 16
    @test promote_type(Binary16p5se, Float64) === Float128     # rung 2
    @test promote_type(Binary16p1uf, Float64) === BigFloat     # rung 3
    @test promote_type(Binary16p1uf, Int) === BigFloat
    @test promote_type(Binary8p4se, Float128) === Float128     # never narrows
    @test promote_type(Binary8p4se, BigFloat) === BigFloat
    let s = MaxFiniteOf(Binary16p1uf) + 1.0
        @test s isa BigFloat
        @test isfinite(s)                                      # was ±Inf under Float64
        @test s > big(2)^32765
    end
    @test Binary8p4se(1.5) + 0.25 === 1.75                     # narrow path unchanged
    # the conversions promotion resolves to must exist and be exact
    @test BigFloat(Binary16p1uf(1.0)) == 1
    @test Float128(Binary16p5se(1.5)) == Float128(1.5)

    # ---- `show` must never be the thing that throws: a failing testset has to
    # be able to print the values it is comparing, at every carrier.
    @test repr(Binary8p4se(0x02)) == "Binary8p4se(0.001953125 ≡ 0x02)"
    @test repr(Binary12p5se(0x0abc)) == "Binary12p5se(-8.344650268554688e-7 ≡ 0x0abc)"
    for nm in sort!(collect(keys(_NAMED)))
        T = getfield(SmallFloats, nm)
        @test (nm, repr(T(zero(SmallFloats.codeunit_type(T)))) isa String) == (nm, true)
    end

end
