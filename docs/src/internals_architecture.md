# Architecture and Invariants

The implementation is organized around two independent classifications: the
carrier rung needed to hold a format exactly and the rigor class attached to a
computed result. The remaining internal pages follow values through those
classifications and into the one projection path.

The first axis is the **carrier rung** a format's datums decode to, chosen by
the format's exponent bias: `Float64` for the 432 formats whose full dynamic
range fits Float64's normal range (rung 1), `Float128` for formats that need
more exponent room but stay in binary floating point (rung 2), and an exact
dyadic carrier for the formats — 72 of them — whose range or precision breaks
even Float128 (rung 3). The choice is a dispatch decision derived from the
exponent bias, never a caller's, and every rung is exact for the datums it
carries. The second axis is the **rigor class** attached to every non-`Float64`
computed result: Class R (unconditional — provable without any accuracy
assumption) and Class E (envelope-conditional — faithful-but-not-CR estimates
validated by a generous, measured slack). Together the two axes answer, for
any operation on any format, "what carries the value" and "what justifies the
result."

The pages that follow work through the machinery each axis produces: the
encoding and projection engine that every carrier rung feeds into
([Encoding and Decoding](internals_encoding_decoding.md)), the oracle and its
two rigor classes ([Oracle and Rigor Classes](internals_oracle.md)), the table
and kernel layer that makes the common rung fast
([Function Tables and Array Kernels](internals_tables.md)), the block layer's
exactness argument ([Exact Block Reductions](internals_blocks.md)), and the
[Verification Strategy](internals_verification.md) that keeps all of it
honest.

## Layer map

Source files load in dependency order, each layer speaking only downward:

| layer | file | provides |
|:---|---|---|
| formats | `formats.jl` | `Binary{K,P,SGN,EXT}`, the 504 named aliases, Group M queries |
| specs | `projspec.jl` | rounding/saturation singletons, `ProjSpec{R,S}`, the predefined spec grid |
| defaults | `defaults.jl` | settable session defaults (`DefaultType`, `DefaultProjection`, …) behind `Ref`s; consumed via the speculation guard |
| codec | `decode_encode.jl` | decode (generated tables + bit-composed compute), encode, order keys, counting sort, `Class`, Next ops |
| engine | `project.jl` | `round_to_precision` (mask-based Float64 core + generic core), `saturate`, `project`, `project_interval` |
| ops | `ops_scalar.jl` | result-kind protocol, `apply_op`, the operation registry, the spec register |
| compat | `juliacompat.jl` | the Base register: declarative op ⇒ Base-function map |
| oracle | `oracle.jl` | ω-semantics for all 52 operations |
| tables | `tables.jl` | the pure-ρ result-table cache (unary/binary + bitwidth-gated ternary) |
| kernels | `kernels.jl` | Shape-A gathers, Shape-B scalar/threaded loops, `vmap` |
| blocks | `blocks.jl` | `Block`, block/scaled ops, exact reductions |
| packed | `packed.jl` | sub-byte `PackedVector` storage |
| approx | `approx.jl` | κ measurement/registry, conformance declaration |
| rand | `rand.jl` | Random-API hooks: uniform-[0,1) floor projection, clamped normal |

## Continue through the implementation

[Encoding and Decoding](internals_encoding_decoding.md),
[Oracle and Rigor Classes](internals_oracle.md),
[Function Tables and Array Kernels](internals_tables.md),
[Exact Block Reductions](internals_blocks.md),
[Verification Strategy](internals_verification.md).
