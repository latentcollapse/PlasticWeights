"""
    Events

Telemetry event types for tracking substrate dynamics.

Logged at step 15 of the tick order.
"""
abstract type Event end

struct TickEvent <: Event
    tick::Int32
    timestamp::Float64
end

struct MeltEvent <: Event
    tick::Int32
    site_index::Int32
    region_id::Int32
    residual::Float32
end

struct CommitEvent <: Event
    tick::Int32
    site_index::Int32
    region_id::Int32
    residual::Float32
end

struct HardeningEvent <: Event
    tick::Int32
    site_index::Int32
    hardness_delta::Float32
end

struct QChangeEvent <: Event
    tick::Int32
    site_index::Int32
    old_q::Int8
    new_q::Int8
end

struct LossEvent <: Event
    tick::Int32
    loss::Float32
    gradient_norm::Float32
end

# Event factory functions
make_tick_event(tick::Integer, timestamp::Real) = TickEvent(Int32(tick), Float64(timestamp))
make_melt_event(tick::Integer, site::Integer, region::Integer, res::Real) = 
    MeltEvent(Int32(tick), Int32(site), Int32(region), Float32(res))
make_commit_event(tick::Integer, site::Integer, region::Integer, res::Real) =
    CommitEvent(Int32(tick), Int32(site), Int32(region), Float32(res))
make_hardening_event(tick::Integer, site::Integer, delta::Real) =
    HardeningEvent(Int32(tick), Int32(site), Float32(delta))
make_q_change_event(tick::Integer, site::Integer, old_q::Integer, new_q::Integer) =
    QChangeEvent(Int32(tick), Int32(site), Int8(old_q), Int8(new_q))
make_loss_event(tick::Integer, loss::Real, grad_norm::Real) =
    LossEvent(Int32(tick), Float32(loss), Float32(grad_norm))
