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
    residuals::Vector{Float32}      # FP32 residuals (index = handle, handle 0 is sentinel)
    free_list::Vector{Int32}        # available handles (1-based, deterministic order)
    allocated::BitVector            # track which slots are allocated (index = handle)
    capacity::Int32
    
    function HotPool(capacity::Integer)
        if capacity <= 0
            error("HardFailure: HotPool capacity must be positive, got $capacity")
        end
        
        # Handle 0 is reserved as invalid sentinel
        # We use 1-based indexing: handle h maps to index h
        # Index 0 is unused/sentinel
        residuals = zeros(Float32, capacity + 1)  # indices 0..capacity, 0 is sentinel
        free_list = collect(Int32, capacity:-1:1)  # deterministic order: highest first
        allocated = BitVector(undef, capacity + 1)
        fill!(allocated, false)
        allocated[1] = false  # ensure index 0 (handle 0 conceptually) is never allocated
        # Note: In Julia BitVector is 1-indexed, so allocated[h] corresponds to handle h
        # We'll treat allocated[1] as handle 1, etc. Handle 0 is purely conceptual.
        
        new(residuals, free_list, allocated, Int32(capacity))
    end
end

# Get the number of allocated slots
num_allocated(pool::HotPool)::Int = count(==(true), pool.allocated)

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
- handle 0 is never allocated (conceptual - we don't store index 0)
- allocated count + free list length = capacity
- no handle is both in free list and allocated
- no double allocation or double release possible
"""
function check_invariants(pool::HotPool)
    # Check free list + allocated = capacity
    num_free = length(pool.free_list)
    num_alloc = count(==(true), pool.allocated)
    
    if num_free + num_alloc != pool.capacity
        error("HardFailure: HotPool invariant violated: free($num_free) + allocated($num_alloc) != capacity($(pool.capacity))")
    end
    
    # Check all free handles are not allocated
    for handle in pool.free_list
        if pool.allocated[handle]
            error("HardFailure: handle $handle in free_list but marked as allocated")
        end
    end
    
    # Check no duplicates in free list
    if length(unique(pool.free_list)) != length(pool.free_list)
        error("HardFailure: duplicate handles in free_list")
    end
    
    # Check all handles in free list are in valid range
    for handle in pool.free_list
        if handle < 1 || handle > pool.capacity
            error("HardFailure: handle $handle in free_list out of range [1, $(pool.capacity)]")
        end
    end
    
    return true
end

"""
    has_capacity(pool::HotPool) -> Bool

Returns true if the pool has at least one free handle.
"""
has_capacity(pool::HotPool)::Bool = !isempty(pool.free_list)

"""
    available_count(pool::HotPool) -> Int

Returns the number of available (free) handles.
"""
available_count(pool::HotPool)::Int = length(pool.free_list)
