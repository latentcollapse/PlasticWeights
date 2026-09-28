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

"""
    RegimeAdaptiveController(k_commit=2; young_fraction=0.5)

E0e (Pass 3b): regime-adaptive routing — the synthesis of E0d's two-mechanism
result. The history effect decomposed into (A) tag-carried memory, dominating
SHORT phases (TAGR beat PHASE at L ≤ 75), and (B) melt/recommit churn,
dominating LONG phases (PHASE beat TAGR at L=150). Both mechanisms are
direction-gated, so the regime test asks only: which mechanism does THIS phase
need? The controller routes by phase position, using the harness-declared
regime metadata (`region.phase_length`, `snapshot.ticks_into_phase`):

- **Young phase** (`ticks_into_phase < young_fraction · phase_length`): tag-
  aligned melted sites commit on the first certified settle tick — dwell
  REMITTED (the TAGR arm; mechanism A). The phase just re-pointed; previously-
  validated material aligned with the new load should be spent immediately.
- **Deep phase** (position at or beyond the boundary): identical to the
  PhaseMachineController — no remission (mechanism B). Churn carries the
  long-phase gains; remission short-circuits it (E0d-R2's mechanistic failure).

The melt side is byte-identical to the phase machine's (direction-sensitive
conflict certificate), so anti-ossification strength is unchanged by
construction; the routing decision remains per-site and load-gated (settle
certificate + melt margin) exactly as in E0d. The controller stays STATELESS:
regime position is declared harness metadata carried on every snapshot, not
controller memory (the "Stateless Stage-0 fixed-rule DCP" contract holds).

`young_fraction` defaults to 0.5 (E1c's map says the transition sits between
the per-phase scales where remission wins and where churn wins; the half-way
boundary is the preregistered cut). Requires an explicitly declared phase
length: a region with `phase_length == 0` is a HardFailure at decision time,
so the arm cannot silently degenerate into the phase machine.

The E0e short-window finding (E0e-D1, pre-grid): under the phase machine's
1/tick commit budget, dwell remission is behaviorally INERT — the budget
queue, not `k_commit`, gates recommit timing — so a budgeted regime arm is
byte-identical to the phase machine and mechanism A cannot appear. The young
window therefore must carry the TAGR rule in full (remission AND no commit
budget), while the deep window carries the PHASE rule in full (dwell AND the
1/tick budget). `budgeted=true` (default) keeps the budget in BOTH windows
for protocol-parity studies; `budgeted=false` is the preregistered synthesis
arm: young window = TAGR conditions, deep window = PHASE conditions.
"""
struct RegimeAdaptiveController <: DCP
    k_commit::Int32
    young_fraction::Float32
    budgeted::Bool
    function RegimeAdaptiveController(k_commit::Integer=2;
                                      young_fraction::Real=0.5,
                                      budgeted::Bool=true)
        k_commit >= 1 ||
            error("HardFailure: RegimeAdaptiveController k_commit must be >= 1")
        yf = Float32(young_fraction)
        isfinite(yf) && 0.0f0 < yf <= 1.0f0 ||
            error("HardFailure: RegimeAdaptiveController young_fraction must be in (0,1], got $yf")
        new(Int32(k_commit), yf, budgeted)
    end
end

const REGIME_ADAPTIVE_CONTROLLER = RegimeAdaptiveController()

"""Young-window boundary in ticks: the number of leading ticks `t` with
`t < young_fraction · L`. Computed in Float64 with a relative snap tolerance
so binary-inexact fractions (0.2f0 · 10 = 2.000000003) cannot shift an exact
integer boundary by one tick; genuinely fractional boundaries round up (a tick
at 7.5 of 15 is still young), matching the strict `<` in the contract."""
function _young_boundary_ticks(young_fraction::Float32, phase_length::Int32)::Int32
    b = Float64(young_fraction) * Float64(phase_length)
    return Int32(ceil(b - 1e-6 * max(1.0, b)))
end

"""Kernel-side single source of truth for the regime window at `tick`:
young iff (tick − 1) mod phase_length is inside the young boundary. Used both
by the commit budget and (indirectly, via the snapshot) by the decision."""
function _regime_young_phase(controller::RegimeAdaptiveController,
                             phase_length::Integer, tick::Integer)::Bool
    phase_length > 0 ||
        error("HardFailure: RegimeAdaptiveController requires a declared positive phase_length")
    tip = mod(tick - 1, phase_length)
    return tip < _young_boundary_ticks(controller.young_fraction, Int32(phase_length))
end

