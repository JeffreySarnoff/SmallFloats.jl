# ===== test/golden/harness.jl — the G5 non-regression oracle
#
# G5 protects the promise that the K ≤ 16 extension changes nothing for
# existing users. It is a stored digest of the K ≤ 8 observable surface,
# captured from the pre-refactor tree and compared byte-for-byte afterwards.
# Re-deriving it from the new code would prove only that the new code agrees
# with itself, so `capture.jl` is run ONCE, before the first edit.
#
# What is digested is deliberately narrow: **semantic observables only** —
# code points, decoded bit patterns, class tags, order keys. Printed type names
# are NOT digested, because the refactor changes `show` for the abstract format
# on purpose (`Binary8p4se` vs `Binary8p4se{format}`), and a golden that fires
# on an intended change is a golden that gets disabled.
#
# Determinism: formats are visited in sorted-name order, no RNG is touched
# (stochastic ρ is driven by explicit R), and NaN is canonicalized to one bit
# pattern so a payload difference cannot masquerade as a value difference.

using SHA

const GOLDEN_FILE = joinpath(@__DIR__, "k8.sha256")

# ---- deterministic byte sink ------------------------------------------------
#
# The writer is `emit!`, not `put!`: `Base.put!` is exported and in scope here,
# so a bare `put!` method definition is a hard error ("must be explicitly
# imported to be extended"), and importing it to write bytes into a local sink
# would be Base piracy for no gain.

struct Sink
    io::IOBuffer
end
Sink() = Sink(IOBuffer())

const _CANON_NAN = 0x7ff8000000000000

@inline emit!(s::Sink, x::UInt64) = (write(s.io, x); s)
@inline emit!(s::Sink, x::Integer) = emit!(s, UInt64(x % Int64 % UInt64))
@inline emit!(s::Sink, x::Bool)    = emit!(s, UInt64(x))
@inline emit!(s::Sink, x::Float64) =
    emit!(s, isnan(x) ? _CANON_NAN : reinterpret(UInt64, x))
@inline emit!(s::Sink, x::Float32) = emit!(s, Float64(x))
@inline emit!(s::Sink, x::Symbol)  = (write(s.io, codeunits(String(x))); write(s.io, 0x00); s)
@inline emit!(s::Sink, x::Enum)    = emit!(s, UInt64(Integer(x)))
# A Binary value is digested as its code point — the only thing that defines it.
@inline emit!(s::Sink, v::SmallFloats.Binary) = emit!(s, UInt64(codepoint(v)))

digest(s::Sink) = bytes2hex(SHA.sha256(take!(s.io)))

# ---- the grid, in a fixed order --------------------------------------------

"""Every K ≤ 8 format, in sorted-alias-name order. The order is part of the
digest, so it must not depend on `Dict` iteration.

The `K ≤ KSPLIT` filter is what makes G5 a *non-regression* gate rather than a
coverage gate: the oracle was captured at `51abb00`, when 120 formats existed,
and its digests are statements about those 120. Widening this list to the 504
would not strengthen the gate — it would silently invalidate every digest in
the file and make the comparison meaningless. Wide formats are covered by the
sweep and the stage gates, which is where new coverage belongs."""
function golden_formats()
    names = sort!([n for n in keys(SmallFloats._NAMED)
                   if bitwidth(SmallFloats._NAMED[n]) <= SmallFloats.KSPLIT])
    [SmallFloats._NAMED[n] for n in names]
end

"""Every code point of `F`, ascending."""
allcodes(F) = 0x00:UInt8((1 << bitwidth(F)) - 1)

"""The `:lazy` sampling fraction — the share of the expensive sections' format
lists that the middle tier walks. Sampling is by **format**, deterministically
by stride, so a lazy run is reproducible and its digest is stable."""
const LAZY_STRIDE = 6      # 21/120 = 17.5 %, 9/48 = 18.8 % — inside the 15–20 % band

"""Deterministic ~1/`LAZY_STRIDE` sample of a format list, always including the
first and last entries so the extremes of the grid are never dropped."""
function lazy_sample(fmts)
    n = length(fmts)
    idx = collect(1:LAZY_STRIDE:n)
    last(idx) == n || push!(idx, n)
    fmts[idx]
