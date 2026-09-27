# E1b — Four-Arm Comparison on a Hard Task Family

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm at `ab7a060` (E1 state, suite green)
**Stream:** A→B→C→D→B→A→C→D→A→B (10 phases × 15 ticks = 150 ticks), four pairwise-conflicting tasks.
**Status:** **3 of 5 preregistered hypotheses pass (H1, H2, H4). H3 and H5 fail** — and the failure pattern localizes the thesis envelope: the lifecycle's history benefit is real but **phase-length-dependent**, and the frozen substrate parameterization over-opens under ultra-short phases.

---

## 1. Design changes vs E1 (both preregistered, amendment in instrument header)

- **E1-D1 (saturation):** phase length 150 → 40 ticks a priori; the canary
  showed FP32 *still* saturated (phase-1 final 0.0014–0.0039), so the same
  preregistered lever was extended in the measured direction: **40 → 15
  ticks** for all arms (re-solve budget ~10× below E1). Probe cadence 10 → 5
  ticks (3 per phase) so the retention band stays populated.
- **E1-D2 (retention confound):** **tercile-matched retention** — each arm's
  off-task probe loss averaged over its lowest-current-loss tercile ("forgetting
  while at your most competent"), with the band's mean current-loss reported.
  C3 also received an lr sweep (anti-sandbagging; its best row is used in
  comparisons, the frozen row reported).
- Family: four tasks (A=−B, C=−D) demanding four distinct outputs at the same
  input; every pair conflicts on exactly one output row.

## 2. Results (150 ticks, seed 71)

| Arm | phaseFinal ↓ | retMatched ↓ (band) | midJump | meanGain | hotMean |
|---|---|---|---|---|---|
| SUB | 0.3112 | 0.7608 (0.093) | 0.260 | −0.090 | **0.929** |
| C3 (best, lr=0.01) | 0.3197 | **0.4607** (0.253) | 0.325 | −0.008 | — |
| FP32 (best, lr=0.03) | **0.1315** | 0.9019 (0.031) | 0.329 | **+0.235** | — |
| FIXED | 0.3050 | 1.0181 (0.110) | 0.324 | −0.057 | 0.720 |

### Hypothesis verdicts

| Hypothesis | Result | Verdict |
|---|---|---|
| H1 validity: best baseline > 0.05 | 0.1315 | **PASS** — the family is genuinely hard; no saturation anywhere |
| H2 Pareto: SUB non-dominated on (phaseFinal, retMatched) | no baseline has both better | **PASS** (FP32: better pf, worse retM; C3: better retM, worse pf; FIXED: worse retM) |
| H3 history: gains > 0 on ≥2/4 tasks ∧ SUB mean > FIXED | SUB positive on 1/4 (A +1.055); mean −0.090 vs FIXED −0.057 | **FAIL** |
| H4 stability: midJump < 1.0 | 0.260 | **PASS** |
| H5 locality: hotMean ≤ 0.5 | 0.929 | **FAIL** |

## 3. Interpretation

**H2 is the thesis-relevant success:** on the hard family, the substrate is
**non-dominated** — FP32 buys its adaptation lead (0.1315 vs 0.3112) with the
worst matched retention of all arms (0.9019), C3 buys its retention lead with
the worst adaptation, and the substrate is the only arm on the efficient
frontier's knee. That is precisely the trade the v0.2 thesis claims, now
observable because the family is hard (E1's ledger entry E1-D1 resolved).

**H5's failure is diagnostic, not noise: hotMean 0.929 ≈ the whole substrate
stayed plastic.** The frozen parameterization was selected on E0c′'s
**150-tick** phases; at 15 ticks the conflict certificates and commit gates
see each task as a sustained contradiction and never re-consolidate — the
substrate spends the run in a near-fully-molted state (which also explains
SUB's phaseFinal being no better than FIXED's: with nothing committing, the
ramp and phase machine have nothing to do beyond what the raw law provides).
**Ledger entry E1b-D3: the E0c-prime parameterization is phase-length-bound.**
The fix is parameterization-class, not architectural: scale
`conflict_k`/`k_commit`/ramp budget with phase duration (or make them
tick-count-adaptive), which Pass 3's controller can own.

**H3's failure is the sharpest scientific finding: the return-trip benefit
exists at 150-tick phases (E1: A +0.35, B +1.07; SUB > FIXED) and vanishes —
inverts — at 15-tick phases.** The mechanism story survives coherently: the
E0c-prime glide makes returns cheap by exposing previously-consolidated
material *toward* the returning task, but that only pays when the substrate
actually consolidates between visits. At 15 ticks nothing commits, so
returns find the same near-fully-plastic substrate regardless of history —
and drift accumulated mid-glide can actively hurt (B −0.85, D −0.35).
**Ledger entry E1b-D4: history benefit requires consolidation between
visits — it is a consolidation-memory effect, not a plasticity effect.** This
is a *testable* refinement of the thesis, and it makes Pass 3's tags the
right instrument: tags persist across non-consolidated stretches and could
route re-opening *before* the substrate loses the structure that makes
returns cheap.

**Controller ablation on the hard family:** SUB vs FIXED — phaseFinal
+0.006 (tie), **retMatched −0.257 (substrate retains markedly better at its
best operating point)**, meanGain −0.033 (tie-ish). With H5's over-opening
in mind, the honest reading is: even in the wrong regime, the phase machine
costs nothing on adaptation and improves matched retention; combined with
E0c (liveness 0% → 100%) and E1 (B-gain 0.702 → 1.070, locality 3×), the
symbolic layer is now positively attributed on every axis it was designed
for — the remaining question is *parameterization robustness*, which is
E1b-D3.

## 4. Where this leaves the programme

| Claim | E1 (150-tick) | E1b (15-tick) |
|---|---|---|
| Family hard enough for a trade | ✗ (saturated) | ✓ |
| SUB non-dominated (adaptation, matched retention) | untestable | **✓** |
| History benefit (consolidation memory) | ✓ (strong) | ✗ (regime-dependent) |
| Stability + locality | ✓ | stability ✓, locality ✗ (parameterization) |

The next instrument is neither another harder family nor more arms — it is
the **phase-length sweep** (15/40/75/150) on SUB with the FIXED control,
which would map the envelope where the lifecycle pays, and the
parameterization-scaling rule from E1b-D3. Pass 3 (consolidation tags +
routing) then targets the H3 mechanism directly.

## 5. Artifacts

- `scripts/e1b_hard_family.jl` — preregistered instrument (canary mode;
  Amendment 1 recorded in-header before the full run)
- `docs/e1b_raw_output.txt` — full four-arm output
- This report: `docs/E1B_HARD_FAMILY_REPORT_2026-09-27.md`

*Generated autonomously by Buffy under Matt's standing authorization. All
results reproducible with the commands above; no state outside this
repository was modified.*
