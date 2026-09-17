"""
    Snapshot

Immutable snapshot for DCP decision-making.

The DCP sees only immutable declared snapshot fields.
Created at step 10 of the tick order.

Snapshot must contain every declared value the rule reads:
- site_index
- q
- allocated
- superplastic
- stress_ema
- residual_motion_ema
- consecutive_above_yield
- consecutive_stable
- yield_up (from region)
- settle_down (from region)
- k_yield (from region)
- k_settle (from region)
- epsilon_delta (from region)
- hot_capacity / budget eligibility boolean(s) needed for melt

The same DCP is used for ZCS and VPS. Do not include branch-specific exposure values
in the DCP snapshot unless a rule actually requires them. Stage-0 rules do not.
"""
struct Snapshot
    site_index::Int32
    q::Int8
    allocated::Bool
    superplastic::Bool
    stress_ema::Float32
    residual_motion_ema::Float32
    consecutive_above_yield::Int32
    consecutive_stable::Int32
    yield_up::Float32
    settle_down::Float32
    k_yield::Int32
    k_settle::Int32
    epsilon_delta::Float32
    has_hot_capacity::Bool  # budget/hot slot availability for melt
    tick::Int32
    
    function Snapshot(site_index::Integer, q::Integer, 
                     allocated::Bool, superplastic::Bool,
                     stress_ema::Real, residual_motion_ema::Real,
                     consecutive_above_yield::Integer, consecutive_stable::Integer,
                     yield_up::Real, settle_down::Real,
                     k_yield::Integer, k_settle::Integer,
                     epsilon_delta::Real,
                     has_hot_capacity::Bool,
                     tick::Integer)
        # Validate q is in valid range
        if !(q in (-1, 0, 1))
            error("HardFailure: Snapshot q must be in {-1,0,+1}, got $q")
        end
        
        new(Int32(site_index), Int8(q), allocated, superplastic,
            Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable),
            Float32(yield_up), Float32(settle_down),
            Int32(k_yield), Int32(k_settle),
            Float32(epsilon_delta), has_hot_capacity, Int32(tick))
    end
end

# Default constructor
Snapshot() = Snapshot(0, 0, false, false, 0.0f0, 0.0f0, 0, 0, 
                      0.5f0, 0.3f0, 3, 3, 0.1f0, false, 0)

"""
    create_snapshot(site_index, region_state, site_state, site_telemetry, 
                    has_hot_capacity, tick) -> Snapshot

Creates an immutable snapshot from current substrate state.
This is the only way to create snapshots - ensures immutability.
"""
function create_snapshot(site_index::Integer, region_state::RegionState,
                        site_state::SiteState, site_telemetry::SiteTelemetry,
                        has_hot_capacity::Bool, tick::Integer)::Snapshot
    return Snapshot(site_index, site_state.q, site_state.allocated,
                   site_state.superplastic,
                   site_telemetry.stress_ema, site_telemetry.residual_motion_ema,
                   site_telemetry.consecutive_above_yield, site_telemetry.consecutive_stable,
                   region_state.yield_up, region_state.settle_down,
                   region_state.k_yield, region_state.k_settle,
                   region_state.epsilon_delta,
                   has_hot_capacity, tick)
end
