"""
    RegionState

Represents a region in the substrate following the Stage-0 contract.

Contract:
- strict partition of sites
- deterministic site -> region lookup
- fixed region size for a run
- no overlap between regions

Persistent material region state contains (MUTABLE for work-hardening):
- id::Int32                    # region identifier
- site_indices::Vector{Int}    # indices of sites belonging to this region
- region_size::Int             # number of sites in this region
- yield_up::Float32            # threshold for melt (sigma > yield_up triggers melt) - MUTABLE
- settle_down::Float32         # threshold for commit (sigma < settle_down enables commit)
- eta::Float32                 # viscosity parameter for constitutive response
- hardening_increment::Float32 # amount to add to yield on commit
- epsilon_delta::Float32       # residual-motion threshold for commit
- k_yield::Int32               # sustained count threshold for melt
- k_settle::Int32              # sustained count threshold for commit

Validation:
    yield_up > settle_down
    eta > 0
    hardening_increment > 0
    k_yield >= 1
    k_settle >= 1
"""
mutable struct RegionState
    id::Int32
    site_indices::Vector{Int}  # indices of sites belonging to this region
    region_size::Int
    
    # Persistent material parameters (declared state required by controller)
    # yield_up is mutable for work-hardening
    yield_up::Float32          # tau_U: threshold for melt
    settle_down::Float32       # tau_S: threshold for commit  
    eta::Float32               # viscosity parameter
    hardening_increment::Float32  # work-hardening amount on commit
    epsilon_delta::Float32     # residual-motion threshold for commit
    k_yield::Int32             # sustained above-yield counter threshold for melt
    k_settle::Int32            # sustained stable counter threshold for commit
    
    function RegionState(id::Integer, site_indices::Vector{Int};
                         yield_up::Real=0.5,
                         settle_down::Real=0.3,
                         eta::Real=1.0,
                         hardening_increment::Real=0.05,
                         epsilon_delta::Real=0.1,
                         k_yield::Integer=3,
                         k_settle::Integer=3)
        if isempty(site_indices)
            error("HardFailure: region $id has empty site_indices")
        end
        
        # Validate constraints
        if Float32(yield_up) <= Float32(settle_down)
            error("HardFailure: region $id yield_up ($(yield_up)) must be > settle_down ($(settle_down))")
        end
        if Float32(eta) <= 0
            error("HardFailure: region $id eta must be > 0, got $(eta)")
        end
        if Float32(hardening_increment) <= 0
            error("HardFailure: region $id hardening_increment must be > 0, got $(hardening_increment)")
        end
        if Int32(k_yield) < 1
            error("HardFailure: region $id k_yield must be >= 1, got $(k_yield)")
        end
        if Int32(k_settle) < 1
            error("HardFailure: region $id k_settle must be >= 1, got $(k_settle)")
        end
        
        new(Int32(id), site_indices, length(site_indices),
            Float32(yield_up), Float32(settle_down), Float32(eta),
            Float32(hardening_increment), Float32(epsilon_delta),
            Int32(k_yield), Int32(k_settle))
    end
end

# Default constructor
RegionState() = RegionState(0, Int[]; yield_up=0.5, settle_down=0.3, eta=1.0,
                            hardening_increment=0.05, epsilon_delta=0.1,
                            k_yield=3, k_settle=3)

"""
    RegionMap

Manages the partition of sites into regions.

Ensures:
- strict partition (every site belongs to exactly one region)
- deterministic site -> region lookup
- fixed region size for a run
- no overlap
"""
struct RegionMap
    regions::Vector{RegionState}
    site_to_region::Vector{Int}  # maps site index -> region id
    num_sites::Int
    region_size::Int
    
    function RegionMap(num_sites::Int, region_size::Int;
                       yield_up::Real=0.5,
                       settle_down::Real=0.3,
                       eta::Real=1.0,
                       hardening_increment::Real=0.05,
                       epsilon_delta::Real=0.1,
                       k_yield::Integer=3,
                       k_settle::Integer=3)
        if num_sites <= 0
            error("HardFailure: num_sites must be positive, got $num_sites")
        end
        if region_size <= 0
            error("HardFailure: region_size must be positive, got $region_size")
        end
        if num_sites % region_size != 0
            error("HardFailure: num_sites ($num_sites) not divisible by region_size ($region_size)")
        end
        
        num_regions = div(num_sites, region_size)
        regions = Vector{RegionState}(undef, num_regions)
        site_to_region = Vector{Int}(undef, num_sites)
        
        for r in 1:num_regions
            start_idx = (r - 1) * region_size + 1
            end_idx = r * region_size
            site_indices = collect(start_idx:end_idx)
            
            regions[r] = RegionState(r, site_indices;
                                     yield_up=yield_up,
                                     settle_down=settle_down,
                                     eta=eta,
                                     hardening_increment=hardening_increment,
                                     epsilon_delta=epsilon_delta,
                                     k_yield=k_yield,
                                     k_settle=k_settle)
            
            # Map each site to its region
            for idx in site_indices
                site_to_region[idx] = r
            end
        end
        
        new(regions, site_to_region, num_sites, region_size)
    end
end

# Get region ID for a site
function get_region_id(map::RegionMap, site_index::Int)::Int
    if site_index < 1 || site_index > map.num_sites
        error("HardFailure: site_index $site_index out of bounds [1, $(map.num_sites)]")
    end
    return map.site_to_region[site_index]
end

# Get region state by ID
function get_region(map::RegionMap, region_id::Int)::RegionState
    if region_id < 1 || region_id > length(map.regions)
        error("HardFailure: region_id $region_id out of bounds [1, $(length(map.regions))]")
    end
    return map.regions[region_id]
end

# Validate region partition invariants
function check_invariants(map::RegionMap)
    # Check that every site is mapped to exactly one region
    for i in 1:map.num_sites
        if map.site_to_region[i] < 1 || map.site_to_region[i] > length(map.regions)
            error("HardFailure: site $i has invalid region mapping $(map.site_to_region[i])")
        end
    end
    
    # Check that regions don't overlap
    seen_sites = Set{Int}()
    for region in map.regions
        for site_idx in region.site_indices
            if site_idx in seen_sites
                error("HardFailure: site $site_idx appears in multiple regions")
            end
            push!(seen_sites, site_idx)
        end
    end
    
    # Check all sites are covered
    if length(seen_sites) != map.num_sites
        error("HardFailure: region partition does not cover all sites: $(length(seen_sites)) != $(map.num_sites)")
    end
    
    return true
end
