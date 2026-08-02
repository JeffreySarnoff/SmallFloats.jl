# Reference: Arrays, Blocks & Packed Storage

Signatures only. For narrative treatment, see the User Guide's Arrays,
kernels, and sorting section, and the Blocks and scaled operations section.

## Array operation forms

| Form | Signature | Teaching page |
|---|---|---|
| Unary array | `Op(fr, ρ, A)` | Cheat Sheet |
| Binary array | `Op(fr, ρ, A, B)` | Cheat Sheet |
| Ternary array | `Op(fr, ρ, A, B, C)` | Cheat Sheet |
| Generic map | `vmap(:Op, fr, ρ, operands...)` | Cheat Sheet |
| Generic map, in-place | `vmap!(C, Val(:Op), fr, ρ, operands...)` | Cheat Sheet |
| Callable operation object | `Op(:Op, fr, ρ)` then `.(A)` or `map(Op(:Op, fr, ρ), A, B)` | User Guide |

Operands and destination must have matching axes.

## Table cache introspection

| Function | Signature | Notes | Teaching page |
|---|---|---|---|
| `table_bytes` | `table_bytes()` | current cache footprint, bytes | Cheat Sheet |
| `empty_tables!` | `empty_tables!()` | reset the table cache | Cheat Sheet |

Deterministic unary/binary array calls use cached result tables (256 B unary,
64 KiB binary). Ternary tables tier by combined operand bitwidth: eager
(≤ 18 bits total), adaptive with LRU eviction (≤ 21 bits total), compute per
element at `K = 8`. Stochastic operations always compute per element and
consume one draw per projection.

## Block functions

| Function | Signature | Teaching page |
|---|---|---|
| `blocksize` | `blocksize(b)` | Cheat Sheet |
| `scaleformat` | `scaleformat(b)` | Cheat Sheet |
| `elemformat` | `elemformat(b)` | Cheat Sheet |
| `ConvertFromBlock` | `ConvertFromBlock(fr, ρ, b)` | Cheat Sheet |
| `ConvertToBlock` | `ConvertToBlock(fs, fr, ρ, values_tuple, scale)` | Cheat Sheet |
| `ConvertToBlockMaxAbsFinite` | `ConvertToBlockMaxAbsFinite(fs, fr, scale_ρ, element_ρ, values_tuple)` | Cheat Sheet |
| `BlockReduceAdd` | `BlockReduceAdd(fr, ρ, b)` | Cheat Sheet |
| `BlockReduceMultiply` | `BlockReduceMultiply(fr, ρ, b)` | Cheat Sheet |
| `BlockDotProduct` | `BlockDotProduct(fr, ρ, bx, by)` | Cheat Sheet |

`BlockReduceAdd`, `BlockReduceMultiply`, and `BlockDotProduct` perform their
lane products and accumulation exactly, projecting once at the end — no
hidden intermediate rounding.

### Generated `BlockOp` / `ScaledOp` pattern

Every scalar operation except `Convert` has a generated block form and a
generated scaled form.

| Pattern | Signature |
|---|---|
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
|---|---|---|
| Construct | `PackedVector(v)` | `v::AbstractVector{F}` |
| Index (read) | `pv[i]` | returns an `F` |
| Index (write) | `pv[i] = x` | `x::F` |
| Collect | `collect(pv)` | materializes a `Vector{F}` |
| `sizeof` rule | `sizeof(pv.data)` | `ceil(length(pv) * bitwidth(F) / 8)` bytes, rounded to the storage word |
| `vmap` acceptance | `vmap(:Op, F, ρ, pv)` | accepted directly; tiles unpack internally |

`PackedVector` stores each code point in exactly `bitwidth(F)` bits.
Computation unpacks tiles internally; packed arithmetic is deliberately not
in-place — store packed, compute unpacked.

Where next: [Cheat Sheet](cheatsheet.md), [Tutorial 3: Operations & Arrays](tutorial3_arrays.md),
[How-To: Use Blocks to Track Dynamic Range](howto_blocks_dynamic_range.md).
