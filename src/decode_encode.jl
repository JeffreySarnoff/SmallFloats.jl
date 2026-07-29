# ===== decode_encode.jl — ωDecode / ωEncode / ordering keys / Next ops (design §3)

# Computational ωDecode: the ground truth from which the lookup table below is
# generated. Kept private; `decode` (the exported entry) reads the table.
# The primary form takes the format TYPE and a code point, not a value: the
# table builders have only a code in hand, and a carrier-generic decode has to
# name the carrier, which is a property of the type (implementextensions §2 R-F).
# The value form is kept because it is the one the suite and the docs call.
@inline _decode_compute(v::Binary) = _decode_compute(typeof(v), codepoint(v))

@inline function _decode_compute(::Type{F}, c) where {K,P,SGN,EXT,F<:Binary{K,P,SGN,EXT}}
    C = datumcarrier(F)                        # Float64 today; Float128/Dyadic later
    # Special code points come from formats.jl rather than being re-derived here:
    # one definition of the layout, not two. (Unsigned formats put NaN and the
    # −Inf slot at the same code, so NaN must be tested first — it is.)
    #
    # The specials go through the carrier-generic constants rather than bare
    # `NaN`/`Inf` literals: those are `Float64`, so on a wider carrier they are a
    # silent narrow-then-widen, and on `Dyadic` they are simply wrong-typed.
    c == nan_code(F) && return _cnan(C)
    if EXT
        c == posinf_code(F) && return _cinf(C)
        SGN && c == neginf_code(F) && return _cninf(C)
    end
    hidden = 1 << (P - 1)                      # implicit-bit weight of the integer significand
    tmask = _cu(F, hidden - 1)                 # trailing-significand mask
    neg = SGN && (c >= signmask(F))
    m = neg ? c - signmask(F) : c
    tsig = m & tmask
    Eb = Int(m >> (P - 1))
    B = expbias(F)
    sig = Eb == 0 ? Int(tsig) : Int(tsig) + hidden
    e = (Eb == 0 ? 1 : Eb) - B + (1 - P)
    # bit assembly (bitops plan K2): every datum exponent is deep inside Float64's
    # normal range (|e + nb − 1| ≤ ~260), so no subnormal/overflow cases exist and
    # ldexp's generality is pure overhead.
    sig == 0 && return 0.0
    nb = 64 - leading_zeros(UInt64(sig))
    mant = (UInt64(sig) << (53 - nb)) & ((UInt64(1) << 52) - 1)
    bits = (UInt64(e + nb - 1 + 1023) << 52) | mant
    neg && (bits |= UInt64(1) << 63)
    return reinterpret(Float64, bits)
end

# Bounded to `Code8` BY SIGNATURE, not by a check inside: a `Code16` request must
# be a `MethodError` at the call site rather than a 65 536-element constant tuple
# the compiler dutifully materializes. That is invariant 10 (§3.5) stated where
# it can be enforced — the tuple length is `2^K`, and `2^KSPLIT = 256` is the
# whole justification for the shape. `decodepolicy` selects it; the two agree by
# construction because both are keyed on the representation.
@generated function _decode_table(::Type{F}) where {K,P,S,E,F<:Code8{K,P,S,E}}
    t = ntuple(i -> _decode_compute(F, UInt8(i - 1)), 1 << K)
    :($t)
end
# The `Code16` half of the guard is a method that THROWS, not an absent method.
# Absence was the first spelling and it is wrong for a reason worth recording:
# the abstract forwarder below infers to `Union{Type{Code8{…}}, Type{Code16{…}}}`
# when the format parameters are not statically known, so a missing `Code16`
# method turns a deliberate refusal into a static-analysis defect — JET reports
# it as an unreachable-method bug against the whole package, and the only way to
# keep the suite green would be a filter, which the verification doctrine says
# must be backed by a concrete-call gate proving the path is clean. It is not
# clean; it is refused. Saying so in a method is both honest and total.
@noinline _decode_table(::Type{<:Code16}) = throw(ArgumentError(
    "a 2^K-entry constant decode table exists only for K ≤ $KSPLIT — at K = 16 it " *
    "would be 65 536 entries, which invariant 10 forbids outright. Wide formats " *
    "decode by computation; see `decodepolicy`"))
@noinline _decode_table32(::Type{<:Code16}) = throw(ArgumentError(
    "the Float32 decode table exists only for K ≤ $KSPLIT; the Float32 surface for " *
    "wide formats is gated on the datum-exactness trait in Stage 4"))

