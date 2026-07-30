# ===== test/dyadic_rational.jl — the Dyadic ↔ Rational bridge
#
# The edge tables of docs/other/dyadic_rational.md §3.2 and §4.2, one assertion
# each. These are enumerable and finite, so there is no reason to sample.
#
# The design document exists because the conversion that was already in the
# package **threw on ±Inf** while `Rational{BigInt}(Inf)` returns `1//0`. That
# defect survived because nothing compared the two, so the first thing this file
# does is compare them — and against `Base`, not against a literal, so the
# assertion tracks Base if Base ever changes its mind.
#
# The lattice-wide law (every code point round-trips through `Rational`) is NOT
# here: it rides in `tier_t1.jl`'s single pass, because that file's cost is
# specialization and a separate 504-format sweep would pay the compilation twice
# for the same 7 602 160 points.

using Test, SmallFloats
using SmallFloats.Formats
using SmallFloats.DyadicNumbers: Dyadic, dyadic_to_rational, rational_to_dyadic,
                                 isdyadic, dyadic_from,
                                 DYADIC_ZERO, DYADIC_POSINF, DYADIC_NEGINF,
                                 DYADIC_NAN

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

_D(S, Q) = Dyadic(Int128(S), Int64(Q))

@testset "Dyadic ↔ Rational" begin
    units = Ref(0)
    bump() = (units[] += 1; true)

    # ---- §3.2: dyadic_to_rational, every row
    @testset "dyadic_to_rational edges" begin
        for (name, x, want) in (
                ("finite",            _D(3, -1),               3 // 2),
                ("unnormalized",      _D(6, -2),               3 // 2),
                ("more unnormalized", _D(24, -4),              3 // 2),
                ("zero, Q ignored",   _D(0, 5),                0 // 1),
                ("zero, Q negative",  _D(0, -5),               0 // 1),
                ("integral",          _D(3, 4),                48 // 1),
                ("negative",          _D(-5, 3),               -40 // 1),
                ("deep subnormal",    _D(7, -40),              BigInt(7) // (BigInt(1) << 40)),
                ("typemin(Int128)",   _D(typemin(Int128), 0),  BigInt(typemin(Int128)) // 1),
                ("+Inf",              DYADIC_POSINF,           1 // 0),
                ("-Inf",              DYADIC_NEGINF,           -1 // 0))
            bump()
            @test (name, dyadic_to_rational(x) == want) == (name, true)
        end

        # NaN is the one row with no rational slot. Base rejects `0//0` too.
        @test_throws InexactError dyadic_to_rational(DYADIC_NAN)
        bump()

        # The correction this bridge carries, asserted against BASE rather than
        # against a literal — so the test follows Base rather than freezing a
        # snapshot of it.
        @test dyadic_to_rational(DYADIC_POSINF) == Rational{BigInt}(Inf)
        @test dyadic_to_rational(DYADIC_NEGINF) == Rational{BigInt}(-Inf)
        bump(); bump()

        # The result is REDUCED: `unsafe_rational` is used, so the invariant it
        # skips checking must be established by the shift. An unreduced result
        # would be a corrupt `Rational` that compares wrong later, silently.
        for (S, Q) in ((6, -2), (24, -4), (1 << 20, -30), (12, -3))
            q = dyadic_to_rational(_D(S, Q))
            bump()
            @test (S, Q, gcd(numerator(q), denominator(q))) == (S, Q, 1)
        end
    end

    # ---- narrow targets: checked, never wrapped
    @testset "narrow target types" begin
        @test dyadic_to_rational(Int64, _D(3, -1)) === Rational{Int64}(3, 2)
        @test dyadic_to_rational(Int128, _D(3, -1)) === Rational{Int128}(3, 2)
        @test_throws OverflowError dyadic_to_rational(Int64, _D(1, -200))
        @test_throws OverflowError dyadic_to_rational(Int64, _D(1, 200))
        # BigInt is the total case and must never throw for a finite input
        @test dyadic_to_rational(BigInt, _D(1, -20_000)) ==
              BigInt(1) // (BigInt(1) << 20_000)
        units[] += 5
    end

    # ---- §4.2: rational_to_dyadic, every row
    @testset "rational_to_dyadic edges" begin
        for (name, q, want) in (
                ("half",        3 // 2,            _D(3, -1)),
                ("negative",    -7 // 8,           _D(-7, -3)),
                ("zero",        0 // 1,            DYADIC_ZERO),
                ("integer",     5 // 1,            _D(5, 0)),
                ("even integer", 8 // 1,           _D(1, 3)),
                ("tiny",        1 // 1024,         _D(1, -10)),
                ("+Inf",        1 // 0,            DYADIC_POSINF),
                ("-Inf",        -1 // 0,           DYADIC_NEGINF))
            bump()
            @test (name, rational_to_dyadic(q) == want) == (name, true)
        end

        # Refuses rather than rounds: rounding here would round outside `project`.
        for q in (1 // 3, 2 // 3, 5 // 6, -1 // 7, 1 // 100)
            @test_throws InexactError rational_to_dyadic(q)
            units[] += 1
        end

        # Never assumes the input is reduced. `unsafe_rational(2, 4)` is a legal
        # hand-built value that violates Rational's invariant; the power-of-two
        # test and the trailing-zero strip are correct on it anyway.
        @test rational_to_dyadic(Base.unsafe_rational(2, 4)) == _D(1, -1)
        @test rational_to_dyadic(Base.unsafe_rational(6, 8)) == _D(3, -2)
        units[] += 2

        # A significand too wide for Int128.
        @test_throws InexactError rational_to_dyadic(
            (BigInt(1) << 200 + 1) // BigInt(1))
        units[] += 1
    end

    # ---- isdyadic agrees with the conversion's success, over a structured set
    @testset "isdyadic ⟺ convertible" begin
        qs = Rational{BigInt}[3//2, -7//8, 0//1, 5//1, 1//1024, 1//0, -1//0,
                              1//3, 2//3, -1//7, 5//6, 1//100, 7//64]
        for q in qs
            ok = isdyadic(q)
            converted = try
                rational_to_dyadic(q); true
            catch
                false
            end
            units[] += 1
            @test (q, ok) == (q, converted)
        end
    end

    # ---- the three round-trip laws (§5), stated on VALUES
    @testset "round-trip laws" begin
        xs = [_D(3, -1), _D(6, -2), _D(12, -3), _D(0, 7), _D(1, 0), _D(-5, 3),
              _D(typemin(Int128), 0), _D(7, -40), _D(typemax(Int128), -3),
              DYADIC_POSINF, DYADIC_NEGINF]

        # Law 1 — value round trip. `==` on Dyadic compares values via cmp_dy,
        # which is the point: the fields are NOT preserved.
        for x in xs
            units[] += 1
            @test rational_to_dyadic(dyadic_to_rational(x)) == x
        end

        # Law 1 is the one a fields-based implementation would break, so it is
        # targeted directly: the same value at several representations must all
        # round-trip to the same value.
        for j in 0:20
            x = _D(BigInt(3) << j, -1 - j)
            units[] += 1
            @test rational_to_dyadic(dyadic_to_rational(x)) == _D(3, -1)
        end

        # Law 2 — Rational round trip is the identity. `Rational` is canonical,
        # so this pins the value AND the reduction.
        for q in (3//2, -7//8, 0//1, 5//1, 1//1024, -1//0, 1//0, 7//64)
            units[] += 1
            @test dyadic_to_rational(rational_to_dyadic(q)) == Rational{BigInt}(q)
        end

        # Law 3 — the composition is the canonical form, and is idempotent.
        # Applying it twice must not move the FIELDS, not merely the value.
        for x in (_D(6, -2), _D(24, -4), _D(1 << 20, -30), _D(3, -1))
            a = rational_to_dyadic(dyadic_to_rational(x))
            b = rational_to_dyadic(dyadic_to_rational(a))
            units[] += 1
            @test (a.S, a.Q) == (b.S, b.Q)
        end

        # …and the canonical form really is "odd significand or zero".
        for x in (_D(6, -2), _D(24, -4), _D(1 << 20, -30))
            a = rational_to_dyadic(dyadic_to_rational(x))
            units[] += 1
            @test (x.S, isodd(a.S)) == (x.S, true)
        end
    end

    # ---- the constructor aliases are the same functions, not a second copy
    @testset "constructor forms" begin
        @test Rational{BigInt}(_D(3, -1)) == dyadic_to_rational(_D(3, -1))
        @test Rational{Int64}(_D(3, -1)) === dyadic_to_rational(Int64, _D(3, -1))
        @test Dyadic(3 // 4) == rational_to_dyadic(3 // 4)
        units[] += 3
    end

    record_gate!("D↔Q"; assertions = 90, units = units[], exhaustive = true,
                 note = "")
    @info "Dyadic↔Rational: $(units[]) edge and law assertions over the §3.2 " *
          "and §4.2 tables — exhaustive over the enumerable edges. The " *
          "lattice-wide identity (every code point round-trips) is T1's, in " *
          "T1's single pass."
end
