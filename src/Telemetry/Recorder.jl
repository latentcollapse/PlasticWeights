"""
    DevelopmentalRecorder

Observer-only append-only recorder for Stage-0 developmental telemetry.

The recorder is deliberately outside the causal path:
- it does not own substrate/material state,
- it does not choose DCP actions,
- it does not modify exposure semantics,
- and it never feeds metrics back into learning.

Its only mutable state is telemetry bookkeeping: the event trace, first-occurrence
milestone latches, and the last recorded tick used to reject time-reversed traces.
"""
mutable struct DevelopmentalRecorder
    events::Vector{EventRecord}
    first_delta_tick::Union{Nothing,Int64}
    wake_tick::Union{Nothing,Int64}
    credit_unlock_tick::Union{Nothing,Int64}
    last_tick::Int64

    DevelopmentalRecorder() =
        new(EventRecord[], nothing, nothing, nothing, Int64(-1))
end

"""Return a defensive copy of the recorder's current event trace."""
event_trace(recorder::DevelopmentalRecorder)::Vector{EventRecord} =
    copy(recorder.events)

Base.length(recorder::DevelopmentalRecorder) = length(recorder.events)
Base.isempty(recorder::DevelopmentalRecorder) = isempty(recorder.events)

"""
    reset_recorder!(recorder)

Clear only observer state. This has no effect on the substrate.
"""
function reset_recorder!(recorder::DevelopmentalRecorder)
    empty!(recorder.events)
    recorder.first_delta_tick = nothing
    recorder.wake_tick = nothing
    recorder.credit_unlock_tick = nothing
    recorder.last_tick = Int64(-1)
    return recorder
end

function _append_event!(recorder::DevelopmentalRecorder,
    event::EventRecord)
    tick = event_tick(event)
    tick >= recorder.last_tick ||
        error("HardFailure: recorder received tick $tick after tick $(recorder.last_tick)")
    push!(recorder.events, event)
    recorder.last_tick = tick
    return event
end

function _record_milestone_once!(recorder::DevelopmentalRecorder,
    tick::Integer,
    kind::MilestoneKind)::Bool
    t = Int64(tick)
    if kind == FIRST_DELTA
        recorder.first_delta_tick === nothing || return false
        _append_event!(recorder, MilestoneEvent(t, kind))
        recorder.first_delta_tick = t
    elseif kind == PHENOTYPIC_WAKE
        recorder.wake_tick === nothing || return false
        _append_event!(recorder, MilestoneEvent(t, kind))
        recorder.wake_tick = t
    elseif kind == CREDIT_UNLOCK
        recorder.credit_unlock_tick === nothing || return false
        _append_event!(recorder, MilestoneEvent(t, kind))
        recorder.credit_unlock_tick = t
    else
        error("HardFailure: unknown milestone kind $kind")
    end
    return true
end

"""O(1) cached milestone queries for trusted live recorder."""
first_delta_tick(recorder::DevelopmentalRecorder) = recorder.first_delta_tick
wake_tick(recorder::DevelopmentalRecorder) = recorder.wake_tick
credit_unlock_tick(recorder::DevelopmentalRecorder) = recorder.credit_unlock_tick

"""
    record_wake!(recorder, tick, exposures)

Record `PHENOTYPIC_WAKE` at the first tick whose immutable exposure snapshot
contains a nonzero visible material coefficient.

Call this from the tick's exposure-snapshot stage, before lifecycle actions are
applied, so a COMMIT becomes visible only on the following tick.
"""
function record_wake!(recorder::DevelopmentalRecorder,
    tick::Integer,
    exposures::AbstractArray{<:Real})::Bool
    recorder.wake_tick === nothing || return false
    any(x -> !iszero(x), exposures) || return false
    return _record_milestone_once!(recorder, tick, PHENOTYPIC_WAKE)
end

"""
    record_credit_unlock!(recorder, tick, upstream_gradient)

Record `CREDIT_UNLOCK` at the first tick with a nonzero upstream feature
gradient. No tolerance is introduced in the deterministic reference path:
the frozen milestone is "first nonzero upstream gradient."
"""
function record_credit_unlock!(recorder::DevelopmentalRecorder,
    tick::Integer,
    upstream_gradient::AbstractArray{<:Real})::Bool
    recorder.credit_unlock_tick === nothing || return false
    any(x -> !iszero(x), upstream_gradient) || return false
    return _record_milestone_once!(recorder, tick, CREDIT_UNLOCK)
end

"""
    record_first_delta!(recorder, tick, delta_updates)

Record `FIRST_DELTA` at the first tick where at least one material residual
actually moves (`Δδ != 0`).
"""
function record_first_delta!(recorder::DevelopmentalRecorder,
    tick::Integer,
    delta_updates::AbstractArray{<:Real})::Bool
    recorder.first_delta_tick === nothing || return false
    any(x -> !iszero(x), delta_updates) || return false
    return _record_milestone_once!(recorder, tick, FIRST_DELTA)
end

