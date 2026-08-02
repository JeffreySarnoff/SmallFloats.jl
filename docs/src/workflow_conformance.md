# Read and Export Conformance

Produce a machine-readable statement of exactly which formats, operations,
and approximations a session used, and attach it to an experiment's
artifacts.

## Ingredients

- `conformance()` — the live declaration as a Julia value.
- `conformance_report()` — a printed, human-readable form.
- `conformance_dict()` — a plain nested `Dict{String,Any}` for JSON/TOML
  serialization.
- `draft_revision()` — the P3109 draft revision the package implements.
- Any JSON/TOML writer your project already depends on.

## Recipe

**1. Inspect the live declaration.** `conformance()` returns the formats,
operations, mode vocabulary, the table specializations actually instantiated
this session, and every registered approximation. `conformance_report()`
prints the same information for a human to read at the REPL.

**2. Export it as a plain `Dict` for serialization.**

```julia
d = conformance_dict()          # plain nested Dict{String,Any}
(d["package"], length(d["formats"]), length(d["operations"]),
 [s["op"] for s in d["cached_specializations"]])
```

Serialize `d` with any JSON/TOML writer to attach a machine-readable
conformance statement to experiment artifacts — for example, alongside a
saved model checkpoint or a benchmark result, so a later reader can confirm
exactly which formats and approximations produced it without re-running the
session.

**3. Record the draft revision alongside it.** `draft_revision()` reports
which revision of the P3109 draft this package implements — include it next
to the conformance dict so an artifact remains interpretable even if the
draft itself changes in a later package version.

**4. Confirm registered approximations show up.** Any approximation
registered with `register_approx!` appears in the conformance declaration
automatically — `conformance_report()` lists it alongside the exact
operation catalog, so the declaration always reflects the true provenance of
a session's results, exact and approximate alike.

## What can go wrong

!!! note "The declaration is live, not static"
    `conformance()` and `conformance_dict()` reflect the *current* session —
    including which table specializations have actually been built so far.
    Call them at the point you want to snapshot (typically right before
    saving results), not at the top of a script, or the declaration may
    under-report what the run actually exercised.

!!! warning "A conformance dict does not travel with unregistered approximations"
    If you registered an approximation in one session and load results from
    it in a fresh session, `conformance_dict()` in the new session will not
    know about that approximation unless you re-register it. Save the
    exported dict itself with the artifact — do not rely on regenerating it
    later from a differently configured session.

!!! note "JSON/TOML serialization is your responsibility, not the package's"
    `conformance_dict()` returns a plain nested `Dict`; the package does not
    ship a JSON or TOML writer. Use whatever serialization library your
    project already depends on — the dict is deliberately unopinionated
    about the output format.

## Next steps

[Register & Measure an Approximation (κ)](workflow_approximation.md),
[Choose a Format](workflow_choose_format.md).
