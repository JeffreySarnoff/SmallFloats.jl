# Arrays, Blocks, and Packed Storage

This page collects signatures and contracts for bulk operations, block-scaled
values, and packed storage. For procedures, use
[Run Operations over Arrays](workflow_arrays.md),
[Use Blocks for Dynamic Range](workflow_blocks.md), or
[Pack Values for Storage](workflow_packed_storage.md).

## Array operation forms

| Form | Signature | Related guide |
|:---|:---|:---|
| Unary array | `Op(fr, ρ, A)` | [Cheat Sheet](help_cheat_sheet.md) |
| Binary array | `Op(fr, ρ, A, B)` | [Cheat Sheet](help_cheat_sheet.md) |
| Ternary array | `Op(fr, ρ, A, B, C)` | [Cheat Sheet](help_cheat_sheet.md) |
| Generic map | `vmap(:Op, fr, ρ, operands...)` | [Cheat Sheet](help_cheat_sheet.md) |
| Generic map, in-place | `vmap!(C, Val(:Op), fr, ρ, operands...)` | [Cheat Sheet](help_cheat_sheet.md) |
| Callable operation object | `Op(:Op, fr, ρ)` then `.(A)` or `map(Op(:Op, fr, ρ), A, B)` | [Run Operations over Arrays](workflow_arrays.md) |

Operands and destination must have matching axes.

## Table cache introspection

| Function | Signature | Notes | Related guide |
|:---|:---|:---|:---|
| `table_bytes` | `table_bytes()` | current cache footprint, bytes | [Cheat Sheet](help_cheat_sheet.md) |
| `empty_tables!` | `empty_tables!()` | reset the table cache | [Cheat Sheet](help_cheat_sheet.md) |

Deterministic unary/binary array calls use cached result tables (256 B unary,
64 KiB binary). Ternary tables tier by combined operand bitwidth: eager
(≤ 18 bits total), adaptive with LRU eviction (≤ 21 bits total), compute per
element at `K = 8`. Stochastic operations always compute per element and
consume one draw per projection.

## Block functions

| Function | Signature | Related guide |
|:---|:---|:---|
| `blocksize` | `blocksize(b)` | [Cheat Sheet](help_cheat_sheet.md) |
| `scaleformat` | `scaleformat(b)` | [Cheat Sheet](help_cheat_sheet.md) |
| `elemformat` | `elemformat(b)` | [Cheat Sheet](help_cheat_sheet.md) |
| `ConvertFromBlock` | `ConvertFromBlock(fr, ρ, b)` | [Cheat Sheet](help_cheat_sheet.md) |
| `ConvertToBlock` | `ConvertToBlock(fs, fr, ρ, values_tuple, scale)` | [Cheat Sheet](help_cheat_sheet.md) |
| `ConvertToBlockMaxAbsFinite` | `ConvertToBlockMaxAbsFinite(fs, fr, scale_ρ, element_ρ, values_tuple)` | [Cheat Sheet](help_cheat_sheet.md) |
| `BlockReduceAdd` | `BlockReduceAdd(fr, ρ, b)` | [Cheat Sheet](help_cheat_sheet.md) |
| `BlockReduceMultiply` | `BlockReduceMultiply(fr, ρ, b)` | [Cheat Sheet](help_cheat_sheet.md) |
| `BlockDotProduct` | `BlockDotProduct(fr, ρ, bx, by)` | [Cheat Sheet](help_cheat_sheet.md) |

`BlockReduceAdd`, `BlockReduceMultiply`, and `BlockDotProduct` perform their
lane products and accumulation exactly, projecting once at the end — no
hidden intermediate rounding.

### Generated `BlockOp` / `ScaledOp` pattern

Every scalar operation except `Convert` has a generated block form and a
generated scaled form.

| Pattern | Signature |
|:---|:---|
| `BlockOp` | `BlockOp(fr, ρ, b1, b2, result_scale)` (arity follows the underlying `Op`) |
| `ScaledOp` | `ScaledOp(fr, ρ, scale1, x1, scale2, x2, ...)` (block size 1; arity follows the underlying `Op`) |

Examples:

```julia
BlockAdd(T, ρ, b1, b2, result_scale)
BlockExp(T, ρ, b, result_scale)

ScaledAdd(T, ρ, scale1, x1, scale2, x2)
ScaledExp(T, ρ, scale, x)
```

## `BlockVector`

Stores many equal-shape blocks in a structure-of-arrays layout. No additional
scalar API beyond the `Block` operations above; construct from a collection of
same-shape `Block`s.

## `PackedVector`

| Operation | Signature | Notes |
|:---|:---|:---|
| Construct | `PackedVector(v)` | `v::AbstractVector{F}` |
| Index (read) | `pv[i]` | returns an `F` |
| Index (write) | `pv[i] = x` | `x::F` |
| Collect | `collect(pv)` | materializes a `Vector{F}` |
| `sizeof` rule | `sizeof(pv.data)` | `ceil(length(pv) * bitwidth(F) / 8)` bytes, rounded to the storage word |
| `vmap` acceptance | `vmap(:Op, F, ρ, pv)` | accepted directly; tiles unpack internally |

`PackedVector` stores each code point in exactly `bitwidth(F)` bits.
Computation unpacks tiles internally; packed arithmetic is deliberately not
in-place — store packed, compute unpacked.

## Related contracts

[Cheat Sheet](help_cheat_sheet.md),
[Run Operations over Arrays](workflow_arrays.md),
[Use Blocks to Track Dynamic Range](workflow_blocks.md).