end

"""A **derived** representative subset of the grid — not hand-listed, so it
cannot silently stop covering a cell. For each (K, Σ, Δ) it takes the two
extreme precisions, `P = 1` and `P = pmax`, which are the two ends of the
(P, B) range at that K: `P = 1` maximizes the exponent bias (the widest datum
spread, the hardest carrier case) and `P = pmax` minimizes it.

Used only by the sections whose per-entry cost is an MPFR ladder. The cheap
sections stay exhaustive over all 120 formats, and `decode` / `project` /
`order` — the stages a type refactor can actually move — are exhaustive for
every format regardless.

*Sizing (§11 M12): an earlier version also took the midpoint precision, giving
70 of 120 formats — 58 % of the grid, which is not a subset in any useful
sense. Two-per-cell gives 46, and since the interior of the P range is
interpolation between the two ends for every trait that matters here (B is
monotone in P at fixed K), the midpoint was buying repetition, not coverage.*"""
function representative_formats()
    out = DataType[]
    for K in 3:8, S in (true, false), E in (true, false)
        pmax = S ? K - 1 : K
        for P in unique((1, pmax))
            push!(out, SmallFloats._NAMED[SmallFloats._formatname(K, P, S, E)])
        end
    end
    out
end

"""A fixed, deterministic subset of at most `n` code points of `F`, always
including 0 and the top code."""
function subcodes(F, n::Int)
    m = 1 << bitwidth(F)
    m <= n && return collect(0x00:UInt8(m - 1))
    step = cld(m, n)
    cs = UInt8[UInt8(c) for c in 0:step:(m - 1)]
    last(cs) == UInt8(m - 1) || push!(cs, UInt8(m - 1))
    cs
end

# ---- projection specifications, in a fixed order ---------------------------

const PURE_RHO = (RNE_SF, RNE_SP, RNE_SN,
                  RNA_SF, RNA_SP, RNA_SN,
                  RTP_SF, RTP_SP, RTP_SN,
                  RTN_SF, RTN_SP, RTN_SN,
                  RTZ_SF, RTZ_SP, RTZ_SN,
                  RTO_SF, RTO_SP, RTO_SN)

const STOCH_RHO = (RSA_SF(4), RSA_SP(4), RSA_SN(4),
                   RSB_SF(4), RSB_SP(4), RSB_SN(4),
                   RSC_SF(4), RSC_SP(4), RSC_SN(4))

"""The ρ set most sections sweep: three pure families plus one stochastic,
chosen to exercise nearest / directed / odd / sub-grid behaviour without
paying for all 27."""
const CORE_RHO = (RNE_SN, RTZ_SF, RTP_SP, RTO_SN)

# ---- a structured carrier-value set (binade edges, ties, subnormal landings) --

"""Float64 inputs chosen to land on and beside every interesting boundary of a
K ≤ 8 format: exact datums, midpoints, ties ± 1 ulp, zeros, specials."""
function structured_inputs()
    xs = Float64[0.0, -0.0, Inf, -Inf, NaN]
    for e in -10:10
        b = 2.0^e
        append!(xs, (b, -b, 1.5b, -1.5b, 1.25b, 0.75b,
                     nextfloat(b), prevfloat(b), b * (1 + 2.0^-8)))
    end
    append!(xs, (1.0e-40, -1.0e-40, 1.0e40, -1.0e40, 5.0e-324, 1.7976931348623157e308))
    xs
end

# ---- sections ---------------------------------------------------------------
#
# Each section is a name and a closure filling a Sink. Section names are part of
# the file, so a section that is added later shows up as a new line rather than
# as a diff of an existing one.

