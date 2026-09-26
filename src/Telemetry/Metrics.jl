"""
    TelemetrySummary

Immutable aggregate view of a Stage-0 developmental event trace.

Metrics are derived observations only. They must never feed back into the
substrate, constitutive law, DCP, or exposure policy.
"""
struct TelemetrySummary
    melt_count::Int
    commit_count::Int
    nonzero_prior_remelts::Int
    commit_flip_count::Int
    total_zcs_lesion::Float64
    total_hardening::Float64
    completed_superplastic_cycles::Int
    mean_superplastic_duration::Union{Nothing,Float64}
    first_delta_tick::Union{Nothing,Int64}
    wake_tick::Union{Nothing,Int64}
    credit_unlock_tick::Union{Nothing,Int64}
end

"""Return the number of applied MELT transitions in an event trace."""
melt_count(events::AbstractVector{<:DevelopmentalEvent})::Int =
    count(event -> event isa MeltEvent || event isa FPMeltEvent, events)

"""Return the number of applied COMMIT transitions in an event trace."""
commit_count(events::AbstractVector{<:DevelopmentalEvent})::Int =
    count(event -> event isa CommitEvent || event isa FPCommitEvent, events)

"""
    nonzero_prior_remelt_count(events)

Count MELT transitions whose prior committed state was nonzero.

This is the divergence-fuel metric for the ZCS/VPS comparison: remelting a
site whose prior committed value is 0 does not distinguish the two exposure
policies.
"""
nonzero_prior_remelt_count(events::AbstractVector{<:DevelopmentalEvent})::Int =
    count(event -> (event isa MeltEvent && event.prior_q != 0) ||
                   (event isa FPMeltEvent && event.prior_w != 0.0f0), events)

"""
    commit_flip_count(events)

Count reconsolidations whose committed value differs from the prior value.
"""
commit_flip_count(events::AbstractVector{<:DevelopmentalEvent})::Int =
    count(event -> (event isa CommitEvent && event.prior_q != event.committed_q) ||
                   (event isa FPCommitEvent && event.prior_w != event.committed_w),
        events)

"""Sum immediate ZCS exposure-lesion magnitudes across all MELT events."""
function zcs_lesion_total(events::AbstractVector{<:DevelopmentalEvent})::Float64
    total = 0.0
    for event in events
        if event isa MeltEvent || event isa FPMeltEvent
            total += Float64(event.zcs_lesion_size)
        end
    end
    return total
end

"""Sum all mandatory work-hardening increments observed at COMMIT events."""
function hardening_total(events::AbstractVector{<:DevelopmentalEvent})::Float64
    total = 0.0
    for event in events
        if event isa CommitEvent || event isa FPCommitEvent
            total += Float64(event.yield_after - event.yield_before)
        end
    end
    return total
end

function _require_nondecreasing_ticks(events::AbstractVector{<:DevelopmentalEvent})
    isempty(events) && return nothing

    previous_tick = event_tick(first(events))
    for event in Iterators.drop(events, 1)
        tick = event_tick(event)
        tick >= previous_tick ||
            error("HardFailure: developmental event trace must be ordered by nondecreasing tick")
        previous_tick = tick
    end
    return nothing
end

"""
    milestone_tick(events, kind)

Return the unique tick recorded for `kind`, or `nothing` if the milestone has
not occurred.

The frozen Stage-0 protocol defines milestones as first-occurrence events, so
multiple records for the same milestone are treated as trace corruption rather
than silently selecting one.
"""
function milestone_tick(events::AbstractVector{<:DevelopmentalEvent},
    kind::MilestoneKind)::Union{Nothing,Int64}
    found = nothing
    for event in events
        event isa MilestoneEvent || continue
        event.kind == kind || continue
        found === nothing ||
            error("HardFailure: milestone $kind was recorded more than once")
        found = event.tick
    end
    return found
end

"""Return the first residual-movement tick, or `nothing` if not yet observed."""
first_delta_tick(events::AbstractVector{<:DevelopmentalEvent}) =
    milestone_tick(events, FIRST_DELTA)

"""Return the first nonzero committed/exposed phenotype tick, or `nothing`."""
wake_tick(events::AbstractVector{<:DevelopmentalEvent}) =
    milestone_tick(events, PHENOTYPIC_WAKE)

"""Return the first tick on which upstream credit becomes nonzero, or `nothing`."""
credit_unlock_tick(events::AbstractVector{<:DevelopmentalEvent}) =
    milestone_tick(events, CREDIT_UNLOCK)

