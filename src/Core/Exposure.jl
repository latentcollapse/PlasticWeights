"""Superplastic forward-exposure policy."""
abstract type ExposurePolicy end

"""Zero-Centered Superplasticity: a superplastic site exposes zero."""
struct ZCS <: ExposurePolicy end

"""Value-Preserving Superplasticity: a superplastic site exposes prior q."""
struct VPS <: ExposurePolicy end

"""
    RampedVPS(ramp_k=2; m_max=0.05f0)

Value-Preserving Superplasticity with a staged commit exposure ramp (E0c).
A freshly committed FP site does not expose its full consolidated delta at
once: the delta is blended into the forward path over `ramp_k` ticks.

This converts the VPS commit jump (E0 report §2, and the one genuine
substrate shock measured in E0b2 — mid-phase jump 2.49 on re-commit) into a
bounded-rate transition. The committed `w` itself is final at commit time;
only its forward visibility is staged.

P5′ (adaptive ramp): `m_max` is the per-tick exposed-change budget in weight
units. At commit the site stores `ramp_ticks = max(ramp_k, ceil(|δ|/m_max))`,
so a large consolidation extends its own ramp and the per-tick visible change
is bounded by ~m_max regardless of ‖δ‖. E0c attribution: the fixed 2-tick
ramp released ~δ/2 per tick for large δ; m_max makes the bound uniform.

ramp_k = 0 disables the ramp (identical to VPS).
"""
struct RampedVPS <: ExposurePolicy
    ramp_k::Int32
    m_max::Float32
    function RampedVPS(ramp_k::Integer=2; m_max::Real=0.05)
        ramp_k >= 0 || error("HardFailure: RampedVPS ramp_k must be >= 0")
        mf = Float32(m_max)
        isfinite(mf) && mf > 0.0f0 || error("HardFailure: RampedVPS m_max must be finite and > 0")
        new(Int32(ramp_k), mf)
    end
end

"""
    RampedZCS(ramp_k=2; m_max=0.05f0)

Zero-Centered Superplasticity with a staged commit exposure ramp (E0c): a
freshly committed site's value fades in over `ramp_k` ticks instead of
appearing at full magnitude. P5′ adaptive ramp semantics as in RampedVPS.
ramp_k = 0 disables the ramp (identical to ZCS).
"""
struct RampedZCS <: ExposurePolicy
    ramp_k::Int32
    m_max::Float32
    function RampedZCS(ramp_k::Integer=2; m_max::Real=0.05)
        ramp_k >= 0 || error("HardFailure: RampedZCS ramp_k must be >= 0")
        mf = Float32(m_max)
        isfinite(mf) && mf > 0.0f0 || error("HardFailure: RampedZCS m_max must be finite and > 0")
        new(Int32(ramp_k), mf)
    end
end

"""
Effective ramp length for a committed site (P5′): the site's stored
`ramp_ticks` when stamped (> 0), else the policy's fixed ramp_k. The kernel
stamps at commit; hand-built committed sites (ramp_ticks == 0) fall back to
the fixed length, preserving fixture semantics.
"""
effective_ramp_ticks(site::FPSiteState, policy::Union{RampedVPS,RampedZCS})::Int32 =
    site.ramp_ticks > Int32(0) ? site.ramp_ticks : policy.ramp_k

"""
P5′ adaptive ramp length: never shorter than the policy's fixed ramp_k, and
long enough that the per-tick exposed change stays within the m_max budget.
|δ| <= m_max consolidates at the fixed length; larger deltas extend it.
"""
function adaptive_ramp_ticks(delta_abs::Real, ramp_k::Integer, m_max::Real)::Int32
    extra = Float32(delta_abs) / Float32(m_max)
    needed = isfinite(extra) ? ceil(Int32, extra) : typemax(Int32) - Int32(ramp_k)
    return max(Int32(ramp_k), needed)
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

"""P5′ blend: ramp length is the site's own, adaptively stamped at commit."""
function commit_blend(site::FPSiteState, policy::Union{RampedVPS,RampedZCS},
                      tick::Integer)::Float32
    return commit_blend(site, effective_ramp_ticks(site, policy), tick)
end

"""
P5″ exposure trajectory (bounded-rate, event-continuous).

The visible value x(t) follows ONE trajectory toward the site's target value
`w`: x(t) = exposed_base + (w − exposed_base)·b(t), where b is the blend of
the transition stamped when the trajectory last began (at commit or at melt).
Lifecycle events REDIRECT the trajectory — they stamp a new transition from
the currently exposed value — they never interrupt it. This is the repair for
the two P5′ failure modes: melt-mid-ramp reversion (the old code snapped a
long-ramp plastic site straight back to w) and per-tick magnitude
unboundedness (both stamp sites compute their ramp length from the remaining
VISIBLE distance, at the policy's m_max budget).

Superplastic sites under ZCS pin to 0 by policy (no trajectory); under VPS a
plastic site rides its surviving (pre-melt) trajectory to w.
"""
function transitioned_exposure(site::FPSiteState,
                               policy::Union{RampedVPS,RampedZCS},
                               tick::Integer)::Float32
    if site.ramp_ticks <= Int32(0) || site.transition_start == Int32(0)
        return site.w
    end
    # P5″ blend: gated ONLY on the transition record — not on
    # consolidation_tick, which is a phase record (0 while plastic) and must
    # not gate a plastic site's in-flight glide.
    elapsed = Int32(tick) - site.transition_start
    elapsed <= 0 && return site.exposed_base
    elapsed >= site.ramp_ticks && return site.w
    blend = Float32(elapsed) / Float32(site.ramp_ticks)
    return site.exposed_base + (site.w - site.exposed_base) * blend
end

"""
Stamp a new bounded-rate transition from the site's CURRENTLY EXPOSED value
(e0 must be the exposure computed just before the event that redirects the
trajectory). Length = max(ramp_k, ceil(|w − e0| / m_max)); the per-tick
exposed change is thereby bounded by ~m_max for every event, at every ‖w−e0‖.
"""
function stamp_transition!(site::FPSiteState, e0::Real,
                           policy::Union{RampedVPS,RampedZCS}, tick::Integer)
    site.exposed_base = Float32(e0)
    site.transition_start = Int32(tick)
    site.ramp_ticks = adaptive_ramp_ticks(abs(Float32(site.w) - Float32(e0)),
                                          policy.ramp_k, policy.m_max)
    return nothing
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
    # P5″: both phases ride the trajectory. A plastic site glides from its
    # pre-melt visible value to w (the melt no longer snaps exposure); a
    # committed site glides from its pre-commit value to w.
    return transitioned_exposure(site, policy, tick)
end

function exposure(site::FPSiteState, policy::RampedZCS, tick::Integer)::Float32
    !site.allocated && return 0.0f0
    site.superplastic && return 0.0f0
    return transitioned_exposure(site, policy, tick)
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
