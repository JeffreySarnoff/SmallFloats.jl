# ===== test/golden/capture.jl — write the G5 golden file
#
#     julia --project=. test/golden/capture.jl
#
# Run this ONCE, against the pre-refactor tree, before the first edit of the
# K ≤ 16 extension. Re-running it after a change *overwrites the oracle* and
# converts G5 from a non-regression gate into a tautology — so it prints a loud
# warning and requires SMALLFLOATS_GOLDEN_OVERWRITE=1 if the file exists.

using SmallFloats
using SmallFloats.Formats          # the 384 names above K = 8 are opt-in (Stage 9 item 1)
include(joinpath(@__DIR__, "harness.jl"))

function main()
    if isfile(GOLDEN_FILE) && get(ENV, "SMALLFLOATS_GOLDEN_OVERWRITE", "") != "1"
        println("""
        REFUSING to overwrite an existing golden.

            $GOLDEN_FILE

        G5 is an oracle captured from the pre-refactor tree. Re-deriving it from
        changed code proves only that the code agrees with itself. If you are
        certain (e.g. a deliberate, reviewed semantic change), set
        SMALLFLOATS_GOLDEN_OVERWRITE=1 and record why in the commit message.
        """)
        return 1
    end
    println("capturing G5 golden over $(length(golden_formats())) formats ",
            "($(length(representative_formats())) representative) …")
    ds = golden_digests(:all; verbose = true)     # every tier's sections
    open(GOLDEN_FILE, "w") do io
        println(io, "# SmallFloats.jl — G5 K ≤ 8 golden non-regression digests")
        println(io, "# captured ", Base.VERSION, " on ", Sys.MACHINE)
        println(io, "# git: ", strip(read(`git -C $(dirname(@__DIR__)) rev-parse HEAD`, String)))
        println(io, "# Each line: <sha256> <section>.  See harness.jl for what each covers.")
        for (name, d) in ds
            println(io, d, "  ", name)
        end
    end
    println("\nwrote ", GOLDEN_FILE)
    return 0
end

exit(main())
