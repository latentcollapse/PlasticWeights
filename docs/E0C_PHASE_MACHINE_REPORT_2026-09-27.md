# E0c — Phase-Machine Sweep Report (Pass 2: Symbolic State + Exposure Ramp)

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm, working tree on `63fc09c` (Pass-2 changes applied, uncommitted)
**Environment:** Julia 1.12.6, single thread, CPU. Full suite green (incl. new `test/phase_machine.jl`) before the sweep.
**Status:** **Five of six preregistered criteria pass.** The mixed developmental phase is now the dominant learner state (49.3% of the grid; E0b: 5%, E0b2: 11.1%), learner liveness is 80.8%, K3 violations fell 83% → 19.2%, runaway is zero. **C3 fails** (max mixed-learner mid-phase jump 1.674 > 1.0), with attribution: the commit *budget* eliminated coordinated waves, but the *fixed-length* ramp does not bound per-tick magnitude for large deltas. E1 remains blocked per the preregistration; the required change is small and Stage-0-implementable.

---

## 1. What changed (Pass 2, P1–P5)

- **P1 — Persistent symbolic phase record** on every `FPSiteState`: `phase`,
  `consolidation_tick`, `last_commit_delta`, `commit_sign`, `commit_stress`,
  `plastic_since`. Phase is *derived* (superplasticity decides) and enforced by
  invariants with HardFailure discipline. This is the neurosymbolic turn: the
  discrete layer is no longer an ephemeral function of thresholds — it is
  state with guarded transitions.
- **P2 — Conflict certificate (mandatory invalidation).** `consecutive_conflicted`
  accrues when a committed site bears *consistent* load **opposite its
  consolidation reference** (`commit_sign`, stamped at commit) at magnitude ≥
  `CONFLICT_FLOOR × commit_stress` (floor relative to the load the site
  actually consolidated under — the EMA-zero-crossing lesson from design
  review). At `conflict_k` the phase machine MUST melt the site. Permanent
  rigidity is no longer a steady state.
- **P3 — PhaseMachineController dwell.** Commit requires settle certificate ∧
  `k_commit` ticks of plastic dwell ∧ melt margin.
- **P4 — Commit budget.** ≤ 1 commit per tick under the machine (the frozen
  FixedRuleController path is exempt; its batch behavior is contract).
- **P5 — Staged exposure ramp.** `RampedVPS(2)`: a fresh commit's delta
  reaches the forward path over 2 ticks. Transition management (stamping) has
  **single authority** in `apply_action!`; the kernel passes the tick.

Design self-corrections made during implementation (each caught before the
grid): the conflict floor was redefined from yield-relative to
consolidation-stress-relative (otherwise small-load learners could never be
invalidated); an over-strong liveness HardFailure was replaced by the
correct dynamic guarantee (the all-committed state is legal under stationary
load; opposed load provably reopens it — tested).

## 2. Verification

- Full suite green, including the new `test/phase_machine.jl`: phase-record
  invariants, exact ramp blending (FP32-tolerant), certificate semantics
  (aligned/below-floor/opposed/no-reference/noise), dwell hysteresis,
  budget-vs-frozen-contract, **full lifecycle cycle under conflicting load**
  (commit under A → invalidation under −A → reopened, w preserved), absorbing-
  state legality + dynamic liveness, and bitwise determinism with the entire
  machine in the training loop.

## 3. E0c results (144 points, grid identical to E0b2; only deltas P1–P5)

| Census | E0b (96) | E0b2 (144) | E0c (144) |
|---|---|---|---|
| uncommitted | 66/96 (69%) | 58/144 (40%) | 58/144 (40%) |
| frozen | 7/96 (7%) | 58/144 (40%) | **15/144 (10%)** |
| consolidated | 18/96 (19%) | 12/144 (8%) | 0/144 |
| mixed | 5/96 (5%) | 16/144 (11%) | **71/144 (49%)** |
| runaway | 0 | 0 | 0 |

Learners: 78/144. Return-trip positives: 30/78 (38%; E0b2: 22%), median still
≈ −0.03 — no demonstrated net benefit yet (Pass-3 target).