"""
    superplastic_durations(events)

Return completed explicit MELT→COMMIT durations, measured in ticks.

Only intervals whose onset is represented by a `MeltEvent` are included. The
initial Stage-0 seed begins superplastic without a MELT transition, so its
initial seed→first-COMMIT interval is intentionally excluded. Likewise, a MELT
that remains superplastic at the end of a trace is not counted as a completed
cycle.

A second MELT for the same site before COMMIT is a lifecycle inconsistency and
raises `HardFailure`.
"""
function superplastic_durations(
    events::AbstractVector{<:DevelopmentalEvent}
)::Vector{Int64}
    _require_nondecreasing_ticks(events)

    open_melts = Dict{Int32,Int64}()
    durations = Int64[]

    for event in events
        if event isa MeltEvent || event isa FPMeltEvent
            haskey(open_melts, event.site_index) &&
                error("HardFailure: site $(event.site_index) melted twice without an intervening commit")
            open_melts[event.site_index] = event.tick
        elseif event isa CommitEvent || event isa FPCommitEvent
            haskey(open_melts, event.site_index) || continue
            start_tick = pop!(open_melts, event.site_index)
            duration = event.tick - start_tick
            duration >= 0 ||
                error("HardFailure: commit precedes melt for site $(event.site_index)")
            push!(durations, duration)
        end
    end

    return durations
end

"""
    mean_superplastic_duration(events)

Return the arithmetic mean duration of completed explicit MELT→COMMIT cycles,
or `nothing` when the trace contains no completed explicit cycle.
"""
function mean_superplastic_duration(
    events::AbstractVector{<:DevelopmentalEvent}
)::Union{Nothing,Float64}
    durations = superplastic_durations(events)
    isempty(durations) && return nothing
    return Float64(sum(durations)) / length(durations)
end

"""
    summarize_events(events)

Derive a compact immutable summary from a developmental event trace in a single O(N)
pass. Tick ordering is validated inline; no separate pre-scan is required.
"""
function summarize_events(
    events::AbstractVector{<:DevelopmentalEvent}
)::TelemetrySummary
    melts = 0
    commits = 0
    remelts = 0
    flips = 0
    zcs_lesion = 0.0
    hardening = 0.0

    first_delta = nothing
    wake = nothing
    credit_unlock = nothing

    open_melts = Dict{Int32,Int64}()
    duration_sum = Int64(0)
    duration_count = 0

    previous_tick = Int64(-1)

    for event in events
        tick = event_tick(event)
        tick >= previous_tick ||
            error("HardFailure: developmental event trace must be ordered by nondecreasing tick")
        previous_tick = tick

        if event isa MeltEvent
            melts += 1
            event.prior_q != 0 && (remelts += 1)
            zcs_lesion += Float64(event.zcs_lesion_size)

            haskey(open_melts, event.site_index) &&
                error("HardFailure: duplicate MELT for site $(event.site_index) before COMMIT")
            open_melts[event.site_index] = tick
        elseif event isa FPMeltEvent
            melts += 1
            event.prior_w != 0.0f0 && (remelts += 1)
            zcs_lesion += Float64(event.zcs_lesion_size)

            haskey(open_melts, event.site_index) &&
                error("HardFailure: duplicate MELT for site $(event.site_index) before COMMIT")
            open_melts[event.site_index] = tick
        elseif event isa CommitEvent
            commits += 1
            event.prior_q != event.committed_q && (flips += 1)
            hardening += Float64(event.yield_after - event.yield_before)

            if haskey(open_melts, event.site_index)
                duration_sum += tick - open_melts[event.site_index]
                duration_count += 1
                delete!(open_melts, event.site_index)
            end
        elseif event isa FPCommitEvent
            commits += 1
            event.prior_w != event.committed_w && (flips += 1)
            hardening += Float64(event.yield_after - event.yield_before)

            if haskey(open_melts, event.site_index)
                duration_sum += tick - open_melts[event.site_index]
                duration_count += 1
                delete!(open_melts, event.site_index)
            end
        elseif event isa MilestoneEvent
            if event.kind == FIRST_DELTA
                first_delta === nothing || error("HardFailure: milestone FIRST_DELTA recorded more than once")
                first_delta = tick
            elseif event.kind == PHENOTYPIC_WAKE
                wake === nothing || error("HardFailure: milestone PHENOTYPIC_WAKE recorded more than once")
                wake = tick
            elseif event.kind == CREDIT_UNLOCK
                credit_unlock === nothing || error("HardFailure: milestone CREDIT_UNLOCK recorded more than once")
                credit_unlock = tick
            end
        end
    end

    mean_duration = duration_count == 0 ? nothing : Float64(duration_sum) / duration_count

    return TelemetrySummary(
        melts,
        commits,
        remelts,
        flips,
        zcs_lesion,
        hardening,
        duration_count,
        mean_duration,
        first_delta,
        wake,
        credit_unlock,
    )
end
