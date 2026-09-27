using Test
using PlasticWeights

# Telemetry gets its own regression file because the observer layer has a
# scientific contract of its own: it must report the developmental trajectory
# faithfully while remaining causally inert.

_tbits(x::Float32) = reinterpret(UInt32, x)

function _telemetry_substrate_fingerprint(s::SubstrateState)
    sites = Tuple(
        (site.q, site.allocated, site.superplastic, site.hot_handle)
        for site in s.sites
    )

    telemetry = Tuple(
        (
            _tbits(t.stress_ema),
            _tbits(t.signed_stress_ema),
            _tbits(t.residual_motion_ema),
            t.consecutive_above_yield,
            t.consecutive_stable,
        )
        for t in s.telemetry
    )

    regions = Tuple(
        (
            r.id,
            Tuple(r.site_indices),
            r.region_size,
            _tbits(r.yield_up),
            _tbits(r.settle_down),
            _tbits(r.eta),
            _tbits(r.hardening_increment),
            _tbits(r.epsilon_delta),
            r.k_yield,
            r.k_settle,
        )
        for r in s.region_map.regions
    )

    pool = (
        Tuple(_tbits(x) for x in s.pool.residuals),
        Tuple(s.pool.free_list),
        Tuple(s.pool.allocated),
        s.pool.capacity,
    )

    return (
        sites=sites,
        telemetry=telemetry,
        regions=regions,
        pool=pool,
        max_superplastic=s.max_superplastic,
    )
end

function _telemetry_action_fingerprint(actions)
    Tuple(action_code(action) for action in actions)
end

@testset "Telemetry — immutable event records" begin
    @test_throws ErrorException MilestoneEvent(-1, FIRST_DELTA)
    @test_throws ErrorException MeltEvent(0, 0, 1, 0, 0.0f0, 0.5f0, 0.0f0)
    @test_throws ErrorException MeltEvent(0, 1, 1, 2, 0.0f0, 0.5f0, 0.0f0)
    @test_throws ErrorException MeltEvent(0, 1, 1, 0, -0.1f0, 0.5f0, 0.0f0)
    @test_throws ErrorException CommitEvent(0, 1, 1, 0, 2, 0.0f0, 0.5f0, 0.6f0)
    @test_throws ErrorException CommitEvent(0, 1, 1, 0, 1, 0.0f0, 0.6f0, 0.5f0)

    milestone = MilestoneEvent(3, FIRST_DELTA)
    melt = MeltEvent(4, 7, 2, -1, 0.75f0, 0.5f0, 1.0f0)
    commit = CommitEvent(8, 7, 2, -1, 1, 0.9f0, 0.5f0, 0.55f0)

    @test event_tick(milestone) == 3
    @test event_site(milestone) === nothing
    @test !is_lifecycle_event(milestone)

    @test event_tick(melt) == 4
    @test event_site(melt) == 7
    @test is_lifecycle_event(melt)

    @test event_tick(commit) == 8
    @test event_site(commit) == 7
    @test is_lifecycle_event(commit)
end

@testset "Telemetry — metric semantics and malformed traces" begin
    events = DevelopmentalEvent[
        MilestoneEvent(2, FIRST_DELTA),
        MilestoneEvent(5, PHENOTYPIC_WAKE),
        MeltEvent(10, 3, 1, -1, 0.8f0, 0.5f0, 1.0f0),
        CommitEvent(15, 3, 1, -1, 1, 0.9f0, 0.5f0, 0.55f0),
        MeltEvent(16, 4, 1, 0, 0.7f0, 0.55f0, 0.0f0),
        CommitEvent(18, 4, 1, 0, 0, 0.1f0, 0.55f0, 0.60f0),
        MilestoneEvent(20, CREDIT_UNLOCK),
    ]

    @test melt_count(events) == 2
    @test commit_count(events) == 2
    @test nonzero_prior_remelt_count(events) == 1
    @test commit_flip_count(events) == 1
    @test zcs_lesion_total(events) == 1.0
    @test hardening_total(events) ≈ 0.10 atol=1.0e-6

    @test superplastic_durations(events) == Int64[5, 2]
    @test mean_superplastic_duration(events) == 3.5

    @test first_delta_tick(events) == 2
    @test wake_tick(events) == 5
    @test credit_unlock_tick(events) == 20

    summary = summarize_events(events)
    @test summary.melt_count == 2
    @test summary.commit_count == 2
    @test summary.nonzero_prior_remelts == 1
    @test summary.commit_flip_count == 1
    @test summary.completed_superplastic_cycles == 2
    @test summary.mean_superplastic_duration == 3.5

    duplicate_milestone = DevelopmentalEvent[
        MilestoneEvent(1, FIRST_DELTA),
        MilestoneEvent(2, FIRST_DELTA),
    ]
    @test_throws ErrorException first_delta_tick(duplicate_milestone)
    @test_throws ErrorException summarize_events(duplicate_milestone)

    reversed_time = DevelopmentalEvent[
        MeltEvent(5, 1, 1, 1, 1.0f0, 0.5f0, 1.0f0),
        CommitEvent(4, 1, 1, 1, 0, -0.6f0, 0.5f0, 0.55f0),
    ]
    @test_throws ErrorException superplastic_durations(reversed_time)

    double_melt = DevelopmentalEvent[
        MeltEvent(5, 1, 1, 1, 1.0f0, 0.5f0, 1.0f0),
        MeltEvent(6, 1, 1, 1, 1.0f0, 0.5f0, 1.0f0),
    ]
    @test_throws ErrorException superplastic_durations(double_melt)
