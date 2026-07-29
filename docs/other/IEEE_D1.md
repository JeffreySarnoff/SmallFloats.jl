<!--
IEEE P3109/D1 (July 2026) draft — plain-Markdown rendering of IEEE_P3109_D1.md.
Derived by mechanical markup conversion only; wording, spacing and line breaks are unchanged.
Notation: **bold**  *italic*  _{subscript}  ^{superscript}  <u>underline</u>.
Fixed-width alignment inside operation tables and brace stacks is significant.
Section index: IEEE_P3109.json
-->






**Draft for Arithmetic Formats for Machine Learning**



**Abstract:** This standard defines binary arithmetic and data formats optimized for machine learning domains. Compact
binary floating-point interchange formats are specified, parameterized by bitwidth, precision, signedness, and domain.
Operations including rounding with saturation modes and conversion between P3109 formats and IEEE Std 754™ for-
mats are defined. A consistent and flexible arithmetic framework is provided for machine learning systems in hardware
and software implementations.

**Keywords:** floating-point formats, floating-point operations, 3109


**Contents**

**1 Overview**                                                                                **11**
   1.1 Scope . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 11
   1.2 Word usage . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 11
**2 Definitions and abbreviations**                                                               **12**
   2.1 Definitions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 12
   2.2 Abbreviations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 13
   2.3 Mathematical notations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 13

**3 Floating-point formats**                                                                     **14**
   3.1 Formats . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 14
   3.2 Naming . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 15

**4 Operations**                                                                               **16**
   4.1 General  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 16
   4.2 Projection specifications  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 16
   4.3 Operation definitions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 17
        4.3.1 Operation definition schema . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 17
        4.3.2 Pattern-matching declarations  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 17
   4.4 Approximate implementations  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 19
   4.5 Conforming implementations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 20
   4.6 Conformance declarations  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 22
   4.7 Internal functions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 23
        4.7.1 General . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 23
        4.7.2 Decoding . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 23
        4.7.3 Projection . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 24
        4.7.4 Rounding to precision  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 25
        4.7.5 Saturation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 27
        4.7.6 Encoding . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 28
   4.8 Decoding and encoding for external formats . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 29
        4.8.1 Decoding . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 29
        4.8.2 Encoding . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 29
   4.9 Converting between formats  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 30
        4.9.1 Conversion . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 30
   4.10 Arithmetic operations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 31
        4.10.1 Absolute value, Negation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 31
        4.10.2 Copying the sign . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 32
        4.10.3 Addition, Subtraction . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 33
        4.10.4 Multiplication . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 34
        4.10.5 Division . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 35
        4.10.6 Fused Multiply–Add . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 36
        4.10.7 Fused Add–Add  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 37
        4.10.8 Square root, Reciprocal, Reciprocal square root . . . . . . . . . . . . . . . . . . . . . . . . . 38
        4.10.9 Logarithm, Exponentiation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 39
        4.10.10 Trigonometric functions  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 40
        4.10.11 Hyperbolic functions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 41
        4.10.12 Trigonometric *π*-functions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 42
        4.10.13 Softplus . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 43
        4.10.14 Hypotenuse . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 44
        4.10.15 Inverse tangent of two variables  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 45


                                                  8
        4.10.16 Inverse tangent of two variables (*π*-variant) . . . . . . . . . . . . . . . . . . . . . . . . . . . 46
   4.11 Extrema . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 47
        4.11.1 Minimum and maximum, and number variants  . . . . . . . . . . . . . . . . . . . . . . . . . 47
        4.11.2 Minimum and maximum magnitude, and number variants  . . . . . . . . . . . . . . . . . . . 48
        4.11.3 Minimum and maximum finite variants  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 49
        4.11.4 Clamping . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 50
   4.12 Comparisons  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 51
        4.12.1 Total order predicate . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 52
        4.12.2 Comparison operator symbols . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53
   4.13 Predicates and classification  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 54
        4.13.1 Classifier operation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 55
   4.14 Format-level operations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 56
   4.15 Projection specification operations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 56
   4.16 Next greater than and next less than  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 57

**5 Block operations**                                                                          **58**
   5.1 Internal functions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 59
        5.1.1 Decoding . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 59
        5.1.2 Projection . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 60
   5.2 Conversion of blocks . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 61
        5.2.1 Conversion from a block . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 61
        5.2.2 Conversion to a block . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 62
        5.2.3 Conversion to a block with scale factor computation  . . . . . . . . . . . . . . . . . . . . . . 63
   5.3 Block reduction operations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 64
        5.3.1 Sum and product . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 64
        5.3.2 Dot product . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 65
   5.4 Elementwise operations on blocks  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 66
   5.5 Scaled operations via block operations . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 67
**Appendices**                                                                                 **68**

**Annex A (informative) Rationales and discussion**                                                  **68**
   A.1 General  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 68
   A.2 Not a number (NaN)  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 68
   A.3 Zero . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 68
   A.4 Infinities . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 69
   A.5 Exponent bias . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 71
   A.6 Subnormals . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 71

**Annex B (informative) Encoding**                                                                **72**
   B.1 Value tables . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 73
**Annex C (informative) Value tables for K=2**                                                      **75**

**Annex D (informative) Examples of approximation declarations**                                     **76**
   D.1 Example: Approximate implementation of Exp  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 76
   D.2 Example: Approximate implementation of BlockDotProduct . . . . . . . . . . . . . . . . . . . . . . 76
**Annex E (informative) Recommendations for reduction accuracy specifications**                         **77**
   E.1 BlockReduceAdd . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 77
   E.2 BlockReduceMultiply . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 77
   E.3 BlockDotProduct . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 78

**Annex F (informative) External formats**                                                         **79**

**Annex G (informative) Operation groups**                                                        **80**
**Annex H (informative) Bibliography**                                                            **82**

# 1 Overview

## 1.1 Scope

This standard defines a binary arithmetic and data format for machine learning-optimized domains. It also specifies the
default handling of exceptions occurring in this arithmetic. This standard provides a consistent and flexible arithmetic
framework optimized for Machine Learning Systems (MLSs) in hardware and/or software implementations to minimize
the work required to make MLSs interoperable with each other as well as other dependent systems. This standard is
aligned with the IEEE Std 754-2019 Standard for Floating-Point Arithmetic.

## 1.2 Word usage
The word *shall* indicates mandatory requirements strictly to be followed in order to conform to the standard and from
which no deviation is permitted (*shall* equals *is required to*).

The word *should* indicates that among several possibilities one is recommended as particularly suitable, without men-
tioning or excluding others; or that a certain course of action is preferred but not necessarily required (*should* equals *is*
*recommended that*).

The word *may* is used to indicate a course of action permissible within the limits of the standard (*may* equals *is permitted*
*to*).
The word *can* is used for statements of possibility and capability, whether material, physical, or causal (*can* equals *is*
*able to*).

# 2 Definitions and abbreviations

## 2.1 Definitions

For the purposes of this document, the following terms and definitions apply.
**bitwidth:** the minimum number of bits required to encode a floating-point value in a given format, denoted K.

**block:** a pair comprising a scale factor and a sequence of one or more floating-point values.

**canonical form:** of a nonzero finite floating-point datum *X* in format *f*, its representation as sgn(*X*)×*S*×2^{1−P}×2^{*E*}
for minimal integer *E >* −B, and nonnegative integer *S*, where P = PrecisionOf(*f*) and B = ExponentBiasOf(*f*).
For zero, *S* = 0 and *E* = 0.
**closed extended reals:** set denoted ℝ^{*ω*}, consisting of the real numbers augmented with positive infinity, negative in-

finity, and not-a-number: ℝ^{*ω*} := ℝ ∪ {−∞, +∞, NaN}.
**code point:** integer in the range 0 to 2^{K} − 1 that encodes a floating-point datum occurring in a format of bitwidth K.

**datum:** see floating-point datum.

**datum set:** the subset of the closed extended reals representable in a given format *f*, denoted D_{*f*}.

**defined operation:** operation whose signature and behavior are defined by this standard.
**defined result:** result of a defined operation for a given set of operands.

**domain:** format-defining parameter in {Finite, Extended} that specifies whether the format’s datum set includes in-
finities.

**encoding:** a format’s unique mapping from its datum set to code points.

**exponent:** of a floating-point datum *X* expressed in canonical form as sgn(*X*) × *S* × 2^{1−P} × 2^{*E*}, the integer *E*.
**exponent bias:** format-specific constant, denoted B, used in encoding and decoding the exponent field.

**exponent field:** the integer value of the biased exponent of a code point.

**floating-point datum:** a closed extended real value representable in a given format, an element of the datum set of the
format.

**floating-point value:** a code point representing a floating-point datum in a given format.
**format:** binary floating-point representation parameterized by bitwidth, precision, signedness, and domain.

**format-defining parameters:** bitwidth (K), precision (P), signedness (Σ), and domain (Δ).

**NaN (Not a Number):** special non-numeric value used to represent undefined or unrepresentable results.

**normal:** finite floating-point datum whose significand *S* satisfies 2^{P−1} ≤ *S <* 2^{P}. A floating-point value is normal
iff its datum is normal.
**operand:** an argument to an operation.

**operation:** a set of operation specializations parameterized over operation parameters, e.g., format, projection speci-
fication, and constants such as block size.

**operation specialization:** mapping from a tuple of operands to one or more results.
**precision:** the bitwidth of the trailing significand field plus one, denoted P.

**projection specification:** pair (rounding mode, saturation mode) that determines how a general closed extended real
is projected to a datum in a format’s datum set.

**rounded value:** a closed extended real value, the result of rounding (via *ω*RoundToPrecision, §4.7.4). If finite, it is
of the form *S* × 2^{*E*} for integers *S* and *E*.

**rounding mode:** attribute of a projection specification that determines how a closed extended real value is rounded to
a rounded value.
**saturation mode:** attribute of a projection specification that determines how rounded values outside the finite range
of the target format are projected to a datum.

**scale factor:** multiplicative factor applied to all elements in a block.

**significand:** of a floating-point datum *X* expressed in canonical form as sgn(*X*) × *S* × 2^{1−P} × 2^{*E*}, the integer *S*.

**signed format:** format that represents signed numbers and has signedness parameter Signed.

**signedness:** format-defining parameter in {Signed, Unsigned} that specifies whether the format includes negative da-
tums.
**special value:** floating-point values encoding zero, ±∞, and NaN.

**subnormal:** finite floating-point datum whose significand *S* satisfies 0 *< S <* 2^{P−1}. A floating-point value is sub-
normal iff its datum is subnormal.

**trailing significand field:** of a code point *x* in format *f*, the value *x* mod 2^{P−1} where P is the precision of the format *f*.

**unsigned format:** format that represents non-negative numbers and has signedness parameter Unsigned.
**value set:** the set of floating-point values for a format.


## 2.2 Abbreviations
FAA      fused add–add
FMA      fused multiply–add
MLS      machine learning system
P3109     IEEE Working Group P3109 (Standard for Arithmetic Formats for Machine Learning)
IEEE-754 IEEE Std 754-2019™


## 2.3 Mathematical notations
IsOdd(*I*) is true if integer *I* is odd, false otherwise.

IsEven(*I*) is true if integer *I* is even, false otherwise.
The number of elements in a set *S* is denoted #*S*.

The signum function sgn(*X*) is defined as −1 for *X <* 0, 0 for *X* = 0, and +1 for *X >* 0.

Division of nonnegative integers is denoted by *x* ÷ *y*, modulo by *x* mod *y*.
Comments are right-justified and parenthesized.                                            (A comment)

# 3 Floating-point formats

## 3.1 Formats

Define the set of *closed extended reals* to be the reals augmented with positive and negative infinity and NaN:
                                   ℝ^{*ω*} := ℝ ∪ {−∞, +∞, NaN}

NOTE 1—This set contains a single NaN value (see Annex A.2). There is no negative zero in this set (see Annex A.3).
A *floating-point format* *f* comprises a *datum set* D_{*f*} and an *encoding*. The datum set is a subset of the closed extended
reals. The *encoding* is a unique bijective mapping from D_{*f*} to integer *code points* 0 . . . 2^{K} − 1, where K is the bitwidth
of the format.

A floating-point format has four *format-defining* parameters:

   • Bitwidth K, an integer greater than two;^{1}
   • Precision P, an integer greater than zero. P shall be strictly less than K (0 < P < K) for signed formats, and
     less than or equal to K (0 < P ≤ K) for unsigned formats;
   • Signedness Σ, in {Signed, Unsigned};
   • Domain Δ, in {Finite, Extended}.^{2}

The *exponent bias* is derived from the format-defining parameters.^{3} For signed formats, the exponent bias shall be
B = 2^{K−P−1}. For unsigned formats, the exponent bias shall be B = 2^{K−P}.
A *floating-point datum* in a format *f* is an element of D_{*f*}, i.e., a closed extended real that encodes to a code point in *f*.

A *floating-point value* is a code point representing a floating-point datum in a given format. The code points for infinities
are denoted Inf and −Inf.

NOTE 2—While a floating-point value is synonymous with a code point, the term is used in contexts where a format is
associated with the value. For example, in an operation definition, a value might be declared “*x*: floating-point value,
format *f*”. In such contexts, the interpretation of a real constant, e.g., 2.0, as a floating-point value is to be read as
*ω*Encode_{*f*}(2.0). In cases where the format may be ambiguous, a real constant may be subscripted with its associated
format, e.g., *X*_{*f*} = *ω*Encode_{*f*}(*X*). For example, 2.0_{Binary8p4se} = *ω*Encode_{Binary8p4se}(2.0) represents the code point
0x48. Similarly, a format may be associated to infinity or NaN, e.g., Inf_{Binary8p4se} = ∞_{Binary8p4se} represents the code
point 0x7F.
The word *finite* applied to a datum signifies that the datum is not ±∞ or NaN. Applied to a value, it signifies that the
value encodes a finite datum.

A finite floating-point datum is a real number whose absolute value has the form

                                        *S* × 2^{1−P} × 2^{*E*},
where the *exponent* *E* is an integer such that *E >* −B, and *S*, the *significand*, is an integer 0 ≤ *S <* 2^{P}. This
decomposition is made canonical for nonzero values by choosing the smallest *E >* −B. For *S* = 0, *E* is chosen to
be 0. The datum is *normal* if 2^{P−1} ≤ *S <* 2^{P}. The datum is *subnormal*^{4} if 0 *< S <* 2^{P−1}. The datum zero is neither
normal nor subnormal.

The *trailing significand* is the integer *S* mod 2^{P−1}.

NOTE 3—The encoding of formats is described in §4.7.6; properties of encodings are described in Annex B.
  ^{1}See Annex C for rationale for K > 2.
  ^{2}See Annex A.4 for rationale for parameterization of domain.
  ^{3}See Annex A.5 for rationale for this choice of exponent bias.
  ^{4}See Annex A.6 for rationale for inclusion of subnormals.

## 3.2 Naming
Formats defined in this document shall be named Binary{K, P, Σ, Δ}.

A shortened notation is also used to refer to specific formats: Binary⟨κ⟩p⟨*ψ*⟩⟨*σ*⟩⟨*δ*⟩ where the placeholders ⟨κ⟩ and ⟨*ψ*⟩
are decimal representations of the bitwidth K and precision P, respectively; signedness ⟨*σ*⟩ ∈ {s, u}, for signed and
unsigned; and domain ⟨*δ*⟩ ∈ {e, f} for extended and finite.

*Examples:*
   • The format “Binary12p7se” is a 12-bit signed, extended format with precision 7.

   • The format “Binary8p1uf” is an 8-bit unsigned, finite format with precision 1.

NOTE—The term “binary” indicates that the finite datums are integer multiples of (positive or negative) powers of
two.

# 4 Operations

## 4.1 General

An *operation* is a parameterized mapping from a tuple of operands to one or more *results*. An operation is denoted by
an identifier, followed by a list of *operation parameter* names, either as subscripts or between angle brackets.
An *operation specialization* supplies values for the parameters of an operation. An operation specialization is denoted
by an identifier, followed by a list of operation parameter values, either as subscripts or between angle brackets.

*Example:*
  Exp*<f*_{*x*}*, f*_{*r*}*, ρ>* is an operation, and Exp<Binary8p4se, Binary8p3ue, (NearestTiesToEven, SatNone)> is a spe-
  cialization of this operation.
An *auxiliary operation* may be defined which operates on the closed extended reals. Such operations are named with
the prefix *ω*. These operations handle non-finite values explicitly and immediately, ensuring that all arithmetic and
other mathematical operations are over (finite) real values.

NOTE 1—Specifications operate on code points using integer arithmetic (e.g., divide and modulo) operations. These
operations may be performed in any equivalent manner, for example bit shifting and masking.

NOTE 2—Operations on floating-point values are defined via conversion to the closed extended reals, on which the
mathematical operation is performed, before projection into the floating-point datum set via rounding and saturation.
The definitions in this document are specifications of behavior.
NOTE 3—The operation definitions herein describe no side effects, such as the setting of flags, or the triggering of
interrupts, and do not return values other than the defined result. Generally, NaN is returned when operands are out of

domain (e.g., Log(−1.0)).
NOTE 4—Many properties of the formats and operations are formally verified [15, 2]. Auxiliary operations are auto-
matically extracted from a formal specification [15].


## 4.2 Projection specifications
A *projection specification* is a pair (rounding mode, saturation mode).

Rounding modes, as specified in §4.7.4, describe the mapping of closed extended real values to *rounded values* as
follows:
  NearestTiesToEven   Round to nearest, ties to even
  NearestTiesToAway  Round to nearest, ties away from zero
  TowardPositive      Round toward positive
  TowardNegative     Round toward negative
  TowardZero         Round toward zero
  ToOdd             Round to odd

  Stochastic[A, B, C]   Stochastic rounding, with variants A, B, and C as defined in §4.7.4
Saturation modes, as specified in §4.7.5, describe the mapping of rounded values to datums as follows:

  SatFinite     All rounded values are clamped to the representable finite range.
  SatPropagate Infinite rounded values are preserved if representable. All other rounded values are clamped to the
              representable range.
  SatNone     Out-of-range rounded values are replaced with the extremal finite datum, positive or negative infinity,
              or NaN, as governed by the rounding direction and the signedness of the target format.

## 4.3 Operation definitions
### 4.3.1 Operation definition schema

Operations are defined according to the following schema.

**Signature**
    Operation_{*p*1,...}(*x*_{1}, ...) → *r*
**Parameters**
    *p*_{1} : description of parameter 1
     ...

**Operands**
    *x*_{1} : description of operand 1
     ...

