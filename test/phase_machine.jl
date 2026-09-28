using Test
using PlasticWeights

# E0c — symbolic phase machine (Pass 2 of the gate-fix programme).
#
# Scientific contracts under test:
#
#   1. The site carries a persistent phase record (what it consolidated under,
#      when, and how long it has been plastic) with HardFailure discipline.
#   2. Commit exposure is staged: a fresh commit's delta reaches the forward
#      path over ramp_k ticks (bounded-rate transition, no impulse).
#   3. Invalidation is mandatory: a committed site under sustained OPPOSED
#      load melts (anti-ossification). K3's "permanent rigidity" is now an
#      illegal state, not a steady state.
#   4. Hysteresis/dwell: transitions require sustained evidence; a plastic
#      site cannot commit before k_commit ticks.
#   5. Budgets: at most one commit per tick under the phase machine.
#   6. The full lifecycle cycle Plastic -> Committed -> Plastic runs end to
#      end under a conflicting task stream (liveness axiom holds).
#
# These tests are the E0c regression harness. The E0c sweep script applies
# them to the grid; this file applies them to mechanism fixtures.

_tpm_bits(x::Float32) = reinterpret(UInt32, x)

@testset "E0c — phase record invariants" begin
    # Seed: all plastic, no consolidation history.
    sub = initialize_fp_seed(64; region_size=64)
    for site in sub.sites
        @test site.phase === :plastic
        @test site.consolidation_tick == 0
        @test site.plastic_since == 0
        @test site.commit_sign == 0
        @test site.last_commit_delta == 0.0f0
        check_invariants(site)
    end
    @test check_invariants(sub)

    # Consolidated fixture: all committed, no plastic_since.
    con = initialize_fp_consolidated_substrate(64; region_size=64)
    for site in con.sites
        @test site.phase === :committed
        @test site.plastic_since == 0
        check_invariants(site)
    end
    @test check_invariants(con)

    # Phase is derived, never supplied: superplasticity decides.
    s = FPSiteState(0.5f0, true, true, Int32(1))
    @test s.phase === :plastic
    c = FPSiteState(0.5f0, true, false, Int32(0); commit_sign=-1, last_commit_delta=0.25f0)
    @test c.phase === :committed
    @test c.commit_sign == -1
    @test c.last_commit_delta === 0.25f0
    @test_throws ErrorException FPSiteState(Inf32)
end

@testset "E0c — ramped exposure blending" begin
    # P5″ trajectory contract: exposure glides exposed_base → w over the
    # stamped transition. Fixture: committed at tick 10, visible value was
    # 0.2 (= w − δ with w=1.0, δ=0.8), transition length 2.
    site = FPSiteState(1.0f0, true, false, Int32(0);
                       last_commit_delta=0.8f0, commit_sign=1)
    site.consolidation_tick = 10
    site.exposed_base = 0.2f0
    site.transition_start = 10
    site.ramp_ticks = 2

    # Commit tick itself: not yet visible (commit affects next tick).
    @test commit_blend(site, 2, 10) == 0.0f0
    @test exposure(site, RampedVPS(2), 10) ≈ 0.2f0 atol=1e-7
    @test exposure(site, RampedZCS(2), 10) ≈ 0.2f0 atol=1e-7  # ZCS glides too

    # Half-way through the ramp.
    @test commit_blend(site, 2, 11) == 0.5f0
    @test exposure(site, RampedVPS(2), 11) ≈ 0.6f0 atol=1e-7
    @test exposure(site, RampedZCS(2), 11) ≈ 0.6f0 atol=1e-7

    # Ramp complete: full value under both policies.
    @test commit_blend(site, 2, 12) == 1.0f0
    @test exposure(site, RampedVPS(2), 12) == 1.0f0
    @test exposure(site, RampedZCS(2), 12) == 1.0f0

    # No transition record (unstamped hand-built site): fully visible — the
    # conservative fallback for direct manipulation.
    bare = FPSiteState(1.0f0, true, false, Int32(0);
                       last_commit_delta=0.8f0, commit_sign=1)
    @test exposure(bare, RampedVPS(2), 99) == 1.0f0
    @test exposure(bare, RampedZCS(2), 99) == 1.0f0
    @test commit_blend(bare, 4, 5) == 1.0f0

    # ramp_k = 0 disables new transitions entirely.
    flat = FPSiteState(1.0f0, true, false, Int32(0))
    flat.consolidation_tick = 10
    flat.exposed_base = 0.2f0
    flat.transition_start = 10
    flat.ramp_ticks = 0
    @test exposure(flat, RampedVPS(0), 10) == 1.0f0

    # Superplastic VPS with an in-flight transition rides the glide to w
    # (P5″: melt no longer snaps exposure); ZCS still pins plastic sites to 0.
    gliding = FPSiteState(1.0f0, true, true, Int32(1))
    gliding.exposed_base = 0.2f0
    gliding.transition_start = 7
    gliding.ramp_ticks = 4
    @test exposure(gliding, RampedVPS(2), 9) ≈ 0.6f0 atol=1e-7
    @test exposure(gliding, RampedZCS(2), 9) == 0.0f0

    # Unstamped committed sites keep the effective-length fallback contract.
    @test effective_ramp_ticks(bare, RampedVPS(2)) == 2
end

@testset "E0d — tag routing mechanics" begin
    # Carrier lock: a site's tag survives MELT (the melt preserves w and the
    # consolidation reference by design — the lifecycle's memory).
    sub = initialize_fp_consolidated_substrate(64; region_size=64)
    site = sub.sites[1]
    site.commit_sign = Int8(1)
    site.commit_stress = 0.05f0
    site.consolidation_tick = Int32(3)
    # Melt via the kernel so stamps are authoritative. NOTE the load is
    # OPPOSED to the tag: the phase machine's committed-side melt fires ONLY
    # via the conflict certificate (sustained opposed load) — aligned sites
    # are implicitly protected forever (the E0d implicit-routing observation).
    # With beta=0 the EMA re-derives exactly (c=1) and the floor is
    # max(0.5*0.05, 1e-3) = 0.025 << 0.6, so the counter accrues 1/tick;
    # default conflict_k=4 → the melt fires on the 4th opposed tick.
    sub.telemetry[1].stress_ema = 0.6f0
    for tick in 9:12
        reference_material_tick!(sub, fill(-0.6f0, 64), NEWTONIAN,
            PHASE_MACHINE_CONTROLLER, RampedVPS(2); beta=0.0f0, gamma=0.0f0, tick=tick)
    end
    @test site.phase === :plastic
    @test site.commit_sign == Int8(1)   # THE CARRIER: tag outlived the melt
    @test site.commit_stress == 0.05f0

    # Dwell remission: TAGR commits a tag-aligned melted site on the first
    # certified settle tick; PHASE makes the same site wait k_commit.
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)
    for (ctrl, expected) in ((TAG_ROUTING_CONTROLLER, :commit),
                             (PHASE_MACHINE_CONTROLLER, :hold))
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)          # aligned with the load below
        st.plastic_since = Int32(10)
        s.telemetry[1].consecutive_stable = Int32(2)  # certificate saturated
        s.telemetry[1].stress_ema = 0.05f0            # melt margin holds
        s.telemetry[1].signed_stress_ema = 0.05f0     # direction: agrees with tag
        snap = create_snapshot(1, s.region_map.regions[1], st,
            s.telemetry[1], true, 11)                 # plastic age = 1 < k=2
        a = decide(ctrl, snap)
        if expected === :commit
            @test a isa CommitAction
        else
            @test a isa NoAction
        end
    end

    # The remission is direction-gated: a tag-OPPOSED melted site still waits.
    s = mksub()
    st = s.sites[1]
    st.commit_sign = Int8(-1)             # opposed to the load below
    st.plastic_since = Int32(10)
    s.telemetry[1].consecutive_stable = Int32(2)
    s.telemetry[1].stress_ema = 0.05f0
    s.telemetry[1].signed_stress_ema = 0.05f0
    snap = create_snapshot(1, s.region_map.regions[1], st,
        s.telemetry[1], true, 11)
    @test decide(TAG_ROUTING_CONTROLLER, snap) isa NoAction

    # Direction-blind twin: aligned sustained load accrues the undirected
    # counter but never the directed one.
    t = SiteTelemetry(0.3f0)
    t.signed_stress_ema = 0.3f0
    update_counters!(t, 0.5f0, 0.25f0, 0.02f0, Int8(1), 0.4f0)
    update_undirected_conflict!(t, 0.25f0, 0.4f0)
    @test t.consecutive_conflicted == 0          # aligned: directed silent
    @test t.consecutive_conflicted_undirected == 1  # blind: counts anyway
    # UndirectedController must therefore melt a site the phase machine spares.
    site2 = sub.sites[2]
    site2.commit_sign = Int8(1)
    site2.commit_stress = 0.3f0
    sub.telemetry[2].stress_ema = 0.3f0
    sub.telemetry[2].signed_stress_ema = 0.3f0
    sub.telemetry[2].consecutive_conflicted_undirected =
        sub.region_map.regions[1].conflict_k   # saturated for THIS region
    snap2 = create_snapshot(2, sub.region_map.regions[1], site2,
        sub.telemetry[2], true, 99)
    @test decide(UNDIRECTED_CONTROLLER, snap2) isa MeltAction
end