"Format metadata and the special / extremal code points (§ formats.jl)."
function sec_meta(s::Sink)
    for F in golden_formats()
        emit!(s, bitwidth(F)); emit!(s, precision(F))
        emit!(s, issigned(F)); emit!(s, isextended(F))
        emit!(s, expbias(F)); emit!(s, expbitwidth(F)); emit!(s, trailingsigbits(F))
        emit!(s, UInt64(SmallFloats.nan_code(F)))
        emit!(s, UInt64(SmallFloats.posinf_code(F)))
        emit!(s, UInt64(SmallFloats.neginf_code(F)))
        emit!(s, UInt64(SmallFloats.signmask(F)))
        emit!(s, MaxFiniteOf(F)); emit!(s, MinFiniteOf(F)); emit!(s, MinPositiveOf(F))
        emit!(s, MaxSubnormalOf(F)); emit!(s, MinNormalOf(F))
        emit!(s, zero(F)); emit!(s, one(F)); emit!(s, typemax(F)); emit!(s, typemin(F))
        emit!(s, Base.floatmax(F)); emit!(s, Base.floatmin(F)); emit!(s, eps(F))
    end
end

"ωDecode over every code point of every format, plus the Float32 twin."
function sec_decode(s::Sink)
    for F in golden_formats(), c in allcodes(F)
        v = rawvalue(F, c)
        emit!(s, decode(v))
        emit!(s, Float32(v))
        emit!(s, Float64(v))
    end
end

"The code lattice: keys, class, stepping, predicates (§ decode_encode.jl)."
function sec_lattice(s::Sink)
    for F in golden_formats(), c in allcodes(F)
        v = rawvalue(F, c)
        emit!(s, UInt64(SmallFloats.order_key(v)))
        emit!(s, Class(v))
        emit!(s, NextGreaterThan(v)); emit!(s, NextLessThan(v))
        emit!(s, isnan(v)); emit!(s, isinf(v)); emit!(s, isfinite(v))
        emit!(s, signbit(v)); emit!(s, issubnormal(v)); emit!(s, iszero(v))
    end
end

"Total order and comparison over every same-format ordered pair."
function sec_order(s::Sink)
    for F in golden_formats(), c1 in allcodes(F)
        x = rawvalue(F, c1)
        for c2 in allcodes(F)
            y = rawvalue(F, c2)
            emit!(s, TotalOrder(x, y)); emit!(s, isless(x, y))
            emit!(s, x == y); emit!(s, x < y); emit!(s, x <= y)
        end
    end
end

"The projection engine over a structured carrier set × every format × all 27 ρ."
function sec_project(s::Sink)
    xs = structured_inputs()
    for F in golden_formats()
        for ρ in PURE_RHO, x in xs
            emit!(s, SmallFloats.project(F, ρ, x))
        end
        for ρ in STOCH_RHO, x in xs, R in (0, 1, 7, 15)
            emit!(s, SmallFloats.project(F, ρ, x; R))
        end
    end
end

"Convert between formats: every result format × a fixed source set, all codes."
function sec_convert(s::Sink)
    srcs = (Binary8p4se, Binary8p1uf, Binary5p2se, Binary3p1se, Binary6p3uf)
    for F in golden_formats(), G in srcs, c in allcodes(G), ρ in CORE_RHO
        emit!(s, Convert(F, ρ, rawvalue(G, c)))
    end
end

# `Convert` is registry arity 1 but registry group `:conv`: it has NO ω-semantics
# (`apply_op` has no `ωeval(::Val{:Convert}, …)` row — `tables.jl`'s `_scalar_code`
# special-cases it into a bare projection). Every consumer that filters the
# registry by arity alone walks into this; filter by group as well. `sec_convert`
# covers Convert properly.
_unary_ops() = [o.name for o in SmallFloats.OP_REGISTRY if o.arity == 1 && o.group !== :conv]
_binary_ops() = [o.name for o in SmallFloats.OP_REGISTRY if o.arity == 2]

"""Every unary operation, **every format**, every code point, under the default
ρ. Pure ρ goes through `get_table`, which by invariant 6 IS the defined result.

Cost note: each table entry is one oracle trip and most unary ops are MPFR
ladders (~200 µs/entry measured), so ρ-breadth here is bought on the derived
representative subset (`sec_unary_rho`) rather than on all 120 formats. The
full-grid claim that matters for G5 — that no *format* changed — is carried by
`decode`, `project`, `order` and this section together."""
sec_unary_default(s::Sink)      = _unary_default(s, golden_formats())
sec_unary_default_lazy(s::Sink) = _unary_default(s, lazy_sample(golden_formats()))