# The abstract-format forwarder every representation-keyed function needs (§11
# M14): `_decode_table(Binary{3,1,true,true})` is how the gate suite asks a
# *format* for its table, and without this it dies with a `MethodError` rather
# than answering. `reptype` is the one map from format to representation.
@inline _decode_table(::Type{Binary{K,P,S,E}}) where {K,P,S,E} =
    _decode_table(reptype(Binary{K,P,S,E}))

# Float32 twin of _decode_table: same ground truth, narrowed once. Narrowing is
# exact for every K ≤ 8 datum (worst cases 2^126 and the Float32-subnormal
# 2^-127, both from Binary8p1u; asserted exhaustively in the suite).
@generated function _decode_table32(::Type{F}) where {K,P,S,E,F<:Code8{K,P,S,E}}
    t = ntuple(i -> Float32(_decode_compute(F, UInt8(i - 1))), 1 << K)
    :($t)
end

"""
    decode(v::Binary) -> Float64

ωDecode (draft §4.7.2). Float64 is the universal exact carrier for K ≤ 8 datums
(≤ 8-bit significands, |exponent| ≲ 2^7); exactness is asserted by exhaustive test.

Implemented as a constant-tuple lookup (bitops plan K2): the per-format table is
generated once from `_decode_compute` above, so the two are correct by
construction and asserted equivalent exhaustively; constant inputs still fold.

Selected by `decodepolicy`, which is dispatch on the representation and not a
branch on K (invariant 9, §2 R-F).
"""
@inline decode(v::Binary) = _decode(decodepolicy(typeof(v)), v)
@inline _decode(::TableDecode, v::Binary) =
    @inbounds _decode_table(typeof(v))[Int(codepoint(v)) + 1]
# Stage 3 leaves this rung of the ladder empty ON PURPOSE. `_decode_compute`'s
# tail is still the Float64 bit assembly whose justifying comment ("|e + nb − 1|
# ≤ ~260") is exactly the K ≤ 8 premise: at B ≈ 1024 the minimum datum is
# 2^(2−P−B), a Float64 subnormal, and the assembly produces garbage rather than
# an error. A wrong answer is worse than no answer, so until Stage 4 replaces
# the tail with the carrier-generic `ldexp` path, ask and be told no.
@noinline _decode(::ComputeDecode, v::Binary) = throw(ArgumentError(
    "decode of a K ≥ $(KSPLIT + 1) format ($(formatname(typeof(v)))) needs the " *
    "carrier-generic finite path, which arrives in Stage 4 of the K ≤ 16 extension"))

"""
    encode(T, sign, S, Q) -> UInt8   (private; design §3.3)

ωEncode from canonical integer form: value = sign · S · 2^Q, with S ∈ 0:2^P
(S == 2^P is the next-binade carry, draft §4.7.4 NOTE 4). Precondition: the value
is in the datum set of `T` (guaranteed by RoundToPrecision ∘ Saturate).
"""
@inline function encode(::Type{F}, sign::Int, S::Int64, Q::Int64) where {K,P,SGN,EXT,F<:Binary{K,P,SGN,EXT}}
    S == 0 && return _cu(F, 0)
    hidden = Int64(1) << (P - 1)               # implicit-bit weight; also the first normal S
    if S == (Int64(1) << P)                    # carry into next binade
        S = hidden; Q += 1
    end
    local c::codeunit_type(F)
    if S < hidden                              # subnormal: Q must equal 2-B-P
        c = _cu(F, S)
    else
        Eb = Int(Q) + P - 1 + expbias(F)       # biased exponent field
        c = _cu(F, (S & (hidden - 1)) + (Int64(Eb) << (P - 1)))
    end
    (SGN && sign < 0) && (c |= signmask(F))
    c
end

# ---- Total-order key (design §3.1): sign–magnitude → monotone unsigned key.
# NaN (at the −0 slot for signed formats / top code for unsigned) sorts ABOVE +Inf
# [interpretation; draft §4.12.1 text unavailable in upload — see checkpoint].

"""
    nan_order_key(F)

The order key reserved for the single NaN — above every finite key and ±Inf.

Per format, not a constant, and the key type is `orderkeytype(F)` rather than
`UInt16`. The reason is arithmetic, not tidiness: a format has `2^K` code points
mapping to keys `1 … 2^K`, so `UInt16` runs out at exactly K = 16 — `UInt16(c) +
UInt16(1)` for `c = 0xffff` wraps **silently to 0**, putting the largest datum
below the smallest. `orderkeytype` returns `UInt32` for `Code16`, which has room
for the keys and for a sentinel strictly above all of them.

*(§4 Stage 4 item 3, pulled forward into Stage 3 — §11 M16. The rest of Stage 3
makes wide formats fail loudly; a wraparound in the total order is the one
K ≥ 9 defect that would have been silent, so it is closed here rather than
carried for a commit.)*
"""
@inline nan_order_key(::Type{F}) where {F<:Binary} = typemax(orderkeytype(F))
@inline nan_order_key(v::Binary) = nan_order_key(typeof(v))

