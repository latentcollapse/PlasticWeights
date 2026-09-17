"""
    FixedRuleController

A simple rule-based DCP controller for Stage-0.

DCP API contract:
    action = decide(dcp, snapshot)

The DCP sees only immutable declared snapshot fields.
Lifecycle application is separate via apply_action!

Rules (per spec):
- consolidated allocated site -> MELT iff consecutive_above_yield >= k_yield and budget/hot slot permits
- superplastic site -> COMMIT iff consecutive_stable >= k_settle
- otherwise HOLD

The DCP must NOT decide from raw δ magnitude.
"""
struct FixedRuleController <: DCP end

const FIXED_RULE_CONTROLLER = FixedRuleController()

"""
    decide(dcp::FixedRuleController, snapshot::Snapshot) -> Action

Decides an action based on fixed rules applied to the snapshot.

Rules:
- If site is consolidated (allocated && !superplastic) AND 
  consecutive_above_yield >= k_yield AND has_hot_capacity -> MeltAction
- If site is superplastic AND consecutive_stable >= k_settle -> CommitAction
- Otherwise -> NoAction

This is a pure function with no side effects.
"""
function decide(dcp::FixedRuleController, snapshot::Snapshot)::Action
    # Rule 1: Melt if consolidated, sustained above-yield, and hot capacity available
    if snapshot.allocated && !snapshot.superplastic &&
       snapshot.consecutive_above_yield >= snapshot.k_yield &&
       snapshot.has_hot_capacity
        return make_melt(snapshot.site_index)
    end
    
    # Rule 2: Commit if superplastic and sustained stable
    if snapshot.superplastic && snapshot.consecutive_stable >= snapshot.k_settle
        return make_commit(snapshot.site_index)
    end
    
    # Default: no action (HOLD)
    return NO_ACTION
end
