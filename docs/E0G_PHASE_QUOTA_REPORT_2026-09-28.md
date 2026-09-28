# E0g — Per-Phase Commit-Budget DCP (Pass 3d)

**Date:** 2026-09-28 · **Status:** COMPLETE (grid done, ledger written)
**Preregistration:** `scripts/e0g_phase_quota.jl` header (declared before any run; committed with the results)
**Rows:** `docs/e0g_rows.csv` (16 rows, resumable cache) · **Checks:** `docs/e0g_checks_output.txt`
**Suite:** full `Pkg.test()` green before the grid (7 new E0g testsets, 31 assertions)

## 1. Mechanism under test

E0f-D1 located the short-L (L=15) deficit as **commit-rate-bound**: the phase
machine's 1/tick budget throttles re-adaptation, and the only prior budget lift
(TAGR's, E0e) fixed short L (+0.1226 vs PHASE −0.0903) but poisoned long L
(−0.085 at L=150) because an unbounded budget destroys the churn pacing that
carries the large-L gain (E0e-D2). E0g shaped the budget as a **phase-level
quota** instead of lifting it wholesale:

```
admitted(tick) = min(1, Q − commits_so_far_in_current_phase),   Q = ceil(quota_fraction·L)
```

- Commit rule **exactly the phase machine's** (settle + dwell `k_commit` + melt
  margin, NO remission); per-tick admission stays ≤ 1 — the E0b2 wave stays
  impossible by construction. The **only** change is budget shape.
- The spent-quota counter is derived **statelessly kernel-side** from live
  `consolidation_tick` stamps in `((p−1)L, tick]`: commits stamp, melts zero,
  so melts **refund** quota. No controller memory, no new substrate state.
- Arms: `QUOTA` (`quota_fraction=0.5` → Q = 8/20/38/75), `QUOTA_A`
  (`quota_fraction=1.0` → Q = L, rate-unbound-within-phase ablation), against
  PHASE / FIXED on the standard four-task grid (seed 71, identical protocol).

## 2. Results (mean per-task gain; commits/melts totals)

| L   | PHASE            | QUOTA            | QUOTA_A          | FIXED            |
|-----|------------------|------------------|------------------|------------------|
| 15  | −0.0903 (51/46)  | −0.0905 (50/43)  | −0.0903 (51/46)  | −0.0572 (41/7)   |
| 40  | +0.0205 (288/248)| **+0.0334** (283/237) | +0.0205 (288/248) | +0.1618 (70/6) |
| 75  | +0.0461 (458/396)| +0.0461 (458/396)| +0.0461 (458/396)| +0.0647 (70/6)   |
| 150 | +0.4067 (282/218)| +0.4067 (282/218)| +0.4067 (282/218)| +0.3215 (71/7)   |

- **C0 PASS** — PHASE(150) = +0.4067 / 218 melts, bit-exact against E0d.
- **R1 FAIL** — the target did not materialize: QUOTA(15) −0.0905 vs PHASE(15)
  −0.0903 (dead tie). The L=40 conjunct held (+0.0334 > +0.0205).
- **R2 PASS, R3 PASS, R4 PASS** — all **by exact identity**: at L=150 QUOTA and
  QUOTA_A are byte-identical to PHASE (same commits, melts, gain). Long-L
  non-toxicity, which TAGR failed, is trivially satisfied here.
- **R5 FAIL** — QUOTA(15) commits 50 vs PHASE 51; the preregistered window
  [77, 153] assumed a consumed quota. **The quota was never consumed at L=15.**

### Budget-binding diagnostics (per-phase commit actions)

| L   | PHASE μ/max | QUOTA μ/max | Q (0.5·L) | reading |
|-----|-------------|-------------|-----------|---------|
| 15  | 5.1 / 12    | 5.0 / 11    | 8         | demand ≈ ceiling; live-stamp refunds absorb the one binding moment (1 commit deferred) |
| 40  | 28.8 / 40   | 28.3 / 40   | 20        | the only L where the quota bit the trajectory (−5 commits, −11 melts) — and it **helped** |
| 75  | 45.8 / 72   | 45.8 / 72   | 38        | byte-identical to PHASE: refunds keep the live count below Q |
| 150 | 28.2 / 58   | 28.2 / 58   | 75        | byte-identical to PHASE (quota never approached) |

## 3. Ledger

### E0g-D1 — the short-L deficit is NOT per-phase-volume-bound (R1, R5 FAIL)
At L=15 the phase machine spends only ~5.1 commits/phase against a quota of 8:
**there is no volume deficit to lift**. Per-phase quota shaping cannot and did
not move the short-L gain. Combined with E0f-D1 (melt acceleration inert at
L=15) and E0e-D1 (remission inert under the budget), the L=15 constraint is now
pinned precisely: commit admission is bound by the **1/tick PACING across the
burst structure of settle-certificate arrivals** (max 12 commit-actions crowd
into single phases), not by per-phase volume and not by dwell. TAGR's short-L
win came from the *unbounded* half of its lift (batch admission inside a burst),
which is exactly the part that poisons long L. Any E0h-style probe must shape
admission *within* bursts (e.g. a burst-width allowance) rather than per phase.

### E0g-D2 — a demand-shaped quota is free at long L and mildly positive at mid-L
The quota acted as a **soft throttle on per-phase demand peaks**: byte-identical
to PHASE at L=75/150 (R2/R3/R4 by identity — the refund-on-melt semantics keep
the live count below Q in churning phases), near-identical at L=15, and at the
one L where it bound (40) it *improved* gain (+0.0334 vs +0.0205, −5 commits,
−11 melts — deferring late-phase recommits of material that was about to melt
anyway). QUOTA_A is byte-identical to PHASE at 15/40/75/150, so the 0.5·L
ceiling — not the quota machinery — did all the work, and none of it was toxic.
This is the first budget-shape change that preserves the phase machine
everywhere it matters while beating it somewhere: it does **not**, however,
address the short-L target and is not a synthesis arm.

### E0g-D3 — the live-stamp quota is soft by construction (mechanism note)
Because melts zero `consolidation_tick`, every melt **refunds** one quota unit:
the effective constraint is `commits − melts` since phase start, not gross
commits. This made the arm far more conservative than the calibration reading
(PHASE gross spend exceeds Q=0.5·L at L=75: 45.8 > 38 — yet the arms are
identical). Gross-demand ceilings on the *action stream* would bind differently
than the live-stamp counter; the distinction is recorded here for any successor
probe (and the kernel-side counter remains the only stateless realization).

## 4. Verdict

E0g falsifies the per-phase-volume reading of E0f-D1 (R1/R5 FAIL, ledgered as
E0g-D1) and contributes a safe mid-L throttle (E0g-D2). The two-lever map now
reads: **short L is bound by 1/tick pacing across certificate bursts**;
mid L responds to mild late-phase commit deferral; long L is fragile to any
unbounded lift but indifferent to quota shaping. The PHASE rule remains the
committed arm; `PhaseQuotaController` ships as an inert-at-long-L,
mildly-positive-at-mid-L budget variant with the ablation cleanly adjudicated.
