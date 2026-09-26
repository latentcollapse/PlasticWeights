"""
    RegionState

Persistent Stage-0 material-region state. `yield_up` is mutable because every
successful commit applies monotonic work-hardening.
"""
mutable struct RegionState
    id::Int32
    site_indices::Vector{Int}
    region_size::Int32
    yield_up::Float32
    settle_down::Float32
    eta::Float32
    hardening_increment::Float32
    epsilon_delta::Float32
    k_yield::Int32
    k_settle::Int32

    function RegionState(id::Integer, site_indices::AbstractVector{<:Integer};
        yield_up::Real=0.5f0,
        settle_down::Real=0.3f0,
        eta::Real=1.0f0,
        hardening_increment::Real=0.05f0,
        epsilon_delta::Real=0.1f0,
        k_yield::Integer=3,
        k_settle::Integer=3)
        isempty(site_indices) &&
            error("HardFailure: region $id has no sites")

        idx = Int.(collect(site_indices))


        issorted(idx) ||
            error("HardFailure: region $id site indices must be sorted")

        for (prev, curr) in zip(idx, Iterators.drop(idx, 1))
            curr == prev + 1 ||
                error("HardFailure: region $id must be contiguous")
        end

        yu = Float32(yield_up)
        sd = Float32(settle_down)
        et = Float32(eta)
        hi = Float32(hardening_increment)
        ed = Float32(epsilon_delta)

        sd >= 0.0f0 || error("HardFailure: settle_down must be >= 0")
        yu > sd || error("HardFailure: yield_up must exceed settle_down")
        et > 0.0f0 || error("HardFailure: eta must be > 0")
        hi > 0.0f0 || error("HardFailure: hardening_increment must be > 0")
        ed > 0.0f0 || error("HardFailure: epsilon_delta must be > 0")
        k_yield >= 1 || error("HardFailure: k_yield must be >= 1")
        k_settle >= 1 || error("HardFailure: k_settle must be >= 1")

        new(Int32(id), idx, Int32(length(idx)), yu, sd, et, hi, ed,
            Int32(k_yield), Int32(k_settle))
    end
end

"""
    RegionMap(num_sites, region_size; ...)

Fixed, contiguous, strict partition of logical parameter order. Stage-0 region
size is constrained to the frozen 64–256-site range.
"""
struct RegionMap
    regions::Vector{RegionState}
    site_to_region::Vector{Int32}
    num_sites::Int32
    region_size::Int32

    function RegionMap(num_sites::Integer, region_size::Integer;
        yield_up::Real=0.5f0,
        settle_down::Real=0.3f0,
        eta::Real=1.0f0,
        hardening_increment::Real=0.05f0,
        epsilon_delta::Real=0.1f0,
        k_yield::Integer=3,
        k_settle::Integer=3)
        num_sites > 0 || error("HardFailure: num_sites must be positive")
        64 <= region_size <= 256 ||
            error("HardFailure: Stage-0 region_size must be in 64:256, got $region_size")
        num_sites % region_size == 0 ||
            error("HardFailure: num_sites ($num_sites) must be divisible by region_size ($region_size)")

        nregions = div(num_sites, region_size)
        regions = Vector{RegionState}(undef, nregions)
        site_to_region = Vector{Int32}(undef, num_sites)

        for r in 1:nregions
            first_site = (r - 1) * region_size + 1
            last_site = r * region_size
            indices = collect(first_site:last_site)
            regions[r] = RegionState(r, indices;
                yield_up=yield_up,
                settle_down=settle_down,
                eta=eta,
                hardening_increment=hardening_increment,
                epsilon_delta=epsilon_delta,
                k_yield=k_yield,
                k_settle=k_settle)
            for i in indices
                site_to_region[i] = Int32(r)
            end
        end

        new(regions, site_to_region, Int32(num_sites), Int32(region_size))
    end
end

function get_region_id(map::RegionMap, site_index::Integer)::Int
    i = Int(site_index)
    1 <= i <= Int(map.num_sites) || error("HardFailure: site index $i out of bounds")
    return Int(map.site_to_region[i])
end

get_region(map::RegionMap, region_id::Integer)::RegionState = begin
    r = Int(region_id)
    1 <= r <= length(map.regions) || error("HardFailure: region id $r out of bounds")
    map.regions[r]
end

get_region_for_site(map::RegionMap, site_index::Integer)::RegionState =
    get_region(map, get_region_id(map, site_index))

function check_invariants(map::RegionMap)
    ns = Int(map.num_sites)
    rs = Int(map.region_size)
    64 <= rs <= 256 || error("HardFailure: region size outside 64:256")
    ns % rs == 0 || error("HardFailure: invalid region partition")
    length(map.site_to_region) == ns || error("HardFailure: site_to_region length mismatch")

    seen = falses(ns)
    for (ridx, region) in enumerate(map.regions)
        Int(region.id) == ridx || error("HardFailure: noncanonical region id")
        Int(region.region_size) == rs || error("HardFailure: inconsistent region size")
        for site_index in region.site_indices
            1 <= site_index <= ns || error("HardFailure: region site out of bounds")
            seen[site_index] && error("HardFailure: site $site_index belongs to multiple regions")
            seen[site_index] = true
            Int(map.site_to_region[site_index]) == ridx ||
                error("HardFailure: site_to_region disagreement at site $site_index")
        end
    end
    all(seen) || error("HardFailure: region partition does not cover every site")
    return true
end
