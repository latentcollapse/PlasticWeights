"""Stateless Stage-0 fixed-rule DCP."""
struct FixedRuleController <: DCP end
const FIXED_RULE_CONTROLLER = FixedRuleController()

function decide(::FixedRuleController, snapshot::Snapshot)::LifecycleAction
    if snapshot.allocated && !snapshot.superplastic &&
       snapshot.consecutive_above_yield >= snapshot.k_yield &&
       snapshot.melt_budget_available
        return MeltAction(snapshot.site_index)
    end

    # D1 fix (E0 report §8.1): commit additionally requires a melt margin.
    # The melt gate reads consecutive_above_yield (fired when stress_ema exceeds
    # yield_up); a commit landing where a melt would be legal means the site is
    # nominally stable while standing inside melt territory — commit is
    # deferred until the site's own stress EMA sits strictly below yield_up.
    # This is the DCP-side half of the commit/melt hysteresis pair; the other
    # half is the consistency certificate in update_counters!.
    if snapshot.allocated && snapshot.superplastic &&
       snapshot.consecutive_stable >= snapshot.k_settle &&
       snapshot.stress_ema < snapshot.yield_up
        return CommitAction(snapshot.site_index)
    end

    return NO_ACTION
end

function decide(::FixedRuleController, snapshot::FPSnapshot)::LifecycleAction
    if snapshot.allocated && !snapshot.superplastic &&
       snapshot.consecutive_above_yield >= snapshot.k_yield &&
       snapshot.melt_budget_available
        return MeltAction(snapshot.site_index)
    end

    if snapshot.allocated && snapshot.superplastic &&
       snapshot.consecutive_stable >= snapshot.k_settle &&
       snapshot.stress_ema < snapshot.yield_up
        return CommitAction(snapshot.site_index)
    end

    return NO_ACTION
end
