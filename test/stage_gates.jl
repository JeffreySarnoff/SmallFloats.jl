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

    # ---- Rung 2 and rung 3 arithmetic: missing METHODS, named by stage.
    x = Binary8p4se(1.0)
    let e = try (Add(Binary16p2se, RNE_SatNone, x, x); nothing) catch e; e end
        @test e isa ArgumentError
        @test occursin("rung-2", e.msg) && occursin("Stage 6", e.msg)
    end
    let e = try (Multiply(Binary16p1uf, RNE_SatNone, x, x); nothing) catch e; e end
        @test e isa ArgumentError
        @test occursin("rung-3", e.msg)
    end

    # Same-format wide arithmetic reaches the refusal by a DIFFERENT route, and
    # the two must both be covered. Above, the operands are narrow and the
    # *result* is wide, so `apply_op` is entered with `Float64`s and Stage 3's
    # `ωeval(rung(fr), …)` gate fires. Here the operands decode to `Float128`
    # and never match `apply_op`'s `Float64` signature at all — which was a
    # `MethodError` until Stage 5 added the generic refusal. The gap was open
    # for one whole stage because this row did not exist.
    let W2 = Binary16p5se, v = W2(0x0100)     # B = 1024, rung 2
        @test rung(W2) === HeadF128()
        for f in (() -> Exp(W2, RNE_SatNone, v), () -> Add(W2, RNE_SatNone, v, v),
                  () -> Sqrt(W2, RNE_SatNone, v))
            e = try (f(); nothing) catch e; e end
            @test e isa ArgumentError
            @test occursin("Stage 6", e.msg)
        end
        # `Convert` is the exception, and legitimately so: it has no ω-semantics
        # to evaluate — it is a bare projection, and the projection engine is
        # carrier-generic already (§1 C10). Refusing it would be arbitrary.
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

    # ---- `show` must never be the thing that throws: a failing testset has to
    # be able to print the values it is comparing, at every carrier.
    @test repr(Binary8p4se(0x02)) == "Binary8p4se(0.001953125 ≡ 0x02)"
    @test repr(Binary12p5se(0x0abc)) == "Binary12p5se(-8.344650268554688e-7 ≡ 0x0abc)"
    for nm in sort!(collect(keys(_NAMED)))
        T = getfield(SmallFloats, nm)
        @test (nm, repr(T(zero(SmallFloats.codeunit_type(T)))) isa String) == (nm, true)
    end

end
