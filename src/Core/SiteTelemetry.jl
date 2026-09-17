"""
    SiteTelemetry

Site-level telemetry required by v0.1.0.

Contains at minimum:
- stress_ema::Float32          # σ: stress EMA for constitutive response
- residual_motion_ema::Float32 # residual-motion EMA for DCP commit decision
- consecutive_above_yield::Int32  # counter for melt eligibility (K_yield)
- consecutive_stable::Int32       # counter for commit eligibility (K_settle)

This state belongs in X_op and is NOT hidden in the DCP.

Note: delta (δ) is stored ONLY in HotPool, not here.
      prior_q is preserved in SiteState.q during superplastic (melt preserves q).
"""
mutable struct SiteTelemetry
    stress_ema::Float32
    residual_motion_ema::Float32
    consecutive_above_yield::Int32
    consecutive_stable::Int32
    
    function SiteTelemetry(stress_ema::Real=0.0,
                          residual_motion_ema::Real=0.0,
                          consecutive_above_yield::Integer=0,
                          consecutive_stable::Integer=0)
        new(Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable))
    end
    
    # Default constructor - Stage-0 seed state
    SiteTelemetry() = new(0.0f0, 0.0f0, Int32(0), Int32(0))
end

export SiteTelemetry
