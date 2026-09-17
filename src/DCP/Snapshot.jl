"""
    Snapshot

Immutable snapshot for DCP decision-making.

The DCP sees only immutable declared snapshot fields.
Created at step 10 of the tick order.
"""
struct Snapshot
    site_index::Int32
    region_id::Int32
    q::Int8
    allocated::Bool
    superplastic::Bool
    exposure_zcs::Int8
    exposure_vps::Int8
    stress_ema::Float32
    residual::Float32
    tick::Int32
    
    function Snapshot(site_index::Integer, region_id::Integer, q::Integer, 
                     allocated::Bool, superplastic::Bool,
                     exposure_zcs::Integer, exposure_vps::Integer,
                     stress_ema::Real, residual::Real, tick::Integer)
        # Validate q is in valid range
        if !(q in (-1, 0, 1))
            error("HardFailure: Snapshot q must be in {-1,0,+1}, got $q")
        end
        
        new(Int32(site_index), Int32(region_id), Int8(q), allocated, superplastic,
            Int8(exposure_zcs), Int8(exposure_vps), Float32(stress_ema), 
            Float32(residual), Int32(tick))
    end
end

# Default constructor
Snapshot() = Snapshot(0, 0, 0, false, false, 0, 0, 0.0f0, 0.0f0, 0)

"""
    create_snapshot(site_index, region_id, site_state, exposure_policy, 
                    stress_ema, residual, tick) -> Snapshot

Creates an immutable snapshot from current substrate state.
This is the only way to create snapshots - ensures immutability.
"""
function create_snapshot(site_index::Integer, region_id::Integer, 
                        site_state::SiteState,
                        stress_ema::Real, residual::Real, tick::Integer)::Snapshot
    exposure_zcs = exposure(site_state, ZCS())
    exposure_vps = exposure(site_state, VPS())
    
    return Snapshot(site_index, region_id, site_state.q, site_state.allocated,
                   site_state.superplastic, exposure_zcs, exposure_vps,
                   stress_ema, residual, tick)
end
