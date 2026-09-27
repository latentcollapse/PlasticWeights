# E0 — Phase Diagram, Liveness, and Return-Trip Probe (Continuous FP Substrate)

**Date:** 2026-09-26
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm, commit `0d8b9c0` (FP viscoplasticity, 2702 tests)
**Environment:** Julia 1.12.6, single thread, CPU. Full suite re-verified green immediately before the sweep.
**Status:** E0 complete. E0b supersedes E0 for all conflict-related conclusions. **E1 is blocked pending gate redesign.**

---

## 1. What was run

| Step | Artifact | Result |
|---|---|---|
| Baseline verification | `Pkg.test()` | All testsets pass on Julia 1.12.6 (incl. 73-assertion FP suite) |
| Stock probe | `scripts/probe_continuous_fp.jl` | Pathological: see §2 |
| E0 sweep | `scripts/e0_phase_sweep.jl` | Superseded by E0b (design fault, §3) |
| E0b sweep | `scripts/e0b_conflict_sweep.jl` | Primary result, §4–§6 |
| Raw data | `docs/e0b_raw_output.txt` | Full 96-point grid |

Shared protocol: `Stage0MLP`, single 64-site region, VPS exposure, `beta=gamma=0.5`,
head Adam `lr=0.02`, `k_yield=k_settle=2`, `epsilon_delta=0.02`, 450 ticks
(A 150 → B 150 → A 150), no rest phases, injected-gradient material tick.

Task families:

- **E0 (faulty):** A and B were the same function with batch samples swapped.
  No conflict. E0's static-load findings remain valid; its conflict findings do not.
- **E0b (corrected):** 2-D output, `X=[1 0 -1; 1 0 -1]`, `Y_B = -Y_A` label swap.
  The material layer is task-invariant; the linear-tanh head provably cannot
  realize both mappings (`[2 1] != -[2 1]`, tanh odd). Conflict is structural.

The correction was made **before** looking at any conflict-related result — E0's
task symmetry was caught during write-up of its verdict, and the redesign was
preregistered in `e0b_conflict_sweep.jl`'s header prior to execution.

## 2. Stock probe pathology (pre-existing, now explained)

`probe_continuous_fp.jl` (load/rest schedule, Bingham, τ=0.05): eval loss
collapses 0.50 → 0.062 (t=10), then explodes to **12.4 by t=24** as the entire
seed commits during the rest phase, then oscillates 0.1 ↔ 4.5 indefinitely.
Best 0.0014 @ t=59; final 1.47. Mechanism:

1. VPS exposure is `w`, **not** `w + δ` (`src/Core/Exposure.jl`). The hot
   residual is invisible until commit.
2. Therefore every COMMIT is a forward-visible jump of magnitude ‖δ‖.
3. Rest phases make gradients vanish → stability counters accumulate → the
   whole substrate commits in a wave → the head is shocked by a coordinated
   weights change it must re-track.

**The lifecycle manufactures its own non-stationarity.** Each exposure policy
has exactly one catastrophic transition (VPS: commit; ZCS: melt). This is a
phase property of the substrate, not a bug in the probe.

## 3. E0 design fault (recorded for honesty)

E0's task family had a degenerate symmetry: `B ≡ A` under batch-permutation.
Consequences: entryB == entryA3 identically, `asym == 0` identically, and the
liveness question (re-melt under contradicting load) was never tested.
All E0 conclusions were discarded except those about static load.

## 4. E0b results — phase census (96 grid points)

| Phase | Count | Interpretation |
|---|---|---|
| uncommitted | 66 | Substrate never consolidates under sustained load; network never becomes functional (loss pinned at chance) |
| consolidated | 18 | Commits once, then never melts; "one-shot warm-up," not a dynamic phase |
| frozen | 7 | Fully committed, zero churn, task learned but substrate inert |
| mixed | 5 | Genuine post-seed lifecycle churn exists — but see §5 |
| runaway | 0 | Never observed |

**The mixed developmental phase exists but is marginal: 5/96 ≈ 5% of the grid.**
This is drns-v0.2 falsification-relevant: the stable band is narrow, though not
a single hyperparameter ridge (mixed points appear at multiple (τ, η) combos,
always at `settle=0.05`).

## 5. The two headline defects

### D1 — The settle gate is load-saturated (control channel defect)

`consecutive_stable` requires `stress_ema < settle_down`. But `stress_ema` is an
EMA of **load**, not of load *imbalance*. Under any sustained load,
`stress_ema → E|g|` ≫ any useful `settle_down`. 66/96 points never commit for
this reason; commits happen **only** when load dips toward zero.

**Observed behavior:** consolidation is *anti-causal* — the substrate commits
exactly when the task stops, and melts when it starts. Under the A→B→A stream,
commit waves land during load dips, never at moments of validated stability.
The Stage-0 settle gate measures "the world went quiet," not "the site has
converged." A site mid-learning with small consistent gradients is
indistinguishable from a site at rest.

