# E0e — Pass 3b: Regime-Adaptive Routing

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm at `4cfae6f` (E0d state; Pass-3 additions, suite green)
**Status:** **3 of 7 preregistered results pass (C0, R1, R5); R2/R3/R4/R6 fail informatively.** Young-window remission **works** — REGIME beats PHASE at every L ≤ 75 and is the best arm in the grid at L=75 — but routing by phase position alone **cannot restore the churn mechanism**: once the young window runs unbudgeted, the phase's trajectory is TAGR-shaped for its entire length, and the deep window never runs the churn loop. The synthesis "TAGR when young, PHASE when deep" is **not realizable by position-gating alone** in this architecture.

---

## 1. What was built (Pass 3b)

- **Regime metadata, harness-declared and DCP-inert:** `phase_length` on `RegionState` (keyword, default 0 = undeclared) and `MaterialTrainingConfig` (keyword, default 0), threaded through `reference_material_tick!` and `create_snapshot`. `FPSnapshot` gained `phase_length` and a DERIVED `ticks_into_phase = mod(tick−1, phase_length)` (position is computed from the authoritative tick, never accumulated — the controller stays **stateless**). HardFailure discipline: negative lengths, out-of-range positions, position-without-length are construction errors; for REGIME an undeclared length is a decision-time error (no silent degeneration).
- **`RegimeAdaptiveController` (REGIME; k_commit=2, young_fraction=0.5):** while `ticks_into_phase` is inside the young boundary, tag-aligned melted sites commit on the first certified settle tick (dwell remitted — the TAGR rule); at or beyond the boundary the controller is behaviorally the phase machine. The melt side is byte-identical to PHASE's at every position (tested).
- **Window-following commit budget (post-amendment):** with `budgeted=false` (preregistered synthesis arm) the young window runs the TAGR rule in full — remission AND no 1/tick commit budget — and the deep window the PHASE rule in full — dwell AND the 1/tick budget. `budgeted=true` (REGIME_B ablation) keeps the budget in both windows.
- Full suite green (63 E0e assertions in 10 new testsets): metadata derivation/validation, young-window TAGR-equivalence, deep-window PHASE-equivalence, boundary arithmetic (float-snap tolerant), melt-side invariance, HardFailure on undeclared length (unit + end-to-end), budget membership, unbudgeted-young/deep-budgeted behavior (E0e-D1 lock), end-to-end determinism.

## 2. Amendment E0e-D1 (declared BEFORE the L=75/150 runs)

The original preregistration budgeted REGIME in both windows (protocol parity with PHASE). The short-window run showed REGIME **byte-identical** to PHASE at L=15 and L=40 (commits 51/288, melts 46/248, identical rows), and a diagnostic showed even `young_fraction=1.0` identical to PHASE while E0d's committed TAGR numbers differ strongly (unbudgeted; commits 100/406, melts 73/345).

**Conclusion: under the phase machine's 1/tick commit budget, dwell remission is behaviorally INERT.** The budget queue, not `k_commit`, gates recommit timing: a site refused by the budget keeps its persistent settle certificate and is admitted on a following tick anyway, so shaving the dwell changes nothing. E0d's mechanism-A effect is **budget-mediated** — TAGR's short-L advantage comes from lifting the rate cap on the commit side, with remission deciding *which* sites commit immediately. The amendment gives the young window the full TAGR rule; R5 was preregistered in the amendment to attribute exactly this. No check was reinterpreted after seeing long-L data.

## 3. Results (four-task family, E1b/E1c/E0d protocol, seed 71)

| L | PHASE | REGIME | REGIME_B | TAGR | FIXED |
|---|---|---|---|---|---|
| 15 | −0.0903 | **+0.0364** | −0.0903 | +0.1226 | −0.0572 |
| 40 | +0.0205 | **+0.1414** | +0.0205 | +0.1372 | +0.1618 |
| 75 | +0.0461 | **+0.0757** | +0.0461 | +0.0720 | +0.0647 |
| 150 | **+0.4067** | +0.3213 | +0.4067 | +0.3254 | +0.3215 |

Melts/commits: L=15 REGIME 64/83 (PHASE 46/51, TAGR 73/100); L=40 REGIME 271/332 (PHASE 248/288); L=75 REGIME 339/401 (PHASE 396/458); L=150 REGIME 68/132 (PHASE 218/282, TAGR 63/127).

