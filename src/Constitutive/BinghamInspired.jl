"""
    BinghamInspired(epsilon=1f-6)

Stage-0 computational mobility law:

    m = max(0, 1 - yield_up / (sigma + epsilon))
    Δδ = -(g / eta) * m
"""
struct BinghamInspired <: ConstitutiveLaw
    epsilon::Float32
    function BinghamInspired(epsilon::Real=1.0f-6)
        epsf = Float32(epsilon)
        epsf > 0.0f0 || error("HardFailure: Bingham epsilon must be > 0")
        new(epsf)
    end
end

const BINGHAM_INSPIRED = BinghamInspired()

function response(law::BinghamInspired, region::RegionState,
                  telemetry::SiteTelemetry, g::Real)::Float32
    denom = telemetry.stress_ema + law.epsilon
    mobility = max(0.0f0, 1.0f0 - region.yield_up / denom)
    mobility == 0.0f0 && return 0.0f0
    return -(Float32(g) / region.eta) * mobility
end
