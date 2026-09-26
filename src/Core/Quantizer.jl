"""
    ternary_round(s) -> Int8

Stage-0 reconsolidation quantizer. Exact ±0.5 boundaries map to zero.
"""
function ternary_round(s::Real)::Int8
    sf = Float32(s)
    sf < -0.5f0 && return Int8(-1)
    sf >  0.5f0 && return Int8(1)
    return Int8(0)
end
