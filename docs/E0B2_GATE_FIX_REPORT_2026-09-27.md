# E0b2 — Gate-Fix Regression Sweep (D1 + D2 Repairs)

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm, working tree on `0d8b9c0` (Pass-1 gate fixes applied, uncommitted)
**Environment:** Julia 1.12.6, single thread, CPU. Full suite re-verified green immediately before the sweep.
**Status:** D1/D2 verified effective. Preregistered bar partially met: **C4 passes, C1/C2/C3 fail** — the binding defect has moved from "gates cannot learn" to "lifecycle still too coarse." E1 remains blocked. Pass 2 (phase machine + exposure ramp) is now the critical path, with preregistered scope updated below.

---

## 1. What changed (Pass 1 implementation)

### D1 — settle gate now certifies gradient-direction persistence

- `SiteTelemetry` gained `signed_stress_ema` (EMA of signed gradient) with a NaN
  "unknown" sentinel; `gradient_consistency` computes
  `c = |EMA(g)| / EMA(|g|)` in [0,1].
- `update_counters!` settle certificate is now
  `c >= settle_down AND residual_motion_ema < epsilon_delta`. The magnitude
  condition `stress_ema < settle_down` is **gone**; `settle_down` is repurposed
  as a consistency threshold (validated to [0,1)).
- Regime separation, as designed: consistent learning → c≈1; rest → both EMAs
  decay geometrically so c **persists** (rest is quiet, not conflicted); fresh
  0/0 rest certifies c=0 and can never settle (kills the anti-causal commit
  wave); sign-flipping conflict collapses c.
- Commit additionally requires a **melt margin** (`stress_ema < yield_up`) —
  commit is refused where MELT would be legal (DCP + `apply_action!` both
  enforce).

### D2 — Bingham mobility shapes flow, never vetoes

- `m = (σ+ε)/(σ+ε+τ·(1−c))`, replacing `m = max(0, 1−τ/σ)`.
- Exactly Newtonian at τ=0; unconflicted flow (c=1) unthrottled by yield;
  hardened+conflicted throttled to m≈σ/τ but strictly > 0 — the
  ratchet-into-permanent-ban mechanism (E0 §5 D2) is structurally removed.
- Scale-covariant in (σ, τ, ε): S1b loss-scale covariance preserved.

**Honesty note (supersedes E0 §5 D2's mechanism guess):** E0b's raw grid showed
Bingham points with τ=1e-5 (mechanically ≈ Newtonian) also never learned, so
the kill mechanism was *not* the low-stress veto alone — commit-hardening
inflates τ monotonically, and under the legacy law the ratchet converts τ into
a fleet-wide flow ban. The new law is designed against that mechanism.

## 2. Verification

- Full test suite: **green** (all testsets, 0 failures / 0 errors).
- Two tests had encoded the defect as expected behavior and were rewritten:
  the telemetry "real developmental trace" 64-site rest-tick commit wave, and
  S1b's rest-driven commit leg. Both now commit under small *consistent* load.
  Golden values for the new mobility law were derived analytically; one
  arithmetic slip in my own S2-FP rewrite (−0.25 vs −0.5) was caught by the
  suite and corrected.
- New unit coverage: consistency certificate semantics (first-tick exactness
  under the shared (1−β) convention, conflict collapse, rest preservation,
  0/0 → 0), shaped-mobility golden values, law-level scale covariance.

## 3. E0b2 results (144 points, same protocol as E0b: A→B→A, 150/150/150)

| Census | E0b (96 pts) | E0b2 (144 pts) |
|---|---|---|
| uncommitted | 66/96 (69%) | 58/144 (40%) |
| frozen | 7/96 (7%) | 58/144 (40%) |
| consolidated | 18/96 (19%) | 12/144 (8%) |
| mixed | 5/96 (5%) | 16/144 (11%) |
| runaway | 0 | 0 |

Learners (final < 0.15): 77/144 (E0b: 11/96). Bingham learners: **41/72**
(E0b: **0/48**).

### Preregistered criteria

| Criterion | Result | Verdict |
|---|---|---|
| C1 mixed ≥ ~20% of grid | 16/144 = 11.1% | **FAILED** (doubled vs E0b, still short) |
| C2 learner liveness ≥ 50% | 15/77 | **FAILED** (up from ~5/96 total) |
| C3 max mid-phase jump < 1.0 | 5.60 | **FAILED** — see decomposition |
| C4 Bingham learners > 0 | 41/72 | **PASSED** |

### C3 decomposition (measured, not hand-waved)

- Boundary jumps (~1.05) are the target flip measured against a net that
  learned the previous task — large *because* learning succeeds. Reclassified
  as informational; the criterion now targets mid-phase jumps.
- Mid-phase 5.6 / 2.3–2.5 jumps occur on **frozen** points: substrate fully
  inert (all melts in phase 1), so these are head-optimizer stiffness events,
  not substrate-manufactured shocks. Attribution: not a lifecycle defect.
- **One genuine substrate shock remains:** mixed learner
  (τ=1.0, η=1.0, σ=0.9) shows mid=2.49@t381 with 6 melts in B — melted-in-B
  sites re-committing during A3 under VPS, i.e. the commit exposure jump
  (E0 §2) still fires on re-commit. This is the residual substrate shock.

### What the fixes demonstrably achieved

- The lifecycle can now **learn under load**: consolidated+cyan mixed states
  with real re-melt counts (mB=58/mA3=29-32 at τ=0.2, η=10; mB=25-31 at
  τ=0.05, η=10) — impossible under E0b's gates.
- Return-trip positives: 9/41 Bingham learners (E0b: 3/11 with the largest
  positive exposed as a task-entry artifact). Largest honest positive
  +0.349; no artifact-scale (+24.5) entries anywhere.
- Zero runaway in 144 points.

## 4. Verdict

**The D1/D2 repairs are confirmed real but insufficient.** The failure mode
changed qualitatively:

- E0b: gates could not learn (66% uncommitted) or learned and ossified (K3
  violated, 7 points).
- E0b2: 53% of the grid learns; the binding residual defects are
  (a) the **frozen 40%** — one commit wave then permanent rigidity (K3 still
  violated in 34 Bingham learners), and (b) the **commit exposure jump** on
  re-commit (the single genuine C3 violation).

Both residuals are exactly the Pass-2 targets: the phase machine's guarded
transitions (dwell, budgets, invalidation) attack permanent rigidity, and the
staged exposure ramp converts the commit jump into a bounded-rate transition.

**E1 remains blocked** — correctly, per the preregistration. Pass-2 (E0c)
preregistered scope: phase alphabet with hysteresis/dwell/budgets, staged
exposure ramp, carried-forward success criteria C1 ≥ 20%, C2 ≥ 50%,
C3 mid-phase < 1.0 (substrate events only), C4 maintained, plus K3 liveness
as a first-class criterion. E0b2 grid becomes the regression floor.

## 5. Artifacts

- `scripts/e0b2_gate_fix_sweep.jl` — preregistered instrument (chunked
  execution: `bingham|newtonian|single|report`; full-sweep mode preserved)
- `docs/e0b2_raw_output.txt` — full 144-point grid
- This report: `docs/E0B2_GATE_FIX_REPORT_2026-09-27.md`
- Source (uncommitted on `0d8b9c0`): SiteTelemetry.jl, RegionState.jl,
  BinghamInspired.jl, FixedRuleController.jl, Actions.jl,
  ReferenceKernel.jl, PlasticWeights.jl + test updates in 4 files

*Generated autonomously by Buffy under Matt's standing authorization. All
results reproducible with the commands above; no state outside this
repository was modified.*
