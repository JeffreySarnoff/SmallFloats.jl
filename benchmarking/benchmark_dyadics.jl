# Run with:
#   julia --project=benchmarking -O3 benchmarking/benchmark_dyadics.jl
#
# Uses Chairmarks, matching benchmarking.jl's doctrine (see its header): every
# benchmarked call sits behind a type-specialized function barrier, operands come
# from Chairmarks' *untimed* setup so values are runtime-varying without paying
# generation cost in the timing, and minima are reported first.

using Chairmarks
using Random
import SmallFloats
using SmallFloats.DyadicNumbers          # `Dyadic` and the DY_* tags
const DN = SmallFloats.DyadicNumbers     # the kernels, which are not exported

fmt_time(s::Float64) =
    s < 1e-6 ? string(round(s * 1e9; digits=1), " ns") :
    s < 1e-3 ? string(round(s * 1e6; digits=2), " μs") :
               string(round(s * 1e3; digits=2), " ms")

function report(name, b::Chairmarks.Benchmark)
    m = minimum(b)
    println("  ", rpad(name, 16), lpad(fmt_time(m.time), 10),
            "   allocs=", m.allocs, "  bytes=", m.bytes)
end

# Operands come from untimed setup and are passed as ARGUMENTS everywhere below.
# A benchmark closure over a non-`const` global measures Julia's dispatch
# machinery rather than the code under test, and it distorts ratios rather than
# just absolutes — see the benchmark doctrine in CLAUDE.md.
function sample_vectors(n::Int)
    rng = MersenneTwister(0xD1AD1C)
    xs = Vector{Dyadic}(undef, n)
    ys = similar(xs)
    @inbounds for i in eachindex(xs)
        xs[i] = Dyadic(rand(rng, Int32(-65_535):Int32(65_535)), rand(rng, -40:40))
        ys[i] = Dyadic(rand(rng, Int32(-65_535):Int32(65_535)), rand(rng, -40:40))
    end
    xs, ys
end

# Every loop REDUCES into an accumulator and ends in `donotdelete`.
#
# The earlier spelling was `z = DN.mul_dy(xs[i], ys[i])`, which leaves every
# iteration but the last dead. Whether the loop then survives depends on whether
# the compiler can prove the body pure — so it compared dead-code elimination
# between implementations, not multiplication. Measured: an unchecked `mul_dy`
# under that loop reports 8 ns for 4096 elements, i.e. 0.002 ns/element.
function add_loop(xs, ys)
    acc = Int64(0)
    @inbounds for i in eachindex(xs, ys)
        h, s = DN.add_sticky_dy(xs[i], ys[i])
        acc += (h.S % Int64) + s        # consume the HEAD too, not only the sticky
    end
    Base.donotdelete(acc)
    acc
end

function mul_loop(xs, ys)
    acc = Int64(0)
    @inbounds for i in eachindex(xs, ys)
        acc += DN.mul_dy(xs[i], ys[i]).S % Int64
    end
    Base.donotdelete(acc)
    acc
end

function mul_checked_loop(xs, ys)
    acc = Int64(0)
    @inbounds for i in eachindex(xs, ys)
        acc += DN.mul_dy_checked(xs[i], ys[i]).S % Int64
    end
    Base.donotdelete(acc)
    acc
end

function cmp_loop(xs, ys)
    acc = 0
    @inbounds for i in eachindex(xs, ys)
        acc += DN.cmp_dy(xs[i], ys[i])
    end
    Base.donotdelete(acc)
    acc
end

function main()
    xs, ys = sample_vectors(4096)
    pool = collect(zip(xs, ys))     # per-sample operand draw for the scalar kernels

    println("Dyadic layout")
    println((sizeof = sizeof(Dyadic),
             offsets = ntuple(i -> fieldoffset(Dyadic, i), fieldcount(Dyadic)),
             isbits = isbitstype(Dyadic)))

    println("\nScalar kernels")
    report("add_sticky_dy",  @be rand(pool) DN.add_sticky_dy(_[1], _[2]))
    report("mul_dy",         @be rand(pool) DN.mul_dy(_[1], _[2]))
    report("mul_dy_checked", @be rand(pool) DN.mul_dy_checked(_[1], _[2]))
    report("cmp_dy",         @be rand(pool) DN.cmp_dy(_[1], _[2]))

    println("\nVector loops (4096 elements)")
    report("add",         @be add_loop(xs, ys) evals=1)
    report("mul",         @be mul_loop(xs, ys) evals=1)
    report("mul checked", @be mul_checked_loop(xs, ys) evals=1)
    report("cmp",         @be cmp_loop(xs, ys) evals=1)
end

main()
