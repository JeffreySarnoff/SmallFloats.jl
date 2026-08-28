# Lemma under test: for any two K<=8 datums, ONE UInt64 alignment window plus a
# one-trit sticky determines the same round-to-P-significant-bits result as the
# exact rational sum.  Sticky convention: rs in {0,+1}; +1 means "the true
# magnitude exceeds the window magnitude by a positive amount below one window
# unit".  win_add normalizes a negative tail away by decrementing the window.
using SmallFloats

const G = 40   # LSB position of the dominant significand inside the window

function ref_round(x::Rational{BigInt}, P::Int)
    x == 0 && return (1, big(0), 0)
    s = x < 0 ? -1 : 1
    a = abs(x); e = 0
    while a >= 2^P;      a //= 2; e += 1; end
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
    dropped = false
    local w2::UInt64
    if sh > G + 8
        w2 = UInt64(0); dropped = true
    else
        k = G - sh
        if k >= 0
            w2 = m2 << k
        else
            w2 = m2 >> (-k)
            dropped = (m2 & ((UInt64(1) << (-k)) - 1)) != 0
        end
    end
    if s1 == s2
        w = w1 + w2
        return (s1, w, e1 - G, dropped ? 1 : 0)          # tail adds to magnitude
    end
    # opposite signs; w1 > w2 strictly whenever a tail was dropped (proved: a
    # tail needs sh > G, which forces w1 >= 2^G > 255 >= w2)
    if w1 > w2
        w = w1 - w2
        dropped && (w -= 1)                              # true = w - eps  ==  (w-1) + (1-eps)
        return (s1, w, e1 - G, dropped ? 1 : 0)
    elseif w1 < w2
        return (s2, w2 - w1, e1 - G, 0)
    else
        return (1, UInt64(0), e1 - G, 0)
    end
end

function win_round(s::Int, w::UInt64, e::Int, rs::Int, P::Int)
    w == 0 && return (1, big(0), 0)
    nb = 64 - leading_zeros(w)
    sh = nb - P
    sh <= 0 && return (s, big(w) << (-sh), e + sh)
    q    = w >> sh
    rem  = w & ((UInt64(1) << sh) - 1)
    half = UInt64(1) << (sh - 1)
    up = rem > half || (rem == half && (rs > 0 || isodd(q)))
    up && (q += 1)
    q >= UInt64(1) << P && (q >>= 1; e += 1)
    (s, big(q), e + sh)
end

function datums(F, K, P)
    out = Tuple{Int,UInt64,Int,Rational{BigInt}}[]
    for c in 0:((1 << K) - 1)
        d = decode(F(UInt8(c)))
        (isfinite(d) && !isnan(d)) || continue
        if d == 0
            push!(out, (1, UInt64(0), 0, big(0)//1)); continue
        end
        a  = abs(Float64(d)); sg = Float64(d) < 0 ? -1 : 1
        ex = exponent(a); sig = Int(significand(a) * 2.0^(P - 1))
        r  = sg * big(sig) * (big(2)//1)^(ex - P + 1)
        @assert Float64(r) == Float64(d)
        push!(out, (sg, UInt64(sig), ex - P + 1, r))
    end
    out
end

function check(K, P, S, E)
    F = SmallFloats.format(K, P, S, E)
    dat = datums(F, K, P)
    bad = 0; n = 0
    for (s1, m1, e1, r1) in dat, (s2, m2, e2, r2) in dat
        n += 1
        want = ref_round(r1 + r2, P)
        s, w, e, rs = win_add(s1, m1, e1, s2, m2, e2)
        got  = win_round(s, w, e, rs, P)
        ok = (want[2] == 0 && got[2] == 0) || want == got
        if !ok
            bad += 1
            bad <= 3 && println("  MISMATCH K=$K P=$P S=$S: $(Float64(r1)) + $(Float64(r2)) -> want $want got $got")
        end
    end
    (n, bad)
end

function main()
    tot = 0; badtot = 0
    for K in 3:8, P in 1:K, S in (false, true), E in (false, true)
        (S && P >= K) && continue
        n, bad = check(K, P, S, E)
        tot += n; badtot += bad
    end
    println("checked $tot datum pairs across 120 formats; mismatches = $badtot")
end
main()
