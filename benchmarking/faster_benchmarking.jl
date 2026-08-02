#!/usr/bin/env julia

"""
    julia --project=benchmarking benchmarking/faster_benchmarking.jl RUNTIME [OUTPUT] [SEED]

Run a representative, deadline-aware subset of `benchmarking.jl`. `RUNTIME` is a
positive duration such as `30`, `30s`, `2m`, or `0.5h`; a bare number means
seconds. The default output is `benchmarking/faster_benchmarking_report.md`.

The budget starts before dependencies are loaded, so it includes package loading,
JIT compilation, operand preparation, measurements, and report generation. It
cannot include Julia process startup. A compilation or table build already in
progress cannot be interrupted, so the limit is necessarily approximate.
"""

const FAST_START_NS = time_ns()
include(joinpath(@__DIR__, "benchmarking.jl"))

const FAST_DEFAULT_OUTPUT = joinpath(@__DIR__, "faster_benchmarking_report.md")
const FAST_DEFAULT_SEED = 2026
const FAST_POOL_SIZE = 512
const FAST_ARRAY_SIZE = 16_384

struct FastCase
    section::String
    name::String
    minimum_budget::Float64
    run::Function
end

struct FastMeasurement
    benchmark::Any
    context::String
end
FastMeasurement(benchmark; context="") = FastMeasurement(benchmark, context)

struct FastResult
    section::String
    name::String
    minimum::Float64
    median::Float64
    allocations::Float64
    samples::Int
    context::String
end

struct FastFailure
    section::String
    name::String
    message::String
end

elapsed_seconds() = (time_ns() - FAST_START_NS) / 1.0e9

"""Resolve a bare output filename beside this script; preserve explicit paths."""
resolve_output_path(path::AbstractString) =
    basename(path) == path ? joinpath(@__DIR__, path) : path

function parse_duration(text::AbstractString)
    m = match(r"^\s*(\d+(?:\.\d*)?|\.\d+)\s*(ms|s|m|h)?\s*$"i, text)
    m === nothing && throw(ArgumentError("invalid runtime '$text'"))
    value = parse(Float64, m.captures[1])
    unit = something(m.captures[2], "s")
    factor = lowercase(unit) == "ms" ? 1e-3 : lowercase(unit) == "s" ? 1.0 :
             lowercase(unit) == "m" ? 60.0 : 3600.0
    duration = value * factor
    isfinite(duration) && duration > 0 ||
        throw(ArgumentError("runtime must be positive and finite"))
    duration
end

function usage(io::IO=stdout)
    println(io, "Usage: julia --project=benchmarking benchmarking/faster_benchmarking.jl ",
            "RUNTIME [OUTPUT] [SEED]")
    println(io, "  RUNTIME  positive duration: 30, 30s, 2m, or 0.5h")
    println(io, "  OUTPUT   Markdown report; bare filenames are written under benchmarking/")
    println(io, "           (default: benchmarking/faster_benchmarking_report.md)")
    println(io, "  SEED     random seed (default: $FAST_DEFAULT_SEED)")
end

# Type-specialized timing barriers. The dynamic case catalog stays outside the
# measured expression; the operation itself is fully specialized inside it.
_fast_op(f::F, ::Type{T}, pool, ::Val{1}, seconds) where {F,T} =
    @be rand(pool) f(T, RNE_SN, _) seconds=seconds
_fast_op(f::F, ::Type{T}, pool, ::Val{2}, seconds) where {F,T} =
    @be (rand(pool), rand(pool)) (t -> f(T, RNE_SN, t[1], t[2]))(_) seconds=seconds
_fast_op(f::F, ::Type{T}, pool, ::Val{3}, seconds) where {F,T} =
    @be (rand(pool), rand(pool), rand(pool)) (t -> f(T, RNE_SN, t[1], t[2], t[3]))(_) seconds=seconds

_fast_op_nt(f::F, ::Type{T}, pool, ::Val{1}, seconds) where {F,T} =
    @be rand(pool) (t -> f(T, RNE_SN, t[1]))(_) seconds=seconds
_fast_op_nt(f::F, ::Type{T}, pool, ::Val{2}, seconds) where {F,T} =
    @be rand(pool) (t -> f(T, RNE_SN, t[1], t[2]))(_) seconds=seconds
