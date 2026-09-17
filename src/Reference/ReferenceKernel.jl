"""
    reference_material_tick!(substrate, gradients, law, dcp, policy; beta, gamma, tick)

Deterministic injected-gradient Stage-0 material tick used by S1b/S3/S3b.
It intentionally starts at the frozen contract's step 5 (coefficient gradients)
because S3 injects a predetermined signed-gradient sequence rather than using a
network forward/backward pass.

The returned `exposures` are the immutable exposure snapshot for the tick.
Lifecycle changes therefore affect only the next tick's exposure.
"""
function reference_material_tick!(substrate::SubstrateState,
                                  gradients::AbstractVector{<:Real},
                                  law::ConstitutiveLaw,
                                  dcp::DCP,
                                  policy::ExposurePolicy;
                                  beta::Real=0.9f0,
                                  gamma::Real=0.9f0,
                                  tick::Integer=1)
    n = length(substrate.sites)
    length(gradients) == n || error("HardFailure: gradient/site length mismatch")
    # Step 1 snapshot is retained through the entire tick.
    exposures = exposure_snapshot(substrate.sites, policy)

    # Steps 6–9: stress, constitutive response, residual integration, motion EMA.
    delta_updates = zeros(Float32, n)
    for i in 1:n
        site = substrate.sites[i]
        telem = substrate.telemetry[i]
        region = get_region_for_site(substrate.region_map, i)
        g = Float32(gradients[i])

        update_stress_ema!(telem, g, beta)

        delta_delta = 0.0f0
        if site.allocated && site.superplastic
            delta_delta = response(law, region, telem, g)
            integrate_residual!(substrate.pool, site.hot_handle, delta_delta)
        end
        delta_updates[i] = delta_delta
        update_residual_motion_ema!(telem, delta_delta, gamma)
        update_counters!(telem, region.yield_up, region.settle_down,
                         region.epsilon_delta)
    end

    # Steps 10–11: immutable snapshots and deterministic DCP decisions. Reserve
    # capacity for melt actions as decisions are emitted so the batch cannot
    # oversubscribe the hot pool before actions are applied.
    actions = Vector{Action}(undef, n)
    reserved_melts = 0
    current_superplastic = count(site -> site.allocated && site.superplastic,
                                 substrate.sites)
    current_superplastic <= Int(substrate.max_superplastic) ||
        error("HardFailure: global superplastic budget already exceeded")
    free_now = available_count(substrate.pool)

    for i in 1:n
        site = substrate.sites[i]
        region = get_region_for_site(substrate.region_map, i)
        budget_available =
            reserved_melts < free_now &&
            current_superplastic + reserved_melts < Int(substrate.max_superplastic)
        snapshot = create_snapshot(i, region, site, substrate.telemetry[i],
                                   budget_available, tick)
        action = decide(dcp, snapshot)
        actions[i] = action
        action isa MeltAction && (reserved_melts += 1)
    end

    # Steps 12–14: atomic lifecycle application in canonical logical site order.
    for action in actions
        apply_action!(substrate, action, policy)
    end

    check_invariants(substrate)
    return (exposures=exposures, delta_updates=delta_updates, actions=actions)
end

"""Canonical action representation used by deterministic reference tests."""
action_code(::NoAction) = (:hold, Int32(0))
action_code(action::MeltAction) = (:melt, action.site_index)
action_code(action::CommitAction) = (:commit, action.site_index)
