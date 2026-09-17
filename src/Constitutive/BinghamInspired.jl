"""
    BinghamInspired

Bingham-inspired constitutive law following the Stage-0 contract.

Models plastic flow with a yield threshold:
- Below yield: elastic/no flow
- Above yield: viscous flow

Constitutive API contract:
    response(law, region_state, site_telemetry, g) -> Δδ

The constitutive function:
- cannot commit
- cannot melt
- cannot allocate
- cannot release
- cannot mutate exposure directly
"""
struct BinghamInspired <: ConstitutiveLaw
    yield_stress::Float32    # threshold for plastic flow
    viscosity::Float32       # post-yield viscosity
    
    BinghamInspired(yield_stress::Real=0.1, viscosity::Real=1.0) = 
        new(Float32(yield_stress), Float32(viscosity))
end

"""
    response(law::BinghamInspired, region_state, site_telemetry, g) -> Float32

Computes the Bingham-inspired constitutive response.

Returns Δδ (change in residual) based on:
- region state
- site telemetry  
- gradient g

Behavior:
- If |g| < yield_stress: no flow (return 0)
- If |g| >= yield_stress: viscous flow with offset

This is a pure function with no side effects.
"""
function response(law::BinghamInspired, region_state, site_telemetry, g::Real)::Float32
    g_float = Float32(g)
    abs_g = abs(g_float)
    
    if abs_g < law.yield_stress
        # Below yield: no plastic flow
        return 0.0f0
    else
        # Above yield: Bingham plastic flow
        # Sign(g) * (|g| - yield) / viscosity
        sign_g = ifelse(g_float >= 0, 1.0f0, -1.0f0)
        return sign_g * (abs_g - law.yield_stress) / law.viscosity
    end
end

# Default Bingham-inspired law
const DEFAULT_BINGHAM = BinghamInspired(0.1f0, 1.0f0)