"""
    PhaseQuotaController(k_commit=2; quota_fraction=0.5)

E0g (Pass 3d): per-phase commit budget. E0f-D1 located the short-L (L=15)
deficit as commit-RATE-bound: the phase machine's 1/tick commit budget
throttles re-adaptation, and TAGR's full budget lift fixed short L (+0.1226
vs PHASE −0.0903) but poisoned long L (−0.085 at L=150 — E0e-D2: churn
pacing carries the large-L gain). The synthesis: keep the phase machine's
commit rule (settle + dwell + melt margin, NO remission) and its 1/tick
pacing, but shape the budget as a PHASE-LEVEL QUOTA:

  admitted(tick) = min(1, Q − commits_so_far_in_current_phase),  Q = quota_fraction·L

so the commit rate is lifted wherever the phase machine is rate-starved
(short L) while the total per-phase commit volume stays bounded; the quota
refills at every phase boundary. Any surplus above what the phase machine
would spend is behaviorally inert at long L (the queue rarely reaches Q),
so the arm degrades to the phase machine BY ARITHMETIC where the quota does
not bind — the same clean ablation structure E0f used on the melt side.

`quota_fraction` defaults to 0.5 (calibration: PHASE spends 5.1/28.8/45.8/
28.2 commits per phase at L=15/40/75/150, so Q = 8/20/38/75 lifts the short-L
rate ~50% while binding nowhere at long L). Requires a declared phase length
(`phase_length > 0`), HardFailure at decision time otherwise; the controller
stays STATELESS — the kernel derives `commits_so_far_in_current_phase` from
live `consolidation_tick` stamps (commits stamp the tick, melts zero it), no
controller memory or substrate state is added.

Note: per-tick admission stays ≤ 1, so the E0b2 coordinated-commit-wave
failure mode stays impossible by construction; the quota changes WHICH ticks
can admit, not how many per tick.
"""
struct PhaseQuotaController <: DCP
    k_commit::Int32
    quota_fraction::Float32
    function PhaseQuotaController(k_commit::Integer=2;
                                  quota_fraction::Real=0.5)
        k_commit >= 1 ||
            error("HardFailure: PhaseQuotaController k_commit must be >= 1")
        qf = Float32(quota_fraction)
        isfinite(qf) && 0.0f0 < qf <= 1.0f0 ||
            error("HardFailure: PhaseQuotaController quota_fraction must be in (0,1], got $qf")
        new(Int32(k_commit), qf)
    end
end

const PHASE_QUOTA_CONTROLLER = PhaseQuotaController()

"""E0g quota in commits: `ceil(quota_fraction · L)` with the same relative
snap tolerance `_young_boundary_ticks` uses, so binary-inexact fractions
(0.2f0·10 = 2.000000003) cannot inflate the quota by one commit."""
function _phase_quota_ticks(quota_fraction::Float32, phase_length::Int32)::Int32
    b = Float64(quota_fraction) * Float64(phase_length)
    return Int32(ceil(b - 1e-6 * max(1.0, b))) >= 1 ?
           Int32(ceil(b - 1e-6 * max(1.0, b))) : Int32(1)
end

"""Kernel-side single source of truth: commits already spent in the phase
containing `tick`. Counts live FPSiteState stamps: commits stamp
`consolidation_tick = tick`, melts zero it, so the count of stamps in the
open interval ((p−1)·L, tick] is exactly the number of commits admitted this
phase — no substrate state or controller memory is needed (the stateless-DCP
contract holds; the kernel is the single authority over the budget).

Requires a declared positive phase_length, HardFailure otherwise."""
function _commits_this_phase(substrate::SubstrateState,
                             phase_length::Integer, tick::Integer)::Int
    phase_length > 0 ||
        error("HardFailure: PhaseQuotaController requires a declared positive phase_length")
    p = cld(tick, phase_length)
    phase_start = (p - 1) * phase_length
    count = 0
    for site in substrate.sites
        site isa FPSiteState || continue
        ct = Int(site.consolidation_tick)
        ct > phase_start && ct <= tick && (count += 1)
    end
    return count
end

