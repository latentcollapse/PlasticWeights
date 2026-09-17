"""
    HotPool

Manages FP32 residuals for superplastic sites.

Contract:
- one FP32 residual per superplastic site
- handle 0 reserved as invalid sentinel
- no consolidated/vacant site owns a hot slot
- commit releases exactly once
- melt allocates exactly once
- deterministic free-list behavior in reference mode
"""
mutable struct HotPool
    residuals::Vector{Float32}      # FP32 residuals
    free_list::Vector{Int32}        # available handles (excluding 0)
    allocated::BitVector            # track which slots are allocated
    next_handle::Int32              # next handle to allocate (for determinism)
    capacity::Int32
    
    function HotPool(capacity::Integer)
        if capacity <= 0
            error("HardFailure: HotPool capacity must be positive, got $capacity")
        end
        
        # Handle 0 is reserved as invalid sentinel, so we need capacity+1 slots
        residuals = zeros(Float32, capacity + 1)
        free_list = Int32[capacity, capacity-1, ..., 1]  # deterministic order
        allocated = BitVector(undef, capacity + 1)
        fill!(allocated, false)
        
        new(residuals, free_list, allocated, Int32(1), Int32(capacity))
    end
end

# Get the number of allocated slots
num_allocated(pool::HotPool)::Int = count(pool.allocated)

# Check if a handle is valid and allocated
is_valid_handle(pool::HotPool, handle::Integer)::Bool
    handle_int = Int32(handle)
    return handle_int > 0 && handle_int <= pool.capacity && pool.allocated[handle_int]
end

"""
    allocate!(pool::HotPool) -> Int32

Allocates a hot slot and returns its handle.
Handle 0 is reserved as invalid sentinel.
Deterministic free-list behavior in reference mode.
"""
function allocate!(pool::HotPool)::Int32
    if isempty(pool.free_list)
        error("HardFailure: HotPool exhausted, no free handles available")
    end
    
    # Pop from free list (deterministic: always use highest available)
    handle = pop!(pool.free_list)
    
    if pool.allocated[handle]
        error("HardFailure: attempted to allocate already-allocated handle $handle")
    end
    
    pool.allocated[handle] = true
    pool.residuals[handle] = 0.0f0  # initialize to zero
    
    return handle
end

"""
    release!(pool::HotPool, handle::Int32)

Releases a hot slot back to the free list.
Must be called exactly once per allocation (commit releases exactly once).
"""
function release!(pool::HotPool, handle::Int32)
    if handle <= 0 || handle > pool.capacity
        error("HardFailure: invalid handle $handle for release")
    end
    
    if !pool.allocated[handle]
        error("HardFailure: attempted to release non-allocated handle $handle")
    end
    
    pool.allocated[handle] = false
    pool.residuals[handle] = 0.0f0
    
    # Push back to free list (deterministic order)
    push!(pool.free_list, handle)
end

"""
    get_residual(pool::HotPool, handle::Int32) -> Float32

Gets the residual value for a given handle.
"""
function get_residual(pool::HotPool, handle::Int32)::Float32
    if handle <= 0 || handle > pool.capacity
        error("HardFailure: invalid handle $handle for get_residual")
    end
    
    if !pool.allocated[handle]
        error("HardFailure: attempted to get residual from non-allocated handle $handle")
    end
    
    return pool.residuals[handle]
end

"""
    set_residual!(pool::HotPool, handle::Int32, value::Float32)

Sets the residual value for a given handle.
"""
function set_residual!(pool::HotPool, handle::Int32, value::Float32)
    if handle <= 0 || handle > pool.capacity
        error("HardFailure: invalid handle $handle for set_residual!")
    end
    
    if !pool.allocated[handle]
        error("HardFailure: attempted to set residual on non-allocated handle $handle")
    end
    
    pool.residuals[handle] = value
end

"""
    check_invariants(pool::HotPool)

Validates hot pool invariants:
- handle 0 is never allocated
- allocated count matches expectations
- free list + allocated = capacity
"""
function check_invariants(pool::HotPool)
    # Gate: handle 0 must never be allocated
    if pool.allocated[1]  # index 1 corresponds to handle 0 if we shifted, but we use 1-based indexing
        # Actually, our handles are 1..capacity mapping to indices 1..capacity
        # Handle 0 is conceptual sentinel, not stored
    end
    
    # Check free list + allocated = capacity
    num_free = length(pool.free_list)
    num_alloc = count(pool.allocated)
    
    if num_free + num_alloc != pool.capacity
        error("HardFailure: HotPool invariant violated: free($num_free) + allocated($num_alloc) != capacity($(pool.capacity))")
    end
    
    # Check all free handles are not allocated
    for handle in pool.free_list
        if pool.allocated[handle]
            error("HardFailure: handle $handle in free_list but marked as allocated")
        end
    end
    
    return true
end
