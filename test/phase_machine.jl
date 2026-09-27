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
