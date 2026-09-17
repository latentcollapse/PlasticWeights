"""
    Atomic Stage-0 Seed Initializer

Creates a valid seed state with:
- q = 0 for all sites
- allocated = true for all sites
- superplastic = true for all sites
- exactly one valid hot handle per site
- residual (δ) = 0 in each hot slot
- valid telemetry initialized to zeros
- valid region state with proper thresholds

This is the ONLY valid Stage-0 seed constructor.
Do NOT create a "superplastic but handle=0" state.
"""

using ..Core: SiteState, SiteTelemetry, HotPool, RegionState, RegionMap

"""
    initialize_stage0_seed(num_sites::Integer, num_regions::Integer; 
                           rng_seed::UInt32=42) -> (sites, telemetry, pool, region_map, regions)

Returns fully initialized Stage-0 seed state:
- sites: Vector{SiteState} with q=0, allocated=true, superplastic=true, valid hot_handle
- telemetry: Vector{SiteTelemetry} with zeros
- pool: HotPool with one slot allocated per site, all residuals=0
- region_map: Strict partition of sites into regions
- regions: Vector{RegionState} with valid material parameters
"""
function initialize_stage0_seed(num_sites::Integer, num_regions::Integer;
                                 rng_seed::UInt32=42)
    if num_sites <= 0 || num_regions <= 0
        error("HardFailure: num_sites and num_regions must be positive")
    end
    if num_regions > num_sites
        error("HardFailure: num_regions cannot exceed num_sites")
    end
    
    rng = Xoshiro(rng_seed)
    
    # Create hot pool with capacity = num_sites (one slot per site)
    pool = HotPool(num_sites)
    
    # Create sites and allocate hot handles
    sites = Vector{SiteState}(undef, num_sites)
    telemetry = Vector{SiteTelemetry}(undef, num_sites)
    
    for i in 1:num_sites
        # Allocate hot handle first
        handle = allocate!(pool, 0.0f0)  # δ = 0
        if handle == 0
            error("HardFailure: failed to allocate hot handle for site $i")
        end
        
        # Create site with valid hot handle
        sites[i] = SiteState(
            q = Int8(0),
            allocated = true,
            superplastic = true,
            hot_handle = handle
        )
        
        # Initialize telemetry to zeros
        telemetry[i] = SiteTelemetry()
    end
    
    # Create region map (strict partition)
    region_map = RegionMap(num_sites, num_regions)
    
    # Create regions with valid material state
    regions = Vector{RegionState}(undef, num_regions)
    for r in 1:num_regions
        regions[r] = RegionState(
            yield_up = Float32(1.0),
            settle_down = Float32(0.5),
            eta = Float32(1.0),
            hardening_increment = Float32(0.1),
            k_yield = Int32(3),
            k_settle = Int32(3),
            epsilon_delta = Float32(0.01)
        )
    end
    
    return sites, telemetry, pool, region_map, regions
end

"""
    create_vacant_sites(num_sites::Integer) -> (sites, telemetry)

Creates vacant sites (not allocated, not superplastic, q=0, no hot handle).
Useful for testing exposure semantics.
"""
function create_vacant_sites(num_sites::Integer)
    sites = Vector{SiteState}(undef, num_sites)
    telemetry = Vector{SiteTelemetry}(undef, num_sites)
    
    for i in 1:num_sites
        sites[i] = SiteState(
            q = Int8(0),
            allocated = false,
            superplastic = false,
            hot_handle = Int32(0)
        )
        telemetry[i] = SiteTelemetry()
    end
    
    return sites, telemetry
end

export initialize_stage0_seed, create_vacant_sites
