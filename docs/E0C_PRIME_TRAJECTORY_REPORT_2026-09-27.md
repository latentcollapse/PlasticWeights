# E0c′ — P5″ Trajectory-Continuity Rerun: All Criteria Pass, E1 Unblocked

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm, working tree on `cd0a88e` (P5′/P5″ changes applied, uncommitted)
**Environment:** Julia 1.12.6, single thread, CPU. Full suite green before the rerun.
**Status:** **All six preregistered criteria pass. E1 is UNBLOCKED.** The Q3 return-trip effect is net-positive for the first time (median +0.184, 61/78 learners). The mixed developmental phase is the dominant state of the substrate.

---

## 1. What this run tested

E0c failed exactly one preregistered criterion (C3, max mixed-learner
mid-phase jump 1.674 > 1.0) with the attribution: the commit budget
eliminated *coordinated* waves, but the fixed-length 2-tick ramp released
~δ/2 per tick, so per-tick exposed change scaled with ‖δ‖.

Amendment 2 (preregistered in the instrument header before the rerun) tested
the repair in two steps, with the canary diagnostic run between them:

- **P5′ (canary, superseded):** adaptive ramp *length* —
  `ramp_ticks = max(ramp_k, ceil(|δ|/m_max))` with `m_max = 0.02` (equal to
  the grid's `epsilon_delta`: the exposure budget matches the plastic flow
  budget). **The canary made C3 worse (5.72)** and produced 2 runaway
  points. Attribution, recorded before the fix:
  1. *Melt-mid-ramp reversion* — a long-ramp site invalidated at blend b
     snapped from `w−(1−b)δ` straight to `w`: an unbounded jump, on a melt
     window now ~150 ticks wide (invalidation almost always caught sites
     mid-transition, especially on low-η Bingham points with ‖δ‖ ~ 5–11).
  2. *Aggregate drift* — `m_max` bounds per-*site* change; the network sum
     over dozens of simultaneously-gliding sites is unbounded.
- **P5″ (authoritative):** **exposure trajectory continuity.** The site
  persists `(exposed_base, transition_start, ramp_ticks)` and its visible
  value follows ONE bounded-rate trajectory
  `x(t) = exposed_base + (w − exposed_base)·b(t)` toward `w`. Lifecycle
  events **redirect** the trajectory — commit and melt each stamp a new
  transition from the *currently exposed* value (`δ_eff = w − x_now`), never
  interrupt it. Consequences: per-tick exposed change is bounded by `m_max`
  for every event at every distance, and invalidation no longer shocks at
  all (the melt-mid-ramp reversion is structurally impossible). ZCS pins
  plastic sites to 0 by policy; its fade-in applies at commit.

The scientific lesson is worth keeping: a bounded-*length* ramp is the wrong
frame. The right object is a continuous exposure *trajectory* that lifecycle
events retarget — hybrid-systems mode continuity applied to visibility
rather than to the weights themselves.

## 2. Verification

- Full suite green, including rewritten blending tests (P5″ contract:
  trajectory records, plastic-glide-under-VPS, ZCS pinning, unstamped
  fallback) and the lifecycle test now asserting that melt *redirects*
  (transition stamped at the reopen tick) rather than clears.
- One real defect caught by the suite during the rewrite:
  `transitioned_exposure` originally delegated to legacy `commit_blend`,
  whose `consolidation_tick == 0 → 1.0` gate silently killed plastic-site
  glides (consolidation_tick is a *phase* record and must not gate a
  *trajectory*). Fixed: the P5″ blend reads only the transition record.

## 3. E0c′ results (144 points, grid identical to E0b2/E0c)

| Census | E0b (96) | E0b2 (144) | E0c (144) | **E0c′ (144)** |
|---|---|---|---|---|
| uncommitted | 69% | 40% | 40% | 58/144 (40%) |
| frozen | 7% | 40% | 10% | **0/144** |
| consolidated | 19% | 8% | 0 | **0/144** |
| mixed | 5% | 11% | 49% | **86/144 (60%)** |
| runaway | 0 | 0 | 0 | **0/144** |

