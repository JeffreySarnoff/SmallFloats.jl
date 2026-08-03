# SmallFloats.jl verification guide

`test/runtests.jl` is the package test entry point. It combines numerical
references, representation and carrier gates, golden digests, documentation
examples, Aqua, JET, and a final coverage roll-call.

## Run a tier

From the repository root:

```sh
SMALLFLOATS_TIER=quick julia --project=. -e 'using Pkg; Pkg.test()'
SMALLFLOATS_TIER=default julia --project=. -e 'using Pkg; Pkg.test()'
SMALLFLOATS_TIER=release julia --project=. -e 'using Pkg; Pkg.test()'
```

| Tier | Purpose | Coverage shape |
|:---|:---|:---|
| `quick` | edit/compile/test loop and pull requests | narrowest representative format axes; fast golden sections |
| `default` | main-branch confidence | derived representative format sets; lazy golden sections |
| `release` | release evidence | every format axis that can be exhaustive; full golden sections |

Runtime depends strongly on compilation caches and hardware. Treat the final
roll-call—not a fixed duration or assertion total—as the record of what ran.

## Read the roll-call

`test/rollcall.jl` runs last. Every required gate registers:

- assertion count;
- units actually compared;
- whether its stated finite domain was exhaustive;
- a note describing every sampled axis.

A quick run is required to identify itself as quick. A release run fails if a
gate that should be exhaustive silently remained sampled. Some gates are
cell-complete or representative by design at every tier; the roll-call names
those exceptions.

## Focused gate controls

The suite-wide tier normally selects all gate levels. Maintainers can override
individual expensive gates while diagnosing them, including
`SMALLFLOATS_G5=off|fast|lazy|full` and
`SMALLFLOATS_G10=quick|rep|full`. An explicit override always wins and is shown
in output. Do not use a narrowed override as release evidence.

## Golden digests

`test/golden/k8.sha256` records defined K <= 8 results by named section. A digest
change is a semantic change, not a snapshot update. Identify the affected
operation and draft row first, update independent expectations and the
changelog, then recapture only as part of a reviewed intentional change using
`test/golden/capture.jl`.

## Failure triage

1. Read the first failing named gate, not only the aggregate summary.
2. Compare its reported domain and tier with the intended run.
3. For numerical mismatches, compare code points and follow the scalar
   exact-result-to-`project` path before inspecting tables or kernels.
4. For table/kernel failures, establish whether scalar semantics changed or the
   execution shapes diverged.
5. For documentation failures, edit `docs/src`; generated HTML/PDF trees are
   outputs.

Benchmarking is separate from correctness verification. Its runners and
measurement contract live under `benchmarking/`.