_fast_op_nt(f::F, ::Type{T}, pool, ::Val{3}, seconds) where {F,T} =
    @be rand(pool) (t -> f(T, RNE_SN, t[1], t[2], t[3]))(_) seconds=seconds

function measure_scalar(op::Symbol, ::Type{T}, arity::Int, class::Symbol, seconds) where {T<:Binary}
    f = getfield(SmallFloats, op)
    if class === :indomain
        pool = indomain_pool(op, T, arity, FAST_POOL_SIZE)
        b = _fast_op_nt(f, T, pool, Val(arity), seconds)
        FastMeasurement(b; context="safe arguments")
    else
        pool = codes_pool(T, FAST_POOL_SIZE; class)
        b = _fast_op(f, T, pool, Val(arity), seconds)
        FastMeasurement(b; context=class === :all ? "all code points" : string(class))
    end
end

function measure_decode(::Type{T}, seconds) where {T<:Binary}
    pool = codes_pool(T, FAST_POOL_SIZE)
    FastMeasurement(@be rand(pool) decode(_) seconds=seconds)
end

function measure_order_key(::Type{T}, seconds) where {T<:Binary}
    pool = codes_pool(T, FAST_POOL_SIZE)
    FastMeasurement(@be rand(pool) order_key(_) seconds=seconds)
end

function measure_project(::Type{T}, ρ, label, seconds) where {T<:Binary}
    pool = [decode(x) for x in codes_pool(T, FAST_POOL_SIZE)]
    FastMeasurement(@be rand(pool) project(T, ρ, _) seconds=seconds; context=label)
end

function per_element_context(b, n)
    ns = median(b).time / n * 1e9
    rate = n / median(b).time / 1e9
    "n=$n; $(round(ns; digits=2)) ns/element; $(round(rate; digits=2)) Gelement/s"
end

function measure_unary_kernel(::Type{T}, seconds; n=FAST_ARRAY_SIZE) where {T<:Binary}
    a = codes_pool(T, n)
    get_table(:Exp, T, T, RNE_SN)
    b = @be similar(a) vmap!(_, Val(:Exp), T, RNE_SN, a) evals=1 seconds=seconds
    FastMeasurement(b; context=per_element_context(b, n))
end

function measure_binary_kernel(::Type{T}, seconds; n=FAST_ARRAY_SIZE) where {T<:Binary}
    a = codes_pool(T, n); bvalues = codes_pool(T, n)
    get_table(:Add, T, T, T, RNE_SN)
    b = @be similar(a) vmap!(_, Val(:Add), T, RNE_SN, a, bvalues) evals=1 seconds=seconds
    FastMeasurement(b; context=per_element_context(b, n))
end

function measure_ternary_kernel(::Type{T}, seconds; n=FAST_ARRAY_SIZE) where {T<:Binary}
    a = codes_pool(T, n); bvalues = codes_pool(T, n); c = codes_pool(T, n)
    b = @be similar(a) vmap!(_, Val(:FMA), T, RNE_SN, a, bvalues, c) evals=1 seconds=seconds
    FastMeasurement(b; context=per_element_context(b, n))
end

function measure_sort(::Type{T}, algorithm, label, seconds; n=FAST_ARRAY_SIZE) where {T<:Binary}
    a = codes_pool(T, n)
    b = algorithm === nothing ?
        (@be copy(a) sort!(_) evals=1 seconds=seconds) :
        (@be copy(a) sort!(_; alg=algorithm) evals=1 seconds=seconds)
    FastMeasurement(b; context="n=$n; $label")
end

function measure_table(kind::Symbol, seconds)
    T = Binary8p4se
    f = kind === :unary ? (() -> get_table(:Exp, T, T, RNE_SN)) :
                          (() -> get_table(:Add, T, T, T, RNE_SN))
    f() # compile before cache eviction; rebuilding remains timed
    b = @be empty_tables!() (_ -> f())(_) evals=1 seconds=seconds
    empty_tables!()
    entries = kind === :unary ? 256 : 65_536
    FastMeasurement(b; context="cold build; $entries entries")
end