"""
    MeltRoutingController(k_commit=2; young_fraction=0.5)

E0f (Pass 3c): melt-side routing. E0e-D2 showed the deep window cannot be
selected independently of the young one on the COMMIT side — young-window rule
choices fork the whole phase trajectory — and located the open lever on the
MELT side. This controller moves the lever while holding everything else at
the phase machine's semantics:

- **Commit side (unchanged everywhere):** exactly the phase machine's rule —
  settle certificate + dwell (`k_commit`) + melt margin, no remission — and
  the same 1/tick commit budget in BOTH windows (the kernel budgets this type
  with the phase machine). Any effect is therefore attributable to melts.
- **Melt side (the lever):** a committed site's conflict certificate fires at
  an effective threshold `k_eff = 1` while the phase is YOUNG — one tick of
  sustained, consistent, above-floor OPPOSED load invalidates immediately —
  and at the phase machine's pace (`region.conflict_k`) once the phase is
  deep. Direction sensitivity, the magnitude floor, and the melt budget gate
  are the phase machine's, untouched.

Rationale (E0e §4): PHASE's large-L advantage is downstream of letting
young-window churn run; accelerating young invalidation should make the site
population consolidate against the new task SOONER while the 1/tick commit
cap keeps the recommit stream bounded — more churn events, same pacing.
Acceleration is meaningful only when `conflict_k > 1` (otherwise the arm
degrades to the phase machine by arithmetic). `young_fraction = 1.0` turns
the acceleration on everywhere and serves as E0f's position-gating ablation
(MROUTE_A): if it matches the half-phase arm, the effect is rate-level, not
position-level (melts already concentrate in the young window — E0e-D2).

Requires a declared phase length (`phase_length > 0`), HardFailure at
decision time otherwise; the controller stays stateless.
"""
struct MeltRoutingController <: DCP
    k_commit::Int32
    young_fraction::Float32
    function MeltRoutingController(k_commit::Integer=2;
                                   young_fraction::Real=0.5)
        k_commit >= 1 ||
            error("HardFailure: MeltRoutingController k_commit must be >= 1")
        yf = Float32(young_fraction)
        isfinite(yf) && 0.0f0 < yf <= 1.0f0 ||
            error("HardFailure: MeltRoutingController young_fraction must be in (0,1], got $yf")
        new(Int32(k_commit), yf)
    end
end

const MELT_ROUTING_CONTROLLER = MeltRoutingController()

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
Shared E0d/E0e/E0c plastic-site commit decision. `remit_dwell` is the flag
that varies between the phase machine (false) and the routing arms (true).
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

function decide(controller::RegimeAdaptiveController, snapshot::FPSnapshot)::LifecycleAction
    # Regime declaration is mandatory for this arm: no silent degeneration to
    # the phase machine when the harness forgot to declare a phase length.
    snapshot.phase_length > 0 ||
        error("HardFailure: RegimeAdaptiveController requires a declared positive region phase_length")

    # Committed sites: identical invalidation to the phase machine — the
    # regime test varies ONLY the commit-side remission window, so anti-
    # ossification strength is unchanged by construction.
    if snapshot.allocated && !snapshot.superplastic
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted >= snapshot.conflict_k
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: remit dwell while the phase is young; behave exactly like
    # the phase machine once it is deep.
    if snapshot.allocated && snapshot.superplastic
        young = snapshot.ticks_into_phase <
                _young_boundary_ticks(controller.young_fraction, snapshot.phase_length)
        return _plastic_commit_decision(snapshot, controller.k_commit, young)
    end

    return NO_ACTION
end

function decide(controller::PhaseQuotaController, snapshot::FPSnapshot)::LifecycleAction
    # Quota declaration is mandatory: no silent degeneration to the phase
    # machine when the harness forgot to declare a phase length (the quota is
    # meaningless without one — the kernel-side counter needs the window).
    snapshot.phase_length > 0 ||
        error("HardFailure: PhaseQuotaController requires a declared positive region phase_length")

    # Committed sites: identical invalidation to the phase machine — the quota
    # varies ONLY the budget shape, so anti-ossification strength is unchanged
    # by construction.
    if snapshot.allocated && !snapshot.superplastic
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted >= snapshot.conflict_k
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: the decision is EXACTLY the phase machine's (settle +
    # dwell, no remission, melt margin). Any behavioral difference comes from
    # the kernel's budget shape, not from the per-site rule.
    if snapshot.allocated && snapshot.superplastic
        return _plastic_commit_decision(snapshot, controller.k_commit, false)
    end

    return NO_ACTION
end

