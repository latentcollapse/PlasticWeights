"""
    HotPool(capacity)

Deterministic FP32 residual storage for superplastic sites. Handles are
`1:capacity`; handle 0 is an invalid sentinel used only by cold sites.
"""
mutable struct HotPool
    residuals::Vector{Float32}
    free_list::Vector{Int32}
    allocated::BitVector
    capacity::Int32

    function HotPool(capacity::Integer)
        capacity > 0 || error("HardFailure: HotPool capacity must be positive, got $capacity")
        residuals = zeros(Float32, capacity)
        # `pop!` therefore yields 1,2,3,... on a fresh pool. Released handles are
        # reused LIFO. Both behaviours are deterministic.
        free_list = Int32.(collect(capacity:-1:1))
        allocated = falses(capacity)
        new(residuals, free_list, allocated, Int32(capacity))
    end
end

num_allocated(pool::HotPool)::Int = count(identity, pool.allocated)
available_count(pool::HotPool)::Int = length(pool.free_list)
has_capacity(pool::HotPool)::Bool = !isempty(pool.free_list)

function is_valid_handle(pool::HotPool, handle::Integer)::Bool
    h = Int(handle)
    return 1 <= h <= Int(pool.capacity) && pool.allocated[h]
end

function allocate!(pool::HotPool, initial_residual::Real=0.0f0)::Int32
    isempty(pool.free_list) && error("HardFailure: HotPool exhausted")
    handle = pop!(pool.free_list)
    h = Int(handle)
    pool.allocated[h] && error("HardFailure: attempted double allocation of handle $handle")
    pool.allocated[h] = true
    pool.residuals[h] = Float32(initial_residual)
    return handle
end

function release!(pool::HotPool, handle::Integer)
    h = Int(handle)
    1 <= h <= Int(pool.capacity) || error("HardFailure: invalid handle $handle for release")
    pool.allocated[h] || error("HardFailure: attempted to release non-allocated handle $handle")
    pool.allocated[h] = false
    pool.residuals[h] = 0.0f0
    push!(pool.free_list, Int32(h))
    return nothing
end

function get_residual(pool::HotPool, handle::Integer)::Float32
    is_valid_handle(pool, handle) || error("HardFailure: invalid/unallocated handle $handle")
    return pool.residuals[Int(handle)]
end

function set_residual!(pool::HotPool, handle::Integer, value::Real)
    is_valid_handle(pool, handle) || error("HardFailure: invalid/unallocated handle $handle")
    pool.residuals[Int(handle)] = Float32(value)
    return nothing
end

function integrate_residual!(pool::HotPool, handle::Integer, delta_delta::Real)::Float32
    new_value = get_residual(pool, handle) + Float32(delta_delta)
    set_residual!(pool, handle, new_value)
    return new_value
end

function check_invariants(pool::HotPool)
    cap = Int(pool.capacity)
    length(pool.residuals) == cap || error("HardFailure: residual array/capacity mismatch")
    length(pool.allocated) == cap || error("HardFailure: allocation array/capacity mismatch")
    available_count(pool) + num_allocated(pool) == cap ||
        error("HardFailure: free + allocated != capacity")
    length(unique(pool.free_list)) == length(pool.free_list) ||
        error("HardFailure: duplicate handle in free_list")
    for handle in pool.free_list
        h = Int(handle)
        1 <= h <= cap || error("HardFailure: free handle $handle out of range")
        !pool.allocated[h] || error("HardFailure: handle $handle is both free and allocated")
    end
    return true
end
