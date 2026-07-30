# ===== test/gates_g10.jl — G10: surface totality at every rung
#
# *The gate whose absence let six defects through Stage 7.*
#
# Every other gate compares two answers. G1–G4, G6, G7 and G9 all ask "is the
# result right?", and each is sharper than this file for the path it covers. But
# a differential gate is silent about a path that never returns an answer at all,
# and it is silent about a path that never runs because no test calls it. Both
# happened, repeatedly, in the same way:
#
#   * `Class` compared a decoded datum against `Inf` — a `Float64` literal, which
#     needs a promotion `Dyadic` deliberately does not have. Threw at rung 3.
#   * `_reduce_add_datum` did the same with `any(==(Inf), X)`. Threw at rung 3.
#   * `_bp_element` and `_encl_div_scale` annotated the scale `::Float64`.
#     `MethodError` for every one of the 72 formats above rung 1.
#   * The generated `Scaled*` surface asserted `::Float64` on the scale product —
#     `blockdecode`'s Stage 6 defect, in a second location nobody looked at.
#   * `BlockReduceMultiply` and `BlockDotProduct` chose a `Float128` accumulator
#     from a *significand* filter, at a rung selected by *exponent* range. They
#     did not throw; they returned `Inf`, which is worse.
#   * `Base.:+` on `Dyadic` was the engine's partial kernel, so summing a decoded
#     vector threw on any pair outside a 94-binade window.
#
# Not one of these is subtle. Every one survived a green suite, because the suite
# enumerates *values* exhaustively and *entry points* by habit. This file
# enumerates the entry points instead: every registry operation, every Base
# veneer, every block and scaled surface, every array verb — over every format
# above rung 1, which is 72 of 504 and therefore affordable to take exhaustively
# rather than by sample (verification doctrine: where enumeration is affordable
# it is mandatory).
#
# What it asserts is deliberately weak — that the call *returns*, and that where
# a result type is declared it holds. A gate this shallow is worth having only
# because it is this broad: it is a smoke test with complete coverage of the
# public surface, and the six defects above are exactly what that catches and
# what a deep gate on a narrow path does not.
#
# ---- what is enumerated, and what is sampled.
#
# The *entry-point* axis is exhaustive and always: every operation in
# `OP_REGISTRY`, on all three surfaces, plus the veneers and the array verbs. It
# is the axis the defects lived on and it is the cheap one.
#
# The *format* axis costs ≈ 1.8 s per format — almost all of it specialization,
# since `Binary{K,P,S,E}` is a distinct type per format and every operation
# recompiles for it. 504 formats is two hours, so this is one of the places the
# verification doctrine's "and where it is not [affordable], the output says
# 'sampled' in so many words" applies. Two tiers, selected by
# `ENV["SMALLFLOATS_G10"]`, and the `@info` line at the end names the tier:
#
#   `rep`  (default, ≈ 1 m 45 s) — all 8 rung-3 formats, one representative of
#          each realized `_class` at rung 2, and eight rung-1 controls.
#          Exhaustive over the equivalence classes dispatch can distinguish,
#          which is the property under test: nothing here is a function of K or
#          P except through the carrier, the code unit, and the `P == 1` block
#          path.
#   `full` (≈ 6 min) — every one of the 72 formats above rung 1, plus the
#          controls. The stage-exit and release tier, and the one that would
#          catch a defect that really is per-format rather than per-class.
#
# The BLOCK surface is enumerated by *shape*, not by format, at both tiers, and
# that is exhaustive rather than sampled: `blockdecode`'s carrier is
# `rung(Val(:Multiply), FS, FE)` and nothing else, so the realized
# (rung FS, rung FE) pairs plus the P = 1 scale path cover every method dispatch
# can select. Adding formats within a pair re-runs the same code.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: _NAMED, OP_REGISTRY, opinfo, rung, joinhead, carriertype,
                   _rungindex, rungindex, codeunit_type, bitwidth, rawvalue,
                   codepoint, expbias, blockdecode, HeadF64, HeadF128, HeadExact,
                   Binary, CarrierValue, datumcarrier

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

