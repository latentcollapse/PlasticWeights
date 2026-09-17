"""
    Sanity Tests

Basic sanity checks for Stage-0 implementation.

Tests:
- SiteState construction and validation
- HotPool allocation/release
- RegionMap partition invariants
- Basic exposure policies
"""

function run_sanity_tests()
    println("Running sanity tests...")
    
    # Test 1: SiteState construction
    println("  Test 1: SiteState construction")
    site = SiteState(0)
    @assert site.q == 0
    @assert !site.allocated
    @assert !site.superplastic
    @assert site.hot_handle == 0
    
    site_pos = SiteState(1)
    @assert site_pos.q == 1
    
    site_neg = SiteState(-1)
    @assert site_neg.q == -1
    
    # Test invalid q
    try
        SiteState(2)
        error("Should have failed for q=2")
    catch e
        # Expected
    end
    
    # Test 2: HotPool basic operations
    println("  Test 2: HotPool operations")
    pool = HotPool(10)
    @assert num_allocated(pool) == 0
    
    handle = allocate!(pool)
    @assert handle > 0
    @assert num_allocated(pool) == 1
    @assert is_valid_handle(pool, handle)
    
    release!(pool, handle)
    @assert num_allocated(pool) == 0
    
    # Test 3: RegionMap construction
    println("  Test 3: RegionMap construction")
    region_map = RegionMap(64, 8)
    @assert length(region_map.regions) == 8
    @assert region_map.region_size == 8
    @assert region_map.num_sites == 64
    
    # Check deterministic mapping
    for i in 1:64
        region_id = get_region_id(region_map, i)
        @assert 1 <= region_id <= 8
    end
    
    # Test 4: Exposure policies
    println("  Test 4: Exposure policies")
    normal_site = SiteState(1, true, false, 0)
    super_site = SiteState(1, true, true, 1)
    
    zcs_normal = exposure(normal_site, ZCS())
    @assert zcs_normal == 1
    
    zcs_super = exposure(super_site, ZCS())
    @assert zcs_super == 1
    
    vps_normal = exposure(normal_site, VPS())
    @assert vps_normal == 1
    
    vps_super = exposure(super_site, VPS())
    @assert vps_super == 2  # Amplified
    
    println("Sanity tests passed!")
    return true
end

# Export the test runner
export run_sanity_tests
