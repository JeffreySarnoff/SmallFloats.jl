# ===== test/float32surface.jl — Float32/BFloat16 surface, carrier-exactness
#       trait, and κ-registered Float32 kernels (docs/other/Float32more.md)
#
# Enumerates rather than samples, per the suite doctrine. Registered kernels
# are unregistered on exit so the approx-registry state is unchanged for the
# harnesses that follow.

using BFloat16s: BFloat16

using SmallFloats: datumsexact, codeunit_type, KSPLIT

# The exactness claim is no longer "every format", because at K ≤ 16 it is not
# true of every format — it is true of every format `datumsexact` says it is
# true of, and that predicate is what `decode!` gates on. The test therefore
# enumerates the trait's *whole* domain and then tests its **boundary**: a
# format where the trait fails must actually fail, or the trait is merely a
# conservative guess wearing a theorem's clothes. (§4 Stage 4 item 6.)
const _NAMES = sort!(collect(keys(SmallFloats._NAMED)))
const _K8_FORMATS = filter(nm -> bitwidth(getfield(SmallFloats, nm)) <= KSPLIT, _NAMES)
const _F32_EXACT  = filter(nm -> datumsexact(Float32, getfield(SmallFloats, nm)), _NAMES)
const _BF16_EXACT = filter(nm -> datumsexact(BFloat16, getfield(SmallFloats, nm)), _NAMES)

"""One datum, exact in `X`? The unit of both sweeps below."""
function datum_exact(::Type{X}, v) where {X}
    d = decode(v)
    isnan(d) && return isnan(X(v))
    big(X(v)) == big(d)
end

"""Every datum of `T`, exact in `X`? Measured, not asked of the trait.

The extremal codes are probed **first**, and that is a cost decision rather than
a semantic one: `datumsexact` can only fail by range (the largest magnitudes) or
by underflow (the least positive datum), so a format the trait rejects has its
witness at one end of the lattice or the other. Probing them turns the
boundary sweep below from `2^K` `BigFloat` comparisons per rejected format into
a handful, which is what makes it affordable at all four target types instead of
only at `Float32`. The full sweep still runs — the probe is an accelerator for
the `false` answer, never a substitute for the `true` one."""
function all_datums_exact(::Type{X}, ::Type{T}) where {X,T}
    for v in (MaxFiniteOf(T), MinFiniteOf(T), MinPositiveOf(T))
        datum_exact(X, v) || return false
    end
    U = codeunit_type(T)
    for i in UInt64(0):((UInt64(1) << bitwidth(T)) - 1)
        datum_exact(X, rawvalue(T, U(i))) || return false
    end
    true
end

