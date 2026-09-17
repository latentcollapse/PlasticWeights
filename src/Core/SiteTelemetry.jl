"""
    SiteTelemetry

Site-level telemetry required by v0.1.0.

Contains at minimum:
- stress_ema::Float32          # σ: stress EMA for constitutive response
- residual_motion_ema::Float32 # residual-motion EMA for DCP commit decision
- consecutive_above_yield::Int32  # counter for melt eligibility (K_yield)
- consecutive_stable::Int32       # counter for commit eligibility (K_settle)
- prior_q::Int8                # prior committed q (for VPS exposure during superplastic)
- delta::Float32               # δ: current residual/displacement

This state belongs in X_op and is NOT hidden in the DCP.
"""
mutable struct SiteTelemetry
    stress_ema::Float32
    residual_motion_ema::Float32
    consecutive_above_yield::Int32
    consecutive_stable::Int32
    prior_q::Int8
    delta::Float32
    
    function SiteTelemetry(stress_ema::Real=0.0,
                          residual_motion_ema::Real=0.0,
                          consecutive_above_yield::Integer=0,
                          consecutive_stable::Integer=0,
                          prior_q::Integer=0,
                          delta::Real=0.0)
        new(Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable),
            Int8(prior_q), Float32(delta))
    end
end

# Default constructor - Stage-0 seed state
SiteTelemetry() = SiteTelemetry(0.0, 0.0, 0, 0, 0, 0.0)

# Export
export SiteTelemetry
