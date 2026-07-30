# ===== test/gates_g9.jl — gate G9: trait folding
#
# The K ≤ 16 traits are selected by dispatch, and where the condition is a
# function of static parameters it goes behind a `Val` barrier
# (implementextensions §2 R-A). That design replaces ~2 520 generated constant
# methods with ~15 dispatched ones, and it rests on a claim: the `Val` folds, so
# every trait resolves to a literal with no `Union` and no allocation.
#
# "Usually folds" is exactly the reasoning the plan rejects elsewhere, so G9
# turns the claim into a measurement: for EVERY format in the grid and EVERY
# type- or tag-valued trait, the inferred return type must be concrete.
#
# If G9 ever fails for a trait, that trait — and only that trait — falls back to
# emitting one generated constant method per format. Generation stays in the
# toolbox; it stops being the default.

using Test, SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
const _S = SmallFloats

isdefined(@__MODULE__, :GATE_LOG) || include("gatelog.jl")

# The predicate is `Base.isdispatchelem`, NOT `isconcretetype`.
#
# A type-valued trait infers to `Type{Float64}` / `Type{UInt8}` / `Type{Code8{…}}`,
# and `isconcretetype(Type{Float64})` is **false** — `Type{X}` is a kind, not a
# concrete type, even though it has exactly one inhabitant. Using
# `isconcretetype` here fails every type-valued trait while passing every
# tag-valued one, which reads like a real defect and is not.
#
# `isdispatchelem` is the property actually wanted: true for a concrete type and
# for a `Type{X}` singleton, false for a `Union` and for `Any`. That is exactly
# "inference resolved this call to one exact answer".
_folded(T) = Base.isdispatchelem(T)

@testset "G9 — trait folding" begin
    # Type- and tag-valued traits: the ones where a failure to fold leaks a
    # `Union` into a value and costs the zero-allocation property.
    traits = (_S.reptype, _S.codeunit_type, _S.decodepolicy, _S.orderkeytype,
              _S.datumcarrier, _S.promotecarrier, _S.rung, _S.codemask)

    fmts = [_S._NAMED[n] for n in sort!(collect(keys(_S._NAMED)))]
    @test !isempty(fmts)

    nonconcrete = Tuple{Symbol,DataType,Any}[]
    for F in fmts, tr in traits
        rts = Base.return_types(tr, Tuple{Type{F}})
        if length(rts) != 1 || !_folded(rts[1])
            push!(nonconcrete, (nameof(tr), F, rts))
        end
    end
    # Reported as one assertion carrying the offenders, so a failure names the
    # (trait, format) pair instead of drowning in 960 identical successes.
    @test nonconcrete == Tuple{Symbol,DataType,Any}[]

    # Value-argument forms must fold identically — they are what user code and
    # the kernels actually call.
    for F in fmts
        rt = Base.return_types(_S.rung, Tuple{F})
        @test length(rt) == 1 && _folded(rt[1])
    end

    # Allocation, through a function barrier so the measurement is of the trait
    # and not of Julia's dispatch machinery (benchmark doctrine: a call on a
    # loop-variable type is a dynamic dispatch, and measuring THAT is the
    # classic error this package has a post-mortem about).
    _probe(::Type{T}) where {T} = (_S.codemask(T), _S.rung(T), _S.datumcarrier(T),
                                   _S.codeunit_type(T), _S.decodepolicy(T))
    for F in (Binary8p4se, Binary8p1uf, Binary5p2se, Binary3p1se)
        _probe(F)                      # warm
        @test @allocated(_probe(F)) == 0
    end

    # The carrier tags themselves: both `carriertype` forms must agree and be
    # concrete. Defining only the instance form is the classic first-day error
    # (the type form is what `apply_op`'s result split needs).
    for H in (_S.HeadF64, _S.HeadF128, _S.HeadExact)
        @test _S.carriertype(H()) === _S.carriertype(H)
        rt = Base.return_types(_S.carriertype, Tuple{Type{H}})
        @test length(rt) == 1 && _folded(rt[1])
    end

    # Zero-behaviour-change pin, now scoped to the K ≤ 8 subgrid — which is what
    # the Stage 1 version of this block said it would become once `Code16`
    # landed. That scoping IS the assertion: opening the grid to 504 formats
    # moved nothing about the 120 that already existed.
    narrow = filter(F -> bitwidth(F) <= _S.KSPLIT, fmts)
    wide   = filter(F -> bitwidth(F) > _S.KSPLIT, fmts)
    @test length(narrow) == 120 && length(wide) == 384

    for F in narrow
        @test _S.rung(F) === _S.HeadF64()
        @test _S.datumcarrier(F) === Float64
        @test _S.promotecarrier(F) === Float64
        @test _S.codeunit_type(F) === UInt8
        @test _S.decodepolicy(F) === _S.TableDecode()
        @test _S.orderkeytype(F) === UInt16
        @test _S.reptype(F) === F
    end

    # The wide half: the storage unit is a function of K alone, the carrier is a
    # function of the bias alone, and the two axes are independent. The last
    # assertion is the interesting one — a K = 16 format can sit on any rung, so
    # a trait that conflated width with carrier would fail here and nowhere else.
    for F in wide
        @test _S.codeunit_type(F) === UInt16
        @test _S.decodepolicy(F) === _S.ComputeDecode()
        @test _S.orderkeytype(F) === UInt32
        @test _S.reptype(F) === F
        @test _S.rung(F) === (expbias(F) <= 512 ? _S.HeadF64() :
                              expbias(F) <= 8192 ? _S.HeadF128() : _S.HeadExact())
    end
    @test _S.rung(Binary16p14se) === _S.HeadF64()     # widest K, narrowest bias
    @test _S.rung(Binary16p1uf) === _S.HeadExact()    # widest K, widest bias
    @test _S.rung(Binary8p1uf) === _S.HeadF64()       # narrow K, widest narrow bias

    # Representation invariant 3, stated as the mask it now derives from, over
    # the whole grid rather than the byte-wide half of it.
    for F in fmts
        K = bitwidth(F)
        U = _S.codeunit_type(F)
        @test _S.codemask(F) === U((UInt64(1) << K) - 1)
        @test _S._unitmask(UInt16, K) == UInt16((UInt64(1) << K) - 1)
    end
    @test _S._unitmask(UInt16, 16) == 0xffff      # the case `1 << K` gets wrong
    @test _S._unitmask(UInt8, 8) == 0xff          # ditto at the byte width
    record_gate!("G9"; assertions=4290, units=4290, exhaustive=true)
end
