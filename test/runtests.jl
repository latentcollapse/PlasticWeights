using Test
using PlasticWeights

bits(x::Float32) = reinterpret(UInt32, x)

function action_fingerprint(actions)
    return Tuple(action_code(a) for a in actions)
end

function substrate_fingerprint(s::SubstrateState)
    sites = Tuple((site.q, site.allocated, site.superplastic, site.hot_handle)
                  for site in s.sites)
    telemetry = Tuple((bits(t.stress_ema), bits(t.residual_motion_ema),
                       t.consecutive_above_yield, t.consecutive_stable)
                      for t in s.telemetry)
    regions = Tuple((r.id, Tuple(r.site_indices), r.region_size,
                     bits(r.yield_up), bits(r.settle_down), bits(r.eta),
                     bits(r.hardening_increment), bits(r.epsilon_delta),
                     r.k_yield, r.k_settle)
                    for r in s.region_map.regions)
    pool = (Tuple(bits(x) for x in s.pool.residuals),
            Tuple(s.pool.free_list), Tuple(s.pool.allocated), s.pool.capacity)
    return (sites=sites, telemetry=telemetry, regions=regions, pool=pool,
            max_superplastic=s.max_superplastic)
end

# S3 explicitly partitions current causal state into X_op and the one retained
# history variable M_hist=yield_up. Everything except that designated history
# variable is canonicalized before subsequent load is applied.
function xop_fingerprint_without_yield(s::SubstrateState)
    sites = Tuple((site.q, site.allocated, site.superplastic, site.hot_handle,
                   site.superplastic ? bits(get_residual(s.pool, site.hot_handle)) : nothing)
                  for site in s.sites)
    telemetry = Tuple((bits(t.stress_ema), bits(t.residual_motion_ema),
                       t.consecutive_above_yield, t.consecutive_stable)
                      for t in s.telemetry)
    region_nonhistory = Tuple((r.id, Tuple(r.site_indices), r.region_size,
                               bits(r.settle_down), bits(r.eta),
                               bits(r.hardening_increment), bits(r.epsilon_delta),
                               r.k_yield, r.k_settle)
                              for r in s.region_map.regions)
    pool = (Tuple(bits(x) for x in s.pool.residuals),
            Tuple(s.pool.free_list), Tuple(s.pool.allocated), s.pool.capacity)
    return (sites=sites, telemetry=telemetry,
            region_nonhistory=region_nonhistory, pool=pool,
            max_superplastic=s.max_superplastic)
end

