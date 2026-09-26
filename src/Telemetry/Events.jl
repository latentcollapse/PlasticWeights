"""
    DevelopmentalEvent

Abstract root for immutable Stage-0 telemetry events.

Events are observations only: they must never own mutable substrate state or
participate in lifecycle decisions. Their purpose is to make developmental
history explicit and replayable without creating a second source of truth.
"""
abstract type DevelopmentalEvent end

"""Named first-occurrence milestones required by the frozen Stage-0 spec."""
@enum MilestoneKind::UInt8 begin
    FIRST_DELTA = 0x01
    PHENOTYPIC_WAKE = 0x02
    CREDIT_UNLOCK = 0x03
end

"""
    MilestoneEvent(tick, kind)

Records the first tick on which a run-level developmental milestone occurs.
The recorder/metrics layer is responsible for enforcing first-occurrence-only
semantics; this type is deliberately an immutable value record.
"""
struct MilestoneEvent <: DevelopmentalEvent
    tick::Int64
    kind::MilestoneKind

    function MilestoneEvent(tick::Integer, kind::MilestoneKind)
        tick >= 0 || error("HardFailure: event tick must be >= 0, got $tick")
        new(Int64(tick), kind)
    end
end

"""
    MeltEvent

Immutable record of an applied MELT transition.

`prior_q` is mandatory because the Stage-0 protocol requires every remelt to
be classified by its prior committed ternary value. `zcs_lesion_size` is the
immediate exposure lesion attributable to ZCS for this melt (0 for VPS, and
also 0 when a ZCS melt starts from q=0).
"""
struct MeltEvent <: DevelopmentalEvent
    tick::Int64
    site_index::Int32
    region_id::Int32
    prior_q::Int8
    stress::Float32
    yield_up::Float32
    zcs_lesion_size::Float32

    function MeltEvent(tick::Integer,
                       site_index::Integer,
                       region_id::Integer,
                       prior_q::Integer,
                       stress::Real,
                       yield_up::Real,
                       zcs_lesion_size::Real)
        tick >= 0 || error("HardFailure: event tick must be >= 0, got $tick")
        site_index >= 1 || error("HardFailure: event site_index must be >= 1")
        region_id >= 1 || error("HardFailure: event region_id must be >= 1")
        prior_q in (-1, 0, 1) ||
            error("HardFailure: melt prior_q must be ternary, got $prior_q")

        s = Float32(stress)
        yu = Float32(yield_up)
        lesion = Float32(zcs_lesion_size)
        s >= 0.0f0 || error("HardFailure: melt stress must be >= 0")
        yu >= 0.0f0 || error("HardFailure: melt yield_up must be >= 0")
        lesion >= 0.0f0 || error("HardFailure: ZCS lesion size must be >= 0")

        new(Int64(tick), Int32(site_index), Int32(region_id), Int8(prior_q),
            s, yu, lesion)
    end
end

"""
    CommitEvent

Immutable record of an applied COMMIT transition.

The event keeps both the previously committed ternary state and the new state,
plus the hot residual used for reconsolidation and the region yield immediately
before/after mandatory work-hardening. This is enough to derive
reconsolidation counts, flip-flop counts, and hardening trajectories without
making telemetry authoritative over model state.
"""
struct CommitEvent <: DevelopmentalEvent
    tick::Int64
    site_index::Int32
    region_id::Int32
    prior_q::Int8
    committed_q::Int8
    residual::Float32
    yield_before::Float32
    yield_after::Float32

    function CommitEvent(tick::Integer,
                         site_index::Integer,
                         region_id::Integer,
                         prior_q::Integer,
                         committed_q::Integer,
                         residual::Real,
                         yield_before::Real,
                         yield_after::Real)
        tick >= 0 || error("HardFailure: event tick must be >= 0, got $tick")
        site_index >= 1 || error("HardFailure: event site_index must be >= 1")
        region_id >= 1 || error("HardFailure: event region_id must be >= 1")
        prior_q in (-1, 0, 1) ||
            error("HardFailure: commit prior_q must be ternary, got $prior_q")
        committed_q in (-1, 0, 1) ||
            error("HardFailure: committed_q must be ternary, got $committed_q")

        yb = Float32(yield_before)
        ya = Float32(yield_after)
        yb >= 0.0f0 || error("HardFailure: yield_before must be >= 0")
        ya >= yb ||
            error("HardFailure: commit yield_after must be >= yield_before")

        new(Int64(tick), Int32(site_index), Int32(region_id), Int8(prior_q),
            Int8(committed_q), Float32(residual), yb, ya)
    end
