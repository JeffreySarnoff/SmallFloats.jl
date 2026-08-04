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
    # A single zero: the draft's datum set has no −0, so the sign is dropped here
    # rather than reaching a carrier that would keep it.
    sig == 0 && return _czero(C)
    _finite_datum(reptype(F), C, sig, e, neg)
end

# The finite datum, `±sig · 2^e`, built on the format's carrier.
#
# Dispatched on the REPRESENTATION rather than on the carrier or on a branch,
# because the split is exactly the representation seam (invariant 9): the bit
# assembly's licence is `|e + nb − 1| ≤ ~260`, and that bound is the K ≤ KSPLIT
# premise written arithmetically. `reptype` is the identity on a concrete
# format and the format→representation map on an abstract one, so the call
# below is correct for both without a second forwarder.
#
# The generic row is `ldexp`, which is where the extension actually bites: a
# B ≈ 1024 format's smallest datum is `2^(2−P−B)`, as low as `2^-1038`, a
# **Float64 subnormal**. Bit assembly there does not merely lose precision — it
# writes a biased exponent that has gone negative into the exponent field and
# produces an unrelated number. `ldexp` is defined on the whole range for every
# carrier, and `C(sig)` is exact for every carrier because `sig ≤ 2^16`.
@inline function _finite_datum(::Type{<:Code8}, ::Type{Float64}, sig::Int, e::Int, neg::Bool)
    # bit assembly (bitops plan K2): every K ≤ 8 datum exponent is deep inside
    # Float64's normal range, so no subnormal/overflow case exists and ldexp's
    # generality is pure overhead. Retained under this signature only.
    nb = 64 - leading_zeros(UInt64(sig))
    mant = (UInt64(sig) << (53 - nb)) & ((UInt64(1) << 52) - 1)
    bits = (UInt64(e + nb - 1 + 1023) << 52) | mant
    neg && (bits |= UInt64(1) << 63)
    reinterpret(Float64, bits)
end
@inline function _finite_datum(::Type{<:Code16}, ::Type{C}, sig::Int, e::Int, neg::Bool) where {C}
    d = ldexp(C(sig), e)
    neg ? -d : d
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
    "the Float32 decode table exists only for K ≤ $KSPLIT; wide formats reach " *
    "Float32 through `Float32(decode(v))`, gated on `datumsexact(Float32, F)`"))

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
    decode(v::Binary) -> datumcarrier(typeof(v))

ωDecode (draft §4.7.2). **Exact for every datum of every format**, which is why
the return type is the format's carrier rather than a fixed one: `Float64` where
the bias allows (432 of the 504 formats), `Float128` to B = 8192, `BigFloat`
above. `Float64(v)` is the way to ask for a `Float64` and accept the rounding.

Two implementations, selected by `decodepolicy` — dispatch on the
representation, not a branch on K (invariant 9, §2 R-F):

  * `TableDecode` (K ≤ `KSPLIT`): a `2^K`-entry constant-tuple lookup (bitops
    plan K2), generated once from `_decode_compute`, so the two are correct by
    construction and asserted equivalent exhaustively; constant inputs fold.
  * `ComputeDecode` (K > `KSPLIT`): `_decode_compute` directly. No table —
    65 536 entries is what invariant 10 exists to forbid.
"""
@inline decode(v::Binary) = _decode(decodepolicy(typeof(v)), v)
@inline _decode(::TableDecode, v::Binary) =
    @inbounds _decode_table(typeof(v))[Int(codepoint(v)) + 1]
@inline _decode(::ComputeDecode, v::Binary) = _decode_compute(v)

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
# NaN (at the −0 slot for signed formats / top code for unsigned) sorts BELOW
# −Inf and every finite — draft §4.12.1. The first implementation put it ABOVE
# +Inf, from an interpretation made while the draft text was unavailable; that
# was a defect, corrected 2026-08-01, and the golden oracle was recaptured with
# the correction (the sec_lattice/sec_order digests pin order semantics, so the
# pre-correction capture pinned the wrong ones).

"""
    nan_order_key(F)

The order key reserved for the single NaN — **below** every finite key and ±Inf.

Key `0` is free by construction: every datum's key is at least 1 (`order_key`
adds 1 above the code arithmetic on both the signed and unsigned paths), so
`zero(orderkeytype(F))` sits strictly under the whole datum lattice without
shifting any other key.

Per format, not a constant, and the key type is `orderkeytype(F)` rather than
`UInt16`. The reason is arithmetic, not tidiness: a format has `2^K` code points
mapping to keys `1 … 2^K`, so `UInt16` runs out at exactly K = 16 — `UInt16(c) +
UInt16(1)` for `c = 0xffff` wraps **silently to 0**, which is now precisely the
NaN key: the largest datum would compare below NaN and below every other datum.
`orderkeytype` returns `UInt32` for `Code16`, which has room for keys `1 … 2^16`
above the NaN sentinel.

