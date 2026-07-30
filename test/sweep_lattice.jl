# ===== test/sweep_lattice.jl — the front-loaded construction sweep
#
# implementextensions.md §4 Stage 3 item 4. Runs BEFORE anything else the stage
# adds, and deliberately so: it constructs every code point of every one of the
# 504 formats — 7 602 160 points — through the checked constructor and the
# unchecked kernel route, at every offered `Unsigned` width.
#
# The reason it is worth its own file and its own position is §1 C5. The audit
# looked for *silent* truncation at K ≥ 9 and found the hazard class empty:
# every `UInt8(...)` in the package is a checked conversion, so a width mistake
# is an exception, never a wrong answer. That finding is only as good as the
# coverage behind it — one exhaustive pass over the whole lattice converts it
# from a reading of the source into a measured property, and does it in one run
# rather than as a residue of whichever tests happen to touch wide formats.
#
# Two shapes here are load-bearing rather than stylistic:
#
#   * The per-format work is a FUNCTION taking the format as a type parameter,
#     not a loop body in test-file scope. At 7.6 M points a dynamically
#     dispatched inner loop is the difference between a second and an hour, and
#     specializing per format is also what the package's own doctrine says the
#     call sites do.
#   * Assertions are accumulated and reported as one `@test` per property per
#     format, not one per code point. 7.6 M `@test` invocations would spend
#     minutes of macro and bookkeeping overhead to report exactly the same
#     fact. Coverage is unchanged — every point is still visited, and the
#     counters printed at the end are what make that checkable rather than
#     assertable.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using SmallFloats: _NAMED, KMIN, KMAX, KSPLIT, codemask, codeunit_type, reptype,
                   rawvalue, Binary, Code8, Code16

"""Every `Unsigned` width a caller could plausibly hand a code point."""
const _SWEEP_WIDTHS = (UInt8, UInt16, UInt32, UInt64, UInt128)

"""
Visit every code point of `T` once, returning the four properties as `Bool`s
plus the number of points visited. Specialized on `T`, so the loop body is
concrete: the constructor, the mask and the code unit are all compile-time
constants inside it.
"""
function sweep_codepoints(::Type{T}) where {T<:Binary}
    U = codeunit_type(T)
    mask = codemask(T)
    top = (UInt64(1) << bitwidth(T)) - 1
    ok_round = true      # codepoint ∘ construct is the identity on codes
    ok_repinv = true     # representation invariant 3: the high bits are zero
    ok_raw = true        # checked route ≡ unchecked kernel route
    ok_width = true      # the MEANING of an `Unsigned` argument is width-free
    for i in UInt64(0):top
        c = U(i)
        v = T(c)
        ok_round &= codepoint(v) === c
        ok_repinv &= (codepoint(v) & ~mask) === zero(U)
        ok_raw &= v === rawvalue(T, c)
        # Invariant 2 read strictly: `Unsigned` is the argument-type *class*
        # meaning code point, so `T(0x02)` and `T(UInt128(2))` are the same code
        # point at every K. Widening an `Unsigned` is lossless, so the only way
        # a wrong-width argument can be wrong is by being out of range.
        ok_width &= T(UInt16(i)) === v && T(UInt32(i)) === v &&
                    T(UInt64(i)) === v && T(UInt128(i)) === v
    end
    (round = ok_round, repinv = ok_repinv, raw = ok_raw, width = ok_width,
     n = Int(top) + 1)
end

let npoints = 0, nformats = 0
    @testset "lattice sweep — every code point of every format" begin
        # The grid itself, before any value is built.
        @test length(_NAMED) == 504
        for K in KMIN:KMAX
            @test (K, count(nm -> bitwidth(getfield(SmallFloats, nm)) == K,
                            keys(_NAMED))) == (K, 4K - 2)
        end

        for nm in sort!(collect(keys(_NAMED)))
            T = getfield(SmallFloats, nm)
            K = bitwidth(T)
            U = codeunit_type(T)
            top = (UInt64(1) << K) - 1

            # The representation is a function of K and of nothing else.
            @test (nm, U) == (nm, K <= KSPLIT ? UInt8 : UInt16)
            @test (nm, T <: (K <= KSPLIT ? Code8 : Code16)) == (nm, true)
            @test (nm, reptype(Binary{K,precision(T),issigned(T),isextended(T)})) == (nm, T)
            @test (nm, codemask(T)) == (nm, U(top))

            r = sweep_codepoints(T)
            @test (nm, r.round) == (nm, true)
            @test (nm, r.repinv) == (nm, true)
            @test (nm, r.raw) == (nm, true)
            @test (nm, r.width) == (nm, true)

            # Out of range throws `ArgumentError` — never `InexactError`, never
            # a `MethodError` — at every width that can express `2^K`. A width
            # that cannot express it is not a case: the argument is unbuildable.
            for W in _SWEEP_WIDTHS
                if UInt128(top) < UInt128(typemax(W))
                    @test_throws ArgumentError T(W(top + 1))
                    @test_throws ArgumentError T(typemax(W))
                end
            end

            npoints += r.n
            nformats += 1
        end
    end
    println("lattice sweep: $nformats formats, $npoints code points, all exhaustive")
end