@inline function order_key(v::Binary{K,P,SGN,EXT}) where {K,P,SGN,EXT}
    T = typeof(v)
    O = orderkeytype(T)
    c = codepoint(v)
    isnan(v) && return typemax(O)
    SGN || return O(c) + O(1)
    sm = signmask(T)
    neg = c >= sm
    neg ? O(sm) - O(c - sm) : O(sm) + O(c) + O(1)
end

"""TotalOrder⟨fx,fy⟩ (draft §4.12.1): x ≤ y in the total order (single NaN largest).
Same-format comparisons run on the integer order key (bitops plan K1) — proven
equivalent to the decode order exhaustively over all pairs; cross-format keys are
not comparable, so mixed formats keep the decode path."""
@inline TotalOrder(x::T, y::T) where {T<:Binary} = order_key(x) <= order_key(y)
function TotalOrder(x::Binary, y::Binary)
    dx, dy = decode(x), decode(y)
    isnan(dx) && return isnan(dy) ? true : false
    isnan(dy) && return true
    dx <= dy
end
# key strict-< reproduces the old TotalOrder-derived isless exactly, including
# NaN-last (key(NaN) = typemax): isless(x, NaN) = true, isless(NaN, NaN) = false.
Base.isless(x::T, y::T) where {T<:Binary} = order_key(x) < order_key(y)

# Numeric comparisons (NaN unordered; keys are order-isomorphic to datums off NaN)
"""Numeric comparison is defined only when neither operand is NaN — every
`==`/`<`/`<=` below returns `false` otherwise, per IEEE unorderedness."""
@inline _comparable(x::Binary, y::Binary) = !(isnan(x) | isnan(y))

Base.:(==)(x::T, y::T) where {T<:Binary} = _comparable(x, y) && order_key(x) == order_key(y)
Base.:(<)(x::T, y::T) where {T<:Binary}  = _comparable(x, y) && order_key(x) < order_key(y)
Base.:(<=)(x::T, y::T) where {T<:Binary} = _comparable(x, y) && order_key(x) <= order_key(y)

# ---- counting sort over the key space (bitops plan K1): ≤ 2^K + 1 distinct keys,
# equal keys ⇒ identical code points, so stability is moot; O(n) one-pass counts.
struct CodeCountingSort <: Base.Sort.Algorithm end
Base.Sort.defalg(::AbstractArray{<:Binary}) = CodeCountingSort()
# any ordering we don't specialize falls back to the stock algorithm
Base.sort!(v::AbstractVector{T}, lo::Int, hi::Int, ::CodeCountingSort,
           o::Base.Order.Ordering) where {T<:Binary} =
    sort!(v, lo, hi, Base.Sort.DEFAULT_UNSTABLE, o)
function Base.sort!(v::AbstractVector{T}, lo::Int, hi::Int, ::CodeCountingSort,
                    o::Union{Base.Order.ForwardOrdering,
                             Base.Order.ReverseOrdering{Base.Order.ForwardOrdering}}) where {T<:Binary}
    K = bitwidth(T)
    U = codeunit_type(T)
    # Counting sort pays 2^K of setup before it looks at the data. At K ≤ 8 that
    # is 257 buckets and never worth a test; at K = 16 it is 65 537 buckets and
    # ~512 KiB for a vector that may hold three elements. The gate is a
    # generalization, not a behaviour change — at K ≤ 8 it fires only for inputs
    # so short that either algorithm is instant, and both algorithms produce the
    # same permutation because equal keys mean identical code points.
    # (§4 Stage 4 item 4, pulled forward with the key retyping — §11 M16.)
    n = hi - lo + 1
    n < (1 << K) && return sort!(v, lo, hi, Base.Sort.DEFAULT_UNSTABLE, o)
    nk = (1 << K) + 1                              # keys 1..2^K plus NaN sentinel bucket
    counts = zeros(Int, nk + 1)
    key2code = Vector{U}(undef, nk + 1)
    nan_key = nan_order_key(T)
    bucket(k) = k == nan_key ? nk + 1 : Int(k)     # sentinel folds to the top bucket
    for c in zero(U):U((1 << K) - 1)               # key ↔ code inversion, 2^K iterations
        key2code[bucket(order_key(rawvalue(T, c)))] = c
    end
    @inbounds for i in lo:hi
        counts[bucket(order_key(v[i]))] += 1
    end
    rev = o isa Base.Order.ReverseOrdering
    i = rev ? hi : lo
    step = rev ? -1 : 1
    @inbounds for b in 1:nk + 1
        c = counts[b]
        c == 0 && continue
        # ascending buckets emitted backward under Reverse puts the NaN bucket
        # (largest key) at the front — exactly Base's rev=true isless semantics
        val = rawvalue(T, key2code[b])
        for _ in 1:c
            v[i] = val
            i += step
        end
    end
    v
