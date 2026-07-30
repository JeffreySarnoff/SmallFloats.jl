# ===== test/gates_shape.jl — Shape A ≡ Shape B
#
# implementextensions §4 Stage 5. From this stage on, every array kernel chooses
# between two implementations at run time: the table gather (Shape A) when the
# budget grants a table, and the per-element scalar path (Shape B) when it does
# not. The choice is made by a *policy* — two `Ref`s and a bitwidth sum — and it
# is allowed to be made differently on two machines, or on the same machine
# after a cache eviction.
#
# That is only acceptable because the two shapes cannot disagree, and the reason
# they cannot is invariant 6: a table entry IS the defined result, because the
# builder produces it with one trip through `_scalar_code` — the same function
# Shape B calls per element. Declining to build a table changes speed and
# nothing else.
#
# **This file is the difference between that being an argument and being a
# fact.** It runs every registry operation, at every arity, over *every* input
# code point of the signature, both ways, and compares code points. If the two
# shapes ever diverge, the array results become a function of cache state, which
# is the worst failure mode this package could have: not wrong, but wrong
# *sometimes*.
#
# Shape B is forced by lowering the build-cost band, not by calling an internal
# scalar helper directly. That matters — it exercises the real dispatch the real
# kernels take, including the `tbl === nothing` branch itself.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using SmallFloats: OP_REGISTRY, codeunit_type, table_for, _ternary_table_for,
                   TABLE_EAGER_BITS, TABLE_MAX_BITS, TERNARY_EAGER_BITS,
                   TERNARY_ADAPTIVE_BITS, empty_tables!, apply_op, _NAMED, KSPLIT,
                   tablebits, within_byte_budget

"""Run `f` with the table policy forced to decline, so kernels take Shape B."""
function force_shape_b(f)
    a, b, c = TABLE_EAGER_BITS[], TERNARY_EAGER_BITS[], TERNARY_ADAPTIVE_BITS[]
    TABLE_EAGER_BITS[] = -1; TERNARY_EAGER_BITS[] = -1; TERNARY_ADAPTIVE_BITS[] = -1
    try
        f()
    finally
        TABLE_EAGER_BITS[] = a; TERNARY_EAGER_BITS[] = b; TERNARY_ADAPTIVE_BITS[] = c
    end
end

"""Every code point of `F`, as values, ascending."""
allvals(::Type{F}) where {F<:SmallFloats.Binary} =
    [rawvalue(F, codeunit_type(F)(c)) for c in UInt64(0):((UInt64(1) << bitwidth(F)) - 1)]

"""The full cross product of two formats' code points, as a pair of vectors."""
function crossvals(::Type{F1}, ::Type{F2}) where {F1,F2}
    n1 = 1 << bitwidth(F1); n2 = 1 << bitwidth(F2)
    U1, U2 = codeunit_type(F1), codeunit_type(F2)
    A = Vector{F1}(undef, n1 * n2); B = Vector{F2}(undef, n1 * n2)
    k = 1
    for c1 in 0:(n1 - 1), c2 in 0:(n2 - 1)
        A[k] = rawvalue(F1, U1(c1)); B[k] = rawvalue(F2, U2(c2)); k += 1
    end
    (A, B)
end

_ops(arity::Int) = [o.name for o in OP_REGISTRY if o.arity == arity]

# Signatures deliberately chosen to put a table on BOTH sides of the code-unit
# seam, and to include a mixed-width one — a wide operand inside an affordable
# table is the case the widened builders exist for and the one a `UInt8`
# assumption would still break.
const UNARY_SIGS = (
    (Binary5p2se, Binary5p2se),      # narrow → narrow, UInt8 table
    (Binary8p4se, Binary8p4se),      # the largest narrow unary table
    (Binary9p4se, Binary9p4se),      # wide → wide, UInt16 table, 512 entries
    (Binary5p2se, Binary9p4se),      # wide operand, NARROW result: mixed units
    (Binary12p5se, Binary12p5se),    # 2^12 entries, UInt16
)
const BINARY_SIGS = (
    (Binary4p2se, Binary4p2se, Binary4p2se),
    (Binary5p2se, Binary5p2se, Binary3p1se),      # asymmetric: catches index-order bugs
    (Binary9p4se, Binary9p4se, Binary5p2se),      # 14 bits, wide operand + wide result
    (Binary4p2se, Binary9p4se, Binary4p2se),      # wide operand, narrow result
)
const TERNARY_SIGS = (
    (Binary4p2se, Binary4p2se, Binary4p2se, Binary4p2se),
    (Binary4p2se, Binary9p4se, Binary3p1se, Binary3p1se),   # 15 bits, wide operand
)
const SHAPE_RHOS = (RNE_SatNone, RNE_SatFinite, RTZ_SatPropagate, RTP_SatNone)

