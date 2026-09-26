"""Superplastic forward-exposure policy."""
abstract type ExposurePolicy end

"""Zero-Centered Superplasticity: a superplastic site exposes zero."""
struct ZCS <: ExposurePolicy end

"""Value-Preserving Superplasticity: a superplastic site exposes prior q."""
struct VPS <: ExposurePolicy end

function exposure(site::SiteState, ::ZCS)::Int8
    !site.allocated && return Int8(0)
    site.superplastic && return Int8(0)
    return site.q
end

function exposure(site::SiteState, ::VPS)::Int8
    !site.allocated && return Int8(0)
    return site.q
end

"""Take the immutable-for-this-tick visible coefficient snapshot."""
function exposure_snapshot(sites::AbstractVector{SiteState}, policy::ExposurePolicy)::Vector{Int8}
    return Int8[exposure(site, policy) for site in sites]
end

commit_base(site::SiteState, ::ZCS)::Float32 = 0.0f0
commit_base(site::SiteState, ::VPS)::Float32 = Float32(site.q)
