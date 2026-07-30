# ===== test/gates_g4.jl — G4: rung-selection equivalence
#
# *The central gate of the carrier lattice.* For a specialization whose selected
# rung is `r`, evaluating the same operands with the carrier **forced** to rung
# `r+1` (and `r+2` where defined) must produce the identical code point.
#
# What it protects is the premise the whole lattice rests on: that `rung` is an
# *optimization*, not a semantics. Every rung is exact for the operands it
# accepts, so the only thing a wider carrier can buy is time. If forcing a wider
# carrier ever changed an answer, then one of them was not exact — and the
# narrow one is the one that ships.
#
# This is the gate that catches the failure mode `rung` itself cannot report. A
# too-narrow rung does not throw: it computes, in a carrier that silently
# rounded or overflowed, and returns a plausible number. G2 catches that for the
# exact-arithmetic precision; this catches it for the carrier choice.
#
# EXCLUSIONS ARE STATED, NOT SILENT. The rung-forcing comparison covers the
# operations with a native row at more than one rung — exact arithmetic and the
# exact selections. The enclosure-ladder operations reach rungs 2 and 3 through
# MPFR by design, so "the same operands at a wider carrier" is the same MPFR call
# for them and the comparison is vacuous rather than absent. What is asserted for
# those instead is the partition: `_EXACT_SELECTION`, `_EXACT_ARITH`,
# `_LADDER_OPS` and `Convert` cover `OP_REGISTRY` exactly, so an operation cannot
# be classified into none of them and silently lose its wide-rung rows.
#
# Since Stage 7 this file also pins two things the equivalence argument used
# without stating: that the exact selections and `Multiply` are CLOSED on the
# carrier at every rung (which is what `blockdecode`'s `::C` rests on), and that
# the four-factor monomials — `ScaledMultiply`, `BlockDotProduct`,
# `BlockReduceMultiply` — agree with the MPFR definition at the rung their join
# selects, rather than merely returning an object of the right type.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
using Quadmath: Float128
using SmallFloats: _NAMED, rung, joinhead, rungindex, lift, carriertype,
                   HeadF64, HeadF128, HeadExact, ωeval, _finish, _EXACT_SELECTION,
                   _EXACT_ARITH, _LADDER_OPS, OP_REGISTRY, opinfo, opfactors,
                   codepoint, expbias, bitwidth, codeunit_type, rawvalue,
                   _rungindex_span, CarrierValue, _cnan, Dyadic

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

# Evaluate `op` on `xs` with the carrier FORCED to `h`, then project. This is the
# whole apparatus of the gate: `lift` is total upward, so any head at or above
# the operands' own is a legal place to evaluate them.
function at_head(h, op::Val, ::Type{fr}, ρ::ProjSpec, R::Int, xs...) where {fr<:Binary}
    res = ωeval(h, op, map(x -> lift(h, x), xs)...)
    _finish(fr, ρ, R, res)
end

_wider(::HeadF64) = HeadF128()
_wider(::HeadF128) = HeadExact()
_wider(::HeadExact) = nothing

