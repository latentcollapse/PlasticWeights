"""Superplastic forward-exposure policy."""
abstract type ExposurePolicy end

"""Zero-Centered Superplasticity: a superplastic site exposes zero."""
struct ZCS <: ExposurePolicy end

"""Value-Preserving Superplasticity: a superplastic site exposes prior q."""
struct VPS <: ExposurePolicy end

"""
    RampedVPS(ramp_k=2)

Value-Preserving Superplasticity with a staged commit exposure ramp (E0c).
A freshly committed FP site does not expose its full consolidated delta at
once: the delta is blended into the forward path over `ramp_k` ticks.

This converts the VPS commit jump (E0 report §2, and the one genuine
substrate shock measured in E0b2 — mid-phase jump 2.49 on re-commit) into a
bounded-rate transition. The committed `w` itself is final at commit time;
only its forward visibility is staged.

ramp_k = 0 disables the ramp (identical to VPS).
"""
struct RampedVPS <: ExposurePolicy
    ramp_k::Int32
    function RampedVPS(ramp_k::Integer=2)
        ramp_k >= 0 || error("HardFailure: RampedVPS ramp_k must be >= 0")
        new(Int32(ramp_k))
    end
end

"""
    RampedZCS(ramp_k=2)

Zero-Centered Superplasticity with a staged commit exposure ramp (E0c): a
freshly committed site's value fades in over `ramp_k` ticks instead of
appearing at full magnitude. ramp_k = 0 disables the ramp (identical to ZCS).
"""
struct RampedZCS <: ExposurePolicy
    ramp_k::Int32
    function RampedZCS(ramp_k::Integer=2)
        ramp_k >= 0 || error("HardFailure: RampedZCS ramp_k must be >= 0")
        new(Int32(ramp_k))
    end
end

"""
Commit-exposure blend for a committed FP site at `tick`, in [0,1].

consolidation_tick == 0 (no recorded commit: pre-existing or initialized
material) is ramp-exempt and returns 1 — nothing re-shocks weights that were
never committed by this lifecycle. The tick of the commit itself returns 0
(commit affects the NEXT tick's exposure, per the frozen causal contract).
"""
function commit_blend(site::FPSiteState, ramp_k::Integer, tick::Integer)::Float32
    site.consolidation_tick == Int32(0) && return 1.0f0
    ramp_k <= 0 && return 1.0f0
    elapsed = Int32(tick) - site.consolidation_tick
    elapsed <= 0 && return 0.0f0
    elapsed >= ramp_k && return 1.0f0
    return Float32(elapsed) / Float32(ramp_k)
end

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

function exposure(site::FPSiteState, ::ZCS)::Float32
    !site.allocated && return 0.0f0
    site.superplastic && return 0.0f0
    return site.w
end

function exposure(site::FPSiteState, ::VPS)::Float32
    !site.allocated && return 0.0f0
    return site.w
end

function exposure(site::FPSiteState, policy::RampedVPS, tick::Integer)::Float32
    !site.allocated && return 0.0f0
    site.superplastic && return site.w
    blend = commit_blend(site, policy.ramp_k, tick)
    blend >= 1.0f0 && return site.w
    # Transition from the previously committed value (w - δ) toward w.
    return site.w - (1.0f0 - blend) * site.last_commit_delta
end

function exposure(site::FPSiteState, policy::RampedZCS, tick::Integer)::Float32
    !site.allocated && return 0.0f0
    site.superplastic && return 0.0f0
    blend = commit_blend(site, policy.ramp_k, tick)
    blend >= 1.0f0 ? site.w : blend * site.w
end

# 2-arg calls on ramped policies (legacy call sites) expose the fully
# committed value: without a tick there is no staged transition to compute.
exposure(site::FPSiteState, policy::RampedVPS)::Float32 = exposure(site, VPS())
exposure(site::FPSiteState, policy::RampedZCS)::Float32 = exposure(site, ZCS())

function exposure_snapshot(sites::AbstractVector{FPSiteState}, policy::ExposurePolicy)::Vector{Float32}
    return Float32[exposure(site, policy) for site in sites]
end

"""Tick-aware immutable exposure snapshot (required for ramped policies)."""
function exposure_snapshot(sites::AbstractVector{FPSiteState},
                           policy::ExposurePolicy, tick::Integer)::Vector{Float32}
    return Float32[exposure(site, policy, tick) for site in sites]
end

# Ramped policies are FP-arm instruments: the ternary substrate has no
# consolidation record to ramp from.
function exposure_snapshot(sites::AbstractVector{SiteState},
                           policy::Union{RampedVPS,RampedZCS})
    error("HardFailure: ramped exposure policies apply to the continuous FP substrate only")
end

# Tick-aware fallbacks: legacy policies ignore the tick entirely (bit-identical
# to their 2-arg results); ramped policies override `exposure` with tick-aware
# methods, so dispatch lands on the staged transition.
exposure(site::FPSiteState, policy::ExposurePolicy, tick::Integer) = exposure(site, policy)
exposure(site::SiteState, policy::ExposurePolicy, tick::Integer) = exposure(site, policy)

function exposure_snapshot(sites::AbstractVector{SiteState},
                           policy::ExposurePolicy, tick::Integer)::Vector{Int8}
    return Int8[exposure(site, policy, tick) for site in sites]
end

commit_base(site::SiteState, ::ZCS)::Float32 = 0.0f0
commit_base(site::SiteState, ::VPS)::Float32 = Float32(site.q)
commit_base(site::FPSiteState, ::ZCS)::Float32 = 0.0f0
commit_base(site::FPSiteState, ::VPS)::Float32 = site.w
commit_base(site::FPSiteState, ::RampedZCS)::Float32 = 0.0f0
commit_base(site::FPSiteState, ::RampedVPS)::Float32 = site.w
