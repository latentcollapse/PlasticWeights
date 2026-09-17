"""
    Actions

DCP actions for substrate transitions.

Actions are immutable declarations of intended changes.
Applied atomically in step 12 of the tick order.
"""
abstract type Action end

"""
    NoAction <: Action

No operation - site remains unchanged.
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

"""
    HardenAction <: Action

Applies hardening to a site.
"""
struct HardenAction <: Action
    site_index::Int32
    hardness_delta::Float32
end

"""
    SetQAction <: Action

Sets the ternary state q of a site.
"""
struct SetQAction <: Action
    site_index::Int32
    new_q::Int8
end

"""
    CompositeAction <: Action

Combines multiple actions for a single site.
"""
struct CompositeAction <: Action
    site_index::Int32
    actions::Vector{Action}
end

# Default no-action
const NO_ACTION = NoAction()

# Helper to create action types
make_no_action() = NO_ACTION
make_melt(site_index::Integer) = MeltAction(Int32(site_index))
make_commit(site_index::Integer) = CommitAction(Int32(site_index))
make_harden(site_index::Integer, delta::Real) = HardenAction(Int32(site_index), Float32(delta))
make_set_q(site_index::Integer, q::Integer) = SetQAction(Int32(site_index), Int8(q))