# ---- the format partition, taken from the package rather than restated.
const _ALLFMT = sort!(collect(keys(_NAMED)))
_fmt(nm) = _NAMED[nm]::Type{<:Binary}   # the registry, not the export surface
const _BY_RUNG = Dict(r => [nm for nm in _ALLFMT if _rungindex(_fmt(nm)) == r] for r in 1:3)

# Rung 1 is 432 formats and is covered exhaustively elsewhere (G5 at K ≤ 8,
# wide_ops.jl above it), so it enters here only as a control that the shared
# code paths did not regress — the same probe, on a spread of eight.
const _R1_CONTROL = [:Binary8p4se, :Binary8p1uf, :Binary6p3se, :Binary3p2se,
                     :Binary16p6se, :Binary16p8se, :Binary9p4se, :Binary12p7se]

const _G10_TIER = lowercase(get(ENV, "SMALLFLOATS_G10", "rep"))
_G10_TIER in ("rep", "full") ||
    error("SMALLFLOATS_G10 must be \"rep\" or \"full\", got $(repr(_G10_TIER))")

"""The equivalence class a format occupies for the purposes of this file: what
dispatch can actually distinguish. Two formats in the same class select the same
method at every site the gate touches, so probing both re-runs one path.

Three axes, and deliberately not a fourth. The rung picks the carrier, the code
unit picks the storage and the decode policy, and `P == 1` picks the second
`blockdecode` method. The `se`/`sf`/`ue`/`uf` kind is NOT here: it changes which
code points exist and what they mean, which is what G5 and G8 measure
exhaustively, but every method this file reaches is selected without consulting
it."""
_class(nm) = (T = _fmt(nm); (_rungindex(T), precision(T) == 1, codeunit_type(T)))

"""One representative per realized class, taken as the FIRST in sorted order so
the choice is stable across runs and reproducible from the name alone."""
function _representatives(nms)
    seen = Set(); out = Symbol[]
    for nm in nms
        c = _class(nm)
        c in seen && continue
        push!(seen, c); push!(out, nm)
    end
    out
end

# Rung 3 enters whole at both tiers: there are only eight of it, it is the
# carrier this stage introduced, and eight formats is affordable by any reading.
const _PROBED = _G10_TIER == "full" ?
    unique(vcat(_R1_CONTROL, _BY_RUNG[2], _BY_RUNG[3])) :
    unique(vcat(_R1_CONTROL, _representatives(_BY_RUNG[2]), _BY_RUNG[3]))

"""Eight code points per format: both ends of the lattice, both signs of the
midpoint, and the specials, taken as raw code points so no format is skipped for
lacking a particular value."""
function _probes(::Type{T}) where {T<:Binary}
    U = codeunit_type(T); n = 1 << bitwidth(T)
    cs = unique(UInt64[0, 1, 2, n ÷ 4, n ÷ 2, n ÷ 2 + 1, n - 2, n - 1])
    [rawvalue(T, U(c)) for c in cs if c < n]
end

"""Run `thunk`, returning `nothing` on success or a short failure line. The point
is to collect ALL failures for a format rather than stopping at the first, so one
red assertion names the whole class."""
function _try(label, thunk)
    try
        thunk()
        nothing
    catch err
        string(label, ": ", first(sprint(showerror, err), 120))
    end
end