@testset "PlasticWeights v0.1.0 deterministic reference kernel" begin
    @testset "S0 — quantizer, exposure, storage invariants" begin
        # Exact ternary boundaries: ±0.5 map to zero.
        @test ternary_round(-0.5001f0) == -1
        @test ternary_round(-0.5f0) == 0
        @test ternary_round(0.0f0) == 0
        @test ternary_round(0.5f0) == 0
        @test ternary_round(0.5001f0) == 1

        # Vacant and consolidated exposure matrix.
        for q in (-1, 0, 1)
            vacant = SiteState(q, false, false, 0)
            consolidated = SiteState(q, true, false, 0)
            @test exposure(vacant, ZCS()) == 0
            @test exposure(vacant, VPS()) == 0
            @test exposure(consolidated, ZCS()) == q
            @test exposure(consolidated, VPS()) == q
        end

        # Superplastic: ZCS abstains, VPS preserves prior committed q.
        for (q, handle) in zip((-1, 0, 1), (1, 2, 3))
            site = SiteState(q, true, true, handle)
            @test exposure(site, ZCS()) == 0
            @test exposure(site, VPS()) == q
            @test exposure(site, VPS()) in (-1, 0, 1)  # never an amplified ±2 state
        end

        # Structurally invalid site states are rejected at construction.
        @test_throws ErrorException SiteState(2)
        @test_throws ErrorException SiteState(0, true, true, 0)
        @test_throws ErrorException SiteState(0, true, false, 1)
        @test_throws ErrorException SiteState(0, false, true, 1)

        pool = HotPool(3)
        @test check_invariants(pool)
        h1, h2, h3 = allocate!(pool), allocate!(pool), allocate!(pool)
        @test (h1, h2, h3) == (Int32(1), Int32(2), Int32(3))
        @test_throws ErrorException allocate!(pool)
        set_residual!(pool, h2, 0.25f0)
        @test get_residual(pool, h2) === 0.25f0
        release!(pool, h2)
        @test_throws ErrorException release!(pool, h2)
        @test allocate!(pool) == h2  # deterministic LIFO reuse
        @test check_invariants(pool)

        region_map = RegionMap(128, 64)
        @test length(region_map.regions) == 2
        @test get_region_id(region_map, 1) == 1
        @test get_region_id(region_map, 64) == 1
        @test get_region_id(region_map, 65) == 2
        @test get_region_id(region_map, 128) == 2
        @test check_invariants(region_map)
        @test_throws ErrorException RegionMap(64, 32)

        seed = initialize_stage0_seed(64; region_size=64)
        @test check_invariants(seed)
        @test num_allocated(seed.pool) == 64
        @test all(site -> site.q == 0 && site.allocated && site.superplastic &&
                          is_valid_handle(seed.pool, site.hot_handle), seed.sites)
        @test all(site -> get_residual(seed.pool, site.hot_handle) === 0.0f0, seed.sites)
    end

    @testset "S0 — DCP and atomic lifecycle semantics" begin
        substrate = initialize_consolidated_substrate(64; region_size=64, q=1,
            yield_up=0.5f0, settle_down=0.25f0, hardening_increment=0.125f0,
            k_yield=2, k_settle=2)
        initial_yield = substrate.region_map.regions[1].yield_up

        snap = Snapshot(1, 1, true, false, 0.75f0, 0.0f0, 2, 0,
                        0.5f0, 0.25f0, 2, 2, 0.05f0, true, 7)
        a1 = decide(FIXED_RULE_CONTROLLER, snap)
        a2 = decide(FixedRuleController(), snap)
        @test action_code(a1) == (:melt, Int32(1))
        @test action_code(a1) == action_code(a2)  # stateless replay

        apply_action!(substrate, a1, ZCS())
        @test substrate.sites[1].q == 1  # melt preserves prior q
        @test substrate.sites[1].superplastic
        @test get_residual(substrate.pool, substrate.sites[1].hot_handle) === 0.0f0

        set_residual!(substrate.pool, substrate.sites[1].hot_handle, -0.6f0)
        apply_action!(substrate, CommitAction(Int32(1)), ZCS())
        @test substrate.sites[1].q == -1  # ZCS base 0 + (-0.6)
        @test !substrate.sites[1].superplastic
        @test substrate.sites[1].hot_handle == 0
        @test substrate.region_map.regions[1].yield_up == initial_yield + 0.125f0
        @test check_invariants(substrate)

        # VPS uses prior q as its commit base.
        vps = initialize_consolidated_substrate(64; region_size=64, q=1)
        apply_action!(vps, MeltAction(Int32(1)), VPS())
        set_residual!(vps.pool, vps.sites[1].hot_handle, -0.6f0)
        apply_action!(vps, CommitAction(Int32(1)), VPS())
        @test vps.sites[1].q == 0  # 1 + (-0.6) = 0.4 -> zero

        # Budget is part of declared operative state and is a hard gate.
        budgeted = initialize_consolidated_substrate(64; region_size=64,
                                                     max_superplastic=1)
        apply_action!(budgeted, MeltAction(Int32(1)), ZCS())
        @test_throws ErrorException apply_action!(budgeted, MeltAction(Int32(2)), ZCS())
        @test check_invariants(budgeted)
    end

    @testset "S1 — Newtonian equivalence" begin
        region = RegionState(1, 1:64; yield_up=0.5f0, settle_down=0.25f0,
                             eta=2.0f0, hardening_increment=0.125f0)
        telemetry = SiteTelemetry()
        gradients = Float32[1.0, -0.5, 0.25, -1.5, 0.0, 0.75]
        delta_material = 0.0f0
        delta_sgd = 0.0f0
        lr = 0.5f0  # 1 / eta, exact power-of-two calibration

        for g in gradients
            dd = response(NEWTONIAN, region, telemetry, g)
            delta_material += dd
            delta_sgd -= lr * g
            @test delta_material === delta_sgd
        end
    end

    @testset "S1 — Bingham-inspired law sanity" begin
        region = RegionState(1, 1:64; yield_up=0.5f0, settle_down=0.25f0,
                             eta=1.0f0, hardening_increment=0.125f0)
        law = BinghamInspired(0.125f0)
        low = SiteTelemetry(0.25f0)
        high = SiteTelemetry(1.0f0)
        @test response(law, region, low, 1.0f0) === 0.0f0
        expected_m = 1.0f0 - 0.5f0 / 1.125f0
        @test response(law, region, high, 1.0f0) ≈ -expected_m atol=1.0f-6
    end

    @testset "S1b — loss-scale covariance" begin
        k = 2.0f0
        base = initialize_consolidated_substrate(64; region_size=64, q=1,
            yield_up=0.5f0, settle_down=0.25f0, eta=1.0f0,
            hardening_increment=0.125f0, epsilon_delta=0.05f0,
            k_yield=2, k_settle=2)
        scaled = initialize_consolidated_substrate(64; region_size=64, q=1,
            yield_up=1.0f0, settle_down=0.5f0, eta=2.0f0,
            hardening_increment=0.25f0,
            # residual-motion units are invariant under loss scaling
            epsilon_delta=0.05f0, k_yield=2, k_settle=2)
        law_base = BinghamInspired(0.125f0)
        law_scaled = BinghamInspired(0.25f0)

        # This sequence exercises HOLD -> MELT -> deformation -> COMMIT.
        gseq = Float32[1, 1, 1, 1, 0, 0, 0, 0, 0]
        saw_melt = false
        saw_commit = false

        for (tick, g) in enumerate(gseq)
            gb = zeros(Float32, 64); gb[1] = g
            gs = zeros(Float32, 64); gs[1] = k * g
            rb = reference_material_tick!(base, gb, law_base, FIXED_RULE_CONTROLLER, ZCS();
                                          beta=0.5f0, gamma=0.5f0, tick=tick)
            rs = reference_material_tick!(scaled, gs, law_scaled, FIXED_RULE_CONTROLLER, ZCS();
                                          beta=0.5f0, gamma=0.5f0, tick=tick)

            @test action_fingerprint(rb.actions) == action_fingerprint(rs.actions)
            @test Tuple(rb.exposures) == Tuple(rs.exposures)
            @test Tuple(bits(x) for x in rb.delta_updates) ==
                  Tuple(bits(x) for x in rs.delta_updates)
            saw_melt = saw_melt || any(a -> a isa MeltAction, rb.actions)
            saw_commit = saw_commit || any(a -> a isa CommitAction, rb.actions)

            # Lifecycle and latent residual trajectories are invariant.
            @test Tuple((s.q, s.allocated, s.superplastic, s.hot_handle) for s in base.sites) ==
                  Tuple((s.q, s.allocated, s.superplastic, s.hot_handle) for s in scaled.sites)
            @test Tuple(bits(x) for x in base.pool.residuals) ==
                  Tuple(bits(x) for x in scaled.pool.residuals)
            @test base.pool.allocated == scaled.pool.allocated
            @test base.pool.free_list == scaled.pool.free_list

            for i in eachindex(base.telemetry)
                tb, ts = base.telemetry[i], scaled.telemetry[i]
                @test ts.stress_ema === k * tb.stress_ema
                @test ts.residual_motion_ema === tb.residual_motion_ema
                @test ts.consecutive_above_yield == tb.consecutive_above_yield
                @test ts.consecutive_stable == tb.consecutive_stable
            end

            rbase = base.region_map.regions[1]
            rscaled = scaled.region_map.regions[1]
            @test rscaled.yield_up === k * rbase.yield_up
            @test rscaled.settle_down === k * rbase.settle_down
            @test rscaled.eta === k * rbase.eta
            @test rscaled.hardening_increment === k * rbase.hardening_increment
            @test rscaled.epsilon_delta === rbase.epsilon_delta
        end
        @test saw_melt
        @test saw_commit
    end

    @testset "S2 — seed local-learning island" begin
        mlp = Stage0MLP(4, 8, 2; feature_size=8, rng_seed=42)
        @test num_material_sites(mlp) == 64
        seed = initialize_stage0_seed(64; region_size=64)
        # These are the actual visible coefficients of the normative all-superplastic ZCS seed.
        exposures = material_exposures(seed.sites, ZCS())
        @test all(==(0.0f0), exposures)

        # Nondegenerate two-example batch.
        X = Float32[ 0.5  -0.4;
                     0.3   0.9;
                    -0.2   0.7;
                     0.8  -0.1]
        target = Float32[1.0 -0.25;
                        -0.5  0.75]
        b = backward_mse(mlp, X, exposures, target)

        @test all(==(0.0f0), b.forward.preactivation)
        @test all(==(0.0f0), b.forward.hidden)
        @test any(!=(0.0f0), b.grad_material)
        @test all(==(0.0f0), b.grad_features)
        @test all(==(0.0f0), b.grad_H)
        @test any(!=(0.0f0), b.grad_bias)
    end

    @testset "S3 — Twin-History mechanism isolation" begin
        A = initialize_consolidated_substrate(64; region_size=64, q=1,
            yield_up=0.5f0, settle_down=0.25f0, eta=1.0f0,
            hardening_increment=0.125f0, epsilon_delta=0.05f0,
            k_yield=2, k_settle=2)
        # Generate B's distinct history through real commits, then canonicalize
        # every non-history causal field by copying A and retaining only the
        # resulting historical yield. M_hist is *only* yield_up in this test.
        history_B = initialize_stage0_seed(64; region_size=64,
            yield_up=0.5f0, settle_down=0.25f0, eta=1.0f0,
            hardening_increment=0.125f0, epsilon_delta=0.05f0,
            k_yield=2, k_settle=2)
        for i in 1:3
            apply_action!(history_B, CommitAction(Int32(i)), ZCS())
        end
        historical_yield = history_B.region_map.regions[1].yield_up

        B = deepcopy(A)
        B.region_map.regions[1].yield_up = historical_yield
        @test A.region_map.regions[1].yield_up == 0.5f0
        @test B.region_map.regions[1].yield_up == 0.875f0
        @test xop_fingerprint_without_yield(A) == xop_fingerprint_without_yield(B)
        @test A.region_map.regions[1].yield_up != B.region_map.regions[1].yield_up

        # Identical predetermined signed load. With beta=.5 and g=1, stress is
        # .5, .75, .875. A obtains two strict-above-yield ticks and melts at t=3;
        # B does not cross its hardened .875 threshold.
        melt_A = nothing
        melt_B = nothing
        delta_A_tick4 = 0.0f0
        delta_B_tick4 = 0.0f0
        for tick in 1:4
            # The fourth load reverses sign. A has already melted, so the same
            # signed load now deforms its latent residual while B remains cold.
            signed_g = tick == 4 ? -1.0f0 : 1.0f0
            g = zeros(Float32, 64); g[1] = signed_g
            ra = reference_material_tick!(A, g, NEWTONIAN, FIXED_RULE_CONTROLLER, ZCS();
                                          beta=0.5f0, gamma=0.5f0, tick=tick)
            rb = reference_material_tick!(B, g, NEWTONIAN, FIXED_RULE_CONTROLLER, ZCS();
                                          beta=0.5f0, gamma=0.5f0, tick=tick)
            if melt_A === nothing && any(a -> a isa MeltAction && a.site_index == 1, ra.actions)
                melt_A = tick
            end
            if melt_B === nothing && any(a -> a isa MeltAction && a.site_index == 1, rb.actions)
                melt_B = tick
            end
            if tick == 4
                delta_A_tick4 = ra.delta_updates[1]
                delta_B_tick4 = rb.delta_updates[1]
            end
        end
        @test melt_A == 3
        @test melt_B === nothing
        @test A.sites[1].superplastic
        @test !B.sites[1].superplastic
        @test delta_A_tick4 == 1.0f0  # Newtonian -g/eta with g=-1, eta=1
        @test delta_B_tick4 == 0.0f0  # consolidated site has no hot residual to deform
    end

    @testset "S3b — equal-history bitwise trajectory identity" begin
        A = initialize_consolidated_substrate(64; region_size=64, q=1,
            yield_up=0.5f0, settle_down=0.25f0, eta=1.0f0,
            hardening_increment=0.125f0, epsilon_delta=0.05f0,
            k_yield=2, k_settle=2)
        B = deepcopy(A)
        @test substrate_fingerprint(A) == substrate_fingerprint(B)

        # Fixed sequence deliberately crosses melt and settle/commit boundaries.
        gseq = Float32[1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1]
        saw_lifecycle_event = false
        trajectory_A = Any[]
        trajectory_B = Any[]

        for (tick, g1) in enumerate(gseq)
            g = zeros(Float32, 64); g[1] = g1
            ra = reference_material_tick!(A, g, BinghamInspired(0.125f0),
                                          FIXED_RULE_CONTROLLER, ZCS();
                                          beta=0.5f0, gamma=0.5f0, tick=tick)
            rb = reference_material_tick!(B, copy(g), BinghamInspired(0.125f0),
                                          FIXED_RULE_CONTROLLER, ZCS();
                                          beta=0.5f0, gamma=0.5f0, tick=tick)
            saw_lifecycle_event = saw_lifecycle_event || any(a -> !(a isa NoAction), ra.actions)

            push!(trajectory_A, (state=substrate_fingerprint(A),
                                 actions=action_fingerprint(ra.actions),
                                 exposure=Tuple(ra.exposures),
                                 delta=Tuple(bits(x) for x in ra.delta_updates)))
            push!(trajectory_B, (state=substrate_fingerprint(B),
                                 actions=action_fingerprint(rb.actions),
                                 exposure=Tuple(rb.exposures),
                                 delta=Tuple(bits(x) for x in rb.delta_updates)))
        end

        @test saw_lifecycle_event
        @test trajectory_A == trajectory_B
    end
end
