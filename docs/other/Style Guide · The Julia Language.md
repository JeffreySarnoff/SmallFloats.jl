Style Guide · The Julia Language window.dataLayer = window.dataLayer || \[\]; function gtag(){dataLayer.push(arguments);} gtag('js', new Date()); gtag('config', 'UA-28835595-6', {'page\_path': location.pathname + location.search + location.hash}); documenterBaseURL="../.."

[![The Julia Language logo](../../assets/logo.svg)![The Julia Language logo](../../assets/logo-dark.svg)](../../)Search docs (Ctrl + /)

*   [Julia Documentation](../../)
*   Manual
    *   [Getting Started](../getting-started/)
    *   [Installation](../installation/)
    *   [Variables](../variables/)
    *   [Integers and Floating-Point Numbers](../integers-and-floating-point-numbers/)
    *   [Mathematical Operations and Elementary Functions](../mathematical-operations/)
    *   [Complex and Rational Numbers](../complex-and-rational-numbers/)
    *   [Strings](../strings/)
    *   [Functions](../functions/)
    *   [Control Flow](../control-flow/)
    *   [Scope of Variables](../variables-and-scoping/)
    *   [Types](../types/)
    *   [Methods](../methods/)
    *   [Constructors](../constructors/)
    *   [Conversion and Promotion](../conversion-and-promotion/)
    *   [Interfaces](../interfaces/)
    *   [Modules](../modules/)
    *   [Documentation](../documentation/)
    *   [Metaprogramming](../metaprogramming/)
    *   [Single- and multi-dimensional Arrays](../arrays/)
    *   [Missing Values](../missing/)
    *   [Networking and Streams](../networking-and-streams/)
    *   [Parallel Computing](../parallel-computing/)
    *   [Asynchronous Programming](../asynchronous-programming/)
    *   [Multi-Threading](../multi-threading/)
    *   [Multi-processing and Distributed Computing](../distributed-computing/)
    *   [Running External Programs](../running-external-programs/)
    *   [Calling C and Fortran Code](../calling-c-and-fortran-code/)
    *   [Handling Operating System Variation](../handling-operating-system-variation/)
    *   [Environment Variables](../environment-variables/)
    *   [Embedding Julia](../embedding/)
    *   [Code Loading](../code-loading/)
    *   [Profiling](../profile/)
    *   [Stack Traces](../stacktraces/)
    *   [Memory Management and Garbage Collection](../memory-management/)
    *   [Performance Tips](../performance-tips/)
    *   [Workflow Tips](../workflow-tips/)
    *   Style Guide
        *   [Indentation](#Indentation)
        *   [Write functions, not just scripts](#Write-functions,-not-just-scripts)
        *   [Avoid writing overly-specific types](#Avoid-writing-overly-specific-types)
        *   [Handle excess argument diversity in the caller](#Handle-excess-argument-diversity-in-the-caller)
        *   [Append `!` to names of functions that modify their arguments](#bang-convention)
        *   [Avoid strange type `Union`s](#Avoid-strange-type-Unions)
        *   [Avoid elaborate container types](#Avoid-elaborate-container-types)
        *   [Prefer exported methods over direct field access](#Prefer-exported-methods-over-direct-field-access)
        *   [Use naming conventions consistent with Julia `base/`](#Use-naming-conventions-consistent-with-Julia-base/)
        *   [Write functions with argument ordering similar to Julia Base](#Write-functions-with-argument-ordering-similar-to-Julia-Base)
        *   [Don't overuse try-catch](#Don't-overuse-try-catch)
        *   [Don't parenthesize conditions](#Don't-parenthesize-conditions)
        *   [Don't overuse `...`](#Don't-overuse-...)
        *   [Ensure constructors return an instance of their own type](#Ensure-constructors-return-an-instance-of-their-own-type)
        *   [Don't use unnecessary static parameters](#Don't-use-unnecessary-static-parameters)
        *   [Avoid confusion about whether something is an instance or a type](#Avoid-confusion-about-whether-something-is-an-instance-or-a-type)
        *   [Don't overuse macros](#Don't-overuse-macros)
        *   [Don't expose unsafe operations at the interface level](#Don't-expose-unsafe-operations-at-the-interface-level)
        *   [Don't overload methods of base container types](#Don't-overload-methods-of-base-container-types)
        *   [Avoid type piracy](#avoid-type-piracy)
        *   [Be careful with type equality](#Be-careful-with-type-equality)
        *   [Don't write a trivial anonymous function `x->f(x)` for a named function `f`](#Don't-write-a-trivial-anonymous-function-x-f\(x\)-for-a-named-function-f)
        *   [Avoid using floats for numeric literals in generic code when possible](#Avoid-using-floats-for-numeric-literals-in-generic-code-when-possible)
    *   [Frequently Asked Questions](../faq/)
    *   [Noteworthy Differences from other Languages](../noteworthy-differences/)
    *   [Unicode Input](../unicode-input/)
    *   [Command-line Interface](../command-line-interface/)
    *   [The World Age mechanism](../worldage/)
*   Base
    *   [Essentials](../../base/base/)
    *   [Collections and Data Structures](../../base/collections/)
    *   [Mathematics](../../base/math/)
    *   [Numbers](../../base/numbers/)
    *   [Strings](../../base/strings/)
    *   [Arrays](../../base/arrays/)
    *   [Tasks](../../base/parallel/)
    *   [Multi-Threading](../../base/multi-threading/)
    *   [Scoped Values](../../base/scopedvalues/)
    *   [Constants](../../base/constants/)
    *   [Filesystem](../../base/file/)
    *   [I/O and Network](../../base/io-network/)
    *   [Punctuation](../../base/punctuation/)
    *   [Sorting and Related Functions](../../base/sort/)
    *   [Iteration utilities](../../base/iterators/)
    *   [Reflection and introspection](../../base/reflection/)
    *   [C Interface](../../base/c/)
    *   [C Standard Library](../../base/libc/)
    *   [StackTraces](../../base/stacktraces/)
    *   [SIMD Support](../../base/simd-types/)
*   Standard Library
    *   [ArgTools](../../stdlib/ArgTools/)
    *   [Artifacts](../../stdlib/Artifacts/)
    *   [Base64](../../stdlib/Base64/)
    *   [CRC32c](../../stdlib/CRC32c/)
    *   [Dates](../../stdlib/Dates/)
    *   [Delimited Files](../../stdlib/DelimitedFiles/)
    *   [Distributed Computing](../../stdlib/Distributed/)
    *   [Downloads](../../stdlib/Downloads/)
    *   [Dynamic Linker](../../stdlib/Libdl/)
    *   [File Events](../../stdlib/FileWatching/)
    *   [Future](../../stdlib/Future/)
    *   [Interactive Utilities](../../stdlib/InteractiveUtils/)
    *   [Julia Syntax Highlighting](../../stdlib/JuliaSyntaxHighlighting/)
    *   [Lazy Artifacts](../../stdlib/LazyArtifacts/)
    *   [LibCURL](../../stdlib/LibCURL/)
    *   [LibGit2](../../stdlib/LibGit2/)
    *   [Linear Algebra](../../stdlib/LinearAlgebra/)
    *   [Logging](../../stdlib/Logging/)
    *   [Markdown](../../stdlib/Markdown/)
    *   [Memory-mapped I/O](../../stdlib/Mmap/)
    *   [Network Options](../../stdlib/NetworkOptions/)
    *   [Pkg](../../stdlib/Pkg/)
    *   [Printf](../../stdlib/Printf/)
    *   [Profiling](../../stdlib/Profile/)
    *   [Random Numbers](../../stdlib/Random/)
    *   [The Julia REPL](../../stdlib/REPL/)
    *   [Serialization](../../stdlib/Serialization/)
    *   [SHA](../../stdlib/SHA/)
    *   [Shared Arrays](../../stdlib/SharedArrays/)
    *   [Sockets](../../stdlib/Sockets/)
    *   [Sparse Arrays](../../stdlib/SparseArrays/)
    *   [Statistics](../../stdlib/Statistics/)
    *   [StyledStrings](../../stdlib/StyledStrings/)
    *   [Tar](../../stdlib/Tar/)
    *   [TOML](../../stdlib/TOML/)
    *   [Unicode](../../stdlib/Unicode/)
    *   [Unit Testing](../../stdlib/Test/)
    *   [UUIDs](../../stdlib/UUIDs/)
*   Developer Documentation
    *   Documentation of Julia's Internals
        *   [Initialization of the Julia runtime](../../devdocs/init/)
        *   [Julia ASTs](../../devdocs/ast/)
        *   [More about types](../../devdocs/types/)
        *   [Memory layout of Julia Objects](../../devdocs/object/)
        *   [Eval of Julia code](../../devdocs/eval/)
        *   [Calling Conventions](../../devdocs/callconv/)
        *   [High-level Overview of the Native-Code Generation Process](../../devdocs/compiler/)
        *   [Julia Functions](../../devdocs/functions/)
        *   [Base.Cartesian](../../devdocs/cartesian/)
        *   [Talking to the compiler (the `:meta` mechanism)](../../devdocs/meta/)
        *   [SubArrays](../../devdocs/subarrays/)
        *   [isbits Union Optimizations](../../devdocs/isbitsunionarrays/)
        *   [System Image Building](../../devdocs/sysimg/)
        *   [Package Images](../../devdocs/pkgimg/)
        *   [Custom LLVM Passes](../../devdocs/llvm-passes/)
        *   [Working with LLVM](../../devdocs/llvm/)
        *   [printf() and stdio in the Julia runtime](../../devdocs/stdio/)
        *   [Bounds checking](../../devdocs/boundscheck/)
        *   [Proper maintenance and care of multi-threading locks](../../devdocs/locks/)
        *   [Arrays with custom indices](../../devdocs/offset-arrays/)
        *   [Module loading](../../devdocs/require/)
        *   [Inference](../../devdocs/inference/)
        *   [Julia SSA-form IR](../../devdocs/ssair/)
        *   [`EscapeAnalysis`](../../devdocs/EscapeAnalysis/)
        *   [Ahead of Time Compilation](../../devdocs/aot/)
        *   [Static analyzer annotations for GC correctness in C code](../../devdocs/gc-sa/)
        *   [Garbage Collection in Julia](../../devdocs/gc/)
        *   [JIT Design and Implementation](../../devdocs/jit/)
        *   [Core.Builtins](../../devdocs/builtins/)
        *   [Fixing precompilation hangs due to open tasks or IO](../../devdocs/precompile_hang/)
    *   Developing/debugging Julia's C code
        *   [Reporting and analyzing crashes (segfaults)](../../devdocs/backtraces/)
        *   [gdb debugging tips](../../devdocs/debuggingtips/)
        *   [Using Valgrind with Julia](../../devdocs/valgrind/)
        *   [External Profiler Support](../../devdocs/external_profilers/)
        *   [Sanitizer support](../../devdocs/sanitizers/)
        *   [Instrumenting Julia with DTrace, and bpftrace](../../devdocs/probes/)
    *   Building Julia
        *   [Building Julia (Detailed)](../../devdocs/build/build/)
        *   [Linux](../../devdocs/build/linux/)
        *   [macOS](../../devdocs/build/macos/)
        *   [Windows](../../devdocs/build/windows/)
        *   [FreeBSD](../../devdocs/build/freebsd/)
        *   [ARM (Linux)](../../devdocs/build/arm/)
        *   [RISC-V (Linux)](../../devdocs/build/riscv/)
        *   [Binary distributions](../../devdocs/build/distributing/)

Version

[](#)

*   Manual
*   Style Guide

*   Style Guide

[GitHub](https://github.com/JuliaLang/julia "View the repository on GitHub")[](https://github.com/JuliaLang/julia/blob/master/doc/src/manual/style-guide.md "Edit source on GitHub")[](# "Settings")[](javascript:; "Collapse all docstrings")

# [Style Guide](#Style-Guide)[](#Style-Guide "Permalink")

The following sections explain a few aspects of idiomatic Julia coding style. None of these rules are absolute; they are only suggestions to help familiarize you with the language and to help you choose among alternative designs.

## [Indentation](#Indentation)[](#Indentation "Permalink")

Use 4 spaces per indentation level.

## [Write functions, not just scripts](#Write-functions,-not-just-scripts)[](#Write-functions,-not-just-scripts "Permalink")

Writing code as a series of steps at the top level is a quick way to get started solving a problem, but you should try to divide a program into functions as soon as possible. Functions are more reusable and testable, and clarify what steps are being done and what their inputs and outputs are. Furthermore, code inside functions tends to run much faster than top level code, due to how Julia's compiler works.

It is also worth emphasizing that functions should take arguments, instead of operating directly on global variables (aside from constants like [`pi`](../../base/numbers/#Base.MathConstants.pi)).

## [Avoid writing overly-specific types](#Avoid-writing-overly-specific-types)[](#Avoid-writing-overly-specific-types "Permalink")

Code should be as generic as possible. Instead of writing:

```julia
Complex{Float64}(x)
```

it's better to use available generic functions:

```julia
complex(float(x))
```

The second version will convert `x` to an appropriate type, instead of always the same type.

This style point is especially relevant to function arguments. For example, don't declare an argument to be of type `Int` or [`Int32`](../../base/numbers/#Core.Int32) if it really could be any integer, expressed with the abstract type [`Integer`](../../base/numbers/#Core.Integer). In fact, in many cases you can omit the argument type altogether, unless it is needed to disambiguate from other method definitions, since a [`MethodError`](../../base/base/#Core.MethodError) will be thrown anyway if a type is passed that does not support any of the requisite operations. (This is known as [duck typing](https://en.wikipedia.org/wiki/Duck_typing).)

For example, consider the following definitions of a function `addone` that returns one plus its argument:

```julia
addone(x::Int) = x + 1                 # works only for Int
addone(x::Integer) = x + oneunit(x)    # any integer type
addone(x::Number) = x + oneunit(x)     # any numeric type
addone(x) = x + oneunit(x)             # any type supporting + and oneunit
```

The last definition of `addone` handles any type supporting [`oneunit`](../../base/numbers/#Base.oneunit) (which returns 1 in the same type as `x`, which avoids unwanted type promotion) and the [`+`](../../base/math/#Base.:+) function with those arguments. The key thing to realize is that there is _no performance penalty_ to defining _only_ the general `addone(x) = x + oneunit(x)`, because Julia will automatically compile specialized versions as needed. For example, the first time you call `addone(12)`, Julia will automatically compile a specialized `addone` function for `x::Int` arguments, with the call to `oneunit` replaced by its inlined value `1`. Therefore, the first three definitions of `addone` above are completely redundant with the fourth definition.

## [Handle excess argument diversity in the caller](#Handle-excess-argument-diversity-in-the-caller)[](#Handle-excess-argument-diversity-in-the-caller "Permalink")

Instead of:

```julia
function foo(x, y)
    x = Int(x); y = Int(y)
    ...
end
foo(x, y)
```

use:

```julia
function foo(x::Int, y::Int)
    ...
end
foo(Int(x), Int(y))
```

This is better style because `foo` does not really accept numbers of all types; it really needs `Int` s.

One issue here is that if a function inherently requires integers, it might be better to force the caller to decide how non-integers should be converted (e.g. floor or ceiling). Another issue is that declaring more specific types leaves more "space" for future method definitions.

## [Append `!` to names of functions that modify their arguments](#bang-convention)[](#bang-convention "Permalink")

Instead of:

```julia
function double(a::AbstractArray{<:Number})
    for i in eachindex(a)
        a[i] *= 2
    end
    return a
end
```

use:

```julia
function double!(a::AbstractArray{<:Number})
    for i in eachindex(a)
        a[i] *= 2
    end
    return a
end
```

Julia Base uses this convention throughout and contains examples of functions with both copying and modifying forms (e.g., [`sort`](../../base/sort/#Base.sort) and [`sort!`](../../base/sort/#Base.sort!)), and others which are just modifying (e.g., [`push!`](../../base/collections/#Base.push!), [`pop!`](../../base/collections/#Base.pop!), [`splice!`](../../base/collections/#Base.splice!)). It is typical for such functions to also return the modified array for convenience.

Functions related to IO or making use of random number generators (RNG) are notable exceptions: Since these functions almost invariably must mutate the IO or RNG, functions ending with `!` are used to signify a mutation _other_ than mutating the IO or advancing the RNG state. For example, `rand(x)` mutates the RNG, whereas `rand!(x)` mutates both the RNG and `x`; similarly, `read(io)` mutates `io`, whereas `read!(io, x)` mutates both arguments.

## [Avoid strange type `Union`s](#Avoid-strange-type-Unions)[](#Avoid-strange-type-Unions "Permalink")

Types such as `Union{Function,AbstractString}` are often a sign that some design could be cleaner.

## [Avoid elaborate container types](#Avoid-elaborate-container-types)[](#Avoid-elaborate-container-types "Permalink")

It is usually not much help to construct arrays like the following:

```julia
a = Vector{Union{Int,AbstractString,Tuple,Array}}(undef, n)
```

In this case `Vector{Any}(undef, n)` is better. It is also more helpful to the compiler to annotate specific uses (e.g. `a[i]::Int`) than to try to pack many alternatives into one type.

## [Prefer exported methods over direct field access](#Prefer-exported-methods-over-direct-field-access)[](#Prefer-exported-methods-over-direct-field-access "Permalink")

Idiomatic Julia code should generally treat a module's exported methods as the interface to its types. An object's fields are generally considered implementation details and user code should only access them directly if this is stated to be the API. This has several benefits:

*   Package developers are freer to change the implementation without breaking user code.
*   Methods can be passed to higher-order constructs like [`map`](../../base/collections/#Base.map) (e.g. `map(imag, zs)`) rather than `[z.im for z in zs]`).
*   Methods can be defined on abstract types.
*   Methods can describe a conceptual operation that can be shared across disparate types (e.g. `real(z)` works on Complex numbers or Quaternions).

Julia's dispatch system encourages this style because `play(x::MyType)` only defines the `play` method on that particular type, leaving other types to have their own implementation.

Similarly, non-exported functions are typically internal and subject to change, unless the documentations states otherwise. Names sometimes are given a `_` prefix (or suffix) to further suggest that something is "internal" or an implementation-detail, but it is not a rule.

Counter-examples to this rule include [`NamedTuple`](../../base/base/#Core.NamedTuple), [`RegexMatch`](../../base/strings/#Base.match), [`StatStruct`](../../base/file/#Base.stat).

## [Use naming conventions consistent with Julia `base/`](#Use-naming-conventions-consistent-with-Julia-base/)[](#Use-naming-conventions-consistent-with-Julia-base/ "Permalink")

*   modules and type names use capitalization and camel case: `module SparseArrays`, `struct UnitRange`.
*   functions are lowercase ([`maximum`](../../base/collections/#Base.maximum), [`convert`](../../base/base/#Base.convert)) and, when readable, with multiple words squashed together ([`isequal`](../../base/base/#Base.isequal), [`haskey`](../../base/collections/#Base.haskey)). When necessary, use underscores as word separators. Underscores are also used to indicate a combination of concepts ([`remotecall_fetch`](../../stdlib/Distributed/#Distributed.remotecall_fetch-Tuple{Any, Integer, Vararg{Any}}) as a more efficient implementation of `fetch(remotecall(...))`) or as modifiers.
*   functions mutating at least one of their arguments end in `!`.
*   conciseness is valued, but avoid abbreviation ([`indexin`](../../base/collections/#Base.indexin) rather than `indxin`) as it becomes difficult to remember whether and how particular words are abbreviated.

If a function name requires multiple words, consider whether it might represent more than one concept and might be better split into pieces.

## [Write functions with argument ordering similar to Julia Base](#Write-functions-with-argument-ordering-similar-to-Julia-Base)[](#Write-functions-with-argument-ordering-similar-to-Julia-Base "Permalink")

As a general rule, the Base library uses the following order of arguments to functions, as applicable:

1.  **Function argument**. Putting a function argument first permits the use of [`do`](../../base/base/#do) blocks for passing multiline anonymous functions.
    
2.  **I/O stream**. Specifying the `IO` object first permits passing the function to functions such as [`sprint`](../../base/io-network/#Base.sprint), e.g. `sprint(show, x)`.
    
3.  **Input being mutated**. For example, in [`fill!(x, v)`](../../base/arrays/#Base.fill!), `x` is the object being mutated and it appears before the value to be inserted into `x`.
    
4.  **Type**. Passing a type typically means that the output will have the given type. In [`parse(Int, "1")`](../../base/numbers/#Base.parse), the type comes before the string to parse. There are many such examples where the type appears first, but it's useful to note that in [`read(io, String)`](../../base/io-network/#Base.read), the `IO` argument appears before the type, which is in keeping with the order outlined here.
    
5.  **Input not being mutated**. In `fill!(x, v)`, `v` is _not_ being mutated and it comes after `x`.
    
6.  **Key**. For associative collections, this is the key of the key-value pair(s). For other indexed collections, this is the index.
    
7.  **Value**. For associative collections, this is the value of the key-value pair(s). In cases like [`fill!(x, v)`](../../base/arrays/#Base.fill!), this is `v`.
    
8.  **Everything else**. Any other arguments.
    
9.  **Varargs**. This refers to arguments that can be listed indefinitely at the end of a function call. For example, in `Matrix{T}(undef, dims)`, the dimensions can be given as a [`Tuple`](../../base/base/#Core.Tuple), e.g. `Matrix{T}(undef, (1,2))`, or as [`Vararg`](../../base/base/#Core.Vararg)s, e.g. `Matrix{T}(undef, 1, 2)`.
    
10.  **Keyword arguments**. In Julia keyword arguments have to come last anyway in function definitions; they're listed here for the sake of completeness.
     

The vast majority of functions will not take every kind of argument listed above; the numbers merely denote the precedence that should be used for any applicable arguments to a function.

There are of course a few exceptions. For example, in [`convert`](../../base/base/#Base.convert), the type should always come first. In [`setindex!`](../../base/collections/#Base.setindex!), the value comes before the indices so that the indices can be provided as varargs.

When designing APIs, adhering to this general order as much as possible is likely to give users of your functions a more consistent experience.

## [Don't overuse try-catch](#Don't-overuse-try-catch)[](#Don't-overuse-try-catch "Permalink")

It is better to avoid errors than to rely on catching them.

## [Don't parenthesize conditions](#Don't-parenthesize-conditions)[](#Don't-parenthesize-conditions "Permalink")

Julia doesn't require parens around conditions in `if` and `while`. Write:

```julia
if a == b
```

instead of:

```julia
if (a == b)
```

## [Don't overuse `...`](#Don't-overuse-...)[](#Don't-overuse-... "Permalink")

Splicing function arguments can be addictive. Instead of `[a..., b...]`, use simply `[a; b]`, which already concatenates arrays. [`collect(a)`](../../base/collections/#Base.collect-Tuple{Any}) is better than `[a...]`, but since `a` is already iterable it is often even better to leave it alone, and not convert it to an array.

## [Ensure constructors return an instance of their own type](#Ensure-constructors-return-an-instance-of-their-own-type)[](#Ensure-constructors-return-an-instance-of-their-own-type "Permalink")

When a method `T(x)` is called on a type `T`, it is generally expected to return a value of type T. Defining a [constructor](../constructors/#man-constructors) that returns an unexpected type can lead to confusing and unpredictable behavior:

```julia-repl
julia> struct Foo{T}
           x::T
       end

julia> Base.Float64(foo::Foo) = Foo(Float64(foo.x))  # Do not define methods like this

julia> Float64(Foo(3))  # Should return `Float64`
Foo{Float64}(3.0)

julia> Foo{Int}(x) = Foo{Float64}(x)  # Do not define methods like this

julia> Foo{Int}(3)  # Should return `Foo{Int}`
Foo{Float64}(3.0)
```

To maintain code clarity and ensure type consistency, always design constructors to return an instance of the type they are supposed to construct.

## [Don't use unnecessary static parameters](#Don't-use-unnecessary-static-parameters)[](#Don't-use-unnecessary-static-parameters "Permalink")

A function signature:

```julia
foo(x::T) where {T<:Real} = ...
```

should be written as:

```julia
foo(x::Real) = ...
```

instead, especially if `T` is not used in the function body. Even if `T` is used, it can be replaced with [`typeof(x)`](../../base/base/#Core.typeof) if convenient. There is no performance difference. Note that this is not a general caution against static parameters, just against uses where they are not needed.

Note also that container types, specifically may need type parameters in function calls. See the FAQ [Avoid fields with abstract containers](../performance-tips/#Avoid-fields-with-abstract-containers) for more information.

## [Avoid confusion about whether something is an instance or a type](#Avoid-confusion-about-whether-something-is-an-instance-or-a-type)[](#Avoid-confusion-about-whether-something-is-an-instance-or-a-type "Permalink")

Sets of definitions like the following are confusing:

```julia
foo(::Type{MyType}) = ...
foo(::MyType) = foo(MyType)
```

Decide whether the concept in question will be written as `MyType` or `MyType()`, and stick to it.

The preferred style is to use instances by default, and only add methods involving `Type{MyType}` later if they become necessary to solve some problems.

If a type is effectively an enumeration, it should be defined as a single (ideally immutable struct or primitive) type, with the enumeration values being instances of it. Constructors and conversions can check whether values are valid. This design is preferred over making the enumeration an abstract type, with the "values" as subtypes.

## [Don't overuse macros](#Don't-overuse-macros)[](#Don't-overuse-macros "Permalink")

Be aware of when a macro could really be a function instead.

Calling [`eval`](../../base/base/#eval) inside a macro is a particularly dangerous warning sign; it means the macro will only work when called at the top level. If such a macro is written as a function instead, it will naturally have access to the run-time values it needs.

## [Don't expose unsafe operations at the interface level](#Don't-expose-unsafe-operations-at-the-interface-level)[](#Don't-expose-unsafe-operations-at-the-interface-level "Permalink")

If you have a type that uses a native pointer:

```julia
mutable struct NativeType
    p::Ptr{UInt8}
    ...
end
```

don't write definitions like the following:

```julia
getindex(x::NativeType, i) = unsafe_load(x.p, i)
```

The problem is that users of this type can write `x[i]` without realizing that the operation is unsafe, and then be susceptible to memory bugs.

Such a function should either check the operation to ensure it is safe, or have `unsafe` somewhere in its name to alert callers.

## [Don't overload methods of base container types](#Don't-overload-methods-of-base-container-types)[](#Don't-overload-methods-of-base-container-types "Permalink")

It is possible to write definitions like the following:

```julia
show(io::IO, v::Vector{MyType}) = ...
```

This would provide custom showing of vectors with a specific new element type. While tempting, this should be avoided. The trouble is that users will expect a well-known type like `Vector()` to behave in a certain way, and overly customizing its behavior can make it harder to work with.

## [Avoid type piracy](#avoid-type-piracy)[](#avoid-type-piracy "Permalink")

"Type piracy" refers to the practice of extending or redefining methods in Base or other packages on types that you have not defined. In extreme cases, you can crash Julia (e.g. if your method extension or redefinition causes invalid input to be passed to a `ccall`). Type piracy can complicate reasoning about code, and may introduce incompatibilities that are hard to predict and diagnose.

As an example, suppose you wanted to define multiplication on symbols in a module:

```julia
module A
import Base.*
*(x::Symbol, y::Symbol) = Symbol(x,y)
end
```

The problem is that now any other module that uses `Base.*` will also see this definition. Since `Symbol` is defined in Base and is used by other modules, this can change the behavior of unrelated code unexpectedly. There are several alternatives here, including using a different function name, or wrapping the `Symbol`s in another type that you define.

Sometimes, coupled packages may engage in type piracy to separate features from definitions, especially when the packages were designed by collaborating authors, and when the definitions are reusable. For example, one package might provide some types useful for working with colors; another package could define methods for those types that enable conversions between color spaces. Another example might be a package that acts as a thin wrapper for some C code, which another package might then pirate to implement a higher-level, Julia-friendly API.

## [Be careful with type equality](#Be-careful-with-type-equality)[](#Be-careful-with-type-equality "Permalink")

You generally want to use [`isa`](../../base/base/#Core.isa) and [`<:`](../../base/base/#Core.:<:) for testing types, not `==`. Checking types for exact equality typically only makes sense when comparing to a known concrete type (e.g. `T == Float64`), or if you _really, really_ know what you're doing.

## [Don't write a trivial anonymous function `x->f(x)` for a named function `f`](#Don't-write-a-trivial-anonymous-function-x-f\(x\)-for-a-named-function-f)[](#Don't-write-a-trivial-anonymous-function-x-f\(x\)-for-a-named-function-f "Permalink")

Since higher-order functions are often called with anonymous functions, it is easy to conclude that this is desirable or even necessary. But any function can be passed directly, without being "wrapped" in an anonymous function. Instead of writing `map(x->f(x), a)`, write [`map(f, a)`](../../base/collections/#Base.map).

## [Avoid using floats for numeric literals in generic code when possible](#Avoid-using-floats-for-numeric-literals-in-generic-code-when-possible)[](#Avoid-using-floats-for-numeric-literals-in-generic-code-when-possible "Permalink")

If you write generic code which handles numbers, and which can be expected to run with many different numeric type arguments, try using literals of a numeric type that will affect the arguments as little as possible through promotion.

For example,

```julia-repl
julia> f(x) = 2.0 * x
f (generic function with 1 method)

julia> f(1//2)
1.0

julia> f(1/2)
1.0

julia> f(1)
2.0
```

while

```julia-repl
julia> g(x) = 2 * x
g (generic function with 1 method)

julia> g(1//2)
1//1

julia> g(1/2)
1.0

julia> g(1)
2
```

As you can see, the second version, where we used an `Int` literal, preserved the type of the input argument, while the first didn't. This is because e.g. `promote_type(Int, Float64) == Float64`, and promotion happens with the multiplication. Similarly, [`Rational`](../../base/numbers/#Base.Rational) literals are less type disruptive than [`Float64`](../../base/numbers/#Core.Float64) literals, but more disruptive than `Int`s:

```julia-repl
julia> h(x) = 2//1 * x
h (generic function with 1 method)

julia> h(1//2)
1//1

julia> h(1/2)
1.0

julia> h(1)
2//1
```

Thus, use `Int` literals when possible, with `Rational{Int}` for literal non-integer numbers, in order to make it easier to use your code.

[« Workflow Tips](../workflow-tips/)[Frequently Asked Questions »](../faq/)

Powered by [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) and the [Julia Programming Language](https://julialang.org/).

Settings

Theme

Automatic (OS)documenter-lightdocumenter-darkcatppuccin-lattecatppuccin-frappecatppuccin-macchiatocatppuccin-mocha

* * *

This document was generated with [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) version 1.17.0 on Thursday 9 April 2026. Using Julia version 1.12.6.