"""Newtonian calibration law: Δδ = -g / η, with dt=1."""
struct Newtonian <: ConstitutiveLaw end
const NEWTONIAN = Newtonian()

function response(::Newtonian, region::RegionState,
                  ::SiteTelemetry, g::Real)::Float32
    return -Float32(g) / region.eta
end