function measure_block(kind::Symbol, seconds; lanes=32)
    FE = Binary8p4se; FS = Binary8p1uf
    mk() = Block(one(FS), ntuple(_ -> rawvalue(FE, UInt8(rand(0:255))), lanes))
    if kind === :dot
        b = @be (mk(), mk()) (t -> BlockDotProduct(Binary8p4se, RNE_SN, t[1], t[2]))(_) seconds=seconds
    else
        b = @be mk() BlockReduceAdd(Binary8p4se, RNE_SN, _) seconds=seconds
    end
    FastMeasurement(b; context="B=$lanes; $(round(median(b).time / lanes * 1e9; digits=2)) ns/lane")
end

function measure_conversion(kind::Symbol, seconds; n=FAST_ARRAY_SIZE)
    T = Binary8p4se
    if kind === :numeric
        pool = [decode(x) for x in codes_pool(T, FAST_POOL_SIZE)]
        return FastMeasurement(@be rand(pool) T(_) seconds=seconds; context="Float64 → Binary8p4se")
    elseif kind === :format
        pool = codes_pool(T, FAST_POOL_SIZE)
        return FastMeasurement(@be rand(pool) Convert(Binary8p3se, RNE_SN, _) seconds=seconds;
                               context="Binary8p4se → Binary8p3se")
    end
    a = codes_pool(T, n)
    if kind === :pack
        b = @be PackedVector(a) evals=1 seconds=seconds
    else
        packed = PackedVector(a)
        b = @be collect(packed) evals=1 seconds=seconds
    end
    FastMeasurement(b; context=per_element_context(b, n))
end

function benchmark_catalog()
    T = Binary8p4se
    stochastic = ProjSpec(StochasticA{8}(), SatNone())
    cases = FastCase[]
    add(section, name, budget, f) = push!(cases, FastCase(section, name, budget, f))

    # The first pass deliberately crosses every major section. Later passes add
    # operations, operand classes, formats, modes, and alternate implementations.
    add("Core representation", "decode", 0, s -> measure_decode(T, s))
    add("Scalar operations", "Add", 0, s -> measure_scalar(:Add, T, 2, :indomain, s))
    add("Projection modes", "NearestTiesToEven · SatNone", 0,
        s -> measure_project(T, RNE_SN, "deterministic", s))
    add("Array kernels", "vmap Exp (table gather)", 0, s -> measure_unary_kernel(T, s))
    add("Sorting", "counting sort", 0, s -> measure_sort(T, nothing, "default algorithm", s))
    add("Block operations", "BlockDotProduct", 0, s -> measure_block(:dot, s))
    add("Conversions", "numeric constructor", 0, s -> measure_conversion(:numeric, s))
    add("Function tables", "Exp table", 0, s -> measure_table(:unary, s))

    add("Core representation", "order_key", 12, s -> measure_order_key(T, s))
    add("Scalar operations", "Abs", 12, s -> measure_scalar(:Abs, T, 1, :indomain, s))
    add("Scalar operations", "Sqrt", 12, s -> measure_scalar(:Sqrt, T, 1, :indomain, s))
    add("Scalar operations", "Exp", 12, s -> measure_scalar(:Exp, T, 1, :indomain, s))
    add("Scalar operations", "Multiply", 12, s -> measure_scalar(:Multiply, T, 2, :indomain, s))
    add("Scalar operations", "Divide", 12, s -> measure_scalar(:Divide, T, 2, :indomain, s))
    add("Scalar operations", "FMA", 12, s -> measure_scalar(:FMA, T, 3, :indomain, s))
    add("Projection modes", "StochasticA[8] · SatNone", 12,
        s -> measure_project(T, stochastic, "stochastic; random bits drawn", s))
    add("Array kernels", "vmap Add (table gather)", 12, s -> measure_binary_kernel(T, s))
    add("Sorting", "comparison sort", 12,
        s -> measure_sort(T, Base.Sort.DEFAULT_UNSTABLE, "stock comparison algorithm", s))
    add("Conversions", "PackedVector pack", 12, s -> measure_conversion(:pack, s))

    for op in (:Log, :Sin, :Tanh)
        add("Scalar operations", string(op), 30, s -> measure_scalar(op, T, 1, :indomain, s))
    end
    for op in (:Minimum, :ArcTan2)
        add("Scalar operations", string(op), 30, s -> measure_scalar(op, T, 2, :indomain, s))
    end
    add("Operand sensitivity", "Add (all code points)", 30,
        s -> measure_scalar(:Add, T, 2, :all, s))
    add("Operand sensitivity", "Sqrt (all code points)", 30,
        s -> measure_scalar(:Sqrt, T, 1, :all, s))
    add("Format sensitivity", "Add · Binary8p1uf", 30,
        s -> measure_scalar(:Add, Binary8p1uf, 2, :all, s))
    add("Projection modes", "NearestTiesToEven · SatFinite", 30,
        s -> measure_project(T, RNE_SF, "deterministic; finite saturation", s))
    add("Array kernels", "vmap FMA (compute)", 30, s -> measure_ternary_kernel(T, s))
    add("Block operations", "BlockReduceAdd", 30, s -> measure_block(:reduce, s))
    add("Conversions", "format conversion", 30, s -> measure_conversion(:format, s))
    add("Conversions", "PackedVector unpack", 30, s -> measure_conversion(:unpack, s))
    add("Function tables", "Add table", 30, s -> measure_table(:binary, s))

    for op in (:Recip, :Log2, :ArcSin, :MaximumMagnitude, :CopySign)
        arity = op in (:MaximumMagnitude, :CopySign) ? 2 : 1
        add("Extended scalar coverage", string(op), 60,
            s -> measure_scalar(op, T, arity, :indomain, s))
    end
    cases
