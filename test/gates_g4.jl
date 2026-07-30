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
# EXCLUSIONS ARE STATED, NOT SILENT. Only operations with rows at more than one
# rung can be compared, which today is Group A plus the exact selections. The
# quotient family and Group B reach the wide rungs through the enclosure ladder,
# which is the remaining Stage 6 item; the count of what was skipped is reported
# so this file cannot read as broader coverage than it has.

using Test, SmallFloats
using Quadmath: Float128
using SmallFloats: _NAMED, rung, joinhead, rungindex, lift, carriertype,
                   HeadF64, HeadF128, HeadExact, ωeval, _finish, _EXACT_SELECTION,
                   OP_REGISTRY, opinfo, opfactors, codepoint, expbias, bitwidth,
                   codeunit_type, rawvalue, _rungindex_span

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
    const_arith = (:Add, :Subtract, :Multiply, :FMA, :FAA)
    @test isempty(intersect(Set(_EXACT_SELECTION), Set(const_arith)))
    # Every registry op is accounted for: a selection, an exact-arithmetic row,
    # Convert, or something that still reaches the wide rungs only through the
    # enclosure ladder. The last group is what remains of Stage 6.
    accounted = union(Set(_EXACT_SELECTION), Set(const_arith), Set((:Convert,)))
    pending = sort!(collect(setdiff(regnames, accounted)))
    @test !isempty(pending)          # if this empties, delete the note below
    pendlist = join(pending, ", ")
    @info "G4: $(length(accounted)) operations have rows at every rung; " *
          "$(length(pending)) still reach rungs 2/3 only via the enclosure " *
          "ladder (remaining Stage 6 item): $pendlist"

    # ---- the join is monotone and idempotent, the two properties the equivalence
    # argument uses without stating.
    heads = (HeadF64(), HeadF128(), HeadExact())
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
    RHOS = (RNE_SatNone, RNE_SatFinite, RTP_SatFinite, RTN_SatFinite,
            RTZ_SatNone, RTO_SatNone,
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
    let S = Binary8p3se, E = Binary16p6se
        @test opfactors(Val(:Multiply)) == 2
        # a 4-factor monomial over B = 512 datums needs 2048 binades: past rung 1
        @test _rungindex_span(4 * 512) == 2
        @test _rungindex_span(2 * 512) == 1
        bx = Block(S(1.0), (E(1.5), E(0.25)))
        by = Block(S(1.0), (E(0.25), E(1.5)))
        @test BlockDotProduct(E, RNE_SatNone, bx, by) isa E
        @test ScaledMultiply(E, RNE_SatNone, S(1.0), E(1.5), S(1.0), E(0.25)) isa E
    end
end
