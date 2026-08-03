       html {font-size: 17px;} .franklin-content {position: relative; padding-left: 8%; padding-right: 5%; line-height: 1.35em;} @media (min-width: 940px) { .franklin-content {width: 100%; margin-left: auto; margin-right: auto;} } @media (max-width: 768px) { .franklin-content {padding-left: 6%; padding-right: 6%;} }  Optimizing your code

# [MoJuWo](/)

Modern Julia Workflows

![MoJuWo Logo](/assets/logo.svg)

[Home](/)

*   [Goals](/#goals)
*   [Contents](/#contents)
*   [Before you start](/#before_you_start)

[Writing](/writing/)

*   [Getting help](/writing/#getting_help)
*   [Installation](/writing/#installation)
*   [REPL](/writing/#repl)
*   [Editor](/writing/#editor)
*   [Running code](/writing/#running_code)
*   [Notebooks](/writing/#notebooks)
*   [Environments](/writing/#environments)
*   [Local packages](/writing/#local_packages)
*   [Development workflow](/writing/#development_workflow)
*   [Configuration](/writing/#configuration)
*   [Interactivity](/writing/#interactivity)
*   [Logging](/writing/#logging)
*   [Debugging](/writing/#debugging)

[Sharing](/sharing/)

*   [Setup](/sharing/#setup)
*   [GitHub Actions](/sharing/#github_actions)
*   [Testing](/sharing/#testing)
*   [Style](/sharing/#style)
*   [Code quality](/sharing/#code_quality)
*   [Documentation](/sharing/#documentation)
*   [Literate programming](/sharing/#literate_programming)
*   [Versions and registration](/sharing/#versions_and_registration)
*   [Reproducibility](/sharing/#reproducibility)
*   [Interoperability](/sharing/#interoperability)
*   [Collaboration](/sharing/#collaboration)

[Optimizing](/optimizing/)

*   [Principles](/optimizing/#principles)
*   [Measurements](/optimizing/#measurements)
*   [Profiling](/optimizing/#profiling)
*   [Type stability](/optimizing/#type_stability)
*   [Memory management](/optimizing/#memory_management)
*   [Compilation](/optimizing/#compilation)
*   [Parallelism](/optimizing/#parallelism)
*   [Efficient types](/optimizing/#efficient_types)

[Going further](/further/)

*   [Official](/further/#official)
*   [Tutorials](/further/#tutorials)
*   [Blogs](/further/#blogs)
*   [Videos](/further/#videos)
*   [Lore](/further/#lore)

[© G. Dalle, J. Smit, A. Hill.](https://github.com/modernjuliaworkflows/modernjuliaworkflows.github.io/blob/main/LICENSE)

[](https://github.com/modernjuliaworkflows/modernjuliaworkflows.github.io)

# [Optimizing your code](#optimizing_your_code)

1.  [Principles](#principles)
2.  [Measurements](#measurements)
3.  [Profiling](#profiling)
4.  [Type stability](#type_stability)
5.  [Memory management](#memory_management)
6.  [Compilation](#compilation)
7.  [Parallelism](#parallelism)
8.  [Efficient types](#efficient_types)

## [Principles](#principles)

**TLDR**: The two fundamental principles for writing fast Julia code:

1.  Ensure that **the compiler can infer the type** of every variable.
2.  Avoid **unnecessary (heap) allocations**.

The compiler's job is to optimize and translate Julia code it into runnable [machine code](https://en.wikipedia.org/wiki/Machine_code). If a variable's type cannot be deduced before the code is run, then the compiler won't generate efficient code to handle that variable. We call this phenomenon "type instability". Enabling type inference means making sure that every variable's type in every function can be deduced from the types of the function inputs alone.

A "heap allocation" (or simply "allocation") occurs when we create a new variable without knowing how much space it will require (like a `Vector` with flexible length). Julia has a mark-and-sweep [garbage collector](https://docs.julialang.org/en/v1/devdocs/gc/) (GC), which runs periodically during code execution to free up space on the heap. Execution of code is stopped while the garbage collector runs, so minimising its usage is important.

The vast majority of performance tips come down to these two fundamental ideas. Typically, the most common beginner pitfall is the use of [untyped global variables](https://docs.julialang.org/en/v1/manual/performance-tips/#Avoid-untyped-global-variables) without passing them as arguments. Why is it bad? Because the type of a global variable can change outside of the body of a function, so it causes type instabilities wherever it is used. Those type instabilities in turn lead to more heap allocations.

With this in mind, after you're done with the current page, you should read the [official performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/): they contain some useful advice which is not repeated here for space reasons.

## [Measurements](#measurements)

**TLDR**: Use BenchmarkTools.jl or Chairmarks.jl with a setup phase to get the most accurate idea of your code's performance.

The simplest way to measure how fast a piece of code runs is to use the `@time` macro, which returns the result of the code and prints the measured runtime and allocations. Because code needs to be compiled before it can be run, you should first run a function without timing it so it can be compiled, and then time it:

```
julia> sum_abs(vec) = sum(abs(x) for x in vec);

julia> v = rand(100);

julia> @time sum_abs(v); # Inaccurate, note the >99% compilation time
0.028848 seconds (70.55 k allocations: 3.404 MiB, 99.91% compilation time)

julia> @time sum_abs(v); # Accurate
0.000006 seconds (1 allocation: 16 bytes)
```

Using `@time` is quick but it has flaws, because your function is only measured once. That measurement might have been influenced by other things going on in your computer at the same time. In general, running the same block of code multiple times is a safer measurement method, because it diminishes the probability of only observing an outlier. The BenchmarkTools.jl and Chairmarks.jl packages both provide convenient syntax to do just that.

**Advanced**: No matter the benchmarking tool used, certain computations may be [optimized away by the compiler](\(https://juliaci.github.io/BenchmarkTools.jl/stable/manual/#Understanding-compiler-optimizations\)) before the benchmark takes place. If you observe suspiciously fast performance, especially below the nanosecond scale, this is very likely to have happened.

### [BenchmarkTools](#benchmarktools)

[BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl) is the most popular package for repeated measurements on function executions. Similarly to `@time`, BenchmarkTools offers `@btime` which can be used in exactly the same way but will run the code multiple times and provide an average. Additionally, by using `$` to [interpolate external values](https://juliaci.github.io/BenchmarkTools.jl/stable/manual/#Interpolating-values-into-benchmark-expressions), you remove the overhead caused by global variables.

```
julia> using BenchmarkTools
ERROR: LoadError: ArgumentError: Package Tables [bd369af6-aec1-5ad0-b16a-f7cc5008161c] is required but does not seem to be installed:
 - Run `Pkg.instantiate()` to install all recorded dependencies.

Stacktrace:
  [1] _require(pkg::Base.PkgId, env::String)
    @ Base ./loading.jl:2515
  [2] __require_prelocked(uuidkey::Base.PkgId, env::String)
    @ Base ./loading.jl:2388
  [3] #invoke_in_world#3
    @ ./essentials.jl:1089 [inlined]
  [4] invoke_in_world
    @ ./essentials.jl:1086 [inlined]
  [5] _require_prelocked(uuidkey::Base.PkgId, env::String)
    @ Base ./loading.jl:2375
  [6] macro expansion
    @ ./loading.jl:2314 [inlined]
  [7] macro expansion
    @ ./lock.jl:273 [inlined]
  [8] __require(into::Module, mod::Symbol)
    @ Base ./loading.jl:2271
  [9] #invoke_in_world#3
    @ ./essentials.jl:1089 [inlined]
 [10] invoke_in_world
    @ ./essentials.jl:1086 [inlined]
 [11] require(into::Module, mod::Symbol)
    @ Base ./loading.jl:2260
 [12] include
    @ ./Base.jl:562 [inlined]
 [13] include_package_for_output(pkg::Base.PkgId, input::String, depot_path::Vector{String}, dl_load_path::Vector{String}, load_path::Vector{String}, concrete_deps::Vector{Pair{Base.PkgId, UInt128}}, source::String)
    @ Base ./loading.jl:2922
 [14] top-level scope
    @ stdin:6
in expression starting at /home/runner/.julia/packages/StructUtils/BDA5D/ext/StructUtilsTablesExt.jl:1
in expression starting at stdin:6
┌ Error: Error during loading of extension StructUtilsTablesExt of StructUtils, use `Base.retry_load_extensions()` to retry.
│   exception =
│    1-element ExceptionStack:
│    Failed to precompile StructUtilsTablesExt [06a1ca1f-7bc7-53d2-8cfe-f45bf2a4bdd3] to "/home/runner/.julia/compiled/v1.11/StructUtilsTablesExt/jl_xeIIjM".
│    Stacktrace:
│      [1] error(s::String)
│        @ Base ./error.jl:35
│      [2] compilecache(pkg::Base.PkgId, path::String, internal_stderr::IO, internal_stdout::IO, keep_loaded_modules::Bool; flags::Cmd, cacheflags::Base.CacheFlags, reasons::Dict{String, Int64}, loadable_exts::Vector{Base.PkgId})
│        @ Base ./loading.jl:3215
│      [3] (::Base.var"#1110#1111"{Base.PkgId})()
│        @ Base ./loading.jl:2579
│      [4] mkpidlock(f::Base.var"#1110#1111"{Base.PkgId}, at::String, pid::Int32; kwopts::@Kwargs{stale_age::Int64, wait::Bool})
│        @ FileWatching.Pidfile /opt/hostedtoolcache/julia/1.11.8/x64/share/julia/stdlib/v1.11/FileWatching/src/pidfile.jl:95
│      [5] #mkpidlock#6
│        @ /opt/hostedtoolcache/julia/1.11.8/x64/share/julia/stdlib/v1.11/FileWatching/src/pidfile.jl:90 [inlined]
│      [6] trymkpidlock(::Function, ::Vararg{Any}; kwargs::@Kwargs{stale_age::Int64})
│        @ FileWatching.Pidfile /opt/hostedtoolcache/julia/1.11.8/x64/share/julia/stdlib/v1.11/FileWatching/src/pidfile.jl:116
│      [7] #invokelatest#2
│        @ ./essentials.jl:1057 [inlined]
│      [8] invokelatest
│        @ ./essentials.jl:1052 [inlined]
│      [9] maybe_cachefile_lock(f::Base.var"#1110#1111"{Base.PkgId}, pkg::Base.PkgId, srcpath::String; stale_age::Int64)
│        @ Base ./loading.jl:3739
│     [10] maybe_cachefile_lock
│        @ ./loading.jl:3736 [inlined]
│     [11] _require(pkg::Base.PkgId, env::Nothing)
│        @ Base ./loading.jl:2565
│     [12] __require_prelocked(uuidkey::Base.PkgId, env::Nothing)
│        @ Base ./loading.jl:2388
│     [13] #invoke_in_world#3
│        @ ./essentials.jl:1089 [inlined]
│     [14] invoke_in_world
│        @ ./essentials.jl:1086 [inlined]
│     [15] _require_prelocked
│        @ ./loading.jl:2375 [inlined]
│     [16] _require_prelocked
│        @ ./loading.jl:2374 [inlined]
│     [17] run_extension_callbacks(extid::Base.ExtensionId)
│        @ Base ./loading.jl:1544
│     [18] run_extension_callbacks(pkgid::Base.PkgId)
│        @ Base ./loading.jl:1576
│     [19] run_package_callbacks(modkey::Base.PkgId)
│        @ Base ./loading.jl:1396
│     [20] _require_search_from_serialized(pkg::Base.PkgId, sourcepath::String, build_id::UInt128, stalecheck::Bool; reasons::Dict{String, Int64}, DEPOT_PATH::Vector{String})
│        @ Base ./loading.jl:2065
│     [21] _require(pkg::Base.PkgId, env::String)
│        @ Base ./loading.jl:2527
│     [22] __require_prelocked(uuidkey::Base.PkgId, env::String)
│        @ Base ./loading.jl:2388
│     [23] #invoke_in_world#3
│        @ ./essentials.jl:1089 [inlined]
│     [24] invoke_in_world
│        @ ./essentials.jl:1086 [inlined]
│     [25] _require_prelocked(uuidkey::Base.PkgId, env::String)
│        @ Base ./loading.jl:2375
│     [26] macro expansion
│        @ ./loading.jl:2314 [inlined]
│     [27] macro expansion
│        @ ./lock.jl:273 [inlined]
│     [28] __require(into::Module, mod::Symbol)
│        @ Base ./loading.jl:2271
│     [29] #invoke_in_world#3
│        @ ./essentials.jl:1089 [inlined]
│     [30] invoke_in_world
│        @ ./essentials.jl:1086 [inlined]
│     [31] require(into::Module, mod::Symbol)
│        @ Base ./loading.jl:2260
│     [32] eval
│        @ ./boot.jl:430 [inlined]
│     [33] include_string(mapexpr::typeof(REPL.softscope), mod::Module, code::String, filename::String)
│        @ Base ./loading.jl:2775
│     [34] include_string
│        @ ./loading.jl:2759 [inlined]
│     [35] #69
│        @ ~/.julia/packages/Xranklin/eTwhW/src/context/code/eval.jl:91 [inlined]
│     [36] (::IOCapture.var"#5#9"{DataType, Xranklin.var"#69#70"{Module, String}, IOContext{Base.PipeEndpoint}, IOContext{Base.PipeEndpoint}, IOContext{Base.PipeEndpoint}, IOContext{Base.PipeEndpoint}})()
│        @ IOCapture ~/.julia/packages/IOCapture/Y5rEA/src/IOCapture.jl:170
│     [37] with_logstate(f::IOCapture.var"#5#9"{DataType, Xranklin.var"#69#70"{Module, String}, IOContext{Base.PipeEndpoint}, IOContext{Base.PipeEndpoint}, IOContext{Base.PipeEndpoint}, IOContext{Base.PipeEndpoint}}, logstate::Base.CoreLogging.LogState)
│        @ Base.CoreLogging ./logging/logging.jl:524
│     [38] with_logger(f::Function, logger::Base.CoreLogging.ConsoleLogger)
│        @ Base.CoreLogging ./logging/logging.jl:635
│     [39] capture(f::Xranklin.var"#69#70"{Module, String}; rethrow::Type, color::Bool, passthrough::Bool, capture_buffer::IOBuffer, io_context::Vector{Any})
│        @ IOCapture ~/.julia/packages/IOCapture/Y5rEA/src/IOCapture.jl:167
│     [40] _attempt_eval
│        @ ~/.julia/packages/Xranklin/eTwhW/src/context/code/eval.jl:90 [inlined]
│     [41] eval_nb_cell(mdl::Module, code::String; cell_name::String, repl_mode::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/context/code/eval.jl:73
│     [42] eval_nb_cell
│        @ ~/.julia/packages/Xranklin/eTwhW/src/context/code/eval.jl:45 [inlined]
│     [43] _eval_code_cell(mdl::Module, code::String, cell_name::String, repl_mode::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/context/code/notebook_code.jl:169
│     [44] eval_code_cell!(lc::Xranklin.LocalContext, cell_code::SubString{String}, cell_name::String; imgdir_html::String, imgdir_latex::String, force::Bool, indep::Bool, repl_mode::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/context/code/notebook_code.jl:126
│     [45] eval_code_cell!
│        @ ~/.julia/packages/Xranklin/eTwhW/src/context/code/notebook_code.jl:21 [inlined]
│     [46] _eval_repl_code(io::IOBuffer, ci::Xranklin.CodeInfo, lc::Xranklin.LocalContext; tohtml::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/rules/code.jl:388
│     [47] _eval_repl_code
│        @ ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/rules/code.jl:352 [inlined]
│     [48] html_repl_code(ci::Xranklin.CodeInfo, lc::Xranklin.LocalContext)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/rules/code.jl:332
│     [49] html_code_block(b::FranklinParser.Block, lc::Xranklin.LocalContext)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/rules/code.jl:257
│     [50] top-level scope
│        @ none:1
│     [51] eval
│        @ ./boot.jl:430 [inlined]
│     [52] eval
│        @ ~/.julia/packages/Xranklin/eTwhW/src/Xranklin.jl:1 [inlined]
│     [53] convert_block(b::FranklinParser.Block, c::Xranklin.LocalContext; tohtml::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:201
│     [54] convert_block
│        @ ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:189 [inlined]
│     [55] html
│        @ ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:203 [inlined]
│     [56] convert_md(md::SubString{String}, c::Xranklin.LocalContext; tohtml::Bool, nop::Bool, error_backtracking_iteration::Int64, kw::@Kwargs{})
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:145
│     [57] convert_md
│        @ ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:20 [inlined]
│     [58] convert_md(s::String, a::Xranklin.LocalContext; kw::@Kwargs{})
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:153
│     [59] convert_md
│        @ ~/.julia/packages/Xranklin/eTwhW/src/convert/markdown/md_core.jl:153 [inlined]
│     [60] process_md_file_pass_1(lc::Xranklin.LocalContext, fpath::String; allow_init_skip::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/process/md/pass_1.jl:72
│     [61] process_md_file_pass_1
│        @ ~/.julia/packages/Xranklin/eTwhW/src/process/md/pass_1.jl:19 [inlined]
│     [62] _md_loop_1(gc::Xranklin.GlobalContext{Xranklin.LocalContext}, fp::Pair{String, String}, skip_dict::Dict{Pair{String, String}, Bool}, allow_init_skip::Bool; reproc::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/build/full_pass.jl:347
│     [63] _md_loop_1
│        @ ~/.julia/packages/Xranklin/eTwhW/src/build/full_pass.jl:337 [inlined]
│     [64] full_pass_markdown(gc::Xranklin.GlobalContext{Xranklin.LocalContext}, watched::Dict{Pair{String, String}, Float64}; skip_files::Vector{Pair{String, String}}, allow_init_skip::Bool, final::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/build/full_pass.jl:426
│     [65] full_pass_markdown
│        @ ~/.julia/packages/Xranklin/eTwhW/src/build/full_pass.jl:388 [inlined]
│     [66] full_pass(gc::Xranklin.GlobalContext{Xranklin.LocalContext}, watched_files::Dict{Symbol, Dict{Pair{String, String}, Float64}}; skip_files::Vector{Pair{String, String}}, initial_pass::Bool, config_changed::Bool, utils_changed::Bool, allow_no_index::Bool, final::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/build/full_pass.jl:179
│     [67] serve(d::String; dir::String, folder::String, clear::Bool, final::Bool, single::Bool, eval::Bool, nocode::Bool, threads::Bool, use_threads::Bool, prepath::String, prefix::String, base_url_prefix::String, allow_no_index::Bool, debug::Bool, cleanup::Bool, skip::Vector{String}, port::Int64, host::String, launch::Bool)
│        @ Xranklin ~/.julia/packages/Xranklin/eTwhW/src/build/serve.jl:222
│     [68] serve
│        @ ~/.julia/packages/Xranklin/eTwhW/src/build/serve.jl:58 [inlined]
│     [69] #build#317
│        @ ~/.julia/packages/Xranklin/eTwhW/src/build/serve.jl:337 [inlined]
│     [70] top-level scope
│        @ ~/work/_actions/tlienart/xranklin-build-action/main/main.jl:68
│     [71] include(mod::Module, _path::String)
│        @ Base ./Base.jl:562
│     [72] exec_options(opts::Base.JLOptions)
│        @ Base ./client.jl:316
└ @ Base loading.jl:1550

julia> @btime sum_abs(v);
99.350 ns (1 allocation: 16 bytes)

julia> @btime sum_abs($v);
61.062 ns (0 allocations: 0 bytes)
```

In more complex settings, you might need to construct variables in a [setup phase](https://juliaci.github.io/BenchmarkTools.jl/stable/manual/#Setup-and-teardown-phases) that is run before each sample. This can be useful to generate a new random input every time, instead of always using the same input.

```
julia> my_matmul(A, b) = A * b;

julia> @btime my_matmul(A, b) setup=(
    A = rand(1000, 1000); # use semi-colons between setup lines
    b = rand(1000)
);
152.735 μs (3 allocations: 7.88 KiB)
```

For better visualization, the `@benchmark` macro shows performance histograms.

### [Chairmarks](#chairmarks)

[Chairmarks.jl](https://github.com/LilithHafner/Chairmarks.jl) is a later benchmarking toolkit with a slightly different design and syntax. Chairmarks offers `@b` (for "benchmark") which can be used in the same way as `@time` but will run the code multiple times and provide a minimum execution time. Alternatively, Chairmarks also provides `@be` to run the same benchmark and output all of its statistics.

```
julia> using Chairmarks

julia> @b sum_abs(v)
Chairmarks.Sample(256.0, 9.905078125e-8, 1.0, 16.0, 0.0, 0.0, 0.0, 1.0)
```

Chairmarks supports a pipeline syntax with optional `init`, `setup`, `teardown`, and `keywords` arguments for more extensive control over the benchmarking process. The `sum_abs` function could also be benchmarked using pipeline syntax as below.

```
julia> @b v sum_abs
Sample(evals=476, time=6.082773109243698e-8)
```

For a more complicated example, you could write the following to benchmark a matrix multiplication function for one second, excluding the time spent to _setup_ the arrays.

```
julia> my_matmul(A, b) = A * b;

julia> @b (A=rand(1000,1000), b=rand(1000)) my_matmul(_.A, _.b) seconds=1
Sample(time=0.00013402000000000002, allocs=3, bytes=8072)
```

See the [Chairmarks documentation](https://chairmarks.lilithhafner.com/) for more details on benchmarking options. For better visualization, [PrettyChairmarks.jl](https://github.com/astrozot/PrettyChairmarks.jl) shows performance histograms alongside the numerical results.

### [Benchmark suites](#benchmark_suites)

While we previously discussed the importance of documenting breaking changes in packages using [semantic versioning](/sharing/index.md#versions-and-registration), regressions in performance can also be vital to track. Several packages exist for this purpose:

*   [PkgBenchmark.jl](https://github.com/JuliaCI/PkgBenchmark.jl) and its unmaintained but functional CI wrapper [BenchmarkCI.jl](https://github.com/tkf/BenchmarkCI.jl)
*   [AirSpeedVelocity.jl](https://github.com/MilesCranmer/AirspeedVelocity.jl)
*   [PkgJogger.jl](https://github.com/awadell1/PkgJogger.jl)

For tracking time-to-first-X (TTFX) performance across different Julia versions and package updates, [Julia-TTFX-Snippets](https://github.com/tecosaur/Julia-TTFX-Snippets) provides a collection of TTFX workloads specifically designed for longitudinal performance testing of Julia packages.

### [Other tools](#other_tools)

To find bottlenecks in a larger program, you should rather use a [profiler](#profiling) or the package [TimerOutputs.jl](https://github.com/KristofferC/TimerOutputs.jl). It allows you to label different sections of your code, then time them and display a table of grouped by label.

For command-line benchmarking outside of Julia, [hyperfine](https://github.com/sharkdp/hyperfine) is an excellent tool for timing the execution of entire Julia scripts or comparing different implementations at the process level.

Finally, if you know a loop is slow and you'll need to wait for it to be done, you can use [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl) or [ProgressLogging.jl](https://github.com/JuliaLogging/ProgressLogging.jl) to track its progress.

## [Profiling](#profiling)

**TLDR**: Profiling can identify performance bottlenecks at function level, and graphical tools such as ProfileView.jl are the best way to use it.

### [Sampling](#sampling)

Whereas a benchmark measures the overall performance of some code, a profiler breaks it down function by function to identify bottlenecks. Sampling-based profilers periodically ask the program which line it is currently executing, and aggregate results by line or by function. Julia offers two kinds: [one for runtime](https://docs.julialang.org/en/v1/stdlib/Profile/#lib-profiling) (in the module `Profile`) and [one for memory](https://docs.julialang.org/en/v1/stdlib/Profile/#Memory-profiling) (in the submodule `Profile.Allocs`).

These built-in profilers print textual outputs, but the result of profiling is best visualized as a flame graph. In a flame graph, each horizontal layer corresponds to a specific level in the call stack, and the width of a tile shows how much time was spent in the corresponding function. Here's an example:

![flamegraph](https://github.com/pfitzseb/ProfileCanvas.jl/raw/main/assets/flamegraph.png)

### [Visualization tools](#visualization_tools)

The packages [ProfileView.jl](https://github.com/timholy/ProfileView.jl) and [PProf.jl](https://github.com/JuliaPerf/PProf.jl) both allow users to record and interact with flame graphs. ProfileView.jl is simpler to use, but PProf is more featureful and is based on [pprof](https://github.com/google/pprof), an external tool maintained by Google which applies to more than just Julia code. Here we only demonstrate the former:

```
using ProfileView
@profview do_work(some_input)
```

**VSCode**: Calling `@profview do_work(some_input)` in the integrated Julia REPL will open an interactive flame graph, similar to ProfileView.jl but without requiring a separate package.

To integrate profile visualisations into environments like Jupyter and Pluto, use [ProfileSVG.jl](https://github.com/kimikage/ProfileSVG.jl) or [ProfileCanvas.jl](https://github.com/pfitzseb/ProfileCanvas.jl), whose outputs can be embedded into a notebook.

For sharing profiles with others (e.g., on Slack or Discourse), [StatProfilerHTML.jl](https://github.com/tkluck/StatProfilerHTML.jl) is particularly useful as it generates self-contained HTML files that can be zipped and shared, allowing others to inspect the profiling results interactively without needing Julia installed.

No matter which tool you use, if your code is too fast to collect samples, you may need to run it multiple times in a loop.

**Advanced**: To visualize memory allocation profiles, use PProf.jl or VSCode's `@profview_allocs`. A known issue with the allocation profiler is that it is not able to determine the type of every object allocated, instead `Profile.Allocs.UnknownType` is shown instead. Inspecting the call graph can help identify which types are responsible for the allocations.

### [External profilers](#external_profilers)

Apart from the built-in `Profile` standard library, there are a few external profilers that you can use including [Intel VTune](https://www.intel.com/content/www/us/en/developer/tools/oneapi/vtune-profiler.html) (in combination with [IntelITT.jl](https://github.com/JuliaPerf/IntelITT.jl)), [NVIDIA Nsight Systems](https://developer.nvidia.com/nsight-systems) (in combination with [NVTX.jl](https://github.com/JuliaGPU/NVTX.jl)), and [Tracy](https://docs.julialang.org/en/v1/devdocs/external_profilers/#Tracy-Profiler).

## [Type stability](#type_stability)

**TLDR**: Use JET.jl to automatically detect type instabilities in your code, and `@code_warntype` or Cthulhu.jl to do so manually. DispatchDoctor.jl can help prevent them altogether.

For a section of code to be considered type stable, the type inferred by the compiler must be "concrete", which means that the size of memory that needs to be allocated to store its value is known at compile time. Types declared abstract with `abstract type` are not concrete and neither are [parametric types](https://docs.julialang.org/en/v1/manual/types/#Parametric-Types) whose parameters are not specified:

```
julia> isconcretetype(Any)
false

julia> isconcretetype(AbstractVector)
false

julia> isconcretetype(Vector) # Shorthand for `Vector{T} where T`
false

julia> isconcretetype(Vector{Real})
true

julia> isconcretetype(eltype(Vector{Real}))
false

julia> isconcretetype(Vector{Int64})
true

julia> isconcretetype(eltype(Vector{Int64}))
true
```

**Advanced**: `Vector{Real}` is concrete despite `Real` being abstract for [subtle typing reasons](https://docs.julialang.org/en/v1/manual/types/#man-parametric-composite-types) but it will still be slow in practice because the type of its elements is abstract.

While type-stable function calls compile down to fast `GOTO` statements, type-unstable function calls generate code that must read the list of all methods for a given operation and find the one that matches. This phenomenon called "dynamic dispatch" prevents further optimizations.

Type-stability is a fragile thing: if a variable's type cannot be inferred, then the types of variables that depend on it may not be inferrable either. As a first approximation, most code should be type-stable unless it has a good reason not to be.

### [Detecting instabilities](#detecting_instabilities)

The simplest way to detect an instability is with the builtin macro [`@code_warntype`](https://docs.julialang.org/en/v1/manual/performance-tips/#man-code-warntype): The output of `@code_warntype` is difficult to parse, but the key takeaway is the return type of the function's `Body`: if it is an abstract type, like `Any`, something is wrong. In a normal Julia REPL, such cases would show up colored in red as a warning.

```
julia> function put_in_vec_and_sum(x)
    v = []
    push!(v, x)
    return sum(v)
end;

julia> @code_warntype put_in_vec_and_sum(1)
MethodInstance for Main.__FRANKLIN_1579807.put_in_vec_and_sum(::Int64)
  from put_in_vec_and_sum(x) @ Main.__FRANKLIN_1579807 string:1
Arguments
  #self#::Core.Const(Main.__FRANKLIN_1579807.put_in_vec_and_sum)
  x::Int64
Locals
  v::Vector{Any}
Body::Any
1 ─      (v = Base.vect())
│   %2 = Main.__FRANKLIN_1579807.push!::Core.Const(push!)
│   %3 = v::Vector{Any}
│        (%2)(%3, x)
│   %5 = v::Vector{Any}
│   %6 = Main.__FRANKLIN_1579807.sum(%5)::Any
└──      return %6
```

Unfortunately, `@code_warntype` is limited to one function body: calls to other functions are not expanded, which makes deeper type instabilities easy to miss. That is where [JET.jl](https://github.com/aviatesk/JET.jl) can help: it provides [optimization analysis](https://aviatesk.github.io/JET.jl/stable/optanalysis/) aimed primarily at finding type instabilities. While [test integrations](https://aviatesk.github.io/JET.jl/stable/optanalysis/#optanalysis-test-integration) are also provided, the interactive entry point of JET is the `@report_opt` macro.

```
julia> using JET

julia> @report_opt put_in_vec_and_sum(1)
═════ 4 possible errors found ═════
┌ put_in_vec_and_sum(x::Int64) @ Main.__FRANKLIN_1579807 ./string:4
│┌ sum(a::Vector{Any}) @ Base ./reducedim.jl:982
││┌ sum(a::Vector{Any}; dims::Colon, kw::@Kwargs{}) @ Base ./reducedim.jl:982
│││┌ _sum(a::Vector{Any}, ::Colon) @ Base ./reducedim.jl:986
││││┌ _sum(a::Vector{Any}, ::Colon; kw::@Kwargs{}) @ Base ./reducedim.jl:986
│││││┌ _sum(f::typeof(identity), a::Vector{Any}, ::Colon) @ Base ./reducedim.jl:987
││││││┌ _sum(f::typeof(identity), a::Vector{Any}, ::Colon; kw::@Kwargs{}) @ Base ./reducedim.jl:987
│││││││┌ mapreduce(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{Any}) @ Base ./reducedim.jl:329
││││││││┌ mapreduce(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{Any}; dims::Colon, init::Base._InitialValue) @ Base ./reducedim.jl:329
│││││││││┌ _mapreduce_dim(f::typeof(identity), op::typeof(Base.add_sum), ::Base._InitialValue, A::Vector{Any}, ::Colon) @ Base ./reducedim.jl:337
││││││││││┌ _mapreduce(f::typeof(identity), op::typeof(Base.add_sum), ::IndexLinear, A::Vector{Any}) @ Base ./reduce.jl:444
│││││││││││┌ mapreduce_impl(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{Any}, ifirst::Int64, ilast::Int64) @ Base ./reduce.jl:277
││││││││││││┌ mapreduce_impl(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{…}, ifirst::Int64, ilast::Int64, blksize::Int64) @ Base ./reduce.jl:262
│││││││││││││ runtime dispatch detected: op::typeof(Base.add_sum)(%91::Any, %110::Any)::Any
││││││││││││└────────────────────
││││││││││││┌ mapreduce_impl(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{…}, ifirst::Int64, ilast::Int64, blksize::Int64) @ Base ./reduce.jl:273
│││││││││││││ runtime dispatch detected: op::typeof(Base.add_sum)(%187::Any, %189::Any)::Any
││││││││││││└────────────────────
││││││││││┌ _mapreduce(f::typeof(identity), op::typeof(Base.add_sum), ::IndexLinear, A::Vector{Any}) @ Base ./reduce.jl:437
│││││││││││ runtime dispatch detected: op::typeof(Base.add_sum)(%97::Any, %115::Any)::Any
││││││││││└────────────────────
││││││││││┌ _mapreduce(f::typeof(identity), op::typeof(Base.add_sum), ::IndexLinear, A::Vector{Any}) @ Base ./reduce.jl:440
│││││││││││ runtime dispatch detected: op::typeof(Base.add_sum)(%118::Any, %139::Any)::Any
││││││││││└────────────────────
```

**VSCode**: The Julia extension features a [static linter](https://www.julia-vscode.org/docs/stable/userguide/linter/), and runtime diagnostics with JET can be automated to run periodically on your codebase and show any problems detected.

[Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl) exposes the `@descend` macro which can be used to interactively "step through" lines of the corresponding typed code, and "descend" into a particular line if needed. This is akin to repeatedly calling `@code_warntype` deeper and deeper into your functions, slowly succumbing to the madness... We cannot demonstrate it on a static website, but the [video example](https://www.youtube.com/watch?v=pvduxLowpPY) is a good starting point.

### [Fixing instabilities](#fixing_instabilities)

The Julia manual has a collection of tips to [improve type inference](https://docs.julialang.org/en/v1.12-dev/manual/performance-tips/#Type-inference).

A more direct approach is to error whenever a type instability occurs: the macro `@stable` from [DispatchDoctor.jl](https://github.com/MilesCranmer/DispatchDoctor.jl) allows exactly that.

## [Memory management](#memory_management)

**TLDR**: You can reduce allocations with careful array management.

After ensuring type stability, one should try to reduce the number of heap allocations a program makes. Again, the Julia manual has a series of tricks related to [arrays and allocations](https://docs.julialang.org/en/v1.12-dev/manual/performance-tips/#Memory-management-and-arrays) which you should take a look at. In particular, try to modify existing arrays instead of allocating new objects (caution with array slices) and try to access arrays in the right order (column major order).

And again, you can also choose to error whenever an allocation occurs, with the help of [AllocCheck.jl](https://github.com/JuliaLang/AllocCheck.jl). By annotating a function with `@check_allocs`, if the function is run and the compiler detects that it might allocate, it will throw an error. Alternatively, to ensure that non-allocating functions never regress in future versions of your code, you can write a test set to check allocations by providing the function and a concrete type-signature.

```
@testset "non-allocating" begin
    @test isempty(AllocCheck.check_allocs(my_func, (Float64, Float64)))
end
```

## [Compilation](#compilation)

**TLDR**: If you can anticipate which functions or packages you will need, loading time can be greatly reduced with PrecompileTools.jl or PackageCompiler.jl.

A number of tools allow you to reduce Julia's latency, also referred to as TTFX (time to first X, where X was historically plotting a graph).

### [Precompilation](#precompilation)

[PrecompileTools.jl](https://github.com/JuliaLang/PrecompileTools.jl) reduces the amount of time taken to run functions loaded from a package or local module that you wrote. It allows module authors to give a "list" of methods to precompile when a module is loaded for the first time. These methods then have the same latency as if they had already been run by the end user.

Here's an example of precompilation, adapted from the package's [documentation](https://julialang.github.io/PrecompileTools.jl/stable/#Tutorial:-forcing-precompilation-with-workloads):

```
module MyPackage

using PrecompileTools: @compile_workload

struct MyType
    x::Int
end

myfunction(a::Vector) = a[1].x

@compile_workload begin
    a = [MyType(1)]
    myfunction(a)
end

end
```

Note that every method that is called will be compiled, no matter how far down the call stack or which module it comes from. To see if the intended calls were compiled correctly or diagnose other problems related to precompilation, use [SnoopCompile.jl](https://github.com/timholy/SnoopCompile.jl). This is especially important for writers of registered Julia packages, as it allows you to diagnose recompilation that happens due to invalidation.

For alternative approaches to precompilation, [PrecompileSignatures.jl](https://github.com/rikhuijzer/PrecompileSignatures.jl) can generate precompile directives by reading method signatures, which can be especially useful when you want to ensure specific method combinations are precompiled.

For managing precompilation after Julia version updates, [PrecompileAfterUpdate.jl](https://github.com/roflmaostc/PrecompileAfterUpdate.jl) can precompile your recent environments automatically after a Julia version update, saving you time when switching between Julia versions.

### [Package compilation](#package_compilation)

To reduce the time that packages take to load, you can use [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) to generate a custom version of Julia, called a sysimage, with its own standard library. As packages in the standard library are already compiled, any `using` or `import` statement involving them is almost instant.

Once PackageCompiler.jl is added to your global environment, activate a local environment for which you want to generate a sysimage, ensure all of the packages you want to compile are in its `Project.toml`, and run `create_sysimage` as in the example below. The filetype of `sysimage_path` differs by operating system: Linux has `.so`, MacOS has `.dylib`, and Windows has `.dll`.

```
packages_to_compile = ["Makie", "DifferentialEquations"]
create_sysimage(packages_to_compile; sysimage_path="MySysimage.so")
```

Once a sysimage is generated, it can be used with the command line flag: `julia --sysimage=path/to/sysimage`.

**VSCode**: The generation and loading of sysimages can be [streamlined with VSCode](https://www.julia-vscode.org/docs/stable/userguide/compilesysimage/). By default, the command sequence `Task: Run Build Task` followed by `Julia: Build custom sysimage for current environment` will compile a sysimage containing all packages in the current environment, but additional details can be specified in a `/.vscode/JuliaSysimage.toml` file. To automatically detect and use a custom sysimage, set `useCustomSysimage` to `true` in the application settings.

### [Static compilation](#static_compilation)

[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) also facilitates the creation of [apps](https://julialang.github.io/PackageCompiler.jl/stable/apps.html) and [libraries](https://julialang.github.io/PackageCompiler.jl/stable/libs.html) that can be shared to and run on machines that don't have Julia installed.

At a basic level, all that's required to turn a Julia module `MyModule` into an app is a function `julia_main()::Cint` that returns `0` upon successful completion. Then, with PackageCompiler.jl loaded, run `create_app("MyModule", "MyAppCompiled")`. Command line arguments to the resulting app are assigned to the global variable `ARGS::Array{ASCIIString}`, the handling of which can be made easier by [ArgParse.jl](https://github.com/carlobaldassi/ArgParse.jl).

In Julia, a library is just a sysimage with some extras that enable external programs to interact with it. Any functions in a module marked with `Base.@ccallable`, and whose type signature involves C-conforming types e.g. `Cint`, `Cstring`, and `Cvoid`, can be compiled into an externally callable library with `create_library`, similarly to `create_app`. Unfortunately, the process of compiling and sharing a standalone executable or callable library must take [relocability](https://julialang.github.io/PackageCompiler.jl/stable/apps.html#relocatability) into account, which is beyond the scope of this blog.

**Advanced**: An alternative way to compile a shareable app or library that doesn't need to compile a sysimage, and therefore results in smaller binaries, is to use [StaticCompiler.jl](https://github.com/tshort/StaticCompiler.jl) and its sister package [StaticTools.jl](https://github.com/brenhinkeller/StaticTools.jl). The biggest tradeoff of not compiling a sysimage, is that Julia's garbage collector is no longer included, so all heap allocations must be managed manually, and all code compiled _must_ be type-stable. To get around this limitation, you can use static equivalents of dynamic types, such as a `StaticArray` ([StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl)) instead of an `Array` or a `StaticString` (StaticTools.jl), use `malloc` and `free` from StaticTools.jl directly, or use arena allocators with [Bumper.jl](https://github.com/MasonProtter/Bumper.jl). The README of StaticCompiler.jl contains a more [detailed guide](https://github.com/tshort/StaticCompiler.jl?tab=readme-ov-file#guide-for-package-authors) on how to prepare code to be compiled.

For more advanced compilation workflows, [JuliaC.jl](https://github.com/JuliaLang/JuliaC.jl) provides tools for compiling and bundling Julia binaries with trimmed dependencies, particularly useful for creating minimal deployments.

## [Parallelism](#parallelism)

**TLDR**: Use `Threads` or OhMyThreads.jl on a single machine, `Distributed` or MPI.jl on a computing cluster. GPU-compatible code is easy to write and run.

Code can be made to run faster through parallel execution with [multithreading](https://docs.julialang.org/en/v1/manual/multi-threading/) (shared-memory parallelism) or [multiprocessing / distributed computing](https://docs.julialang.org/en/v1/manual/distributed-computing/). Many common operations such as maps and reductions can be trivially parallelised through either method by using their respective Julia packages (e.g `pmap` from Distributed.jl and `tmap` from OhMyThreads.jl). Multithreading is available on almost all modern hardware, whereas distributed computing is most useful to users of high-performance computing clusters.

### [Multithreading](#multithreading)

To enable multithreading with the built-in `Threads` library, use one of the following equivalent command line flags, and give either an integer or `auto`:

```
julia --threads 4
julia -t auto
```

Once Julia is running, you can check if this was successful by calling `Threads.nthreads()`.

**VSCode**: The default number of threads can be edited by adding `"julia.NumThreads": 4,` to your settings. This will be applied to the integrated terminal.

**Advanced**: Linear algebra code calls the low-level libraries [BLAS](https://en.wikipedia.org/wiki/Basic_Linear_Algebra_Subprograms) and [LAPACK](https://en.wikipedia.org/wiki/LAPACK). These libraries manage their own pool of threads, so single-threaded Julia processes can still make use of multiple threads, and multi-threaded Julia processes that call these libraries may run into performance issues due to the limited number of threads available in a single core. In this case, once `LinearAlgebra` is loaded, BLAS can be set to use only one thread by calling `BLAS.set_num_threads(1)`. For more information see the docs on [multithreading and linear algebra](https://docs.julialang.org/en/v1/manual/performance-tips/#man-multithreading-linear-algebra).

Regardless of the number of threads, you can parallelise a for loop with the macro `Threads.@threads`. The macros `@spawn` and `@async` function similarly, but require more manual management of tasks and their results. For this reason `@threads` is recommended for those who do not wish to use third-party packages.

When designing multithreaded code, you should generally try to write to shared memory as rarely as possible. Where it cannot be avoided, you need to be careful to avoid "race conditions", i.e. situations when competing threads try to write different things to the same memory location. It is usually a good idea to separate memory accesses with loop indices, as in the example below:

```
results = zeros(Int, 4)
Threads.@threads for i in 1:4
    results[i] = i^2
end
```

Almost always, it is [**not** a good idea to use `threadid()`](https://julialang.org/blog/2023/07/PSA-dont-use-threadid/).

Even if you manage to avoid any race conditions in your multithreaded code, it is very easy to run into subtle performance issues (like [false sharing](https://en.wikipedia.org/wiki/False_sharing)). For these reasons, you might want to consider using a high-level package like [OhMyThreads.jl](https://github.com/JuliaFolds2/OhMyThreads.jl), which provides a user-friendly alternative to `Threads` and makes managing threads and their memory use much easier. The helpful [translation guide](https://juliafolds2.github.io/OhMyThreads.jl/stable/translation/) will get you started in a jiffy.

If the latency of spinning up new threads becomes a bottleneck, check out [Polyester.jl](https://github.com/JuliaSIMD/Polyester.jl) for very lightweight threads that are quicker to start.

If you're on Linux, you should consider using [ThreadPinning.jl](https://github.com/carstenbauer/ThreadPinning.jl) to pin your Julia threads to CPU cores to obtain stable and optimal performance. The package can also be used to visualize where the Julia threads are running on your system (see `threadinfo()`).

**Advanced**: Some widely used parallel programming packages like [LoopVectorization.jl](https://github.com/JuliaSIMD/LoopVectorization.jl) (which also powers [Octavian.jl](https://github.com/JuliaLinearAlgebra/Octavian.jl)) or [ThreadsX.jl](https://github.com/tkf/ThreadsX.jl) are no longer maintained.

### [Distributed computing](#distributed_computing)

Julia's multiprocessing and distributed computing relies on the standard library `Distributed`. The main difference compared to multi-threading is that data isn't shared between worker processes. Once Julia is started, processes can be added with `addprocs`, and they can be queried with `nworkers`.

The macro `Distributed.@distributed` is a _syntactic_ equivalent for `Threads.@threads`. Hence, we can use `@distributed` to parallelise a for loop as before, but we have to additionally deal with sharing and recombining the `results` array. We can delegate this responsibility to the standard library `SharedArrays`. However, in order for all workers to know about a function or module, we have to load it `@everywhere`:

```
using Distributed

# Add additional workers then load code on the workers
addprocs(3)
@everywhere using SharedArrays
@everywhere f(x) = 3x^2

results = SharedArray{Int}(4)
@sync @distributed for i in 1:4
    results[i] = f(i)
end
```

Note that `@distributed` does not force the main process to wait for other workers, so we must use `@sync` to block execution until all computations are done.

One feature `@distributed` has over `@threads` is the possibility to specify a reduction function (an associative binary operator) which combines the results of each worker. In this case `@sync` is implied, as the reduction cannot happen unless all of the workers have finished.

```
@distributed (+) for i in 1:4
    i^2
end
```

Alternately, the convenience function `pmap` can be used to easily parallelise a `map`, both in a distributed and multi-threaded way.

```
results = pmap(f, 1:100; distributed=true, batch_size=25, on_error=ex->0)
```

For more functionalities related to higher-order functions, [Transducers.jl](https://github.com/JuliaFolds2/Transducers.jl) and [Folds.jl](https://github.com/JuliaFolds2/Folds.jl) are the way to go.

**Advanced**: [MPI.jl](https://github.com/JuliaParallel/MPI.jl) implements the [Message Passing Interface standard](https://en.wikipedia.org/wiki/Message_Passing_Interface), which is heavily used in high-performance computing beyond Julia. The C library that MPI.jl wraps is _highly_ optimized, so Julia code that needs to be scaled up to a large number of cores, such as an HPC cluster, will typically run faster with MPI than with plain `Distributed`.

[Elemental.jl](https://github.com/JuliaParallel/Elemental.jl) is a package for distributed dense and sparse linear algebra which wraps the [Elemental](https://github.com/LLNL/Elemental) library written in C++, itself using MPI under the hood.

### [GPU programming](#gpu_programming)

GPUs are specialised in executing instructions in parallel over a large number of threads. While they were originally designed for accelerating graphics rendering, more recently they have been used to train and evaluate machine learning models.

Julia's GPU ecosystem is managed by the [JuliaGPU](https://juliagpu.org/) organisation, which provides individual packages for directly working with each GPU vendor's instruction set. The most popular one is [CUDA.jl](https://github.com/JuliaGPU/CUDA.jl), which also simplifies installation of CUDA drivers for NVIDIA GPUs. Through [KernelAbstractions.jl](https://github.com/JuliaGPU/KernelAbstractions.jl), you can easily write code that is agnostic to the type of GPU where it will run.

### [SIMD instructions](#simd_instructions)

In the Single Instruction, Multiple Data paradigm, several processing units perform the same instruction at the same time, differing only in their inputs. The range of operations that can be parallelised (or "vectorized") like this is more limited than in the previous sections, and slightly harder to control. Julia can automatically vectorize repeated numerical operations (such as those found in loops) provided a few conditions are met:

1.  Reordering operations must not change the result of the computation.
2.  There must be no control flow or branches in the core computation.
3.  All array accesses must follow some linear pattern.

While this may seem straightforward, there are a number of important caveats which prevent code from being vectorized. [Performance annotations](https://docs.julialang.org/en/v1/manual/performance-tips/#man-performance-annotations) like `@simd` or `@inbounds` help enable vectorization in some cases, as does replacing control flow with `ifelse`.

If this isn't enough, [SIMD.jl](https://github.com/eschnett/SIMD.jl) allows users to force the use of SIMD instructions and bypass the check for whether this is possible. One particular use-case for this is for vectorising non-contiguous memory reads and writes through `SIMD.vgather` and `SIMD.vscatter` respectively.

**Advanced**: You can detect whether the optimizations have occurred by inspecting the output of `@code_llvm` or `@code_native` and looking for vectorised registers, types, instructions. Note that the exact things you're looking for will vary between code and CPU instruction set, an example of what to look for can be seen in this [blog post](https://kristofferc.github.io/post/intrinsics/) by Kristoffer Carlsson.

## [Efficient types](#efficient_types)

**TLDR**: Be aware that [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl) exist and learn how they work.

Using an efficient data structure is a tried and true way of improving the performance. While users can write their own efficient implementations through officially documented [interfaces](https://docs.julialang.org/en/v1/manual/interfaces/), a number of packages containing common use cases are more tightly integrated into the Julia ecosystem.

### [Static arrays](#static_arrays)

Using [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl), you can construct arrays which contain size information in their type. Through multiple dispatch, statically sized arrays give rise to specialised, efficient methods for certain algorithms like linear algebra. In addition, the `SArray`, `SMatrix` and `SVector` types are immutable, so the array does not need to be garbage collected as it can be stack-allocated. Creating a new `SArray`s comes at almost no extra cost, compared to directly editing the data of a mutable object. With `MArray`, `MMatrix`, and `MVector`, data remains mutable as in normal arrays.

To handle mutable and immutable data structures with the same syntax, you can use [Accessors.jl](https://github.com/JuliaObjects/Accessors.jl):

```
using StaticArrays, Accessors

sx = SA[1, 2, 3] # SA constructs an SArray
@set sx[1] = 3 # Returns a copy, does not update the variable
@reset sx[1] = 4 # Replaces the original
```

### [Classic data structures](#classic_data_structures)

All but the most obscure data structures can be found in the packages from the [JuliaCollections](https://github.com/JuliaCollections) organization, especially [DataStructures.jl](https://github.com/JuliaCollections/DataStructures.jl) which has all the standards from the computer science courses (stacks, queues, heaps, trees and the like). Iteration and memoization utilities are also provided by packages like [IterTools.jl](https://github.com/JuliaCollections/IterTools.jl) and [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl).

[CC BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/) G. Dalle, J. Smit, A. Hill. Last modified: January 03, 2026.  
Website built with [Franklin.jl](https://github.com/tlienart/Franklin.jl) and the [Julia programming language](https://julialang.org).

hljs.highlightAll();hljs.configure({tabReplace: ' '});