@testset "E0c P5-prime — adaptive ramp bounds per-tick exposed change" begin
    # Length selection: small deltas keep the fixed length; large deltas
    # extend it to ceil(|δ|/m_max).
    @test adaptive_ramp_ticks(0.04f0, 2, 0.05f0) == 2
    @test adaptive_ramp_ticks(0.05f0, 2, 0.05f0) == 2   # ceil(1.0) = 1 < k
    @test adaptive_ramp_ticks(0.11f0, 2, 0.05f0) == 3   # ceil(2.2)
    @test adaptive_ramp_ticks(0.30f0, 2, 0.05f0) == 6

    # A stamped commit with a large delta: ramp_ticks = 6 for |w − e0| = 0.3
    # at m_max = 0.05, so the per-tick visible change is ~0.05, not δ/2 = 0.15.
    site = FPSiteState(1.3f0, true, false, Int32(0);
                       last_commit_delta=0.3f0, commit_sign=1)
    site.consolidation_tick = 10
    site.exposed_base = 1.0f0
    site.transition_start = 10
    site.ramp_ticks = 6
    policy = RampedVPS(2; m_max=0.05f0)

    @test effective_ramp_ticks(site, policy) == 6
    e10 = exposure(site, policy, 10)
    e13 = exposure(site, policy, 13)
    e16 = exposure(site, policy, 16)
    @test e10 ≈ 1.0f0 atol=1e-6          # transition start: still the old value
    @test e13 ≈ 1.15f0 atol=1e-6         # halfway: +0.15 over 3 ticks
    @test e16 == 1.3f0                   # ramp complete
    @test (e13 - e10) / 3 ≈ 0.05f0 atol=1e-6   # the P5′ bound, honored

    # ZCS gets the same treatment: fades in over the stored length.
    z = FPSiteState(0.9f0, true, false, Int32(0); last_commit_delta=0.9f0)
    z.consolidation_tick = 4
    z.exposed_base = 0.0f0
    z.transition_start = 4
    z.ramp_ticks = 18
    @test adaptive_ramp_ticks(0.9f0, 2, 0.05f0) == 18
    @test exposure(z, RampedZCS(2; m_max=0.05f0), 13) ≈ 0.45f0 atol=1e-6
    @test exposure(z, RampedZCS(2; m_max=0.05f0), 22) == 0.9f0

    # Tick-aware snapshots: ramped FP path stages; legacy path bit-identical.
    sub = initialize_fp_seed(64; region_size=64)
    snap_legacy = exposure_snapshot(sub.sites, VPS())
    snap_tickaware = exposure_snapshot(sub.sites, VPS(), 99)
    @test snap_legacy == snap_tickaware
    @test exposure_snapshot(sub.sites, RampedVPS(3), 5) isa Vector{Float32}

    # Ramped policies refuse the ternary substrate: no record to ramp from.
    ternary = initialize_stage0_seed(64; region_size=64)
    @test_throws ErrorException exposure_snapshot(ternary.sites, RampedVPS(2))
end

@testset "E0c — conflict certificate and mandatory invalidation" begin
    # A committed site with a consolidation reference (sign +1, consolidated
    # under stress 0.5), under sustained OPPOSED consistent load.
    sub = initialize_fp_consolidated_substrate(64; region_size=64,
        initial_weights=fill(0.5f0, 64), conflict_k=2)
    site = sub.sites[1]
    site.commit_sign = Int8(1)          # consolidated under positive load
    site.commit_stress = 0.5f0          # under stress EMA 0.5
    site.consolidation_tick = Int32(5)
    sub.telemetry[1].stress_ema = 0.6f0
    sub.telemetry[1].signed_stress_ema = 0.6f0

    # Aligned load: never conflicted (consistency high, direction agrees).
    update_counters!(sub.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        site.commit_sign, site.commit_stress)
    @test sub.telemetry[1].consecutive_conflicted == 0

    # Opposed but BELOW the floor (half the consolidating stress): small
    # contrary drift cannot invalidate.
    sub.telemetry[1].stress_ema = 0.2f0
    sub.telemetry[1].signed_stress_ema = -0.2f0
    update_counters!(sub.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        site.commit_sign, site.commit_stress)
    @test sub.telemetry[1].consecutive_conflicted == 0

    # Opposed, above floor (0.6 >= 0.25), consistent: the counter accrues...
    sub.telemetry[1].stress_ema = 0.6f0
    sub.telemetry[1].signed_stress_ema = -0.6f0
    update_counters!(sub.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        site.commit_sign, site.commit_stress)
    @test sub.telemetry[1].consecutive_conflicted == 1

    # ...and the phase machine MUST melt once conflict_k is reached.
    update_counters!(sub.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        site.commit_sign, site.commit_stress)
    @test sub.telemetry[1].consecutive_conflicted == 2

    snap = create_snapshot(1, sub.region_map.regions[1], site,
        sub.telemetry[1], true, 99)
    action = decide(PHASE_MACHINE_CONTROLLER, snap)
    @test action isa MeltAction
    @test action.site_index == Int32(1)

    # Without a consolidation reference (commit_sign == 0): never invalidated.
    bare = deepcopy(sub)
    bare.sites[1].commit_sign = Int8(0)
    update_counters!(bare.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        bare.sites[1].commit_sign, bare.sites[1].commit_stress)
    update_counters!(bare.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        bare.sites[1].commit_sign, bare.sites[1].commit_stress)
    @test bare.telemetry[1].consecutive_conflicted == 0

    # Inconsistent opposed load (direction noise): counter resets.
    sub.telemetry[1].consecutive_conflicted = 1
    sub.telemetry[1].signed_stress_ema = 0.1f0   # noise, not opposed
    update_counters!(sub.telemetry[1], 0.5f0, 0.25f0, 0.02f0,
        site.commit_sign, site.commit_stress)
    @test sub.telemetry[1].consecutive_conflicted == 0
end

@testset "E0c — commit dwell (chattering hysteresis)" begin
    # Fast-settle plastic site, freshly melted at tick 10 (plastic_since=10).
    # The settle certificate is hand-saturated (as in the Pass-1 fixture
    # style) so the ONLY remaining gate under test is the dwell.
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)
    site = sub.sites[1]
    site.plastic_since = Int32(10)
    sub.telemetry[1].consecutive_stable = Int32(2)  # k_settle = 2: saturated
    sub.telemetry[1].stress_ema = 0.0f0             # melt margin holds (τ=100)

    # k_commit = 2: at tick 11 (age 1) commit is refused even though the
    # settle certificate is saturated.
    snap11 = create_snapshot(1, sub.region_map.regions[1], site,
        sub.telemetry[1], true, 11)
    @test decide(PhaseMachineController(2), snap11) isa NoAction

    # At tick 12 (age 2): dwell satisfied, commit fires.
    snap12 = create_snapshot(1, sub.region_map.regions[1], site,
        sub.telemetry[1], true, 12)
    a12 = decide(PhaseMachineController(2), snap12)
    @test a12 isa CommitAction

    # k_commit = 5 at tick 12: still refused.
    @test decide(PhaseMachineController(5), snap12) isa NoAction

    # FixedRuleController is exempt from dwell (frozen contract).
    @test decide(FIXED_RULE_CONTROLLER, snap11) isa CommitAction
end

@testset "E0c — full lifecycle cycle under conflicting load" begin
    # End-to-end: commit under task A (positive gradients), then sustained
    # opposed load (negative) must invalidate and reopen the site.
    # eta=10 puts |Δδ| = |g|/eta = 0.005 below epsilon_delta, i.e. the load is
    # in the converged-learning regime the settle certificate recognizes.
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.25f0,
        epsilon_delta=0.02f0, eta=10.0f0, conflict_k=2)
    dcp = PHASE_MACHINE_CONTROLLER
    law = NEWTONIAN
    ramp = RampedVPS(2)

    # Phase 1: consistent positive load, small (converged-learning regime).
    # The settle certificate fires when c >= 0.25, which the shared (1-β)
    # first-step convention delivers from the first tick; commit then needs
    # melt margin (σ < τ) and dwell (k_commit = 2).
    g_pos = fill(0.05f0, 64)
    committed_tick = 0
    for tick in 1:30
        reference_material_tick!(sub, g_pos, law, dcp, RampedVPS(2);
            beta=0.5f0, gamma=0.5f0, tick=tick)
        if sub.sites[1].phase === :committed
            committed_tick = tick
            break
        end
    end
    @test committed_tick > 0
    @test sub.sites[1].commit_sign == Int8(1)
    @test sub.sites[1].consolidation_tick == committed_tick
    @test sub.sites[1].plastic_since == 0
    # P5′: the commit stamped its own adaptive ramp length.
    @test sub.sites[1].ramp_ticks ==
          adaptive_ramp_ticks(abs(sub.sites[1].last_commit_delta), 2, 0.05f0)

    # Phase 2: sustained opposed load. conflict_k = 2 → reopen quickly.
    g_neg = fill(-0.05f0, 64)
    reopened_tick = 0
    for tick in (committed_tick + 1):(committed_tick + 40)
        reference_material_tick!(sub, g_neg, law, dcp, RampedVPS(2);
            beta=0.5f0, gamma=0.5f0, tick=tick)
        if sub.sites[1].phase === :plastic
            reopened_tick = tick
            break
        end
    end
    @test reopened_tick > 0
    @test sub.sites[1].plastic_since == reopened_tick
    # P5″: melt REDIRECTS the exposure trajectory instead of clearing it —
    # the site keeps gliding to w at the policy's per-tick budget, so
    # invalidation never shocks. A fresh bounded-rate transition is stamped.
    @test sub.sites[1].ramp_ticks > 0
    @test sub.sites[1].transition_start == reopened_tick

    # The re-melt only costs the site its open residual — the committed w
    # survives as the melt base (VPS), so invalidation is not amnesia.
    @test sub.sites[1].hot_handle != 0

    # Liveness axiom: the machine never left itself zero open residuals.
    @test any(s -> s.allocated && s.superplastic, sub.sites)
end

@testset "E0c — commit budget under the phase machine" begin
    # All-settle seed under a small consistent load: FixedRule commits all 64
    # at once (frozen contract); PhaseMachine admits at most one per tick.
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)
    g = fill(0.01f0, 64)

    fixed = mk()
    rf = nothing
    for tick in 1:2
        rf = reference_material_tick!(fixed, g, NEWTONIAN,
            FIXED_RULE_CONTROLLER, VPS(); beta=0.0f0, gamma=0.0f0, tick=tick)
    end
    @test count(a -> a isa CommitAction, rf.actions) == 64

    pm = mk()
    rp = nothing
    for tick in 1:2
        rp = reference_material_tick!(pm, g, NEWTONIAN,
            PHASE_MACHINE_CONTROLLER, RampedVPS(2); beta=0.0f0, gamma=0.0f0, tick=tick)
    end
    @test count(a -> a isa CommitAction, rp.actions) == 1
    # Not admitted this tick ≠ lost: the settle counter persists.
    @test count(a -> a isa NoAction, rp.actions) == 63
    # 63 sites still hold their saturated certificate; the committed site's
    # counters were reset by the transition.
    @test count(==(2), [t.consecutive_stable for t in pm.telemetry]) == 63