end

@testset "Telemetry — recorder milestone latching" begin
    recorder = DevelopmentalRecorder()
    @test isempty(recorder)
    @test length(recorder) == 0

    # Zero-valued observations are not milestones.
    @test !record_wake!(recorder, 1, zeros(Float32, 4))
    @test !record_first_delta!(recorder, 1, zeros(Float32, 4))
    @test !record_credit_unlock!(recorder, 1, zeros(Float32, 4))
    @test isempty(recorder)

    # First occurrence is recorded exactly once.
    @test record_first_delta!(recorder, 2, Float32[0, 0.25, 0, 0])
    @test !record_first_delta!(recorder, 3, Float32[1, 1, 1, 1])

    @test record_wake!(recorder, 3, Float32[0, 1, 0, 0])
    @test !record_wake!(recorder, 4, Float32[1, 1, 1, 1])

    @test record_credit_unlock!(recorder, 4, Float32[0, 0, -0.5, 0])
    @test !record_credit_unlock!(recorder, 5, Float32[1, 1, 1, 1])

    trace = event_trace(recorder)
    @test length(trace) == 3
    @test first_delta_tick(trace) == 2
    @test wake_tick(trace) == 3
    @test credit_unlock_tick(trace) == 4

    # event_trace is defensive: callers cannot mutate recorder storage by
    # mutating the returned vector.
    empty!(trace)
    @test length(recorder) == 3

    reset_recorder!(recorder)
    @test isempty(recorder)
    @test record_first_delta!(recorder, 1, Float32[1])
    @test first_delta_tick(event_trace(recorder)) == 1

    # Recorder rejects time reversal rather than silently sorting history.
    reversed = DevelopmentalRecorder()
    @test record_first_delta!(reversed, 5, Float32[1])
    @test_throws ErrorException record_wake!(reversed, 4, Float32[1])
end

@testset "Telemetry — lifecycle observation is policy-faithful" begin
    zcs_substrate = initialize_consolidated_substrate(64; region_size=64, q=1)
    vps_substrate = deepcopy(zcs_substrate)

    zcs_recorder = DevelopmentalRecorder()
    vps_recorder = DevelopmentalRecorder()

    melt = MeltAction(1)

    zcs_pending = observe_action_before(zcs_substrate, melt, ZCS())
    apply_action!(zcs_substrate, melt, ZCS())
    record_action_after!(zcs_recorder, 1, zcs_pending, zcs_substrate)

    vps_pending = observe_action_before(vps_substrate, melt, VPS())
    apply_action!(vps_substrate, melt, VPS())
    record_action_after!(vps_recorder, 1, vps_pending, vps_substrate)

    zcs_event = only(event_trace(zcs_recorder))
    vps_event = only(event_trace(vps_recorder))

    @test zcs_event isa MeltEvent
    @test vps_event isa MeltEvent
    @test zcs_event.prior_q == 1
    @test vps_event.prior_q == 1
    @test zcs_event.zcs_lesion_size == 1.0f0
    @test vps_event.zcs_lesion_size == 0.0f0
end