**Result**
     *r* : description of result

**Behavior**
An ordered sequence of *pattern-matching declarations* (see §4.3.2)

**Details**
An optional section listing additional aspects of the operation’s behavior.

### 4.3.2 Pattern-matching declarations

A pattern-matching declaration is of the form

    Operation(*x*_{1}, ...) → ...
describing the result of the operation given operands *x*_{1}, ....

In a sequence of pattern-matching declarations, the first matching pattern in the order presented in this document defines
the behavior for given operands.
The following notations facilitate concise specifications.

**4.3.2.1 Exact pattern**

Only the provided operands match.

*Example:*
      Operation(NaN, 0) → NaN

**4.3.2.2 Set inclusion**
Match for all *x* values in the given set.

*Example:*
      Operation(*x* ∈ {−Inf, Inf}*, y*) → *x*

**4.3.2.3 Wildcard match**

The ∗ symbol matches any value.

*Example:*
      Operation(∗, 0) → 0

**4.3.2.4 Explicit parameters introduced in result expression**
A reference to an operation specialization in the result expression uses explicit parameters.

*Example:*
      Operation(*x, y*) → Operation_{*fx,fy,fr*}(*x, y*)


*Example:*
  The definition of the operation Log, taken from §4.10.9:
  **Signature**

      Log_{*fx,fr,ρ*}(*x*) → *r*
  **Parameters**
      *f*_{*x*} : format of operand *x*
      *f*_{*r*} : format of result *r*
       *ρ* : projection specification

  **Operands**
      *x* : floating-point value, format *f*_{*x*}
  **Result**

       *r* : floating-point value, format *f*_{*r*}
  **Behavior**
      *ω*Log(NaN) → NaN
      *ω*Log(−∞) → NaN
      *ω*Log(+∞) → +∞
      *ω*Log(*X*) if *X <* 0 → NaN
      *ω*Log(0) → −∞
      *ω*Log(*X*) → log_{*e*} *X*

      Log(*x*) → *ω*Project_{*fr,ρ*}(*ω*Log(*ω*Decode_{*fx*}(*x*)))

## 4.4 Approximate implementations
An operation is a *numeric operation* if one or more of its results is a floating-point value.

An operation’s *defined results* are the result values specified in the definitions in this document.

For numeric operations, a system that provides approximate implementations shall declare them as *κ-approximate*
operations as follows.^{5} A *κ*-approximate implementation shall compute values whose maximum difference from the
defined results does not exceed *κ* *value steps*, as defined in this section.
A numeric operation *a*, for a given set of parameters, has a defined result *â*(*x*) for operands *x*. A *κ*-approximate
implementation produces a floating-point value *ã*(*x*), which for some operands *x* has *ã*(*x*) ≠ *â*(*x*).

Where an approximate implementation does not “match on NaNs”, that is where IsNaN(*â*(*x*)) ≠ IsNaN(*ã*(*x*)) for any
input *x*, then it shall declare *κ* = NaN.

Define
                        ⎧True  if IsNaN(*x*) and IsNaN(*y*)
                        ⎨True  if IsFinite(*x*) and IsFinite(*y*)
   MatchOnInfinity(*x, y*) =
                        ⎪True  if IsInfinite(*x*) and IsInfinite(*y*) and IsSignMinus(*x*) = IsSignMinus(*y*)
                        ⎩False  otherwise

Where an approximate implementation matches on NaNs but does not match on infinities, that is where
MatchOnInfinity(*â*(*x*), *ã*(*x*)) is false for any input *x*, then it shall declare *κ* = ∞.
For operations which match on NaNs and infinities, the value of *κ* is defined as follows.

    Let the set of operands producing finite results be *I*, so that for all *x* ∈ *I* we have *â*(*x*) ∈ *V* , where *V* is the
    result format’s finite value set. For all *x* ∈ *I*, *ã*(*x*) shall be in *V* .

    The value of *κ* will be the maximum over all operands *x* ∈ *I* of the number of values in *V* between *ã*(*x*) and
    *â*(*x*) inclusive of the former, exclusive of the latter. Formally,^{6}

                          *κ* = max_{*x*∈*I*} #(((*â*(*x*), *ã*(*x*)] ∪ [*ã*(*x*), *â*(*x*))) ∩ *V*).

    The value of *κ* will in general be specific to each operation specialization, for example a system may supply
    implementations of Add_{*fx,fy,fr,ρ*} where *κ* depends on *f*_{*r*}.

    For each *κ*-approximate operation specialization, *κ* shall be specified. Such a specification may be over *I* or
    over a covering union of disjoint subsets of *I*, written

                *κ* ∈ {*I*₁ : *κ*_{*I*₁}, ..., *I*ₙ : *κ*_{*I*ₙ}} where *I* = ⋃ᵢ *I*ᵢ and ∀*i* ≠ *j* : *I*ᵢ ∩ *I*ⱼ = {}.

    This may be attested by any proof method, including direct computation.
Operations returning multiple floating-point values shall declare *κ* as follows, where *κ*[*m*] is *κ* for the operation which
returns the *m*^{th} return value, that is *ã*(*x*)[*m*]. If any *κ*[*m*] is NaN, *κ* = NaN shall be declared. Otherwise, if any *κ*[*m*]
is infinite, *κ* = ∞ shall be declared. If all *κ*[*m*] are finite, *κ* = max_{*m*} *κ*[*m*] shall be declared.

Approximate implementations shall be named differently from the name of the operation that is approximated.

Additional accuracy declarations may be supplied.^{7}
  ^{5}See Annex D for worked examples of approximation declarations.
  ^{6}The intervals (*ℓ, u*] and [*ℓ, u*) where *u* ≤ *ℓ* are empty sets.
  ^{7}See Annex E for examples.

## 4.5 Conforming implementations
An implementation shall provide the following operation specializations, where the two format sets F_{4} and F_{8} and the
external format^{8} set F_{*X*} are defined as

                                 F_{8}  =  {Binary8p4se, Binary8p3se}
                                 F_{4}  =  {Binary4p2sf}

                           {} ≠ F_{*X*}  ⊆  {binary32, binary16, BFloat16}
with operation specializations as follows, for all *f*, *f*_{1}, *f*_{2}, and *f*_{*r*} in the indicated sets, and *ρ* = (NearestTiesToEven, SatNone).

Convert*<f, f*_{*r*}*, ρ>*      where  {*f, f*_{*r*}} ⊂ F_{4} ∪ F_{8} ∪ F_{*X*}

Negate*<f, f, ρ>*        where  *f* ∈ F_{4} ∪ F_{8}
Abs*<f, f, ρ>*           where  *f* ∈ F_{4} ∪ F_{8}
Recip*<f, f*_{*r*}*, ρ>*        where  {*f, f*_{*r*}} ⊂ F_{4} ∪ F_{8} ∪ F_{*X*}

Add*<f*_{1}*, f*_{2}*, f*_{*r*}*, ρ>*      where  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                        and  *f*_{*r*} ∈ F_{8} ∪ F_{*X*}
Subtract*<f*_{1}*, f*_{2}*, f*_{*r*}*, ρ>*  where  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                        and  *f*_{*r*} ∈ F_{8} ∪ F_{*X*}
Multiply*<f*_{1}*, f*_{2}*, f*_{*r*}*, ρ>*  where  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                        and  *f*_{*r*} ∈ F_{8} ∪ F_{*X*}

FMA*<f*_{1}*, f*_{2}*, f*_{*r*}*, f*_{*r*}*, ρ>*  where  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                        and  *f*_{*r*} ∈ F_{*X*}
FAA*<f*_{1}*, f*_{2}*, f*_{*r*}*, f*_{*r*}*, ρ>*   where  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                        and  *f*_{*r*} ∈ F_{*X*}
MinmaxOp*<f, f, f, ρ>*  where  *f* ∈ F_{4} ∪ F_{8}
                                          ⎧ Minimum,                 Maximum,                ⎫
                                          ⎪ MinimumNumber,           MaximumNumber,          ⎪
                        and  MinmaxOp ∈ ⎨ MinimumMagnitude,         MaximumMagnitude,        ⎬
                                          ⎪ MinimumMagnitudeNumber,  MaximumMagnitudeNumber, ⎪
                                          ⎩ MinimumFinite,             MaximumFinite         ⎭

For CompareOp ∈ {CompareLess, CompareLessEqual, CompareEqual, CompareGreater, CompareGreaterEqual} the
following operation specializations shall be provided:

CompareOp*<f, f >*  where  *f* ∈ F_{4} ∪ F_{8} .

For each format in F_{4} ∪ F_{8}, the following operation specializations shall be provided:
  IsZero, IsOne, IsNaN, IsInfinite, IsFinite, IsSignMinus, IsNormal, IsSubnormal, NextGreaterThan, NextLessThan.

For each format in F_{4} ∪ F_{8} ∪ F_{*X*}, the following format-level operation specializations shall be provided:

  BitwidthOf, PrecisionOf, SignednessOf, DomainOf,
  ExponentBitwidthOf, TrailingSignificandBitwidthOf, ExponentBiasOf,
  MaxFiniteOf, MinFiniteOf, MinPositiveOf, MaxSubnormalOf, MinNormalOf.



  ^{8}See §4.14 about external formats.

In addition, scaled operations, as defined in §5.5, shall be provided as follows, with F_{*s*} = {Binary8p1uf}:

  ScaledAdd<(*f*_{*s*}*, f*_{1}), (*f*_{*s*}*, f*_{2})*, f*_{*r*}*, ρ>*      where  *f*_{*s*} ∈ F_{*s*}
                                       and  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                                       and  *f*_{*r*} ∈ F_{8} ∪ F_{*X*}

  ScaledSubtract<(*f*_{*s*}*, f*_{1}), (*f*_{*s*}*, f*_{2})*, f*_{*r*}*, ρ>*  where  *f*_{*s*} ∈ F_{*s*}
                                       and  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                                       and  *f*_{*r*} ∈ F_{8} ∪ F_{*X*}
  ScaledMultiply<(*f*_{*s*}*, f*_{1}), (*f*_{*s*}*, f*_{2})*, f*_{*r*}*, ρ>*  where  *f*_{*s*} ∈ F_{*s*}
                                       and  {*f*_{1}*, f*_{2}} ⊂ F_{4} ∪ F_{8}
                                       and  *f*_{*r*} ∈ F_{8} ∪ F_{*X*}

Note that the choice of subset for F_{*X*} is implementation-defined.

## 4.6 Conformance declarations
Note that an implementation provides a subset of operation specializations for a subset of operations defined in this
standard.

Where an operation specialization is supplied, the implementation shall compute the same result as does the defined
operation specialization for all possible operand values. This may be attested by any proof method, including direct
computation.

Where an approximate implementation of an operation specialization is supplied, the implementation shall declare *κ*
as defined in §4.4. Such an implementation should use an implementation-specific identifier which indicates that the
implementation is approximate.
It is recommended that an implementation supply a means whereby a user may query the presence of an implementation
of a given operation specialization defined by a string representation.

*Example:*
  An implementation that supports an exponentiation operation which operates on 8-bit, signed, extended floating-
  point values with a precision of 3 or 4, with result precision always 4, and saturation to finite or no saturation. These
  operation specializations could be declared as follows:

  exp 8.3.to.8.4.finite: Exp<Binary8p3se, Binary8p4se, (NearestTiesToEven, SatFinite)>
  exp 8.4.to.8.4.finite: Exp<Binary8p4se, Binary8p4se, (NearestTiesToEven, SatFinite)>

  exp 8.3.to.8.4.inf: Exp<Binary8p3se, Binary8p4se, (NearestTiesToEven, SatNone)>
  exp 8.4.to.8.4.inf: Exp<Binary8p4se, Binary8p4se, (NearestTiesToEven, SatNone)>

## 4.7 Internal functions
### 4.7.1 General

The following subclauses define auxiliary operations which are referenced in the definitions of operations, but which
themselves are not required of a conforming implementation.

### 4.7.2 Decoding

**Signature**
    *ω*Decode_{*f*}(*x*) → *X*
    *ω*DecodeAux_{*f*}(Σ, Δ*, x*) → *X*

**Parameters**
     *f* : format of *x*
**Operands**

     *x* : floating-point value, in format *f*
**Result**

    *X* : floating-point datum, a closed extended real value in D_{*f*}
**Behavior**

    *ω*Decode(*x*) → *ω*DecodeExternal_{*f*}(*x*)  if *f* ∈ {binary64, binary32, binary16, BFloat16} ^{9}
    *ω*Decode(*x*) → *ω*DecodeAux_{*f*}(SignednessOf(*f*), DomainOf(*f*)*, x*)
    *ω*DecodeAux(Signed, ∗, 2^{K−1}) → NaN
    *ω*DecodeAux(Unsigned, ∗, 2^{K} − 1) → NaN

    *ω*DecodeAux(Signed, Extended, 2^{K−1} − 1) → +∞
    *ω*DecodeAux(Signed, Extended, 2^{K} − 1) → −∞
    *ω*DecodeAux(Unsigned, Extended, 2^{K} − 2) → +∞

    *ω*DecodeAux(Signed, Δ, 2^{K−1} *< x <* 2^{K}) → −*ω*DecodeAux_{*f*}(Signed, Δ*, x* − 2^{K−1})
    *ω*DecodeAux(∗, ∗*, x*) → *X*
             where

               *T* = *x* mod 2^{P−1}                                    (Trailing significand)
               *E*_{biased} = *x* ÷ 2^{P−1}                                      (Biased exponent)

                *X* = ⎧ (0 + *T* × 2^{1−P}) × 2^{1−B}       if *E*_{biased} = 0       (Subnormal and zero)
                    ⎩ (1 + *T* × 2^{1−P}) × 2^{*E*_{biased}−B}  otherwise                  (Normal)
              and

               P = PrecisionOf(*f*)
               B = ExponentBiasOf(*f*)

     where
       K = BitwidthOf(*f*)



  ^{9}See §4.14 about external formats.

### 4.7.3 Projection
Project closed extended real value to format *f*, applying specified rounding and saturation.

**Signature**
    *ω*Project_{*f,ρ*}(*X*) → *x*

**Parameters**
     *f* : target format
     *ρ* : projection specification

**Operands**
    *X* : closed extended real value
**Result**

     *x* : floating-point value in format *f*
**Behavior**

    *ω*Project(NaN) → NaN
    *ω*Project(*X*) → *x*
                   **where**
                     *R* = *ω*RoundToPrecision_{PrecisionOf(*f*),ExponentBiasOf(*f*),RoundOf(*ρ*)}(*X*)

                     *S* = *ω*Saturate_{*M*}^{lo}_{*,M*}^{hi}(SatOf(*ρ*), RoundOf(*ρ*)*, R,* Σ, Δ)
                     *x* = *ω*Encode_{*f*}(*S*)
                   **and**
                     Σ = SignednessOf(*f*)

                     Δ = DomainOf(*f*)
                     *M*^{lo} = *ω*Decode_{*f*}(MinFiniteOf(*f*))
                     *M*^{hi} = *ω*Decode_{*f*}(MaxFiniteOf(*f*))


NOTE 1—Under NearestTiesToEven rounding, *ω*Project has the property, shared with IEEE-754, that values be-
tween *M*^{hi} and the number half a unit in the last place above *M*^{hi} will project to *M*^{hi} because *ω*RoundToPrecision
precedes saturation.
NOTE 2—Under NearestTiesToEven rounding, subnormals are handled following IEEE-754, for example, values
strictly between the smallest subnormal and its half are rounded to the smallest subnormal, while values of magnitude
below or equal to half that of the smallest subnormal are rounded to zero.

### 4.7.4 Rounding to precision
Convert a closed extended real value to a closed extended real value expressible (where finite) as an integer multiple
of a power of two.

NOTE— Where *X* is nonzero and finite, the returned value with a given precision P and exponent bias B, is of the
form sgn(*X*) × *S* × 2^{1−P} × 2^{*E*}, where *S* ∈ ℤ, 0 ≤ *S <* 2^{P}, and *E* ∈ ℤ with −B *< E*.

**Signature**
    *ω*RoundToPrecision_{P,B*,μ*}(*X*) → *Z*
**Parameters**

    P : precision
    B : exponent bias
     *μ* : rounding mode
**Operands**
    *X* : closed extended real value

**Result**
    *Z* : closed extended real value

**Behavior**
    *ω*RoundToPrecision(*X* ∈ {0, −∞, +∞, NaN}) → *X*
    *ω*RoundToPrecision(*X*) → *Z*
              where

                *Q* = max(⌊log_{2}(|*X*|)⌋, 1 − B) − P + 1        (Subnormals handled by max(·, 1 − B))
                *S̃* = |*X*| × 2^{−*Q*}                   (Real-valued significand, to be rounded to integer)
                         ⎧ ⌊*S̃*⌋ + 1  if RoundAway(*μ*)
                     *S* = ⎨
                         ⎩ ⌊*S̃*⌋      otherwise
                *Z* = sgn(*X*) × *S* × 2^{*Q*}

              and, for *ν* = *S̃* − ⌊*S̃*⌋:
                RoundAway(TowardZero) = False

                RoundAway(TowardPositive) = *ν >* 0 and *X >* 0
                RoundAway(TowardNegative) = *ν >* 0 and *X <* 0
                RoundAway(NearestTiesToAway) = *ν* ≥ 0.5
                RoundAway(NearestTiesToEven) = *ν* > 0.5 or (*ν* = 0.5 and not CodeIsEven)

                RoundAway(ToOdd) = *ν >* 0 and CodeIsEven
                RoundAway(StochasticA_{*N,R*}) = ⌊*ν* × 2^{*N*}⌋ + *R* ≥ 2^{*N*}
                RoundAway(StochasticB_{*N,R*}) = ⌊*ν* × 2^{*N*+1}⌋ + (2 × *R* + 1) ≥ 2^{*N*+1}

                RoundAway(StochasticC_{*N,R*}) = RNITE(*ν* × 2^{*N*}) + *R* ≥ 2^{*N*}
              and
                              ⎧ IsEven(⌊*S̃*⌋)                          if P > 1
                CodeIsEven = ⎨
                              ⎩ (⌊*S̃*⌋ = 0) or IsEven(*Q* + B)  if P = 1
                              ⎧ ⌊*X*⌋      if (*X* < ⌊*X*⌋ + 0.5) or (*X* = ⌊*X*⌋ + 0.5 and IsEven(⌊*X*⌋))
                RNITE(*X*) = ⎨
                              ⎩ ⌊*X*⌋ + 1  otherwise

