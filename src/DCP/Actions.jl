"""Immutable lifecycle actions emitted by the DCP."""
abstract type Action end
struct NoAction <: Action end
struct MeltAction <: Action
    site_index::Int32
end
struct CommitAction <: Action
    site_index::Int32
end

const NO_ACTION = NoAction()
make_no_action() = NO_ACTION
make_melt(site_index::Integer) = MeltAction(Int32(site_index))
make_commit(site_index::Integer) = CommitAction(Int32(site_index))

"""Concrete isbits union of all possible DCP lifecycle actions."""
const LifecycleAction = Union{NoAction, MeltAction, CommitAction}

function _checked_site_index(substrate::SubstrateState, site_index::Integer)::Int
    i = Int(site_index)
    1 <= i <= length(substrate.sites) || error("HardFailure: action site index $i out of bounds")
    return i
end

function apply_action!(substrate::SubstrateState, ::NoAction, ::ExposurePolicy)
    return nothing
end

function apply_action!(substrate::SubstrateState, action::MeltAction, policy::ExposurePolicy;
                       tick::Integer=0)
    i = _checked_site_index(substrate, action.site_index)
    site = substrate.sites[i]
    site.allocated && !site.superplastic ||
        error("HardFailure: MELT requires an allocated consolidated site")
    has_capacity(substrate.pool) || error("HardFailure: MELT requested with no hot capacity")
    current_superplastic = count(s -> s.allocated && s.superplastic, substrate.sites)
    current_superplastic < Int(substrate.max_superplastic) ||
        error("HardFailure: MELT would exceed global superplastic budget")

    # P5″: capture the pre-melt VISIBLE value before mutation consumes it —
    # the exposure trajectory will be REDIRECTED from here, not interrupted.
    # (Pre-melt the site is committed: both policies expose w, or the glide
    # value if a transition is still in flight.)
    e0_melt = if site isa FPSiteState && policy isa Union{RampedVPS,RampedZCS}
        if site.ramp_ticks > Int32(0) && site.transition_start != Int32(0)
            transitioned_exposure(site, policy, tick)
        else
            site.w
        end
    else
        Float32(0)
    end

    # All checks precede the state mutation. Allocation initializes δ to zero.
    handle = allocate!(substrate.pool, 0.0f0)
    site.superplastic = true
    site.hot_handle = handle

    # E0c: symbolic phase transition Committed -> Plastic (single authority).
    # tick == 0 means "unstamped" (direct manipulation without a tick);
    # the reference kernel always passes the real tick.
    if site isa FPSiteState
        site.phase = :plastic
        site.plastic_since = Int32(tick)
        site.consolidation_tick = Int32(0)
        site.last_commit_delta = 0.0f0
        if policy isa Union{RampedVPS,RampedZCS}
            # P5″: the visible value keeps gliding to w at the policy's
            # per-tick budget — invalidation no longer shocks.
            stamp_transition!(site, e0_melt, policy, tick)
        else
            site.ramp_ticks = Int32(0)
            site.exposed_base = 0.0f0
            site.transition_start = Int32(0)
        end
    end
    reset_lifecycle_counters!(substrate.telemetry[i])
    check_invariants(substrate)
    return nothing
end

function apply_action!(substrate::SubstrateState, action::CommitAction,
                       policy::ExposurePolicy;
                       tick::Integer=0)
    i = _checked_site_index(substrate, action.site_index)
    site = substrate.sites[i]
    site.allocated && site.superplastic ||
        error("HardFailure: COMMIT requires an allocated superplastic site")
    is_valid_handle(substrate.pool, site.hot_handle) ||
        error("HardFailure: COMMIT site owns invalid hot handle")

    delta = get_residual(substrate.pool, site.hot_handle)
    old_handle = site.hot_handle
    region = get_region_for_site(substrate.region_map, i)

    # D1 fix (E0 report §8.1): commit-side hysteresis is now the melt margin —
    # a commit must land where MELT would not be legal for this site
    # (stress_ema strictly below yield_up). The legacy guard
    # (yield_up > settle_down) assumed settle_down was a stress magnitude;
    # settle_down is now a gradient-consistency threshold, independent of
    # yield_up. All checks precede mutation.
    region.yield_up > substrate.telemetry[i].stress_ema ||
        error("HardFailure: COMMIT without melt margin (stress_ema >= yield_up)")

    # Commit is exposed only after this tick's immutable exposure snapshot has
    # already been consumed by the forward/backward path.
    # P5″: capture the pre-commit VISIBLE value before mutation. Under ZCS a
    # plastic site is pinned to 0 (policy, regardless of any in-flight glide);
    # under VPS it exposes its trajectory value (or w if none is in flight).
    e0_commit = if site isa FPSiteState && policy isa Union{RampedVPS,RampedZCS}
        if policy isa RampedZCS && site.superplastic
            0.0f0
        elseif site.ramp_ticks > Int32(0) && site.transition_start != Int32(0)
            transitioned_exposure(site, policy, tick)
        else
            site.w
        end
    else
        Float32(0)
    end

    release!(substrate.pool, old_handle)
    if site isa SiteState
        new_q = ternary_round(commit_base(site, policy) + delta)
        site.q = new_q
    elseif site isa FPSiteState
        new_w = commit_base(site, policy) + delta
        site.w = new_w
    else
        error("HardFailure: unknown site type $(typeof(site))")
    end
    site.superplastic = false
    site.hot_handle = Int32(0)

    # E0c: symbolic phase transition Plastic -> Committed (single authority).
    # The consolidation reference (sign + stress) is recorded from the
    # telemetry this commit closes under; tick == 0 means unstamped.
    if site isa FPSiteState
        telem = substrate.telemetry[i]
        raw = telem.signed_stress_ema
        # If the commit happened at (numerically) zero or unknown load, keep
        # the previous reference — a site that re-commits during a quiet
        # window has not declared a new direction.
        new_sign = !isfinite(raw) || raw == 0.0f0 ? site.commit_sign :
                   (raw > 0.0f0 ? Int8(1) : Int8(-1))
        site.phase = :committed
        site.consolidation_tick = Int32(tick)
        site.plastic_since = Int32(0)
        site.last_commit_delta = delta
        site.commit_sign = new_sign
        site.commit_stress = telem.stress_ema
        if policy isa Union{RampedVPS,RampedZCS}
            # P5″: the trajectory continues from the pre-commit visible value
            # toward the new w — continuity holds by construction, and the
            # ramp length bounds the per-tick exposed change by m_max.
            stamp_transition!(site, e0_commit, policy, tick)
        else
            site.ramp_ticks = Int32(0)
            site.exposed_base = 0.0f0
            site.transition_start = Int32(0)
        end
    end
    reset_lifecycle_counters!(substrate.telemetry[i])
    region.yield_up += region.hardening_increment
    check_invariants(substrate)
    return nothing
end