end

function sampling_slice(target, eligible_count, elapsed)
    usable = max(0.0, target - elapsed - min(0.5, 0.04target))
    clamp(0.45 * usable / max(eligible_count, 1), 0.002, target >= 60 ? 0.10 : 0.05)
end

markdown_escape(text) = replace(string(text), "|" => "\\|", '\n' => ' ')

function write_report(path, target, actual, seed, slice, passes, measurements,
                      eligible_count, catalog_count, results, failures, stop_reason)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, "# SmallFloats fast benchmark report\n")
        println(io, "This deadline-aware run samples representative work from the full suite. ",
                "It favors breadth first and adds depth as the requested budget grows. Results ",
                "are useful for rapid feedback; use `benchmarking.jl` for the exhaustive report.\n")
        println(io, "- Requested runtime: `$(round(target; digits=3)) s`")
        println(io, "- Observed runtime: `$(round(actual; digits=3)) s` (from script entry through report preparation)")
        println(io, "- Completed: `$(length(results)) / $eligible_count` eligible cases (`$catalog_count` in catalog)")
        println(io, "- Measurement passes: `$passes` (`$measurements` total case measurements)")
        println(io, "- Initial per-case Chairmarks sampling slice: `$(round(slice * 1e3; digits=2)) ms`")
        println(io, "- Seed: `$seed`; Julia: `$(VERSION)`; threads: `$(Threads.nthreads())`")
        println(io, "- Stop condition: $(markdown_escape(stop_reason))\n")
        println(io, "The runtime is approximate: Julia process startup precedes the timer, while package ",
                "loading, compilation, data preparation, and measurement are included. An in-progress ",
                "compilation or table build cannot be interrupted and can cause an overshoot.\n")

        sections = unique(r.section for r in results)
        for (section_index, section) in enumerate(sections)
            section_index > 1 && println(io)
            println(io, "## $section\n")
            println(io, "| benchmark | min | median | allocs | samples | context |")
            println(io, "|:---|---:|---:|---:|---:|:---|")
            for r in results
                r.section == section || continue
                println(io, "| `$(markdown_escape(r.name))` | $(fmt_time(r.minimum)) | ",
                        "$(fmt_time(r.median)) | $(fmt_alloc(r.allocations)) | $(r.samples) | ",
                        "$(markdown_escape(r.context)) |")
            end
        end
        if !isempty(failures)
            isempty(sections) || println(io)
            println(io, "## Cases that failed\n")
            println(io, "| benchmark | error |")
            println(io, "|:---|:---|")
            for f in failures
                println(io, "| `$(markdown_escape(f.section)): $(markdown_escape(f.name))` | ",
                        "$(markdown_escape(f.message)) |")
            end
        end
    end