*(§4 Stage 4 item 3, pulled forward into Stage 3 — §11 M16. The rest of Stage 3
makes wide formats fail loudly; a wraparound in the total order is the one
K ≥ 9 defect that would have been silent, so it is closed here rather than
carried for a commit.)*
"""
@inline nan_order_key(::Type{F}) where {F<:Binary} = zero(orderkeytype(F))
@inline nan_order_key(v::Binary) = nan_order_key(typeof(v))

@inline function order_key(v::Binary{K,P,SGN,EXT}) where {K,P,SGN,EXT}
    T = typeof(v)
    O = orderkeytype(T)
    c = codepoint(v)
    isnan(v) && return nan_order_key(T)          # 0 — below every datum key
    SGN || return O(c) + O(1)
    sm = signmask(T)
    neg = c >= sm
    neg ? O(sm) - O(c - sm) : O(sm) + O(c) + O(1)
end

"""TotalOrder⟨fx,fy⟩ (draft §4.12.1): x ≤ y in the total order (single NaN
smallest — NaN ≼ −Inf ≼ … ≼ +Inf). Same-format comparisons run on the integer
order key (bitops plan K1) — proven equivalent to the decode order exhaustively
over all pairs; cross-format keys are not comparable, so mixed formats keep the
decode path."""
@inline TotalOrder(x::T, y::T) where {T<:Binary} = order_key(x) <= order_key(y)
function TotalOrder(x::Binary, y::Binary)
    dx, dy = decode(x), decode(y)
    isnan(dx) && return true                     # NaN ≼ everything, itself included
    isnan(dy) && return false                    # non-NaN ⋠ NaN
    dx <= dy
end
# Key strict-< gives the TotalOrder-derived isless, including NaN-FIRST
# (key(NaN) = 0): isless(NaN, x) = true for every non-NaN x, isless(NaN, NaN) =
# false. `sort` therefore places NaN at the FRONT — the draft's order, and a
# deliberate divergence from Base's float convention of NaN-last.
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
    # Keys are 0..2^K with 0 the NaN sentinel (below every datum), so the key
    # space maps to buckets by a plain shift — the previous typemax sentinel
    # needed a fold onto a synthetic top bucket; the bottom sentinel does not.
    nk = (1 << K) + 1                              # buckets: NaN, then keys 1..2^K
    counts = zeros(Int, nk)
    key2code = Vector{U}(undef, nk)
    bucket(k) = Int(k) + 1                         # key 0 (NaN) → bucket 1
    for c in zero(U):U((1 << K) - 1)               # key ↔ code inversion, 2^K iterations
        key2code[bucket(order_key(rawvalue(T, c)))] = c
    end
    @inbounds for i in lo:hi
        counts[bucket(order_key(v[i]))] += 1
    end
    rev = o isa Base.Order.ReverseOrdering
    i = rev ? hi : lo
    step = rev ? -1 : 1
    @inbounds for b in 1:nk
        c = counts[b]
        c == 0 && continue
        # ascending buckets emitted backward under Reverse puts the NaN bucket
        # (smallest key) at the BACK — exactly Base's rev=true isless semantics
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
    # Predicates, not comparisons against `Float64` literals: at rung 3 `d` is a
    # `Dyadic`, which has no promotion to `Float64` by design (§11 M44). The
    # rewritten form is also the cheaper one at every rung — a bit test rather
    # than a compare — and `signbit` is exact on the sign of a nonzero, which is
    # all this branch ever wanted from `d > 0`.
    _isposinf(d) && return ClassPosInf
    _isneginf(d) && return ClassNegInf
    iszero(v) && return ClassZero
    sub = issubnormal_3109(v)
    if !signbit(d)
        return sub ? ClassPosSubnormal : ClassPosNormal
    else
        return sub ? ClassNegSubnormal : ClassNegNormal
    end
end

# ---- NextGreaterThan / NextLessThan (draft §4.16): ±1 steps on magnitude code points

# The stepping edges are named once here: both directions run off the lattice
# into NaN, and both pivot on the extremal finite code.
@inline _nan_datum(::Type{T}) where {T<:Binary} = rawvalue(T, nan_code(T))
# `_minfinite_code` / `_maxfinite_code` now live in formats.jl beside the other
# special code points, and `MinFiniteOf`/`MaxFiniteOf` are built FROM them. They
# were defined here as `codepoint(MaxFiniteOf(T))` — construct then destructure —
# which every consumer of the code paid for. Defining them again here would be a
# method overwrite, which is a precompilation *error* (see show.jl:121).

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
"""NextGreaterThan(v) (draft §4.16): the least datum greater than `v` in the total
order — one step up the code lattice, with NaN → NaN and MaxFinite/+Inf → NaN at
the top. `Base.nextfloat` on `Binary` is this operation."""
Base.nextfloat(v::Binary) = NextGreaterThan(v)

"""NextLessThan(v) (draft §4.16): the greatest datum less than `v` in the total
order — one step down the code lattice, with NaN → NaN and MinFinite/−Inf → NaN at
the bottom. `Base.prevfloat` on `Binary` is this operation."""
Base.prevfloat(v::Binary) = NextLessThan(v)
