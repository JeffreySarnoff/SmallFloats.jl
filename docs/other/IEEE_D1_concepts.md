<!--
Concept map for IEEE P3109/D1 (July 2026) draft.
Source document: IEEE_D1.md (2948 lines).  Section index: IEEE_D1.json
Every concept node carries a link of the form IEEE_D1.md#L<line> back to the draft.
Normative = clauses 1..5.  Informative = Annexes A..H.
-->

# IEEE P3109/D1 — Concept Map

Concept map of the whole draft **Arithmetic Formats for Machine Learning**
(IEEE P3109/D1, July 2026), source [IEEE_D1.md](IEEE_D1.md), section index
[IEEE_D1.json](IEEE_D1.json).

> **Scope.** This is a map of the external D1 specification, not a map of the
> SmallFloats.jl source tree. It is intentionally stable with the D1 snapshot.
> The implementation-facing chain is [extendingK.md](extendingK.md) for design
> decisions, [doingtheextensions.md](doingtheextensions.md) for the resulting
> architecture, and [implementextensions.md](implementextensions.md) for the
> executed stages and conformance gates. Current code remains the authority when
> an implementation record and a source file differ.

## 0. How to read

- Nodes are **concepts** (types, parameters, functions, modes, artifacts).
- Edges are **labeled relations**, not control flow. Relation vocabulary:

| Relation | Meaning |
| --- | --- |
| `parameterizes` | left is a defining parameter of right |
| `derives` | right is computed from left by a fixed formula |
| `member-of` | left is an element of the set/enumeration right |
| `maps-to` | left is a function whose codomain is right |
| `composed-of` | right is built by composing left |
| `constrains` | left restricts the admissible values of right |
| `classifies` | left is a predicate/partition over right |
| `justifies` | informative rationale for a normative choice |
| `requires` | conformance obligation |
| `approximates` | left is a declared-inexact stand-in for right |

- **N** = normative clause, **I** = informative annex.
- Diagrams are split by layer; §1 is the master map tying the layers together.

---

## 1. Master map

```mermaid
flowchart TB
  subgraph L1["Layer 1 — Format space (N, cl.3)"]
    FP["Format-defining parameters<br/>K, P, Sigma, Delta"]
    FMT["Floating-point format f"]
    B["Exponent bias B"]
  end

  subgraph L2["Layer 2 — Value space (N, cl.3, 4.7.6)"]
    REALS["Closed extended reals<br/>R-omega"]
    DSET["Datum set D_f"]
    CP["Code points 0 .. 2^K - 1"]
  end

  subgraph L3["Layer 3 — Operation machinery (N, cl.4)"]
    OP["Operation / specialization"]
    OMEGA["Auxiliary omega-operation"]
    PIPE["decode - compute - project"]
  end

  subgraph L4["Layer 4 — Projection (N, 4.2, 4.7.3-4.7.5)"]
    RHO["Projection specification rho"]
    RND["Rounding mode"]
    SAT["Saturation mode"]
  end

  subgraph L5["Layer 5 — Operation catalog (N, 4.9-4.16)"]
    ARITH["Arithmetic"]
    EXTR["Extrema and Clamp"]
    CMP["Comparisons and predicates"]
    META["Format-level ops"]
  end

  subgraph L6["Layer 6 — Blocks (N, cl.5)"]
    BLK["Block: scale factor + elements"]
    BOPS["Block ops, reductions, scaled ops"]
  end

  subgraph L7["Layer 7 — Conformance (N, 4.4-4.6)"]
    CONF["Conforming implementation"]
    KAPPA["kappa-approximate implementation"]
  end

  subgraph L8["Layer 8 — Rationale and reference (I, Annexes)"]
    RAT["Annex A rationales"]
    ENC["Annex B, C value tables"]
    EX["Annex D, E accuracy examples"]
    EXT["Annex F external formats"]
    GRP["Annex G operation groups"]
    BIB["Annex H bibliography"]
  end

  FP -->|parameterizes| FMT
  FP -->|derives| B
  FMT -->|maps-to| DSET
  DSET -->|subset-of| REALS
  DSET -->|encoding bijection| CP
  B -->|parameterizes| CP

  FMT -->|parameterizes| OP
  RHO -->|parameterizes| OP
  OP -->|composed-of| PIPE
  PIPE -->|uses| OMEGA
  OMEGA -->|operates-on| REALS
  RHO -->|composed-of| RND
  RHO -->|composed-of| SAT
  PIPE -->|projects-to| DSET

  OP --> ARITH
  OP --> EXTR
  OP --> CMP
  OP --> META
  BLK -->|lifts| BOPS
  OP -->|elementwise-lift| BOPS

  CONF -->|requires| OP
  KAPPA -->|approximates| OP

  RAT -->|justifies| FP
  RAT -->|justifies| DSET
  ENC -->|illustrates| CP
  EX -->|illustrates| KAPPA
  EXT -->|compares| FMT
  GRP -->|partitions| OP
  BIB -->|supports| RAT
```

---

## 2. Layer 1 — Format space (N)