@testset "Telemetry — real developmental trace" begin
    substrate = initialize_stage0_seed(
        64;
        region_size=64,
        eta=1.0f0,
        k_yield=1,
        k_settle=1,
    )
    initial_yield = substrate.region_map.regions[1].yield_up
    recorder = DevelopmentalRecorder()

    reference_material_tick!(
        substrate,
        fill(-1.0f0, 64),
        NEWTONIAN,
        FIXED_RULE_CONTROLLER,
        ZCS();
        beta=0.0f0,
        gamma=0.0f0,
        tick=1,
        recorder=recorder,
    )

    @test first_delta_tick(event_trace(recorder)) == 1
    @test commit_count(event_trace(recorder)) == 0
    @test wake_tick(event_trace(recorder)) === nothing

    # D1 fix (E0 report §8.1): exact-zero rest certifies consistency 0 and can
    # never settle — the rest-tick commit wave this test used to encode is the
    # anti-causal behavior the fix removed. The commit wave is now driven by a
    # small CONSISTENT load (the converged-learning regime the certificate was
    # designed to recognize); every downstream expectation is unchanged.
    reference_material_tick!(
        substrate,
        fill(-0.01f0, 64),
        NEWTONIAN,
        FIXED_RULE_CONTROLLER,
        ZCS();
        beta=0.0f0,
        gamma=0.0f0,
        tick=2,
        recorder=recorder,
    )

    @test commit_count(event_trace(recorder)) == 64
    # Tick-2 exposure was snapshotted before COMMIT, so wake is not legal yet.
    @test wake_tick(event_trace(recorder)) === nothing

    reference_material_tick!(
        substrate,
        zeros(Float32, 64),
        NEWTONIAN,
        FIXED_RULE_CONTROLLER,
        ZCS();
        beta=0.0f0,
        gamma=0.0f0,
        tick=3,
        recorder=recorder,
    )

    @test wake_tick(event_trace(recorder)) == 3

    g = zeros(Float32, 64)
    g[1] = 10.0f0

    reference_material_tick!(
        substrate,
        g,
        NEWTONIAN,
        FIXED_RULE_CONTROLLER,
        ZCS();
        beta=0.0f0,
        gamma=0.0f0,
        tick=4,
        recorder=recorder,
    )

    trace = event_trace(recorder)
    summary = summarize_events(trace)

    @test summary.first_delta_tick == 1
    @test summary.wake_tick == 3
    @test summary.credit_unlock_tick === nothing
    @test summary.commit_count == 64
    @test summary.melt_count == 1
    @test summary.nonzero_prior_remelts == 1
    @test summary.total_zcs_lesion == 1.0
    final_yield = substrate.region_map.regions[1].yield_up
    @test summary.total_hardening == Float64(final_yield) - Float64(initial_yield)
    @test summary.completed_superplastic_cycles == 0
    @test summary.mean_superplastic_duration === nothing

    melts = [event for event in trace if event isa MeltEvent]
    @test length(melts) == 1
    @test melts[1].tick == 4
    @test melts[1].site_index == 1
    @test melts[1].prior_q == 1
end

@testset "Telemetry — observer transparency" begin
    # This is the critical telemetry property:
    #
    #     trajectory(recorder = nothing)
    #       ===
    #     trajectory(recorder = enabled)
    #
    # Telemetry is allowed to mutate only its own recorder bookkeeping.
    plain = initialize_consolidated_substrate(
        64;
        region_size=64,
        q=1,
        yield_up=0.5f0,
        settle_down=0.25f0,
        eta=1.0f0,
        hardening_increment=0.125f0,
        epsilon_delta=0.05f0,
        k_yield=2,
        k_settle=2,
    )
    observed = deepcopy(plain)
    recorder = DevelopmentalRecorder()
    law = BinghamInspired(0.125f0)

    gseq = Float32[1, 1, 1, -1, 0, 0, 0, 0, 1, 1]

    for (tick, g1) in enumerate(gseq)
        g_plain = zeros(Float32, 64)
        g_observed = zeros(Float32, 64)
        g_plain[1] = g1
        g_observed[1] = g1

        r_plain = reference_material_tick!(
            plain,
            g_plain,
            law,
            FIXED_RULE_CONTROLLER,
            ZCS();
            beta=0.5f0,
            gamma=0.5f0,
            tick=tick,
        )

        r_observed = reference_material_tick!(
            observed,
            g_observed,
            law,
            FIXED_RULE_CONTROLLER,
            ZCS();
            beta=0.5f0,
            gamma=0.5f0,
            tick=tick,
            recorder=recorder,
        )

        @test Tuple(r_plain.exposures) == Tuple(r_observed.exposures)
        @test Tuple(_tbits(x) for x in r_plain.delta_updates) ==
              Tuple(_tbits(x) for x in r_observed.delta_updates)
        @test _telemetry_action_fingerprint(r_plain.actions) ==
              _telemetry_action_fingerprint(r_observed.actions)
        @test _telemetry_substrate_fingerprint(plain) ==
              _telemetry_substrate_fingerprint(observed)
    end

    @test !isempty(recorder)
end
