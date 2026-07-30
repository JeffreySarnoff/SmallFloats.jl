# ===== test/gatelog.jl — the roll-call register (Stage 8 steps 5 and 6)
#
# Two of Stage 8's requirements are really one requirement:
#
#   step 5 — "every budget a `Ref` and reported in suite output; every sampled
#             result labelled in the same words `measure_kappa` already uses"
#   step 6 — "G1–G10 all standing, all named in the suite output"
#
# Both are the same claim: *the suite must state what it actually covered, in a
# place a reader will see, and the statement must be checked rather than
# maintained.* A comment saying "G4 is standing" is maintained; a roll-call that
# fails when G4 does not register is checked.
#
# So every gate and every tier calls `record_gate!` with three things: what it
# is, how much it did (the budget, as a number, from the `Ref` it counted into),
# and whether that was exhaustive or sampled — in `measure_kappa`'s own words, so
# a reader who knows what `exhaustive = false` means in the conformance report
# knows what it means here.
#
# `test/rollcall.jl` runs last and asserts the register is complete. A gate that
# is deleted, renamed, or silently skipped fails that assertion; a gate whose
# coverage quietly narrows changes a number the run prints.

"""The register. Keyed by gate name so a double-registration is caught rather
than appended — two files claiming the same gate is a defect, not a merge."""
const GATE_LOG = Dict{String,NamedTuple}()

"""
    record_gate!(name; assertions, units, exhaustive, note="")

Record what a gate or tier covered.

* `assertions` — the count of `@test` invocations, i.e. what the summary line
  shows. Cheap to know and easy to misread as coverage, which is why it is not
  the only number here.
* `units` — the count of *things actually compared*: rounding decisions, code
  points, engine calls. This is the budget the plan asks to be a `Ref` and
  reported, and it is the honest measure — G4's 152 064 comparisons behind 369
  assertions is the shape every accumulating gate in this suite has.
* `exhaustive` — `true` only if the gate enumerated its whole input space.
  `false` means sampled, and `note` must then say over what.
"""
function record_gate!(name::AbstractString; assertions::Integer, units::Integer,
                      exhaustive::Bool, note::AbstractString="")
    haskey(GATE_LOG, name) &&
        error("gatelog: $name registered twice — two files claim the same gate")
    exhaustive || !isempty(note) ||
        error("gatelog: $name is sampled and must say over what (pass `note`)")
    GATE_LOG[name] = (; assertions=Int(assertions), units=Int(units), exhaustive, note)
    nothing
end

"""The gates and tiers that MUST be present in a complete run. Named here rather
than derived, because the point is to notice one going missing — a list derived
from what ran cannot detect what did not run."""
const REQUIRED_GATES = ["G1", "G2", "G3", "G4", "G5", "G6", "G7", "G9", "G10",
                        "T1", "T2a", "T2b", "Tρ", "D↔Q"]

# `G8` is deliberately absent from the required list: the representation
# invariant is asserted inside the constructors and swept by T1's encode
# round-trip at every K, so it has no file of its own. Naming that here keeps the
# gap from reading as an omission — see §6.4 in the plan, and the roll-call's
# printed note.