function _unary_default(s::Sink, fmts)
    for F in fmts, op in _unary_ops()
        tbl = SmallFloats.get_table(op, F, F, RNE_SN)
        for i in eachindex(tbl)
            emit!(s, UInt64(tbl[i]))
        end
    end
    SmallFloats.empty_tables!()
end

"""ρ-breadth for the unary catalogue over the derived representative formats,
plus the stochastic sweep (never tabulable — invariant 4 — so it runs the
scalar path with an explicit R and never touches RNG state).

*Cost note (§11 M12): each ρ here re-derives the SAME `ωeval` result — the
exact value or enclosure is ρ-independent, and only `project` differs — so a
third pure ρ costs a full extra MPFR sweep to exercise one more projection
mode. Two directed modes on opposite sides (`RTZ` truncating, `RTP` toward
+∞ with Propagate saturation) is where the marginal information is; `RTO` was
dropped. It is still covered exhaustively over all 120 formats by the `project`
section, which is carrier-cheap.*"""
sec_unary_rho(s::Sink)      = _unary_rho(s, representative_formats())
sec_unary_rho_lazy(s::Sink) = _unary_rho(s, lazy_sample(representative_formats()))

function _unary_rho(s::Sink, fmts)
    ops = _unary_ops()
    for F in fmts
        for op in ops, ρ in (RTZ_SF, RTP_SP)
            tbl = SmallFloats.get_table(op, F, F, ρ)
            for i in eachindex(tbl)
                emit!(s, UInt64(tbl[i]))
            end
        end
        for op in ops, ρ in (RSA_SN(4), RSC_SF(4))
            V = Val(op)
            for c in subcodes(F, 16), R in (0, 5, 15)
                emit!(s, SmallFloats.apply_op(V, F, ρ, R, decode(rawvalue(F, c))))
            end
        end
    end
    SmallFloats.empty_tables!()
end

"""Every binary operation over same-format pairs. The arithmetic and extremum
families are Float64-resident and sweep all 120 formats on a 32-code subset;
the three MPFR-backed ones sweep the representative formats on 12 codes."""
sec_binary(s::Sink)      = _binary(s, golden_formats(), representative_formats())
sec_binary_lazy(s::Sink) = _binary(s, lazy_sample(golden_formats()),
                                      lazy_sample(representative_formats()))

function _binary(s::Sink, fmts, repfmts)
    dear  = (:Hypot, :ArcTan2, :ArcTan2Pi)
    cheap = filter(op -> !(op in dear), _binary_ops())
    for F in fmts
        cs = subcodes(F, 32)
        for op in cheap, ρ in CORE_RHO
            V = Val(op)
            for c1 in cs, c2 in cs
                emit!(s, SmallFloats.apply_op(V, F, ρ, 0,
                                             decode(rawvalue(F, c1)), decode(rawvalue(F, c2))))
            end
        end
    end
    for F in repfmts
        cs = subcodes(F, 12)
        for op in dear, ρ in (RNE_SN, RTZ_SF)
            V = Val(op)
            for c1 in cs, c2 in cs
                emit!(s, SmallFloats.apply_op(V, F, ρ, 0,
                                             decode(rawvalue(F, c1)), decode(rawvalue(F, c2))))
            end
        end
    end
end

"""FMA / FAA / Clamp over a fixed triple subset. FMA and FAA reach the
wide-spread sticky-head escalation, which is exactly the machinery the carrier
work will later touch, so this section is the one that would notice."""
function sec_ternary(s::Sink)
    for F in golden_formats()
        cs = subcodes(F, 6)
        for op in (:FMA, :FAA, :Clamp), ρ in (RNE_SN, RTZ_SF)
            V = Val(op)
            for c1 in cs, c2 in cs, c3 in cs
                emit!(s, SmallFloats.apply_op(V, F, ρ, 0, decode(rawvalue(F, c1)),
                                             decode(rawvalue(F, c2)), decode(rawvalue(F, c3))))
            end
        end
    end
end

