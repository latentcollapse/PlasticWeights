# E0f — Pass 3c: Melt-Side Routing

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm at `8bc7b38` (E0e state; Pass-3b additions, suite green)
**Status:** **5 of 6 preregistered results pass (C0, R2, R3, R4, R5); R1 fails informatively.** The melt lever is **real and certified** (timing-not-volume; young-melt concentration 90%), **long-L-safe** — unlike every commit-side intervention, accelerating young invalidation preserves PHASE's large-L gain exactly — but it is **inert at L=15** and cannot reach the short-L problem. The two levers are asymmetric: melt-side acceleration is long-L-safe but short-L-useless; commit-side remission is short-L-active but long-L-toxic.

---

## 1. What was built (Pass 3c)

- **`MeltRoutingController` (MROUTE; k_commit=2, young_fraction=0.5):** the commit side is **exactly the phase machine's** in both windows (settle certificate + dwell + melt margin, no remission) and MROUTE shares the phase machine's 1/tick commit budget — any behavioral difference is melt-side by construction (tested: identical commit streams on a no-committed-site fixture).
- **The lever:** a committed site's conflict certificate fires at `k_eff = 1` while the phase is young (one tick of sustained, consistent, above-floor *opposed* load invalidates immediately) and at `region.conflict_k` once deep. Direction condition, magnitude floor, and melt budget untouched (tested, including the `commit_sign = 0` can't-be-invalidated path).
- **`MROUTE_A` ablation** (`young_fraction = 1.0`): accelerate everywhere — adjudicates position-gating on the melt side.
- Full suite green (6 new E0f testsets, 38 assertions), including live-kernel verification that the young certificate melts one tick earlier than the phase machine's and end-to-end determinism.

## 2. Results (four-task family, E1b/E1c/E0d/E0e protocol, seed 71)

| L | PHASE | MROUTE (half) | MROUTE_A (everywhere) | FIXED |
|---|---|---|---|---|
| 15 | −0.0903 | −0.0904 | −0.1056 | −0.0572 |
| 40 | +0.0205 | **+0.0525** | +0.0015 | +0.1618 |
| 75 | +0.0461 | +0.0340 | −0.0093 | +0.0647 |
| 150 | +0.4067 | **+0.4079** | **+0.4082** | +0.3215 |

Melts young/total at key rows: PHASE@150 196/218, MROUTE@150 210/225, MROUTE_A@150 221/253; PHASE@75 206/396 → MROUTE@75 239/398 (33 melts moved young, volume unchanged); PHASE@15 21/46 (only 46% young — NOT concentrated).

| Result | Verdict |
|---|---|
| C0 canary: PHASE(150) reproduces E0d committed | **PASS** (bit-exact, every run) |
| R1 short-window win: MROUTE>PHASE at 15 AND 40 | **FAIL** (L=15 is a dead tie: −0.0904 vs −0.0903; L=40 passes: +0.0525 vs +0.0205) |
| R2 long-window parity: MROUTE(150) ≥ PHASE(150) − 5% | **PASS** (+0.4079 vs +0.4067) |
| R3 timing-not-volume: \|MROUTE−PHASE\| melts ≤ 15% at 150 | **PASS** (225 vs 218, +3%) |
| R4 melt-lever safety: MROUTE_A(150) ≥ PHASE(150) − 5% | **PASS** (+0.4082) |
| R5 E0e-D2 premise: PHASE(150) young melt fraction > 0.5 | **PASS** (196/218 = **0.90**) |

## 3. Interpretation

**R5 certifies the E0e-D2 premise directly:** 90% of PHASE's long-phase melts happen in the young window. The churn mechanism lives where E0e said it lives.

**R2/R3/R4 are the positive core:** the melt lever re-times churn without changing its volume (225 vs 218 melts; 33 moved young at L=75 with volume flat), and both the half-phase and accelerate-everywhere variants preserve the +0.407 large-L gain. Contrast E0e: commit-side remission cost −0.085 at L=150. The reason is pacing — the melt lever only changes *when stale (opposed) material reopens*; every subsequent commit still runs under the 1/tick budget at PHASE pace, so the churn stream's rate profile survives. Commit-side remission removed a pacing constraint; melt-side acceleration merely re-orders invalidation. **The large-L gain lives in the volume+pacing of the churn stream, not in the exact timing of individual melts.**

**R1's failure maps the lever's reach.** At L=15 the churn is *not* young-concentrated (46%) and the certificate needs `consistency ≥ 0.8` sustained — one tick of acceleration moves exactly one melt (26 vs 21 young, 47 vs 46 total) and the gain is untouched. A faster certificate cannot fix a phase whose churn cycle doesn't fit inside it; the short-L deficit is a *rate* problem (the commit budget throttles re-adaptation), which only the commit-side budget lift reaches (TAGR +0.1226, E0d/E0e). At L=75 the lever mildly *hurts* (+0.0340 vs +0.0461) — there the young window is long enough that early invalidation spends sites the deep window still needed.

**Position-gating is unnecessary on the melt side at long L** (MROUTE_A ≈ MROUTE ≈ PHASE at 150, R4) but mildly correct at mid L (MROUTE_A < MROUTE at 40/75, and *harmful* at 15: −0.1056). The melt side is position-insensitive exactly where the effect is strong and position-sensitive where it is weak — the opposite of the commit side.

## 4. The final two-lever map (E0d → E0e → E0f)

| Lever | Short L (15) | Mid L (40–75) | Long L (150) |
|---|---|---|---|
| Commit-side remission (TAGR/REGIME) | **+0.12 / +0.14** (active; budget-mediated) | mixed | **−0.085** (toxic: breaks churn pacing) |
| Melt-side acceleration (MROUTE) | **0.000** (inert: churn not young-bound) | +0.032 @ 40 / −0.012 @ 75 | **+0.001** (free: pacing preserved) |
| No machine (FIXED) | +0.033 | best gain, worst retention (retM 1.02 @ 15) | −0.085 |

The two mechanisms are governed by **different levers with opposite L-profiles**, and no fixed-rule position schedule separates them: the long-L-safe rule has no short-L effect, and the short-L-active rule poisons long L. E0f therefore closes the position-gating programme: the remaining synthesis directions are stateful or budget-shaping DCPs (e.g. a per-phase commit-budget allocation instead of 1/tick), which depart from the fixed-rule contract by design. Ledger: **E0f-D1** (R1: melt lever inert at L=15 — certificate episodes and churn distribution are not young-bound at short L), **E0f-D2** (L=75 observation: young melt acceleration slightly *reduces* gain at mid-long L).

## 5. Artifacts

- `scripts/e0f_melt_routing.jl` — preregistered instrument (canary/short/ensure/grid75/grid150/grid/checks; resumable row cache with melt-position diagnostics)
- `docs/e0f_rows.csv` — all 16 (arm, L) rows; `docs/e0f_checks_output.txt` — final check evaluation
- Source: FixedRuleController.jl (MeltRoutingController), ReferenceKernel.jl (budget membership), PlasticWeights.jl (exports), test/phase_machine.jl (6 E0f testsets)

*Generated autonomously by Buffy under Matt's standing authorization. All results reproducible with the commands above; no state outside this repository was modified.*
