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
mutable struct SiteState
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

# Default constructor - vacant site
SiteState() = SiteState(0, false, false, 0)

"""
    SiteState(; stage0_seed=true)

Stage-0 seed constructor: creates allocated, superplastic site with q=0.
Requires a valid hot_handle to be assigned by HotPool.
"""
function SiteState(; stage0_seed::Bool=false)
    if stage0_seed
        # Material sites begin allocated and superplastic with q=0
        # hot_handle will be assigned by HotPool during initialization
        return SiteState(0, true, true, 0)  # handle set to 0 temporarily
    else
        return SiteState()
    end
end

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