@testset "Float32/BFloat16 surface (M1)" begin
    @test length(_K8_FORMATS) == 120
    @test length(_F32_EXACT) == 376
    @test length(_BF16_EXACT) == 244
    # Every K ≤ 8 format is still in the exact set — the extension takes nothing
    # away from the grid that existed before it.
    @test _K8_FORMATS ⊆ _F32_EXACT && _K8_FORMATS ⊆ _BF16_EXACT

    @testset "exact decode over the trait's whole domain" begin
        for nm in _F32_EXACT
            @test (nm, all_datums_exact(Float32, getfield(SmallFloats, nm))) == (nm, true)
        end
        for nm in _BF16_EXACT
            @test (nm, all_datums_exact(BFloat16, getfield(SmallFloats, nm))) == (nm, true)
        end
    end

    @testset "the trait's boundary is real, not conservative" begin
        # For every format the trait REJECTS, some datum must genuinely fail to
        # round-trip. Without this the trait could refuse everything and the
        # suite above would still pass.
        #
        # All FOUR targets, not just `Float32`. The trait is one expression in
        # `(P, B)` against `_extexprange(X)`, so a defect in it is a defect at
        # every target — and it had one: the unsigned row of `emax` read `0`
        # where the decoder produces `B − 1`, masked at all four types because
        # the subnormal condition binds first at every power-of-two bias, with
        # exactly zero margin. A completeness sweep at one target could not
        # distinguish "the trait is tight" from "the trait is tight *here*".
        for X in (Float64, Float32, Float16, BFloat16), nm in _NAMES
            T = getfield(SmallFloats, nm)
            datumsexact(X, T) && continue
            @test (X, nm, all_datums_exact(X, T)) == (X, nm, false)
        end
    end

    @testset "decode! gather ≡ scalar surface" begin
        for T in (Binary8p4se, Binary8p1uf, Binary3p1se)
            A = [rawvalue(T, UInt8(c)) for c in 0:(1 << bitwidth(T)) - 1]
            @test isequal(decode!(similar(A, Float32), A), Float32.(A))
            @test isequal(decode!(similar(A, Float64), A), Float64.(A))
        end
        # The ComputeDecode branch, on a wide format that clears both gates.
        let T = Binary16p8se
            @test datumsexact(Float32, T) && datumsexact(Float64, T)
            A = [rawvalue(T, UInt16(c)) for c in 0:255:65535]
            @test isequal(decode!(similar(A, Float32), A), Float32.(A))
            @test isequal(decode!(similar(A, Float64), A), Float64.(A))
        end
        @test_throws DimensionMismatch decode!(zeros(Float32, 3), fill(zero(Binary8p4se), 4))

        # `decode!` promises exactness and must refuse rather than round. The
        # scalar conversions are NOT gated — `Float32(x)` rounds, by Julia
        # convention — so the pair below is the whole contract in two lines.
        let T = Binary16p2se                       # B = 8192: no external float holds it
            @test !datumsexact(Float32, T) && !datumsexact(Float64, T)
            A = [rawvalue(T, UInt16(c)) for c in 0:9]
            @test_throws ArgumentError decode!(zeros(Float32, 10), A)
            @test_throws ArgumentError decode!(zeros(Float64, 10), A)
            @test Float32.(A) isa Vector{Float32}   # rounding route stays open
        end
        # The 22-format band where the datums fit Float64 but the arithmetic
        # carrier is wider: `decode!` must accept these, which is exactly why
        # its gate is `datumsexact` and not `datumcarrier`.
        let T = Binary12p1se                       # B = 1024, carrier Float128
            @test SmallFloats.datumcarrier(T) === Float128
            @test datumsexact(Float64, T)
            A = [rawvalue(T, UInt16(c)) for c in 0:4095]
            @test isequal(decode!(similar(A, Float64), A), Float64.(A))
        end
    end

    @testset "array Convert ≡ scalar Convert" begin
        T = Binary8p4se
        X = [1.5f0, -0.26f0, 3.4f38, -1.0f-6, 0.0f0, Inf32, NaN32]
        # code-point comparison: `==` on Binary is IEEE-numeric (NaN unordered)
        samecodes(A, B) = codepoint.(A) == codepoint.(B)
        @test samecodes(Convert(T, RNE_SN, X), [Convert(T, RNE_SN, x) for x in X])
        Xb = BFloat16.([1.5, -0.25, 100.0])
        @test samecodes(Convert(T, RNE_SN, Xb), [Convert(T, RNE_SN, x) for x in Xb])
        ρ = RSA_SN(8)                     # stochastic: same seeded stream ⇒ same codes
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
    # The COUNTS are scoped to K ≤ 8 on purpose: they are a pinned measurement
    # over the grid they were measured on. The trait's DOMAIN is not — see the
    # wide-format section below.
    for name in _K8_FORMATS, op in (:Add, :Subtract, :Multiply)
        T = getfield(SmallFloats, name)
        g = f32_exact(op, T, T)
        counts[op] += g
        op === :Multiply && !g && push!(mulfail, name)
    end
    @test counts[:Multiply] == 118
    @test sort(mulfail) == [:Binary8p1ue, :Binary8p1uf]   # Float32 range exceeded
    @test counts[:Add] == 88
    @test counts[:Subtract] == 88
    @test_throws ArgumentError f32_exact(:Divide, Binary8p3se, Binary8p3se)

    # ---- the fast-`false` screen is a SUBSET of enumeration, not an equal.
    #
    # `f32_exact` answers `false` without enumerating when either format fails
    # `datumsexact(Float32, ·)`, justified by a witness construction (see the
    # comment at the screen). This checks the construction rather than trusting
    # it: exhaustive over all 120 K ≤ 8 formats × three ops.
    #
    # Implication, NOT equality — and that asymmetry is the content. Add and
    # Subtract fail 32 formats the screen passes, because those fail by
    # *arithmetic* (a Float32 sum of two exactly-represented datums can still be
    # inexact) rather than by datum representability. A test asserting equality
    # would fail on exactly those 32 and would be wrong to.
    @testset "screen ⊆ enumeration" begin
        for name in _K8_FORMATS, op in (:Add, :Subtract, :Multiply)
            T = getfield(SmallFloats, name)
            datumsexact(Float32, T) && continue          # screen did not fire
            @test (op, name, f32_exact(op, T, T)) == (op, name, false)
        end
    end

    # ---- the domain is every bitwidth, and the budget refuses by name.
    #
    # Until 2026-08-xx this threw `InexactError` for every K ≥ 9 format, from a
    # hardcoded `UInt8` in the enumeration bounds — an error about the storage
    # unit where the caller's question was about the format, and the same defect
    # `measure_kappa` had already fixed (its finding A1). The roll-call's
    # uncovered list recorded it as "enumeration at K ≥ 12", which implied
    # K = 9, 10, 11 worked; they did not.
    @testset "wide formats answer, and the budget refuses" begin
        # 2^18 pairs — inside the budget, and a format whose datums are all
        # Float32-exact, so the screen does not short-circuit the enumeration.
        @test datumsexact(Float32, Binary9p4se)
        @test f32_exact(:Multiply, Binary9p4se, Binary9p4se) isa Bool
        # The screen answers wide formats whose datums leave Float32's range,
        # with no enumeration and therefore no budget question.
        @test f32_exact(:Add, Binary16p1uf, Binary16p1uf) === false
        # 2^32 pairs — a cost refusal that names the budget, not a MethodError
        # and not an InexactError.
        err = try
            f32_exact(:Add, Binary16p8se, Binary16p8se); nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("pair budget", sprint(showerror, err))
    end
