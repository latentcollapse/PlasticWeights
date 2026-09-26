using Test
using PlasticWeights
using Random

_fp_bits(x::Float32) = reinterpret(UInt32, x)

function _fp_substrate_fingerprint(s::SubstrateState{FPSiteState})
    sites = Tuple((_fp_bits(site.w), site.allocated, site.superplastic, site.hot_handle)
                  for site in s.sites)
    telemetry = Tuple((_fp_bits(t.stress_ema), _fp_bits(t.residual_motion_ema),
        t.consecutive_above_yield, t.consecutive_stable)
                      for t in s.telemetry)
    regions = Tuple((r.id, Tuple(r.site_indices), r.region_size,
        _fp_bits(r.yield_up), _fp_bits(r.settle_down), _fp_bits(r.eta),
        _fp_bits(r.hardening_increment), _fp_bits(r.epsilon_delta),
        r.k_yield, r.k_settle)
                    for r in s.region_map.regions)
    pool = (Tuple(_fp_bits(x) for x in s.pool.residuals),
        Tuple(s.pool.free_list), Tuple(s.pool.allocated), s.pool.capacity)
    return (sites=sites, telemetry=telemetry, regions=regions, pool=pool,
        max_superplastic=s.max_superplastic)
end

@testset "Continuous FP Viscoplastic Substrate" begin

    @testset "S0-FP — continuous site invariants and substrate construction" begin
        # Arbitrary continuous weights are permitted
        for w in (-3.14159f0, -0.732f0, 0.0f0, 0.42f0, 2.71828f0)
            site = FPSiteState(w, true, false, 0)
            @test site.w === Float32(w)
            @test site.allocated
            @test !site.superplastic
            @test site.hot_handle == 0
            @test check_invariants(site)
        end

        # Structural violations are rejected
        @test_throws ErrorException FPSiteState(NaN32, true, false, 0)
        @test_throws ErrorException FPSiteState(Inf32, true, false, 0)
        @test_throws ErrorException FPSiteState(0.5f0, false, true, 1)  # vacant superplastic
        @test_throws ErrorException FPSiteState(0.5f0, true, true, 0)   # superplastic missing handle
        @test_throws ErrorException FPSiteState(0.5f0, true, false, 1)  # consolidated owns handle
        @test_throws ErrorException FPSiteState(0.5f0, true, false, -1) # negative handle

        # Substrate seed initialization
        init_w = Float32[0.1 * i for i in 1:64]
        seed = initialize_fp_seed(64; initial_weights=init_w, region_size=64)
        @test check_invariants(seed)
        @test length(seed.sites) == 64
        @test all(s -> s.allocated && s.superplastic, seed.sites)
        @test [s.w for s in seed.sites] == init_w
        @test num_allocated(seed.pool) == 64

        # Consolidated substrate initialization
        cons = initialize_fp_consolidated_substrate(64; initial_weights=init_w, region_size=64)
        @test check_invariants(cons)
        @test all(s -> s.allocated && !s.superplastic && s.hot_handle == 0, cons.sites)
        @test [s.w for s in cons.sites] == init_w
        @test num_allocated(cons.pool) == 0
    end

    @testset "S1-FP — continuous exposure semantics and lesion behavior" begin
        init_w = Float32[1.25f0, -0.65f0, 0.0f0, 3.5f0]
        pool = HotPool(4)
        h1 = allocate!(pool)
        h2 = allocate!(pool)

        sites = FPSiteState[
            FPSiteState(init_w[1], true, false, 0),   # consolidated
            FPSiteState(init_w[2], true, true, h1),   # superplastic
            FPSiteState(init_w[3], false, false, 0),  # vacant
            FPSiteState(init_w[4], true, true, h2),   # superplastic
        ]

        # ZCS: superplastic exposes 0.0f0; consolidated exposes full continuous w
        zcs_exp = exposure_snapshot(sites, ZCS())
        @test zcs_exp isa Vector{Float32}
        @test zcs_exp == Float32[1.25f0, 0.0f0, 0.0f0, 0.0f0]

        # VPS: superplastic retains prior continuous w; continuous execution continues smoothly
        vps_exp = exposure_snapshot(sites, VPS())
        @test vps_exp isa Vector{Float32}
        @test vps_exp == Float32[1.25f0, -0.65f0, 0.0f0, 3.5f0]

        # In continuous VPS, lesion size is zero by construction
        @test commit_base(sites[1], VPS()) === 1.25f0
        @test commit_base(sites[2], VPS()) === -0.65f0
        @test commit_base(sites[1], ZCS()) === 0.0f0
        @test commit_base(sites[2], ZCS()) === 0.0f0
    end

    @testset "S2-FP — Bingham-inspired yield law on continuous weights" begin
        substrate = initialize_fp_seed(64; region_size=64, yield_up=0.5f0, settle_down=0.25f0, eta=2.0f0)
        region = substrate.region_map.regions[1]
        telemetry = substrate.telemetry[1]

        law = BinghamInspired(1.0f-6)

        # 1. Stress below yield: mobility is identically 0.0f0
        telemetry.stress_ema = 0.3f0
        @test response(law, region, telemetry, 1.0f0) == 0.0f0
        @test response(law, region, telemetry, -5.0f0) == 0.0f0

        # 2. Stress above yield: Bingham plastic flow occurs
        telemetry.stress_ema = 1.0f0
        # mobility = max(0, 1 - 0.5 / 1.0) = 0.5
        # Δδ = -(g / eta) * mobility = -(1.0 / 2.0) * 0.5 = -0.25f0
        delta = response(law, region, telemetry, 1.0f0)
        @test isapprox(delta, -0.25f0; atol=1e-5)
    end

    @testset "S3-FP — zero quantization cycle loss and work-hardening" begin
        # Create a consolidated substrate with known continuous weights in region of 64 sites
        init_w = zeros(Float32, 64)
        init_w[1] = 0.37f0
        init_w[2] = -0.84f0
        substrate = initialize_fp_consolidated_substrate(64; initial_weights=init_w,
            region_size=64, yield_up=0.5f0, settle_down=0.25f0, eta=1.0f0,
            hardening_increment=0.1f0, epsilon_delta=0.01f0, k_yield=1, k_settle=1)

        recorder = DevelopmentalRecorder()

        # Tick 1: apply high stress -> triggers MELT on site 1
        g = zeros(Float32, 64)
        g[1] = -1.0f0
        r1 = reference_material_tick!(substrate, g, BinghamInspired(1e-6),
            FIXED_RULE_CONTROLLER, VPS();
            beta=0.0f0, gamma=0.0f0, tick=1, recorder=recorder)

        @test substrate.sites[1].superplastic
        @test substrate.sites[1].w === 0.37f0  # Prior w preserved
        @test substrate.sites[1].hot_handle != 0
        @test !substrate.sites[2].superplastic

        # Tick 2: site is superplastic, apply gradient to deform residual in HotPool
        # Injected residual: let's directly integrate a precise continuous value
        target_delta = 0.42857f0
        set_residual!(substrate.pool, substrate.sites[1].hot_handle, target_delta)
        # Settle conditions: set stress low and motion low
        substrate.telemetry[1].stress_ema = 0.01f0
        substrate.telemetry[1].residual_motion_ema = 0.001f0
        substrate.telemetry[1].consecutive_stable = 1  # satisfies k_settle=1

        initial_yield = substrate.region_map.regions[1].yield_up

        # Tick 3: DCP fires COMMIT
        r3 = reference_material_tick!(substrate, zeros(Float32, 64), BinghamInspired(1e-6),
            FIXED_RULE_CONTROLLER, VPS();
            beta=0.0f0, gamma=0.0f0, tick=3, recorder=recorder)

        # In continuous FP: new weight is EXACTLY prior_w + delta
        # Notice: in ternary, 0.37 + 0.42857 = 0.79857 would SNAP to 1.0 (error: 0.20143)
        # In continuous FP, there is ZERO quantization error!
        expected_w = 0.37f0 + target_delta
        @test !substrate.sites[1].superplastic
        @test substrate.sites[1].hot_handle == 0
        @test isapprox(substrate.sites[1].w, expected_w; atol=1e-6)

        # Work-hardening increment applied
        new_yield = substrate.region_map.regions[1].yield_up
        @test isapprox(new_yield, initial_yield + 0.1f0; atol=1e-6)

        # Verify telemetry recorded FP events faithfully
        summary = summarize_events(recorder)
        @test summary.melt_count == 1
        @test summary.commit_count == 1
        @test summary.commit_flip_count == 1
        @test isapprox(summary.total_hardening, 0.1; atol=1e-5)
    end

    @testset "S4-FP — bitwise deterministic trajectory replay" begin
        init_w = Float32[sin(Float32(i)) for i in 1:64]
        A = initialize_fp_consolidated_substrate(64; initial_weights=init_w,
            region_size=64, yield_up=0.5f0, settle_down=0.25f0, eta=1.0f0,
            hardening_increment=0.05f0, epsilon_delta=0.05f0, k_yield=2, k_settle=2)
        B = deepcopy(A)

        @test _fp_substrate_fingerprint(A) == _fp_substrate_fingerprint(B)

        gseq = Float32[1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1]
        trajectory_A = Any[]
        trajectory_B = Any[]

        for (tick, g1) in enumerate(gseq)
            g = zeros(Float32, 64)
            g[1] = g1
            ra = reference_material_tick!(A, g, BinghamInspired(0.125f0),
                FIXED_RULE_CONTROLLER, VPS();
                beta=0.5f0, gamma=0.5f0, tick=tick)
            rb = reference_material_tick!(B, copy(g), BinghamInspired(0.125f0),
                FIXED_RULE_CONTROLLER, VPS();
                beta=0.5f0, gamma=0.5f0, tick=tick)

            push!(trajectory_A, (state=_fp_substrate_fingerprint(A),
                actions=Tuple(action_code(a) for a in ra.actions),
                exposure=Tuple(ra.exposures),
                delta=Tuple(_fp_bits(x) for x in ra.delta_updates)))
            push!(trajectory_B, (state=_fp_substrate_fingerprint(B),
                actions=Tuple(action_code(a) for a in rb.actions),
                exposure=Tuple(rb.exposures),
                delta=Tuple(_fp_bits(x) for x in rb.delta_updates)))
        end

        @test trajectory_A == trajectory_B
    end

    @testset "S5-FP — End-to-end continuous FP learning without ternary cycle loss" begin
        # 2-input, 32-hidden, 1-output MLP -> 2 * 32 = 64 material sites
        mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=61)
        N = num_material_sites(mlp)
        @test N == 64

        # Fast-commit continuous FP substrate:
        # High settle_down and epsilon_delta allow the seed to commit after k_settle ticks,
        # consolidating continuous residuals into W_material and exposing them to the head.
        substrate = initialize_fp_seed(N; region_size=64,
            yield_up=100.0f0, settle_down=50.0f0, eta=0.01f0,
            hardening_increment=0.05f0, epsilon_delta=1.0f6,
            k_yield=2, k_settle=2)

        state = initialize_material_training(mlp, substrate)
        recorder = DevelopmentalRecorder()

        X = Float32[
            1 -1
            1 -1
        ]
        Y = Float32[
            1 -1
        ]

        prediction0 = material_predict(mlp, state, X, VPS())
        initial_loss = 0.5f0 * sum(abs2, prediction0 .- Y) / length(Y)

        cfg = MaterialTrainingConfig(
            law=NEWTONIAN,
            dcp=FIXED_RULE_CONTROLLER,
            policy=VPS(),
            head=AdamConfig(learning_rate=0.02f0),
            beta=0.0f0,
            gamma=0.0f0,
        )

        for _ in 1:200
            material_training_step!(mlp, state, X, Y, cfg; recorder=recorder)
        end

        prediction1 = material_predict(mlp, state, X, VPS())
        final_loss = 0.5f0 * sum(abs2, prediction1 .- Y) / length(Y)

        # Continuous FP learning smoothly converges
        @test final_loss < initial_loss
        @test final_loss < 0.25f0 * initial_loss
        @test prediction1[1, 1] > 0.0f0
        @test prediction1[1, 2] < 0.0f0
        @test check_invariants(state, mlp)
        @test length(recorder) > 0
        @test any(!iszero, [s.w for s in state.substrate.sites])
    end
end
