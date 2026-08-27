# Documentation claim ledger

This ledger keeps implementation-sensitive prose reviewable. It is a
maintenance artifact: readers should use the guides and references, while
authors use this file to prevent a correct `Code8` statement from becoming an
incorrect claim about every `Binary` format.

| ID | Claim and scope | Primary source authority | Documentation owner | Review status |
|---|---|---|---|---|
| FMT-1 | Legal formats span `K = 3:16`; `Code8` and `Code16` are distinct concrete representations selected from the abstract format. | `src/formats.jl` (`KMAX`, `KSPLIT`, `reptype`) | format anatomy, format reference | reviewed 2026-08-18 |
| CODEC-1 | `decode(v)` returns `datumcarrier(typeof(v))`; the result is exact for every datum. | `src/carriers.jl`, `src/decode_encode.jl` | values, core model, codec guide | reviewed 2026-08-18 |
| CODEC-2 | Code8 uses a generated decode tuple; Code16 uses computational decode and refuses a wide constant tuple. | `src/formats.jl`, `src/decode_encode.jl` | codec guide, technical guide | reviewed 2026-08-18 |
| CODEC-3 | `encode` returns `codeunit_type(F)` and documents a caller-side datum-set precondition. | `src/decode_encode.jl`, `src/project.jl` | projection/codec guides | reviewed 2026-08-18 |
| ORDER-1 | NaN is the smallest total-order member; order-key type scales from `UInt16` to `UInt32`. | `src/formats.jl`, `src/decode_encode.jl` | values, code-point algebra, codec guide | reviewed 2026-08-18 |
| TABLE-1 | Tables store result code units of the result representation and are admitted by the current byte-budget policy; compute paths remain semantically identical. | `src/tables.jl`, `src/kernels.jl` | tables guide, performance model | reviewed 2026-08-18 |
| CARRIER-1 | Carrier selection and oracle rigor are separate: a datum carrier answers representation range; a rigor class justifies an operation result. | `src/carriers.jl`, `src/oracle.jl` | architecture, oracle guide | reviewed 2026-08-18 |
| PERF-1 | Timings, allocation figures, and thread scaling are measurements, not package guarantees; every reported number names its format, path, environment, and measurement script. | `benchmarking/`, `docs/src/examples_performance.md` | performance pages | pending measurement refresh |

When source changes, update the row before changing prose. A new numerical
claim requires a new row or a refreshed `PERF-1` entry with its command,
environment, and date.