end

function run_fast_benchmarks(target::Float64, output::AbstractString; seed=FAST_DEFAULT_SEED)
    Random.seed!(seed)
    preflight(Binary8p4se)
    catalog = benchmark_catalog()
    eligible = filter(c -> c.minimum_budget <= target, catalog)
    slice = sampling_slice(target, length(eligible), elapsed_seconds())
    reserve = min(0.5, max(0.05, 0.04target))
    deadline = target
    results = FastResult[]
    failures = FastFailure[]
    durations = Float64[]
    stop_reason = "all eligible cases completed"
    measurements = 0
    passes = 1

    for case in eligible
        remaining = deadline - elapsed_seconds()
        recent = isempty(durations) ? 0.05 : median(durations[max(1, end - 3):end])
        guard = max(0.03, 1.20recent)
        if remaining <= reserve + guard
            stop_reason = "deadline guard stopped before launching another case"
            break
        end
        case_slice = min(slice, max(0.001, 0.45 * (remaining - reserve)))
        started = time_ns()
        try
            measurement = case.run(case_slice)
            measurements += 1
            b = measurement.benchmark
            push!(results, FastResult(case.section, case.name, minimum(b).time,
                                      median(b).time, median(b).allocs,
                                      length(b.samples), measurement.context))
        catch err
            push!(failures, FastFailure(case.section, case.name,
                                        sprint(showerror, err)))
        end
        push!(durations, (time_ns() - started) / 1e9)
    end

    # Breadth comes first. If it finishes early, spend the remaining budget on
    # longer refinement passes and replace each coarse result with the newest
    # measurement. This makes a larger requested runtime buy greater precision
    # rather than merely returning early after the same short suite.
    completed_all = length(results) == length(eligible) && isempty(failures)
    while completed_all
        remaining = deadline - elapsed_seconds()
        remaining <= reserve + 0.05 && break
        passes += 1
        refinement_slice = min(1.0, 0.82 * (remaining - reserve) / length(eligible))
        refinement_slice < 0.002 && break
        completed_pass = true
        for (i, case) in enumerate(eligible)
            remaining = deadline - elapsed_seconds()
            if remaining <= reserve + max(0.03, 1.15refinement_slice)
                stop_reason = "deadline guard stopped during refinement pass $passes"
                completed_pass = false
                break
            end
            case_slice = min(refinement_slice, max(0.001, 0.45 * (remaining - reserve)))
            try
                measurement = case.run(case_slice)
                measurements += 1
                b = measurement.benchmark
                results[i] = FastResult(case.section, case.name, minimum(b).time,
                                        median(b).time, median(b).allocs,
                                        length(b.samples), measurement.context)
            catch err
                push!(failures, FastFailure(case.section, case.name,
                                            "refinement: " * sprint(showerror, err)))
                completed_pass = false
                break
            end
        end
        completed_pass || break
    end

    actual = elapsed_seconds()
    isempty(results) && isempty(failures) &&
        (stop_reason = "budget was consumed by loading, compilation, and preflight")
    write_report(output, target, actual, seed, slice, passes, measurements,
                 length(eligible), length(catalog), results, failures, stop_reason)
    final_actual = elapsed_seconds()
    println("Wrote $(abspath(output))")
    println("Completed $(length(results))/$(length(eligible)) eligible cases in ",
            "$(round(final_actual; digits=3)) s (requested $(round(target; digits=3)) s).")
    !isempty(failures) && println(stderr, "$(length(failures)) case(s) failed; see the report.")
    isempty(failures)
end

function main(args=ARGS)
    if any(x -> x in ("-h", "--help"), args)
        usage()
        return 0
    end
    1 <= length(args) <= 3 || throw(ArgumentError("expected RUNTIME [OUTPUT] [SEED]"))
    target = parse_duration(args[1])
    output = length(args) >= 2 ? resolve_output_path(args[2]) : FAST_DEFAULT_OUTPUT
    seed = length(args) >= 3 ? parse(Int, args[3]) : FAST_DEFAULT_SEED
    run_fast_benchmarks(target, output; seed) ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(main())
    catch err
        println(stderr, "error: ", sprint(showerror, err))
        usage(stderr)
        exit(2)
    end
end
