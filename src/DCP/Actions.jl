"""Immutable lifecycle actions emitted by the DCP."""
abstract type Action end
struct NoAction <: Action end
struct MeltAction <: Action
    site_index::Int32
end
struct CommitAction <: Action
    site_index::Int32
end

const NO_ACTION = NoAction()
make_no_action() = NO_ACTION
make_melt(site_index::Integer) = MeltAction(Int32(site_index))
make_commit(site_index::Integer) = CommitAction(Int32(site_index))

function _checked_site_index(substrate::SubstrateState, site_index::Integer)::Int
    i = Int(site_index)
    1 <= i <= length(substrate.sites) || error("HardFailure: action site index $i out of bounds")
    return i
end

function apply_action!(substrate::SubstrateState, ::NoAction, ::ExposurePolicy)
    return nothing
end

function apply_action!(substrate::SubstrateState, action::MeltAction, ::ExposurePolicy)
    i = _checked_site_index(substrate, action.site_index)
    site = substrate.sites[i]
    site.allocated && !site.superplastic ||
        error("HardFailure: MELT requires an allocated consolidated site")
    has_capacity(substrate.pool) || error("HardFailure: MELT requested with no hot capacity")
    current_superplastic = count(s -> s.allocated && s.superplastic, substrate.sites)
    current_superplastic < Int(substrate.max_superplastic) ||
        error("HardFailure: MELT would exceed global superplastic budget")

    # All checks precede the state mutation. Allocation initializes δ to zero.
    handle = allocate!(substrate.pool, 0.0f0)
    site.superplastic = true
    site.hot_handle = handle
    reset_lifecycle_counters!(substrate.telemetry[i])
    check_invariants(substrate)
    return nothing
end

function apply_action!(substrate::SubstrateState, action::CommitAction,
                       policy::ExposurePolicy)
    i = _checked_site_index(substrate, action.site_index)
    site = substrate.sites[i]
    site.allocated && site.superplastic ||
        error("HardFailure: COMMIT requires an allocated superplastic site")
    is_valid_handle(substrate.pool, site.hot_handle) ||
        error("HardFailure: COMMIT site owns invalid hot handle")

    delta = get_residual(substrate.pool, site.hot_handle)
    new_q = ternary_round(commit_base(site, policy) + delta)
    old_handle = site.hot_handle
    region = get_region_for_site(substrate.region_map, i)

    # Commit is exposed only after this tick's immutable exposure snapshot has
    # already been consumed by the forward/backward path.
    release!(substrate.pool, old_handle)
    site.q = new_q
    site.superplastic = false
    site.hot_handle = Int32(0)
    reset_lifecycle_counters!(substrate.telemetry[i])
    region.yield_up += region.hardening_increment

    region.yield_up > region.settle_down ||
        error("HardFailure: hardening violated yield/settle hysteresis")
    check_invariants(substrate)
    return nothing
end