end

# ---- Class (draft §4.13.1)
"Eight-way datum classification returned by `Class` (draft §4.13.1)."
@enum FPClass::UInt8 ClassNaN ClassNegInf ClassNegNormal ClassNegSubnormal ClassZero ClassPosSubnormal ClassPosNormal ClassPosInf
"""Class(v) -> FPClass (draft §4.13.1): classify `v` as NaN, ±Inf, ±normal,
±subnormal, or zero."""
function Class(v::Binary)
    isnan(v) && return ClassNaN
    d = decode(v)
    d == Inf && return ClassPosInf
    d == -Inf && return ClassNegInf
    iszero(v) && return ClassZero
    sub = issubnormal_3109(v)
    if d > 0
        return sub ? ClassPosSubnormal : ClassPosNormal
    else
        return sub ? ClassNegSubnormal : ClassNegNormal
    end
end

# ---- NextGreaterThan / NextLessThan (draft §4.16): ±1 steps on magnitude code points

# The stepping edges are named once here: both directions run off the lattice
# into NaN, and both pivot on the extremal finite code.
@inline _nan_datum(::Type{T}) where {T<:Binary} = rawvalue(T, nan_code(T))
@inline _minfinite_code(::Type{T}) where {T<:Binary} = codepoint(MinFiniteOf(T))
@inline _maxfinite_code(::Type{T}) where {T<:Binary} = codepoint(MaxFiniteOf(T))

"""NextGreaterThan(v) (draft §4.16): the least datum greater than `v` in the total
order — one step up the code lattice, with NaN → NaN and MaxFinite/+Inf → NaN at
the top. `Base.nextfloat` on `Binary` is this operation."""
function NextGreaterThan(v::T) where {K,P,SGN,EXT,T<:Binary{K,P,SGN,EXT}}
    isnan(v) && return v
    c = codepoint(v)
    if EXT
        c == posinf_code(T) && return _nan_datum(T)                    # Inf → NaN
        SGN && c == neginf_code(T) && return MinFiniteOf(T)            # -Inf → MinFinite
    elseif c == _maxfinite_code(T)
        return _nan_datum(T)                                           # Finite: MaxFinite → NaN
    end
    if SGN && signbit(v)
        c == (signmask(T) | 0x01) && return zero(T)                    # SmallestNegative → 0
        return rawvalue(T, c - 0x01)
    end
    rawvalue(T, c + 0x01)
end
"""NextLessThan(v) (draft §4.16): the greatest datum less than `v` in the total
order — one step down the code lattice, with NaN → NaN and MinFinite/−Inf → NaN at
the bottom. `Base.prevfloat` on `Binary` is this operation."""
function NextLessThan(v::T) where {K,P,SGN,EXT,T<:Binary{K,P,SGN,EXT}}
    isnan(v) && return v
    c = codepoint(v)
    if !SGN
        c == 0x00 && return _nan_datum(T)
        EXT && c == posinf_code(T) && return MaxFiniteOf(T)
        (!EXT && c == _minfinite_code(T)) && return _nan_datum(T)
        return rawvalue(T, c - 0x01)
    end
    if EXT
        c == neginf_code(T) && return _nan_datum(T)                     # -Inf → NaN
        c == _minfinite_code(T) && return rawvalue(T, neginf_code(T))
        c == posinf_code(T) && return MaxFiniteOf(T)
    else
        c == _minfinite_code(T) && return _nan_datum(T)
    end
    c == 0x00 && return rawvalue(T, signmask(T) | 0x01)                 # 0 → SmallestNegative
    signbit(v) ? rawvalue(T, c + 0x01) : rawvalue(T, c - 0x01)
end
Base.nextfloat(v::Binary) = NextGreaterThan(v)
Base.prevfloat(v::Binary) = NextLessThan(v)