### D2 — Bingham mobility law is structurally inert on this substrate

Bingham: 0 learning in **all 48 Bingham points**; Newtonian learns in 11.
Mechanism: `m = max(0, 1 - τ/σ)` multiplies Δδ by a mobility that is small
precisely when stress is small — but the commit gate (`settle_down`) already
restricts residual motion to the low-stress regime. The two gates are redundant
**in opposite directions**: the DCP only permits motion where the law suppresses
it. The Bingham yield gate and the settle gate annihilate each other.
(The S2-FP unit test passes because it feeds `stress_ema` directly at 1.0 with
τ=0.5 — a regime the coupled system can never reach while `settle_down` binds.)

## 6. Liveness, return trip, K3

- **Liveness (Q1): 5/96 points show any post-seed re-melt.** Under a
  contradicting task stream, a committed FP substrate almost never reopens.
  Diagnostic liveness in the FP arm is effectively absent under load.
- **Return-trip asymmetry (Q3):** among the 11 learners, 3 positive / 8 negative,
  median −0.078. The largest positive (+24.5) is an artifact of a B-entry shock
  (entryB=25.8), not history helping. **No credible positive return-trip effect
  was demonstrated.**
- **K3 (self-ossification): violated.** 7 points learned both tasks with zero
  re-melts — adaptation happened entirely through the head + pre-commit
  superplastic window, after which the substrate was inert. This is the FP arm's
  rich-get-richer: **one commit wave, then permanent rigidity.**

## 7. Verdict against preregistered criteria

| Criterion | Verdict |
|---|---|
| No stable mixed phase | **Marginal pass** — mixed phase exists but covers ~5% of grid, always at high `settle_down` |
| Deadlock (mature regions never reopen) | **FAILED** — K3 violated; liveness 5/96 under contradiction |
| Hardening ratchet | Confirmed monotone (never decays), though it was not the binding constraint in E0b — the settle gate is |
| Return-trip (history helps) | **Not demonstrated** — no credible positive asymmetry anywhere |

**Overall: the FP substrate at Stage-0 parameterization does not pass E0.**
The binding failure is not the thesis (localization of plasticity) but two
implementable-at-Stage-0 defects: the settle gate measures the wrong thing (D1),
and the constitutive law's mobility gate is redundant with the DCP gate in the
suppressive direction (D2).

## 8. E1 blockers (what must change before the four-arm run)

E1 as preregistered is **blocked**. Running it now would measure D1+D2, not the
thesis. Required first:

1. **Fix the settle gate (D1).** Stress magnitude cannot certify stability.
   Candidates (in order of preference):
   - **Prediction-error stability:** site settles when its local contribution's
     gradient sign/magnitude is stable (low *variance* of g, not low |g|),
     - **Relative stress:** `stress_ema / (stress_ema + baseline)` with an
     adaptive baseline,
   - **Gradient-direction persistence:** settling requires sustained gradient
     direction (cosine persistence), which is high during consistent learning
     and collapses at rest/noise — the exact inverse of the current gate.
   Note the corrected gate must still distinguish "converged" from "rest" —
   direction-persistence does this naturally: at rest, gradients are noise
   (direction random); during converged learning, gradients are small but
   *consistent*; during conflict, direction flips.
2. **Fix the mobility law (D2).** Either decouple the law's regime from the
   DCP gates (mobility should *shape* motion, not veto it twice), or make
   Bingham's yield reference the *conflict* signal rather than raw stress
   magnitude (per v0.2 §8.3 — cosine conflict vs consolidated reference).
3. **Then** rerun E0b (it is the regression harness for both fixes) and require:
   mixed phase ≥ ~20% of grid, liveness under contradiction > 0 for all
   learners, and no commit-wave shocks (max single-tick eval-loss jump bounded).

## 9. What survives

- The reference kernel's determinism and invariants held through 96 × 450-tick
  runs with zero HardFailures. The machinery is sound; the gates are wrong.
- The E0b harness (cyclic conflicting tasks, distinct-site melt census,
  boundary-tick entry asymmetry, retention telemetry) is the right instrument
  and is reusable as-is for post-fix regression.
- The commit-shock finding (§2) independently motivates the exposure-policy
  axis: VPS's commit jump and ZCS's melt jump are now *measured* phenomena,
  not hypotheticals.

## 10. Artifacts

- `scripts/e0_phase_sweep.jl` — E0 (superseded, kept for the fault record)
- `scripts/e0b_conflict_sweep.jl` — corrected instrument
- `docs/e0b_raw_output.txt` — full grid
- This report: `docs/E0_PHASE_REPORT_2026-09-26.md`

*Generated autonomously by Buffy under Matt's standing authorization. All
results reproducible with the commands above; no state outside this repository
was modified.*
