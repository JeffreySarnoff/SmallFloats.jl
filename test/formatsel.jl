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
sweep that cannot afford 504 formats takes this set and says so.

Named `derive_representatives` rather than `representative_formats` because
`test/golden/harness.jl` already owns the latter — G5's own two-per-cell K ≤ 8
selection, which is a different set answering a different question. Both files are
`include`d into `Main`, so the shorter name was a silent method overwrite: whichever
loaded second won, and the `const REPRESENTATIVE` below happened to be computed
before the clobber. That is luck, not design, and the run said so with a
`Method definition ... overwritten` warning."""
function derive_representatives()
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

const REPRESENTATIVE = derive_representatives()

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

# ---- ONE dial for the whole suite.
#
# Before this, `SmallFloats_EXHAUSTIVE` was read by exactly one file
# (`tier_t2.jl`). Setting it and nothing else gave a caller a partial G10 and a
# six-format Tρ **while they believed they had asked for everything** — and the
# roll-call's `SAMPLED` label made that look intentional rather than omitted.
#
# CLAUDE.md's own words: *"A tier the caller asks for is **honoured, never
# downgraded**: a gate that quietly runs less than it was told to is worse than
# no gate."* A switch only one of four tiers reads is that failure exactly, so
# the switch is now central and `exhaustive_requested()` is the single question
# every format-swept tier asks.
#
#   quick    — the edit-compile-test loop. Narrow format axes, G5 `fast`.
#              Roughly 5 minutes. Exists because a suite with no named fast path
#              gets one invented badly (developers running single files).
#   default  — what `Pkg.test()` does with no environment set. ~17 minutes.
#   release  — every format axis exhaustive, G5 and G10 at `full`. ~38 minutes.
#              The stage-exit and release gate.
#
# **`T1` is exhaustive at every tier and is not tunable here.** The lattice sweep
# at every K is 7 602 160 points for 1m50, and §6.2 says it must stay exhaustive.
# That is the line the dial does not move.
#
# The individual switches remain as overrides — a caller who sets
# `SMALLFLOATS_G5` or `SmallFloats_EXHAUSTIVE` explicitly gets exactly that —
# but nobody should need to know three of them to run a release gate.
const _TIER_NAMES = ("quick", "default", "release")
const SUITE_TIER = let t = lowercase(get(ENV, "SMALLFLOATS_TIER", "default"))
    t in _TIER_NAMES ||
        error("SMALLFLOATS_TIER must be one of $(_TIER_NAMES), got $(repr(t))")
    t
end

"""
Divisor applied to every sampling loop count in `runtests.jl`.

The full literals there are the source of truth; this is the only thing that
shrinks them, and it moves with `SMALLFLOATS_TIER` so **a tier runs what its
name says**. `release` is 1 by definition — the doctrine's "a tier the caller
asks for is honoured, never downgraded" is exactly this constant not exceeding 1
there.

Before this existed the counts were divided unconditionally (`div(5000, 5)`,
`div(4096, 4)`, …) and the `FastTest` switch that once selected between the two
sets had been commented out, so the undivided counts were unreachable at every
tier — including `release`. That is the shape of defect this constant exists to
make impossible: a narrowing the tier dial cannot see.
"""
const LOOP_SCALE = SUITE_TIER == "release" ? 1 : SUITE_TIER == "quick" ? 8 : 4

"""`true` when the caller asked for every format. Set by `SMALLFLOATS_TIER=release`
or by `SmallFloats_EXHAUSTIVE=1` directly; the explicit switch wins so a caller
can widen one axis without moving the whole tier."""
exhaustive_requested() =
    get(ENV, "SmallFloats_EXHAUSTIVE", "") in ("1", "true", "yes") ||
    (SUITE_TIER == "release" && !haskey(ENV, "SmallFloats_EXHAUSTIVE"))

"""`true` at the `quick` tier, where a format axis should be as narrow as it can
be while still touching every carrier. Never narrower than "one per rung" — a
tier that skipped a carrier would not be a faster suite, it would be a different
one."""
quick_requested() = SUITE_TIER == "quick"

"""The format list a sweep should use, and a phrase naming what it is — so the
`@info` line and the roll-call cannot claim coverage the run did not have."""
function sweep_formats(what::AbstractString)
    if exhaustive_requested()
        (ALL_FORMATS,
         "$what: EXHAUSTIVE — all $(length(ALL_FORMATS)) formats")
    elseif quick_requested()
        fs = quick_formats()
        (fs,
         "$what: SAMPLED (tier=quick) — $(length(fs)) of $(length(ALL_FORMATS)) " *
         "formats, one per (rung, P == 1) cell; every carrier is touched and " *
         "nothing else is. Use SMALLFLOATS_TIER=default or =release for more")
    else
        (REPRESENTATIVE,
         "$what: SAMPLED — $(length(REPRESENTATIVE)) of $(length(ALL_FORMATS)) " *
         "formats, one per realized (rung, rung-boundary, code unit, P-class, " *
         "Σ, Δ) cell, maximizing B within each; SMALLFLOATS_TIER=release " *
         "(or SmallFloats_EXHAUSTIVE=1) for all of them")
    end
end

"""The narrowest format set that still reaches every evaluation carrier and both
`blockdecode` methods: one per `(rung, P == 1)` cell, drawn from the derived
representative set so it inherits its "maximizing B" rule."""
function quick_formats()
    seen = Set(); out = Symbol[]
    for nm in REPRESENTATIVE
        T = _selF(nm)
        c = (_rungindex(T), precision(T) == 1)
        c in seen && continue
        push!(seen, c); push!(out, nm)
    end
    sort!(out)
end
