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
"""
struct Newtonian <: ConstitutiveLaw
    viscosity::Float32
    
    Newtonian(viscosity::Real=1.0) = new(Float32(viscosity))
end

"""
    response(law::Newtonian, region_state, site_telemetry, g) -> Float32

Computes the Newtonian constitutive response.

Returns Δδ (change in residual) based on:
- region state
- site telemetry
- gradient g

This is a pure function with no side effects.
"""
function response(law::Newtonian, region_state, site_telemetry, g::Real)::Float32
    # Newtonian response: linear viscous response
    # Δδ = -viscosity * g
    return -law.viscosity * Float32(g)
end

# Default Newtonian law
const DEFAULT_NEWTONIAN = Newtonian(1.0)
