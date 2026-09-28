"""
    reference_material_tick!(substrate, gradients, law, dcp, policy;
                             beta=0.9f0, gamma=0.9f0, tick=1,
                             recorder=nothing)

Deterministic injected-gradient Stage-0 material tick used by S1b/S3/S3b.

It intentionally starts at the frozen contract's step 5 (coefficient gradients)
because S3 injects a predetermined signed-gradient sequence rather than using a
network forward/backward pass.

If `recorder` is a `DevelopmentalRecorder`, telemetry is observed from the
already-computed state transitions without participating in DCP decisions or
substrate mutation.

This path can observe:
- `PHENOTYPIC_WAKE` from the immutable exposure snapshot,
- `FIRST_DELTA` from actual residual movement,
- applied MELT/COMMIT lifecycle events.

`CREDIT_UNLOCK` is intentionally not inferred here because this injected-gradient
reference path does not compute an upstream network gradient. That milestone
belongs to the full network training path.

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
    tick::Integer=1,
    recorder::Union{Nothing,DevelopmentalRecorder}=nothing,
    phase_length::Integer=0)
    n = length(substrate.sites)
    length(gradients) == n || error("HardFailure: gradient/site length mismatch")

    # Step 1: immutable exposure snapshot retained through the entire tick.
    # Tick-aware overload (E0c): ramped policies stage commit visibility;
    # legacy policies ignore the tick (bit-identical to the frozen 2-arg path).
    exposures = exposure_snapshot(substrate.sites, policy, tick)
    recorder === nothing || record_wake!(recorder, tick, exposures)

    # Steps 6–9: stress, constitutive response, residual integration, motion EMA.
    delta_updates = zeros(Float32, n)
    for i in eachindex(substrate.sites)
        site = substrate.sites[i]
        telem = substrate.telemetry[i]
        region = get_region_for_site(substrate.region_map, i)
        g = Float32(gradients[i])

        update_stress_ema!(telem, g, beta)
        update_signed_stress_ema!(telem, g, beta)

        delta_delta = 0.0f0
        if site.allocated && site.superplastic
            delta_delta = response(law, region, telem, g)
            integrate_residual!(substrate.pool, site.hot_handle, delta_delta)
        end

        delta_updates[i] = delta_delta
        update_residual_motion_ema!(telem, delta_delta, gamma)
        # E0c: the conflict certificate needs the site's consolidation
        # reference; ternary sites have none and pass defaults (never
        # conflicted).
        if site isa FPSiteState
            update_counters!(
                telem,
                region.yield_up,
                region.settle_down,
                region.epsilon_delta,
                site.commit_sign,
                site.commit_stress,
            )
            # E0d: direction-blind twin counter for the UndirectedController
            # ablation (same thresholds, no tag-direction condition).
            update_undirected_conflict!(telem, region.settle_down, site.commit_stress)
        else
            update_counters!(
                telem,
                region.yield_up,
                region.settle_down,
                region.epsilon_delta,
            )
        end
    end

    recorder === nothing || record_first_delta!(recorder, tick, delta_updates)

    # Steps 10–11: immutable snapshots and deterministic DCP decisions.
    #
    # Reserve capacity for MELT actions as decisions are emitted so the batch
    # cannot oversubscribe the hot pool before actions are applied.
    actions = Vector{LifecycleAction}(undef, n)
    reserved_melts = 0
    current_superplastic = count(
        site -> site.allocated && site.superplastic,
        substrate.sites,
    )

    current_superplastic <= Int(substrate.max_superplastic) ||
        error("HardFailure: global superplastic budget already exceeded")

    free_now = available_count(substrate.pool)

    # E0c commit budget: at most one COMMIT per tick UNDER THE PHASE MACHINE.
    # The E0b2 residual shock was a coordinated re-commit wave; a per-tick
    # budget turns any wave into a bounded-rate stream. Sites not admitted this
    # tick keep their counters (settle is persistent), so they are admitted on
    # following ticks. The frozen FixedRuleController path is exempt: its
    # batch-commit behavior is part of the frozen reference contract. E0d's
    # TAGR/UNDIR arms ran unbudgeted and stay unbudgeted (committed-arm
    # behavior is preserved bit-exactly). E0e (E0e-D1): the regime-adaptive
    # arm's budget FOLLOWS ITS WINDOW — young = the TAGR rule in full (no
    # budget), deep = the PHASE rule in full (1/tick). `budgeted=true` keeps
    # the 1/tick budget in both windows for protocol-parity studies. The
    # run-wide declaration resolves exactly as decide() resolves it per
    # snapshot: explicit argument first, else the first region's declared
    # length (regions share the declaration in every protocol; undeclared +
    # REGIME remains a HardFailure).
    young_window = false
    if dcp isa RegimeAdaptiveController
        declared_L = phase_length > 0 ? phase_length :
                     Int(substrate.region_map.regions[1].phase_length)
        young_window = _regime_young_phase(dcp, declared_L, tick)
    end
    # E0g (per-phase quota): the budget stays 1/tick in SHAPE, but the phase-
    # quota arm admits min(1, Q − commits_so_far_this_phase) — the quota
    # refills at each phase boundary, lifting the commit rate exactly where
    # the phase machine is rate-starved (short L) while keeping the per-phase
    # VOLUME bounded (E0f-D1 vs TAGR's long-L poisoning). The spent-quota
    # counter is derived from live consolidation stamps, statelessly.
    phase_quota_remaining = 0
    if dcp isa PhaseQuotaController
        declared_L = phase_length > 0 ? phase_length :
                     Int(substrate.region_map.regions[1].phase_length)
        spent = _commits_this_phase(substrate, declared_L, tick)
        phase_quota_remaining =
            max(0, Int(_phase_quota_ticks(dcp.quota_fraction, Int32(declared_L))) - spent)
    end
    # E0h (burst-width allowance): admission is shaped WITHIN the tick's own
    # commit burst. `burst_fraction` scales a cap off the RAW intent count W —
    # the number of sites whose decision is a CommitAction before budget
    # truncation — observed statelessly in a discarded intent pass (decide()
    # is pure, snapshots immutable, so the pass cannot perturb state). The
    # cap is POSITION-BLIND: no phase_length declaration is consulted.
    # E0h-R0 discipline: the budget is computed BEFORE the admission loop for
    # every arm and the loop applies one truncation pass for every arm; arms
    # whose budget cannot truncate (PHASE/MROUTE: 1; TAGR/UNDIR/REGIME
    # unbudgeted: typemax; QUOTA: min(1, remaining); BURST: the burst cap)
    # therefore remain bit-exactly as previously committed.
    burst_cap = 0
    if dcp isa BurstCommitController
        intents = Vector{LifecycleAction}(undef, n)
        for i in eachindex(substrate.sites)
            site = substrate.sites[i]
            region = get_region_for_site(substrate.region_map, i)
            budget_available =
                reserved_melts < free_now &&
                current_superplastic + reserved_melts < Int(substrate.max_superplastic)
            snap = create_snapshot(i, region, site, substrate.telemetry[i],
                budget_available, tick; phase_length=phase_length)
            intents[i] = decide(dcp, snap)
        end
        burst_cap = _burst_allowance(dcp.burst_fraction,
            count(a -> a isa CommitAction, intents))
    end
    commit_budget =
        dcp isa Union{PhaseMachineController, MeltRoutingController} ? 1 :
        dcp isa RegimeAdaptiveController ?
            (dcp.budgeted || !young_window ? 1 : typemax(Int)) :
        dcp isa PhaseQuotaController ? min(1, phase_quota_remaining) :
        dcp isa BurstCommitController ? burst_cap :
        typemax(Int)

    for i in eachindex(substrate.sites)
        site = substrate.sites[i]
        region = get_region_for_site(substrate.region_map, i)

        budget_available =
            reserved_melts < free_now &&
            current_superplastic + reserved_melts < Int(substrate.max_superplastic)

        snapshot = create_snapshot(
            i,
            region,
            site,
            substrate.telemetry[i],
            budget_available,
            tick;
            phase_length=phase_length,
        )

        action = decide(dcp, snapshot)
        if action isa CommitAction && commit_budget <= 0
            action = NO_ACTION
        end
        actions[i] = action
        action isa MeltAction && (reserved_melts += 1)
        action isa CommitAction && (commit_budget -= 1)
    end

    # Steps 12–14: atomic lifecycle application in canonical logical site order.
    #
    # Telemetry observes the same already-decided action immediately before and
    # after application. It has no authority over whether the action occurs.
    for action in actions
        action isa NoAction && continue

        pending = recorder === nothing ? nothing :
                  observe_action_before(substrate, action, policy)

        # apply_action! is the single authority for lifecycle transitions; the
        # E0c phase-record stamps (phase, consolidation_tick, plastic_since,
        # consolidation reference) are part of the transition itself.
        apply_action!(substrate, action, policy; tick=tick)

        # A fired transition resets both conflict counters: the site's
        # reference is fresh (commit) or void (melt reopens the residual).
        telem_i = substrate.telemetry[Int(action.site_index)]
        telem_i.consecutive_conflicted = Int32(0)
        telem_i.consecutive_conflicted_undirected = Int32(0)

        recorder === nothing ||
            record_action_after!(recorder, tick, pending, substrate)
    end

    # E0c note on liveness: the all-committed absorbing state is LEGAL under
    # the phase machine (a stationary task legitimately converges there).
    # Liveness is guaranteed dynamically, not by an invariant: opposed load
    # fires the conflict certificate (mandatory invalidation) and above-yield
    # load fires melts, so capacity to reopen always exists.

    check_invariants(substrate)

    # Keep the historical return surface unchanged. Telemetry is retrieved from
    # the recorder so enabling observation cannot alter callers' data contracts.
    return (
        exposures=exposures,
        delta_updates=delta_updates,
        actions=actions,
    )
end

"""Canonical action representation used by deterministic reference tests."""
action_code(::NoAction) = (:hold, Int32(0))
action_code(action::MeltAction) = (:melt, action.site_index)
action_code(action::CommitAction) = (:commit, action.site_index)
