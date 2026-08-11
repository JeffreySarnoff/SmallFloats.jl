# Installation

A working install in about five minutes.

## Requirements

- **Julia 1.12** or later.
- **`Quadmath`** (libquadmath's `Float128`) is a hard dependency. It is used only
  inside the oracle and exact-fallback paths — never where it could change a
  result.

## Install

The package is not yet registered, so install by URL:

```
pkg> add https://github.com/JeffreySarnoff/SmallFloats.jl
```

Append `#main` (or a tag/commit) to pin a revision:

```
pkg> add https://github.com/JeffreySarnoff/SmallFloats.jl#main
```

For an editable install, `pkg> dev https://github.com/JeffreySarnoff/SmallFloats.jl`
clones into `~/.julia/dev`, or use an existing clone:

```
pkg> dev path/to/SmallFloats.jl
```

## Smoke test

Thirty seconds to confirm everything is in place:

```julia-repl
julia> using SmallFloats

julia> Binary8p4se(1.6) + Binary8p4se(0.25)
Binary8p4se(1.875 ≡ 0x47)

julia> conformance() !== nothing
true
```

The first line proves the projection engine is live (1.6 rounds to 1.625, plus
0.25, lands exactly on 1.875); the second proves the conformance machinery is.