let ncmp = 0, nsig = 0
    @testset "Shape A ≡ Shape B" begin
        empty_tables!()

        # ---- The policy's K ≤ 8 non-regression, asserted on the policy itself
        # rather than inferred from G5 staying green. `TABLE_EAGER_BITS = 16` was
        # chosen as *exactly* the largest table the K ≤ 8 grid already builds, so
        # every narrow signature that tabulated before this stage must still
        # tabulate. If someone later lowers the band to buy build time, this is
        # what tells them they also changed which shape 120 formats take.
        @testset "no K ≤ 8 signature loses its table" begin
            narrow = sort!([nm for nm in keys(_NAMED)
                            if bitwidth(getfield(SmallFloats, nm)) <= KSPLIT])
            @test length(narrow) == 120
            ok_un = ok_bin = true
            for nm in narrow
                F = getfield(SmallFloats, nm)
                ok_un  &= bitwidth(F) <= TABLE_EAGER_BITS[] && within_byte_budget(F, F)
                ok_bin &= 2 * bitwidth(F) <= TABLE_EAGER_BITS[] && within_byte_budget(F, F, F)
            end
            @test ok_un && ok_bin
            # …and the boundary is where it was said to be: 8×8 fits, 9×8 does not.
            @test tablebits(Binary8p4se, Binary8p4se, Binary8p4se) == 16
            @test tablebits(Binary9p4se, Binary9p4se, Binary8p4se) == 18
            @test table_for(:Add, Binary8p4se, Binary8p4se, Binary8p4se, RNE_SatNone) !== nothing
            @test table_for(:Add, Binary9p4se, Binary9p4se, Binary8p4se, RNE_SatNone) === nothing
            # The byte budget is a separate question from the build band, and it
            # is the one that must never be computed by shifting: 3 × K = 16 is
            # 2^48 entries, and `1 << 48` is a perfectly ordinary `Int`.
            @test !within_byte_budget(Binary16p8se, Binary16p8se, Binary16p8se, Binary16p8se)
            @test tablebits(Binary16p8se, Binary16p8se, Binary16p8se, Binary16p8se) == 49
        end

        @testset "unary" begin
            for (FR, F1) in UNARY_SIGS, ρ in SHAPE_RHOS, op in _ops(1)
                A = allvals(F1)
                # Vacuity guard: if the policy declined a table here, the two
                # runs below would both be Shape B and the test would pass while
                # measuring nothing.
                @test (op, FR, F1, table_for(op, FR, F1, ρ) !== nothing) == (op, FR, F1, true)
                a = vmap!(similar(A, FR), Val(op), FR, ρ, A)
                b = force_shape_b(() -> vmap!(similar(A, FR), Val(op), FR, ρ, A))
                @test (op, FR, F1, codepoint.(a) == codepoint.(b)) == (op, FR, F1, true)
                ncmp += length(A); nsig += 1
            end
        end

        @testset "binary" begin
            for (FR, F1, F2) in BINARY_SIGS, ρ in SHAPE_RHOS, op in _ops(2)
                A, B = crossvals(F1, F2)
                @test (op, FR, table_for(op, FR, F1, F2, ρ) !== nothing) == (op, FR, true)
                a = vmap!(similar(A, FR), Val(op), FR, ρ, A, B)
                b = force_shape_b(() -> vmap!(similar(A, FR), Val(op), FR, ρ, A, B))
                @test (op, FR, F1, F2, codepoint.(a) == codepoint.(b)) == (op, FR, F1, F2, true)
                ncmp += length(A); nsig += 1
            end
        end

        @testset "ternary" begin
            for (FR, F1, F2, F3) in TERNARY_SIGS, ρ in (RNE_SatNone, RTZ_SatPropagate),
                op in _ops(3)
                A, B = crossvals(F1, F2)
                U3 = codeunit_type(F3)
                C = [rawvalue(F3, U3((i - 1) % (1 << bitwidth(F3)))) for i in eachindex(A)]
                @test (op, FR, _ternary_table_for(op, FR, F1, F2, F3, ρ, length(A)) !== nothing) ==
                      (op, FR, true)
                a = vmap!(similar(A, FR), Val(op), FR, ρ, A, B, C)
                b = force_shape_b(() -> vmap!(similar(A, FR), Val(op), FR, ρ, A, B, C))
                @test (op, FR, codepoint.(a) == codepoint.(b)) == (op, FR, true)
                ncmp += length(A); nsig += 1
            end
        end

        # The fallback is reached by the policy, not only by the forcing lever:
        # a genuinely over-budget signature must take Shape B on its own and
        # still agree with the scalar path element by element.
        @testset "over-budget signatures fall back on their own" begin
            W = Binary12p5se
            @test table_for(:Add, W, W, W, RNE_SatNone) === nothing      # 24 bits > 16
            A = [rawvalue(W, UInt16(c)) for c in 0:255:4095]
            B = reverse(A)
            for ρ in SHAPE_RHOS, op in (:Add, :Subtract, :Multiply, :Divide)
                got = vmap!(similar(A, W), Val(op), W, ρ, A, B)
                want = [apply_op(Val(op), W, ρ, 0, decode(A[i]), decode(B[i]))
                        for i in eachindex(A)]
                @test (op, codepoint.(got) == codepoint.(want)) == (op, true)
                ncmp += length(A)
            end
        end

        empty_tables!()
    end
    println("Shape A ≡ Shape B: $nsig signatures, $ncmp element comparisons, exhaustive over each signature's input space")
end
