"""
    SubstrateState

Minimal deterministic Stage-0 substrate used by the reference kernel. Region
state has exactly one source of truth: `region_map.regions`.
"""
mutable struct SubstrateState{S<:AbstractSiteState}
    sites::Vector{S}
    telemetry::Vector{SiteTelemetry}
    pool::HotPool
    region_map::RegionMap
    max_superplastic::Int32
end

function _region_map(num_sites::Integer, region_size::Integer;
                     yield_up::Real, settle_down::Real, eta::Real,
                     hardening_increment::Real, epsilon_delta::Real,
                     k_yield::Integer, k_settle::Integer)
    return RegionMap(num_sites, region_size;
        yield_up=yield_up,
        settle_down=settle_down,
        eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta,
        k_yield=k_yield,
        k_settle=k_settle)
end

"""
    initialize_stage0_seed(num_sites; region_size=64, ...)

Create the normative all-allocated/all-superplastic Stage-0 seed atomically:
q=0, one unique hot slot per site, and δ=0 in every slot.
"""
function initialize_stage0_seed(num_sites::Integer; region_size::Integer=64,
                                yield_up::Real=0.5f0,
                                settle_down::Real=0.3f0,
                                eta::Real=1.0f0,
                                hardening_increment::Real=0.05f0,
                                epsilon_delta::Real=0.1f0,
                                k_yield::Integer=3,
                                k_settle::Integer=3)::SubstrateState
    region_map = _region_map(num_sites, region_size;
        yield_up=yield_up, settle_down=settle_down, eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta, k_yield=k_yield, k_settle=k_settle)
    pool = HotPool(num_sites)
    sites = Vector{SiteState}(undef, num_sites)
    telemetry = [SiteTelemetry() for _ in 1:num_sites]

    for i in 1:num_sites
        handle = allocate!(pool, 0.0f0)
        sites[i] = SiteState(0, true, true, handle)
    end

    # The normative seed is all-superplastic, so its budget must admit every site.
    substrate = SubstrateState{SiteState}(sites, telemetry, pool, region_map, Int32(num_sites))
    check_invariants(substrate)
    return substrate
end

"""Create an all-allocated consolidated substrate for mechanism tests."""
function initialize_consolidated_substrate(num_sites::Integer; region_size::Integer=64,
                                           q::Integer=0,
                                           max_superplastic::Integer=num_sites,
                                           yield_up::Real=0.5f0,
                                           settle_down::Real=0.3f0,
                                           eta::Real=1.0f0,
                                           hardening_increment::Real=0.05f0,
                                           epsilon_delta::Real=0.1f0,
                                           k_yield::Integer=3,
                                           k_settle::Integer=3)::SubstrateState
    q in (-1, 0, 1) || error("HardFailure: q must be ternary")
    0 <= max_superplastic <= num_sites ||
        error("HardFailure: max_superplastic must be in 0:num_sites")
    region_map = _region_map(num_sites, region_size;
        yield_up=yield_up, settle_down=settle_down, eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta, k_yield=k_yield, k_settle=k_settle)
    pool = HotPool(num_sites)
    sites = [SiteState(q, true, false, 0) for _ in 1:num_sites]
    telemetry = [SiteTelemetry() for _ in 1:num_sites]
    substrate = SubstrateState{SiteState}(sites, telemetry, pool, region_map, Int32(max_superplastic))
    check_invariants(substrate)
    return substrate
end

"""
    initialize_fp_seed(num_sites; initial_weights=nothing, region_size=64, ...)

Create the all-allocated/all-superplastic continuous FP seed atomically:
each site is allocated, superplastic with hot handle, and initialized to initial_weights (default zeros).
"""
function initialize_fp_seed(num_sites::Integer;
                            initial_weights::Union{Nothing,AbstractVector{<:Real}}=nothing,
                            region_size::Integer=64,
                            yield_up::Real=0.5f0,
                            settle_down::Real=0.3f0,
                            eta::Real=1.0f0,
                            hardening_increment::Real=0.05f0,
                            epsilon_delta::Real=0.1f0,
                            k_yield::Integer=3,
                            k_settle::Integer=3)::SubstrateState{FPSiteState}
    region_map = _region_map(num_sites, region_size;
        yield_up=yield_up, settle_down=settle_down, eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta, k_yield=k_yield, k_settle=k_settle)
    pool = HotPool(num_sites)
    sites = Vector{FPSiteState}(undef, num_sites)
    telemetry = [SiteTelemetry() for _ in 1:num_sites]

    w_init = initial_weights === nothing ? zeros(Float32, num_sites) : Float32.(initial_weights)
    length(w_init) == num_sites || error("HardFailure: initial_weights length mismatch")

    for i in 1:num_sites
        handle = allocate!(pool, 0.0f0)
        sites[i] = FPSiteState(w_init[i], true, true, handle)
    end

    substrate = SubstrateState{FPSiteState}(sites, telemetry, pool, region_map, Int32(num_sites))
    check_invariants(substrate)
    return substrate
end

"""Create an all-allocated consolidated continuous FP substrate for mechanism tests."""
function initialize_fp_consolidated_substrate(num_sites::Integer;
                                              initial_weights::Union{Nothing,AbstractVector{<:Real}}=nothing,
                                              region_size::Integer=64,
                                              max_superplastic::Integer=num_sites,
                                              yield_up::Real=0.5f0,
                                              settle_down::Real=0.3f0,
                                              eta::Real=1.0f0,
                                              hardening_increment::Real=0.05f0,
                                              epsilon_delta::Real=0.1f0,
                                              k_yield::Integer=3,
                                              k_settle::Integer=3)::SubstrateState{FPSiteState}
    0 <= max_superplastic <= num_sites ||
        error("HardFailure: max_superplastic must be in 0:num_sites")
    region_map = _region_map(num_sites, region_size;
        yield_up=yield_up, settle_down=settle_down, eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta, k_yield=k_yield, k_settle=k_settle)
    pool = HotPool(num_sites)
    w_init = initial_weights === nothing ? zeros(Float32, num_sites) : Float32.(initial_weights)
    length(w_init) == num_sites || error("HardFailure: initial_weights length mismatch")

    sites = [FPSiteState(w_init[i], true, false, 0) for i in 1:num_sites]
    telemetry = [SiteTelemetry() for _ in 1:num_sites]
    substrate = SubstrateState{FPSiteState}(sites, telemetry, pool, region_map, Int32(max_superplastic))
    check_invariants(substrate)
    return substrate
end

function check_invariants(substrate::SubstrateState)
    n = length(substrate.sites)
    length(substrate.telemetry) == n || error("HardFailure: site/telemetry length mismatch")
    Int(substrate.region_map.num_sites) == n || error("HardFailure: region-map/site length mismatch")
    check_invariants(substrate.pool)
    check_invariants(substrate.region_map)
    0 <= substrate.max_superplastic <= n || error("HardFailure: invalid superplastic budget")

    owned = Int32[]
    for site in substrate.sites
        check_invariants(site)
        if site.superplastic
            is_valid_handle(substrate.pool, site.hot_handle) ||
                error("HardFailure: site owns invalid hot handle $(site.hot_handle)")
            push!(owned, site.hot_handle)
        end
    end
    length(unique(owned)) == length(owned) || error("HardFailure: two sites own the same hot handle")
    length(owned) == num_allocated(substrate.pool) ||
        error("HardFailure: allocated hot slot has no owning superplastic site")
    length(owned) <= Int(substrate.max_superplastic) ||
        error("HardFailure: global superplastic budget exceeded")
    return true
end
