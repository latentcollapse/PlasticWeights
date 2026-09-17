"""
    ExposurePolicy

Exposure API following the Stage-0 contract.

Conceptual contract:
    exposure(site, ::ZCS) -> Int8
    exposure(site, ::VPS) -> Int8

This is the only variant-specific forward semantic.
"""
abstract type ExposurePolicy end

"""
    ZCS <: ExposurePolicy

Zero-Change-Sensitive exposure policy.

Returns the site's current q value as exposure.
"""
struct ZCS <: ExposurePolicy end

"""
    VPS <: ExposurePolicy

Variable-Plasticity-Sensitive exposure policy.

Returns modified exposure based on superplastic state.
"""
struct VPS <: ExposurePolicy end

"""
    exposure(site::SiteState, policy::ZCS) -> Int8

ZCS exposure: returns the site's q value directly.
"""
function exposure(site::SiteState, policy::ZCS)::Int8
    return site.q
end

"""
    exposure(site::SiteState, policy::VPS) -> Int8

VPS exposure: returns modified exposure based on superplastic state.
For superplastic sites, may amplify or modify the signal.
"""
function exposure(site::SiteState, policy::VPS)::Int8
    if site.superplastic
        # Superplastic sites have amplified exposure
        return site.q * Int8(2)  # Example amplification
    else
        return site.q
    end
end

# Export helper for getting exposure with a policy
get_exposure(site::SiteState, policy::ExposurePolicy)::Int8 = exposure(site, policy)
