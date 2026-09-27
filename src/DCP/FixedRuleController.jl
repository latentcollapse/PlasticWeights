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

"""
    TagRoutingController(k_commit=2)

E0d (Pass 3): explicit consolidation-tag routing. Identical to the
PhaseMachineController except for one asymmetry: a MELTED site whose tag
agrees with the current load direction (its consolidation reference matches
the signed stress) has its commit DWELL REMITTED — it may re-commit on the
first settle-certificate tick, without waiting k_commit ticks.

Rationale (E1c-D6): the return-trip benefit is consolidation-memory — sites
recommitting toward their prior material make revisited tasks cheap. The
melt path already preserves the tag; this controller spends that memory as
fast-commit priority for previously-validated material, while opposed load
still melts sites at exactly the baseline pace (routing only touches the
COMMIT side, so anti-ossification strength is unchanged by construction).
"""
struct TagRoutingController <: DCP
    k_commit::Int32
    function TagRoutingController(k_commit::Integer=2)
        k_commit >= 1 || error("HardFailure: TagRoutingController k_commit must be >= 1")
        new(Int32(k_commit))
    end
end

const TAG_ROUTING_CONTROLLER = TagRoutingController()

"""
    UndirectedController(k_commit=2)

E0d ablation arm: identical to the PhaseMachineController except the conflict
certificate is DIRECTION-BLIND (fires on sustained consistent above-floor
load regardless of its relation to the consolidation tag). If TAG routing's
advantage disappears here, the tag — not merely sustained load — is the
carrier of the history effect (E0d-R3).
"""
struct UndirectedController <: DCP
    k_commit::Int32
    function UndirectedController(k_commit::Integer=2)
        k_commit >= 1 || error("HardFailure: UndirectedController k_commit must be >= 1")
        new(Int32(k_commit))
    end
end

const UNDIRECTED_CONTROLLER = UndirectedController()

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

"""
Shared E0d/E0c plastic-site commit decision. `remit_dwell` is the flag that
varies between the phase machine (false) and tag routing (true).
"""
function _plastic_commit_decision(snapshot::FPSnapshot, k_commit::Int32,
                                  remit_dwell::Bool)::LifecycleAction
    snapshot.consecutive_stable >= snapshot.k_settle || return NO_ACTION
    snapshot.stress_ema < snapshot.yield_up || return NO_ACTION  # melt margin

    if remit_dwell && snapshot.melt_tag_agrees
        # E0d tag routing: previously-validated material aligned with the
        # current load re-commits on the first certified settle tick.
        return CommitAction(snapshot.site_index)
    end

    plastic_since = snapshot.plastic_since
    (plastic_since == Int32(0) ||
     (snapshot.tick - plastic_since) >= k_commit) || return NO_ACTION
    return CommitAction(snapshot.site_index)
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

    # Plastic sites: commit behind settle + dwell + melt margin (no remission).
    if snapshot.allocated && snapshot.superplastic
        return _plastic_commit_decision(snapshot, controller.k_commit, false)
    end

    return NO_ACTION
end

function decide(controller::TagRoutingController, snapshot::FPSnapshot)::LifecycleAction
    # Committed sites: identical invalidation to the phase machine — routing
    # touches ONLY the commit side, so anti-ossification strength is unchanged
    # by construction (E0d-R4 isolation).
    if snapshot.allocated && !snapshot.superplastic
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted >= snapshot.conflict_k
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: dwell remitted for tag-aligned melts.
    if snapshot.allocated && snapshot.superplastic
        return _plastic_commit_decision(snapshot, controller.k_commit, true)
    end

    return NO_ACTION
end

function decide(controller::UndirectedController, snapshot::FPSnapshot)::LifecycleAction
    # E0d ablation: the certificate fires on sustained consistent above-floor
    # load REGARDLESS of direction relative to the consolidation tag.
    if snapshot.allocated && !snapshot.superplastic
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted_undirected >= snapshot.conflict_k
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: identical to the phase machine (no remission).
    if snapshot.allocated && snapshot.superplastic
        return _plastic_commit_decision(snapshot, controller.k_commit, false)
    end

    return NO_ACTION
end
