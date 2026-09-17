"""
    Newtonian

Newtonian constitutive law following the Stage-0 contract.

Constitutive API contract:
    response(law, region_state, site_telemetry, g) -> Δδ

The constitutive function:
- cannot commit
- cannot melt
- cannot allocate
- cannot release
- cannot mutate exposure directly

Newtonian equation:
    Δδ = -g / η

where:
- g is the gradient
- η (eta) is the viscosity from region state
"""
struct Newtonian <: ConstitutiveLaw end

const NEWTONIAN = Newtonian()

"""
    response(law::Newtonian, region_state, site_telemetry, g) -> Float32

Computes the Newtonian constitutive response.

Δδ = -g / η

This is a pure function with no side effects.
"""
function response(law::Newtonian, region_state, site_telemetry, g::Real)::Float32
    # Newtonian response: Δδ = -g / η
    eta = region_state.eta
    return -Float32(g) / eta
end
