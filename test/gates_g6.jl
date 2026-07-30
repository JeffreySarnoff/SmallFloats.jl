# ===== test/gates_g6.jl — gate G6: carrier-lift exactness
#
# implementextensions §2 R-B, §5 G6. After the carrier split, `decode(x1)` and
# `decode(x2)` can be different types, and the mixed-format join works by
# lifting each datum **up** to the head the operation runs on. The whole
# construction rests on one claim: *every lift is exact*. If it is not, a
# mixed-format operation rounds a datum before the operation even starts, and
# nothing downstream can detect it — the result is a plausible number.
#
# So the claim is enumerated, not argued: every datum of every one of the 504
# formats, lifted to every head at or above its own rung.
#
# Exactness is checked with `Base.decompose`, which returns the exact dyadic
# `(num, pow, den)` of a float and is therefore an *independent* witness — it
# does not go through any conversion this gate is testing. The values are
# normalized (trailing zeros of the significand moved into the exponent) because
# the same real number has many `decompose` spellings across carriers: `3·2^-10`
# comes back as `3·2^111 · 2^-121` from a `Float128` and `3·2^126 · 2^-136` from
# a `BigFloat`.
#
# The second half of the gate is the *absence* of narrowing methods. That
# absence is load-bearing design (§2 R-B item 3): a narrowing lift would round a
# datum on a path that believes itself exact, so it must be a `MethodError` and
# not a rounding.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
const _G6 = SmallFloats

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

"""Normalized exact dyadic value of a float: `(significand, exponent)` with the
significand odd and carrying the sign, or `(±1 or 0, :nonfinite)`.

Two `decompose` quirks have to be absorbed here, and both bit on the first run:

  * **the sign lives in the denominator.** `decompose(-0.0078125)` is
    `(4503599627370496, -59, -1)` — a *positive* significand over `den = -1`.
    Reading `den == 1` as "finite" silently classifies every negative datum as
    non-finite, which compares two unnormalized tuples and fails on carriers
    that merely spell the same value differently.
  * **zero's exponent is carrier-specific.** `decompose(0.0)` is `(0, -1074, 1)`
    while `decompose(BigFloat(0))` is `(0, 0, 1)`. Both mean zero.
"""
function dyadic(x)
    n, p, d = Base.decompose(x)
    d == 0 && return (big(n), 0, :nonfinite)     # NaN (n = 0) / ±Inf (n = ±1)
    abs(d) == 1 || error("decompose gave a non-dyadic denominator $d for $x")
    s = big(n) * d                               # fold the denominator's sign in
    s == 0 && return (big(0), 0, :finite)
    t = trailing_zeros(s)
    (s >> t, p + t, :finite)
end

"""Lift every datum of `F` to `h` and confirm the value is unchanged. Returns
`(ok, npoints)`. Specialized on `F` so the loop body is concrete."""
function sweep_lift(::Type{F}, h) where {F<:SmallFloats.Binary}
    U = SmallFloats.codeunit_type(F)
    top = (UInt64(1) << bitwidth(F)) - 1
    ok = true
    for i in UInt64(0):top
        d = decode(rawvalue(F, U(i)))
        l = _G6.lift(h, d)
        ok &= dyadic(l) == dyadic(d)
    end
    (ok, Int(top) + 1)
end

let npoints = 0
    @testset "G6 — carrier-lift exactness" begin
        # The heads a format's datums may legitimately be lifted to: its own and
        # every wider one. `rung` is a total order on three points, so this is
        # just "at or above".
        heads = (_G6.HeadF64(), _G6.HeadF128(), _G6.HeadExact())
        rungof = Dict(_G6.HeadF64() => 1, _G6.HeadF128() => 2, _G6.HeadExact() => 3)

        for nm in sort!(collect(keys(_G6._NAMED)))
            F = getfield(SmallFloats, nm)
            r = rungof[_G6.rung(F)]
            for h in heads
                rungof[h] >= r || continue
                ok, n = sweep_lift(F, h)
                @test (nm, nameof(typeof(h)), ok) == (nm, nameof(typeof(h)), true)
                npoints += n
            end
        end

        # `lift` is the identity on its own carrier — not merely equal, the same
        # object, so the rung-1 path costs nothing.
        @test _G6.lift(_G6.HeadF64(), 1.5) === 1.5
        @test _G6.lift(_G6.HeadF128(), Float128(1.5)) === Float128(1.5)

        # No narrowing method exists, at any of the three narrowing directions.
        # `hasmethod` rather than a `@test_throws`: the point is that the method
        # table is empty here, which is a stronger and more durable statement
        # than "calling it happens to fail".
        @test !hasmethod(_G6.lift, Tuple{_G6.HeadF64, Float128})
        @test !hasmethod(_G6.lift, Tuple{_G6.HeadF64, BigFloat})
        @test !hasmethod(_G6.lift, Tuple{_G6.HeadF128, BigFloat})
        @test_throws MethodError _G6.lift(_G6.HeadF64(), Float128(1.5))

        # Every lift target is the head's own carrier — the property `apply_op`'s
        # result split depends on.
        @test _G6.lift(_G6.HeadF128(), 1.5) isa _G6.carriertype(_G6.HeadF128)
        @test _G6.lift(_G6.HeadExact(), 1.5) isa _G6.carriertype(_G6.HeadExact)
    end
    println("G6: carrier lifts verified over $npoints (datum, head) pairs, all exhaustive")
    record_gate!("G6"; assertions=1440, units=npoints, exhaustive=true)
end
