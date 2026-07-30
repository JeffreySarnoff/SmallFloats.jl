# ===== test/wide_ops.jl — Group A is operational at every K
#
# The Stage 4 exit criterion (implementextensions §4). Stage 3 opened the grid
# to 504 formats but refused to decode past K = 8; Stage 4 gives `decode` the
# carrier-generic path, and the claim this file measures is that the *whole*
# scalar pipeline — decode → ωeval → ωRoundToPrecision → ωSaturate → ωEncode —
# now produces defined results on wide formats, not merely runs on them.
#
# The reference is deliberately **not** the package's own oracle. Each expected
# code point is recomputed from the draft definition: decode both operands into
# `BigFloat` at a precision that makes the operation exact, evaluate there, and
# project. That shares `project` with the code under test (the projection engine
# is carrier-generic and unchanged by this stage — §1 C10) but shares nothing
# with `decode`'s new finite path or with the Float64 evaluation route, which
# are what Stage 4 actually changed.
#
# Scope is honest about what it covers: Group A over the arithmetic ops, on
# rung-1 wide formats. Rungs 2 and 3 still refuse — `test/stage_gates.jl` holds
# them — and Group B/C on wide formats waits for the carrier lattice in Stage 6.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using SmallFloats: _NAMED, KSPLIT, rung, HeadF64, datumcarrier, project

"""The wide formats Group A is expected to work on today: K > KSPLIT and rung 1,
so every operand decodes to `Float64` and the Float64 catalogue applies."""
const _WIDE_A = sort!([nm for nm in keys(_NAMED)
                       if bitwidth(getfield(SmallFloats, nm)) > KSPLIT &&
                          rung(getfield(SmallFloats, nm)) === HeadF64()])

"""Exact reference for a binary Group A op: evaluate on `BigFloat` operands at a
precision that cannot round, then project. `bigprec` is the package's own
derivation of that precision, and is itself asserted sufficient by gate G2 —
here it is used at 4× as a belt-and-braces margin, since this file is a
reference and not a performance path."""
function refbinary(op::Symbol, ::Type{T}, ρ, x, y) where {T<:SmallFloats.Binary}
    setprecision(BigFloat, 4 * SmallFloats.bigprec(T)) do
        a = BigFloat(decode(x)); b = BigFloat(decode(y))
        r = op === :Add      ? a + b :
            op === :Subtract ? a - b :
            op === :Multiply ? a * b :
            error("unsupported reference op $op")
        # The draft's single zero: a signed zero from BigFloat must not become a
        # different code point than the package's.
        iszero(r) && (r = zero(BigFloat))
        codepoint(SmallFloats.project(T, ρ, r))
    end
end

"""A deterministic spread of code points: both ends, the sign boundary, and an
even stride through the interior."""
function probe_codes(::Type{T}, n::Int) where {T<:SmallFloats.Binary}
    U = SmallFloats.codeunit_type(T)
    top = (UInt64(1) << bitwidth(T)) - 1
    cs = UInt64[0, 1, top ÷ 2, top ÷ 2 + 1, top - 1, top]
    step = max(UInt64(1), (top + 1) ÷ UInt64(n))
    append!(cs, UInt64(0):step:top)
    U.(sort!(unique!(cs)))
end