### Preregistered criteria — all pass

| Criterion | E0b2 | E0c | **E0c′** | Verdict |
|---|---|---|---|---|
| C1 mixed ≥ ~20% | 11.1% | 49.3% | **59.7%** | **PASS** |
| C2 learner liveness ≥ 50% | 19% | 80.8% | **78/78 = 100%** | **PASS** |
| C3 mid-phase jump < 1.0 (mixed) | 5.60 | 1.674 | **0.549** | **PASS** |
| C4 Bingham learners > 0 | 41/72 | 42/72 | **42/72** | **PASS** |
| C5 K3 violations ≤ 20% | 83% | 19.2% | **0/78 = 0%** | **PASS** |
| C6 runaway = 0 | 0 | 0 | **0** | **PASS** |

Arm detail: Bingham C1 = 63.9%, C2 = 42/42, C3 = 0.549, C5 = 0; Newtonian
C1 = 55.6%, C2 = 36/36, C3 = 0.521, C5 = 0.

### Q3 return-trip (the unexpected result)

| | E0b | E0b2 | E0c | **E0c′** |
|---|---|---|---|---|
| positive asymmetry | 3/11 (artifact-top) | 9/41 | 30/78 | **61/78 (78%)** |
| median asym | — | −0.037 | −0.027 | **+0.184** |
| max | +24.5 (artifact) | +0.349 | +1.147 | **+1.064 (no artifact)** |

Median **+0.184** with bounded downside (min −0.362): history now *helps on
average*. Candidate mechanism (to be tested, not yet claimed): the return
trip re-exposes previously-consolidated material through the bounded glide —
relearning runs against a substrate still moving toward its old values, so
the head tracks a smooth drift toward the A-solution instead of starting
cold. This is the first evidence that the lifecycle's memory *pays*, and it
is exactly the hook Pass 3's consolidation tags are designed to sharpen and
route.

## 4. E1 decision

**E1 is UNBLOCKED.** Per the original E0b preregistration, E1 (the four-arm
comparison) may run once the gate defects are repaired and E0-style
regression passes its bar — which E0c′ now does on all six criteria, with
the E0b2/E0c/E0c′ grids as the recorded regression floor. The E1 protocol
itself remains as preregistered in the E0 report (§8): the four arms
(Stage-0 substrate, C3 control, conventional FP32, mixed) on extended
multi-task streams, with liveness, retention, and return-trip as first-class
outcomes.

Recommended E1 parameterization from the E0c′ grid: Bingham τ ∈ [0.05, 1],
η ∈ [1, 10], settle ∈ {0.8, 0.9}, hard = 0.01, conflict_k = 2,
k_commit = 2, RampedVPS(2; m_max = epsilon_delta) — the region where every
criterion passes simultaneously with positive median return-trip.

## 5. Artifacts

- `scripts/e0c_phase_machine_sweep.jl` — Amendment 2 instrument (P5′ canary
  finding + P5″ description recorded in-header before execution)
- `docs/e0c_prime_raw_output.txt` — full 144-point grid (authoritative)
- `docs/e0c_raw_output.txt` — E0c grid (census-amendment record, C3 failed)
- This report: `docs/E0C_PRIME_TRAJECTORY_REPORT_2026-09-27.md`
- Source (uncommitted on `cd0a88e`): SiteState.jl (exposed_base,
  transition_start, coherence invariants), Exposure.jl
  (`transitioned_exposure`, `stamp_transition!`, adaptive lengths),
  Actions.jl (redirect-at-commit/melt), + test updates in
  `test/phase_machine.jl`

*Generated autonomously by Buffy under Matt's standing authorization. All
results reproducible with the commands above; no state outside this
repository was modified.*