end

@testset "E0c — all-committed absorbing state is legal; liveness is dynamic" begin
    # A fully-committed substrate is a legitimate steady state under a
    # stationary task (nothing to adapt to). The tick must NOT fail.
    converged = initialize_fp_consolidated_substrate(64; region_size=64)
    r = reference_material_tick!(converged, fill(0.01f0, 64), NEWTONIAN,
        PHASE_MACHINE_CONTROLLER, RampedVPS(2);
        beta=0.5f0, gamma=0.5f0, tick=1)
    @test all(a -> a isa NoAction, r.actions)

    # Liveness is guaranteed dynamically: sustained OPPOSED load of comparable
    # strength to the consolidating load fires the conflict certificate and
    # reopens sites (mandatory invalidation).
    opposed = initialize_fp_consolidated_substrate(64; region_size=64)
    site = opposed.sites[1]
    site.commit_sign = Int8(1)
    site.commit_stress = 0.05f0   # consolidated under modest load
    site.consolidation_tick = Int32(1)
    reopened = false
    for tick in 1:30
        reference_material_tick!(opposed, fill(-0.05f0, 64), NEWTONIAN,
            PHASE_MACHINE_CONTROLLER, RampedVPS(2);
            beta=0.5f0, gamma=0.5f0, tick=tick)
        site.phase === :plastic && (reopened = true; break)
    end
    @test reopened

    # The frozen controller keeps its contract on the same substrate.
    frozen = initialize_fp_consolidated_substrate(64; region_size=64)
    rf = reference_material_tick!(frozen, zeros(Float32, 64), NEWTONIAN,
        FIXED_RULE_CONTROLLER, VPS(); beta=0.0f0, gamma=0.0f0, tick=1)
    @test all(a -> a isa NoAction, rf.actions)
end

@testset "E0c — ramped VPS end-to-end learning and determinism" begin
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    mk_state = (m) -> initialize_material_training(m, initialize_fp_seed(N;
        region_size=64, settle_down=0.0f0, eta=1.0f0,
        hardening_increment=0.05f0, epsilon_delta=1.0f6,
        k_yield=2, k_settle=2))

    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=PHASE_MACHINE_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
    )

    X = Float32[1 -1; 1 -1]
    Y = Float32[1 -1]

    mlp1 = mlp
    mlp2 = deepcopy(mlp)
    st1 = mk_state(mlp1)
    st2 = mk_state(mlp2)

    rec1 = DevelopmentalRecorder()
    for _ in 1:60
        material_training_step!(mlp1, st1, X, Y, cfg; recorder=rec1)
    end
    for _ in 1:60
        material_training_step!(mlp2, st2, X, Y, cfg)
    end

    # Bitwise determinism with the phase machine + ramp in the loop.
    fp1 = [_tpm_bits(Float32(x)) for x in vec(mlp1.H_FP32)]
    fp2 = [_tpm_bits(Float32(x)) for x in vec(mlp2.H_FP32)]
    @test fp1 == fp2
    @test check_invariants(st1, mlp1)

    # Learns: committed material is (staged, then fully) forward-visible and
    # the head converges.
    pred = material_predict(mlp1, st1, X, RampedVPS(2), st1.step)
    final_loss = 0.5f0 * sum(abs2, pred .- Y) / length(Y)
    @test final_loss < 0.05f0
end

# ---------------------------------------------------------------------------
# E0e — regime-adaptive routing (Pass 3b).
#
# Contracts under test:
#   1. Regime metadata is harness-declared (region/config) and DERIVED
#      per-snapshot from the authoritative tick; it is DCP-inert for every
#      committed arm and validated with HardFailure discipline.
#   2. Young window: REGIME remits dwell exactly like TAGR (tag-aligned
#      melted sites commit on the first certified settle tick).
#   3. Deep window: REGIME is behaviorally the phase machine — dwell applies,
#      commit-identical to PHASE and different from TAGR on the same state.
#   4. The melt side is the phase machine's, independent of the window.
#   5. Undeclared phase length is a HardFailure for REGIME (no silent
#      degeneration), end to end through the training config path.
#   6. REGIME joins the phase machine's 1/tick commit budget.
# ---------------------------------------------------------------------------
@testset "E0e — regime metadata on FPSnapshot" begin
    # Undeclared by default: phase_length 0, ticks_into_phase 0.
    sub0 = initialize_fp_seed(64; region_size=64)
    snap0 = create_snapshot(1, sub0.region_map.regions[1], sub0.sites[1],
        sub0.telemetry[1], true, 25)
    @test snap0.phase_length == 0
    @test snap0.ticks_into_phase == 0

    # Region-declared: position is derived from the authoritative tick.
    sub = initialize_fp_seed(64; region_size=64, phase_length=10)
    snap = create_snapshot(1, sub.region_map.regions[1], sub.sites[1],
        sub.telemetry[1], true, 25)
    @test snap.phase_length == 10
    @test snap.ticks_into_phase == mod(24, 10) == 4

    # Config override wins over the region's declaration (harness declares
    # per run; no substrate mutation, snapshot-level only).
    snapov = create_snapshot(1, sub.region_map.regions[1], sub.sites[1],
        sub.telemetry[1], true, 25; phase_length=40)
    @test snapov.phase_length == 40
    @test snapov.ticks_into_phase == 24

    # Constructor validation: HardFailure discipline on regime metadata.
    @test_throws ErrorException FPSnapshot(1, 0.5f0, true, true, 0.1f0, 0.0f0,
        0, 0, 0.2f0, 0.8f0, 2, 2, 0.02f0, true, 11; phase_length=-5)
    @test_throws ErrorException FPSnapshot(1, 0.5f0, true, true, 0.1f0, 0.0f0,
        0, 0, 0.2f0, 0.8f0, 2, 2, 0.02f0, true, 11; phase_length=5,
        ticks_into_phase=5)          # out of range [0, L-1]
    @test_throws ErrorException FPSnapshot(1, 0.5f0, true, true, 0.1f0, 0.0f0,
        0, 0, 0.2f0, 0.8f0, 2, 2, 0.02f0, true, 11; phase_length=0,
        ticks_into_phase=3)          # position without a declared length
    ok = FPSnapshot(1, 0.5f0, true, true, 0.1f0, 0.0f0,
        0, 0, 0.2f0, 0.8f0, 2, 2, 0.02f0, true, 11; phase_length=5,
        ticks_into_phase=4)
    @test ok.phase_length == 5 && ok.ticks_into_phase == 4
end

@testset "E0e — RegimeAdaptiveController construction" begin
    @test RegimeAdaptiveController(2).k_commit == Int32(2)
    @test RegimeAdaptiveController(2).young_fraction == 0.5f0
    @test RegimeAdaptiveController(2; young_fraction=1.0).young_fraction == 1.0f0
    @test_throws ErrorException RegimeAdaptiveController(0)
    @test_throws ErrorException RegimeAdaptiveController(2; young_fraction=0.0)
    @test_throws ErrorException RegimeAdaptiveController(2; young_fraction=1.5)
    @test_throws ErrorException RegimeAdaptiveController(2; young_fraction=NaN32)
end

@testset "E0e — young window remits dwell (TAGR-equivalent)" begin
    # Same fixture as the E0d remission test, with a DECLARED phase length.
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    for tick in (11, 13)            # ticks_into_phase 0 and 2, both < 5
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)    # aligned with the load below
        st.plastic_since = Int32(10)
        s.telemetry[1].consecutive_stable = Int32(2)  # certificate saturated
        s.telemetry[1].stress_ema = 0.05f0            # melt margin holds
        s.telemetry[1].signed_stress_ema = 0.05f0     # direction agrees with tag
        snap = create_snapshot(1, s.region_map.regions[1], st,
            s.telemetry[1], true, tick)               # plastic age = tick - 10
        @test snap.ticks_into_phase < 5               # young, by construction
        a = decide(REGIME_ADAPTIVE_CONTROLLER, snap)
        @test a isa CommitAction
        # TAGR gives the same answer in the young window (remission equality).
        @test decide(TAG_ROUTING_CONTROLLER, snap) isa CommitAction
        # k_commit=5 exceeds the young-window ages here: remission is what
        # fires, not age.
        @test decide(RegimeAdaptiveController(5), snap) isa CommitAction
    end
end

@testset "E0e — deep window is behaviorally the phase machine" begin
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    mk = (tick, plastic_since) -> begin
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)
        st.plastic_since = Int32(plastic_since)
        s.telemetry[1].consecutive_stable = Int32(2)
        s.telemetry[1].stress_ema = 0.05f0
        s.telemetry[1].signed_stress_ema = 0.05f0
        return create_snapshot(1, s.region_map.regions[1], st,
            s.telemetry[1], true, tick)
    end

    # Fresh melt DEEP in the phase (melted at tick 15 while young; now tick
    # 16 = tip 5 deep, plastic age 1 < k_commit): the dwell applies to REGIME
    # and PHASE alike. This is the E0e mechanism under test — melts land at
    # every phase position, and only the YOUNG window fast-tracks them.
    snap16 = mk(16, 15)
    @test snap16.ticks_into_phase == 5
    @test decide(REGIME_ADAPTIVE_CONTROLLER, snap16) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap16) isa NoAction
    @test decide(TAG_ROUTING_CONTROLLER, snap16) isa CommitAction

    # One tick later (tip 6, age 2 = k_commit): dwell satisfied, REGIME
    # commits exactly when the phase machine commits.
    snap17 = mk(17, 15)
    @test snap17.ticks_into_phase == 6
    @test action_code(decide(REGIME_ADAPTIVE_CONTROLLER, snap17)) ==
          action_code(decide(PHASE_MACHINE_CONTROLLER, snap17))
    @test decide(REGIME_ADAPTIVE_CONTROLLER, snap17) isa CommitAction

    # Late-phase fresh melt (tick 19, tip 8, age 1): the deep refusal holds
    # to the end of the phase; TAGR's unconditional remission still differs.
    snap19 = mk(19, 18)
    @test snap19.ticks_into_phase == 8
    @test decide(REGIME_ADAPTIVE_CONTROLLER, snap19) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap19) isa NoAction
    @test decide(TAG_ROUTING_CONTROLLER, snap19) isa CommitAction
