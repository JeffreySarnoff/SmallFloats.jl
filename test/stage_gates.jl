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

    # ---- Wide decode: refused until the carrier-generic finite path exists.
    # `_decode_compute`'s tail is still the Float64 bit assembly whose premise is
    # exactly K ≤ 8, so the alternative to refusing is a wrong answer.
    @test decodepolicy(Binary8p4se) === TableDecode()
    @test decodepolicy(Binary12p5se) === ComputeDecode()
    let e = try (decode(Binary12p5se(0x0abc)); nothing) catch e; e end
        @test e isa ArgumentError
        @test occursin("Stage 4", e.msg)
    end

    # ---- `show` must never be the thing that throws: a failing testset has to
    # be able to print the values it is comparing.
    @test repr(Binary12p5se(0x0abc)) == "Binary12p5se(0x0abc)"
    @test repr(Binary8p4se(0x02)) == "Binary8p4se(0.001953125 ≡ 0x02)"

end
