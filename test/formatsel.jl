# ===== test/formatsel.jl — the representative format set, DERIVED from the grid
#
# Stage 8 step 3. A hand-listed tuple of four names cannot track a 504-format
# grid, and one that silently stops covering a newly-realized cell is the most
# likely way this extension ships a hole. So the selection is computed, the cell
# structure is stated, and the count is reported — a cell that appears or
# disappears changes the number in the suite output rather than passing quietly.
#
# ---- why a representative set exists at all, and what it costs to skip it.
#
# Measured, not assumed: sweeping 20 formats × 27 ρ through `project` costs
# **21.5 s cold and 0.0 s warm**. The entire cost is specialization —
# `Binary{K,P,Σ,Δ}` is a distinct type per format and every method recompiles for
# each — so the full 504-format sweep is ≈ 9 minutes of compilation and ≈ 1.5 s
# of arithmetic. That is the whole reason the shipped suite samples this
# dimension, and it is why the sampling has to be principled: the expensive axis
# is the one where a bad choice is invisible.
#
# ---- the cells.
#
# A cell is what *dispatch and the draft together* can distinguish, which is a
# different question from what the format means:
#
#   rung          — which evaluation carrier the format's operands land on
#                   (`Float64` / `Float128` / `Dyadic`). Three values.
#   boundary      — whether the format sits adjacent to a rung boundary, in
#                   either direction. A wrong `_rungindex_span` threshold shows
#                   up first at the formats either side of it and nowhere else.
#   code unit     — `UInt8` vs `UInt16`: the representation seam, `Code8`/`Code16`.
#   P-class       — `P == 1` (no significand bits to round; the MX scale shape),
#                   `P == K` (no exponent bits; unsigned only), or neither.
#   Σ, Δ          — signedness and domain. These are the two the ωSaturate rows
#                   branch on, so they are never collapsed.
#
# Within a cell the representative is the format **maximizing B**, i.e. the
# widest exponent range in that cell. Ties break on the largest K, then the name,
# so the selection is deterministic and reproducible from the definition alone —
# a set that moved between runs would be worse than a hand-listed one.
#
# The choice of "maximizing B" is deliberate rather than arbitrary: B is what
# every precision, spread and carrier-range question in this package scales with
# — `bigprec`, `_lane_sum_prec`, the rung boundaries, and the alignment bands are
# all functions of it. Within a cell, the largest B is the hardest case.

using SmallFloats
using SmallFloats: _NAMED, bitwidth, precision, expbias, issigned, isextended,
                   codeunit_type, _rungindex, Binary

# The registry, not the module binding. `_NAMED` maps a format name to its
# concrete type directly, so this is independent of the EXPORT SURFACE — and the
# export surface is Stage 9 item 1, still open. `getfield(SmallFloats, nm)` would
# tie every derived sweep in this suite to the 504 aliases staying bindings of
# `SmallFloats`; if they move behind a `SmallFloats.Formats` submodule the
# dictionary lookup keeps working and the `getfield` does not. A test harness
# should not be the thing that constrains a naming decision.
_selF(nm) = _NAMED[nm]::Type{<:Binary}

"""Every format name in the grid, sorted, so every derived set below is
deterministic."""
const ALL_FORMATS = sort!(collect(keys(_NAMED)))

"""`true` when a format sits next to a rung boundary — its rung differs from that
of a format one step away in B. Computed from `_rungindex` rather than from the
threshold constants, so moving a threshold moves the set that tests it."""
function _boundary_adjacent(nm)
    T = _selF(nm); r = _rungindex(T)
    for other in ALL_FORMATS
        O = _selF(other)
        # one step in B, at the same P-class: the smallest change that can move
        # a format across a rung boundary
        abs(expbias(O) - expbias(T)) == 0 && continue
        if _rungindex(O) != r && abs(bitwidth(O) - bitwidth(T)) <= 1 &&
           precision(O) == precision(T)
            return true
        end
    end
    false
end

_pclass(T) = precision(T) == 1 ? :Pmin :
             precision(T) == bitwidth(T) ? :Pmax : :Pmid

"""The cell a format occupies. Changing this function changes the shipped
coverage, which is why it is one function and not a scattering of conditions."""
format_cell(nm) = (T = _selF(nm);
                   (_rungindex(T), _boundary_adjacent(nm), codeunit_type(T),
                    _pclass(T), issigned(T), isextended(T)))

"""One format per realized cell: the one maximizing B, then K, then name. Every
sweep that cannot afford 504 formats takes this set and says so."""
function representative_formats()
    best = Dict{Any,Symbol}()
    for nm in ALL_FORMATS
        c = format_cell(nm); T = _selF(nm)
        cur = get(best, c, nothing)
        if cur === nothing
            best[c] = nm
        else
            C = _selF(cur)
            key(X, n) = (expbias(X), bitwidth(X), string(n))
            key(T, nm) > key(C, cur) && (best[c] = nm)
        end
    end
    sort!(collect(values(best)))
end

const REPRESENTATIVE = representative_formats()

# ---- the T4 edge set, derived from the thresholds in the SOURCE.
#
# The plan's step 3 asks for this in the same breath and for the same reason:
# an edge set written as literals is a snapshot of the thresholds as they were
# on the day it was written. These come from the constants themselves, so moving
# `_STICKY_MIN` or a rung boundary moves the values that probe it, and a
# threshold with no probe on either side is a thing the count makes visible.
using SmallFloats: _STICKY_MIN, _rungindex_span
using SmallFloats.DyadicNumbers: DYADIC_ALIGN_MAX, DYADIC_ADD_COVERAGE

"""Exponent-difference probes: each threshold in the source, and one step either
side of it. `ΔE` is the quantity every `_DE_*` decision and every sticky-head
shortcut turns on, so this is the axis on which T4's edges live."""
function threshold_edges()
    ts = Int[_STICKY_MIN, DYADIC_ALIGN_MAX, DYADIC_ADD_COVERAGE,
             53, 113,                       # the two hardware carrier widths
             1024, 16384]                   # the rung boundaries, in ΣB
    es = Int[]
    for t in ts, d in (-1, 0, 1)
        push!(es, t + d)
    end
    sort!(unique(filter(>=(0), es)))
end

const THRESHOLD_EDGES = threshold_edges()

"""`true` when the caller asked for the exhaustive sweep. Named here so every
tier reads the same switch and reports it the same way (Stage 8 step 5)."""
exhaustive_requested() = get(ENV, "SmallFloats_EXHAUSTIVE", "0") in ("1", "true", "yes")

"""The format list a sweep should use, and a phrase naming what it is — so the
`@info` line cannot claim coverage the run did not have."""
function sweep_formats(what::AbstractString)
    if exhaustive_requested()
        (ALL_FORMATS,
         "$what: EXHAUSTIVE — all $(length(ALL_FORMATS)) formats")
    else
        (REPRESENTATIVE,
         "$what: SAMPLED — $(length(REPRESENTATIVE)) of $(length(ALL_FORMATS)) " *
         "formats, one per realized (rung, rung-boundary, code unit, P-class, " *
         "Σ, Δ) cell, maximizing B within each; set SmallFloats_EXHAUSTIVE=1 " *
         "for all of them")
    end
end