end

"""
    FPMeltEvent

Immutable record of an applied MELT transition for a continuous FP site.
"""
struct FPMeltEvent <: DevelopmentalEvent
    tick::Int64
    site_index::Int32
    region_id::Int32
    prior_w::Float32
    stress::Float32
    yield_up::Float32
    zcs_lesion_size::Float32

    function FPMeltEvent(tick::Integer,
                         site_index::Integer,
                         region_id::Integer,
                         prior_w::Real,
                         stress::Real,
                         yield_up::Real,
                         zcs_lesion_size::Real)
        tick >= 0 || error("HardFailure: event tick must be >= 0, got $tick")
        site_index >= 1 || error("HardFailure: event site_index must be >= 1")
        region_id >= 1 || error("HardFailure: event region_id must be >= 1")
        pw = Float32(prior_w)
        isfinite(pw) || error("HardFailure: melt prior_w must be finite, got $pw")

        s = Float32(stress)
        yu = Float32(yield_up)
        lesion = Float32(zcs_lesion_size)
        s >= 0.0f0 || error("HardFailure: melt stress must be >= 0")
        yu >= 0.0f0 || error("HardFailure: melt yield_up must be >= 0")
        lesion >= 0.0f0 || error("HardFailure: ZCS lesion size must be >= 0")

        new(Int64(tick), Int32(site_index), Int32(region_id), pw,
            s, yu, lesion)
    end
end

"""
    FPCommitEvent

Immutable record of an applied COMMIT transition for a continuous FP site.
"""
struct FPCommitEvent <: DevelopmentalEvent
    tick::Int64
    site_index::Int32
    region_id::Int32
    prior_w::Float32
    committed_w::Float32
    residual::Float32
    yield_before::Float32
    yield_after::Float32

    function FPCommitEvent(tick::Integer,
                           site_index::Integer,
                           region_id::Integer,
                           prior_w::Real,
                           committed_w::Real,
                           residual::Real,
                           yield_before::Real,
                           yield_after::Real)
        tick >= 0 || error("HardFailure: event tick must be >= 0, got $tick")
        site_index >= 1 || error("HardFailure: event site_index must be >= 1")
        region_id >= 1 || error("HardFailure: event region_id must be >= 1")
        pw = Float32(prior_w)
        cw = Float32(committed_w)
        isfinite(pw) || error("HardFailure: commit prior_w must be finite, got $pw")
        isfinite(cw) || error("HardFailure: commit committed_w must be finite, got $cw")

        yb = Float32(yield_before)
        ya = Float32(yield_after)
        yb >= 0.0f0 || error("HardFailure: yield_before must be >= 0")
        ya >= yb ||
            error("HardFailure: commit yield_after must be >= yield_before")

        new(Int64(tick), Int32(site_index), Int32(region_id), pw,
            cw, Float32(residual), yb, ya)
    end
end

"""Return the canonical tick associated with any developmental event."""
event_tick(event::DevelopmentalEvent)::Int64 = event.tick

"""Return the site index for a lifecycle event, or `nothing` for run milestones."""
event_site(::MilestoneEvent) = nothing
event_site(event::MeltEvent)::Int = Int(event.site_index)
event_site(event::CommitEvent)::Int = Int(event.site_index)
event_site(event::FPMeltEvent)::Int = Int(event.site_index)
event_site(event::FPCommitEvent)::Int = Int(event.site_index)

"""True for events corresponding to an applied material lifecycle transition."""
is_lifecycle_event(::DevelopmentalEvent)::Bool = false
is_lifecycle_event(::MeltEvent)::Bool = true
is_lifecycle_event(::CommitEvent)::Bool = true
is_lifecycle_event(::FPMeltEvent)::Bool = true
is_lifecycle_event(::FPCommitEvent)::Bool = true

"""Concrete isbits union of all possible Stage-0 and Continuous-FP developmental events."""
const EventRecord = Union{MilestoneEvent, MeltEvent, CommitEvent, FPMeltEvent, FPCommitEvent}