**Details**
In stochastic rounding, random bits *R* are supplied as an unsigned integer in the range 0 ≤ *R <* 2^{*N*}, thus *N* is the
number of random bits.

NOTE 1—The quality of the random bits is not specified in this document.
NOTE 2—The variants StochasticA, StochasticB, StochasticC offer a balance between accuracy and complexity [3].

NOTE 3—The notation StochasticA  _{∗} may be used to indicate that *N* random bits are supplied but not further spec-
ified.                         *N,*

NOTE 4—The intermediate value *S* may be set to 2^{P}, which might appear to preclude its representation in P − 1 bits
of explicit significand, but the computed real value is represented as the first number in the next binade.

### 4.7.5 Saturation
Saturate closed extended real to ±∞, or to maximum/minimum finite value.

**Signature**
    *ω*Saturate_{*M*}^{lo}_{*,M*}^{hi}(Sat, Round*, X,* Σ, Δ) → *Z*

**Parameters**
  *M*^{lo} : minimum finite value
  *M*^{hi} : maximum finite value

**Operands**                                       **Result**
   Sat : saturation mode                                *Z* : closed extended real value
Round : rounding mode
    *X* : closed extended real value
    Σ : signedness in {Signed, Unsigned}
    Δ : domain in {Finite, Extended}


**Behavior**
    *ω*Saturate(∗, ∗, NaN, ∗, ∗) → NaN
    *ω*Saturate(∗, ∗*, X,* ∗, ∗) if *M*^{lo} ≤ *X* and *X* ≤ *M*^{hi} → *X*

    *ω*Saturate(SatFinite, ∗, +∞, ∗, ∗) → *M*^{hi}
    *ω*Saturate(SatFinite, ∗, −∞, ∗, ∗) → *M*^{lo}
    *ω*Saturate(SatFinite, ∗*, X,* ∗, ∗) if *X < M*^{lo} → *M*^{lo}
    *ω*Saturate(SatFinite, ∗*, X,* ∗, ∗) if *X > M*^{hi} → *M*^{hi}

    *ω*Saturate(SatPropagate, ∗, +∞, ∗, Extended) → +∞
    *ω*Saturate(SatPropagate, ∗, +∞, ∗, ∗) → *M*^{hi}
    *ω*Saturate(SatPropagate, ∗, −∞, Signed, Extended) → −∞
    *ω*Saturate(SatPropagate, ∗, −∞, ∗, ∗) → *M*^{lo}
    *ω*Saturate(SatPropagate, ∗*, X,* ∗, ∗) if *X < M*^{lo} → *M*^{lo}
    *ω*Saturate(SatPropagate, ∗*, X,* ∗, ∗) if *X > M*^{hi} → *M*^{hi}

    *ω*Saturate(SatNone, TowardZero or TowardNegative*, X,* ∗, ∗) if *X > M*^{hi} and *X* ≠ +∞ → *M*^{hi}
    *ω*Saturate(SatNone, TowardZero or TowardPositive*, X,* ∗, ∗) if *X < M*^{lo} and *X* ≠ −∞ → *M*^{lo}
    *ω*Saturate(SatNone, ∗, +∞, ∗, Extended) → +∞
    *ω*Saturate(SatNone, ∗, −∞, Signed, Extended) → −∞
    *ω*Saturate(SatNone, ∗, −∞, Unsigned, Extended) → NaN
    *ω*Saturate(SatNone, ∗*, X,* Signed, Extended) if *X < M*^{lo} → −∞
    *ω*Saturate(SatNone, ∗*, X,* Unsigned, Extended) if *X < M*^{lo} → NaN
    *ω*Saturate(SatNone, ∗*, X,* ∗, Extended) if *X > M*^{hi} → +∞
    *ω*Saturate(SatNone, ∗, ∗, ∗, Finite) → NaN


NOTE—Whilst rounding precedes saturation in *ω*Project, the rounding mode is supplied to *ω*Saturate in order to
resolve cases where rounding direction requires a finite result. Saturation does not round any value.

### 4.7.6 Encoding
Encode a closed extended real value to a code point in format *f*. *ω*Encode is applied only to a value which is in the
datum set of *f*. This value may be produced by *ω*RoundToPrecision and *ω*Saturate, or the argument may be known
to be in the datum set, for example, the absolute value of a number already in the set.

**Signature**
    *ω*Encode_{*f*}(*X*) → *r*

**Parameters**
     *f* : target format

**Operands**
    *X* : floating-point datum, a closed extended real value in the datum set of format *f*
**Result**

     *r* : floating-point value, in format *f*
**Behavior**

    *ω*Encode(*X*) → *ω*EncodeExternal_{*f*}(*X*)  if *f* ∈ {binary64, binary32, binary16, BFloat16}
                         ⎧ 2^{K−1}  if Σ = Signed
    *ω*Encode(NaN) → ⎨
                         ⎩ 2^{K} − 1  if Σ = Unsigned
                         ⎧ 2^{K−1} − 1  if Σ = Signed
    *ω*Encode(+∞) →  ⎨
                         ⎩ 2^{K} − 2    if Σ = Unsigned
    *ω*Encode(*X <* 0) → *ω*Encode_{*f*}(−*X*) + 2^{K−1}
    *ω*Encode(0) → 0
    *ω*Encode(*X >* 0) → *r*
      where
               *r* = ⎧ *T*                           if *S* < 2^{P−1}   (Subnormals)
                   ⎨
                   ⎩ *T* + (*E* + B) × 2^{P−1}  otherwise
      and
        *E* = max(⌊log_{2}(*X*)⌋, 1 − B)
        *S* = *X* × 2^{−*E*} × 2^{P−1}                         (*S* is the significand)

        *T* = *S* mod 2^{P−1}
      and
        K = BitwidthOf(*f*)
        P = PrecisionOf(*f*)

        B = ExponentBiasOf(*f*)
        Σ = SignednessOf(*f*)

NOTE—From the precondition that *X* is in the datum set of format *f*, it follows that *S* ∈ ℕ, and that *X* is finite in
finite formats.

## 4.8 Decoding and encoding for external formats
The *ω*DecodeExternal and *ω*EncodeExternal functions convert between external formats and closed extended reals.


### 4.8.1 Decoding
The function *ω*DecodeExternal converts a floating-point value in an external format to a datum in the closed extended
reals.

**Signature**
    *ω*DecodeExternal_{*f*}(*x*) → *X*

**Parameters**
     *f* : format of *x*, in {binary64, binary32, binary16, BFloat16}
**Operands**

     *x* : floating-point value, in format *f*
**Result**

    *X* : floating-point datum, a closed extended real value in D_{*f*}, the datum set of *f*
**Behavior**
    *ω*DecodeExternal(Any NaN) → NaN
    *ω*DecodeExternal(−Inf) → −∞
    *ω*DecodeExternal(Inf) → +∞
    *ω*DecodeExternal(−0) → 0
    *ω*DecodeExternal(*x*) → The extended real value encoded by *x*


### 4.8.2 Encoding
Encode floating-point datum to a floating-point value in external format *f*.

**Signature**
    *ω*EncodeExternal_{*f*}(*X*) → *r*

**Parameters**
     *f* : target format, in {binary64, binary32, binary16, BFloat16}
**Operands**

    *X* : floating-point datum, a closed extended real value in the datum set of format *f*
**Result**

     *r* : floating-point value, in format *f*
**Behavior**
    *ω*EncodeExternal(NaN) → Any quiet NaN
    *ω*EncodeExternal(0) → The code in *f* that decodes to the non-negative 0

    *ω*EncodeExternal(*X*) → The code in *f* that decodes to *X*
**Details**
While an implementation may return any quiet NaN, it is recommended that the quiet NaN with zero payload is returned.

NOTE— The *ω*EncodeExternal function is only called with arguments in the datum set of format *f*, therefore the
encoding is unambiguous and independent of rounding mode.

## 4.9 Converting between formats
### 4.9.1 Conversion

Convert a floating-point value to another format, with projection specification.

**Signature**
    Convert_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**

    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification
**Operands**

     *x* : floating-point value, format *f*_{*x*}
**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Convert(*X*) → *X*

    Convert(*x*) → *ω*Project_{*fr,ρ*}(*ω*Convert(*ω*Decode_{*fx*}(*x*)))

## 4.10 Arithmetic operations
Arithmetic operations that take one or more floating-point values as operands and return one or more floating-point
values are defined in this section.


