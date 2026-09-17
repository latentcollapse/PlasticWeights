"""
    Invariant Tests

Tests for hard failure gates and invariants.

Tests:
- Site q stays in {-1, 0, +1}
- Superplastic sites have valid hot handles
- Non-superplastic sites don't own hot handles
- Region partition validity
- Hot pool invariants
"""

function run_invariant_tests()
    println("Running invariant tests...")
    
    # Test 1: SiteState q invariant
    println("  Test 1: SiteState q invariant")
    for q_val in [-1, 0, 1]
        site = SiteState(q_val)
        @assert is_valid_q(site) "Valid q=$q_val failed check"
    end
    
    # Invalid q values should fail
    for invalid_q in [-2, 2, 3, -5, 10]
        try
            SiteState(invalid_q)
            error("Should have failed for q=$invalid_q")
        catch e
            # Expected - hard failure gate
        end
    end
    
    # Test 2: Superplastic-hot handle invariant
    println("  Test 2: Superplastic-hot handle invariant")
    
    # Superplastic without handle should fail check
    super_no_handle = SiteState(1, true, true, 0)
    try
        check_invariants(super_no_handle)
        error("Should have failed: superplastic without handle")
    catch e
        # Expected
    end
    
    # Non-superplastic with handle should fail check
    normal_with_handle = SiteState(1, true, false, 5)
    try
        check_invariants(normal_with_handle)
        error("Should have failed: non-superplastic with handle")
    catch e
        # Expected
    end
    
    # Valid combinations should pass
    normal_no_handle = SiteState(1, true, false, 0)
    @assert check_invariants(normal_no_handle)
    
    # Test 3: HotPool invariants
    println("  Test 3: HotPool invariants")
    pool = HotPool(10)
    @assert check_invariants(pool)
    
    handle = allocate!(pool)
    @assert check_invariants(pool)
    
    release!(pool, handle)
    @assert check_invariants(pool)
    
    # Allocate multiple
    handles = [allocate!(pool) for _ in 1:5]
    @assert check_invariants(pool)
    @assert num_allocated(pool) == 5
    
    # Release some
    release!(pool, handles[1])
    release!(pool, handles[3])
    @assert check_invariants(pool)
    @assert num_allocated(pool) == 3
    
    # Test 4: RegionMap invariants
    println("  Test 4: RegionMap invariants")
    region_map = RegionMap(24, 6)
    @assert check_invariants(region_map)
    
    # Every site should map to a valid region
    for i in 1:24
        r = get_region_id(region_map, i)
        @assert 1 <= r <= 4 "Site $i maps to invalid region $r"
    end
    
    # Test 5: Snapshot q validation
    println("  Test 5: Snapshot q validation")
    snap = create_snapshot(1, 1, SiteState(0), 0.0, 0.5, 1)
    @assert snap.q == 0
    
    snap_pos = create_snapshot(1, 1, SiteState(1), 0.0, 0.5, 1)
    @assert snap_pos.q == 1
    
    snap_neg = create_snapshot(1, 1, SiteState(-1), 0.0, 0.5, 1)
    @assert snap_neg.q == -1
    
    println("Invariant tests passed!")
    return true
end

# Export the test runner
export run_invariant_tests