```mermaid
flowchart LR
  K["Bitwidth K<br/>integer, K &gt; 2"]
  P["Precision P"]
  SIG["Signedness Sigma<br/>Signed | Unsigned"]
  DOM["Domain Delta<br/>Finite | Extended"]
  F["Format f = Binary{K,P,Sigma,Delta}"]
  SHORT["Short name Binary&lt;k&gt;p&lt;p&gt;&lt;s&gt;&lt;d&gt;"]
  BIAS["Exponent bias B"]
  EBW["ExponentBitwidthOf"]
  TSBW["TrailingSignificandBitwidthOf"]
  EMAX["emax (Annex A.5, informative)"]
  EXTF["External formats<br/>binary64, binary32, binary16, BFloat16"]

  K -->|parameterizes| F
  P -->|parameterizes| F
  SIG -->|parameterizes| F
  DOM -->|parameterizes| F
  F -->|abbreviated-as| SHORT
  K -->|derives| BIAS
  P -->|derives| BIAS
  SIG -->|selects formula for| BIAS
  K -->|derives| EBW
  P -->|derives| EBW
  P -->|derives| TSBW
  K -->|derives| EMAX
  P -->|derives| EMAX
  SIG -->|constrains| P
  DOM -->|constrains| DSETNOTE["Datum set includes infinities iff Extended"]
  EXTF -->|treated-as| F
```

