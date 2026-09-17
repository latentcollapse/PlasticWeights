"""
    Actions

DCP actions for substrate transitions.

Actions are immutable declarations of intended changes.
Applied atomically in step 12 of the tick order.

Rules:
- consolidated allocated site -> MELT iff consecutive_above_yield >= k_yield and budget/hot slot permits
- superplastic site -> COMMIT iff consecutive_stable >= k_settle
- otherwise HOLD
"""
abstract type Action end

"""
    NoAction <: Action

No operation - site remains unchanged (HOLD).
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

# Default no-action
const NO_ACTION = NoAction()

# Helper to create action types
make_no_action() = NO_ACTION
make_melt(site_index::Integer) = MeltAction(Int32(site_index))
make_commit(site_index::Integer) = CommitAction(Int32(site_index))
