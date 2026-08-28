# Same window, harder inputs: FMA forms an exact 16-bit product and adds an
# 8-bit datum, with an exponent spread up to 506 binades.
using SmallFloats
const G = 40

function ref_round(x::Rational{BigInt}, P::Int)
    x == 0 && return (1, big(0), 0)
    s = x < 0 ? -1 : 1; a = abs(x); e = 0
    while a >= 2^P;       a //= 2; e += 1; end
    while a <  2^(P - 1); a *= 2;  e -= 1; end
    n = numerator(a); d = denominator(a)
    q, r = divrem(n, d)
    (2r > d || (2r == d && isodd(q))) && (q += 1)
    q >= 2^P && (q >>= 1; e += 1)
    (s, q, e)
end

function win_add(s1::Int, m1::UInt64, e1::Int, s2::Int, m2::UInt64, e2::Int)
    m1 == 0 && return (s2, m2 << G, e2 - G, 0)
    m2 == 0 && return (s1, m1 << G, e1 - G, 0)
    if e1 < e2 || (e1 == e2 && m1 < m2)
        s1, m1, e1, s2, m2, e2 = s2, m2, e2, s1, m1, e1
    end
    sh = e1 - e2
    w1 = m1 << G
    local w2::UInt64; dropped = false
    k = G - sh
    if k >= 0
        w2 = m2 << k
    elseif -k >= 64
        w2 = UInt64(0); dropped = true
    else
        w2 = m2 >> (-k)
        dropped = (m2 & ((UInt64(1) << (-k)) - 1)) != 0
    end
    if s1 == s2
        return (s1, w1 + w2, e1 - G, dropped ? 1 : 0)
    end
    if w1 > w2
        w = w1 - w2; dropped && (w -= 1)
        return (s1, w, e1 - G, dropped ? 1 : 0)
    elseif w1 < w2
        return (s2, w2 - w1, e1 - G, 0)
    else
        @assert !dropped "equal windows with a dropped tail — lemma premise violated"
        return (1, UInt64(0), e1 - G, 0)
    end
end

function win_round(s::Int, w::UInt64, e::Int, rs::Int, P::Int)
    w == 0 && return (1, big(0), 0)
    nb = 64 - leading_zeros(w); sh = nb - P
    sh <= 0 && return (s, big(w) << (-sh), e + sh)
    q = w >> sh; rem = w & ((UInt64(1) << sh) - 1); half = UInt64(1) << (sh - 1)
    (rem > half || (rem == half && (rs > 0 || isodd(q)))) && (q += 1)
    q >= UInt64(1) << P && (q >>= 1; e += 1)
    (s, big(q), e + sh)
end

function datums(F, K, P)
    out = Tuple{Int,UInt64,Int,Rational{BigInt}}[]
    for c in 0:((1 << K) - 1)
        d = decode(F(UInt8(c)))
        (isfinite(d) && !isnan(d)) || continue
        if d == 0; push!(out, (1, UInt64(0), 0, big(0)//1)); continue; end
        a = abs(Float64(d)); sg = Float64(d) < 0 ? -1 : 1
        ex = exponent(a); sig = Int(significand(a) * 2.0^(P - 1))
        push!(out, (sg, UInt64(sig), ex - P + 1, sg * big(sig) * (big(2)//1)^(ex - P + 1)))
    end
    out
end

function check_fma(K, P, S, E)
    dat = datums(SmallFloats.format(K, P, S, E), K, P)
    bad = 0; n = 0
    for (sx, mx, ex, rx) in dat, (sy, my, ey, ry) in dat
        ps, pm, pe, pr = sx * sy, mx * my, ex + ey, rx * ry   # exact product
        for (sz, mz, ez, rz) in dat
            n += 1
            want = ref_round(pr + rz, P)
            s, w, e, rs = win_add(ps, pm, pe, sz, mz, ez)
            got = win_round(s, w, e, rs, P)
            ok = (want[2] == 0 && got[2] == 0) || want == got
            if !ok
                bad += 1
                bad <= 3 && println("  MISMATCH K=$K P=$P S=$S: $(Float64(rx))*$(Float64(ry))+$(Float64(rz)) want $want got $got")
            end
        end
    end
    (n, bad)
end

function main()
    tot = 0; badtot = 0
    # every format at K <= 6 exhaustively, plus the widest-spread K=7,8 formats
    for K in 3:6, P in 1:K, S in (false, true), E in (false, true)
        (S && P >= K) && continue
        n, b = check_fma(K, P, S, E); tot += n; badtot += b
    end
    for (K, P, S, E) in ((7,1,false,false), (7,1,false,true), (7,1,true,true),
                         (8,1,false,false), (8,1,false,true), (8,1,true,true),
                         (8,2,false,true), (8,4,true,true), (8,7,true,true))
        n, b = check_fma(K, P, S, E); tot += n; badtot += b
        println("  K=$K P=$P S=$S E=$E: $n triples, $b bad")
    end
    println("checked $tot FMA triples; mismatches = $badtot")
end
main()
