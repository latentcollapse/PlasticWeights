"""
    PlasticWeights Test Suite

Runs all Stage-0 tests: S0, S1, S1b, S2, S3, S3b

This is the main test entry point for Pkg.test()
"""

using Test
using PlasticWeights
using Random

@testset "PlasticWeights Stage-0" begin

    @testset "S0: Core Sanity Tests" begin
        # SiteState construction
        site = SiteState(0)
        @test site.q == 0
        @test !site.allocated
        @test !site.superplastic
        @test site.hot_handle == 0
        
        site_pos = SiteState(1)
        @test site_pos.q == 1
        
        site_neg = SiteState(-1)
        @test site_neg.q == -1
        
        # Invalid q should fail
        @test_throws ErrorException SiteState(2)
        @test_throws ErrorException SiteState(-2)
        
        # HotPool basic operations
        pool = HotPool(10)
        @test num_allocated(pool) == 0
        @test available_count(pool) == 10
        
        handle = allocate!(pool)
        @test handle > 0
        @test handle <= 10
        @test num_allocated(pool) == 1
        @test is_valid_handle(pool, handle)
        
        release!(pool, handle)
        @test num_allocated(pool) == 0
        @test available_count(pool) == 10
        
        # RegionMap construction
        region_map = RegionMap(64, 8)
        @test length(region_map.regions) == 8
        @test region_map.region_size == 8
        @test region_map.num_sites == 64
        
        # Check deterministic mapping
        for i in 1:64
            region_id = get_region_id(region_map, i)
            @test 1 <= region_id <= 8
        end
    end
    
    @testset "S0: Exposure Exhaustive Tests" begin
        # Vacant sites (!allocated) - expose 0 for both ZCS and VPS
        vacant_neg = SiteState(-1, false, false, 0)
        vacant_zero = SiteState(0, false, false, 0)
        vacant_pos = SiteState(1, false, false, 0)
        
        @test exposure(vacant_neg, ZCS()) == 0
        @test exposure(vacant_zero, ZCS()) == 0
        @test exposure(vacant_pos, ZCS()) == 0
        
        @test exposure(vacant_neg, VPS()) == 0
        @test exposure(vacant_zero, VPS()) == 0
        @test exposure(vacant_pos, VPS()) == 0
        
        # Consolidated sites (allocated && !superplastic) - expose q
        consol_neg = SiteState(-1, true, false, 0)
        consol_zero = SiteState(0, true, false, 0)
        consol_pos = SiteState(1, true, false, 0)
        
        @test exposure(consol_neg, ZCS()) == -1
        @test exposure(consol_zero, ZCS()) == 0
        @test exposure(consol_pos, ZCS()) == 1
        
        @test exposure(consol_neg, VPS()) == -1
        @test exposure(consol_zero, VPS()) == 0
        @test exposure(consol_pos, VPS()) == 1
        
        # Superplastic sites (allocated && superplastic)
        # ZCS exposes 0, VPS exposes site.q (prior committed q preserved during melt)
        super_neg = SiteState(-1, true, true, 1)
        super_zero = SiteState(0, true, true, 2)
        super_pos = SiteState(1, true, true, 3)
        
        @test exposure(super_neg, ZCS()) == 0
        @test exposure(super_zero, ZCS()) == 0
        @test exposure(super_pos, ZCS()) == 0
        
        # VPS superplastic exposes site.q (the prior committed q)
        @test exposure(super_neg, VPS()) == -1
        @test exposure(super_zero, VPS()) == 0
        @test exposure(super_pos, VPS()) == 1
        
        # NO ±2 state exists
        @test !(exposure(super_pos, ZCS()) == 2)
        @test !(exposure(super_pos, VPS()) == 2)
    end
    
    @testset "S0: HotPool Invariants" begin
        pool = HotPool(5)
        @test check_invariants(pool)
        
        # Allocate all
        handles = [allocate!(pool) for _ in 1:5]
        @test check_invariants(pool)
        @test num_allocated(pool) == 5
        @test available_count(pool) == 0
        @test sort(handles) == [1, 2, 3, 4, 5]  # deterministic allocation order
        
        # Exhaustion
        @test_throws ErrorException allocate!(pool)
        
        # Release some
        release!(pool, handles[1])
        @test check_invariants(pool)
        @test num_allocated(pool) == 4
        @test available_count(pool) == 1
        
        # Double release should fail
        @test_throws ErrorException release!(pool, handles[1])
        
        # Invalid handle should fail
        @test_throws ErrorException release!(pool, 0)
        @test_throws ErrorException release!(pool, 100)
        
        # Residual set/get
        h = allocate!(pool)
        set_residual!(pool, h, 3.14f0)
        @test get_residual(pool, h) == 3.14f0
        
        # free + allocated == capacity
        @test available_count(pool) + num_allocated(pool) == 5
    end
    
    @testset "S1: Newtonian Constitutive Law" begin
        region = RegionState(1, [1, 2, 3]; eta=2.0f0)
        telemetry = SiteTelemetry()
        
        g = 4.0f0
        delta_delta = response(NEWTONIAN, region, telemetry, g)
        
        # Newtonian: Δδ = -g / η = -4.0 / 2.0 = -2.0
        @test delta_delta ≈ -2.0f0 atol=1e-6
    end
    
    @testset "S1: Bingham-Inspired Constitutive Law" begin
        region = RegionState(1, [1, 2, 3]; yield_up=0.5f0, eta=1.0f0)
        telemetry_low = SiteTelemetry(0.1f0)  # low stress
        telemetry_high = SiteTelemetry(1.0f0)  # high stress
        
        g = 1.0f0
        
        # Low stress: m = max(0, 1 - 0.5/(0.1 + ε)) ≈ 0
        delta_low = response(BINGHAM_INSPIRED, region, telemetry_low, g)
        @test abs(delta_low) < 1e-5  # nearly zero
        
        # High stress: m = max(0, 1 - 0.5/(1.0 + ε)) ≈ 0.5
        delta_high = response(BINGHAM_INSPIRED, region, telemetry_high, g)
        expected_m = 1.0f0 - 0.5f0 / (1.0f0 + 1e-6f0)
        expected_delta = -g * expected_m
        @test delta_high ≈ expected_delta atol=1e-5
    end
    
    @testset "S1b: Loss-Scale Covariance" begin
        k = 2.5f0  # scale factor
        
        # Base setup
        region_base = RegionState(1, [1, 2, 3]; 
                                  yield_up=0.5f0, settle_down=0.3f0, 
                                  eta=1.0f0, hardening_increment=0.05f0,
                                  epsilon_delta=0.1f0, k_yield=3, k_settle=3)
        
        # Scaled setup: (k*tau, k*epsilon, k*eta)
        region_scaled = RegionState(1, [1, 2, 3]; 
                                    yield_up=k * 0.5f0,
                                    settle_down=k * 0.3f0,
                                    eta=k * 1.0f0,
                                    hardening_increment=k * 0.05f0,
                                    epsilon_delta=k * 0.1f0,
                                    k_yield=3, k_settle=3)
        
        telemetry_base = SiteTelemetry(0.5f0, 0.1f0, 0, 0)
        telemetry_scaled = SiteTelemetry(k * 0.5f0, k * 0.1f0, 0, 0)
        
        g = 0.3f0
        
        # Newtonian response should be identical (scale cancels)
        delta_base = response(NEWTONIAN, region_base, telemetry_base, g)
        delta_scaled = response(NEWTONIAN, region_scaled, telemetry_scaled, k * g)
        @test delta_base ≈ delta_scaled atol=1e-6
        
        # Bingham-inspired response should be identical (ratios preserved)
        delta_b_base = response(BINGHAM_INSPIRED, region_base, telemetry_base, g)
        delta_b_scaled = response(BINGHAM_INSPIRED, region_scaled, telemetry_scaled, k * g)
        @test delta_b_base ≈ delta_b_scaled atol=1e-6
    end
    
    @testset "S2: Stage-0 Seed State" begin
        # Material sites begin allocated and superplastic with q=0
        # HotPool provides exactly one valid hot slot per superplastic site
        
        pool = HotPool(10)
        sites = [SiteState(0, true, true, 0) for _ in 1:10]
        telemetry = [SiteTelemetry() for _ in 1:10]
        
        # Allocate hot slots for all superplastic sites
        for i in 1:10
            handle = allocate!(pool)
            sites[i].hot_handle = handle
        end
        
        # Verify seed state
        for i in 1:10
            @test sites[i].q == 0
            @test sites[i].allocated == true
            @test sites[i].superplastic == true
            @test sites[i].hot_handle > 0
            @test telemetry[i].stress_ema == 0.0f0
            @test telemetry[i].residual_motion_ema == 0.0f0
        end
        
        @test check_invariants(pool) == true
    end
    
    @testset "S3: DCP Snapshot and Decision Rules" begin
        # DCP receives only immutable typed snapshot
        # It does NOT decide from raw residual magnitude
        
        region = RegionState(1, [1]; k_yield=3, k_settle=2, epsilon_delta=0.1f0)
        pool = HotPool(5)
        
        # Test MELT decision: consolidated site with sustained above-yield
        site_consolidated = SiteState(1, true, false, 0)
        telemetry_melt = SiteTelemetry(0.6f0, 0.05f0, 3, 0)  # consecutive_above_yield >= k_yield
        
        snap_melt = create_snapshot(1, region, site_consolidated, telemetry_melt, true, 1)
        action = decide(FIXED_RULE_CONTROLLER, snap_melt)
        @test action isa MeltAction
        
        # No hot capacity -> no melt
        snap_no_capacity = create_snapshot(1, region, site_consolidated, telemetry_melt, false, 1)
        action = decide(FIXED_RULE_CONTROLLER, snap_no_capacity)
        @test action isa NoAction
        
        # Test COMMIT decision: superplastic site with sustained stable
        site_super = SiteState(0, true, true, 1)
        telemetry_commit = SiteTelemetry(0.2f0, 0.05f0, 0, 2)  # consecutive_stable >= k_settle
        
        snap_commit = create_snapshot(1, region, site_super, telemetry_commit, true, 1)
        action = decide(FIXED_RULE_CONTROLLER, snap_commit)
        @test action isa CommitAction
        
        # Not enough stability -> HOLD
        telemetry_hold = SiteTelemetry(0.2f0, 0.05f0, 0, 1)  # consecutive_stable < k_settle
        snap_hold = create_snapshot(1, region, site_super, telemetry_hold, true, 1)
        action = decide(FIXED_RULE_CONTROLLER, snap_hold)
        @test action isa NoAction
    end
    
    @testset "S3b: Bitwise Trajectory Identity" begin
        function run_trajectory(seed::UInt32, num_ticks::Int)
            rng = Xoshiro(seed)
            pool = HotPool(5)
            sites = [SiteState(0, true, true, 0) for _ in 1:5]
            telemetry = [SiteTelemetry() for _ in 1:5]
            region = RegionState(1, [1, 2, 3, 4, 5])
            
            # Allocate handles
            for i in 1:5
                handle = allocate!(pool)
                sites[i].hot_handle = handle
            end
            
            trajectory = Float32[]
            
            for tick in 1:num_ticks
                # Deterministic gradient
                g = rand(rng) * 0.5f0
                
                # Compute response for first site
                delta = response(NEWTONIAN, region, telemetry[1], g)
                
                push!(trajectory, delta)
            end
            
            return trajectory
        end
        
        # Run twice with same seed
        traj1 = run_trajectory(42, 10)
        traj2 = run_trajectory(42, 10)
        
        # Must be bitwise identical
        @test traj1 == traj2
        
        # Different seed should give different trajectory
        traj3 = run_trajectory(43, 10)
        @test traj1 != traj3
    end
end

println("All Stage-0 tests passed!")