**Constraints and formulas** ([§3.1](IEEE_D1.md#L264), [§4.14](IEEE_D1.md#L1975), [Annex A.5](IEEE_D1.md#L2503)):

| Quantity | Signed | Unsigned |
| --- | --- | --- |
| Precision range | `0 < P < K` | `0 < P <= K` |
| Exponent bias `B` | `2^(K-P-1)` | `2^(K-P)` |
| `ExponentBitwidthOf(f)` | `K - P` | `K - P + 1` |
| `TrailingSignificandBitwidthOf(f)` | `P - 1` | `P - 1` |

`emax` (informative, [Annex A.5](IEEE_D1.md#L2503)):

```
emax = 2^(K-1) - 3    if P = 1, Unsigned, Extended
     = 2^(K-1) - 2    if P = 1, Unsigned, Finite
     = 2^(K-2) - 2    if P = 1, Signed,   Extended
     = 2^(K-2) - 2    if P = 2, Unsigned, Extended
     = 2^(K-P-1) - 1  otherwise if Signed
     = 2^(K-P) - 1    otherwise if Unsigned
```

---

## 3. Layer 2 — Value space, datums, encoding (N)

```mermaid
flowchart TB
  RW["Closed extended reals<br/>R-omega = R + {-inf, +inf, NaN}"]
  D["Datum set D_f"]
  V["Value set (code points) 0 .. 2^K - 1"]
  DATUM["Floating-point datum X"]
  VAL["Floating-point value x"]
  CANON["Canonical form<br/>sgn(X) * S * 2^(1-P) * 2^E"]
  SIGD["Significand S"]
  EXPO["Exponent E, E &gt; -B"]
  TS["Trailing significand<br/>T = S mod 2^(P-1)"]
  EBF["Exponent field (biased exponent)"]
  NORM["normal: 2^(P-1) &lt;= S &lt; 2^P"]
  SUB["subnormal: 0 &lt; S &lt; 2^(P-1)"]
  ZERO["zero (exactly one)"]
  INF["infinities (Extended only)"]
  NAN["NaN (exactly one)"]
  SPEC["special values"]
  ENC["omega-Encode"]
  DEC["omega-Decode"]

  D -->|subset-of| RW
  DATUM -->|member-of| D
  VAL -->|member-of| V
  D -->|bijection| V
  DATUM -->|expressed-as| CANON
  CANON -->|has-part| SIGD
  CANON -->|has-part| EXPO
  SIGD -->|derives| TS
  EXPO -->|plus bias B derives| EBF
  SIGD -->|classifies| NORM
  SIGD -->|classifies| SUB
  ZERO -->|member-of| SPEC
  INF -->|member-of| SPEC
  NAN -->|member-of| SPEC
  SPEC -->|member-of| D
  DEC -->|maps-to| DATUM
  ENC -->|maps-to| VAL
  VAL -->|omega-Decode| DATUM
  DATUM -->|omega-Encode| VAL
```

**Special code points** ([Annex B](IEEE_D1.md#L2536), Table 3):

| Datum | Signed extended | Signed finite | Unsigned extended | Unsigned finite |
| --- | --- | --- | --- | --- |
| Zero | `0` | `0` | `0` | `0` |
| One | `2^(K-2)` | `2^(K-2)` | `2^(K-1)` | `2^(K-1)` |
| NaN | `2^(K-1)` | `2^(K-1)` | `2^K - 1` | `2^K - 1` |
| `+Inf` | `2^(K-1) - 1` | — | `2^K - 2` | — |
| `-Inf` | `2^K - 1` | — | — | — |

Zero is unique (no `-0`); NaN is unique and occupies the IEEE-754 `-0`
code point in signed formats.

---

## 4. Layer 3 — Operation machinery (N, [§4](IEEE_D1.md#L330))

The single most load-bearing structure in the document: **every numeric
operation is decode, then exact computation over `R-omega`, then projection.**

```mermaid
flowchart LR
  X["Operand x<br/>value in format f_x"]
  XD["Datum X in R-omega"]
  RES["Exact result in R-omega"]
  RND["omega-RoundToPrecision"]
  SATF["omega-Saturate"]
  ENCF["omega-Encode"]
  R["Result r<br/>value in format f_r"]

  X -->|omega-Decode_fx| XD
  XD -->|omega-Op| RES
  RES -->|step 1| RND
  RND -->|step 2| SATF
  SATF -->|step 3| ENCF
  ENCF --> R

  subgraph PROJ["omega-Project_(f_r, rho)"]
    RND
    SATF
    ENCF
  end
```

Canonical law ([§4.3.2](IEEE_D1.md#L405), applied throughout §4.9–§4.11):

```
Op_{f_x, f_y, f_r, rho}(x, y)
    = omega-Project_{f_r, rho}( omega-Op( omega-Decode_{f_x}(x),
                                          omega-Decode_{f_y}(y) ) )
```

Exceptions to the law: comparisons and predicates return Booleans and stop
after `omega-Decode` ([§4.12](IEEE_D1.md#L1778), [§4.13](IEEE_D1.md#L1895));
`NextGreaterThan` / `NextLessThan` work directly on code points
([§4.16](IEEE_D1.md#L2027)); format-level operations take a format, not a value
([§4.14](IEEE_D1.md#L1975)).

```mermaid
flowchart TB
  OPER["Operation<br/>identifier + operation parameters"]
  SPEC["Operation specialization<br/>parameters bound to values"]
  AUX["Auxiliary operation (omega-prefixed)<br/>total over R-omega"]
  SCHEMA["Operation definition schema<br/>Signature, Parameters, Operands, Result, Behavior, Details"]
  PATT["Pattern-matching declarations<br/>first match wins"]
  EXACTP["Exact pattern"]
  SETP["Set inclusion pattern"]
  WILD["Wildcard *"]
  EXPLP["Explicit parameters in result"]
  INTERNAL["Internal functions (4.7)<br/>not required of implementations"]

  OPER -->|instantiated-by| SPEC
  OPER -->|defined-by| SCHEMA
  SCHEMA -->|behavior-given-as| PATT
  PATT --> EXACTP
  PATT --> SETP
  PATT --> WILD
  PATT --> EXPLP
  OPER -->|delegates-to| AUX
  AUX -->|member-of| INTERNAL
```

Internal functions ([§4.7](IEEE_D1.md#L613)): `omega-Decode` / `omega-DecodeAux`,
`omega-Project`, `omega-RoundToPrecision`, `omega-Saturate`, `omega-Encode`;
plus external-format bridges `omega-DecodeExternal` / `omega-EncodeExternal`
([§4.8](IEEE_D1.md#L865)).

---

## 5. Layer 4 — Projection: rounding and saturation (N)

```mermaid
flowchart TB
  RHO["Projection specification rho = (rounding mode, saturation mode)"]
  ROUNDOF["RoundOf(rho)"]
  SATOF["SatOf(rho)"]

  subgraph RM["Rounding modes (4.7.4)"]
    NTE["NearestTiesToEven"]
    NTA["NearestTiesToAway"]
    TP["TowardPositive"]
    TN["TowardNegative"]
    TZ["TowardZero"]
    TO["ToOdd"]
    SA["StochasticA[N,R]"]
    SB["StochasticB[N,R]"]
    SC["StochasticC[N,R]"]
  end

  subgraph SM["Saturation modes (4.7.5)"]
    SF["SatFinite"]
    SP["SatPropagate"]
    SN["SatNone"]
  end

  RA["RoundAway(mu) predicate"]
  CIE["CodeIsEven<br/>special case when P = 1"]
  RNITE["RNITE helper"]
  MLO["M_lo = MinFiniteOf(f)"]
  MHI["M_hi = MaxFiniteOf(f)"]

  RHO -->|queried-by| ROUNDOF
  RHO -->|queried-by| SATOF
  ROUNDOF -->|selects| RM
  SATOF -->|selects| SM
  RM -->|decided-by| RA
  RA -->|uses| CIE
  SC -->|uses| RNITE
  SM -->|clamps-against| MLO
  SM -->|clamps-against| MHI
  SM -->|depends-on| SIGDOM["Sigma and Delta of target format"]
```

Ordering fact that the whole clause turns on ([§4.7.3](IEEE_D1.md#L665) NOTE 1,
[§4.7.5](IEEE_D1.md#L770) NOTE): **rounding precedes saturation**, yet the
rounding mode is *also* passed to `omega-Saturate` so that a directed rounding
mode can force a finite result. Saturation itself never rounds.

Saturation semantics summary:

| Mode | Out-of-range finite | `+/-inf` input |
| --- | --- | --- |
| `SatFinite` | clamp to `M_lo` / `M_hi` | clamp to `M_lo` / `M_hi` |
| `SatPropagate` | clamp to `M_lo` / `M_hi` | preserved if representable, else clamped |
| `SatNone` | to `+/-inf` (Extended) or NaN, per rounding direction, signedness, domain | preserved if representable, else NaN |

Stochastic rounding takes `N` random bits as unsigned `R`, `0 <= R < 2^N`;
bit quality is explicitly unspecified ([§4.7.4](IEEE_D1.md#L704) Details).

---

## 6. Layer 5 — Operation catalog (N, [§4.9](IEEE_D1.md#L917)–[§4.16](IEEE_D1.md#L2027))

```mermaid
flowchart TB
  CAT["Operation catalog"]

  subgraph CONV["Conversion (4.9)"]
    CONVERT["Convert"]
  end

  subgraph A1["Sign and basic arithmetic (4.10.1-4.10.7)"]
    ABS["Abs, Negate"]
    CS["CopySign"]
    AS["Add, Subtract"]
    MUL["Multiply"]
    DIV["Divide"]
    FMA["FMA"]
    FAA["FAA"]
  end

  subgraph A2["Elementary functions (4.10.8-4.10.16)"]
    ROOTS["Sqrt, Recip, RSqrt"]
    LOGS["Exp, Exp2, Log, Log2, LogOnePlus, ExpMinusOne"]
    TRIG["Sin, Cos, Tan, ArcSin, ArcCos, ArcTan"]
    HYP["Sinh, Cosh, Tanh, ArcSinh, ArcCosh, ArcTanh"]
    PITRIG["SinPi, CosPi, TanPi, ArcSinPi, ArcCosPi, ArcTanPi"]
    ML["Softplus"]
    TWOARG["Hypot, ArcTan2, ArcTan2Pi"]
  end

  subgraph EX["Extrema (4.11)"]
    MINMAX["Minimum, Maximum"]
    NUMV["...Number variants"]
    MAGV["...Magnitude variants"]
    MAGNUM["...MagnitudeNumber variants"]
    FINV["...Finite variants"]
    CLAMP["Clamp"]
  end

  subgraph PRED["Comparisons and classification (4.12-4.13)"]
    CMPOPS["CompareLess, CompareLessEqual, CompareEqual,<br/>CompareGreater, CompareGreaterEqual"]
    TOTAL["TotalOrder"]
    SYMS["Comparison operator symbols (Table 1)"]
    ISX["IsZero, IsOne, IsNaN, IsInfinite, IsFinite,<br/>IsSignMinus, IsNormal, IsSubnormal"]
    CLASS["Class -> ClassEnum (Table 2)"]
  end

  subgraph FMTOPS["Format-level and rho ops (4.14-4.15)"]
    INTQ["BitwidthOf, PrecisionOf, SignednessOf, DomainOf,<br/>ExponentBitwidthOf, TrailingSignificandBitwidthOf, ExponentBiasOf"]
    VALQ["MaxFiniteOf, MinFiniteOf, MinPositiveOf,<br/>MaxSubnormalOf, MinNormalOf"]
    RHOQ["RoundOf, SatOf"]
  end

  subgraph NEIGH["Neighbours (4.16)"]
    NGT["NextGreaterThan"]
    NLT["NextLessThan"]
  end

  CAT --> CONV
  CAT --> A1
  CAT --> A2
  CAT --> EX
  CAT --> PRED
  CAT --> FMTOPS
  CAT --> NEIGH

  MINMAX -->|NaN-quieting variant| NUMV
  MINMAX -->|by magnitude| MAGV
  MAGV -->|NaN-quieting variant| MAGNUM
  MINMAX -->|infinity-quieting variant| FINV
  CMPOPS -->|extended-by| TOTAL
  CMPOPS -->|surface syntax| SYMS
  ISX -->|partition| CLASS
  VALQ -->|referenced-by| CLAMP
  VALQ -->|referenced-by| NEIGH
```

**Class enumeration** ([§4.13.1](IEEE_D1.md#L1944), Table 2), eight disjoint
classes: `ClsNaN`, `ClsNegativeInfinity`, `ClsNegativeNormal`,
`ClsNegativeSubnormal`, `ClsZero`, `ClsPositiveSubnormal`,
`ClsPositiveNormal`, `ClsPositiveInfinity`.

**Design decisions visible only in the pattern tables:**

| Case | Result | Where |
| --- | --- | --- |
| `Divide(x, 0)` | `NaN` (not `Inf`) | [§4.10.5](IEEE_D1.md#L1093) NOTE 2 |
| `Divide(x, +/-Inf)` | `0` | [§4.10.5](IEEE_D1.md#L1093) NOTE 1 |
| `Recip(+/-inf)` | `0`, and `Recip(0) = NaN` | [§4.10.8](IEEE_D1.md#L1232) |
| `ArcTan2(0, 0)` | `NaN` (limit indeterminate) | [§4.10.15](IEEE_D1.md#L1518) |
| `TotalOrder(NaN, x)` | `True` — NaN is most negative | [§4.12.1](IEEE_D1.md#L1851) |
| `NextGreaterThan(Inf)` | `NaN`, unlike IEEE-754 `nextUp` | [§4.16](IEEE_D1.md#L2027) NOTE 2 |
| `omega-FMA(X,Y,Z)` | equivalent to `omega-Add(omega-Multiply(X,Y), Z)` | [§4.10.6](IEEE_D1.md#L1131) |
| `omega-FAA` | associative: `Add(Add(X,Y),Z) = Add(X,Add(Y,Z))` | [§4.10.7](IEEE_D1.md#L1182) |

---

## 7. Layer 6 — Blocks and scaled operations (N, [§5](IEEE_D1.md#L2077))

```mermaid
flowchart TB
  BLOCK["Block (s, [x_1 .. x_B])"]
  SCALE["Scale factor s, format f_s"]
  ELEMS["Elements x_i, format f_x"]
  BSIZE["Block size B"]
  REDUCE["reduce(f, list) — left fold"]

  BDEC["omega-BlockDecode<br/>Z_i = Multiply(Decode(s), Decode(x_i))"]
  BPROJ["omega-BlockProject<br/>Z_i = Divide(X_i, S), with S=0, S=inf, NaN cases"]

  CFB["ConvertFromBlock"]
  CTB["ConvertToBlock (s supplied)"]
  CTBM["ConvertToBlockMaxAbsFinite (s computed)"]

  RADD["BlockReduceAdd"]
  RMUL["BlockReduceMultiply"]
  RDOT["BlockDotProduct"]

  BOP["BlockOp — elementwise lift of any Op"]
  SCALED["ScaledOp — BlockOp at B = 1"]

  SCALE -->|part-of| BLOCK
  ELEMS -->|part-of| BLOCK
  BSIZE -->|parameterizes| BLOCK
  BLOCK -->|decoded-by| BDEC
  BPROJ -->|produces| BLOCK
  BDEC -->|used-by| CFB
  BPROJ -->|used-by| CTB
  BPROJ -->|used-by| CTBM
  CTBM -->|scale from| MAXF["reduce(omega-MaximumFinite, NaN and abs X_i)"]
  CTBM -->|separate rho_s for scale| SCALE
  BDEC -->|used-by| RADD
  BDEC -->|used-by| RMUL
  BDEC -->|used-by| RDOT
  RADD -->|reduce with omega-Add, seed 0| REDUCE
  RMUL -->|reduce with omega-Multiply, seed 1| REDUCE
  RDOT -->|products then reduce omega-Add| REDUCE
  BOP -->|composed-of| BDEC
  BOP -->|composed-of| BPROJ
  BOP -->|specializes-to| SCALED
```

Key block facts:

- `omega-BlockDecode` **multiplies** by the scale; `omega-BlockProject`
  **divides** by it ([§5.1](IEEE_D1.md#L2089)).
- Scale-factor edge cases in `omega-BlockProject`: `S` NaN or `X_i` NaN gives
  NaN; `S = 0` gives `0`; `S = +/-inf` gives `sgn(X_i) * sgn(S)`.
- `ConvertToBlockMaxAbsFinite` carries **two** projection specifications:
  `rho_s` for the scale factor, `rho` for the elements
  ([§5.2.3](IEEE_D1.md#L2200)).
- `BlockOp` result scale factor `s_r` is an **input operand**, not computed
  ([§5.4](IEEE_D1.md#L2310)).
- Valid `Op` substitutions in `BlockOp`: 30 unary, 18 binary, 3 ternary
  (`FMA`, `FAA`, `Clamp`).
- Scaled operations are exactly `B = 1` block operations
  ([§5.5](IEEE_D1.md#L2357)); a scale format with `P = 1` restricts scales to
  powers of two.

---

## 8. Layer 7 — Conformance and approximation (N, [§4.4](IEEE_D1.md#L468)–[§4.6](IEEE_D1.md#L588))

```mermaid
flowchart TB
  IMPL["Implementation"]
  EXACT["Exact implementation<br/>result equals defined result for all operands"]
  APPROX["kappa-approximate implementation"]
  DEFRES["Defined result a-hat(x)"]
  APPRES["Approximate result a-tilde(x)"]
  VSTEP["value step — count of values of V between the two results"]
  KNAN["kappa = NaN — does not match on NaNs"]
  KINF["kappa = inf — matches NaNs, not infinities"]
  MOI["MatchOnInfinity(x, y)"]
  KFIN["kappa finite — max over operands giving finite results"]
  SUBSETS["kappa declared over disjoint cover I_1 .. I_n"]
  MULTI["Multi-result rule<br/>NaN dominates, then inf, else max over m"]
  NAMING["Approximate op must be named differently"]

  F4["F_4 = {Binary4p2sf}"]
  F8["F_8 = {Binary8p4se, Binary8p3se}"]
  FX["F_X, nonempty subset of<br/>{binary32, binary16, BFloat16}"]
  FS["F_s = {Binary8p1uf} for scaled ops"]
  RHOREQ["rho = (NearestTiesToEven, SatNone)"]
  REQOPS["Required specializations"]
  DECL["Conformance declaration strings"]

  IMPL --> EXACT
  IMPL --> APPROX
  APPROX -->|approximates| DEFRES
  APPROX -->|produces| APPRES
  DEFRES -->|distance measured in| VSTEP
  APPRES -->|distance measured in| VSTEP
  VSTEP -->|yields| KFIN
  MOI -->|decides| KINF
  APPROX --> KNAN
  APPROX --> KINF
  APPROX --> KFIN
  KFIN -->|may be refined by| SUBSETS
  APPROX --> MULTI
  APPROX -->|requires| NAMING
  F4 -->|requires| REQOPS
  F8 -->|requires| REQOPS
  FX -->|requires| REQOPS
  FS -->|requires| REQOPS
  RHOREQ -->|fixes| REQOPS
  EXACT -->|requires| REQOPS
  IMPL -->|should publish| DECL
```

`kappa` ladder, in decision order ([§4.4](IEEE_D1.md#L468)):

1. NaN behavior differs anywhere → declare `kappa = NaN`.
2. Else infinity behavior differs anywhere (`MatchOnInfinity` false) → `kappa = inf`.
3. Else `kappa = max over x in I of #(((a-hat(x), a-tilde(x)] union [a-tilde(x), a-hat(x))) intersect V)`.

Required specializations ([§4.5](IEEE_D1.md#L521)): `Convert`, `Negate`, `Abs`,
`Recip`, `Add`, `Subtract`, `Multiply`, `FMA`, `FAA`, the ten min/max variants,
five comparisons, ten predicates and neighbour ops, twelve format-level ops,
and `ScaledAdd` / `ScaledSubtract` / `ScaledMultiply`.

---

## 9. Layer 8 — Interoperation with IEEE-754 and external formats

```mermaid
flowchart LR
  P3109["P3109 format Binary{K,P,Sigma,Delta}"]
  EXT["External formats<br/>binary64, binary32, binary16, BFloat16"]
  DECX["omega-DecodeExternal"]
  ENCX["omega-EncodeExternal"]
  RW["R-omega"]
  DIFF["Divergences from IEEE-754"]

  EXT -->|omega-DecodeExternal| RW
  RW -->|omega-EncodeExternal| EXT
  P3109 -->|omega-Decode| RW
  RW -->|omega-Encode| P3109
  DECX -->|collapses any NaN to single NaN| DIFF
  DECX -->|maps -0 to 0| DIFF
  ENCX -->|emits any quiet NaN, zero payload recommended| DIFF
```

Divergences from IEEE Std 754-2019, collected:

| Aspect | IEEE-754 | P3109/D1 |
| --- | --- | --- |
| NaN count | many, with payloads | exactly one |
| Negative zero | present | absent |
| Infinities | always present | only in `Extended` domain |
| Exponent bias | from `emax` and interchange params | from `K`, `P`, `Sigma` |
| `1/0` | signed infinity | `NaN` |
| `nextUp(+inf)` | `+inf` | `NextGreaterThan(Inf) = NaN` |
| Saturation | not a format attribute | first-class `rho` component |

Annex F ([§Annex F](IEEE_D1.md#L2781)) compares against OCP (OFP8), AGQ
(AMD / Graphcore / Qualcomm), and TSL (Tesla Dojo) on: shared special values,
single NaN, negative zero, infinity presence, and `emax`.

---

## 10. Layer 9 — Rationale map (I, [Annex A](IEEE_D1.md#L2371))

```mermaid
flowchart LR
  COST["Design principle:<br/>code points are scarce in narrow formats"]
  A2["A.2 single NaN"]
  A3["A.3 single zero, no -0"]
  A4["A.4 infinities and the domain parameter"]
  A5["A.5 exponent bias formula"]
  A6["A.6 subnormals"]

  DNAN["Datum set has exactly one NaN"]
  DZERO["Datum set has exactly one zero"]
  DDOM["Domain parameter Delta"]
  DBIAS["B = 2^(K-P-1) or 2^(K-P)"]
  DSUB["Subnormals included when P &gt; 1"]

  COST --> A2 --> DNAN
  COST --> A3 --> DZERO
  COST --> A4 --> DDOM
  A5 --> DBIAS
  A6 --> DSUB

  A2 -->|justified-by| USES["ML uses: accelerator debugging, sentinel values"]
  A3 -->|justified-by| SYMM["NaN at the -0 code point makes signed ranges symmetric"]
  A3 -->|justified-by| BRANCH["ArcTan2 branch cuts rarely needed in deep learning"]
  A4 -->|justified-by| MASK["Attention masks, logsumexp shift identity, loss scaling"]
  A5 -->|consequence| ONE["1.0 lands on the midway code point"]
  A6 -->|justified-by| GRAD["Near-zero gradients, small random init weights"]
  A6 -->|permits| FTZ["Flush-to-zero allowed via the 4.4 approximation provision"]
```

The `logsumexp` argument in [Annex A.4](IEEE_D1.md#L2427) is the strongest
rationale in the document: the shift identity
`logsumexp(v) = logsumexp(v - max(v)) + max(v)` needs the *stickiness* of `-inf`;
substituting `maxFinite` silently breaks it at small temperature `tau` or in
mixed precision.

---

## 11. Reference artifacts (I, Annexes B–H)

```mermaid
flowchart TB
  ANB["Annex B — encoding properties, K = 4 value tables 4-7"]
  ANC["Annex C — K = 2 value tables, degenerate formats"]
  AND["Annex D — kappa declaration examples"]
  ANE["Annex E — reduction error bound recommendations"]
  ANF["Annex F — external format comparison"]
  ANG["Annex G — operation groups"]
  ANH["Annex H — bibliography"]

  ANB -->|illustrates| ENCODING["4.7.6 Encoding"]
  ANC -->|edge cases of| ENCODING
  AND -->|illustrates| KAPPA["4.4 kappa-approximate"]
  ANE -->|recommends bounds for| REDUCE["5.3 block reductions"]
  ANF -->|positions| FORMATS["clause 3 formats"]
  ANG -->|partitions| OPS["clause 4 and 5 operations"]
  ANH -->|supports| ALL["all rationales"]
```

**Annex C degeneracies at `K = 2`** — worth knowing when writing generic code:

- `Binary2p1ue` and `Binary2p2ue` share a datum set (different subnormal split);
  likewise `Binary2p1uf` and `Binary2p2uf`.
- `1.0` is absent from `Binary2p1se`, `Binary2p1ue`, `Binary2p2ue`, so Table 3
  does not apply.
- `Binary2p1se` has no normal or subnormal values: `MinPositiveOf = Inf`.
- `Binary2p1se`, `Binary2p2ue` have no normals: `MinNormalOf(f) = NaN`.

**Annex G operation groups**: A (Core), B (Basic), C (Full), M (Meta),
KA (Block Core), KB (Block Basic), KC (Block Full), E (Block Reductions).

**Annex E error bounds** for `B = 8`, `Binary8p4se` in/out, `binary16`
accumulation, `NearestTiesToEven`:

| Operation | Bound |
| --- | --- |
| `BlockReduceAdd` | `abs(S - S~) <= abs(S)/16 + 3.637e-3 * sum(abs(X_i))` |
| `BlockReduceMultiply` | `abs(P - P~) <= abs(P) * 6.614e-2` |
| `BlockDotProduct` | `abs(D - D~) <= abs(D)/16 + 3.637e-3 * sum(abs(X_i * Y_i))` |

Constants derive from `11 = PrecisionOf(binary16)`, `7 = B - 1`, and
`16 = 2^PrecisionOf(Binary8p4se)`.

---

## 12. Concept inventory

Alphabetical, with kind, source, and status.

| Concept | Kind | Source | Status |
| --- | --- | --- | --- |
| approximate implementation | conformance | [§4.4](IEEE_D1.md#L468) | N |
| auxiliary operation (`omega-`) | function class | [§4.1](IEEE_D1.md#L332) | N |
| bitwidth `K` | parameter | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| block | data structure | [§2.1](IEEE_D1.md#L161), [§5](IEEE_D1.md#L2077) | N |
| block size `B` | parameter | [§5](IEEE_D1.md#L2077) | N |
| canonical form | representation | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| `Class` / `ClassEnum` | operation / enumeration | [§4.13.1](IEEE_D1.md#L1944) | N |
| closed extended reals `R-omega` | value domain | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| code point | encoding | [§2.1](IEEE_D1.md#L161) | N |
| comparison predicate | operation class | [§4.12](IEEE_D1.md#L1778) | N |
| conformance declaration | artifact | [§4.6](IEEE_D1.md#L588) | N |
| conforming implementation | conformance | [§4.5](IEEE_D1.md#L521) | N |
| datum | value | [§2.1](IEEE_D1.md#L161) | N |
| datum set `D_f` | value domain | [§2.1](IEEE_D1.md#L161) | N |
| defined operation / defined result | conformance | [§2.1](IEEE_D1.md#L161), [§4.4](IEEE_D1.md#L468) | N |
| domain `Delta` | parameter | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| encoding | mapping | [§2.1](IEEE_D1.md#L161), [§4.7.6](IEEE_D1.md#L818) | N |
| exponent `E` | component | [§2.1](IEEE_D1.md#L161) | N |
| exponent bias `B` | derived parameter | [§3.1](IEEE_D1.md#L264), [Annex A.5](IEEE_D1.md#L2503) | N + I |
| exponent field | encoding field | [§2.1](IEEE_D1.md#L161), [§4.7.2](IEEE_D1.md#L619) | N |
| external format | interop | [§4.8](IEEE_D1.md#L865), [Annex F](IEEE_D1.md#L2781) | N + I |
| `emax` | derived quantity | [Annex A.5](IEEE_D1.md#L2503) | I |
| finite (of datum / of value) | qualifier | [§3.1](IEEE_D1.md#L264) | N |
| format `f` | type | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| format-defining parameters | parameter set | [§3.1](IEEE_D1.md#L264) | N |
| format naming | notation | [§3.2](IEEE_D1.md#L315) | N |
| format-level operation | operation class | [§4.14](IEEE_D1.md#L1975) | N |
| infinity | special value | [§3.1](IEEE_D1.md#L264), [Annex A.4](IEEE_D1.md#L2427) | N + I |
| internal function | function class | [§4.7](IEEE_D1.md#L613) | N |
| `kappa` (value steps) | accuracy measure | [§4.4](IEEE_D1.md#L468), [Annex D](IEEE_D1.md#L2672) | N + I |
| `MatchOnInfinity` | predicate | [§4.4](IEEE_D1.md#L468) | N |
| NaN | special value | [§2.1](IEEE_D1.md#L161), [Annex A.2](IEEE_D1.md#L2380) | N + I |
| normal | value class | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| operand | term | [§2.1](IEEE_D1.md#L161) | N |
| operation | term | [§2.1](IEEE_D1.md#L161), [§4.1](IEEE_D1.md#L332) | N |
| operation definition schema | notation | [§4.3.1](IEEE_D1.md#L382) | N |
| operation group | taxonomy | [Annex G](IEEE_D1.md#L2805) | I |
| operation specialization | term | [§2.1](IEEE_D1.md#L161), [§4.1](IEEE_D1.md#L332) | N |
| pattern-matching declaration | notation | [§4.3.2](IEEE_D1.md#L405) | N |
| precision `P` | parameter | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| projection specification `rho` | parameter | [§2.1](IEEE_D1.md#L161), [§4.2](IEEE_D1.md#L360) | N |
| `reduce` | helper | [§5](IEEE_D1.md#L2077) | N |
| rounded value | intermediate | [§2.1](IEEE_D1.md#L161), [§4.7.4](IEEE_D1.md#L704) | N |
| rounding mode | attribute | [§4.2](IEEE_D1.md#L360), [§4.7.4](IEEE_D1.md#L704) | N |
| saturation mode | attribute | [§4.2](IEEE_D1.md#L360), [§4.7.5](IEEE_D1.md#L770) | N |
| scale factor | block component | [§2.1](IEEE_D1.md#L161), [§5](IEEE_D1.md#L2077) | N |
| scaled operation | operation class | [§5.5](IEEE_D1.md#L2357) | N |
| significand `S` | component | [§2.1](IEEE_D1.md#L161) | N |
| signedness `Sigma` | parameter | [§2.1](IEEE_D1.md#L161), [§3.1](IEEE_D1.md#L264) | N |
| special value | value class | [§2.1](IEEE_D1.md#L161), [Annex B](IEEE_D1.md#L2536) | N + I |
| stochastic rounding A / B / C | rounding mode | [§4.7.4](IEEE_D1.md#L704) | N |
| subnormal | value class | [§2.1](IEEE_D1.md#L161), [Annex A.6](IEEE_D1.md#L2523) | N + I |
| total order | predicate | [§4.12.1](IEEE_D1.md#L1851) | N |
| trailing significand field | encoding field | [§2.1](IEEE_D1.md#L161) | N |
| value set | set | [§2.1](IEEE_D1.md#L161) | N |
| word usage: shall / should / may / can | convention | [§1.2](IEEE_D1.md#L146) | N |
| zero | special value | [§3.1](IEEE_D1.md#L264), [Annex A.3](IEEE_D1.md#L2404) | N + I |

---

## 13. Relation index

Central relations, stated as triples.

| Subject | Relation | Object |
| --- | --- | --- |
| `K, P, Sigma, Delta` | parameterize | format `f` |
| `K, P, Sigma` | derive | exponent bias `B` |
| format `f` | determines | datum set `D_f` and its encoding |
| `D_f` | is a subset of | `R-omega` |
| encoding | is a bijection | `D_f` to `0 .. 2^K - 1` |
| `Delta = Extended` | admits | infinities into `D_f` |
| `Sigma = Signed` | admits | negative datums into `D_f` |
| `omega-Decode` | maps | value to datum |
| `omega-Project` | composes | round, saturate, encode |
| `rho` | supplies | rounding mode and saturation mode |
| rounding mode | selects | `RoundAway` branch |
| saturation mode plus `Sigma`, `Delta` | select | out-of-range result |
| numeric operation | equals | project of `omega-Op` of decodes |
| comparison / predicate | stops at | decode, returns Boolean |
| `Class` | partitions | value set into eight classes |
| `TotalOrder` | orders | entire value set, NaN least |
| block | pairs | scale factor with element sequence |
| `omega-BlockDecode` | multiplies elements by | scale factor |
| `omega-BlockProject` | divides values by | scale factor |
| `BlockOp` | lifts | any unary, binary, or ternary `Op` |
| `ScaledOp` | is | `BlockOp` at `B = 1` |
| `kappa` | measures | value-step distance to the defined result |
| conforming implementation | must provide | the §4.5 specialization list |
| Annex A | justifies | single NaN, single zero, domain, bias, subnormals |
| Annex G | partitions | operations into groups A, B, C, M, KA, KB, KC, E |

---

## 14. Invariants and laws

1. **Encoding bijection.** For every format `f`, `omega-Encode_f` and
   `omega-Decode_f` are mutual inverses between `D_f` and `0 .. 2^K - 1`.
2. **Pipeline law.** Every numeric operation equals
   `omega-Project(omega-Op(omega-Decode(...)))` — no intermediate rounding.
3. **Single specials.** Exactly one NaN, exactly one zero, per format;
   zero always encodes to code point `0`.
4. **Round then saturate.** `omega-RoundToPrecision` runs before
   `omega-Saturate`; saturation never rounds; the rounding mode is still
   visible to saturation.
5. **Nearest-ties-to-even overflow.** Values between `M_hi` and half a ulp
   above `M_hi` project to `M_hi`, matching IEEE-754.
6. **Canonicality.** Nonzero finite datums use the smallest `E > -B`;
   zero uses `S = 0, E = 0`.
7. **Bias consequence.** `1.0` encodes to `2^(K-2)` signed, `2^(K-1)` unsigned.
8. **FMA / FAA exactness.** Single rounding at the end;
   `omega-FAA` is associative over `R-omega`.
9. **No side effects.** No flags, no traps; out-of-domain inputs return NaN.
10. **Approximation escape hatch.** Flush-to-zero and similar shortcuts are
    legal only as declared `kappa`-approximate implementations under a
    different operation name.

---

## 15. Coverage matrix

Every section of [IEEE_D1.json](IEEE_D1.json), mapped to the layer that covers it.

| Section | Title | Covered in |
| --- | --- | --- |
| 1, 1.1, 1.2 | Overview, Scope, Word usage | §12 inventory (word usage), §9 (alignment with IEEE-754) |
| 2.1 | Definitions | §12 concept inventory (all 30+ terms) |
| 2.2 | Abbreviations | FAA, FMA, MLS, P3109, IEEE-754 — used throughout |
| 2.3 | Mathematical notations | `IsOdd`, `IsEven`, `#S`, `sgn`, `div`, `mod` — §5, §8 |
| 3.1 | Formats | §2 Layer 1, §3 Layer 2 |
| 3.2 | Naming | §2 Layer 1 |
| 4.1 | General | §4 Layer 3 |
| 4.2 | Projection specifications | §5 Layer 4 |
| 4.3, 4.3.1, 4.3.2 | Operation definitions, schema, patterns | §4 Layer 3 |
| 4.4 | Approximate implementations | §8 Layer 7 |
| 4.5 | Conforming implementations | §8 Layer 7 |
| 4.6 | Conformance declarations | §8 Layer 7 |
| 4.7.1–4.7.6 | Internal functions: decode, project, round, saturate, encode | §4 Layer 3, §5 Layer 4 |
| 4.8, 4.8.1, 4.8.2 | External decode / encode | §9 Layer 8 |
| 4.9, 4.9.1 | Conversion | §6 Layer 5 |
| 4.10.1–4.10.16 | Arithmetic and elementary functions | §6 Layer 5 |
| 4.11.1–4.11.4 | Extrema and clamping | §6 Layer 5 |
| 4.12, 4.12.1, 4.12.2 | Comparisons, total order, symbols | §6 Layer 5 |
| 4.13, 4.13.1 | Predicates, classifier | §6 Layer 5 |
| 4.14 | Format-level operations | §2 Layer 1, §6 Layer 5 |
| 4.15 | Projection specification operations | §5 Layer 4 |
| 4.16 | Next greater / less than | §6 Layer 5, §9 Layer 8 |
| 5, 5.1.1, 5.1.2 | Blocks, block decode, block project | §7 Layer 6 |
| 5.2.1–5.2.3 | Block conversions | §7 Layer 6 |
| 5.3.1, 5.3.2 | Block reductions, dot product | §7 Layer 6, §11 |
| 5.4 | Elementwise block operations | §7 Layer 6 |
| 5.5 | Scaled operations | §7 Layer 6 |
| Annex A.1–A.6 | Rationales | §10 Layer 9 |
| Annex B, B.1 | Encoding properties, K = 4 tables | §3 Layer 2, §11 |
| Annex C | K = 2 value tables | §11 |
| Annex D.1, D.2 | `kappa` examples | §8 Layer 7, §11 |
| Annex E.1–E.3 | Reduction accuracy recommendations | §11 |
| Annex F | External formats | §9 Layer 8 |
| Annex G | Operation groups | §11 |
| Annex H | Bibliography | §11 |
