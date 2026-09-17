"""
    ExposurePolicy

Exposure API following the Stage-0 contract.

Conceptual contract:
    exposure(site, ::ZCS) -> Int8
    exposure(site, ::VPS) -> Int8

This is the only variant-specific forward semantic.

ZCS (Zero-Centered Superplasticity): 
- Vacant sites expose 0 (!allocated)
- Consolidated sites expose q (allocated && !superplastic)
- Superplastic sites expose 0 (allocated && superplastic)

VPS (Value-Preserving Superplasticity):
- Vacant sites expose 0 (!allocated)
- Consolidated sites expose q (allocated && !superplastic)
- Superplastic sites expose prior committed q (site.q, preserved during melt)

There is NEVER an amplified ±2 state.
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
- site.q for superplastic sites (the q value before melting, preserved in site.q)
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
    exposure(site::SiteState, policy::VPS) -> Int8

VPS exposure:
- Vacant: 0
- Consolidated: q
- Superplastic: prior committed q (which equals site.q since melt preserves q)
"""
function exposure(site::SiteState, policy::VPS)::Int8
    if !site.allocated
        # Vacant site exposes 0
        return Int8(0)
    elseif site.superplastic
        # Superplastic VPS exposes prior committed q
        # Since melt preserves site.q, the current site.q IS the prior committed q
        return site.q
    else
        # Consolidated exposes q
        return site.q
    end
end
