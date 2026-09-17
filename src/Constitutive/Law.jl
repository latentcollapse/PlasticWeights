"""
    ConstitutiveLaw

Abstract base type for constitutive laws.

All constitutive laws must implement:
    response(law, region_state, site_telemetry, g) -> Δδ

The constitutive function:
- cannot commit
- cannot melt
- cannot allocate
- cannot release
- cannot mutate exposure directly
"""
abstract type ConstitutiveLaw end

# Export the abstract type and response function
export ConstitutiveLaw, response

"""
    response(law::ConstitutiveLaw, region_state, site_telemetry, g)

Generic response function - dispatches to concrete implementations.
"""
function response end
