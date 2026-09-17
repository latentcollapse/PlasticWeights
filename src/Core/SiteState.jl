"""
    SiteState

Core site storage following the Stage-0 contract.

Logical fields:
- q::Int8             # ternary state: -1, 0, +1
- allocated::Bool     # whether site is allocated
- superplastic::Bool  # whether site is in superplastic state
- hot_handle::Int32   # handle into hot pool (0 = invalid sentinel)

Note: Prototype storage does not need final bit-packing.
Correctness before compression.
"""
struct SiteState
    q::Int8
    allocated::Bool
    superplastic::Bool
    hot_handle::Int32
    
    function SiteState(q::Integer, allocated::Bool=false, superplastic::Bool=false, hot_handle::Integer=0)
        # Hard failure gate: q must be in {-1, 0, +1}
        if !(q in (-1, 0, 1))
            error("HardFailure: site q leaves {-1,0,+1}, got q=$q")
        end
        new(Int8(q), allocated, superplastic, Int32(hot_handle))
    end
end

# Default constructor
SiteState() = SiteState(0, false, false, 0)

# Validation helpers
is_valid_q(site::SiteState)::Bool = site.q in (-1, 0, 1)

has_valid_hot_handle(site::SiteState)::Bool = site.hot_handle != 0

"""
    check_invariants(site::SiteState)

Hard failure gates for site state:
- site q must be in {-1, 0, +1}
- superplastic site must have valid hot handle
- non-superplastic site must not own hot handle
"""
function check_invariants(site::SiteState)
    # Gate 1: q must be in {-1, 0, +1}
    if !is_valid_q(site)
        error("HardFailure: site q leaves {-1,0,+1}, got q=$(site.q)")
    end
    
    # Gate 2: superplastic site must have valid hot handle
    if site.superplastic && site.hot_handle == 0
        error("HardFailure: superplastic site lacks valid hot handle")
    end
    
    # Gate 3: non-superplastic site must not own hot handle
    if !site.superplastic && site.hot_handle != 0
        error("HardFailure: non-superplastic site owns hot handle $(site.hot_handle)")
    end
    
    return true
end

# Mutations (used during apply_action! phase)
function set_q!(site::SiteState, new_q::Integer)
    if !(new_q in (-1, 0, 1))
        error("HardFailure: attempted to set q to $new_q, outside {-1,0,+1}")
    end
    # Note: In practice we'd use Ref or mutable struct for this
    # For now, return new state
    SiteState(new_q, site.allocated, site.superplastic, site.hot_handle)
end

function set_allocated!(site::SiteState, allocated::Bool)
    SiteState(site.q, allocated, site.superplastic, site.hot_handle)
end

function set_superplastic!(site::SiteState, superplastic::Bool)
    SiteState(site.q, site.allocated, superplastic, site.hot_handle)
end

function set_hot_handle!(site::SiteState, handle::Integer)
    SiteState(site.q, site.allocated, site.superplastic, Int32(handle))
end