function decide(controller::MeltRoutingController, snapshot::FPSnapshot)::LifecycleAction
    # Melt-side routing, like REGIME, needs the declared phase length.
    snapshot.phase_length > 0 ||
        error("HardFailure: MeltRoutingController requires a declared positive region phase_length")
    young = snapshot.ticks_into_phase <
            _young_boundary_ticks(controller.young_fraction, snapshot.phase_length)

    # Committed sites: THE LEVER. The conflict certificate fires at k_eff = 1
    # in the young window and at the phase machine's pace (conflict_k) deep.
    # Everything else — direction condition, magnitude floor, melt budget —
    # is the phase machine's.
    if snapshot.allocated && !snapshot.superplastic
        k_eff = young ? Int32(1) : snapshot.conflict_k
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted >= k_eff
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: the commit side is EXACTLY the phase machine's (dwell,
    # no remission) — any behavioral difference is melt-side by construction.
    if snapshot.allocated && snapshot.superplastic
        return _plastic_commit_decision(snapshot, controller.k_commit, false)
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

"""
    BurstCommitController(k_commit=2; burst_fraction=0.5)

E0h (Pass 3e): burst-width commit allowance. E0g-D1 pinned the short-L
deficit: per-phase VOLUME is not the constraint (the phase machine spends
~5.1 commits/phase at L=15 against a quota of 8 — the quota never bound);
the binding constraint is the 1/tick PACING across the BURST STRUCTURE of
settle-certificate arrivals (up to 12 commit-intent sites crowd into a single
short phase, all gated to one per tick). This controller shapes admission
WITHIN each tick's burst instead of across the phase:

  cap(tick) = max(1, floor(burst_fraction · W)),   W = raw commit-intent count

W is the number of sites whose DCP decision is a CommitAction before budget
truncation (the kernel observes it in a discarded intent pass — decide() is
pure, snapshots immutable). The kernel admits the leading `cap` intent sites
in canonical order and denies the rest, which keep their persistent counters.
Per-tick admission stays ≤ W (and ≥ 1 for any nonempty burst), so this is a
bounded-rate stream, not the E0b2 coordinated wave.

The per-site commit rule is EXACTLY the phase machine's (settle + dwell
`k_commit` + melt margin, NO remission) and the melt side is untouched — the
only change is the budget shape. `burst_fraction = 1.0` admits every intent
site and is the "TAGR minus remission" ablation: if it reproduces TAGR's
short-L gain, the carrier was the batch ADMISSION SHAPE, not dwell remission
(E0h's adjudication of E0d mechanism A). `burst_fraction → 0` degenerates to
the phase machine's 1/tick.

Unlike the position-gated arms, burst admission is POSITION-BLIND: no
phase_length declaration is required and none is consulted — the budget is a
function of the tick's own intent count alone (undeclared-L substrates are
legal for this arm by design).
"""
struct BurstCommitController <: DCP
    k_commit::Int32
    burst_fraction::Float32
    function BurstCommitController(k_commit::Integer=2;
                                   burst_fraction::Real=0.5)
        k_commit >= 1 ||
            error("HardFailure: BurstCommitController k_commit must be >= 1")
        bf = Float32(burst_fraction)
        isfinite(bf) && 0.0f0 < bf <= 1.0f0 ||
            error("HardFailure: BurstCommitController burst_fraction must be in (0,1], got $bf")
        new(Int32(k_commit), bf)
    end
end

const BURST_COMMIT_CONTROLLER = BurstCommitController()

"""E0h burst admission cap for a tick whose raw commit-intent count is `W`:
`max(1, floor(burst_fraction · W))` — the leading `cap` intent sites in
canonical order are admitted this tick, the rest are denied and keep their
counters. `burst_fraction = 1.0` admits every intent site; fractional caps
keep admission ≤ W by construction and ≥ 1 whenever the burst is nonempty
(a single intent site is always admitted — the floor alone would strand it)."""
function _burst_allowance(burst_fraction::Float32, W::Integer)::Int
    W >= 1 || return 0
    cap = floor(Float64(burst_fraction) * Float64(W))
    return cap >= 1 ? Int(cap) : 1
end

function decide(controller::BurstCommitController, snapshot::FPSnapshot)::LifecycleAction
    # Committed sites: identical invalidation to the phase machine — the
    # burst arm varies ONLY the budget shape, so anti-ossification strength
    # is unchanged by construction.
    if snapshot.allocated && !snapshot.superplastic
        if snapshot.commit_sign != 0 &&
           snapshot.consecutive_conflicted >= snapshot.conflict_k
            snapshot.melt_budget_available || return NO_ACTION
            return MeltAction(snapshot.site_index)
        end
        return NO_ACTION
    end

    # Plastic sites: the decision is EXACTLY the phase machine's (settle +
    # dwell, no remission, melt margin). Any behavioral difference comes from
    # the kernel's burst cap, not from the per-site rule.
    if snapshot.allocated && snapshot.superplastic
        return _plastic_commit_decision(snapshot, controller.k_commit, false)
    end

    return NO_ACTION
end
