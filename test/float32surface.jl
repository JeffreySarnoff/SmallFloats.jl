# ===== test/float32surface.jl — Float32/BFloat16 surface, carrier-exactness
#       trait, and κ-registered Float32 kernels (docs/other/Float32more.md)
#
# Enumerates rather than samples, per the suite doctrine. Registered kernels
# are unregistered on exit so the approx-registry state is unchanged for the
# harnesses that follow.

using BFloat16s: BFloat16

@testset "Float32/BFloat16 surface (M1)" begin
    @testset "exact decode, every format × every code" begin
        nf32 = nbf16 = 0
        for T in values(SmallFloats._NAMED)
            for c in 0x00:UInt8((1 << bitwidth(T)) - 1)
                v = rawvalue(T, c); d = decode(v)
                if isnan(d)
                    nf32 += isnan(Float32(v)); nbf16 += isnan(BFloat16(v))
                else
                    nf32 += Float64(Float32(v)) == d
                    nbf16 += Float64(BFloat16(v)) == d
                end
            end
        end
        total = sum(1 << bitwidth(T) for T in values(SmallFloats._NAMED))
        @test nf32 == total          # Float32 narrowing exact, all datums
        @test nbf16 == total         # BFloat16 narrowing exact, all datums
    end

    @testset "decode! gather ≡ scalar surface" begin
        for T in (Binary8p4se, Binary8p1uf, Binary3p1se)
            A = [rawvalue(T, UInt8(c)) for c in 0:(1 << bitwidth(T)) - 1]
            @test isequal(decode!(similar(A, Float32), A), Float32.(A))
            @test isequal(decode!(similar(A, Float64), A), Float64.(A))
        end
        @test_throws DimensionMismatch decode!(zeros(Float32, 3), fill(zero(Binary8p4se), 4))
    end

    @testset "array Convert ≡ scalar Convert" begin
        T = Binary8p4se
        X = [1.5f0, -0.26f0, 3.4f38, -1.0f-6, 0.0f0, Inf32, NaN32]
        # code-point comparison: `==` on Binary is IEEE-numeric (NaN unordered)
        samecodes(A, B) = codepoint.(A) == codepoint.(B)
        @test samecodes(Convert(T, RNE_SatNone, X), [Convert(T, RNE_SatNone, x) for x in X])
        Xb = BFloat16.([1.5, -0.25, 100.0])
        @test samecodes(Convert(T, RNE_SatNone, Xb), [Convert(T, RNE_SatNone, x) for x in Xb])
        ρ = RSA_SatNone(8)                     # stochastic: same seeded stream ⇒ same codes
        @test samecodes(Convert(T, ρ, X; rng=Xoshiro(42)),
                        let rng = Xoshiro(42); [Convert(T, ρ, x; rng) for x in X] end)
    end

    @testset "BFloat16 promotion" begin
        T = Binary8p4se
        @test promote_type(T, BFloat16) === Float64
        @test T(1.5) * BFloat16(2) === 3.0
    end
end

@testset "f32_exact carrier trait (M2)" begin
    # measured gate contents, pinned (docs/other/Float32more.md §3.2):
    # Multiply 118/120 same-format signatures; Add and Subtract 88/120.
    counts = Dict(op => 0 for op in (:Add, :Subtract, :Multiply))
    mulfail = Symbol[]
    for (name, T) in SmallFloats._NAMED, op in (:Add, :Subtract, :Multiply)
        g = f32_exact(op, T, T)
        counts[op] += g
        op === :Multiply && !g && push!(mulfail, name)
    end
    @test counts[:Multiply] == 118
    @test sort(mulfail) == [:Binary8p1ue, :Binary8p1uf]   # Float32 range exceeded
    @test counts[:Add] == 88
    @test counts[:Subtract] == 88
    @test_throws ArgumentError f32_exact(:Divide, Binary8p3se, Binary8p3se)
end

@testset "Float32 kernel family (M3)" begin
    T3, T1e = Binary8p3se, Binary8p1ue
    names = Symbol[]
    try
        # each registration measures κ exhaustively; κ = 0 is the shipped claim.
        # Multiply⟨8p1ue, SatPropagate⟩ exercises the overflow guard, Divide the
        # zero-divisor guard, Sqrt the negative-argument guard.
        for (op, T, ρ) in ((:Add, T3, RNE_SatNone),
                           (:Multiply, T1e, RNE_SatPropagate),
                           (:Divide, T3, RNE_SatNone))
            impl = register_f32!(op, T, (T, T), ρ)
            push!(names, impl.name)
            @test kappa(impl) == 0.0
            @test impl.exhaustive
        end
        impl = register_f32!(:Sqrt, T3, (T3,), RNE_SatNone)
        push!(names, impl.name)
        @test kappa(impl) == 0.0 && impl.exhaustive
        # retrieval by name; the kernel agrees with the defined result
        fn = approx(names[1]).fn
        @test fn(T3(1.5), T3(0.25)) == Add(T3, RNE_SatNone, T3(1.5), T3(0.25))
        # conformance reflects the registrations
        @test all(n -> any(a -> a.name == n, conformance().approximate), names)
        # policy gates: directed ρ and unaudited ops are rejected at build time
        @test_throws ArgumentError f32_impl(:Add, T3, RTZ_SatNone)
        @test_throws ArgumentError f32_impl(:Exp, T3, RNE_SatNone)
    finally
        foreach(unregister_approx!, names)     # leave the registry as found
    end
end