end

@testset "E0e — young_fraction moves the boundary" begin
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    mk = (tick, plastic_since) -> begin
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)
        st.plastic_since = Int32(plastic_since)
        s.telemetry[1].consecutive_stable = Int32(2)
        s.telemetry[1].stress_ema = 0.05f0
        s.telemetry[1].signed_stress_ema = 0.05f0
        return create_snapshot(1, s.region_map.regions[1], st,
            s.telemetry[1], true, tick)
    end
    # yf = 0.2, L = 10: young iff ticks_into_phase < 2 (boundary exclusive).
    r02 = RegimeAdaptiveController(2; young_fraction=0.2)
    @test decide(r02, mk(11, 10)) isa CommitAction     # tip 0, age 1: remitted
    @test decide(r02, mk(12, 10)) isa CommitAction     # tip 1, age 2: remitted
    @test decide(r02, mk(13, 12)) isa NoAction         # tip 2 (deep!), age 1: dwell applies
    @test decide(TAG_ROUTING_CONTROLLER, mk(13, 12)) isa CommitAction  # the contrast
    # yf = 1.0: the whole phase is young — remission everywhere.
    r10 = RegimeAdaptiveController(2; young_fraction=1.0)
    for (tick, ps) in ((11, 10), (13, 12), (16, 15), (19, 15))
        @test decide(r10, mk(tick, ps)) isa CommitAction
    end
end

@testset "E0e — melt side is the phase machine's, window-independent" begin
    # A committed, conflicted site MUST melt at any phase position.
    sub = initialize_fp_consolidated_substrate(64; region_size=64,
        initial_weights=fill(0.5f0, 64), conflict_k=2, phase_length=10)
    site = sub.sites[1]
    site.commit_sign = Int8(1)
    site.commit_stress = 0.5f0
    site.consolidation_tick = Int32(5)
    sub.telemetry[1].stress_ema = 0.6f0
    sub.telemetry[1].signed_stress_ema = -0.6f0
    for tip_tick in (11, 16)        # young and deep positions alike
        t = sub.telemetry[1]
        t.consecutive_conflicted = Int32(2)   # saturated for this region
        snap = create_snapshot(1, sub.region_map.regions[1], site, t, true, tip_tick)
        a = decide(REGIME_ADAPTIVE_CONTROLLER, snap)
        @test a isa MeltAction && a.site_index == Int32(1)
        # Same verdict as the phase machine on identical state.
        @test action_code(decide(PHASE_MACHINE_CONTROLLER, snap)) ==
              action_code(a)
    end
end

@testset "E0e — undeclared phase length is a HardFailure for REGIME" begin
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)   # phase_length undeclared
    st = sub.sites[1]
    st.commit_sign = Int8(1)
    st.plastic_since = Int32(10)
    sub.telemetry[1].consecutive_stable = Int32(2)
    sub.telemetry[1].stress_ema = 0.05f0
    sub.telemetry[1].signed_stress_ema = 0.05f0
    snap = create_snapshot(1, sub.region_map.regions[1], st,
        sub.telemetry[1], true, 11)
    @test_throws ErrorException decide(REGIME_ADAPTIVE_CONTROLLER, snap)
    # The other arms are unaffected (metadata is DCP-inert for them).
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    @test decide(TAG_ROUTING_CONTROLLER, snap) isa CommitAction

    # End to end: the training config path cannot silently degenerate either.
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    state = initialize_material_training(mlp, sub)
    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=REGIME_ADAPTIVE_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
    )
    @test_throws ErrorException material_training_step!(mlp, state,
        Float32[1 -1; 1 -1], Float32[1 -1], cfg)
end

@testset "E0e — REGIME joins the phase machine's commit budget" begin
    # All-settle seed under a small consistent load: PHASE admits at most one
    # commit per tick; REGIME must behave IDENTICALLY (seeds have
    # plastic_since == 0, so remission is unreachable — only the budget is
    # under test). Tick 1 commits nothing anywhere: the settle counter accrues
    # live and reaches k_settle = 2 only on tick 2.
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=50)
    g = fill(0.01f0, 64)
    counts = Dict{Symbol,Vector{Int}}()
    prints = Dict{Symbol,Vector{Vector{Tuple{Symbol,Int32}}}}()
    for (name, dcp) in ((:phase, PHASE_MACHINE_CONTROLLER),
                        (:regime, REGIME_ADAPTIVE_CONTROLLER))
        sub = mk()
        per_tick = Int[]
        prints[name] = Vector{Tuple{Symbol,Int32}}[]
        for tick in 1:4
            r = reference_material_tick!(sub, g, NEWTONIAN, dcp, ZCS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            push!(per_tick, count(a -> a isa CommitAction, r.actions))
            push!(prints[name], action_code.(r.actions))
        end
        counts[name] = per_tick
        @test all(<=(1), per_tick)                     # the budget itself
        @test check_invariants(sub)
    end
    @test counts[:regime] == counts[:phase]            # identical admission
    @test counts[:regime] == [0, 1, 1, 1]              # and the live pattern
    @test prints[:regime] == prints[:phase]            # same sites, same ticks
end

@testset "E0e — unbudgeted young window runs the full TAGR rule (E0e-D1)" begin
    # E0e-D1: under the 1/tick budget, dwell remission is behaviorally inert
    # (the budget queue gates recommit timing, not k_commit). With
    # budgeted=false, the YOUNG window therefore carries the TAGR rule in
    # full — remission AND no commit budget — while the DEEP window keeps the
    # phase machine's 1/tick budget.
    saturate! = (sub) -> begin
        for i in 1:64
            st = sub.sites[i]
            st.commit_sign = Int8(1)              # tag aligned with the load
            st.plastic_since = Int32(10)          # fresh melt at tick 10
            tl = sub.telemetry[i]
            tl.consecutive_stable = Int32(2)      # settle certificate saturated
            tl.stress_ema = 0.05f0                # melt margin holds
            tl.signed_stress_ema = 0.05f0         # direction agrees with tag
        end
    end
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    g = fill(0.01f0, 64)
    regime = RegimeAdaptiveController(2; budgeted=false)

    # Young tick (11, tip 0): every site is remittable AND unbudgeted —
    # the frozen-contract-style batch commit TAGR would produce.
    sub = mksub(); saturate!(sub)
    r = reference_material_tick!(sub, g, NEWTONIAN, regime, ZCS();
        beta=0.5f0, gamma=0.5f0, tick=11)
    @test count(a -> a isa CommitAction, r.actions) == 64
    @test check_invariants(sub)

    # The same state under the phase machine: at tick 11 BOTH PHASE gates
    # refuse — the sites melted at tick 10 have plastic age 1 < k_commit = 2
    # (dwell), and the budget would admit only one anyway. Zero commits:
    # these are exactly the two gates the young window lifts.
    sub = mksub(); saturate!(sub)
    rp11 = reference_material_tick!(sub, g, NEWTONIAN, PHASE_MACHINE_CONTROLLER, ZCS();
        beta=0.5f0, gamma=0.5f0, tick=11)
    @test count(a -> a isa CommitAction, rp11.actions) == 0

    # One tick later (age 2): dwell satisfied, the 1/tick budget admits one.
    sub = mksub(); saturate!(sub)
    rp12 = reference_material_tick!(sub, g, NEWTONIAN, PHASE_MACHINE_CONTROLLER, ZCS();
        beta=0.5f0, gamma=0.5f0, tick=12)
    @test count(a -> a isa CommitAction, rp12.actions) == 1

    # And under TAGR itself: identical count to unbudgeted-young REGIME.
    sub = mksub(); saturate!(sub)
    rt = reference_material_tick!(sub, g, NEWTONIAN, TAG_ROUTING_CONTROLLER, ZCS();
        beta=0.5f0, gamma=0.5f0, tick=11)
    @test count(a -> a isa CommitAction, rt.actions) == 64

    # Deep tick (16, tip 5): the budget is back — at most one commit even
    # though every site's dwell is long satisfied.
    sub = mksub(); saturate!(sub)
    rd = reference_material_tick!(sub, g, NEWTONIAN, regime, ZCS();
        beta=0.5f0, gamma=0.5f0, tick=16)
    @test count(a -> a isa CommitAction, rd.actions) == 1
    @test check_invariants(sub)
end

@testset "E0e — REGIME end-to-end determinism with declared phase length" begin
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    mk_state = (m) -> initialize_material_training(m, initialize_fp_seed(N;
        region_size=64, settle_down=0.0f0, eta=1.0f0,
        hardening_increment=0.05f0, epsilon_delta=1.0f6,
        k_yield=2, k_settle=2, phase_length=8))

    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=REGIME_ADAPTIVE_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
        phase_length=8,
    )

    X = Float32[1 -1; 1 -1]
    Y = Float32[1 -1]

    mlp1 = mlp
    mlp2 = deepcopy(mlp)
    st1 = mk_state(mlp1)
    st2 = mk_state(mlp2)

    for _ in 1:40
        material_training_step!(mlp1, st1, X, Y, cfg)
    end
    for _ in 1:40
        material_training_step!(mlp2, st2, X, Y, cfg)
    end

    fp1 = [_tpm_bits(Float32(x)) for x in vec(mlp1.H_FP32)]
    fp2 = [_tpm_bits(Float32(x)) for x in vec(mlp2.H_FP32)]
    @test fp1 == fp2
    @test check_invariants(st1, mlp1)
    @test check_invariants(st2, mlp2)