| Result | Verdict |
|---|---|
| C0 canary: PHASE(150) reproduces E0d committed (+0.4067, 218 melts) | **PASS** (bit-exact, re-verified on every run) |
| R1 short-window win: REGIME>PHASE at 15 and 40, REGIME(15)>0 | **PASS** (+0.0364 vs −0.0903; +0.1414 vs +0.0205) |
| R5 budget attribution (E0e-D1): REGIME(15) > REGIME_B(15) ≈ PHASE(15) | **PASS** (REGIME_B byte-identical to PHASE at 15/40/75/150) |
| R2 long-window parity: REGIME(150) ≥ PHASE(150) − 5% | **FAIL** (+0.3213 vs +0.4067) |
| R3 churn-trace parity: \|REGIME−PHASE\| melts ≤ 15% at 150 | **FAIL** (68 vs 218) |
| R4 adaptivity attribution: REGIME(150) > TAGR(150) | **FAIL** (+0.3213 vs +0.3254) |
| R6 window parity: REGIME(150) == REGIME_B(150) on gain and melts | **FAIL** (REGIME_B == PHASE; REGIME == TAGR-shaped) |

## 4. Interpretation: the window is not a switch — it is a trajectory fork

**What worked.** The young window delivers mechanism A cleanly and *sparing beats fully*: REGIME spends remission only on the phase's first half and beats PHASE at every L ≤ 75, edges TAGR at both 40 (+0.1414 vs +0.1372) and 75 (+0.0757 vs +0.0720), and cuts TAGR's excess churn at 15 (64 vs 73 melts). Regime metadata and the stateless position-derivation are sound and tested.

**What failed, and why.** REGIME(150) is not a blend — it is TAGR's trajectory with slightly more commits (132 vs 127). Melts in this regime happen overwhelmingly in the EARLY portion of a phase (the task switch shock), i.e. inside the young window. A site melted young and remitted commits immediately, re-hardens, and carries its committed state into the deep window; by the time the position crosses the boundary there is nothing left to gate — the deep window inherits a post-TAGR state and its 1/tick budget has no queue to drain. The window is evaluated **per commit event**, but the churn mechanism is a **phase-global trajectory**: to preserve mechanism B, the *early* phase must run churn too (that is where its melts happen), which position-gating forbids by construction.

**The two-mechanism picture, corrected.** Mechanism A (tag-carried memory) is budget-mediated and needs the rate cap lifted at the moment of recommit. Mechanism B (melt/recommit churn) needs churn events spread across the phase, including its earliest ticks. These requirements are **simultaneously satisfiable per-event** (remission touches only tag-aligned commits; churn events are mostly opposed-load melts) — E0d already ran both at once, globally, as TAGR. What is NOT satisfiable is *position-gating* them: "young" and "deep" do not partition the mechanisms, because the mechanisms do not partition by phase position. The honest statement of E0e: **the history effect is carried by what happens in the young window; PHASE's large-L advantage is downstream of letting young-window churn run.**

## 5. Consequences for the programme

1. **Pass 3b's synthesis fails as position-gating.** Ledger: E0e-D1 (budget inertness under remission — pre-grid finding), E0e-D2 (R2/R3/R4/R6: young-window rule choice forks the whole phase trajectory; deep-window behavior cannot be selected independently).
2. **The Pareto frontier across L is real and controller-level, not window-level:** PHASE wins L=150, REGIME wins L=75 and the sign at 15/40, TAGR wins 15/40 outright. If a single controller must win everywhere, the lever is not *when* remission is allowed but the *melt side* (E0d-R4 showed TAGR's melts ≠ PHASE's) or a stateful/rate-shaping DCP — both departures from the current fixed-rule contract.
3. **Reproducibility discipline held:** the row cache (docs/e0e_rows.csv) rebuilt after the outage reproduced every pre-outage number bit-exactly; the C0 canary re-verified the E0d baseline through the new code path (proving the metadata is DCP-inert for every committed arm).

## 6. Artifacts

- `scripts/e0e_regime_adaptive.jl` — preregistered instrument (canary/short/ensure/grid75/grid150/grid/checks; resumable row cache)
- `docs/e0e_rows.csv` — all 20 (arm, L) rows; `docs/e0e_short_output.txt`, `docs/e0e_checks_output.txt` — run transcripts
- Source: FixedRuleController.jl (REGIME controller, young-boundary helper), Snapshot.jl (phase_length/ticks_into_phase), RegionState.jl + Initialization.jl (declared metadata), ReferenceKernel.jl (pass-through, window-following budget), MaterialTraining.jl (config field), PlasticWeights.jl (exports), test/phase_machine.jl (10 E0e testsets)

*Generated autonomously by Buffy under Matt's standing authorization. All results reproducible with the commands above; no state outside this repository was modified.*
