"""
    SiteTelemetry

Declared site-level operative telemetry used by the Stage-0 constitutive law
and DCP. The latent residual δ is deliberately *not* stored here; HotPool is
its sole source of truth.
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
        stress_ema >= 0 || error("HardFailure: stress EMA cannot be negative")
        residual_motion_ema >= 0 || error("HardFailure: residual-motion EMA cannot be negative")
        consecutive_above_yield >= 0 || error("HardFailure: negative above-yield counter")
        consecutive_stable >= 0 || error("HardFailure: negative stable counter")
        new(Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable))
    end
end

function _check_ema_factor(name::AbstractString, x::Real)::Float32
    xf = Float32(x)
    0.0f0 <= xf <= 1.0f0 || error("HardFailure: $name must be in [0,1], got $x")
    return xf
end

"""Update σ_t = β σ_{t-1} + (1-β)|g_t|."""
function update_stress_ema!(telemetry::SiteTelemetry, g::Real, beta::Real)::Float32
    b = _check_ema_factor("beta", beta)
    telemetry.stress_ema = b * telemetry.stress_ema + (1.0f0 - b) * abs(Float32(g))
    return telemetry.stress_ema
end

"""Update r_t = γ r_{t-1} + (1-γ)|Δδ_t|."""
function update_residual_motion_ema!(telemetry::SiteTelemetry,
                                     delta_delta::Real, gamma::Real)::Float32
    g = _check_ema_factor("gamma", gamma)
    telemetry.residual_motion_ema =
        g * telemetry.residual_motion_ema + (1.0f0 - g) * abs(Float32(delta_delta))
    return telemetry.residual_motion_ema
end

"""
Update the two declared sustained-eligibility counters from current telemetry
and region thresholds.
"""
function update_counters!(telemetry::SiteTelemetry, yield_up::Real,
                          settle_down::Real, epsilon_delta::Real)
    if telemetry.stress_ema > Float32(yield_up)
        telemetry.consecutive_above_yield += Int32(1)
    else
        telemetry.consecutive_above_yield = Int32(0)
    end

    if telemetry.stress_ema < Float32(settle_down) &&
       telemetry.residual_motion_ema < Float32(epsilon_delta)
        telemetry.consecutive_stable += Int32(1)
    else
        telemetry.consecutive_stable = Int32(0)
    end
    return nothing
end

function reset_lifecycle_counters!(telemetry::SiteTelemetry)
    telemetry.consecutive_above_yield = Int32(0)
    telemetry.consecutive_stable = Int32(0)
    return nothing
end
