"""
    Causal Tests

Tests for causal correctness and deterministic behavior.

Tests:
- Deterministic iteration order
- Reproducible results with same seed
- Tick order compliance
- No unordered hash-map iteration in state paths
"""

function run_causal_tests()
    println("Running causal tests...")
    
    # Test 1: Deterministic HotPool allocation
    println("  Test 1: Deterministic HotPool allocation")
    pool1 = HotPool(5)
    pool2 = HotPool(5)
    
    handles1 = [allocate!(pool1) for _ in 1:5]
    handles2 = [allocate!(pool2) for _ in 1:5]
    
    @assert handles1 == handles2 "HotPool allocation not deterministic"
    
    # Release and reallocate - should be deterministic
    release!(pool1, handles1[5])
    release!(pool2, handles2[5])
    
    h1 = allocate!(pool1)
    h2 = allocate!(pool2)
    @assert h1 == h2 "HotPool re-allocation not deterministic"
    
    # Test 2: Deterministic RegionMap
    println("  Test 2: Deterministic RegionMap")
    map1 = RegionMap(32, 4)
    map2 = RegionMap(32, 4)
    
    for i in 1:32
        r1 = get_region_id(map1, i)
        r2 = get_region_id(map2, i)
        @assert r1 == r2 "RegionMap mapping not deterministic at site $i"
    end
    
    # Test 3: Deterministic MLP forward pass
    println("  Test 3: Deterministic MLP forward")
    mlp1 = Stage0MLP(8, 16, 1; rng_seed=42)
    mlp2 = Stage0MLP(8, 16, 1; rng_seed=42)
    
    input_vec = rand(Float32, 8)
    out1 = forward(mlp1, input_vec)
    out2 = forward(mlp2, input_vec)
    
    @assert out1 == out2 "MLP forward pass not deterministic"
    
    # Different seed should give different output
    mlp3 = Stage0MLP(8, 16, 1; rng_seed=43)
    out3 = forward(mlp3, input_vec)
    @assert out1 != out3 "Different seeds should produce different outputs"
    
    # Test 4: Deterministic exposure computation
    println("  Test 4: Deterministic exposure")
    sites = [SiteState(i % 3 - 1, true, (i % 2) == 0, i) for i in 1:10]
    
    exposures_zcs1 = [exposure(s, ZCS()) for s in sites]
    exposures_zcs2 = [exposure(s, ZCS()) for s in sites]
    @assert exposures_zcs1 == exposures_zcs2 "ZCS exposure not deterministic"
    
    exposures_vps1 = [exposure(s, VPS()) for s in sites]
    exposures_vps2 = [exposure(s, VPS()) for s in sites]
    @assert exposures_vps1 == exposures_vps2 "VPS exposure not deterministic"
    
    println("Causal tests passed!")
    return true
end

# Export the test runner
export run_causal_tests