end

# ---------------------------------------------------------------------------
# E0f — melt-side routing (Pass 3c).
#
# Contracts under test:
#   1. The melt lever: young-window conflict certificates fire at k_eff = 1;
#      deep-window pace is the phase machine's (conflict_k). Direction
#      condition, floor, and melt budget are untouched.
#   2. The commit side is EXACTLY the phase machine's in both windows (dwell,
#      no remission) and shares the 1/tick commit budget — any behavioral
#      difference is melt-side by construction.
#   3. Undeclared phase length is a HardFailure (no silent degeneration).
#   4. End-to-end determinism with the melt lever in the loop.
# ---------------------------------------------------------------------------
@testset "E0f — MeltRoutingController construction" begin
    @test MeltRoutingController(2).k_commit == Int32(2)
    @test MeltRoutingController(2).young_fraction == 0.5f0
    @test MeltRoutingController(2; young_fraction=1.0).young_fraction == 1.0f0
    @test_throws ErrorException MeltRoutingController(0)
    @test_throws ErrorException MeltRoutingController(2; young_fraction=0.0)
    @test_throws ErrorException MeltRoutingController(2; young_fraction=1.5)
end

@testset "E0f — young melt acceleration; deep pace is the phase machine's" begin
    mksub = () -> initialize_fp_consolidated_substrate(64; region_size=64,
        initial_weights=fill(0.5f0, 64), conflict_k=2, phase_length=10)
    mk = (tick, counter) -> begin
        s = mksub()
        site = s.sites[1]
        site.commit_sign = Int8(1)          # consolidated under positive load
        site.commit_stress = 0.5f0
        site.consolidation_tick = Int32(5)
        t = s.telemetry[1]
        t.stress_ema = 0.6f0
        t.signed_stress_ema = -0.6f0        # sustained consistent OPPOSED load
        t.consecutive_conflicted = Int32(counter)
        return (s, create_snapshot(1, s.region_map.regions[1], site, t, true, tick))
    end

    # Young window (tip 0 at tick 11): one accrued opposed tick melts NOW.
    s, snap = mk(11, 1)
    a = decide(MELT_ROUTING_CONTROLLER, snap)
    @test a isa MeltAction && a.site_index == Int32(1)
    # The phase machine on the SAME state: counter 1 < conflict_k = 2 — spares.
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction

    # Deep window (tip 5 at tick 16): the pace is the phase machine's.
    s, snap = mk(16, 1)
    @test decide(MELT_ROUTING_CONTROLLER, snap) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    s, snap = mk(16, 2)
    @test action_code(decide(MELT_ROUTING_CONTROLLER, snap)) ==
          action_code(decide(PHASE_MACHINE_CONTROLLER, snap))
    @test decide(MELT_ROUTING_CONTROLLER, snap) isa MeltAction

    # Accelerate-everywhere ablation (young_fraction = 1.0): k_eff = 1 at any
    # position — the same deep state melts immediately.
    everywhere = MeltRoutingController(2; young_fraction=1.0)
    s, snap = mk(16, 1)
    @test decide(everywhere, snap) isa MeltAction

    # The melt budget gate and the certificate requirement are untouched:
    # without a consolidation reference the site can never be invalidated.
    s = mksub()
    s.sites[1].commit_sign = Int8(0)
    s.telemetry[1].consecutive_conflicted = Int32(9)
    snap = create_snapshot(1, s.region_map.regions[1], s.sites[1],
        s.telemetry[1], true, 11)
    @test decide(MELT_ROUTING_CONTROLLER, snap) isa NoAction
    # ...and with the melt budget exhausted, no melt either.
    s, snap = mk(11, 1)
    snap = create_snapshot(1, s.region_map.regions[1], s.sites[1],
        s.telemetry[1], false, 11)
    @test decide(MELT_ROUTING_CONTROLLER, snap) isa NoAction
end

@testset "E0f — kernel: young certificate melts one tick early" begin
    # Live accrual through reference_material_tick!: opposed load (g = -0.6,
    # beta = 0 re-derives the EMA exactly) accrues one conflicted tick per
    # tick. MROUTE (young) melts on the FIRST; the phase machine on the SECOND.
    # The consolidated initializer builds sites WITHOUT a consolidation
    # reference (commit_sign = 0 — the certificate can never fire on it), so
    # the reference is stamped by hand exactly as in the E0c committed-side
    # fixture above.
    mksub = () -> begin
        s = initialize_fp_consolidated_substrate(64; region_size=64,
            initial_weights=fill(0.5f0, 64), conflict_k=2, phase_length=10)
        site1 = s.sites[1]
        site1.commit_sign = Int8(1)
        site1.commit_stress = 0.5f0
        site1.consolidation_tick = Int32(5)
        s
    end
    g = fill(-0.6f0, 64)

    mroute = mksub()
    r = reference_material_tick!(mroute, g, NEWTONIAN, MELT_ROUTING_CONTROLLER,
        RampedVPS(2); beta=0.0f0, gamma=0.0f0, tick=11)
    @test any(a -> a isa MeltAction && a.site_index == Int32(1), r.actions)
    @test mroute.sites[1].superplastic

    phase = mksub()
    r1 = reference_material_tick!(phase, g, NEWTONIAN, PHASE_MACHINE_CONTROLLER,
        RampedVPS(2); beta=0.0f0, gamma=0.0f0, tick=11)
    @test !any(a -> a isa MeltAction, r1.actions)
    @test !phase.sites[1].superplastic
    r2 = reference_material_tick!(phase, g, NEWTONIAN, PHASE_MACHINE_CONTROLLER,
        RampedVPS(2); beta=0.0f0, gamma=0.0f0, tick=12)
    @test any(a -> a isa MeltAction && a.site_index == Int32(1), r2.actions)
    @test check_invariants(mroute)
    @test check_invariants(phase)
end

@testset "E0f — commit side is the phase machine's in both windows" begin
    # Fresh melt DEEP in the phase (age 1 < k_commit): MROUTE refuses exactly
    # like the phase machine — no remission even though the tag is aligned —
    # while the E0e remission arms would commit.
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    mk = (tick, plastic_since) -> begin
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)
        st.plastic_since = Int32(plastic_since)
        t = s.telemetry[1]
        t.consecutive_stable = Int32(2)
        t.stress_ema = 0.05f0
        t.signed_stress_ema = 0.05f0
        return (s, create_snapshot(1, s.region_map.regions[1], st, t, true, tick))
    end
    s, snap = mk(16, 15)                    # tip 5 deep, plastic age 1
    @test decide(MELT_ROUTING_CONTROLLER, snap) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    @test decide(REGIME_ADAPTIVE_CONTROLLER, snap) isa NoAction   # deep: dwell too
    @test decide(TAG_ROUTING_CONTROLLER, snap) isa CommitAction   # the contrast
    # Age 2: commit fires, identical to the phase machine's.
    s, snap = mk(17, 15)
    @test action_code(decide(MELT_ROUTING_CONTROLLER, snap)) ==
          action_code(decide(PHASE_MACHINE_CONTROLLER, snap))
    @test decide(MELT_ROUTING_CONTROLLER, snap) isa CommitAction

    # Budget membership: on an all-settle seed (no committed sites, so the
    # melt lever is unreachable) MROUTE and PHASE produce identical action
    # streams — same sites admitted per tick under the 1/tick budget.
    g = fill(0.01f0, 64)
    prints = Dict{Symbol,Vector{Vector{Tuple{Symbol,Int32}}}}()
    for (name, dcp) in ((:phase, PHASE_MACHINE_CONTROLLER),
                        (:mroute, MELT_ROUTING_CONTROLLER))
        sub = mksub()
        prints[name] = Vector{Tuple{Symbol,Int32}}[]
        for tick in 1:4
            r = reference_material_tick!(sub, g, NEWTONIAN, dcp, ZCS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            push!(prints[name], action_code.(r.actions))
        end
        @test check_invariants(sub)
    end
    @test prints[:mroute] == prints[:phase]
end

@testset "E0f — undeclared phase length is a HardFailure for MROUTE" begin
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)   # no phase_length declared
    st = sub.sites[1]
    st.commit_sign = Int8(1)
    st.plastic_since = Int32(10)
    snap = create_snapshot(1, sub.region_map.regions[1], st,
        sub.telemetry[1], true, 11)
    @test_throws ErrorException decide(MELT_ROUTING_CONTROLLER, snap)
    # Committed-side lever also requires the declaration.
    csub = initialize_fp_consolidated_substrate(64; region_size=64)
    csnap = create_snapshot(1, csub.region_map.regions[1], csub.sites[1],
        csub.telemetry[1], true, 11)
    @test_throws ErrorException decide(MELT_ROUTING_CONTROLLER, csnap)
    # The phase machine is unaffected on the same snapshots.
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, csnap) isa NoAction
end

@testset "E0f — MROUTE end-to-end determinism with declared phase length" begin
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    mk_state = (m) -> initialize_material_training(m, initialize_fp_seed(N;
        region_size=64, settle_down=0.0f0, eta=1.0f0,
        hardening_increment=0.05f0, epsilon_delta=1.0f6,
        k_yield=2, k_settle=2, phase_length=8))

    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=MELT_ROUTING_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
        phase_length=8,
    )

    X = Float32[1 -1; 1 -1]
    Y = Float32[1 -1]

    mlp1 = mlp
    mlp2 = deepcopy(mlp)
    st1 = mk_state(mlp1)
    st2 = mk_state(mlp2)

    for _ in 1:40
        material_training_step!(mlp1, st1, X, Y, cfg)
    end
    for _ in 1:40
        material_training_step!(mlp2, st2, X, Y, cfg)
    end

    fp1 = [_tpm_bits(Float32(x)) for x in vec(mlp1.H_FP32)]
    fp2 = [_tpm_bits(Float32(x)) for x in vec(mlp2.H_FP32)]
    @test fp1 == fp2
    @test check_invariants(st1, mlp1)
    @test check_invariants(st2, mlp2)