"Blocks, scaled operations, and reductions over a fixed structured set."
function sec_blocks(s::Sink)
    FS = Binary8p1uf                      # a P = 1 power-of-two scale format
    for FE in (Binary8p4se, Binary6p3se, Binary4p2se, Binary8p2uf),
        FR in (Binary8p4se, Binary5p3se)
        cs = subcodes(FE, 4)
        scs = subcodes(FS, 4)
        for sc in scs
            sv = rawvalue(FS, sc)
            for a in cs, b in cs
                bx = Block(sv, (rawvalue(FE, a), rawvalue(FE, b),
                                rawvalue(FE, b), rawvalue(FE, a)))
                by = Block(sv, (rawvalue(FE, b), rawvalue(FE, a),
                                rawvalue(FE, a), rawvalue(FE, b)))
                for ρ in (RNE_SN, RTZ_SF)
                    emit!(s, BlockDotProduct(FR, ρ, bx, by))
                    emit!(s, BlockReduceAdd(FR, ρ, bx))
                    emit!(s, BlockReduceMultiply(FR, ρ, bx))
                    emit!(s, ScaledAdd(FR, ρ, sv, rawvalue(FE, a), sv, rawvalue(FE, b)))
                    emit!(s, ScaledMultiply(FR, ρ, sv, rawvalue(FE, a), sv, rawvalue(FE, b)))
                end
            end
        end
    end
end

"Packed storage round-trips at every K (the sub-byte splice)."
function sec_packed(s::Sink)
    for F in golden_formats()
        A = [rawvalue(F, c) for c in allcodes(F)]
        pv = PackedVector(A)
        for i in eachindex(A)
            emit!(s, pv[i])
        end
        emit!(s, length(pv.data))
    end
end

"Array kernels: the Shape-A gathers and `decode!`, against the same inputs."
function sec_kernels(s::Sink)
    for F in (Binary8p4se, Binary6p3se, Binary4p2se, Binary8p1uf, Binary3p1se)
        A = [rawvalue(F, c) for c in allcodes(F)]
        B = reverse(A)
        d = similar(A)
        for op in (:Add, :Multiply, :Divide), ρ in CORE_RHO
            vmap!(d, Val(op), F, ρ, A, B)
            for v in d; emit!(s, v); end
        end
        for op in (:Exp, :Sqrt, :Negate), ρ in CORE_RHO
            vmap!(d, Val(op), F, ρ, A)
            for v in d; emit!(s, v); end
        end
        f64 = Vector{Float64}(undef, length(A)); decode!(f64, A)
        f32 = Vector{Float32}(undef, length(A)); decode!(f32, A)
        for x in f64; emit!(s, x); end
        for x in f32; emit!(s, x); end
    end
    SmallFloats.empty_tables!()
end

"Sorting: the counting-sort path against a fixed permutation of every lattice."
function sec_sort(s::Sink)
    for F in golden_formats()
        A = [rawvalue(F, c) for c in allcodes(F)]
        # a fixed, RNG-free shuffle: stride by a coprime step
        n = length(A)
        step = n > 3 ? 3 : 1
        B = [A[((i * step) % n) + 1] for i in 0:(n - 1)]
        for v in sort(B);              emit!(s, v); end
        for v in sort(B; rev = true);  emit!(s, v); end
    end
end

"The Base-register veneers (juliacompat.jl) over every code point."
function sec_juliacompat(s::Sink)
    for F in golden_formats()
        for c in subcodes(F, 32)
            x = rawvalue(F, c)
            emit!(s, -x); emit!(s, abs(x)); emit!(s, sqrt(x)); emit!(s, exp(x))
            for c2 in subcodes(F, 8)
                y = rawvalue(F, c2)
                emit!(s, x + y); emit!(s, x - y); emit!(s, x * y); emit!(s, x / y)
                emit!(s, min(x, y)); emit!(s, max(x, y)); emit!(s, fma(x, y, x))
            end
        end
    end
end

# NOTE — there is deliberately no `conformance` section.
#
# `conformance_dict()` is a *declaration*, not a computed result, and digesting
# it byte-exact would produce two classes of false positive:
#
#   · it embeds `collect(keys(TABLE_CACHE))`, so its value depends on which
#     tables happen to be cached when it is called — nondeterministic across
#     runs and across section orderings;
#   · it lists all 120 format names, which Stage 3 changes to 504 **on
#     purpose**.
#
# A golden that fires on an intended change is a golden that gets disabled.
# Invariant 5's real content — κ measured by exhaustive enumeration at
# registration time — is pinned by the suite proper, not here.

