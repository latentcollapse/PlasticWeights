"""
    ExposurePolicy

Exposure API following the Stage-0 contract.

Conceptual contract:
    exposure(site, ::ZCS) -> Int8
    exposure(site, ::VPS) -> Int8

This is the only variant-specific forward semantic.

ZCS (Zero-Centered Superplasticity): 
- Vacant sites expose 0
- Consolidated sites expose q
- Superplastic sites expose 0

VPS (Value-Preserving Superplasticity):
- Vacant sites expose 0
- Consolidated sites expose q  
- Superplastic sites expose prior committed q (stored in residual or tracked separately)
"""
abstract type ExposurePolicy end

"""
    ZCS <: ExposurePolicy

Zero-Centered Superplasticity exposure policy.

Returns:
- 0 for vacant sites (!allocated)
- q for consolidated sites (allocated && !superplastic)
- 0 for superplastic sites (allocated && superplastic)
"""
struct ZCS <: ExposurePolicy end

"""
    VPS <: ExposurePolicy

Value-Preserving Superplasticity exposure policy.

Returns:
- 0 for vacant sites (!allocated)
- q for consolidated sites (allocated && !superplastic)
- prior_q for superplastic sites (the q value before melting)
"""
struct VPS <: ExposurePolicy end

"""
    exposure(site::SiteState, policy::ZCS) -> Int8

ZCS exposure:
- Vacant: 0
- Consolidated: q
- Superplastic: 0
"""
function exposure(site::SiteState, policy::ZCS)::Int8
    if !site.allocated
        # Vacant site exposes 0
        return Int8(0)
    elseif site.superplastic
        # Superplastic ZCS exposes 0
        return Int8(0)
    else
        # Consolidated exposes q
        return site.q
    end
end

"""
    exposure(site::SiteState, policy::VPS; prior_q::Int8=site.q) -> Int8

VPS exposure:
- Vacant: 0
- Consolidated: q
- Superplastic: prior committed q (passed as keyword arg or defaults to current q)

Note: For superplastic sites, the prior_q must be tracked externally
(e.g., in site telemetry or passed from the substrate state).
"""
function exposure(site::SiteState, policy::VPS; prior_q::Int8=site.q)::Int8
    if !site.allocated
        # Vacant site exposes 0
        return Int8(0)
    elseif site.superplastic
        # Superplastic VPS exposes prior committed q
        return prior_q
    else
        # Consolidated exposes q
        return site.q
    end
end

# Export helper for getting exposure with a policy
get_exposure(site::SiteState, policy::ExposurePolicy; kwargs...)::Int8 = exposure(site, policy; kwargs...)
