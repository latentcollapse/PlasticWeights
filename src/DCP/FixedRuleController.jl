"""
    FixedRuleController

A simple rule-based DCP controller for Stage-0.

DCP API contract:
    action = decide(dcp, snapshot)

The DCP sees only immutable declared snapshot fields.
Lifecycle application is separate via apply_action!
"""
struct FixedRuleController <: DCP
    melt_threshold::Float32
    commit_threshold::Float32
    
    FixedRuleController(melt_threshold::Real=0.5, commit_threshold::Real=0.8) =
        new(Float32(melt_threshold), Float32(commit_threshold))
end

"""
    decide(dcp::FixedRuleController, snapshot::Snapshot) -> Action

Decides an action based on fixed rules applied to the snapshot.

Rules:
- If residual > melt_threshold and not superplastic: MeltAction
- If residual < commit_threshold and superplastic: CommitAction
- Otherwise: NoAction

This is a pure function with no side effects.
"""
function decide(dcp::FixedRuleController, snapshot::Snapshot)::Action
    # Rule 1: Melt if residual exceeds threshold and not already superplastic
    if !snapshot.superplastic && snapshot.residual > dcp.melt_threshold
        return make_melt(snapshot.site_index)
    end
    
    # Rule 2: Commit if residual below threshold and superplastic
    if snapshot.superplastic && snapshot.residual < dcp.commit_threshold
        return make_commit(snapshot.site_index)
    end
    
    # Default: no action
    return NO_ACTION
end

# Default controller
const DEFAULT_DCP = FixedRuleController(0.5f0, 0.8f0)