end

@testset "Float32 kernel family (M3)" begin
    T3, T1e = Binary8p3se, Binary8p1ue
    names = Symbol[]
    try
        # each registration measures κ exhaustively; κ = 0 is the shipped claim.
        # Multiply⟨8p1ue, SatPropagate⟩ exercises the overflow guard, Divide the
        # zero-divisor guard, Sqrt the negative-argument guard.
        for (op, T, ρ) in ((:Add, T3, RNE_SN),
                           (:Multiply, T1e, RNE_SP),
                           (:Divide, T3, RNE_SN))
            impl = register_f32!(op, T, (T, T), ρ)
            push!(names, impl.name)
            @test kappa(impl) == 0.0
            @test impl.exhaustive
        end
        impl = register_f32!(:Sqrt, T3, (T3,), RNE_SN)
        push!(names, impl.name)
        @test kappa(impl) == 0.0 && impl.exhaustive
        # retrieval by name; the kernel agrees with the defined result
        fn = approx(names[1]).fn
        @test fn(T3(1.5), T3(0.25)) == Add(T3, RNE_SN, T3(1.5), T3(0.25))
        # conformance reflects the registrations
        @test all(n -> any(a -> a.name == n, conformance().approximate), names)
        # policy gates: directed ρ and unaudited ops are rejected at build time
        @test_throws ArgumentError f32_impl(:Add, T3, RTZ_SN)
        @test_throws ArgumentError f32_impl(:Exp, T3, RNE_SN)
    finally
        foreach(unregister_approx!, names)     # leave the registry as found
    end
end