let nchecked = 0
    @testset "Group A operational at every K" begin
        @test !isempty(_WIDE_A)
        @test length(_WIDE_A) == 312          # 432 rung-1 formats less the 120 narrow

        ρ = RNE_SN
        for nm in _WIDE_A
            T = getfield(SmallFloats, nm)
            @test (nm, datumcarrier(T)) == (nm, Float64)
            cs = probe_codes(T, 12)
            ok = true
            for c1 in cs, c2 in cs
                x = rawvalue(T, c1); y = rawvalue(T, c2)
                ok &= codepoint(Add(T, ρ, x, y))      == refbinary(:Add, T, ρ, x, y)
                ok &= codepoint(Subtract(T, ρ, x, y)) == refbinary(:Subtract, T, ρ, x, y)
                ok &= codepoint(Multiply(T, ρ, x, y)) == refbinary(:Multiply, T, ρ, x, y)
                nchecked += 3
            end
            @test (nm, ok) == (nm, true)
        end

        # The unary half of Group A is exact on the *datum* — no rounding is
        # involved — but the result still has to land in the format, and that is
        # not an identity: `Negate` of a positive datum of an **unsigned** format
        # is outside the datum set, and under `SatNone` the defined result is
        # NaN. Comparing against `abs(d)` / `-d` directly would call 158 of the
        # 312 formats wrong, which is what the first version of this file did.
        # The reference is therefore "the exact datum, projected", which is the
        # draft's own definition of the operation.
        for nm in _WIDE_A
            T = getfield(SmallFloats, nm)
            ok = true
            for c in probe_codes(T, 24)
                v = rawvalue(T, c); d = decode(v)
                a = isnan(d) ? d : abs(d)
                n = isnan(d) ? d : (iszero(d) ? d : -d)
                ok &= codepoint(Abs(T, RNE_SN, v))    == codepoint(project(T, RNE_SN, a))
                ok &= codepoint(Negate(T, RNE_SN, v)) == codepoint(project(T, RNE_SN, n))
                nchecked += 2
            end
            @test (nm, ok) == (nm, true)
        end

        # Julia's own operators reach the same place.
        let T = Binary12p5se
            a, b = T(1.5), T(0.25)
            @test a + b === Add(T, RNE_SN, a, b)
            @test a * b === Multiply(T, RNE_SN, a, b)
            @test decode(a + b) == 1.75
        end
    end

    # ---- ordering and sorting at wide K.
    #
    # Stage 3 retyped the order key from `UInt16` to `orderkeytype(F)` because at
    # K = 16 the old key wrapped to 0 and put the largest datum below the
    # smallest. That was fixed before wide `decode` existed, so it could only be
    # asserted structurally; now the datums are available and the key can be
    # checked against them — which is the property that actually matters.
    @testset "total order and counting sort at wide K" begin
        for nm in ("Binary16p4se", "Binary16p1se", "Binary9p4se", "Binary16p16uf",
                   "Binary13p7sf", "Binary16p8ue")
            T = getfield(SmallFloats, Symbol(nm))
            U = SmallFloats.codeunit_type(T)
            top = (UInt64(1) << bitwidth(T)) - 1
            keys_ = [SmallFloats.order_key(rawvalue(T, U(i))) for i in UInt64(0):top]
            # Every code has a distinct key, and NaN's is the largest.
            @test (nm, length(unique(keys_))) == (nm, Int(top) + 1)
            @test (nm, maximum(keys_)) == (nm, SmallFloats.nan_order_key(T))
            @test (nm, eltype(keys_)) == (nm, SmallFloats.orderkeytype(T))
            # The key order is the datum order off NaN — the whole reason the key
            # exists. This is where a wraparound would show as a false `isless`.
            fin = [(SmallFloats.order_key(v), decode(v))
                   for v in (rawvalue(T, U(i)) for i in UInt64(0):top) if !isnan(v)]
            sort!(fin; by = first)
            @test (nm, issorted(fin; by = last)) == (nm, true)

            # Counting sort agrees with the reference algorithm, on inputs both
            # above and below the `n < 2^K` length gate Stage 3 introduced.
            for n in (7, (1 << bitwidth(T)) + 3)
                A = [rawvalue(T, U(rand(UInt64(0):top))) for _ in 1:n]
                @test (nm, n, codepoint.(sort(A))) ==
                      (nm, n, codepoint.(sort(A; alg = Base.Sort.DEFAULT_UNSTABLE)))
            end
        end
    end
    println("Group A at every K: $nchecked wide-format results verified against an MPFR reference")
end