### Preregistered criteria

| Criterion | Result | Verdict |
|---|---|---|
| C1 mixed ≥ ~20% | **49.3%** | **PASSED** (E0b2: 11.1%) |
| C2 learner liveness ≥ 50% | **63/78 = 80.8%** | **PASSED** (E0b2: 19%) |
| C3 mid-phase jump < 1.0 (mixed learners) | 1.674 | **FAILED** — see attribution |
| C4 Bingham learners > 0 | 42/72 | **PASSED** (Newtonian: 36/36 liveness, 0 K3) |
| C5 K3 ≤ 20% of learners | **19.2%** | **PASSED** (E0b2: 83%) |
| C6 runaway = 0 | 0 | **PASSED** |

**Preregistration amendment** (recorded before any grid data existed): the
single-point diagnostic showed E0b2's `n_super > 32` runaway rule
misclassifies the machine's legitimate steady state — under aggressive
invalidation, a *learning* substrate correctly holds many plastic sites while
a contradicting task demands adaptation. Runaway was redefined as churn > 20
distinct-site melts/phase ∧ final ≥ 0.15 (unbounded churn *without*
learning). The diagnostic point itself (final 0.0003, 28+27 re-melts, bounded
jumps, positive asym) reclassified frozen→mixed under the amended rule.

### C3 attribution (measured, not hand-waved)

- Newtonian arm: C3 **passes** outright (0.675).
- The Bingham offenders split: 1.674/1.378 on mixed learners with **exactly
  one melt in B** — a single site invalidated early, then ~148 B-ticks of
  opposed load accumulating an O(1) delta, whose 2-tick ramp releases ~δ/2
  per tick; and 1.41–1.74 on frozen learners (head-optimizer stiffness, same
  attribution class as E0b2).
- Interpretation: **coordination is eliminated** (no commit waves anywhere —
  the budget did its job), but the ramp's *length* is fixed while the shock
  scales with ‖δ‖. Per-tick magnitude is not yet bounded in units of
  network-visible change. The criterion's letter fails; its purpose (no
  manufactured non-stationarity) is half-met.

## 4. Verdict and E1 decision

The thesis-level result is strong: with symbolic phase state, guarded
transitions, mandatory invalidation, and staged exposure, the substrate
sustains a **wide, dominant mixed developmental phase with high learner
liveness and near-eliminated ossification** — the three properties drns-v0.2
demands and E0/E0b2 could not deliver. What remains is a *parameterization*
defect in P5 (fixed ramp length vs delta magnitude), not an architectural one.

**E1 remains blocked**, per the preregistration (C3 must hold). The
preregistered unblock path is small:

1. **P5′ (adaptive ramp):** lengthen the ramp until the per-tick exposed
   change is bounded — e.g. ramp over `max(ramp_k, ceil(|δ| / m_max))` ticks,
   or normalize blend steps to a fixed visible-change budget. Re-run E0c
   (it is the regression harness) and require C3 < 1.0 with C1/C2/C5 held.
2. **Pass 3 (E0d, unchanged):** consolidation tags + invalidation routing,
   now with a cleaner instrument: the return-trip question (Q3) is the last
   major uncommitted claim, and 30/78 positives suggest the signal exists
   but is not yet *used* — tags let the controller route reopen priority
   instead of leaving it to load-imposition order.

## 5. Artifacts

- `scripts/e0c_phase_machine_sweep.jl` — preregistered instrument
  (`bingham|newtonian|single|report`), amendment recorded in-header
- `docs/e0c_raw_output.txt` — full 144-point grid
- This report: `docs/E0C_PHASE_MACHINE_REPORT_2026-09-27.md`
- Source (uncommitted on `63fc09c`): SiteState.jl, SiteTelemetry.jl,
  RegionState.jl, Exposure.jl, Initialization.jl, Snapshot.jl,
  FixedRuleController.jl, Actions.jl, ReferenceKernel.jl,
  MaterialTraining.jl, PlasticWeights.jl + `test/phase_machine.jl`

*Generated autonomously by Buffy under Matt's standing authorization. All
results reproducible with the commands above; no state outside this
repository was modified.*