end

# ---------------------------------------------------------------------------
# E0g — per-phase commit budget (Pass 3d).
#
# Contracts under test:
#   1. Construction: quota_fraction ∈ (0, 1], HardFailure otherwise.
#   2. The commit decision is EXACTLY the phase machine's (settle + dwell +
#      melt margin, NO remission) in both windows; the melt side too. Any
#      behavioral difference comes from the kernel's budget shape.
#   3. Undeclared phase length is a HardFailure — at decide() AND in the
#      kernel's budget block (no silent degeneration).
#   4. Kernel quota: exhaustion mid-phase and refill at the phase boundary on
#      the live all-settle fixture (settle accrues live; tick 1 admits 0).
#      Per-tick admission stays <= 1 (the E0b2 wave stays impossible).
#   5. The spent-quota counter is derived from LIVE consolidation stamps in
#      ((p−1)L, tick]: commits stamp, melts zero, previous-phase stamps do
#      not consume this phase's quota. No controller memory.
#   6. An unbound quota is behaviorally the phase machine (same sites, same
#      ticks).
#   7. End-to-end determinism with the quota binding in the loop.
#
# Fixture gotchas (E0c/E0e/E0f, carried forward): consolidated initializers
# build commit_sign = 0, so the certificate can NEVER fire until the commit
# reference is hand-stamped; settle counters accrue live, so tick 1 of a
# fresh seed commits 0 (k_settle = 2 reached on tick 2); plastic age is
# tick − plastic_since, not position in phase.
# ---------------------------------------------------------------------------
@testset "E0g — PhaseQuotaController construction" begin
    @test PhaseQuotaController(2).k_commit == Int32(2)
    @test PhaseQuotaController(2).quota_fraction == 0.5f0
    @test PhaseQuotaController(2; quota_fraction=1.0).quota_fraction == 1.0f0
    @test_throws ErrorException PhaseQuotaController(0)
    @test_throws ErrorException PhaseQuotaController(2; quota_fraction=0.0)
    @test_throws ErrorException PhaseQuotaController(2; quota_fraction=1.5)
end

@testset "E0g — commit and melt decisions are the phase machine's" begin
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    mk = (tick, plastic_since) -> begin
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)             # aligned tag: remission arms would fire
        st.plastic_since = Int32(plastic_since)
        t = s.telemetry[1]
        t.consecutive_stable = Int32(2)
        t.stress_ema = 0.05f0
        t.signed_stress_ema = 0.05f0
        return (s, create_snapshot(1, s.region_map.regions[1], st, t, true, tick))
    end
    # Young window, plastic age 1 < k_commit: refused — the QUOTA rule carries
    # NO remission (only the budget shape differs from the phase machine).
    s, snap = mk(11, 10)
    @test decide(PHASE_QUOTA_CONTROLLER, snap) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    @test decide(TAG_ROUTING_CONTROLLER, snap) isa CommitAction   # the contrast
    # Age 2: fires, identical to the phase machine.
    s, snap = mk(12, 10)
    @test action_code(decide(PHASE_QUOTA_CONTROLLER, snap)) ==
          action_code(decide(PHASE_MACHINE_CONTROLLER, snap))
    @test decide(PHASE_QUOTA_CONTROLLER, snap) isa CommitAction

    # Committed side: certificate + melt budget exactly the phase machine's.
    # (Hand-stamp the reference: consolidated fixtures carry commit_sign = 0.)
    mkc = () -> begin
        s = initialize_fp_consolidated_substrate(64; region_size=64,
            initial_weights=fill(0.5f0, 64), conflict_k=2, phase_length=10)
        site = s.sites[1]
        site.commit_sign = Int8(1)
        site.commit_stress = 0.5f0
        site.consolidation_tick = Int32(5)
        t = s.telemetry[1]
        t.stress_ema = 0.6f0
        t.signed_stress_ema = -0.6f0        # sustained consistent OPPOSED load
        t.consecutive_conflicted = Int32(2)
        return (s, create_snapshot(1, s.region_map.regions[1], site, t, true, 11))
    end
    s, snap = mkc()
    @test decide(PHASE_QUOTA_CONTROLLER, snap) isa MeltAction
    # Melt budget exhausted: no melt either.
    s, snap = mkc()
    snap = create_snapshot(1, s.region_map.regions[1], s.sites[1],
        s.telemetry[1], false, 11)
    @test decide(PHASE_QUOTA_CONTROLLER, snap) isa NoAction
end

@testset "E0g — undeclared phase length is a HardFailure for QUOTA" begin
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)   # no phase_length declared
    st = sub.sites[1]
    st.commit_sign = Int8(1)
    st.plastic_since = Int32(10)
    snap = create_snapshot(1, sub.region_map.regions[1], st,
        sub.telemetry[1], true, 11)
    @test_throws ErrorException decide(PHASE_QUOTA_CONTROLLER, snap)
    # The kernel's budget block needs the window too — it must fail BEFORE any
    # site is decided, on the same undeclared substrate.
    @test_throws ErrorException reference_material_tick!(sub, fill(0.01f0, 64),
        NEWTONIAN, PHASE_QUOTA_CONTROLLER, ZCS(); beta=0.5f0, gamma=0.5f0, tick=11)
    # The phase machine is unaffected on the same state.
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
end

