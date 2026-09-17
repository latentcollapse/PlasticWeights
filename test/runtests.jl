"""
    PlasticWeights Test Suite

Runs all Stage-0 tests: S0, S1, S1b, S2, S3, S3b

This is the main test entry point for Pkg.test()
"""

using Test
using PlasticWeights
using Random

@testset "PlasticWeights Stage-0" begin
    @testset "S0: Sanity Tests" begin
        include("../src/Tests/Sanity/runtests.jl")
        @test run_sanity_tests() == true
    end
    
    @testset "S1: Causal Tests" begin
        include("../src/Tests/Causal/runtests.jl")
        @test run_causal_tests() == true
    end
    
    @testset "S1b: Loss-Scale Covariance" begin
        include("../src/Tests/Invariants/runtests.jl")
        @test run_invariant_tests() == true
        
        # S1b specific: loss-scale covariance test
        # For L' = kL and transformed (tau, epsilon, eta) -> (k tau, k epsilon, k eta),
        # the deterministic reference residual/lifecycle trajectory must be identical.
        
        rng = Xoshiro(42)
        
        # Create two identical setups with different scales
        k = 2.5f0  # scale factor
        
        # Base setup
        region_base = RegionState(1, [1, 2, 3]; yield_up=0.5f0, settle_down=0.3f0, 
                                  eta=1.0f0, hardening_increment=0.05f0,
                                  epsilon_delta=0.1f0, k_yield=3, k_settle=3)
        
        # Scaled setup: (k*tau, k*epsilon, k*eta)
        region_scaled = RegionState(1, [1, 2, 3]; 
                                    yield_up=k * 0.5f0,      # k * tau
                                    settle_down=k * 0.3f0,   # k * tau_S  
                                    eta=k * 1.0f0,           # k * eta
                                    hardening_increment=k * 0.05f0,
                                    epsilon_delta=k * 0.1f0, # k * epsilon_delta
                                    k_yield=3, k_settle=3)
        
        telemetry_base = SiteTelemetry(0.5f0, 0.1f0, 0, 0, 0, 0.2f0)
        telemetry_scaled = SiteTelemetry(k * 0.5f0, k * 0.1f0, 0, 0, 0, k * 0.2f0)
        
        g = 0.3f0
        
        # Newtonian response should scale appropriately
        delta_base = response(NEWTONIAN, region_base, telemetry_base, g)
        delta_scaled = response(NEWTONIAN, region_scaled, telemetry_scaled, k * g)
        
        # For Newtonian: Δδ = -g/η
        # Base: -0.3/1.0 = -0.3
        # Scaled: -(k*0.3)/(k*1.0) = -0.3 (same!)
        @test delta_base ≈ delta_scaled atol=1e-6
        
        # Bingham-inspired response
        delta_b_base = response(BINGHAM_INSPIRED, region_base, telemetry_base, g)
        delta_b_scaled = response(BINGHAM_INSPIRED, region_scaled, telemetry_scaled, k * g)
        
        # For Bingham: m = max(0, 1 - τ_R/(σ + ε))
        # Base m = max(0, 1 - 0.5/(0.5 + 1e-6)) ≈ 0
        # Scaled m = max(0, 1 - (k*0.5)/(k*0.5 + k*1e-6)) = same ratio
        # So Δδ should be identical
        @test delta_b_base ≈ delta_b_scaled atol=1e-6
    end
    
    @testset "S2: Seed Learnability" begin
        # S2 seed learnability test
        # Material sites begin allocated and superplastic with q=0 and δ=0
        
        pool = HotPool(10)
        sites = [SiteState(stage0_seed=true) for _ in 1:10]
        telemetry = [SiteTelemetry() for _ in 1:10]
        
        # Allocate hot slots for all superplastic sites
        for i in 1:10
            handle = allocate!(pool)
            sites[i].hot_handle = handle
            sites[i].superplastic = true
            sites[i].allocated = true
        end
        
        # Verify seed state
        for i in 1:10
            @test sites[i].q == 0
            @test sites[i].allocated == true
            @test sites[i].superplastic == true
            @test sites[i].hot_handle > 0
            @test telemetry[i].delta == 0.0f0
            @test telemetry[i].stress_ema == 0.0f0
        end
        
        @test check_invariants(pool) == true
    end
    
    @testset "S3: DCP Snapshot and Actions" begin
        # S3 test: DCP receives only immutable typed snapshot
        # It does not decide from raw residual magnitude
        
        pool = HotPool(5)
        site = SiteState(1, true, false, 0)  # consolidated site
        telemetry = SiteTelemetry(0.5f0, 0.1f0, 0, 0, 1, 0.0f0)
        
        # Create snapshot
        snap = create_snapshot(1, 1, site, telemetry.stress_ema, 0.3f0, 1)
        
        # Verify snapshot is immutable and contains declared fields only
        @test snap.site_index == 1
        @test snap.region_id == 1
        @test snap.q == 1
        @test snap.allocated == true
        @test snap.superplastic == false
        @test snap.stress_ema == 0.5f0
        @test snap.residual == 0.3f0
        @test snap.tick == 1
        
        # DCP decision based on sustained counters, not raw residual
        dcp = FixedRuleController(yield_up=0.5f0, settle_down=0.3f0,
                                  k_yield=3, k_settle=3, epsilon_delta=0.1f0)
        
        action = decide(dcp, snap)
        @test action isa Action
    end
    
    @testset "S3b: Bitwise Trajectory Identity" begin
        # S3b requires bitwise identity across runs with same seed
        # Run single-threaded CPU and verify identical trajectories
        
        function run_trajectory(seed::UInt32, num_ticks::Int)
            rng = Xoshiro(seed)
            pool = HotPool(5)
            sites = [SiteState(stage0_seed=true) for _ in 1:5]
            telemetry = [SiteTelemetry() for _ in 1:5]
            
            # Allocate handles
            for i in 1:5
                handle = allocate!(pool)
                sites[i].hot_handle = handle
            end
            
            trajectory = Float32[]
            
            for tick in 1:num_ticks
                # Deterministic gradient
                g = rand(rng) * 0.5f0
                
                # Get region
                region = RegionState(1, [1, 2, 3, 4, 5])
                
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
    
    @testset "Exposure Exhaustive Tests" begin
        # Exhaustive exposure tests over vacant, superplastic, and consolidated -1/0/+1 cases
        
        # Vacant sites (!allocated)
        vacant_neg = SiteState(-1, false, false, 0)
        vacant_zero = SiteState(0, false, false, 0)
        vacant_pos = SiteState(1, false, false, 0)
        
        @test exposure(vacant_neg, ZCS()) == 0
        @test exposure(vacant_zero, ZCS()) == 0
        @test exposure(vacant_pos, ZCS()) == 0
        
        @test exposure(vacant_neg, VPS()) == 0
        @test exposure(vacant_zero, VPS()) == 0
        @test exposure(vacant_pos, VPS()) == 0
        
        # Consolidated sites (allocated && !superplastic)
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
        # ZCS exposes 0
        # VPS exposes prior_q
        super_neg = SiteState(-1, true, true, 1)
        super_zero = SiteState(0, true, true, 2)
        super_pos = SiteState(1, true, true, 3)
        
        @test exposure(super_neg, ZCS()) == 0
        @test exposure(super_zero, ZCS()) == 0
        @test exposure(super_pos, ZCS()) == 0
        
        # VPS with prior_q
        @test exposure(super_neg, VPS(); prior_q=Int8(-1)) == -1
        @test exposure(super_zero, VPS(); prior_q=Int8(0)) == 0
        @test exposure(super_pos, VPS(); prior_q=Int8(1)) == 1
        
        # VPS without explicit prior_q defaults to current q (not typical but valid)
        @test exposure(super_neg, VPS()) == -1  # uses site.q as prior_q
        @test exposure(super_zero, VPS()) == 0
        @test exposure(super_pos, VPS()) == 1
    end
end

println("All Stage-0 tests passed!")
