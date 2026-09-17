"""
    Actions

DCP actions for substrate transitions.

Actions are immutable declarations of intended changes.
Applied atomically in step 12 of the tick order.

Rules:
- consolidated allocated site -> MELT iff consecutive_above_yield >= k_yield and budget/hot slot permits
- superplastic site -> COMMIT iff consecutive_stable >= k_settle
- otherwise HOLD
"""
abstract type Action end

"""
    NoAction <: Action

No operation - site remains unchanged (HOLD).
"""
struct NoAction <: Action end

"""
    MeltAction <: Action

Transitions a site to superplastic state (melt).
Allocates a hot slot.
"""
struct MeltAction <: Action
    site_index::Int32
end

"""
    CommitAction <: Action

Transitions a site from superplastic to consolidated state.
Releases the hot slot.
"""
struct CommitAction <: Action
    site_index::Int32
end

# Default no-action
const NO_ACTION = NoAction()

# Helper to create action types
make_no_action() = NO_ACTION
make_melt(site_index::Integer) = MeltAction(Int32(site_index))
make_commit(site_index::Integer) = CommitAction(Int32(site_index))

"""
    apply_action!(action::Action, sites, telemetry, pool, region_map, regions, 
                  exposure_policy)

Applies an action atomically to the substrate.

MELT:
- Requires consolidated allocated site (allocated=true, superplastic=false)
- Allocates exactly one hot slot
- Sets residual (δ) = 0
- Preserves q
- Sets superplastic = true
- Writes hot handle to site
- Resets lifecycle counters (consecutive_above_yield, consecutive_stable)

COMMIT:
- Requires superplastic site with exactly one valid hot handle
- Reads δ from HotPool
- ZCS base = 0; VPS base = site.q
- s = base + delta
- Ternary round: s < -0.5 => -1, -0.5 <= s <= 0.5 => 0, s > 0.5 => +1
- Writes committed q
- Sets superplastic = false
- Releases hot handle exactly once
- Sets hot_handle = 0
- Resets counters
- Applies region work-hardening: region.yield_up += hardening_increment
"""
function apply_action!(action::Action, sites, telemetry, pool, region_map, regions,
                       exposure_policy=nothing)
    if action isa NoAction
        return nothing
    elseif action isa MeltAction
        i = action.site_index
        site = sites[i]
        
        # Require consolidated allocated site
        if !site.allocated || site.superplastic
            error("HardFailure: MELT requires consolidated allocated site at index $i")
        end
        
        # Allocate exactly one hot slot with δ = 0
        handle = allocate!(pool, 0.0f0)
        if handle == 0
            error("HardFailure: failed to allocate hot handle for MELT at site $i")
        end
        
        # Preserve q, set superplastic=true, write hot handle
        sites[i] = SiteState(
            q = site.q,
            allocated = true,
            superplastic = true,
            hot_handle = handle
        )
        
        # Reset lifecycle counters
        telemetry[i].consecutive_above_yield = Int32(0)
        telemetry[i].consecutive_stable = Int32(0)
        
    elseif action isa CommitAction
        i = action.site_index
        site = sites[i]
        
        # Require superplastic site with valid hot handle
        if !site.superplastic || site.hot_handle == 0
            error("HardFailure: COMMIT requires superplastic site with valid hot handle at index $i")
        end
        
        # Read δ from HotPool
        delta = get_residual(pool, site.hot_handle)
        
        # Determine base: ZCS=0, VPS=site.q
        base = 0.0f0
        if exposure_policy !== nothing && exposure_policy == :VPS
            base = Float32(site.q)
        end
        
        # s = base + delta
        s = base + delta
        
        # Ternary round
        new_q = Int8(0)
        if s < -0.5f0
            new_q = Int8(-1)
        elseif s > 0.5f0
            new_q = Int8(1)
        else
            new_q = Int8(0)
        end
        
        # Release hot handle exactly once
        release!(pool, site.hot_handle)
        
        # Update site: q written, superplastic=false, hot_handle=0
        sites[i] = SiteState(
            q = new_q,
            allocated = true,
            superplastic = false,
            hot_handle = Int32(0)
        )
        
        # Reset counters
        telemetry[i].consecutive_above_yield = Int32(0)
        telemetry[i].consecutive_stable = Int32(0)
        
        # Apply region work-hardening
        region_id = get_region_id(region_map, i)
        region = regions[region_id]
        region.yield_up += region.hardening_increment
        # Ensure yield_up > settle_down
        if region.yield_up <= region.settle_down
            region.yield_up = region.settle_down + Float32(0.01)
        end
        regions[region_id] = region
        
    else
        error("HardFailure: unknown action type $(typeof(action))")
    end
    
    return nothing
end

export apply_action!