@testset "E0g — kernel quota exhausts and refills at the phase boundary" begin
    # All-settle seed under a small consistent load: settle accrues live, so
    # tick 1 admits 0 and ticks 2+ admit at the budget's pace. With
    # quota_fraction = 1/4 on L = 16, Q = 4: the quota binds at tick 6, refills
    # at tick 17. Admission stays <= 1 per tick throughout (E0b2 impossible).
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=16)
    g = fill(0.01f0, 64)
    quota = PhaseQuotaController(2; quota_fraction=0.25)
    sub = mk()
    counts = Int[]
    for tick in 1:32
        r = reference_material_tick!(sub, g, NEWTONIAN, quota, ZCS();
            beta=0.5f0, gamma=0.5f0, tick=tick)
        push!(counts, count(a -> a isa CommitAction, r.actions))
    end
    @test all(<=(1), counts)                                   # pacing preserved
    @test counts[1:16] == [0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    @test counts[17:32] == [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    @test sum(counts) == 8                                     # Q = 4 spent per phase
    @test check_invariants(sub)

    # The ONLY difference from the phase machine is the quota binding: through
    # tick 5 the admissions are identical; at tick 6 the spent quota (4) blocks
    # what the phase machine still admits.
    phsub = mk()
    ph = Int[]
    for tick in 1:6
        r = reference_material_tick!(phsub, g, NEWTONIAN, PHASE_MACHINE_CONTROLLER,
            ZCS(); beta=0.5f0, gamma=0.5f0, tick=tick)
        push!(ph, count(a -> a isa CommitAction, r.actions))
    end
    @test ph == [0, 1, 1, 1, 1, 1]
    @test counts[1:6] == [0, 1, 1, 1, 1, 0]
end

@testset "E0g — quota counts live stamps in the current phase window" begin
    # The spent-quota counter derives from consolidation stamps in
    # ((p−1)L, tick]: a commit hand-stamped in the PREVIOUS phase must not
    # consume this phase's quota. (Hand-convert a seed site to committed:
    # release its hot slot — a freed site owning an allocated pool slot is an
    # invariant HardFailure — then stamp.)
    mk = (stamp) -> begin
        s = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
            epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
        st = s.sites[1]
        release!(s.pool, st.hot_handle)
        st.hot_handle = Int32(0)
        st.superplastic = false
        st.phase = :committed
        st.commit_sign = Int8(1)
        st.commit_stress = 0.05f0
        st.consolidation_tick = Int32(stamp)
        st.plastic_since = Int32(0)
        s
    end
    g = fill(0.01f0, 64)
    quota = PhaseQuotaController(2; quota_fraction=0.2)   # Q = 2 at L = 10
    run = (s, ticks) -> begin
        counts = Int[]
        for tick in ticks
            r = reference_material_tick!(s, g, NEWTONIAN, quota, ZCS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            push!(counts, count(a -> a isa CommitAction, r.actions))
        end
        counts
    end
    # Stamp INSIDE the current phase (tick 11 ∈ (10, 20]): one unit already
    # spent → after live settle accrual, exactly one commit (tick 12), then
    # the quota blocks tick 13.
    @test run(mk(11), 11:13) == [0, 1, 0]
    # The same stamp in the PREVIOUS phase (tick 8 ∈ (0, 10]): quota full →
    # two commits (ticks 12 and 13). Settlement accrual is identical, so the
    # difference is purely the stamp window.
    @test run(mk(8), 11:13) == [0, 1, 1]
end

@testset "E0g — unbound quota is behaviorally the phase machine" begin
    # quota_fraction = 1.0 on L = 16 gives Q = 16, far above what six ticks can
    # spend at 1/tick: identical action streams — same sites, same ticks.
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=16)
    g = fill(0.01f0, 64)
    prints = Dict{Symbol,Vector{Vector{Tuple{Symbol,Int32}}}}()
    for (name, dcp) in ((:phase, PHASE_MACHINE_CONTROLLER),
                        (:quota, PhaseQuotaController(2; quota_fraction=1.0)))
        sub = mk()
        prints[name] = Vector{Tuple{Symbol,Int32}}[]
        for tick in 1:6
            r = reference_material_tick!(sub, g, NEWTONIAN, dcp, ZCS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            push!(prints[name], action_code.(r.actions))
        end
        @test check_invariants(sub)
    end
    @test prints[:quota] == prints[:phase]
end

@testset "E0g — QUOTA end-to-end determinism with declared phase length" begin
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    mk_state = (m) -> initialize_material_training(m, initialize_fp_seed(N;
        region_size=64, settle_down=0.0f0, eta=1.0f0,
        hardening_increment=0.05f0, epsilon_delta=1.0f6,
        k_yield=2, k_settle=2, phase_length=8))

    # Default quota_fraction = 0.5 → Q = 4 per 8-tick phase: the quota BINDS.
    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=PHASE_QUOTA_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
        phase_length=8,
    )

    X = Float32[1 -1; 1 -1]
    Y = Float32[1 -1]

    mlp1 = mlp
    mlp2 = deepcopy(mlp)
    st1 = mk_state(mlp1)
    st2 = mk_state(mlp2)

    for _ in 1:40
        material_training_step!(mlp1, st1, X, Y, cfg)
    end
    for _ in 1:40
        material_training_step!(mlp2, st2, X, Y, cfg)
    end

    fp1 = [_tpm_bits(Float32(x)) for x in vec(mlp1.H_FP32)]
    fp2 = [_tpm_bits(Float32(x)) for x in vec(mlp2.H_FP32)]
    @test fp1 == fp2
    @test check_invariants(st1, mlp1)
    @test check_invariants(st2, mlp2)
end

# ---------------------------------------------------------------------------
# E0h — burst-width commit allowance (Pass 3e).
#
# Contracts under test:
#   1. Construction: burst_fraction ∈ (0, 1], HardFailure otherwise.
#   2. The commit decision is EXACTLY the phase machine's (settle + dwell +
#      melt margin, NO remission) and the melt side too — the burst cap lives
#      entirely in the kernel's budget shape.
#   3. Kernel burst drain: the cap admits the leading intent sites in
#      canonical order; denied sites keep their counters and re-intend. On
#      the all-settle fixture the burst drains geometrically
#      [32, 16, 8, 4, 2, 1, 1] — bounded-rate, never the E0b2 uncontrolled
#      wave (per-tick admission is capped at ceil-of-half the burst).
#   4. The single-intent floor: a lone intending site is admitted even when
#      floor(burst_fraction · 1) = 0 (the floor alone would strand it).
#   5. burst_fraction = 1.0 is batch admission bounded by the intent count —
#      byte-identical to the frozen FixedRuleController on a settling seed
#      ("TAGR minus remission" shape).
#   6. Position-blind: no phase_length declaration is required (contrast
#      QUOTA/REGIME HardFailures) and none changes the budget.
#   7. End-to-end determinism with the burst cap in the loop.
#
# Fixture gotchas (carried forward): the all-settle seed commits 0 on tick 1
# (settle accrues live, k_settle = 2 reached on tick 2); budget denial keeps
# counters, so denied sites re-intend on the next tick.
# ---------------------------------------------------------------------------
@testset "E0h — BurstCommitController construction" begin
    @test BurstCommitController(2).k_commit == Int32(2)
    @test BurstCommitController(2).burst_fraction == 0.5f0
    @test BurstCommitController(2; burst_fraction=1.0).burst_fraction == 1.0f0
    @test_throws ErrorException BurstCommitController(0)
    @test_throws ErrorException BurstCommitController(2; burst_fraction=0.0)
    @test_throws ErrorException BurstCommitController(2; burst_fraction=1.5)
    @test_throws ErrorException BurstCommitController(2; burst_fraction=NaN)
end

@testset "E0h — commit and melt decisions are the phase machine's" begin
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    mk = (tick, plastic_since) -> begin
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)             # aligned tag: remission arms would fire
        st.plastic_since = Int32(plastic_since)
        t = s.telemetry[1]
        t.consecutive_stable = Int32(2)
        t.stress_ema = 0.05f0
        t.signed_stress_ema = 0.05f0
        return (s, create_snapshot(1, s.region_map.regions[1], st, t, true, tick))
    end
    # Young window, plastic age 1 < k_commit: refused — BURST carries NO
    # remission (only the budget shape differs from the phase machine).
    s, snap = mk(11, 10)
    @test decide(BURST_COMMIT_CONTROLLER, snap) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    @test decide(TAG_ROUTING_CONTROLLER, snap) isa CommitAction   # the contrast
    # Age 2: fires, identical to the phase machine.
    s, snap = mk(12, 10)
    @test action_code(decide(BURST_COMMIT_CONTROLLER, snap)) ==
          action_code(decide(PHASE_MACHINE_CONTROLLER, snap))
    @test decide(BURST_COMMIT_CONTROLLER, snap) isa CommitAction

    # Committed side: certificate + melt budget exactly the phase machine's
    # (hand-stamp the reference: consolidated fixtures carry commit_sign = 0).
    mkc = () -> begin
        s = initialize_fp_consolidated_substrate(64; region_size=64,
            initial_weights=fill(0.5f0, 64), conflict_k=2, phase_length=10)
        site = s.sites[1]
        site.commit_sign = Int8(1)
        site.commit_stress = 0.5f0
        site.consolidation_tick = Int32(5)
        t = s.telemetry[1]
        t.stress_ema = 0.6f0
        t.signed_stress_ema = -0.6f0        # sustained consistent OPPOSED load
        t.consecutive_conflicted = Int32(2)
        return (s, create_snapshot(1, s.region_map.regions[1], site, t, true, 11))
    end
    s, snap = mkc()
    @test decide(BURST_COMMIT_CONTROLLER, snap) isa MeltAction
    s, snap = mkc()
    snap = create_snapshot(1, s.region_map.regions[1], s.sites[1],
        s.telemetry[1], false, 11)
    @test decide(BURST_COMMIT_CONTROLLER, snap) isa NoAction
end

@testset "E0h — kernel burst drains geometrically in canonical order" begin
    # All-settle seed under a small consistent load: on tick 2 every site
    # intends (W = 64), so BURST(0.5) admits 32, then 16, 8, 4, 2, 1, 1 —
    # the burst drains geometrically and every admitted site had intended.
    # PHASE admits the same stream at 1/tick; the leading sites coincide.
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=16)
    g = fill(0.01f0, 64)
    sub = mk()
    counts = Int[]
    first_tick2_commits = Int32[]
    for tick in 1:8
        r = reference_material_tick!(sub, g, NEWTONIAN, BURST_COMMIT_CONTROLLER,
            ZCS(); beta=0.5f0, gamma=0.5f0, tick=tick)
        push!(counts, count(a -> a isa CommitAction, r.actions))
        tick == 2 &&
            (first_tick2_commits = [a.site_index for a in r.actions if a isa CommitAction])
    end
    @test counts == [0, 32, 16, 8, 4, 2, 1, 1]      # geometric drain
    @test first_tick2_commits == Int32.(1:32)       # canonical order, leading cap
    @test sum(counts) == 64
    @test all(counts .<= 32)                        # bounded-rate, not the E0b2 wave
    @test check_invariants(sub)

    # The phase machine on the same fixture: 1/tick, same leading sites.
    phsub = mk()
    ph = Int[]
    for tick in 1:6
        r = reference_material_tick!(phsub, g, NEWTONIAN, PHASE_MACHINE_CONTROLLER,
            ZCS(); beta=0.5f0, gamma=0.5f0, tick=tick)
        push!(ph, count(a -> a isa CommitAction, r.actions))
    end
    @test ph == [0, 1, 1, 1, 1, 1]
    @test sum(counts[1:6]) >= 3 * sum(ph)           # the drain lifts the rate
end

@testset "E0h — single-intent floor admits a lone intending site" begin
    # Site 1's certificate is saturated and its load is EXACT zero (certifies
    # immediately); every other site sees alternating ±2e6 load, which NEVER
    # certifies: the first sample is inconsistent against the zero-seed EMA
    # (|2e6 − 0| > epsilon_delta = 1e6) and every later sample breaks
    # consistency again (|Δg| = 4e6). So the tick-1 burst has W = 1 and
    # floor(0.5 · 1) = 0 — without the max(1, ·) floor the lone intending
    # site would be stranded forever (its counters persist, but no later
    # burst ever forms under this load). It must be admitted at tick 1;
    # afterwards nobody else ever certifies, so the run goes silent —
    # proving W = 1 was the only intent.
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=16)
    t1 = sub.telemetry[1]
    t1.consecutive_stable = Int32(2)
    r1 = reference_material_tick!(sub, vcat(0.0f0, fill(2.0f6, 63)), NEWTONIAN,
        BURST_COMMIT_CONTROLLER, ZCS(); beta=0.5f0, gamma=0.5f0, tick=1)
    @test count(a -> a isa CommitAction, r1.actions) == 1
    @test r1.actions[1] isa CommitAction && r1.actions[1].site_index == Int32(1)
    r2 = reference_material_tick!(sub, vcat(0.0f0, fill(-2.0f6, 63)), NEWTONIAN,
        BURST_COMMIT_CONTROLLER, ZCS(); beta=0.5f0, gamma=0.5f0, tick=2)
    @test count(a -> a isa CommitAction, r2.actions) == 0
    r3 = reference_material_tick!(sub, vcat(0.0f0, fill(2.0f6, 63)), NEWTONIAN,
        BURST_COMMIT_CONTROLLER, ZCS(); beta=0.5f0, gamma=0.5f0, tick=3)
    @test count(a -> a isa CommitAction, r3.actions) == 0
    @test check_invariants(sub)
end

@testset "E0h — burst_fraction 1.0 is the frozen batch shape (TAGR minus remission)" begin
    # On a settling seed the unbounded burst admits every intent site in one
    # tick — byte-identical action streams to the FixedRuleController's frozen
    # batch-commit contract. This isolates E0d mechanism A: the ADMISSION
    # SHAPE, without any dwell remission.
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=16)
    g = fill(0.01f0, 64)
    prints = Dict{Symbol,Vector{Vector{Tuple{Symbol,Int32}}}}()
    for (name, dcp) in ((:burst, BurstCommitController(2; burst_fraction=1.0)),
                        (:fixed, FIXED_RULE_CONTROLLER))
        sub = mk()
        prints[name] = Vector{Tuple{Symbol,Int32}}[]
        for tick in 1:4
            r = reference_material_tick!(sub, g, NEWTONIAN, dcp, ZCS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            push!(prints[name], action_code.(r.actions))
        end
        @test check_invariants(sub)
    end
    @test prints[:burst] == prints[:fixed]
end

@testset "E0h — burst budget is position-blind (undeclared L is legal)" begin
    # No phase_length declared anywhere: QUOTA and REGIME HardFail here, the
    # burst arm cannot — its cap never consults the declaration.
    sub = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)   # no phase_length kwarg
    g = fill(0.01f0, 64)
    counts = Int[]
    for tick in 1:4
        r = reference_material_tick!(sub, g, NEWTONIAN, BURST_COMMIT_CONTROLLER,
            ZCS(); beta=0.5f0, gamma=0.5f0, tick=tick)
        push!(counts, count(a -> a isa CommitAction, r.actions))
    end
    @test counts == [0, 32, 16, 8]
    @test check_invariants(sub)
