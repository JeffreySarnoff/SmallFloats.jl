const SHOW_STYLE_KEY = :binary_show_style
const DEFAULT_SHOW_STYLE = Ref{Symbol}(:value)

const VALID_SHOW_STYLES = (:value, :codepoint, :datum, :typed)

function set_show_style!(style::Symbol)
    style in VALID_SHOW_STYLES ||
        throw(ArgumentError("invalid Binary show style: $style"))
    DEFAULT_SHOW_STYLE[] = style
    return style
end

# `:value` is the default: a `Binary` prints as the number it denotes, which is
# what generic Julia code and ordinary output want.
#
# The DOCUMENTATION renders in `:typed` instead, because `1.625 ≡ 0x45` is its
# central teaching point — see "Choose how values print" in the Quickstart. That
# convention is established by the doc-example harness, not by this default, so
# the two cannot silently disagree: `test/docs_examples.jl` sets `:typed` per
# file exactly as it restores the other process-global session defaults.
set_show_style!(:value)

"""
    get_show_style()      -> Symbol
    get_show_style(io::IO) -> Symbol

The style `show` will use: the process default, or — given an `IO` — the style
that `io` resolves to, which is its `:binary_show_style` property when set and
the process default otherwise.

The no-argument form previously read an undefined `io` and threw
`UndefVarError` on every call.
"""
get_show_style() = DEFAULT_SHOW_STYLE[]
get_show_style(io::IO) = get(io, SHOW_STYLE_KEY, DEFAULT_SHOW_STYLE[])

@inline function binary_show_style(io::IO)
    style = get(io, SHOW_STYLE_KEY, DEFAULT_SHOW_STYLE[])
    style in VALID_SHOW_STYLES ||
        throw(ArgumentError("invalid Binary show style: $style"))
    return style
end

function show_all(io::IO, v::Binary)
    T = typeof(v)
    d = decode(v)

    print(io, formatname(T), "(")
    isnan(d) ? print(io, "NaN") : print(io, _shortdatum(T, d))
    print(
        io,
        " ≡ 0x",
        string(
            codepoint(v);
            base = 16,
            pad = 2 * sizeof(codeunit_type(T)),
        ),
        ")",
    )
end

function show_datum(io::IO, v::Binary)
    T = typeof(v)
    d = decode(v)

    print(io, "(")
    isnan(d) ? print(io, "NaN") : print(io, _shortdatum(T, d))
    print(
        io,
        " ≡ 0x",
        string(
            codepoint(v);
            base = 16,
            pad = 2 * sizeof(codeunit_type(T)),
        ),
        ")",
    )
end

function show_value(io::IO, v::Binary)
    show(io, decode(v))
end

function show_codepoint(io::IO, v::Binary)
    show(io, codepoint(v))
end

# Then use one dispatcher for the three show methods:

function show_binary(io::IO, v::Binary)
    style = binary_show_style(io)

    if style === :value
        show_value(io, v)
    elseif style === :codepoint
        show_codepoint(io, v)
    elseif style === :datum
        show_datum(io, v)
    elseif style === :typed
        show_all(io, v)
    else
        error("unreachable")
    end

    return nothing
end

Base.show(io::IO, v::Binary) =
    show_binary(io, v)

Base.show(io::IO, ::MIME"text/plain", v::Binary) =
    show_binary(io, v)    

# Print fully-instantiated formats by their draft name; 
#   anything else (UnionAlls, TypeVar-parameterized types
#   met during stacktrace printing) defers to Base —
# a parametric `::Type{Binary{K,P,S,E}}` method here can be
#   handed unbound static parameters by the printing machinery
#   and crash (found by test).

# `_fully_instantiated` lives in formats.jl; defining it again here is a method
# overwrite, which is an error during precompilation rather than a warning.

function Base.show(io::IO, T::Type{<:Binary})
    if _fully_instantiated(T)
        print(io, formatname(T))
        # The format and its representation must not print identically:
        # the difference between them is exactly what an error about 
        # `similar`, `eltype` or a failed `===` needs to communicate.
        isabstracttype(T) && print(io, "{format}")
    else # this case was found in testing
        invoke(show, Tuple{IO,Type}, io, T)
    end
end

