"""
    PhaseMachineController(k_commit=2)

E0c symbolic phase machine (Pass 2 of the gate-fix programme).

Same lifecycle alphabet as the FixedRuleController — the constitutive law still
cannot commit, melt, allocate, or release; the DCP is still the only authority —
but transitions are guarded by the site's persistent phase record and by
dwell/budget/conflict conditions:

- **Conflict invalidation (anti-ossification, mandatory):** a committed site
  whose conflict certificate reaches `region.conflict_k` (sustained consistent
  above-floor load OPPOSITE its consolidation reference) MUST melt. Permanent
  rigidity is not a legal steady state.
- **Ramp-gated commit:** a superplastic site may commit only after the settle
  certificate (`k_settle`) AND a dwell period of at least `k_commit` ticks
  since its melt, plus the melt margin. Liveness is preserved; waves are not.
- **Guarded transitions:** every transition re-checks phase consistency;
  illegal transitions are HardFailures (same discipline as the substrate
  invariants).

`k_commit` is the minimum plastic dwell before commit (hysteresis against
chattering); the conflict certificate's `conflict_k` lives on the region.
"""
struct PhaseMachineController <: DCP
    k_commit::Int32
    function PhaseMachineController(k_commit::Integer=2)
        k_commit >= 1 || error("HardFailure: PhaseMachineController k_commit must be >= 1")
        new(Int32(k_commit))
    end
end

const PHASE_MACHINE_CONTROLLER = PhaseMachineController()

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

function decide(controller::PhaseMachineController, snapshot::FPSnapshot)::LifecycleAction
    # Committed sites: the phase machine's invalidation duty.
    if snapshot.allocated && !snapshot.superplastic
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted >= snapshot.conflict_k
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: commit behind settle + dwell + melt margin.
    if snapshot.allocated && snapshot.superplastic
        if snapshot.consecutive_stable >= snapshot.k_settle &&
           snapshot.stress_ema < snapshot.yield_up
            # Dwell (hysteresis against chattering): the site must have been
            # plastic for at least k_commit ticks. plastic_since is stamped by
            # the kernel at melt time; plastic_since == 0 means unstamped
            # (direct apply_action! calls without a tick, as in some tests),
            # where the dwell is vacuously satisfied.
            plastic_since = snapshot.plastic_since
            (plastic_since == Int32(0) ||
             (snapshot.tick - plastic_since) >= controller.k_commit) ||
                return NO_ACTION
            return CommitAction(snapshot.site_index)
        end
    end

    return NO_ACTION
end