### 4.10.1 Absolute value, Negation
**Signature**
    Abs_{*fx,fr,ρ*}(*x*) → *r*
    Negate_{*fx,fr,ρ*}(*x*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*Abs(NaN) → NaN
    *ω*Abs(−∞) → +∞
    *ω*Abs(+∞) → +∞
    *ω*Abs(*X*) → |*X*|
    Abs(*x*) → *ω*Project_{*fr,ρ*}(*ω*Abs(*ω*Decode_{*fx*}(*x*)))


    *ω*Negate(NaN) → NaN
    *ω*Negate(−∞) → +∞
    *ω*Negate(+∞) → −∞
    *ω*Negate(*X*) → −*X*

    Negate(*x*) → *ω*Project_{*fr,ρ*}(*ω*Negate(*ω*Decode_{*fx*}(*x*)))

### 4.10.2 Copying the sign
Copies the sign of a floating-point value onto another floating-point value.

**Signature**
    CopySign_{*fx,fy,fr,ρ*}(*x, y*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*CopySign(NaN, ∗) → NaN
    *ω*CopySign(∗, NaN) → NaN
    *ω*CopySign(±∞, +∞) → +∞
    *ω*CopySign(±∞, −∞) → −∞
    *ω*CopySign(±∞*, Y* ) if *Y* ≥ 0 → +∞
    *ω*CopySign(±∞*, Y* ) if *Y <* 0 → −∞
    *ω*CopySign(*X,* +∞) → |*X*|
    *ω*CopySign(*X,* −∞) → −|*X*|
    *ω*CopySign(*X, Y* ) if *Y* ≥ 0 → |*X*|
    *ω*CopySign(*X, Y* ) if *Y <* 0 → −|*X*|
    CopySign(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*CopySign(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.10.3 Addition, Subtraction
Addition and subtraction of two floating-point values, returning a floating-point value.

**Signature**
    Add_{*fx,fy,fr,ρ*}(*x, y*) → *r*
    Subtract_{*fx,fy,fr,ρ*}(*x, y*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*Add(NaN, ∗) → NaN
    *ω*Add(∗, NaN) → NaN
    *ω*Add(+∞, −∞) → NaN
    *ω*Add(−∞, +∞) → NaN
    *ω*Add(+∞, ∗) → +∞
    *ω*Add(∗, +∞) → +∞
    *ω*Add(−∞, ∗) → −∞
    *ω*Add(∗, −∞) → −∞
    *ω*Add(*X, Y* ) → *X* + *Y*
    Add(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Add(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

    *ω*Subtract(NaN, ∗) → NaN
    *ω*Subtract(∗, NaN) → NaN
    *ω*Subtract(+∞, +∞) → NaN
    *ω*Subtract(−∞, −∞) → NaN
    *ω*Subtract(∗, +∞) → −∞
    *ω*Subtract(+∞, ∗) → +∞
    *ω*Subtract(∗, −∞) → +∞
    *ω*Subtract(−∞, ∗) → −∞
    *ω*Subtract(*X, Y* ) → *X* − *Y*

    Subtract(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Subtract(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.10.4 Multiplication
Multiplication of two floating-point values, returning a floating-point value.

**Signature**
    Multiply_{*fx,fy,fr,ρ*}(*x, y*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*Multiply(NaN, ∗) → NaN
    *ω*Multiply(∗, NaN) → NaN
    *ω*Multiply(+∞, +∞) → +∞
    *ω*Multiply(−∞, −∞) → +∞
    *ω*Multiply(−∞, +∞) → −∞
    *ω*Multiply(+∞, −∞) → −∞
    *ω*Multiply(+∞*, Y* ) if *Y >* 0 → +∞
    *ω*Multiply(+∞*, Y* ) if *Y* = 0 → NaN
    *ω*Multiply(+∞*, Y* ) if *Y <* 0 → −∞
    *ω*Multiply(*X,* +∞) if *X >* 0 → +∞
    *ω*Multiply(*X,* +∞) if *X* = 0 → NaN
    *ω*Multiply(*X,* +∞) if *X <* 0 → −∞
    *ω*Multiply(−∞*, Y* ) if *Y >* 0 → −∞
    *ω*Multiply(−∞*, Y* ) if *Y* = 0 → NaN
    *ω*Multiply(−∞*, Y* ) if *Y <* 0 → +∞
    *ω*Multiply(*X,* −∞) if *X >* 0 → −∞
    *ω*Multiply(*X,* −∞) if *X* = 0 → NaN
    *ω*Multiply(*X,* −∞) if *X <* 0 → +∞
    *ω*Multiply(*X, Y* ) → *X* × *Y*
    Multiply(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Multiply(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.10.5 Division
Division of two floating-point values, returning a floating-point value.

**Signature**
    Divide_{*fx,fy,fr,ρ*}(*x, y*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*Divide(NaN, ∗) → NaN
    *ω*Divide(∗, NaN) → NaN
    *ω*Divide(+∞, ±∞) → NaN
    *ω*Divide(−∞, ±∞) → NaN
    *ω*Divide(∗, 0) → NaN
    *ω*Divide(+∞*, Y* ) if *Y >* 0 → +∞
    *ω*Divide(+∞*, Y* ) if *Y <* 0 → −∞
    *ω*Divide(−∞*, Y* ) if *Y >* 0 → −∞
    *ω*Divide(−∞*, Y* ) if *Y <* 0 → +∞
    *ω*Divide(∗, ±∞) → 0
    *ω*Divide(*X, Y* ) → *X/Y*
    Divide(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Divide(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))


NOTE 1—Divide(*x,* ±Inf) where *x* is finite yields 0.

NOTE 2—Divide(*x,* 0) yields NaN. Returning Inf for finite *x* would imply 1/(1/−∞) → ∞, an inconsistency.

### 4.10.6 Fused Multiply–Add
Compute *R* = *X*×*Y* +*Z*, with computation in the reals. Rounding and the determination of overflow and underflow are
applied only on the result. The behavior of *ω*FMA(*X, Y, Z*) is equivalent [15] to the behavior of *ω*Add(*ω*Multiply(*X, Y* )*, Z*).

**Signature**
    FMA_{*fx,fy,fz,fr,ρ*}(*x, y, z*) → *r*

**Parameters**                                      **Operands**
    *f*_{*x*} : format of operand *x*                             *x* : floating-point value, format *f*_{*x*}
    *f*_{*y*} : format of operand *y*                             *y* : floating-point value, format *f*_{*y*}
    *f*_{*z*} : format of operand *z*                             *z* : floating-point value, format *f*_{*z*}
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification                      **Result**
                                                    *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*FMA(NaN, ∗, ∗) → NaN
    *ω*FMA(∗, NaN, ∗) → NaN
    *ω*FMA(∗, ∗, NaN) → NaN
    *ω*FMA(0, ±∞, ∗) → NaN
    *ω*FMA(±∞, 0, ∗) → NaN
    *ω*FMA(*X,* +∞, +∞) if *X <* 0 → NaN
    *ω*FMA(*X,* −∞, +∞) if *X >* 0 → NaN
    *ω*FMA(+∞*, Y,* +∞) if *Y <* 0 → NaN
    *ω*FMA(−∞*, Y,* +∞) if *Y >* 0 → NaN
    *ω*FMA(*X,* −∞, −∞) if *X <* 0 → NaN
    *ω*FMA(*X,* +∞, −∞) if *X >* 0 → NaN
    *ω*FMA(−∞*, Y,* −∞) if *Y <* 0 → NaN
    *ω*FMA(+∞*, Y,* −∞) if *Y >* 0 → NaN
    *ω*FMA(−∞, +∞, +∞) → NaN
    *ω*FMA(+∞, −∞, +∞) → NaN
    *ω*FMA(+∞, +∞, −∞) → NaN
    *ω*FMA(−∞, −∞, −∞) → NaN
    *ω*FMA(+∞, +∞, ∗) → +∞
    *ω*FMA(−∞, −∞, ∗) → +∞
    *ω*FMA(+∞, −∞, ∗) → −∞
    *ω*FMA(−∞, +∞, ∗) → −∞
    *ω*FMA(∗, ∗, +∞) → +∞
    *ω*FMA(∗, ∗, −∞) → −∞
    *ω*FMA(*X,* −∞, ∗) if *X >* 0 → −∞
    *ω*FMA(*X,* −∞, ∗) if *X <* 0 → +∞
    *ω*FMA(*X,* +∞, ∗) if *X >* 0 → +∞
    *ω*FMA(*X,* +∞, ∗) if *X <* 0 → −∞
    *ω*FMA(+∞*, Y,* ∗) if *Y >* 0 → +∞
    *ω*FMA(+∞*, Y,* ∗) if *Y <* 0 → −∞
    *ω*FMA(−∞*, Y,* ∗) if *Y >* 0 → −∞
    *ω*FMA(−∞*, Y,* ∗) if *Y <* 0 → +∞
    *ω*FMA(*X, Y, Z*) → *X* × *Y* + *Z*

    FMA(*x, y, z*) → *ω*Project_{*fr,ρ*}(*ω*FMA(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*), *ω*Decode_{*fz*}(*z*)))

### 4.10.7 Fused Add–Add
Compute *R* = *X*+*Y* +*Z*, with computation in the reals. Rounding and the determination of overflow and underflow are
applied only on the result. The behavior of *ω*FAA(*X, Y, Z*) is equivalent [15] to the behavior of *ω*Add(*ω*Add(*X, Y* )*, Z*),
which is in turn equivalent to *ω*Add(*X,* *ω*Add(*Y, Z*)).

**Signature**
    FAA_{*fx,fy,fz,fr,ρ*}(*x, y, z*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*z*} : format of operand *z*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
     *z* : floating-point value, format *f*_{*z*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*FAA(NaN, ∗, ∗) → NaN
    *ω*FAA(∗, NaN, ∗) → NaN
    *ω*FAA(∗, ∗, NaN) → NaN
    *ω*FAA(+∞, −∞, ∗) → NaN
    *ω*FAA(−∞, +∞, ∗) → NaN
    *ω*FAA(+∞, ∗, −∞) → NaN
    *ω*FAA(−∞, ∗, +∞) → NaN
    *ω*FAA(∗, +∞, −∞) → NaN
    *ω*FAA(∗, −∞, +∞) → NaN
    *ω*FAA(+∞, +∞, +∞) → +∞
    *ω*FAA(−∞, −∞, −∞) → −∞
    *ω*FAA(∗, +∞, +∞) → +∞
    *ω*FAA(+∞, ∗, +∞) → +∞
    *ω*FAA(+∞, +∞, ∗) → +∞
    *ω*FAA(∗, −∞, −∞) → −∞
    *ω*FAA(−∞, ∗, −∞) → −∞
    *ω*FAA(−∞, −∞, ∗) → −∞
    *ω*FAA(+∞, ∗, ∗) → +∞
    *ω*FAA(∗, +∞, ∗) → +∞
    *ω*FAA(∗, ∗, +∞) → +∞
    *ω*FAA(−∞, ∗, ∗) → −∞
    *ω*FAA(∗, −∞, ∗) → −∞
    *ω*FAA(∗, ∗, −∞) → −∞
    *ω*FAA(*X, Y, Z*) → *X* + *Y* + *Z*
    FAA(*x, y, z*) → *ω*Project_{*fr,ρ*}(*ω*FAA(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*), *ω*Decode_{*fz*}(*z*)))

### 4.10.8 Square root, Reciprocal, Reciprocal square root
**Signature**

    Sqrt_{*fx,fr,ρ*}(*x*) → *r*
    Recip_{*fx,fr,ρ*}(*x*) → *r*
    RSqrt_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Sqrt(NaN) → NaN
    *ω*Sqrt(−∞) → NaN
    *ω*Sqrt(*X*) if *X <* 0 → NaN
    *ω*Sqrt(+∞) → +∞
    *ω*Sqrt(*X*) → √*X*

    Sqrt(*x*) → *ω*Project_{*fr,ρ*}(*ω*Sqrt(*ω*Decode_{*fx*}(*x*)))

    *ω*Recip(NaN) → NaN
    *ω*Recip(0) → NaN
    *ω*Recip(±∞) → 0
    *ω*Recip(*X*) → 1*/X*

    Recip(*x*) → *ω*Project_{*fr,ρ*}(*ω*Recip(*ω*Decode_{*fx*}(*x*)))


    *ω*RSqrt(NaN) → NaN
    *ω*RSqrt(−∞) → NaN
    *ω*RSqrt(*X*) if *X* ≤ 0 → NaN
    *ω*RSqrt(+∞) → 0
    *ω*RSqrt(*X*) → 1/√*X*
    RSqrt(*x*) → *ω*Project_{*fr,ρ*}(*ω*RSqrt(*ω*Decode_{*fx*}(*x*)))

### 4.10.9 Logarithm, Exponentiation
**Signature**

    Exp_{*fx,fr,ρ*}(*x*) → *r*
    Exp2_{*fx,fr,ρ*}(*x*) → *r*
    Log_{*fx,fr,ρ*}(*x*) → *r*
    Log2_{*fx,fr,ρ*}(*x*) → *r*
    LogOnePlus_{*fx,fr,ρ*}(*x*) → *r*
    ExpMinusOne_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Exp(NaN) → NaN                               *ω*Exp2(NaN) → NaN
    *ω*Exp(+∞) → +∞                               *ω*Exp2(+∞) → +∞
    *ω*Exp(−∞) → 0                                  *ω*Exp2(−∞) → 0
    *ω*Exp(*X*) → *e*^{*X*}                                  *ω*Exp2(*X*) → 2^{*X*}

    Exp(*x*) → *ω*Project_{*fr,ρ*}(*ω*Exp(*ω*Decode_{*fx*}(*x*)))         Exp2(*x*) → *ω*Project_{*fr,ρ*}(*ω*Exp2(*ω*Decode_{*fx*}(*x*)))


    *ω*Log(NaN) → NaN                               *ω*Log2(NaN) → NaN
    *ω*Log(−∞) → NaN                               *ω*Log2(−∞) → NaN
    *ω*Log(+∞) → +∞                               *ω*Log2(+∞) → +∞
    *ω*Log(*X*) if *X <* 0 → NaN                        *ω*Log2(*X*) if *X <* 0 → NaN
    *ω*Log(0) → −∞                                  *ω*Log2(0) → −∞
    *ω*Log(*X*) → log_{*e*} *X*                               *ω*Log2(*X*) → log_{2} *X*

    Log(*x*) → *ω*Project_{*fr,ρ*}(*ω*Log(*ω*Decode_{*fx*}(*x*)))         Log2(*x*) → *ω*Project_{*fr,ρ*}(*ω*Log2(*ω*Decode_{*fx*}(*x*)))


    *ω*LogOnePlus(*X*) → *ω*Log(*ω*Add(1*, X*))

    LogOnePlus(*x*) → *ω*Project_{*fr,ρ*}(*ω*LogOnePlus(*ω*Decode_{*fx*}(*x*)))

    *ω*ExpMinusOne(*X*) → *ω*Subtract(*ω*Exp(*X*), 1)

    ExpMinusOne(*x*) → *ω*Project_{*fr,ρ*}(*ω*ExpMinusOne(*ω*Decode_{*fx*}(*x*)))

### 4.10.10 Trigonometric functions
**Signature**

    Sin_{*fx,fr,ρ*}(*x*) → *r*
    Cos_{*fx,fr,ρ*}(*x*) → *r*
    Tan_{*fx,fr,ρ*}(*x*) → *r*
    ArcSin_{*fx,fr,ρ*}(*x*) → *r*
    ArcCos_{*fx,fr,ρ*}(*x*) → *r*
    ArcTan_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Sin(NaN) → NaN                               *ω*ArcSin(NaN) → NaN
    *ω*Sin(+∞) → NaN                               *ω*ArcSin(+∞) → NaN
    *ω*Sin(−∞) → NaN                               *ω*ArcSin(−∞) → NaN
    *ω*Sin(*X*) → sin *X*                                *ω*ArcSin(*X*) if *X <* −1 or *X >* 1 → NaN
                                                   *ω*ArcSin(*X*) → arcsin *X*
    Sin(*x*) → *ω*Project_{*fr,ρ*}(*ω*Sin(*ω*Decode_{*fx*}(*x*)))
                                                   ArcSin(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcSin(*ω*Decode_{*fx*}(*x*)))


    *ω*Cos(NaN) → NaN                               *ω*ArcCos(NaN) → NaN
    *ω*Cos(+∞) → NaN                               *ω*ArcCos(+∞) → NaN
    *ω*Cos(−∞) → NaN                               *ω*ArcCos(−∞) → NaN
    *ω*Cos(*X*) → cos *X*                                *ω*ArcCos(*X*) if *X <* −1 or *X >* 1 → NaN
                                                   *ω*ArcCos(*X*) → arccos *X*
    Cos(*x*) → *ω*Project_{*fr,ρ*}(*ω*Cos(*ω*Decode_{*fx*}(*x*)))
                                                   ArcCos(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcCos(*ω*Decode_{*fx*}(*x*)))


    *ω*Tan(NaN) → NaN                               *ω*ArcTan(NaN) → NaN
    *ω*Tan(+∞) → NaN                               *ω*ArcTan(+∞) → ^{*π*}_{2}
    *ω*Tan(−∞) → NaN                               *ω*ArcTan(−∞) → −^{*π*}_{2}
    *ω*Tan(*X*) if cos *X* = 0 and sin *X >* 0 → +∞         *ω*ArcTan(*X*) → arctan *X*
    *ω*Tan(*X*) if cos *X* = 0 and sin *X <* 0 → −∞
    *ω*Tan(*X*) → tan *X*                               ArcTan(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcTan(*ω*Decode_{*fx*}(*x*)))

    Tan(*x*) → *ω*Project_{*fr,ρ*}(*ω*Tan(*ω*Decode_{*fx*}(*x*)))

NOTE— There are no datums *X* in the datum set of any format *f* for which cos *X* = 0, as all floats are rational, but
the special case is included for documentation, and to support formal verification.

### 4.10.11 Hyperbolic functions
**Signature**

    Sinh_{*fx,fr,ρ*}(*x*) → *r*
    Cosh_{*fx,fr,ρ*}(*x*) → *r*
    Tanh_{*fx,fr,ρ*}(*x*) → *r*
    ArcSinh_{*fx,fr,ρ*}(*x*) → *r*
    ArcCosh_{*fx,fr,ρ*}(*x*) → *r*
    ArcTanh_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Sinh(NaN) → NaN                              *ω*ArcSinh(NaN) → NaN
    *ω*Sinh(+∞) → +∞                               *ω*ArcSinh(+∞) → +∞
    *ω*Sinh(−∞) → −∞                               *ω*ArcSinh(−∞) → −∞
    *ω*Sinh(*X*) → sinh *X*                              *ω*ArcSinh(*X*) → arcsinh *X*

    Sinh(*x*) → *ω*Project_{*fr,ρ*}(*ω*Sinh(*ω*Decode_{*fx*}(*x*)))        ArcSinh(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcSinh(*ω*Decode_{*fx*}(*x*)))


    *ω*Cosh(NaN) → NaN                              *ω*ArcCosh(NaN) → NaN
    *ω*Cosh(+∞) → +∞                              *ω*ArcCosh(+∞) → +∞
    *ω*Cosh(−∞) → +∞                              *ω*ArcCosh(−∞) → NaN
    *ω*Cosh(*X*) → cosh *X*                              *ω*ArcCosh(*X*) if *X <* 1 → NaN
                                                   *ω*ArcCosh(*X*) → arccosh *X*
    Cosh(*x*) → *ω*Project_{*fr,ρ*}(*ω*Cosh(*ω*Decode_{*fx*}(*x*)))
                                                   ArcCosh(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcCosh(*ω*Decode_{*fx*}(*x*)))


    *ω*Tanh(NaN) → NaN                              *ω*ArcTanh(NaN) → NaN
    *ω*Tanh(+∞) → 1                                 *ω*ArcTanh(+∞) → NaN
    *ω*Tanh(−∞) → −1                               *ω*ArcTanh(−∞) → NaN
    *ω*Tanh(*X*) → tanh *X*                             *ω*ArcTanh(1) → +∞
                                                   *ω*ArcTanh(−1) → −∞
    Tanh(*x*) → *ω*Project_{*fr,ρ*}(*ω*Tanh(*ω*Decode_{*fx*}(*x*)))       *ω*ArcTanh(*X*) if *X <* −1 or *X >* 1 → NaN
                                                   *ω*ArcTanh(*X*) → arctanh *X*

                                                   ArcTanh(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcTanh(*ω*Decode_{*fx*}(*x*)))

### 4.10.12 Trigonometric *π*-functions
**Signature**

    SinPi_{*fx,fr,ρ*}(*x*) → *r*
    CosPi_{*fx,fr,ρ*}(*x*) → *r*
    TanPi_{*fx,fr,ρ*}(*x*) → *r*
    ArcSinPi_{*fx,fr,ρ*}(*x*) → *r*
    ArcCosPi_{*fx,fr,ρ*}(*x*) → *r*
    ArcTanPi_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*SinPi(NaN) → NaN                             *ω*ArcSinPi(NaN) → NaN
    *ω*SinPi(+∞) → NaN                              *ω*ArcSinPi(+∞) → NaN
    *ω*SinPi(−∞) → NaN                              *ω*ArcSinPi(−∞) → NaN
    *ω*SinPi(*X*) → sin (*X* × *π*)                         *ω*ArcSinPi(*X*) if *X <* −1 or *X >* 1 → NaN
                                                   *ω*ArcSinPi(*X*) → (arcsin *X*)*/π*
    SinPi(*x*) → *ω*Project_{*fr,ρ*}(*ω*SinPi(*ω*Decode_{*fx*}(*x*)))
                                                   ArcSinPi(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcSinPi(*ω*Decode_{*fx*}(*x*)))


    *ω*CosPi(NaN) → NaN                             *ω*ArcCosPi(NaN) → NaN
    *ω*CosPi(+∞) → NaN                             *ω*ArcCosPi(+∞) → NaN
    *ω*CosPi(−∞) → NaN                             *ω*ArcCosPi(−∞) → NaN
    *ω*CosPi(*X*) → cos (*X* × *π*)                         *ω*ArcCosPi(*X*) if *X <* −1 or *X >* 1 → NaN
                                                   *ω*ArcCosPi(*X*) → (arccos *X*)*/π*
    CosPi(*x*) → *ω*Project_{*fr,ρ*}(*ω*CosPi(*ω*Decode_{*fx*}(*x*)))
                                                   ArcCosPi(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcCosPi(*ω*Decode_{*fx*}(*x*)))


    *ω*TanPi(NaN) → NaN                             *ω*ArcTanPi(NaN) → NaN
    *ω*TanPi(+∞) → NaN                             *ω*ArcTanPi(+∞) → 1/2
    *ω*TanPi(−∞) → NaN                             *ω*ArcTanPi(−∞) → −1/2
    *ω*TanPi(*X*) if cos (*X* × *π*) = 0 and                  *ω*ArcTanPi(*X*) → (arctan *X*)*/π*
                sin (*X* × *π*) > 0 → +∞
    *ω*TanPi(*X*) if cos (*X* × *π*) = 0 and                  ArcTanPi(*x*) → *ω*Project_{*fr,ρ*}(*ω*ArcTanPi(*ω*Decode_{*fx*}(*x*)))
                sin (*X* × *π*) < 0 → −∞
    *ω*TanPi(*X*) → tan (*X* × *π*)

    TanPi(*x*) → *ω*Project_{*fr,ρ*}(*ω*TanPi(*ω*Decode_{*fx*}(*x*)))

### 4.10.13 Softplus
**Signature**

    Softplus_{*fx,fr,ρ*}(*x*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Softplus(NaN) → NaN
    *ω*Softplus(+∞) → +∞
    *ω*Softplus(−∞) → 0
    *ω*Softplus(*X*) → log_{*e*} (1 + *e*^{*X*})

    Softplus(*x*) → *ω*Project_{*fr,ρ*}(*ω*Softplus(*ω*Decode_{*fx*}(*x*)))

### 4.10.14 Hypotenuse
**Signature**

    Hypot_{*fx,fy,fr,ρ*}(*x, y*) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Hypot(NaN, ∗) → NaN
    *ω*Hypot(∗, NaN) → NaN
    *ω*Hypot(∗, ±∞) → +∞
    *ω*Hypot(±∞, ∗) → +∞
    *ω*Hypot(*X, Y*) → √(|*X*|^{2} + |*Y*|^{2})

    Hypot(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Hypot(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.10.15 Inverse tangent of two variables
**Signature**

    ArcTan2_{*fy,fx,fr,ρ*}(*y, x*) → *r*
**Parameters**
    *f*_{*y*} : format of operand *y*
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *y* : floating-point value, format *f*_{*y*}
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*ArcTan2(NaN, ∗) → NaN
    *ω*ArcTan2(∗, NaN) → NaN
    *ω*ArcTan2(0, 0) → NaN
    *ω*ArcTan2(−∞, ±∞) → NaN
    *ω*ArcTan2(+∞, ±∞) → NaN
    *ω*ArcTan2(∗, +∞) → 0
    *ω*ArcTan2(0*, X*) if *X >* 0 → 0
    *ω*ArcTan2(+∞, ∗) → ^{*π*}_{2}
    *ω*ArcTan2(*Y,* 0) if *Y >* 0 → ^{*π*}_{2}
    *ω*ArcTan2(*Y,* −∞) if *Y* ≥ 0 → *π*
    *ω*ArcTan2(*Y,* −∞) if *Y <* 0 → −*π*
    *ω*ArcTan2(0*, X*) if *X <* 0 → *π*
    *ω*ArcTan2(−∞, ∗) → −^{*π*}_{2}
    *ω*ArcTan2(*Y,* 0) if *Y <* 0 → −^{*π*}_{2}
    *ω*ArcTan2(*Y, X*) if *X >* 0 → arctan (*Y /X*)
    *ω*ArcTan2(*Y, X*) if *Y >* 0 and *X <* 0 → arctan (*Y /X*) + *π*
    *ω*ArcTan2(*Y, X*) if *Y <* 0 and *X <* 0 → arctan (*Y /X*) − *π*

    ArcTan2(*y, x*) → *ω*Project_{*fr,ρ*}(*ω*ArcTan2(*ω*Decode_{*fy*}(*y*), *ω*Decode_{*fx*}(*x*)))

NOTE 1—It would be inconsistent to define ArcTan2(0, 0) as 0, as the limit is indeterminate.

NOTE 2—ArcTan2(±Inf, ±Inf) yields NaN, which is consistent with Divide(±Inf, ±Inf).

### 4.10.16 Inverse tangent of two variables (*π*-variant)
**Signature**

    ArcTan2Pi_{*fy,fx,fr,ρ*}(*y, x*) → *r*
**Parameters**
    *f*_{*y*} : format of operand *y*
    *f*_{*x*} : format of operand *x*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *y* : floating-point value, format *f*_{*y*}
     *x* : floating-point value, format *f*_{*x*}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*ArcTan2Pi(NaN, ∗) → NaN
    *ω*ArcTan2Pi(∗, NaN) → NaN
    *ω*ArcTan2Pi(0, 0) → NaN
    *ω*ArcTan2Pi(−∞, ±∞) → NaN
    *ω*ArcTan2Pi(+∞, ±∞) → NaN
    *ω*ArcTan2Pi(∗, +∞) → 0
    *ω*ArcTan2Pi(0*, X*) if *X >* 0 → 0
    *ω*ArcTan2Pi(+∞, ∗) → 1/2
    *ω*ArcTan2Pi(*Y,* 0) if *Y >* 0 → 1/2
    *ω*ArcTan2Pi(*Y,* −∞) if *Y* ≥ 0 → 1
    *ω*ArcTan2Pi(*Y,* −∞) if *Y <* 0 → −1
    *ω*ArcTan2Pi(0*, X*) if *X <* 0 → 1
    *ω*ArcTan2Pi(−∞, ∗) → −1/2
    *ω*ArcTan2Pi(*Y,* 0) if *Y <* 0 → −1/2
    *ω*ArcTan2Pi(*Y, X*) if *X >* 0 → (arctan (*Y /X*))*/π*
    *ω*ArcTan2Pi(*Y, X*) if *Y >* 0 and *X <* 0 → (arctan (*Y /X*) + *π*)*/π*
    *ω*ArcTan2Pi(*Y, X*) if *Y <* 0 and *X <* 0 → (arctan (*Y /X*) − *π*)*/π*

    ArcTan2Pi(*y, x*) → *ω*Project_{*fr,ρ*}(*ω*ArcTan2Pi(*ω*Decode_{*fy*}(*y*), *ω*Decode_{*fx*}(*x*)))

NOTE 1—It would be inconsistent to define ArcTan2Pi(0, 0) as 0, as the limit is indeterminate.

NOTE 2—ArcTan2Pi(±Inf, ±Inf) yields NaN, which is consistent with Divide(±Inf, ±Inf).

## 4.11 Extrema
### 4.11.1 Minimum and maximum, and number variants

Minimum and maximum, with or without propagation of NaN.

**Signature**
    Operation_{*fx,fy,fr,ρ*}(*x, y*) → *r*
**Parameters**

    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification
**Operands**

     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Minimum(NaN, ∗) → NaN                        *ω*Maximum(NaN, ∗) → NaN
    *ω*Minimum(∗, NaN) → NaN                        *ω*Maximum(∗, NaN) → NaN
    *ω*Minimum(+∞, +∞) → +∞                      *ω*Maximum(+∞, +∞) → +∞
    *ω*Minimum(−∞, −∞) → −∞                      *ω*Maximum(−∞, −∞) → −∞
    *ω*Minimum(+∞, −∞) → −∞                      *ω*Maximum(+∞, −∞) → +∞
    *ω*Minimum(−∞, +∞) → −∞                      *ω*Maximum(−∞, +∞) → +∞
    *ω*Minimum(+∞*, Y* ) → *Y*                          *ω*Maximum(+∞, ∗) → +∞
    *ω*Minimum(*X,* +∞) → *X*                          *ω*Maximum(∗, +∞) → +∞
    *ω*Minimum(−∞, ∗) → −∞                        *ω*Maximum(−∞*, Y* ) → *Y*
    *ω*Minimum(∗, −∞) → −∞                        *ω*Maximum(*X,* −∞) → *X*
    *ω*Minimum(*X, Y* ) → if *X < Y* then *X* else *Y*         *ω*Maximum(*X, Y* ) → if *X < Y* then *Y* else *X*


    Minimum(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Minimum(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

    Maximum(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*Maximum(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

    *ω*MinimumNumber(NaN, NaN) → NaN               *ω*MaximumNumber(NaN, NaN) → NaN
    *ω*MinimumNumber(*X,* NaN) → *X*                   *ω*MaximumNumber(*X,* NaN) → *X*
    *ω*MinimumNumber(NaN*, Y* ) → *Y*                   *ω*MaximumNumber(NaN*, Y* ) → *Y*
    *ω*MinimumNumber(*X, Y* ) → *ω*Minimum(*X, Y* )        *ω*MaximumNumber(*X, Y* ) → *ω*Maximum(*X, Y* )


    MinimumNumber(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*MinimumNumber(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))
    MaximumNumber(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*MaximumNumber(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.11.2 Minimum and maximum magnitude, and number variants
Minimum and maximum by magnitude, with or without propagation of NaN.

**Signature**
    Operation_{*fx,fy,fr,ρ*}(*x, y*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**
    *ω*MinimumMagnitude(NaN,∗) → NaN               *ω*MaximumMagnitude(NaN,∗) → NaN
    *ω*MinimumMagnitude(∗,NaN) → NaN               *ω*MaximumMagnitude(∗,NaN) → NaN
    *ω*MinimumMagnitude(+∞,+∞) → +∞             *ω*MaximumMagnitude(+∞,∗) → +∞
    *ω*MinimumMagnitude(−∞,−∞) → −∞             *ω*MaximumMagnitude(∗,+∞) → +∞
    *ω*MinimumMagnitude(+∞,−∞) → −∞             *ω*MaximumMagnitude(−∞,∗) → −∞
    *ω*MinimumMagnitude(−∞,+∞) → −∞             *ω*MaximumMagnitude(∗,−∞) → −∞
    *ω*MinimumMagnitude(±∞*, Y* ) → *Y*                 *ω*MaximumMagnitude(*X, Y* ) if |*X*| > |*Y* | → *X*
    *ω*MinimumMagnitude(*X,*±∞) → *X*                *ω*MaximumMagnitude(*X, Y* ) if |*X*| < |*Y* | → *Y*
    *ω*MinimumMagnitude(*X, Y* ) if |*X*| < |*Y* | → *X*        *ω*MaximumMagnitude(*X, Y* ) if |*X*| = |*Y* | →
    *ω*MinimumMagnitude(*X, Y* ) if |*X*| > |*Y* | → *Y*                               if *X < Y* then*Y* else*X*
    *ω*MinimumMagnitude(*X, Y* ) if |*X*| = |*Y* | →
                          if *X < Y* then*X* else*Y*
    MinimumMagnitude(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*MinimumMagnitude(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

    MaximumMagnitude(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*MaximumMagnitude(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))


    *ω*MinimumMagnitudeNumber(*X,* NaN) → *X*
    *ω*MinimumMagnitudeNumber(NaN*, Y* ) → *Y*
    *ω*MinimumMagnitudeNumber(*X, Y* ) → *ω*MinimumMagnitude(*X, Y* )
    MinimumMagnitudeNumber(*x, y*) →
                *ω*Project_{*fr,ρ*}(*ω*MinimumMagnitudeNumber(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))


    *ω*MaximumMagnitudeNumber(*X,* NaN) → *X*
    *ω*MaximumMagnitudeNumber(NaN*, Y* ) → *Y*
    *ω*MaximumMagnitudeNumber(*X, Y* ) → *ω*MaximumMagnitude(*X, Y* )

    MaximumMagnitudeNumber(*x, y*) →
                *ω*Project_{*fr,ρ*}(*ω*MaximumMagnitudeNumber(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.11.3 Minimum and maximum finite variants
Minimum and maximum finite value.

**Signature**
    Operation_{*fx,fy,fr,ρ*}(*x, y*) → *r*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *r* : floating-point value, format *f*_{*r*}
**Behavior**

    *ω*MinimumFinite(NaN, NaN) → NaN                 *ω*MaximumFinite(NaN, NaN) → NaN
    *ω*MinimumFinite(NaN*, Y* ) → *Y*                     *ω*MaximumFinite(NaN*, Y* ) → *Y*
    *ω*MinimumFinite(*X,* NaN) → *X*                     *ω*MaximumFinite(*X,* NaN) → *X*
    *ω*MinimumFinite(+∞, +∞) → +∞                 *ω*MaximumFinite(+∞, +∞) → +∞
    *ω*MinimumFinite(−∞, −∞) → −∞                 *ω*MaximumFinite(−∞, −∞) → −∞
    *ω*MinimumFinite(+∞, −∞) → −∞                 *ω*MaximumFinite(+∞, −∞) → +∞
    *ω*MinimumFinite(−∞, +∞) → −∞                 *ω*MaximumFinite(−∞, +∞) → +∞
    *ω*MinimumFinite(+∞*, Y* ) → *Y*                      *ω*MaximumFinite(+∞*, Y* ) → *Y*
    *ω*MinimumFinite(*X,* +∞) → *X*                     *ω*MaximumFinite(*X,* +∞) → *X*
    *ω*MinimumFinite(−∞*, Y* ) → *Y*                      *ω*MaximumFinite(−∞*, Y* ) → *Y*
    *ω*MinimumFinite(*X,* −∞) → *X*                     *ω*MaximumFinite(*X,* −∞) → *X*
    *ω*MinimumFinite(*X, Y* ) →                         *ω*MaximumFinite(*X, Y* ) →
                        if *X < Y* then *X* else *Y*                            if *X < Y* then *Y* else *X*

    MinimumFinite(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*MinimumFinite(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

    MaximumFinite(*x, y*) → *ω*Project_{*fr,ρ*}(*ω*MaximumFinite(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*)))

### 4.11.4 Clamping
**Signature**

    Clamp_{*fx,f*lo*,f*hi*,fr,ρ*}(*x,* lo, hi) → *r*
**Parameters**
    *f*_{*x*} : format of operand *x*
   *f*_{lo} : format of lower bound lo
   *f*_{hi} : format of upper bound hi
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *x* : floating-point value, format *f*_{*x*}
    lo : floating-point value, format *f*_{lo}
    hi : floating-point value, format *f*_{hi}

**Result**
     *r* : floating-point value, format *f*_{*r*}

**Behavior**
    *ω*Clamp(NaN, ∗, ∗) → NaN
    *ω*Clamp(∗, NaN, ∗) → NaN
    *ω*Clamp(∗, ∗, NaN) → NaN
    *ω*Clamp(∗, Lo, Hi) if Lo > Hi → NaN
    *ω*Clamp(∗, +∞, +∞) → +∞
    *ω*Clamp(∗, −∞, −∞) → −∞
    *ω*Clamp(∗, ∗, −∞) → NaN
    *ω*Clamp(∗, +∞, ∗) → NaN
    *ω*Clamp(+∞, ∗, +∞) → +∞
    *ω*Clamp(+∞, ∗, Hi) → Hi
    *ω*Clamp(−∞, −∞, ∗) → −∞
    *ω*Clamp(−∞, Lo, ∗) → Lo
    *ω*Clamp(*X,* −∞, +∞) → *X*
    *ω*Clamp(*X,* −∞, Hi) if *X* ≤ Hi → *X*
    *ω*Clamp(*X,* −∞, Hi) if *X >* Hi → Hi
    *ω*Clamp(*X,* Lo, +∞) if *X* ≤ Lo → Lo
    *ω*Clamp(*X,* Lo, +∞) if *X >* Lo → *X*
    *ω*Clamp(*X,* Lo, Hi) → if *X* ≤ Lo then Lo else if *X* ≥ Hi then Hi else *X*

    Clamp(*x,* lo, hi) → *ω*Project_{*fr,ρ*}(*ω*Clamp(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*f*lo}(lo), *ω*Decode_{*f*hi}(hi)))

## 4.12 Comparisons
Comparison operators take two operands and return a Boolean value.

**Signature**
    CompareOp_{*fx,fy*}(*x, y*) → *b*

**Parameters**
    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*

**Operands**
     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**

     *b* : boolean value
**Behavior**

    *ω*CompareLess(NaN, ∗) → False
    *ω*CompareLess(∗, NaN) → False
    *ω*CompareLess(+∞, ∗) → False
    *ω*CompareLess(∗, +∞) → True
    *ω*CompareLess(−∞, −∞) → False
    *ω*CompareLess(−∞, ∗) → True
    *ω*CompareLess(∗, −∞) → False
    *ω*CompareLess(*X, Y* ) → *X < Y*
    CompareLess(*x, y*) → *ω*CompareLess(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*))

    *ω*CompareLessEqual(NaN, ∗) → False
    *ω*CompareLessEqual(∗, NaN) → False
    *ω*CompareLessEqual(∗, +∞) → True
    *ω*CompareLessEqual(−∞, ∗) → True
    *ω*CompareLessEqual(+∞, ∗) → False
    *ω*CompareLessEqual(∗, −∞) → False
    *ω*CompareLessEqual(*X, Y* ) → *X* ≤ *Y*

    CompareLessEqual(*x, y*) → *ω*CompareLessEqual(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*))
    *ω*CompareEqual(NaN, ∗) → False
    *ω*CompareEqual(∗, NaN) → False
    *ω*CompareEqual(+∞, +∞) → True
    *ω*CompareEqual(−∞, −∞) → True
    *ω*CompareEqual(+∞, ∗) → False
    *ω*CompareEqual(−∞, ∗) → False
    *ω*CompareEqual(∗, −∞) → False
    *ω*CompareEqual(∗, +∞) → False
    *ω*CompareEqual(*X, Y* ) → *X* = *Y*

    CompareEqual(*x, y*) → *ω*CompareEqual(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*))


                                                              [Comparisons continued on next page]

    *ω*CompareGreaterEqual(NaN, ∗) → False
    *ω*CompareGreaterEqual(∗, NaN) → False
    *ω*CompareGreaterEqual(+∞, ∗) → True
    *ω*CompareGreaterEqual(−∞, −∞) → True
    *ω*CompareGreaterEqual(−∞, ∗) → False
    *ω*CompareGreaterEqual(∗, +∞) → False
    *ω*CompareGreaterEqual(∗, −∞) → True
    *ω*CompareGreaterEqual(*X, Y* ) → *X* ≥ *Y*

    CompareGreaterEqual(*x, y*) → *ω*CompareGreaterEqual(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*))
    *ω*CompareGreater(NaN, ∗) → False
    *ω*CompareGreater(∗, NaN) → False
    *ω*CompareGreater(∗, +∞) → False
    *ω*CompareGreater(−∞, −∞) → False
    *ω*CompareGreater(∗, −∞) → True
    *ω*CompareGreater(+∞, ∗) → True
    *ω*CompareGreater(−∞, ∗) → False
    *ω*CompareGreater(*X, Y* ) → *X > Y*

    CompareGreater(*x, y*) → *ω*CompareGreater(*ω*Decode_{*fx*}(*x*), *ω*Decode_{*fy*}(*y*))

### 4.12.1 Total order predicate

**Signature**
    TotalOrder_{*fx,fy*}(*x, y*) → *b*
**Parameters**

    *f*_{*x*} : format of operand *x*
    *f*_{*y*} : format of operand *y*
**Operands**

     *x* : floating-point value, format *f*_{*x*}
     *y* : floating-point value, format *f*_{*y*}
**Result**
     *b* : Boolean value

**Behavior**
    TotalOrder(NaN*, x*) → True
    TotalOrder(*x,* NaN) → False
    TotalOrder(*x, y*) → CompareLessEqual_{*fx,fy*}(*x, y*)


NOTE 1—The TotalOrder(*x, y*) predicate provides a total ordering over each format’s value set.
NOTE 2—The above definition is consistent with the IEEE-754 definition of TotalOrder. There is a single NaN and it
always compares as the most negative value.

### 4.12.2 Comparison operator symbols
This section defines the mapping between comparison operator symbols that a system may make available with floating-
point values as operands.

                            Table 1—Comparison predicates and negations

                            Mathematical
                                            Predicate
                            symbol
                            *x* = *y*            CompareEqual(*x, y*)

                            *x > y*            CompareGreater(*x, y*)

                            *x* ≥ *y, x* >= *y*      CompareGreaterEqual(*x, y*)
                            *x < y*            CompareLess(*x, y*)

                            *x* ≤ *y, x* <= *y*      CompareLessEqual(*x, y*)
                            *x* ≠ *y, x* != *y*      notCompareEqual(*x, y*)

## 4.13 Predicates and classification
The classification operations comprise: 1) a set of predicate functions with a Boolean return value, taking a single
operand; 2) a classifier operation Class(*x*) that returns a single value of enumeration type, describing the operand’s
properties.

**Signature**
    IsClass_{*f*}(*x*) → *b*

**Parameters**
     *f* : format of operand *x*

**Operands**
     *x* : floating-point value, in format *f*
**Result**

     *b* : boolean value
**Behavior**

    *ω*IsZero(NaN) → False
    *ω*IsZero(±∞) → False
    *ω*IsZero(*X*) → *X* = 0
    IsZero(*x*) → *ω*IsZero(*ω*Decode_{*f*}(*x*))

    *ω*IsOne(NaN) → False
    *ω*IsOne(±∞) → False
    *ω*IsOne(*X*) → *X* = 1

    IsOne(*x*) → *ω*IsOne(*ω*Decode_{*f*}(*x*))

    IsNaN(*x*) → *ω*Decode_{*f*}(*x*) ∈ {NaN}

    IsInfinite(*x*) → *ω*Decode_{*f*}(*x*) ∈ {−∞, +∞}


    IsFinite(*x*) → not IsInfinite(*x*) and not IsNaN(*x*)

    *ω*IsSignMinus(NaN) → False
    *ω*IsSignMinus(+∞) → False
    *ω*IsSignMinus(−∞) → True
    *ω*IsSignMinus(*X*) → *X <* 0
    IsSignMinus(*x*) → *ω*IsSignMinus(*ω*Decode_{*f*}(*x*))


    IsNormal(*x*) if IsZero(*x*) or IsInfinite(*x*) or IsNaN(*x*) → False
    IsNormal(*x*) → |*ω*Decode_{*f*}(*x*)| ≥ *ω*Decode_{*f*}(MinNormalOf(*f*))

    IsSubnormal(*x*) if IsZero(*x*) or IsInfinite(*x*) or IsNaN(*x*) → False
    IsSubnormal(*x*) → not IsNormal(*x*)

### 4.13.1 Classifier operation
The classifier operation Class(*x*) tells which of the eight classes *x* falls into as defined by Table 2.

**Signature**
    Class_{*f*}(*x*) → *c*

**Parameters**
     *f* : format of operand *x*

**Operands**
     *x* : floating-point value, format *f*
**Result**

     *c* : enumeration
**Behavior**

    Class(*x*) → ClassEnum

                                   Table 2—Classifier operation

                  ClassEnum              *Condition*

                  ClsNaN                 IsNaN(x)
                  ClsNegativeInfinity        IsInfinite(x) and IsSignMinus(x)
                  ClsNegativeNormal        IsNormal(x) and IsSignMinus(x)
                  ClsNegativeSubnormal     IsSubnormal(x) and IsSignMinus(x)
                  ClsZero                 IsZero(x)
                  ClsPositiveSubnormal      IsSubnormal(x) and not IsSignMinus(x)
                  ClsPositiveNormal        IsNormal(x) and not IsSignMinus(x)
                  ClsPositiveInfinity         IsInfinite(x) and not IsSignMinus(x)

## 4.14 Format-level operations
Certain operations act on formats rather than values, for example, determining the precision of a format.^{10}

The following operations return integers or enumerations:

 Operation                                                Format

                                 Binary{K, P, Σ, Δ}       binary64   binary32   binary16   BFloat16
                             Σ = Signed  Σ = Unsigned
 BitwidthOf(*f*)                    K            K          64        32        16        16
 PrecisionOf(*f*)                   P            P          53        24        11         8
 SignednessOf(*f*)                Signed      Unsigned     Signed     Signed     Signed     Signed
 DomainOf(*f*)                    Δ           Δ       Extended  Extended  Extended  Extended
 ExponentBitwidthOf(*f*)          K − P      K − P + 1       11         8         5         8
 TrailingSignificandBitwidthOf(*f*)   P − 1        P − 1         52        23        10         7
 ExponentBiasOf(*f*)             2^{K−P−1}        2^{K−P}        1023       127        15        127

The following operations return floating-point values, in the format *f*:

 Operation              Description

 MaxFiniteOf(*f*)         Maximum finite value representable in format *f*.
 MinFiniteOf(*f*)          Minimum finite value representable in format *f*.
                        In signed formats, MinFiniteOf(*f*) = −MaxFiniteOf(*f*).
                        In unsigned formats, MinFiniteOf(*f*) = 0.
 MinPositiveOf(*f*)        Minimum strictly positive value representable in format *f*.
 MaxSubnormalOf(*f*)     Maximum positive subnormal value representable in format *f*, or NaN if no values are
                        subnormal.
 MinNormalOf(*f*)        Minimum positive normal value representable in format *f*.

## 4.15 Projection specification operations

These operations query projection specifications and return enumerations:

 RoundOf(*ρ*)            Rounding mode of projection specification *ρ*, such that RoundOf((*r, s*)) = *r*.
 SatOf(*ρ*)               Saturation mode of projection specification *ρ*, such that SatOf((*r, s*)) = *s*.














  ^{10}The external formats binary64,binary32,binary16 are from [7], and BFloat16 from [8].

## 4.16 Next greater than and next less than
**Signature**

    NextGreaterThan_{*f*}(*x*) → *r*
    NextLessThan_{*f*}(*x*) → *r*
**Parameters**
     *f* : format of operand *x* and result *r*

**Operands**
     *x* : floating-point value, format *f*

**Result**
     *r* : floating-point value, format *f*

**Behavior**
    NextGreaterThanAux(∗, ∗, NaN) → NaN
    NextGreaterThanAux(∗, Extended, Inf) → NaN
    NextGreaterThanAux(∗, Finite, MaxFinite) → NaN
    NextGreaterThanAux(∗, Extended, MaxFinite) → Inf
    NextGreaterThanAux(Signed, Extended, −Inf) → MinFinite
    NextGreaterThanAux(Signed, ∗, SmallestNegative) → 0
    NextGreaterThanAux(Signed, ∗*, x*) if IsSignMinus(*x*) → *x* − 1
    NextGreaterThanAux(∗, ∗*, x*) → *x* + 1                   (See §4.1 for integer arithmetic on code points.)

    NextGreaterThan(*x*) → NextGreaterThanAux(SignednessOf(*f*), DomainOf(*f*)*, x*)

    NextLessThanAux(∗, ∗, NaN) → NaN
    NextLessThanAux(∗, Finite, MinFinite) → NaN
    NextLessThanAux(Unsigned, ∗, 0) → NaN
    NextLessThanAux(Signed, Extended, −Inf) → NaN
    NextLessThanAux(Signed, Extended, MinFinite) → −Inf
    NextLessThanAux(∗, Extended, Inf) → MaxFinite
    NextLessThanAux(Signed, ∗, 0) → SmallestNegative
    NextLessThanAux(Signed, ∗*, x*) if IsSignMinus(*x*) → *x* + 1
    NextLessThanAux(∗, ∗*, x*) → *x* − 1
    NextLessThan(*x*) → NextLessThanAux(SignednessOf(*f*), DomainOf(*f*)*, x*)

    where

    MaxFinite = MaxFiniteOf(*f*)
    MinFinite = MinFiniteOf(*f*)
    SmallestNegative = *ω*Encode_{*f*}(−*ω*Decode_{*f*}(MinPositiveOf(*f*)))   (The negative number of least magnitude)

NOTE 1—SmallestNegative is not expanded for unsigned formats.

NOTE 2—These operations follow IEEE-754 nextUp and nextDown operations, with extensions for signedness and
domain. The wording, using nextUp as an example, is extended from “least floating-point number that compares greater
than” to “least floating-point number that compares greater than, or NaN”. This requires that Inf → NaN, while IEEE-
754 defines nextUp(+∞) = +∞, so new names are chosen in this document.

# 5 Block operations

A block is a pair (*s,* [*x*_{1}*, ..., x*_{*B*}]) comprising a scale factor *s* in format *f*_{*s*} and a sequence of one or more elements *x*_{*i*},
each in format *f*_{*x*}.

These operations make use of the function reduce, defined as follows, for binary function *f*, and arguments *x*_{1}*, . . . , x*_{*n*}:

                    reduce(*f,* [*x*_{1}*, x*_{2}])  =  *f*(*x*_{1}*, x*_{2})
                reduce(*f,* [*x*_{1}*, . . . , x*_{*n*}])  =  reduce(*f,* [*f*(*x*_{1}*, x*_{2})*, x*_{3}*, . . . , x*_{*n*}])  for *n* ≥ 3

NOTE— Scaled operations are available as block operations using blocks of one element (§5.5).

## 5.1 Internal functions
### 5.1.1 Decoding

**Signature**
    *ω*BlockDecode_{*B,fs,fx*}(*s,* [*x*_{1}*, ..., x*_{*B*}]) → [*Z*_{1}*, ..., Z*_{*B*}]

**Parameters**
    *B* : block size
    *f*_{*s*} : format of scale factor *s*
    *f*_{*x*} : format of elements *x*

**Operands**
     *s* : scale factor, in format *f*_{*s*}
     x : sequence of floating-point values in format *f*_{*x*}
**Result**

    Z : sequence of closed extended real values
**Behavior**

    *ω*BlockDecode(*s,* [*x*_{1}*, ..., x*_{*B*}]) → [*Z*_{1}*, ..., Z*_{*B*}]
                                where
                                 *Z*_{*i*} = *ω*Multiply(*ω*Decode_{*fs*}(*s*), *ω*Decode_{*fx*}(*x*_{*i*}))

### 5.1.2 Projection
Convert a sequence of closed extended reals *X*_{1*..B*} to a block (*s,* [*r*_{1*..B*}]), with scale factor *s* supplied as an operand.

**Signature**
    *ω*BlockProject_{*B,fs,fr,ρ*}(*s,* [*X*_{1}*, ..., X*_{*B*}]) → [*r*_{1}*, ..., r*_{*B*}]

**Parameters**
    *B* : block size
    *f*_{*s*} : format of result scale factor *s*
    *f*_{*r*} : format of result elements *r*
     *ρ* : projection specification for elements

**Operands**
     *s* : result scale factor in format *f*_{*s*}
    X : sequence of closed extended reals
**Result**

     r : sequence of floating-point values in format *f*_{*r*}
**Behavior**

    *ω*BlockProject(*s,* [*X*_{1}*, ..., X*_{*B*}]) → [*r*_{1}*, ..., r*_{*B*}]
                      where
                        *S* = *ω*Decode_{*fs*}(*s*)
                            ⎧NaN             if *S* is NaN or *X*_{*i*} is NaN
                            ⎨0                if *S* = 0
                        *Z*_{*i*} =
                            ⎪sgn(*X*_{*i*}) × sgn(*S*)  if *S* = ±∞
                            ⎩*ω*Divide(*X*_{*i*}*, S*)    otherwise
                        *r*_{*i*} = *ω*Project_{*fr,ρ*}(*Z*_{*i*})

NOTE 1—If the scale factor *s* is zero, all non-NaN result elements are zero.

NOTE 2—If the scale factor *s* is infinite, all nonzero, non-NaN result elements are ±1.

## 5.2 Conversion of blocks
### 5.2.1 Conversion from a block

Convert a block (*s,* [*x*_{1*..B*}]) to a sequence of floating-point values *r*_{1*..B*}.

**Signature**
    ConvertFromBlock_{*B,fs,fx,fr,ρ*}(*s,* [*x*_{1}*, ..., x*_{*B*}]) → [*r*_{1}*, ..., r*_{*B*}]
**Parameters**

    *B* : block size
    *f*_{*s*} : format of scale factor operand *s*
    *f*_{*x*} : format of operand elements *x*_{*i*}
    *f*_{*r*} : format of result elements *r*
     *ρ* : projection specification for result elements
**Operands**

     *s* : scale factor in format *f*_{*s*}
     x : sequence of floating-point values in format *f*_{*x*}
**Result**
     r : sequence of floating-point values in format *f*_{*r*}

**Behavior**
    ConvertFromBlock(*s,* [*x*_{1}*, ..., x*_{*B*}]) → [*r*_{1}*, ..., r*_{*B*}]
                      where
                        [*Z*_{1}*, ..., Z*_{*B*}] = *ω*BlockDecode(*s,* [*x*_{1}*, ..., x*_{*B*}])
                        *r*_{*i*} = *ω*Project_{*fr,ρ*}(*Z*_{*i*})

### 5.2.2 Conversion to a block
Convert a sequence of floating-point values *x*_{1*..B*} to a block (*s,* [*r*_{1*..B*}]), with scale factor supplied as an operand.

**Signature**
    ConvertToBlock_{*B,fx,fs,fr,ρ*}([*x*_{1}*, ..., x*_{*B*}]*, s*) → (*s,* [*r*_{1}*, ..., r*_{*B*}])

**Parameters**
    *B* : block size
    *f*_{*x*} : format of operand elements *x*_{*i*}
    *f*_{*s*} : format of result scale factor *s*
    *f*_{*r*} : format of result elements *r*
     *ρ* : projection specification for result elements

**Operands**
     x : sequence of floating-point values in format *f*_{*x*}
     *s* : result scale factor, a floating-point value in format *f*_{*s*}
**Result**

     *s* : result scale factor, a floating-point value in format *f*_{*s*}
     r : sequence of floating-point values in format *f*_{*r*}
**Behavior**

    ConvertToBlock([*x*_{1}*, ..., x*_{*B*}]*, s*) → (*s,* [*r*_{1}*, ..., r*_{*B*}])
                      where
                        *X*_{*i*} = *ω*Decode_{*fx*}(*x*_{*i*})
                        [*r*_{1}*, ..., r*_{*B*}] = *ω*BlockProject_{*B,fs,fr,ρ*}(*s,* [*X*_{1}*, ..., X*_{*B*}])

### 5.2.3 Conversion to a block with scale factor computation
Convert a sequence of floating-point values *x*_{1*..B*} to a block (*s,* [*r*_{1*..B*}]), computing the scale factor as a maximum over
finite absolute values of *x*_{*i*}.

**Signature**
    ConvertToBlockMaxAbsFinite_{*B,fx,fs*}*,f*_{*r,ρs,ρ*}([*x*_{1}*, ..., x*_{*B*}]) → (*s,* [*r*_{1}*, ..., r*_{*B*}])

**Parameters**
    *B* : block size
    *f*_{*x*} : format of operand elements *x*_{*i*}
    *f*_{*s*} : format of result scale factor *s*
    *f*_{*r*} : format of result elements *r*
    *ρ*_{*s*} : projection specification for result scale factor
     *ρ* : projection specification for result elements

**Operands**
     x : sequence of floating-point values in format *f*_{*x*}
**Result**

     *s* : result scale factor, a floating-point value in format *f*_{*s*}
     r : sequence of floating-point values in format *f*_{*r*}
**Behavior**

    ConvertToBlockMaxAbsFinite([*x*_{1}*, ..., x*_{*B*}]) → (*s,* [*r*_{1}*, ..., r*_{*B*}])
                      where
                        *X*_{*i*} = *ω*Decode_{*fx*}(*x*_{*i*})
                        *M*_{*i*} = *ω*Abs(*X*_{*i*})
                        *S* = reduce(*ω*MaximumFinite, [NaN*, M*_{1}*, ..., M*_{*B*}])
                        *s* = *ω*Project_{*fs,ρs*}(*S*)
                        [*r*_{1}*, ..., r*_{*B*}] = *ω*BlockProject_{*B,fs,fr,ρ*}(*s,* [*X*_{1}*, ..., X*_{*B*}])

NOTE 1—If all *x*_{*i*} are NaN, the result scale factor and elements will be NaN.

NOTE 2—If all *x*_{*i*} are infinite, the result scale factor will be Inf or MaxFiniteOf(*f*_{*s*}) and the elements will be ±1 or
±MaxFiniteOf(*f*_{*r*}).
NOTE 3—If some *x* are infinite, they are preserved (or saturated, according to *ρ*) in the result, and do not influence
the scale of finite elements.*i*

NOTE 4—If the maximum value *S* rounds to zero under *ρ* , the result scale factor will be zero, and all result elements
will be zero.                                    *s*

NOTE 5—The projection specifications for the scale factor and elements allow implementation of some common
strategies, e.g., rounding *s* using TowardPositive and saturating *r*.

## 5.3 Block reduction operations
### 5.3.1 Sum and product

**Signature**
    BlockReduceAdd_{*B, fs,fx, fr,ρ*}((*s,* [*x*_{1}*, ..., x*_{*B*}])) → *r*
    BlockReduceMultiply_{*B, fs,fx, fr,ρ*}((*s,* [*x*_{1}*, ..., x*_{*B*}])) → *r*

**Parameters**
    *B* : block size
    *f*_{*s*} : format of scale factor operand *s*
    *f*_{*x*} : format of operand elements *x*_{*i*}
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
     *s* : scale factor, a floating-point value in format *f*_{*s*}
     x : sequence of floating-point values in format *f*_{*x*}
**Result**

     *r* : floating-point value in format *f*_{*r*}
**Behavior**

    BlockReduceAdd((*s,* [*x*_{1}*, ..., x*_{*B*}])) → *r*
                      where
                        [*X*_{1}*, ..., X*_{*B*}] = *ω*BlockDecode_{*B,fs,fx*}(*s,* [*x*_{1}*, ..., x*_{*B*}])
                        *R* = reduce(*ω*Add, [0*, X*_{1}*, ..., X*_{*B*}])
                        *r* = *ω*Project_{*fr,ρ*}(*R*)
    BlockReduceMultiply((*s,* [*x*_{1}*, ..., x*_{*B*}])) → *r*
                      where
                        [*X*_{1}*, ..., X*_{*B*}] = *ω*BlockDecode_{*B,fs,fx*}(*s,* [*x*_{1}*, ..., x*_{*B*}])
                        *R* = reduce(*ω*Multiply, [1*, X*_{1}*, ..., X*_{*B*}])
                        *r* = *ω*Project_{*fr,ρ*}(*R*)

### 5.3.2 Dot product
Dot product of two blocks of floating-point values.

**Signature**
    BlockDotProduct_{*B, fsx,fx*}*, f*_{*sy*}*,f*_{*y, fr,ρ*}((*s*_{*x*}, [*x*_{1}*, ..., x*_{*B*}]), (*s*_{*y*}, [*y*_{1}*, ..., y*_{*B*}])) → *r*

**Parameters**
    *B* : block size
   *f*_{*sx*} : format of scale factor operand *s*_{*x*}
    *f*_{*x*} : format of operand elements *x*_{*i*}
   *f*_{*sy*} : format of scale factor operand *s*_{*y*}
    *f*_{*y*} : format of operand elements *y*_{*i*}
    *f*_{*r*} : format of result *r*
     *ρ* : projection specification

**Operands**
    *s*_{*x*} : scale factor for *x*, a floating-point value in format *f*_{*sx*}
     x : sequence of floating-point values in format *f*_{*x*}
    *s*_{*y*} : scale factor for *y*, a floating-point value in format *f*_{*sy*}
    y : sequence of floating-point values in format *f*_{*y*}
**Result**

     *r* : floating-point value in format *f*_{*r*}
**Behavior**

    BlockDotProduct((*s*_{*x*}, [*x*_{1}*, ..., x*_{*B*}]), (*s*_{*y*}, [*y*_{1}*, ..., y*_{*B*}])) → *r*
                      where
                        [*X*_{1}*, ..., X*_{*B*}] = *ω*BlockDecode_{*B,fsx,fx*}(*s*_{*x*}, [*x*_{1}*, ..., x*_{*B*}])
                        [*Y*_{1}*, ..., Y*_{*B*}] = *ω*BlockDecode_{*B,fsy,fy*}(*s*_{*y*}, [*y*_{1}*, ..., y*_{*B*}])
                        *P*_{*i*} = *ω*Multiply(*X*_{*i*}*, Y*_{*i*})
                        *R* = reduce(*ω*Add, [0*, P*_{1}*, ..., P*_{*B*}])
                        *r* = *ω*Project_{*fr,ρ*}(*R*)

## 5.4 Elementwise operations on blocks
Operations on blocks are declared according to the following schema, where BlockOp is defined in terms of *ω*Op.

Note that the scale factor of the result block *s* is supplied as an *input* operand. Implementations are free to supply any
method of computation of this scale factor, and to supply an operation in which that computation is composed with the*r*
elementwise operation.

Valid substitutions for Op are:
   • Unary (*n* = 1): Convert, Abs, Negate, Sqrt, RSqrt, Recip, Exp, Log, ExpMinusOne, LogOnePlus, Exp2,
     Log2, Sin, Cos, Tan, ArcSin, ArcCos, ArcTan, Sinh, Cosh, Tanh, ArcSinh, ArcCosh, ArcTanh, SinPi, CosPi,
     TanPi, ArcSinPi, ArcCosPi, ArcTanPi, Softplus;

   • Binary (*n* = 2): CopySign, Add, Subtract, Multiply, Divide, Hypot, ArcTan2, ArcTan2Pi, Maximum,
     Minimum, MaximumNumber, MinimumNumber, MaximumMagnitude, MinimumMagnitude,
     MaximumMagnitudeNumber, MinimumMagnitudeNumber, MinimumFinite, MaximumFinite;

   • Ternary (*n* = 3): FMA, FAA, Clamp.
**Signature**

    BlockOp_{*B,*} _{(*fs*1}*,f*_{*x*1}),..., (*f*_{*sn*}*,f*_{*xn*})*, f*_{*s,fr,ρ*}((*s*_{1}, [*x*_{11}*, ..., x*_{1*B*}]), ..., (*s*_{*n*}, [*x*_{*n*1}*, ..., x*_{*nB*}])*, s*_{*r*}) → (*s*_{*r*}, [*r*_{1}*, ..., r*_{*B*}])
**Parameters**                                      **Operands**
    *B* : block size                                    *s*_{1} : scale factor, a floating-point value in format *f*_{*s*1}
   *f*_{*s*1} : format of first operand scale factor *s*_{1}              x_{1} : sequence of floating-point values in format *f*_{*x*1}
   *f*_{*x*1} : format of first operand element *x*_{1*i*}                 ... : ...
    ... : ...                                          *s*_{*n*} : scale factor, a floating-point value in format *f*_{*sn*}
   *f*_{*sn*} : format of *n*^{th} operand scale factor *s*_{*n*}               x_{*n*} : sequence of floating-point values in format *f*_{*xn*}
   *f*  : format of *n*^{th} operand elements *x*
    *xn*                            *ni*                *s*_{*r*} : result scale factor, a floating-point value in for-
    *f*_{*s*} : format of scale factor of result *s*_{*r*}              mat *f*_{*s*}
    *f*_{*r*} : format of result elements *r*
     *ρ* : projection specification for result elements


**Result**
    *s*_{*r*} : result scale factor, copied from operand
     r : sequence of floating-point values in format *f*_{*r*}

**Behavior**
    BlockOp((*s*_{1}, [*x*_{11}*, ..., x*_{1*B*}]), ..., (*s*_{*n*}, [*x*_{*n*1}*, ..., x*_{*nB*}])*, s*_{*r*}) → (*s*_{*r*}, [*r*_{1}*, ..., r*_{*B*}])
                      where
                        [*X*_{11}*, ..., X*_{1*B*}] = *ω*BlockDecode_{*B,fs*1*,fx*1}(*s*_{1}, [*x*_{11}*, ..., x*_{1*B*}])
                        ...
                        [*X*_{*n*1}*, ..., X*_{*nB*}] = *ω*BlockDecode_{*B,fsn,fxn*}(*s*_{*n*}, [*x*_{*n*1}*, ..., x*_{*nB*}])
                        *Z*_{*i*} = *ω*Op(*X*_{1*i*}*, ..., X*_{*ni*})  ∀*i* ∈ {1*, ..., B*}

                        [*r*_{1}*, ..., r*_{*B*}] = *ω*BlockProject_{*B,fs,fr,ρ*}(*s*_{*r*}, [*Z*_{1}*, ..., Z*_{*B*}])

## 5.5 Scaled operations via block operations
A block size of *B* = 1 provides scaled operations.

An *n*-ary scaled operation is defined as follows:

    ScaledOp_{(*f*} _{*,f*}  ),...,(*f*  *,f*  _{)*,f*} _{*,ρ*}(*s*_{1}*, x*_{1}*, ..., s*_{*n*}*, x*_{*n*}) → *r*
             *s*1 *x*1    *sn* *xn*  *r*                where
                                                (1, [*r*]) = BlockOp((*s*_{1}, [*x*_{1}]), ..., (*s*_{*n*}, [*x*_{*n*}]), 1)

NOTE—A choice of scale factor format with P = 1 allows scale factors to be restricted to powers of two.

**Appendices**


# Annex A (informative) Rationales and discussion

## A.1 General
The principle underpinning the design of floating-point formats is suitability for use in machine learning systems, where
narrow bitwidths are important for reducing energy usage, conserving memory space, and delivering timely results.
Therefore, rationales consider the cost of a feature in terms of number of code points required and its utility in machine
learning systems.


## A.2 Not a number (NaN)
Datum sets include exactly one NaN.

NaN is obtained from operation results that are outside the set of numerical values, e.g., division of zero by zero, or
addition of positive and negative infinities. Other floating-point systems define multiple NaN values. These encodings
are used to allow different exceptional conditions to be distinguished.

In the context of machine learning systems, uses of NaN include:
   • Debugging of code running on accelerator hardware. In machine learning accelerators, exceptions may be diffi-
     cult or expensive to convey back to user code, so it is common practice to allow NaN values to propagate through
     calculations to indicate that an error has occurred.

   • Use as a sentinel value. In some datasets, for example, where individual element values may be missing or out of
     range, a sentinel may be used to record the position of these values. In many cases, this will require less memory
     than storing such information out-of-band, such as in a coordinate-list (COO) format array. In some cases, ±Inf
     can be used as a missing value, but given the restricted range of the formats, it is likely that infinity will be used
     as a separate indicator of rounding from values outside of the finite range.

   • The use of multiple NaN payloads is known in statistical code (e.g., NaN and “not available” or NA), but it is
     not widely used in large-scale machine learning systems.
For our purposes, supporting multiple NaNs would reduce the already limited encoding space (e.g., occupying code
points where the exponent field is all ones, reducing dynamic range) and potentially increase hardware complexity.


## A.3 Zero
Datum sets include exactly one zero.

The inclusion of negative zero (−0) would incur the cost of an additional code point. Given the decision to encode only
a single NaN, placing that NaN at the code point where negative zero would be encoded enables the strictly positive
and strictly negative number ranges to be symmetric for signed formats.
A key rationale for including −0 in IEEE-754 was the consistent implementation of branch cuts in the ArcTan2 function
and the complex trigonometric functions [9, 10]. The ArcTan2 function is rarely used in deep learning applications.
The related ArcTan function is common in deep learning, however it is generally used as an activation function, rather
than a trigonometric operation.

A secondary reason for providing −0 is the hardware simplification offered by its presence in the implementation of
sign/magnitude arithmetic. However, current practice has made it evident that the small hardware simplification has
not been sufficient to balance the loss of one code point.
Another reason for including −0 in IEEE-754 was to allow the reciprocal of a signed infinity to be the corresponding
signed zero. In this standard the reciprocal of either infinity is zero, and a corollary of that decision is that dividing by
zero produces NaN, not an infinity.

The use of integer comparisons in sorting might argue against placing NaN at the negative zero code point. For example,
the JAX machine learning framework is known to sort using integer comparison [5]. However, such sorting still requires
*O*(*n*) additional processing steps to enable the use of two’s-complement integer comparison, and already has special
treatment of NaN and −0. Eliminating −0 and placing NaN in the −0 position imposes negligible additional burden.

## A.4 Infinities

Representing infinite values requires two code points in a signed format, and for narrow formats, the reduction in
number of finite values may be significant. Hence formats are defined using the finite and extended domains.

Infinite values are used widely in machine learning systems. Examples of such usage are:
   • Mask values, for example in transformer models in machine learning [13].

   • Representation of overflow, for example to adjust dynamic loss scaling factors [16].

The following example shows that in certain machine learning computations, it is insufficient to substitute an infinity
with the largest finite value.


























                                                                         [Continued on next page]

*Example:*
  Consider the use of infinity in computation of attention masks. These values, assembled in a mask vector *M* with
  values *M*_{*i*} ∈ {0, −∞}, are typically added to computed values *A* in a computation such as:


                                   log(∑_{*i*} exp(*τ* × (*A*_{*i*} + *M*_{*i*})))

  where *τ >* 0 is a “temperature” or “base” parameter [4]. This calculation depends on the fact that exp(*τ* × (*A*_{*i*} −
  ∞)) = 0. The operation sequence log(∑_{*i*} exp(*v*_{*i*})) is typically fused into a single block operation logsumexp(*v*).
  For formats without infinities, *M*_{*i*} = ∞ will be replaced by a large float (e.g., the largest finite Binary8p4sf value
  is 240.0). This is not in itself a difficulty: if all the *A* values are bounded (e.g., the results of a softmax operation
  are bounded above by 1.0), then exp(1.0 − 240.0) is an extremely small number, sufficiently small to round to zero.
  Therefore, an explicit representation of infinity is *not* needed in order for this computation to yield its desired value.

  However, careful implementations do not execute the calculation as written; instead, the implementation of
  logsumexp makes use of the identity transformation

                          logsumexp(*v*) → logsumexp(*v* − max(*v*)) + max(*v*)

  Without the “sticky” properties of Inf, this would produce incorrect answers, as follows.
  For example, compare a format using the finite domain where maxFinite=240, and a format using the extended
  domain. In both cases, the value 224.0 is representable, and the logsumexp calculation on a two-element vector
  might be, in a format with infinity:

                       logsumexp(*τ* × [−224.0, −∞]) → logsumexp(*τ* × [0, −∞]),

  and in a format without infinity:

                     logsumexp(*τ* × [−224.0, −240.0]) → logsumexp(*τ* × [0, −16.0]).

  If *τ* = 1 and all calculations are done in 8-bit floating-point, then the two answers will be the same, because
  exp(−16) ≈ 1.1×10^{−7}, which will round to zero in all precisions P > 2. However, if *τ* is small, or calculations are
  done in mixed precision, the loss of “stickiness” will silently yield unexpected answers. It is not expected that the
  full calculation would be done in 8-bit floating-point, but the subtraction of the maximum value (and computation
  of the maximum) might reasonably be done in 8-bit floating-point.

## A.5 Exponent bias
The exponent bias is derived from the format-defining parameters using the formula in §3.1.

This differs from IEEE-754, where the exponent bias is defined in terms of emax, the exponent of the largest finite
value, which is in turn derived from the IEEE-754 interchange format parameters *k* and *p*.

The maximum exponent emax is

                           ⎧2^{K−1} − 3    if P = 1, Σ = Unsigned, Δ = Extended
                           ⎪2^{K−1} − 2    if P = 1, Σ = Unsigned, Δ = Finite
                           ⎨2^{K−2} − 2    if P = 1, Σ = Signed, Δ = Extended
                    emax =
                           ⎪2^{K−2} − 2    if P = 2, Σ = Unsigned, Δ = Extended
                           ⎪2^{K−P−1} − 1  otherwise if Σ = Signed
                           ⎩2^{K−P} − 1    otherwise if Σ = Unsigned

A consequence of these specifications is that the datum 1.0 encodes consistently to the midway code point, that is 2^{K−2}
for signed formats and 2^{K−1} for unsigned formats.


## A.6 Subnormals
Subnormal numbers extend the dynamic range of floating-point values and induce equal quantization steps close to zero.
This is useful when training models, where it is common for gradients to have near-zero non-zero values. Subnormals
can also be useful to represent random values drawn from certain distributions, e.g., where model weights are initialized
to small random values for training.

Subnormals are uniformly spaced around zero, and near-zero values are more probable under bell-shaped distributions.
Formats with narrow exponent bitwidths necessarily have a limited range; subnormals extend this range by a power of
two for every bit in the trailing significand.

The datum sets of formats with precision greater than one include subnormals; this does not preclude implementations
of operations from flushing subnormals to zero, under the provision for approximate operations in §4.4.

# Annex B (informative) Encoding

A K-bit floating-point value is encoded by an integer in the range 0 to 2^{K} − 1. Some properties of this encoding are
summarized here, while the detailed specification of the encoding is presented in §4.7.6.

All formats contain a single zero, encoded by the integer 0.

All formats contain a single NaN. For signed formats, NaN is encoded at the code point which IEEE-754 uses for
negative zero, that is 2^{K−1}. For unsigned formats, NaN is encoded at 2^{K} − 1.
Extended formats contain one or two infinities. For signed formats, Inf is encoded at 2^{K−1} − 1 and −Inf is encoded at
2^{K} − 1. For unsigned formats, Inf is encoded at 2^{K} − 2.

Table 3 summarizes the encodings of selected special values.

     Datum          Symbol Signed extended Signed finite Unsigned extended Unsigned finite

     Zero                0.0        0             0              0               0
     One                1.0     2^{K−2} − 0      2^{K−2} − 0       2^{K−1} − 0        2^{K−1} − 0
     Not a Number       NaN     2^{K−1} − 0      2^{K−1} − 0       2^{K−0} − 1        2^{K−0} − 1
     Positive Infinity       Inf     2^{K−1} − 1        N/A         2^{K−0} − 2          N/A
     Negative Infinity     −Inf     2^{K−0} − 1        N/A            N/A             N/A
                   Table 3—Encodings of selected datums for given K, independent of P.

## B.1 Value tables
Tables 4, 5, 6, and 7 show the complete value sets for K = 4. Subnormals are shown in *underlined italic*, special
values are shown in **bold**.

                       Code point    Binary4p1se  Binary4p2se  Binary4p3se
                        0 0b0000        Zero       Zero       Zero
                        1 0b0001       0.1250      *<u>0.2500</u>*      *<u>0.2500</u>*
                        2 0b0010       0.2500      0.5000      *<u>0.5000</u>*
                        3 0b0011       0.5000      0.7500      *<u>0.7500</u>*
                        4 0b0100       1.0000      1.0000      1.0000
                        5 0b0101       2.0000      1.5000      1.2500
                        6 0b0110       4.0000      2.0000      1.5000
                        7 0b0111          Inf         Inf         Inf
                        8 0b1000        NaN       NaN       NaN
                        9 0b1001      −0.1250      *<u>−0.2500</u>*      *<u>−0.2500</u>*
                       10 0b1010      −0.2500      −0.5000      *<u>−0.5000</u>*
                       11 0b1011      −0.5000      −0.7500      *<u>−0.7500</u>*
                       12 0b1100      −1.0000      −1.0000      −1.0000
                       13 0b1101      −2.0000      −1.5000      −1.2500
                       14 0b1110      −4.0000      −2.0000      −1.5000
                       15 0b1111         −Inf        −Inf        −Inf

              Table 4—Value sets for K = 4, signed formats with 1 ≤ P < 4, extended domain.

                        Code point    Binary4p1sf   Binary4p2sf   Binary4p3sf
                        0 0b0000        Zero       Zero       Zero
                        1 0b0001       0.1250      *<u>0.2500</u>*      *<u>0.2500</u>*
                        2 0b0010       0.2500      0.5000      *<u>0.5000</u>*
                        3 0b0011       0.5000      0.7500      *<u>0.7500</u>*
                        4 0b0100       1.0000      1.0000      1.0000
                        5 0b0101       2.0000      1.5000      1.2500
                        6 0b0110       4.0000      2.0000      1.5000
                        7 0b0111       8.0000      3.0000      1.7500
                        8 0b1000        NaN       NaN       NaN
                        9 0b1001      −0.1250     *<u>−0.2500</u>*     *<u>−0.2500</u>*
                       10 0b1010      −0.2500     −0.5000     *<u>−0.5000</u>*
                       11 0b1011      −0.5000     −0.7500     *<u>−0.7500</u>*
                       12 0b1100      −1.0000     −1.0000     −1.0000
                       13 0b1101      −2.0000     −1.5000     −1.2500
                       14 0b1110      −4.0000     −2.0000     −1.5000
                       15 0b1111      −8.0000     −3.0000     −1.7500

                Table 5—Value sets for K = 4, signed formats with 1 ≤ P < 4, finite domain.

                 Code point    Binary4p1ue  Binary4p2ue  Binary4p3ue  Binary4p4ue
                 0 0b0000        Zero        Zero        Zero        Zero
                 1 0b0001     ≈0.0078      *<u>0.0625</u>*      *<u>0.1250</u>*      *<u>0.1250</u>*
                 2 0b0010     ≈0.0156      0.1250      *<u>0.2500</u>*      *<u>0.2500</u>*
                 3 0b0011     ≈0.0312      0.1875      *<u>0.3750</u>*      *<u>0.3750</u>*
                 4 0b0100       0.0625      0.2500      0.5000      *<u>0.5000</u>*
                 5 0b0101       0.1250      0.3750      0.6250      *<u>0.6250</u>*
                 6 0b0110       0.2500      0.5000      0.7500      *<u>0.7500</u>*
                 7 0b0111       0.5000      0.7500      0.8750      *<u>0.8750</u>*
                 8 0b1000       1.0000      1.0000      1.0000      1.0000
                 9 0b1001       2.0000      1.5000      1.2500      1.1250
                10 0b1010       4.0000      2.0000      1.5000      1.2500
                11 0b1011       8.0000      3.0000      1.7500      1.3750
                12 0b1100      16.0000      4.0000      2.0000      1.5000
                13 0b1101      32.0000      6.0000      2.5000      1.6250
                14 0b1110          Inf         Inf         Inf         Inf
                15 0b1111        NaN        NaN        NaN        NaN
             Table 6—Value sets for K = 4, unsigned formats with 1 ≤ P ≤ 4, extended domain.








                  Code point    Binary4p1uf   Binary4p2uf   Binary4p3uf   Binary4p4uf
                  0 0b0000        Zero        Zero        Zero        Zero
                  1 0b0001     ≈0.0078      *<u>0.0625</u>*      *<u>0.1250</u>*      *<u>0.1250</u>*
                  2 0b0010     ≈0.0156      0.1250      *<u>0.2500</u>*      *<u>0.2500</u>*
                  3 0b0011     ≈0.0312      0.1875      *<u>0.3750</u>*      *<u>0.3750</u>*
                  4 0b0100       0.0625      0.2500      0.5000      *<u>0.5000</u>*
                  5 0b0101       0.1250      0.3750      0.6250      *<u>0.6250</u>*
                  6 0b0110       0.2500      0.5000      0.7500      *<u>0.7500</u>*
                  7 0b0111       0.5000      0.7500      0.8750      *<u>0.8750</u>*
                  8 0b1000       1.0000      1.0000      1.0000      1.0000
                  9 0b1001       2.0000      1.5000      1.2500      1.1250
                 10 0b1010       4.0000      2.0000      1.5000      1.2500
                 11 0b1011       8.0000      3.0000      1.7500      1.3750
                 12 0b1100      16.0000      4.0000      2.0000      1.5000
                 13 0b1101      32.0000      6.0000      2.5000      1.6250
                 14 0b1110      64.0000      8.0000      3.0000      1.7500
                 15 0b1111        NaN        NaN        NaN        NaN
               Table 7—Value sets for K = 4, unsigned formats with 1 ≤ P ≤ 4, finite domain.

# Annex C (informative) Value tables for K=2

Table 8 shows the floating-point value sets for K = 2 formats which follow the patterns in this document. Not all of
these formats will typically be useful in practice, but they are included for completeness. As the table shows, certain
peculiarities are evident:

   • The formats Binary2p1ue and Binary2p2ue have the same datum set, albeit a different partitioning of subnormals.
   • Similarly the formats Binary2p1uf and Binary2p2uf have the same datum set.

   • The datum 1.0 is not present in Binary2p1se, Binary2p1ue, Binary2p2ue, hence is not encoded according to
     Table 3.

   • Binary2p1se has no normal or subnormal values, hence MinPositiveOf(Binary2p1se) = Inf.
   • Binary2p1se and Binary2p2ue have no normal values, hence MinNormalOf(*f*) = NaN for these formats.


    Code point   Binary2p1se  Binary2p1sf   Binary2p1ue  Binary2p2ue  Binary2p1uf   Binary2p2uf
    0 0b00          Zero        Zero        Zero        Zero        Zero        Zero
    1 0b01            Inf        1.000        0.500        *<u>0.500</u>*        0.500        *<u>0.500</u>*
    2 0b10          NaN        NaN          Inf          Inf        1.000        1.000
    3 0b11           −Inf       −1.000        NaN        NaN        NaN        NaN

        Table 8—Value sets for K = 2. Subnormals are shown in *<u>underlined italic</u>*, special values in **bold**.

# Annex D (informative) Examples of approximation declarations

## D.1 Example: Approximate implementation of Exp

Consider an implementation of Exp<binary32, Binary8p4se, (NearestTiesToEven, SatNone)> which flushes subnor-
mals in the result to zero or to the smallest normal, whichever is nearest, with ties going to zero. There are seven
nonzero positive subnormals in Binary8p4se, of which four will be flushed to zero, and three will be returned as the
smallest normal. Hence the value of *κ* over all inputs producing finite results is 4. Writing the cut points *a, b, c* =
ln(2^{−11}), ln(9 · 2^{−11}), ln(15 · 2^{−11}), the intervals are:

                   *I*_{0} = D_{binary32} ∩ ((−∞*, a*) ∪ (*c,* +∞))                   *κ*_{*I*0} = 0
                   *I*_{4} = D_{binary32} ∩ (*a, b*)                                *κ*_{*I*4} = 4
                   *I*_{3} = D_{binary32} ∩ (*b, c*)                                *κ*_{*I*3} = 3

and the implementation would declare
                                    *κ* ∈ {*I*_{0} : 0*, I*_{3} : 3*, I*_{4} : 4}.

Note that as *a, b, c* are irrational, the sets *I*_{0}*, I*_{3}*, I*_{4} are disjoint and cover all inputs producing finite results.

## D.2 Example: Approximate implementation of BlockDotProduct
Consider an implementation of dot product on blocks of size 8, with Binary8p4se elements and Binary8p1uf scale
factors, with a binary32 result, rounding mode NearestTiesToEven and saturation mode SatNone. This is the operation
specialization

  BlockDotProduct<8,Binary8p1uf,Binary8p4se,Binary8p1uf,Binary8p4se,binary32,(NearestTiesToEven,SatNone)>

Suppose the nature of the implementation is such that it matches on NaNs and infinities, but has only the trivial bound
*κ* = 2^{32} − 2^{24} − 1 over all inputs producing finite results. The implementation may choose to declare *κ* over a subset
of the input space, for example by declaring

                    *I*_{0} = {(*s*_{*x*}, [*x*_{1}*, ..., x*_{8}]*, s*_{*y*}, [*y*_{1}*, ..., y*_{8}]) such that
                                                  *s*_{*x*} = 1.0,
                                                  *s*_{*y*} = 1.0,
                                                  Abs(*x*_{*i*}) ≤ 2.0 for *i* ∈ {1, 2},

                                                  *x*_{*i*} = 0.0 for *i* ∈ {3 . . . 8},
                                                  Abs(*y*_{*i*}) ≤ 2.0 for *i* ∈ {1, 2},
                                                  *y*_{*i*} = 0.0 for *i* ∈ {3 . . . 8}
                                                  }


and that *κ*_{*I*₀} = 3, while *κ*_{*I*∖*I*₀} is the trivial bound as above.
This permits the implementation to provide a useful guarantee over a subset of the input space, while still providing a
trivial guarantee over all inputs as required. Annex E shows an approach to characterization of accuracy for reduction
operations.

# Annex E (informative) Recommendations for reduction accuracy specifications

## E.1 BlockReduceAdd

It is suggested that a finite error bound for the operation BlockReduceAdd be provided. Such a bound should apply at
least whenever the output is finite. Examples of such bounds are given by Higham [6, §4.2] and by Blanchard et al. [1].

*Example:*
  Consider a block of length *B* = 8, with arguments and output in Binary8p4se, where the accumulation is performed
  in binary16 using NearestTiesToEven, and the inputs are summed sequentially in any order. Let

                                       *S* = *X*_{1} + · · · + *X*_{8}
  denote the true sum, and let *S̃* denote the implementation’s approximate result. In the absence of overflow in *S̃*,

                                                           8
                              |*S* − *S̃*| ≤ |*S*|/16 + 3.637 × 10^{−3} ∑ |*X*_{*i*}| .
                                                          *i*=1

   The constant 3.637×10^{−3} is obtained by rounding up (1 + 1/16)((1 + 2^{−11})^{7} − 1), where the constants are obtained
  as follows: 11 is the accumulator precision, i.e., PrecisionOf(binary16); 7 = *B* − 1 is the number of additions; and
   16 = 2^{PrecisionOf(Binary8p4se)}.

## E.2 BlockReduceMultiply
It is suggested that a finite error bound for the operation BlockReduceMultiply be provided. Such a bound should apply
at least whenever the output is finite. Examples of such bounds are given by Higham [6, §2.2].

*Example:*
  Consider a block of length 8, with arguments and output in Binary8p4se, where the multiplications are performed in
  binary16 using NearestTiesToEven, sequentially in any order. Let

                                       *P* = *X*_{1} × · · · × *X*_{8}
  denote the true product, and let *P̃* denote the implementation’s approximate result. In the absence of underflow or
  overflow, both intermediate and final,

                                  |*P* − *P̃*| ≤ |*P*| × 6.614 × 10^{−2}.

   The constant 6.614 × 10^{−2} is obtained by rounding up (1 + 1/16)(1 + 2^{−11})^{7} − 1, where the constants are obtained
  as follows: 11 is the accumulator precision, i.e., PrecisionOf(binary16); 7 = *B* −1 is the number of multiplications;
   and 16 = 2^{PrecisionOf(Binary8p4se)}.

## E.3 BlockDotProduct
It is suggested that a finite error bound for the operation BlockDotProduct be provided. Such a bound should apply at
least whenever the output is finite and the final rounding does not underflow. Examples of such bounds are given by
Higham [6, §3.1] and by Blanchard et al. [1]. More generally applicable bounds may be complicated by implementation
choices, for example when the precision used for the individual products varies during the computation.

*Example:*
  Consider a block of length 8, with arguments and output in Binary8p4se, where the multiplications and accumulation
  are performed in binary16 using NearestTiesToEven, and the products are summed sequentially in any order. Let

                                   *D* = *X*_{1} × *Y*_{1} + · · · + *X*_{8} × *Y*_{8}

  denote the true dot product, and let *D̃* denote the implementation’s approximate result. In the absence of overflow,
  both intermediate and final, and if the final rounding does not underflow, then
                                                         8
                           |*D* − *D̃*| ≤ |*D*|/16 + 3.637 × 10^{−3} ∑ |*X*_{*i*} × *Y*_{*i*}|.

                                                        *i*=1
  In this example the products *X*_{*i*} × *Y*_{*i*} are exact, while intermediate underflows, if they occur, are exact.
   The constant 3.637×10^{−3} is obtained by rounding up (1 + 1/16)((1 + 2^{−11})^{7} − 1), where the constants are obtained
  as follows: 11 is the accumulator precision, i.e., PrecisionOf(binary16); 7 = *B* − 1 is the number of additions; and
   16 = 2^{PrecisionOf(Binary8p4se)}.

# Annex F (informative) External formats

This table summarizes the points of agreement and of difference between a number of existing format families, some
of which have hardware implementations, and their P3109 analogs.

OCP: Open Compute Platform [11], describing hardware implementations including nVidia, Intel, and ARM.
AGQ: AMD, Graphcore, Qualcomm[12], implemented in Graphcore’s C600 product, and AMD’s gfx940.

TSL: Tesla Dojo Technology [14].

    Format               Binary{K, P, Σ, Δ}           OCP             AGQ         TSL
    Subformat          k8p1uf k8p3se k8p4se E8M0 E5M2 E4M3 E5M2 E4M3 E5M2 E4M3
    Special values shared           Y                   N               Y            N

    Exactly one NaN              Y             Y        N            Y            Y
    Include negative zero           N             N        Y            N            N
    Has infinity           N         Y         N     Y     N        N            N
    Max exponent emax    126     15      7     127    15     8     15     7    N/A   N/A

Max exponent for TSL is marked as N/A given the configurable bias.

“Special values shared” means that format families within an implementation with the same signedness and domain
share the encodings of special values.

# Annex G (informative) Operation groups

Operations are defined in groups as follows
Group A (Core)                               Group KA (Block Core)
Convert*<f*_{*x*}*, f*_{*r*}*, ρ>*                                 ConvertFromBlock*<B, f*_{*s*}*, f*_{*x*}*, f*_{*r*}*, ρ>*
Negate*<f*_{*x*}*, f*_{*r*}*, ρ>*                                 ConvertToBlock*<B, f*_{*x*}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Abs*<f*_{*x*}*, f*_{*r*}*, ρ>*                                    ConvertToBlockMaxAbsFinite*<B, f*_{*x*}*, f*_{*s*}*, f*_{*r*}*, ρ*_{*s*}*, ρ>*
Add*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                                 BlockConvert*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Subtract*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                             BlockNegate*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Multiply*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                              BlockAbs*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
FMA*<f*_{*x*}*, f*_{*y*}*, f*_{*z*}*, f*_{*r*}*, ρ>*                              BlockAdd*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
FAA*<f*_{*x*}*, f*_{*y*}*, f*_{*z*}*, f*_{*r*}*, ρ>*                              BlockSubtract*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Minimum*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                             BlockMultiply*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Maximum*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                            BlockFMA*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*3}*, f*_{*x*3}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MinimumNumber*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                       BlockFAA*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*3}*, f*_{*x*3}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MaximumNumber*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                      BlockMinimum*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MinimumMagnitude*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                     BlockMaximum*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MaximumMagnitude*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                    BlockMinimumNumber*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MinimumMagnitudeNumber*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*              BlockMaximumNumber*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MaximumMagnitudeNumber*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*              BlockMinimumMagnitude*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MinimumFinite*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                        BlockMaximumMagnitude*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
MaximumFinite*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                        BlockMinimumMagnitudeNumber*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Clamp*<f*_{*x*}*, f*_{lo}*, f*_{hi}*, f*_{*r*}*, ρ>*                            BlockMaximumMagnitudeNumber*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
CompareLess*<f*_{*x*}*, f*_{*y*}>                              BlockMinimumFinite*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
CompareLessEqual*<f*_{*x*}*, f*_{*y*}>                          BlockMaximumFinite*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
CompareEqual*<f*_{*x*}*, f*_{*y*}>                             BlockClamp*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*3}*, f*_{*x*3}*, f*_{*s*}*, f*_{*r*}*, ρ>*
CompareGreater*<f*_{*x*}*, f*_{*y*}>
CompareGreaterEqual*<f*_{*x*}*, f*_{*y*}>
IsZero*<f >*                                       Group M (Meta)
IsOne*<f >*
IsNaN*<f >*                                       BitwidthOf*<f >*
IsInfinite*<f >*                                     PrecisionOf*<f >*
IsFinite*<f >*                                      SignednessOf*<f >*
IsSignMinus*<f >*                                  DomainOf*<f >*
IsNormal*<f >*                                     ExponentBitwidthOf*<f >*
IsSubnormal*<f >*                                  TrailingSignificandBitwidthOf*<f >*
                                               ExponentBiasOf*<f >*
                                               MaxFiniteOf*<f >*
                                               MinFiniteOf*<f >*
                                               MinPositiveOf*<f >*
                                               MaxSubnormalOf*<f >*
                                               MinNormalOf*<f >*

Group B (Basic)                               Group KB (Block Basic)
Divide*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                               BlockDivide*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Sqrt*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockSqrt*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Recip*<f*_{*x*}*, f*_{*r*}*, ρ>*                                  BlockRecip*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
RSqrt*<f*_{*x*}*, f*_{*r*}*, ρ>*                                  BlockRSqrt*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Exp*<f*_{*x*}*, f*_{*r*}*, ρ>*                                    BlockExp*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Exp2*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockExp2*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ExpMinusOne*<f*_{*x*}*, f*_{*r*}*, ρ>*                            BlockExpMinusOne*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Log*<f*_{*x*}*, f*_{*r*}*, ρ>*                                    BlockLog*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Log2*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockLog2*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
LogOnePlus*<f*_{*x*}*, f*_{*r*}*, ρ>*                             BlockLogOnePlus*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Softplus*<f*_{*x*}*, f*_{*r*}*, ρ>*                                BlockSoftplus*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
NextGreaterThan*<f >*                              BlockCopySign*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
NextLessThan*<f >*
CopySign*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*
TotalOrder*<f*_{*x*}*, f*_{*y*}>
Class*<f >*

Group C (Full)                                 Group KC (Block Full)
Hypot*<f*_{*x*}*, f*_{*y*}*, f*_{*r*}*, ρ>*                               BlockHypot*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcTan2*<f*_{*y*}*, f*_{*x*}*, f*_{*r*}*, ρ>*                             BlockArcTan2*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcTan2Pi*<f*_{*y*}*, f*_{*x*}*, f*_{*r*}*, ρ>*                            BlockArcTan2Pi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*2}*, f*_{*x*2}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Sin*<f*_{*x*}*, f*_{*r*}*, ρ>*                                    BlockSin*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Cos*<f*_{*x*}*, f*_{*r*}*, ρ>*                                    BlockCos*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Tan*<f*_{*x*}*, f*_{*r*}*, ρ>*                                    BlockTan*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcSin*<f*_{*x*}*, f*_{*r*}*, ρ>*                                 BlockArcSin*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcCos*<f*_{*x*}*, f*_{*r*}*, ρ>*                                 BlockArcCos*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcTan*<f*_{*x*}*, f*_{*r*}*, ρ>*                                 BlockArcTan*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Sinh*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockSinh*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Cosh*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockCosh*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
Tanh*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockTanh*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcSinh*<f*_{*x*}*, f*_{*r*}*, ρ>*                                 BlockArcSinh*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcCosh*<f*_{*x*}*, f*_{*r*}*, ρ>*                                BlockArcCosh*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcTanh*<f*_{*x*}*, f*_{*r*}*, ρ>*                                BlockArcTanh*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
SinPi*<f*_{*x*}*, f*_{*r*}*, ρ>*                                   BlockSinPi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
CosPi*<f*_{*x*}*, f*_{*r*}*, ρ>*                                  BlockCosPi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
TanPi*<f*_{*x*}*, f*_{*r*}*, ρ>*                                  BlockTanPi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcSinPi*<f*_{*x*}*, f*_{*r*}*, ρ>*                                BlockArcSinPi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcCosPi*<f*_{*x*}*, f*_{*r*}*, ρ>*                               BlockArcCosPi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*
ArcTanPi*<f*_{*x*}*, f*_{*r*}*, ρ>*                               BlockArcTanPi*<B, f*_{*s*1}*, f*_{*x*1}*, f*_{*s*}*, f*_{*r*}*, ρ>*

                                               Group E (Block Reductions)
                                               BlockReduceAdd*<B, f*_{*s*}*, f*_{*x*}*, f*_{*r*}*, ρ>*
                                               BlockReduceMultiply*<B, f*_{*s*}*, f*_{*x*}*, f*_{*r*}*, ρ>*
                                               BlockDotProduct*<B, f*_{*sx*}*, f*_{*x*}*, f*_{*sy*}*, f*_{*y*}*, f*_{*r*}*, ρ>*

# Annex H (informative) Bibliography

**References**

 [1] P. Blanchard, N. J. Higham, F. Lopez, T. Mary, and S. Pranesh, “Mixed precision block fused multiply-add:
    Error analysis and application to GPU tensor cores,” *SIAM Journal on Scientific Computing*, vol. 42, no. 3, pp.
    C124–C141, 2020.

 [2] T.-C. Chang, S. Park, J. P. Lim, and S. Nagarakatte, “FLoPS: Semantics, operations, and properties of P3109
    floating-point representations in Lean,” 2026, rutgers Department of Computer Science Technical Report
    DCS-TR-762. [Online]. Available: https://arxiv.org/abs/2602.15965

 [3] A. W. Fitzgibbon and S. Felix, “On stochastic rounding with few random bits,” in *IEEE 32nd Symposium on*
    *Computer Arithmetic, ARITH 2025, El Paso, TX, USA, May 4-7, 2025*. IEEE, 2025, pp. 133–140. [Online].
    Available: https://doi.org/10.1109/ARITH64983.2025.00029
 [4] I. Goodfellow, Y. Bengio, and A. Courville, *Deep Learning*. MIT Press, 2016, ch. 6.2.2.3 Softmax Units for
    Multinoulli Output Distributions, pp. 180–184.

 [5] Google, “Jax lax package:    float to int for sort ,” https://github.com/google/jax/blob/fc5960f2b8/jax/ src/
    lax/lax.py#L3934.

 [6] N. J. Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed. SIAM, 2002.
 [7] IEEE Computer Society, “IEEE standard for floating-point arithmetic,” *IEEE Std 754-2019 (Revision of IEEE*
    *754-2008)*, pp. 1–84, 2019.

 [8] N. P. Jouppi, C. Young, N. Patil, D. Patterson, G. Agrawal, R. Bajwa, S. Bates, S. Bhatia, N. Boden, A. Borchers
    *et al.*, “Cloud TPU: Machine learning accelerators for training and inference,” *IEEE Micro*, vol. 38, no. 2, pp.
    39–47, 2018.

 [9] W. Kahan, “Branch cuts for complex elementary functions or much ado about nothing’s sign bit,” *Institute of*
    *Mathematics and its Applications Conference*, 1987, https://www.arithmazium.org/library/lib/wk branch cuts
    86.pdf.
[10] W. Kahan and J. W. Thomas, “Augmenting a programming language with complex arithmetic,” EECS Depart-
    ment, University of California, Berkeley, Tech. Rep. UCB/CSD-92-667, 1991, https://www2.eecs.berkeley.edu/
    Pubs/TechRpts/1992/6127.html.

[11] P. Micikevicius, S. Oberman, P. Dubey, M. Cornea, A. Rodriguez, I. Bratt, R. Grisenthwaite, N. Jouppi, C. Chou,
    A. Huffman, M. Schulte, R. Wittig, D. Jani, and S. Deng, “OCP 8-bit floating point specification (OFP8) revision
    1.0,” opencompute.org, Tech. Rep., 2023.

[12] B. Noune, P. Jones, D. Justus, D. Masters, and C. Luschi, “8-bit numerical formats for deep neural networks,”
    arXiv cs.LG, Tech. Rep., 2022, https://arxiv.org/abs/2206.02915.
[13] PyTorch authors, “Pytorch torchtext package:   t5 multi head attention forward ,” https://github.com/pytorch/
    text/blob/a933cbe5a008bc2cb61d985cf5864069194157eb/torchtext/prototype/models/t5/modules.py#L236.

[14] Tesla, Inc., “Tesla Dojo Technology: A guide to Tesla’s configurable floating point formats and
    arithmetic,” 2023, https://web.archive.org/web/20230503235751/https://tesla-cdn.thron.com/static/MXMU3S
    tesla-dojo-technology 1WDVZN.pdf.
[15] C. M. Wintersteiger, “Formal verification of the IEEE P3109 standard for binary floating-point formats for ma-
    chine learning,” in *IEEE 32nd Symposium on Computer Arithmetic, ARITH 2025, El Paso, TX, USA, May 4-7*.
    IEEE, 2025, https://github.com/imandra-ai/ieee-p3109.

[16] R. Zhao, B. Vogel, and T. Ahmed, “Adaptive loss scaling for mixed precision training,” arXiv cs.LG, Tech. Rep.,
    2019, https://arxiv.org/abs/1910.12385.
