"""Stateless Stage-0 fixed-rule DCP."""
struct FixedRuleController <: DCP end
const FIXED_RULE_CONTROLLER = FixedRuleController()

function decide(::FixedRuleController, snapshot::Snapshot)::LifecycleAction
    if snapshot.allocated && !snapshot.superplastic &&
       snapshot.consecutive_above_yield >= snapshot.k_yield &&
       snapshot.melt_budget_available
        return MeltAction(snapshot.site_index)
    end

    if snapshot.allocated && snapshot.superplastic &&
       snapshot.consecutive_stable >= snapshot.k_settle
        return CommitAction(snapshot.site_index)
    end

    return NO_ACTION
end