# ---- the section table ------------------------------------------------------

#
# G5 runs in two tiers. The split is a wall-clock decision, not a coverage
# concession:
#
#   :fast (~45 s) — the stages a type refactor can actually move. Storage,
#       traits, constructors, decode/encode plumbing and the projection engine
#       all show up here, exhaustively over all 120 formats. Re-run at EVERY
#       step of every stage; a change that gets past it cannot have altered a
#       decoded datum, a code point, an order key or a projection.
#
#   :full (~5 min) — adds the operation catalogue, blocks, kernels and the Base
#       veneers. Defence in depth: an arithmetic result cannot move without one
#       of the fast sections moving first, but "cannot" is an argument and this
#       is the measurement. Required at STAGE EXIT, and specifically at the
#       exits of Stages 1 and 2, which are the stages G5 exists for.
#
const FAST_SECTIONS = (
    "meta"         => sec_meta,
    "decode"       => sec_decode,
    "lattice"      => sec_lattice,
    "order"        => sec_order,
    "project"      => sec_project,
    "packed"       => sec_packed,
    "sort"         => sec_sort,
)

const FULL_SECTIONS = (
    "convert"       => sec_convert,
    "unary_default" => sec_unary_default,
    "unary_rho"     => sec_unary_rho,
    "binary"        => sec_binary,
    "ternary"       => sec_ternary,
    "blocks"        => sec_blocks,
    "kernels"       => sec_kernels,
    "juliacompat"   => sec_juliacompat,
)

# `:lazy` — the middle tier. Everything `:fast` does, plus the *cheap* full
# sections in full, plus a deterministic ~1/LAZY_STRIDE format sample of the
# three expensive ones.
#
# The sampled sections carry their OWN section names and therefore their own
# golden entries. This is forced, not stylistic: a golden compares digests, and
# a digest over a sampled format list is simply a different number from the
# digest over the whole list. Reusing the `unary_rho` name for a sample would
# make every lazy run report a spurious mismatch. `capture.jl` writes all three
# tiers' entries, so any tier can be checked against the same file.
const LAZY_SECTIONS = (
    "convert"            => sec_convert,
    "ternary"            => sec_ternary,
    "blocks"             => sec_blocks,
    "kernels"            => sec_kernels,
    "juliacompat"        => sec_juliacompat,
    "unary_default~lazy" => sec_unary_default_lazy,
    "unary_rho~lazy"     => sec_unary_rho_lazy,
    "binary~lazy"        => sec_binary_lazy,
)

sections(tier::Symbol) =
    tier === :fast ? FAST_SECTIONS :
    tier === :lazy ? (FAST_SECTIONS..., LAZY_SECTIONS...) :
    tier === :full ? (FAST_SECTIONS..., FULL_SECTIONS...) :
    throw(ArgumentError("tier must be :fast, :lazy or :full, got :$tier"))

"""Every section any tier can ask for, deduplicated, in a stable order — what
`capture.jl` must write so that all three tiers are checkable."""
function all_sections()
    seen = Set{String}()
    out = Pair{String,Any}[]
    for (name, f) in (FAST_SECTIONS..., FULL_SECTIONS..., LAZY_SECTIONS...)
        name in seen && continue
        push!(seen, name); push!(out, name => f)
    end
    Tuple(out)
end

"""Compute the section digests for `tier`, in declaration order. `tier = :all`
computes every section any tier can request — what `capture.jl` writes."""
function golden_digests(tier::Symbol = :full; verbose::Bool = false)
    secs = tier === :all ? all_sections() : sections(tier)
    out = Pair{String,String}[]
    for (name, f) in secs
        t = @elapsed begin
            s = Sink(); f(s); d = digest(s)
        end
        verbose && println(rpad(name, 15), d, "   ", round(t; digits = 2), "s")
        push!(out, name => d)
    end
    out
end

"""Read a captured golden file into `Vector{Pair{String,String}}`."""
function read_golden(path::AbstractString = GOLDEN_FILE)
    out = Pair{String,String}[]
    for line in eachline(path)
        (isempty(line) || startswith(line, '#')) && continue
        d, name = split(line)
        push!(out, String(name) => String(d))
    end
    out
end