@testset "G10 — surface totality at every rung" begin

    # ---- the partition is complete and non-empty where the lattice says it is.
    @test sum(length, values(_BY_RUNG)) == length(_ALLFMT)
    @test length(_ALLFMT) == 504
    @test length(_BY_RUNG[1]) == 432
    @test length(_BY_RUNG[2]) == 64
    @test length(_BY_RUNG[3]) == 8
    # every probed format's declared carrier is the one its rung names
    for nm in _PROBED
        T = _fmt(nm)
        @test (nm, datumcarrier(T)) == (nm, carriertype(rung(T)))
    end

    # ---- scalar surface: every registry operation, at every probed format.
    for nm in _PROBED
        T = _fmt(nm); vs = _probes(T)
        bad = String[]
        for o in OP_REGISTRY
            f = getfield(SmallFloats, o.name); ar = o.arity
            r = _try(o.name, () -> begin
                for x in vs[1:min(end, 4)], y in vs[1:min(end, 4)]
                    args = ar == 1 ? (x,) : ar == 2 ? (x, y) : (x, y, vs[end])
                    res = f(T, RNE_SatFinite, args...)
                    res isa T || error("returned $(typeof(res)), not $T")
                end
            end)
            r === nothing || push!(bad, r)
        end
        @test (nm, bad) == (nm, String[])
    end

    # ---- Base veneers and package predicates, which is where the `== Inf`
    # comparisons against `Float64` literals lived.
    for nm in _PROBED
        T = _fmt(nm); vs = _probes(T)
        bad = String[]
        for (lbl, f) in ((:Class, Class), (:NextGreaterThan, NextGreaterThan),
                         (:NextLessThan, NextLessThan),
                         (:isnan, isnan), (:isinf, isinf), (:isfinite, isfinite),
                         (:iszero, iszero), (:signbit, signbit), (:abs, abs),
                         (:sign, sign), (:float, float), (:Float64, Float64),
                         (:Float32, Float32), (:Float16, Float16),
                         (:BigFloat, BigFloat), (:show, v -> sprint(show, v)),
                         (:decode, decode), (:codepoint, codepoint))
            r = _try(lbl, () -> for x in vs; f(x); end)
            r === nothing || push!(bad, r)
        end
        for (lbl, f) in ((:TotalOrder, TotalOrder), (:lt, <), (:le, <=), (:eq, ==),
                         (:isequal, isequal), (:isless, isless),
                         (:add, +), (:sub, -), (:mul, *), (:div, /),
                         (:max, max), (:min, min))
            r = _try(lbl, () -> for x in vs[1:min(end, 4)], y in vs[1:min(end, 4)]; f(x, y); end)
            r === nothing || push!(bad, r)
        end
        @test (nm, bad) == (nm, String[])
    end

    # ---- array verbs. `sum` over decoded values is the one that found
    # `Base.:+`'s partiality on `Dyadic`, and it is the most ordinary thing a
    # caller can do with a vector of small floats.
    for nm in _PROBED
        T = _fmt(nm); vs = _probes(T)
        A = T[v for v in vs if !isnan(v)]
        bad = String[]
        for (lbl, f) in ((:sort, sort), (:maximum, maximum), (:minimum, minimum),
                         (:extrema, extrema), (:sum_decoded, a -> sum(decode.(a))),
                         (:broadcast_add, a -> a .+ a),
                         (:vmap, a -> Add.(T, Ref(RNE_SatFinite), a, a)))
            r = _try(lbl, () -> f(A))
            r === nothing || push!(bad, r)
        end
        @test (nm, bad) == (nm, String[])
    end

    # ---- block and scaled surface, enumerated by SHAPE.
    #
    # `blockdecode`'s carrier is `rung(Val(:Multiply), FS, FE)` and depends on the
    # two formats through nothing but that join, so the shapes below — every
    # realized (rung FS, rung FE) pair, in both orders, plus the P = 1 scale path
    # that has its own `blockdecode` method — cover every method dispatch can
    # select on this surface. That is exhaustive, not sampled: a fourth rung-2
    # scale format re-runs the third one's code.
    #
    # Both orders matter and were separately broken. A wide scale against narrow
    # lanes is what killed `_bp_element` (the scale is the divisor); narrow scale
    # against wide lanes is what killed the `Scaled*` `::Float64` assertion (the
    # product is the operand).
    SHAPES = ((Binary8p4se,  Binary8p4se),      # 1/1, both K ≤ 8
              (Binary16p6se, Binary8p4se),      # 1/1 across the code-unit seam
              (Binary8p4se,  Binary16p6se),
              (Binary16p5se, Binary8p4se),      # 2/1 — wide scale, narrow lanes
              (Binary8p4se,  Binary16p5se),     # 1/2 — narrow scale, wide lanes
              (Binary16p5se, Binary16p4se),     # 2/2
              (Binary16p1uf, Binary8p4se),      # 3/1, P = 1 scale (the MX shape)
              (Binary8p4se,  Binary16p1uf),     # 1/3
              (Binary16p1uf, Binary16p5se),     # 3/2
              (Binary16p1sf, Binary16p1uf),     # 3/3, both P = 1
              (Binary8p1uf,  Binary8p4se))      # 1/1, P = 1 scale (E8M0, Annex F)
    seenheads = Set()
    for (S, E) in SHAPES
        tag = "$(nameof(S))/$(nameof(E))"
        bad = String[]
        b1 = Block(S(1.0), (E(1.5), E(0.25)))
        b2 = Block(S(-1.0), (E(0.25), E(1.5)))
        h = rung(Val(:Multiply), S, E); C = carriertype(h)
        push!(seenheads, (rungindex(h), precision(S) == 1))
        for (lbl, th) in (("blockdecode", () -> begin
                               X = blockdecode(b1)
                               all(x -> x isa C, X) ||
                                   error("lane type $(typeof(X[1])) ≠ $C")
                           end),
                          ("BlockReduceAdd", () -> BlockReduceAdd(E, RNE_SatNone, b1)),
                          ("BlockReduceMultiply", () -> BlockReduceMultiply(E, RNE_SatNone, b1)),
                          ("BlockDotProduct", () -> BlockDotProduct(E, RNE_SatNone, b1, b2)),
                          ("ConvertFromBlock", () -> ConvertFromBlock(E, RNE_SatNone, b1)),
                          ("ConvertToBlock",
                           () -> ConvertToBlock(S, E, RNE_SatNone, (E(1.5), E(0.25)), S(1.0))),
                          ("ConvertToBlockMaxAbsFinite",
                           () -> ConvertToBlockMaxAbsFinite(S, E, RNE_SatNone, RNE_SatNone,
                                                            (E(1.5), E(0.25)))))
            r = _try("$tag $lbl", th)
            r === nothing || push!(bad, r)
        end
        # the generated Block*/Scaled* surface, at every registry arity
        for o in OP_REGISTRY
            o.name === :Convert && continue
            bf = getfield(SmallFloats, Symbol(:Block, o.name))
            sf = getfield(SmallFloats, Symbol(:Scaled, o.name))
            bs = ntuple(i -> iseven(i) ? b2 : b1, o.arity)
            sx = collect(Iterators.flatten((S(1.0), E(1.5)) for _ in 1:o.arity))
            r = _try("$tag Block$(o.name)", () -> bf(E, RNE_SatNone, bs..., S(1.0)))
            r === nothing || push!(bad, r)
            r = _try("$tag Scaled$(o.name)", () -> sf(E, RNE_SatNone, sx...))
            r === nothing || push!(bad, r)
        end
        @test (tag, bad) == (tag, String[])
    end
    # the shape list reaches all three heads, by both `blockdecode` methods
    @test sort!(collect(seenheads)) == [(1, false), (1, true), (2, false),
                                        (3, false), (3, true)]

    nr = Dict(r => count(nm -> _rungindex(_fmt(nm)) == r, _PROBED) for r in 1:3)
    record_gate!("G10"; assertions=length(_PROBED) * 3 + length(SHAPES) + 8,
                 units=length(_PROBED) * length(OP_REGISTRY) +
                       length(SHAPES) * length(OP_REGISTRY) * 2,
                 exhaustive=(_G10_TIER == "full"),
                 note=_G10_TIER == "full" ? "" :
                      "format axis sampled: one per (rung, P==1?, code unit) " *
                      "class at rung 2, exhaustive at rung 3; SMALLFLOATS_G10=full for all 72")
    @info "G10 [tier=$(_G10_TIER)]: $(length(_PROBED)) formats " *
          "($(nr[1]) rung-1, $(nr[2]) rung-2, $(nr[3]) rung-3) × " *
          "$(length(OP_REGISTRY)) registry operations, plus the Base veneers and " *
          "array verbs; block surface over $(length(SHAPES)) (FS,FE) shapes " *
          "covering every realized head and both `blockdecode` methods. " *
          (_G10_TIER == "rep" ?
           "The format axis is SAMPLED — one representative per realized " *
           "(rung, P=1?, code unit) class at rung 2, plus eight rung-1 " *
           "controls, exhaustive at rung 3. `SMALLFLOATS_G10=full` probes all " *
           "72 formats above rung 1." :
           "The format axis is EXHAUSTIVE above rung 1 (all 72).")
end