# -----------------------------------------------------------------------------
# Lifecycle observation
# -----------------------------------------------------------------------------
# These records are intentionally internal. They capture just enough pre-action
# state to emit a faithful immutable event after the already-decided action has
# been applied. They never influence whether the action occurs.

abstract type _PendingLifecycleObservation end

struct _PendingMeltObservation <: _PendingLifecycleObservation
    site_index::Int32
    region_id::Int32
    prior_q::Int8
    stress::Float32
    yield_up::Float32
    zcs_lesion_size::Float32
end

struct _PendingCommitObservation <: _PendingLifecycleObservation
    site_index::Int32
    region_id::Int32
    prior_q::Int8
    residual::Float32
    yield_before::Float32
    hardening_increment::Float32
end

"""Concrete union of pre-action lifecycle observations."""
const PendingObservation = Union{Nothing, _PendingMeltObservation, _PendingCommitObservation}

"""
    observe_action_before(substrate, action, policy)

Capture immutable pre-action data needed for telemetry.

This function is read-only with respect to the substrate. The caller remains
responsible for applying the action through `apply_action!`.
"""
observe_action_before(::SubstrateState, ::NoAction, ::ExposurePolicy) = nothing

function observe_action_before(substrate::SubstrateState,
    action::MeltAction,
    policy::ExposurePolicy)
    i = _checked_site_index(substrate, action.site_index)
    site = substrate.sites[i]
    site.allocated && !site.superplastic ||
        error("HardFailure: recorder observed invalid MELT pre-state at site $i")

    region = get_region_for_site(substrate.region_map, i)
    telemetry = substrate.telemetry[i]
    lesion = policy isa ZCS ? abs(Float32(site.q)) : 0.0f0

    return _PendingMeltObservation(
        Int32(i),
        region.id,
        site.q,
        telemetry.stress_ema,
        region.yield_up,
        lesion,
    )
end

function observe_action_before(substrate::SubstrateState,
    action::CommitAction,
    ::ExposurePolicy)
    i = _checked_site_index(substrate, action.site_index)
    site = substrate.sites[i]
    site.allocated && site.superplastic ||
        error("HardFailure: recorder observed invalid COMMIT pre-state at site $i")
    is_valid_handle(substrate.pool, site.hot_handle) ||
        error("HardFailure: recorder observed COMMIT with invalid hot handle")

    region = get_region_for_site(substrate.region_map, i)

    return _PendingCommitObservation(
        Int32(i),
        region.id,
        site.q,
        get_residual(substrate.pool, site.hot_handle),
        region.yield_up,
        region.hardening_increment,
    )
end

"""
    record_action_after!(recorder, tick, pending, substrate)

Validate the post-action state and append the corresponding immutable lifecycle
event. `pending` must come from `observe_action_before` immediately before the
matching `apply_action!` call.
"""
record_action_after!(::DevelopmentalRecorder, ::Integer, ::Nothing,
    ::SubstrateState) = nothing

function record_action_after!(recorder::DevelopmentalRecorder,
    tick::Integer,
    pending::_PendingMeltObservation,
    substrate::SubstrateState)
    i = Int(pending.site_index)
    site = substrate.sites[i]

    site.allocated && site.superplastic ||
        error("HardFailure: MELT post-state is not allocated+superplastic at site $i")
    site.q == pending.prior_q ||
        error("HardFailure: MELT changed committed q at site $i")
    is_valid_handle(substrate.pool, site.hot_handle) ||
        error("HardFailure: MELT post-state has invalid hot handle at site $i")
    get_residual(substrate.pool, site.hot_handle) == 0.0f0 ||
        error("HardFailure: MELT hot residual was not initialized to zero at site $i")

    event = MeltEvent(
        tick,
        i,
        pending.region_id,
        pending.prior_q,
        pending.stress,
        pending.yield_up,
        pending.zcs_lesion_size,
    )
    return _append_event!(recorder, event)
end

function record_action_after!(recorder::DevelopmentalRecorder,
    tick::Integer,
    pending::_PendingCommitObservation,
    substrate::SubstrateState)
    i = Int(pending.site_index)
    site = substrate.sites[i]
    region = get_region(substrate.region_map, pending.region_id)

    site.allocated && !site.superplastic ||
        error("HardFailure: COMMIT post-state is not allocated+consolidated at site $i")
    site.hot_handle == 0 ||
        error("HardFailure: COMMIT post-state retained a hot handle at site $i")

    expected_yield_after = pending.yield_before + pending.hardening_increment
    region.yield_up == expected_yield_after ||
        error("HardFailure: COMMIT hardening mismatch at site $i")

    event = CommitEvent(
        tick,
        i,
        pending.region_id,
        pending.prior_q,
        site.q,
        pending.residual,
        pending.yield_before,
        region.yield_up,
    )
    return _append_event!(recorder, event)
end

"""Allow the existing summary API to consume a recorder directly."""
summarize_events(recorder::DevelopmentalRecorder)::TelemetrySummary =
    summarize_events(recorder.events)
