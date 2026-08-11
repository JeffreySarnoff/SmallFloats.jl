# Encoding and Decoding

The public promise is simple: a code point identifies one exact datum, and
decoding that identity never rounds. The implementation chooses different
carriers and decode strategies by format, but those choices may change cost,
never meaning.

## Invariant

For every valid code point `c` of a concrete representation `T`:

```julia
codepoint(SmallFloats.rawvalue(T, c)) == c
```

and `decode(SmallFloats.rawvalue(T, c))` equals the P3109 datum assigned to `c`. For every
non-NaN datum, encoding the exact decoded value returns the corresponding code
point under an exact-grid projection.

## Representation and storage

`Binary{K,P,SGN,EXT}` describes the abstract format. A concrete alias such as
`Binary8p4se` supplies the machine representation. Code points use `UInt8` at
`K ≤ 8` and `UInt16` above that split; unused high bits are not part of the
format's identity.

The bit layout follows the draft: sign where present, biased exponent, and
trailing significand. The negative-zero slot names the format's single NaN;
there is one zero rather than signed zeros.

## Decode policies

`decodepolicy(T)` selects an implementation shape.

For `K ≤ 8`, decoding uses a generated constant tuple containing all datums.
The tuple is built from the computational decoder, so lookup and computation
have one source of meaning. A runtime decode becomes one indexed load, while a
constant input can fold completely.

Above `K = 8`, materializing a 65,536-entry constant for every format is not a
useful trade. The computational decoder runs directly.

## Datum carriers

The decoded datum must be exact even when its magnitude exceeds `Float64`.
`datumcarrier(T)` selects among three carrier rungs from format properties:

- rung 1 uses `Float64` where its normal range and precision cover every datum;
- rung 2 uses `Float128` when greater exponent room is required;
- rung 3 uses an exact dyadic carrier when a hardware-style binary float cannot
  cover the format exactly.

The caller does not select the datum carrier. The invariant is stronger than
“most values fit in Float64”: every selected carrier is exact for every datum
of its format.

## Ordering keys

Comparisons and counting sort use an unsigned integer key obtained by a
sign-magnitude fold. Key zero is reserved for the single NaN, which P3109's
total order places below the other datums. Every ordinary datum key is at least
one.

The key type has room for the entire code lattice plus the NaN sentinel. The
mapping is monotone, so comparison and sort can operate on integers without
decoding floating values.

## Source map

- format parameters, representations, masks, and carrier traits:
  `src/formats.jl`;
- computational decoding and order keys: `src/decode_encode.jl`;
- wide exact datum carriers: `src/dyadic.jl` and carrier
  support files;
- constructor normalization and representation aliases: format and conversion
  entry points in `src/`.

## Evidence

The verification suite compares computational decoding against an independent
big-float transliteration over the supported lattice. It also checks lookup
versus computation, round trips, carrier widening, ordering monotonicity, and
the format/code-point algebra.

## Extension seam

A new representation or carrier policy must preserve the public invariant and
add equivalence tests against an existing wider path. Do not make a carrier
choice from runtime caller preference; that would turn representation into
semantics.