end

@testset "E0h — BURST end-to-end determinism with declared phase length" begin
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    mk_state = (m) -> initialize_material_training(m, initialize_fp_seed(N;
        region_size=64, settle_down=0.0f0, eta=1.0f0,
        hardening_increment=0.05f0, epsilon_delta=1.0f6,
        k_yield=2, k_settle=2, phase_length=8))

    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=BURST_COMMIT_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
        phase_length=8,
    )

    X = Float32[1 -1; 1 -1]
    Y = Float32[1 -1]

    mlp1 = mlp
    mlp2 = deepcopy(mlp)
    st1 = mk_state(mlp1)
    st2 = mk_state(mlp2)

    for _ in 1:40
        material_training_step!(mlp1, st1, X, Y, cfg)
    end
    for _ in 1:40
        material_training_step!(mlp2, st2, X, Y, cfg)
    end

    fp1 = [_tpm_bits(Float32(x)) for x in vec(mlp1.H_FP32)]
    fp2 = [_tpm_bits(Float32(x)) for x in vec(mlp2.H_FP32)]
    @test fp1 == fp2
    @test check_invariants(st1, mlp1)
    @test check_invariants(st2, mlp2)
end

# ---------------------------------------------------------------------------
# E0i — burst-within-quota composite budget (Pass 3f).
#
# Contracts under test:
#   1. Construction: both fractions validated in (0, 1], HardFailure otherwise.
#   2. The commit decision is EXACTLY the phase machine's (settle + dwell +
#      melt margin, NO remission) and the melt side too; position-gated
#      (undeclared L is a HardFailure, like QUOTA).
#   3. The composite cap is min(burst allowance, remaining quota) — the quota
#      bounds the FIRST tick of a burst (the E0b2 wave is impossible), and
#      whichever constraint is tighter binds.
#   4. Exhaustion and refill: the live-stamp quota admits at most Q commits
#      per phase and refills at the boundary.
#   5. End-to-end determinism with the composite budget in the loop.
#
# Fixture gotchas (carried forward): settle accrues live (tick 1 commits 0,
# k_settle = 2 reached on tick 2); budget denial keeps counters.
# ---------------------------------------------------------------------------
@testset "E0i — BurstQuotaController construction" begin
    @test BurstQuotaController(2).k_commit == Int32(2)
    @test BurstQuotaController(2).burst_fraction == 1.0f0
    @test BurstQuotaController(2).quota_fraction == 0.5f0
    @test BurstQuotaController(2; burst_fraction=0.5, quota_fraction=0.25).burst_fraction == 0.5f0
    @test BurstQuotaController(2; burst_fraction=0.5, quota_fraction=0.25).quota_fraction == 0.25f0
    @test_throws ErrorException BurstQuotaController(0)
    @test_throws ErrorException BurstQuotaController(2; burst_fraction=0.0)
    @test_throws ErrorException BurstQuotaController(2; quota_fraction=0.0)
    @test_throws ErrorException BurstQuotaController(2; quota_fraction=1.5)
end

@testset "E0i — commit and melt decisions are the phase machine's; undeclared L fails" begin
    mksub = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=10)
    mk = (tick, plastic_since) -> begin
        s = mksub()
        st = s.sites[1]
        st.commit_sign = Int8(1)             # aligned tag: remission arms would fire
        st.plastic_since = Int32(plastic_since)
        t = s.telemetry[1]
        t.consecutive_stable = Int32(2)
        t.stress_ema = 0.05f0
        t.signed_stress_ema = 0.05f0
        return (s, create_snapshot(1, s.region_map.regions[1], st, t, true, tick))
    end
    # Young window, plastic age 1 < k_commit: refused — the composite carries
    # NO remission (only the budget shape differs from the phase machine).
    s, snap = mk(11, 10)
    @test decide(BURST_QUOTA_CONTROLLER, snap) isa NoAction
    @test decide(PHASE_MACHINE_CONTROLLER, snap) isa NoAction
    @test decide(TAG_ROUTING_CONTROLLER, snap) isa CommitAction   # the contrast
    # Age 2: fires, identical to the phase machine.
    s, snap = mk(12, 10)
    @test action_code(decide(BURST_QUOTA_CONTROLLER, snap)) ==
          action_code(decide(PHASE_MACHINE_CONTROLLER, snap))
    @test decide(BURST_QUOTA_CONTROLLER, snap) isa CommitAction

    # Committed side: certificate + melt budget exactly the phase machine's
    # (hand-stamp the reference: consolidated fixtures carry commit_sign = 0).
    mkc = () -> begin
        s = initialize_fp_consolidated_substrate(64; region_size=64,
            initial_weights=fill(0.5f0, 64), conflict_k=2, phase_length=10)
        site = s.sites[1]
        site.commit_sign = Int8(1)
        site.commit_stress = 0.5f0
        site.consolidation_tick = Int32(5)
        t = s.telemetry[1]
        t.stress_ema = 0.6f0
        t.signed_stress_ema = -0.6f0        # sustained consistent OPPOSED load
        t.consecutive_conflicted = Int32(2)
        return (s, create_snapshot(1, s.region_map.regions[1], site, t, true, 11))
    end
    s, snap = mkc()
    @test decide(BURST_QUOTA_CONTROLLER, snap) isa MeltAction

    # Undeclared L: HardFailure at decide AND in the kernel's budget block.
    free = initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2)   # no phase_length declared
    fst = free.sites[1]
    fst.commit_sign = Int8(1)
    fst.plastic_since = Int32(10)
    fsnap = create_snapshot(1, free.region_map.regions[1], fst,
        free.telemetry[1], true, 11)
    @test_throws ErrorException decide(BURST_QUOTA_CONTROLLER, fsnap)
    @test_throws ErrorException reference_material_tick!(free, fill(0.01f0, 64),
        NEWTONIAN, BURST_QUOTA_CONTROLLER, ZCS(); beta=0.5f0, gamma=0.5f0, tick=11)
    # The phase machine is unaffected on the same state.
    @test decide(PHASE_MACHINE_CONTROLLER, fsnap) isa NoAction
end

@testset "E0i — composite quota bounds the first burst tick and refills" begin
    # All-settle seed (W = 64 at tick 2) under Q = 8 (L = 16, qf = 0.5):
    # the composite must admit min(burst cap, remaining) — 8, NOT the E0b2
    # 64-wave — then sit closed until the phase boundary refills it.
    # burst_fraction = 1.0 is the STRONGER form: even the full batch admits
    # only the remaining quota; bf = 0.5 gives burst cap 32, still above 8,
    # so BOTH fractions must produce the same quota-bound pattern.
    mk = () -> initialize_fp_seed(64; region_size=64, settle_down=0.0f0,
        epsilon_delta=1.0f6, k_yield=2, k_settle=2, phase_length=16)
    g = fill(0.01f0, 64)
    for (name, dcp) in ((:bq_full, BurstQuotaController(2; burst_fraction=1.0)),
                        (:bq_half, BurstQuotaController(2; burst_fraction=0.5)))
        sub = mk()
        counts = Int[]
        for tick in 1:18
            r = reference_material_tick!(sub, g, NEWTONIAN, dcp, ZCS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            push!(counts, count(a -> a isa CommitAction, r.actions))
        end
        @test counts == [0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0]
        @test all(counts .<= 8)                    # never above the quota
        @test check_invariants(sub)
    end

    # When the burst cap is TIGHTER than the quota, the burst binds instead:
    # bf = 0.1 on W = 64 → floor(6.4) = 6 < 8; tick 3 runs on the remaining 2.
    sub = mk()
    counts = Int[]
    for tick in 1:4
        r = reference_material_tick!(sub, g, NEWTONIAN,
            BurstQuotaController(2; burst_fraction=0.1), ZCS();
            beta=0.5f0, gamma=0.5f0, tick=tick)
        push!(counts, count(a -> a isa CommitAction, r.actions))
    end
    @test counts == [0, 6, 2, 0]               # burst binds, then remaining
end

@testset "E0i — BQ end-to-end determinism with declared phase length" begin
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    mk_state = (m) -> initialize_material_training(m, initialize_fp_seed(N;
        region_size=64, settle_down=0.0f0, eta=1.0f0,
        hardening_increment=0.05f0, epsilon_delta=1.0f6,
        k_yield=2, k_settle=2, phase_length=8))

    # Defaults (bf = 1.0, qf = 0.5): Q = 4 per 8-tick phase — the quota BINDS
    # against full-batch demand.
    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=BURST_QUOTA_CONTROLLER,
        policy=RampedVPS(2),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.0f0,
        gamma=0.0f0,
        phase_length=8,
    )

    X = Float32[1 -1; 1 -1]
    Y = Float32[1 -1]

    mlp1 = mlp
    mlp2 = deepcopy(mlp)
    st1 = mk_state(mlp1)
    st2 = mk_state(mlp2)

    for _ in 1:40
        material_training_step!(mlp1, st1, X, Y, cfg)
    end
    for _ in 1:40
        material_training_step!(mlp2, st2, X, Y, cfg)
    end

    fp1 = [_tpm_bits(Float32(x)) for x in vec(mlp1.H_FP32)]
    fp2 = [_tpm_bits(Float32(x)) for x in vec(mlp2.H_FP32)]
    @test fp1 == fp2
    @test check_invariants(st1, mlp1)
    @test check_invariants(st2, mlp2)
end