@testset "G4 — rung-selection equivalence" begin

    # ---- completeness of the exact-selection list (promised by oracle.jl).
    #
    # `_EXACT_SELECTION` is an explicit list because it does not coincide with a
    # registry group. Explicit is only safe if it is checked: every name in it
    # must be a real registry operation, and no operation may be classified as
    # both a selection and an escalating arithmetic row.
    regnames = Set(o.name for o in OP_REGISTRY)
    for nm in _EXACT_SELECTION
        @test (nm, nm in regnames) == (nm, true)
    end
    @test length(unique(_EXACT_SELECTION)) == length(_EXACT_SELECTION)
    # `_EXACT_ARITH` and `_LADDER_OPS` come FROM the package, not from a literal
    # restated here. `_LADDER_OPS` is itself derived by subtraction inside
    # `oracle.jl`, so what this asserts is that the three names plus `Convert`
    # partition the registry exactly — the property that makes the derivation
    # sound. Restating the arithmetic list, as this file did through Stage 6,
    # meant a registry change could satisfy the gate and break the package
    # (invariant 7).
    @test isempty(intersect(Set(_EXACT_SELECTION), Set(_EXACT_ARITH)))
    @test isempty(intersect(Set(_EXACT_SELECTION), Set(_LADDER_OPS)))
    @test isempty(intersect(Set(_EXACT_ARITH), Set(_LADDER_OPS)))
    accounted = union(Set(_EXACT_SELECTION), Set(_EXACT_ARITH), Set(_LADDER_OPS),
                      Set((:Convert,)))
    @test sort!(collect(accounted)) == sort!(collect(regnames))
    @info "G4: $(length(_EXACT_SELECTION)) exact selections + " *
          "$(length(_EXACT_ARITH)) exact-arithmetic rows + " *
          "$(length(_LADDER_OPS)) enclosure-ladder rows + Convert = " *
          "$(length(regnames)) registry operations, partitioned"

    # ---- carrier closure, which is what `blockdecode`'s `::C` rests on.
    #
    # `carriertype(h)` is a statement about the DATUMS a head accepts, and it is
    # tempting to read it as a statement about results too. It is one for the
    # exact selections and for `Multiply` — and NOT one for the ladder ops, which
    # escape to MPFR by design at rung 3, nor for `Add`, which can return a
    # `StickyF`. Asserting the true version pins the difference so a future row
    # cannot quietly widen `blockdecode`'s premise.
    #
    # This was not checked before, and the exact-selection rows returned a
    # `Float64` NaN from every wide evaluation as a result: `project` accepts one
    # on every path, and a differential gate sees the same wrong type on both
    # sides (§11 M44).
    heads = (HeadF64(), HeadF128(), HeadExact())
    for h in heads
        C = carriertype(h)
        for nm in _EXACT_SELECTION
            ar = opinfo(nm).arity
            for t in ((1.5, -2.0, 0.0), (NaN, 1.0, 2.0), (Inf, -Inf, 1.0),
                      (0.0, -0.0, NaN), (-0.0, 0.0, -Inf))
                xs = ntuple(i -> lift(h, t[i]), ar)
                r = ωeval(h, Val(nm), xs...)
                @test (nameof(typeof(h)), nm, typeof(r)) ===
                      (nameof(typeof(h)), nm, C)
            end
        end
        # `Multiply` is closed at every rung, and `blockdecode` asserts exactly
        # that: its lanes are `S · xᵢ` typed `::carriertype(h)`.
        for t in ((1.5, -2.0), (0.0, Inf), (NaN, 1.0), (Inf, -Inf), (-0.0, 3.0))
            r = ωeval(h, Val(:Multiply), lift(h, t[1]), lift(h, t[2]))
            @test (nameof(typeof(h)), :Multiply, typeof(r)) ===
                  (nameof(typeof(h)), :Multiply, C)
        end
    end

    # ---- the join is monotone and idempotent, the two properties the equivalence
    # argument uses without stating.
    for a in heads, b in heads
        @test rungindex(joinhead(a, b)) == max(rungindex(a), rungindex(b))
        @test joinhead(a, a) === a
        @test joinhead(a, b) === joinhead(b, a)
    end
    # `lift` never narrows: every lift target is at or above the value's own head
    for h in heads
        @test lift(h, 1.5) isa carriertype(h)
        rungindex(h) >= 2 && @test lift(h, Float128(1.5)) isa carriertype(h)
        rungindex(h) >= 3 && @test lift(h, BigFloat(1.5)) isa carriertype(h)
    end

    # ---- the equivalence itself.
    #
    # Formats chosen to sit on both sides of every rung boundary rather than
    # sampled: the boundary is where a wrong rung would first show.
    FMTS = (Binary8p4se, Binary8p1uf, Binary6p3se,          # rung 1, K ≤ 8
            Binary16p6se, Binary16p8se,                     # rung 1, K = 16
            Binary16p5se, Binary16p4se,                     # rung 2
            Binary16p1uf, Binary16p1sf)                     # rung 3
    RHOS = (RNE_SN, RNE_SF, RTP_SF, RTN_SF,
            RTZ_SN, RTO_SN,
            ProjSpec(StochasticA{8}(), SatNone()),          # stochastic, explicit R
            ProjSpec(StochasticC{8}(), SatFinite()))

    # operands: extremes and a mid-range point, taken from the lattice
    function probes(::Type{T}) where {T<:Binary}
        U = codeunit_type(T); n = 1 << bitwidth(T)
        cs = unique(UInt64[0, 1, 2, n ÷ 4, n ÷ 2, n ÷ 2 + 1, n - 2, n - 1])
        [rawvalue(T, U(c)) for c in cs if c < n]
    end

    # One assertion per (format, operation) cell, with the disagreements — not a
    # count — as the compared value, so a failure names the operands that broke
    # rather than saying "n mismatches". Emitting a `@test` only on mismatch was
    # the first shape of this loop and it is a bad one: a green run then records
    # almost nothing, and a gate that silently stopped iterating looks exactly
    # like a gate that passed. This matches G3's and G6's accounting — one
    # assertion per cell, the true comparison count reported by `@info`.
    compared = 0
    for T in FMTS
        vs = probes(T)
        h0 = rung(T)
        h1 = _wider(h0)
        h1 === nothing && continue                # rung 3 has nothing above it
        h2 = _wider(h1)
        for op in (:Add, :Subtract, :Multiply, :Abs, :Negate, :CopySign,
                   :Maximum, :Minimum, :MaximumMagnitude, :MinimumFinite)
            V = Val(op); ar = opinfo(op).arity
            bad = Tuple{Symbol,UInt,UInt,Int,UInt,UInt}[]
            for ρ in RHOS, R in (0, 3, 7)
                for x in vs, y in (ar == 1 ? vs[1:1] : vs)
                    xs = ar == 1 ? (decode(x),) : (decode(x), decode(y))
                    a = at_head(h0, V, T, ρ, R, xs...)
                    b = at_head(h1, V, T, ρ, R, xs...)
                    compared += 1
                    codepoint(a) == codepoint(b) ||
                        push!(bad, (:r1, UInt(codepoint(x)), UInt(codepoint(y)),
                                    R, UInt(codepoint(a)), UInt(codepoint(b))))
                    h2 === nothing && continue
                    c = at_head(h2, V, T, ρ, R, xs...)
                    compared += 1
                    codepoint(a) == codepoint(c) ||
                        push!(bad, (:r2, UInt(codepoint(x)), UInt(codepoint(y)),
                                    R, UInt(codepoint(a)), UInt(codepoint(c))))
                end
            end
            @test (nameof(T), op, bad) == (nameof(T), op, eltype(bad)[])
        end
    end
    @test compared > 0
    @info "G4: $compared rung-forced comparisons over $(length(FMTS)) formats × " *
          "$(length(RHOS)) ρ × 3 R values, all agreeing on the code point"

    # ---- the four-factor case the plan calls out: `ScaledMultiply` needs a wider
    # carrier than either operand format does, and that is the join's whole point.
    @test opfactors(Val(:Multiply)) == 2
    # a 4-factor monomial over B = 512 datums needs 2048 binades: past rung 1
    @test _rungindex_span(4 * 512) == 2
    @test _rungindex_span(2 * 512) == 1

    # The four-factor products are `ScaledMultiply` (two scales, two elements)
    # and each lane of `BlockDotProduct`. Through Stage 6 this section asserted
    # only `isa E` — that the call returned an object of the right type — which
    # is a check that the carrier lattice is *reachable*, not that it is *right*.
    # A silently-narrowed carrier returns an `E` too; that is exactly how
    # `BlockReduceMultiply` returned `Inf` at rung 3 (§11 M44).
    #
    # The reference is the definition, computed in MPFR at a precision derived
    # from the four formats and then doubled. It shares `project` with the code
    # under test and nothing else — not the head selection, not the accumulator
    # choice, not the lane decode.
    function ref4(::Type{FR}, ρ, s1, x1, s2, x2, op) where {FR<:Binary}
        p = 4 * (sum(expbias ∘ typeof, (s1, x1, s2, x2)) +
                 sum(precision ∘ typeof, (s1, x1, s2, x2))) + 256
        setprecision(BigFloat, p) do
            a = BigFloat(decode(s1)) * BigFloat(decode(x1))
            b = BigFloat(decode(s2)) * BigFloat(decode(x2))
            r = op === :mul ? a * b : a + b
            iszero(r) && (r = zero(BigFloat))
            codepoint(SmallFloats.project(FR, ρ, r))
        end
    end

    # scale/element pairs spanning the rungs, including the P = 1 MX shape whose
    # `blockdecode` takes the ldexp path and whose scale exceeds Float128's range
    QUADS = ((Binary8p3se,  Binary16p6se),      # rung 1 both
             (Binary16p5se, Binary16p6se),      # rung 2 scale
             (Binary16p4se, Binary8p4se),       # rung 2 scale, narrow lanes
             (Binary16p1uf, Binary16p6se),      # rung 3, P = 1 (the MX shape)
             (Binary16p1sf, Binary8p4se),       # rung 3, P = 1, narrow lanes
             (Binary8p1uf,  Binary16p6se))      # E8M0 scale (Annex F), rung 1
    quads = 0
    for (S, E) in QUADS
        bad = Tuple{Symbol,Symbol,Float64,Float64,UInt,UInt}[]
        for sv in (S(1.0), S(-1.0), S(0.5)), xv in (E(1.5), E(0.25), E(-2.0))
            for ρ in (RNE_SN, RNE_SF, RTZ_SN)
                got = codepoint(ScaledMultiply(E, ρ, sv, xv, S(1.0), E(0.25)))
                want = ref4(E, ρ, sv, xv, S(1.0), E(0.25), :mul)
                quads += 1
                got == want && continue
                push!(bad, (nameof(S), nameof(E), Float64(decode(sv)),
                            Float64(decode(xv)), UInt(got), UInt(want)))
            end
        end
        @test (nameof(S), nameof(E), bad) == (nameof(S), nameof(E), eltype(bad)[])

        # BlockDotProduct: a two-lane dot product IS a sum of two four-factor
        # monomials, so it is the same reference twice plus one exact add.
        bx = Block(S(1.0), (E(1.5), E(0.25)))
        by = Block(S(-1.0), (E(0.25), E(1.5)))
        p = 4 * (2 * (expbias(S) + expbias(E) + precision(S) + precision(E))) + 256
        want = setprecision(BigFloat, p) do
            t(i) = BigFloat(decode(bx.s)) * BigFloat(decode(bx.x[i])) *
                   BigFloat(decode(by.s)) * BigFloat(decode(by.x[i]))
            r = t(1) + t(2)
            iszero(r) && (r = zero(BigFloat))
            codepoint(SmallFloats.project(E, RNE_SN, r))
        end
        @test (nameof(S), nameof(E), codepoint(BlockDotProduct(E, RNE_SN, bx, by))) ==
              (nameof(S), nameof(E), want)
        quads += 1

        # BlockReduceMultiply over two lanes is the same monomial in one call.
        wantp = setprecision(BigFloat, p) do
            r = (BigFloat(decode(bx.s)) * BigFloat(decode(bx.x[1]))) *
                (BigFloat(decode(bx.s)) * BigFloat(decode(bx.x[2])))
            iszero(r) && (r = zero(BigFloat))
            codepoint(SmallFloats.project(E, RNE_SN, r))
        end
        @test (nameof(S), nameof(E), codepoint(BlockReduceMultiply(E, RNE_SN, bx))) ==
              (nameof(S), nameof(E), wantp)
        quads += 1
    end
    record_gate!("G4"; assertions=369, units=compared + quads, exhaustive=false,
                 note="9 formats chosen either side of every rung boundary, " *
                      "8 ρ, 3 R values; the format axis is boundary-targeted, not swept")
    @info "G4: $quads four-factor monomials over $(length(QUADS)) (scale, element) " *
          "shapes agree with the MPFR definition, at every rung the join selects"
end
