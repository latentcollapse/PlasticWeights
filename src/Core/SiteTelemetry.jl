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

"""
    update_stress_ema!(telemetry::SiteTelemetry, g::Real, beta::Real)

Updates stress EMA: σ_t = β*σ_{t-1} + (1-β)*|g_t|
"""
function update_stress_ema!(telemetry::SiteTelemetry, g::Real, beta::Real)
    beta_f = Float32(beta)
    telemetry.stress_ema = beta_f * telemetry.stress_ema + (1.0f0 - beta_f) * abs(Float32(g))
end

"""
    update_residual_motion_ema!(telemetry::SiteTelemetry, delta_delta::Real, gamma::Real)

Updates residual-motion EMA: r_t = γ*r_{t-1} + (1-γ)*|Δδ_t|
"""
function update_residual_motion_ema!(telemetry::SiteTelemetry, delta_delta::Real, gamma::Real)
    gamma_f = Float32(gamma)
    telemetry.residual_motion_ema = gamma_f * telemetry.residual_motion_ema + 
                                     (1.0f0 - gamma_f) * abs(Float32(delta_delta))
end

"""
    update_counters!(telemetry::SiteTelemetry, yield_up::Real, settle_down::Real, 
                     epsilon_delta::Real)

Updates sustained counters deterministically:
- consecutive_above_yield increments iff sigma > yield_up, else resets to 0
- consecutive_stable increments iff sigma < settle_down AND residual_motion_ema < epsilon_delta, else resets to 0
"""
function update_counters!(telemetry::SiteTelemetry, yield_up::Real, settle_down::Real, 
                          epsilon_delta::Real)
    sigma = telemetry.stress_ema
    r_ema = telemetry.residual_motion_ema
    
    # Above-yield counter
    if sigma > Float32(yield_up)
        telemetry.consecutive_above_yield += Int32(1)
    else
        telemetry.consecutive_above_yield = Int32(0)
    end
    
    # Stable counter
    if sigma < Float32(settle_down) && r_ema < Float32(epsilon_delta)
        telemetry.consecutive_stable += Int32(1)
    else
        telemetry.consecutive_stable = Int32(0)
    end
end

export SiteTelemetry, update_stress_ema!, update_residual_motion_ema!, update_counters!
