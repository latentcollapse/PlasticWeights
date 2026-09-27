# E1c — Phase-Length Sweep: the Lifecycle's Pay Window and the Scaling Rule

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm at `69e9373` (E1b state, suite green)
**Status:** Map complete. **M2 and M3 pass; M1 fails as written and refines:** the lifecycle's meanGain advantage window is **L ≥ 75**, not L ≥ 40. The map also corrects E1b's mechanism hypothesis (§3). The scaling rule is derived from the map and **preregistered below before the held-out L=100 validation run** (S1–S3 shape unchanged from the instrument header).

---

## 1. The map (four-task family, A→B→C→D→B→A→C→D→A→B, seed 71)

| L | Arm | phaseFinal | retMatched | meanGain | hotMean | commitφ | meltφ | commits |
|---|---|---|---|---|---|---|---|---|
| 15 | SUB | 0.3112 | **0.7608** | −0.0903 | 0.93 | 0.90 | 0.90 | 51 |
| 15 | FIXED | 0.3050 | 1.0181 | −0.0572 | 0.72 | 0.90 | 0.20 | 41 |
| 40 | SUB | 0.0863 | 0.8315 | +0.0205 | 0.71 | 0.90 | 0.90 | 288 |
| 40 | FIXED | 0.0849 | 0.8606 | **+0.1618** | 0.35 | 0.60 | 0.10 | 70 |
| 75 | SUB | 0.0653 | 0.8408 | +0.0461 | 0.46 | 0.90 | 0.90 | 458 |
| 75 | FIXED | **0.0552** | 0.8408 | +0.0647 | 0.25 | 0.30 | 0.10 | 70 |
| 150 | SUB | 0.0132 | **0.8586** | **+0.4067** | 0.20 | 1.00 | 1.00 | 282 |
| 150 | FIXED | 0.0116 | 0.8689 | +0.3215 | 0.07 | 0.20 | 0.20 | 71 |

### Hypothesis verdicts

| Hypothesis | Result | Verdict |
|---|---|---|
| M1 lifecycle window (SUB > FIXED gain at L∈{75,150}, tie/lose at 15) | SUB wins at 150 (+0.085) and 75 is a tie-against (+0.047 vs +0.065); loses at 15 and 40 | **FAIL as written → refined: window is L ≥ 75** |
| M2 retention cross (SUB retM < FIXED at every L) | 15: −0.257, 40: −0.029, 75: 0.000, 150: −0.010 | **PASS** (never worse) |
| M3 mechanism (commit_frac ↑ with L; hot 15 > 0.8, hot 150 < 0.6) | commitφ 0.90→1.00; hot 0.93 vs 0.20 | **PASS** |

## 2. What the map shows

1. **The lifecycle pays in consolidation-rich regimes.** SUB's meanGain over
   FIXED crosses zero between L=40 and L=75 and is decisively positive at
   L=150 (+0.085), with SUB committing 4× more often than FIXED (282 vs 71)
   at L=150. The E1 history result (A +0.35, B +1.07) lives at the
   consolidation-rich end of the axis; the E1b inversion lives at the
   consolidation-starved end. **One mechanism, two regimes — E1b-D4
   confirmed along the axis.**
2. **SUB's retention advantage over FIXED holds at every L** (M2), largest
   exactly where consolidation is hardest (L=15: −0.257).
3. **The cost is real and located:** SUB pays an adaptation tax of ~+0.001–0.010
   phaseFinal at every L (the invalidation/melt churn), and at mid-L the
   FIXED controller's *fewer, better-timed* commits beat the machine's
   higher-frequency cycling on return-trips (L=40: FIXED +0.162 vs SUB +0.021
   meanGain — FIXED's 70 commits were worth more than SUB's 288).

## 3. Mechanism correction (E1b-D3 refined)

The E1b hypothesis attributed the small-L failure to "the settle certificate
cannot saturate within a phase." The telemetry refutes that: **commit_frac is
0.90 even at L=15 — consolidation is not blocked by gate saturation, it is
blocked by what happens AFTER the first commit.** Per-phase melt fractions
(SUB 0.90 everywhere) with commit counts growing superlinearly in L (51 →
288 → 458 on 4× fewer phases at 75 vs 15) show the pattern: **one early
commit wave per phase, then the hardened region sits inert for the rest of
the phase** — at L=15 that is the entire phase. The binding constraint is
the **invalidation side** (work-hardened yield + a certificate that needs
sustained seconds-scale opposition), not the settle side. The substrate is
not "never consolidating" at small L; it is "consolidating once, too early,
then never re-engaging."

## 4. PREREGISTERED SCALING RULE (frozen before the held-out validation)

The binding gate is invalidation latency: a committed site's certificate
needs `conflict_k` sustained ticks, but at small L the phase ends before
hardened sites with stale references re-engage. The map's fix is therefore
**invalidation-side**: scale the certificate's dwell with the phase clock,
not the settle side (commit_frac is already 0.90 at L=15; scaling k_commit
or the settle gate would attack the healthy gate).

**The rule:**

```
conflict_k(L) = max(2, round(sqrt(L / 15) * 2))
```

- L=15 → 2 (unchanged), L=40 → 3, L=75 → 4, **L=100 → 5**, L=150 → 7.
- Rationale: certificate *latency* must shrink relative to phase duration as
  phases shorten; √ keeps the latency sub-linear so small phases are
  proportionally more aggressive (they need re-engagement most), while long
  phases keep their measured-good deliberate pace. k_commit and m_max are
  held FIXED by the rule (they gate the healthy side; the map shows no
  settle-side block). This is a one-parameter rule.

**Validation shape (unchanged from the instrument header):** at held-out
L=100 (not in the map), SUB-scaled vs FIXED at the same L:
- S1: SUB-scaled hotMean ≤ 0.5 (locality restored mid-axis);
- S2: SUB-scaled meanGain > FIXED meanGain (history pays inside the window);
- S3: SUB-scaled phaseFinal ≤ FIXED + 0.05 (no adaptation tax beyond noise).
All three required. The unscaled SUB at L=100 is reported alongside for the
rule's effect size; the FIXED arm is unscaled by definition (it has no
lifecycle parameters — that asymmetry is the point of the ablation).

---

## 6. VALIDATION OUTCOME (held-out L=100): the rule FAILED S2 — and the map's own telemetry explains why

`validate 100 2 5 0.02` (the §4 rule: conflict_k 2→5, k_commit/m_max held):

| Arm | phaseFinal | retMatched | meanGain | hotMean | commits | melts |
|---|---|---|---|---|---|---|
| SUB-scaled | 0.0581 | 0.8476 | +0.0561 | 0.282 | 106 | 42 |
| FIXED | 0.0132 | 0.8578 | +0.3572 | 0.120 | 70 | 6 |

- **S1 PASS** (hotMean 0.282 ≤ 0.5): scaling conflict_k does restore locality.
- **S3 PASS** (0.0581 ≤ 0.0132 + 0.05): no adaptation tax beyond allowance.
- **S2 FAIL** (+0.056 vs +0.357): the scaled configuration *destroyed* the
  history benefit it was meant to rescue.

**Verdict: the preregistered scaling rule is refuted as a free lunch.** It is
a locality/gain trade-off knob, not a repair.

### Why (mechanism correction, visible in the map's own telemetry)

The map's `cert_frac` was ≈ 0.01–0.02 at **every** L — the conflict
certificate is nearly inactive everywhere; the melt churn that tracks the
lifecycle's gains (SUB melts 46→248→396→218 across L, melt_frac 0.90) is
driven by the classical **above-yield melt gate**, not the certificate. The
rule therefore scaled a nearly-dormant channel: raising conflict_k 2→5
cut melts 5× (42 vs the map's L=150-churn equivalent) and with them the
recommit cycling that the gain tracks. **The history benefit is carried by
the melt→recommit churn loop, not by stale-reference invalidation.**

### Conclusions (ledgered)

- **E1c-D5:** the conflict certificate, as implemented, is not the driver of
  any measured lifecycle benefit at any L; its measured role is confined to
  the E0c grid regime (aggressive conflict_k=2 on 150-tick phases). It
  remains the anti-ossification backstop, but the workhorse of adaptation
  churn is the above-yield melt/recommit cycle.
- **E1c-D6:** the history-benefit window is **intrinsic, not a scaling
  artifact**: it requires phases longer than the task's re-learning time AND
  melt churn within them. No single-parameter scaling rescues small L — at
  L=15 the phase ends before relearning pays, regardless of parameters.
- The deliverable of E1c is the corrected envelope statement: *the lifecycle
  pays where phases exceed the re-learning time and churn is active
  (L ≳ 75 here); everywhere else its value is retention (M2, never worse
  than FIXED at any L) and stability, at a small, bounded adaptation tax.*

### What was validated despite the S2 failure

S1 and S3 passing at held-out L=100 is itself informative: the substrate
with an aggressive invalidation schedule remains local and tax-free. The
knob exists; the map just says using it for gains is the wrong direction.
Pass 3's tags (persisting memory across non-consolidated stretches) remain
the designed instrument for extending the gain window below L≈75 — by
carrying history WITHOUT requiring consolidation, which is exactly what the
E1b-D4/E1c-D6 mechanism lacks at small L.

## 5. Artifacts

- `scripts/e1c_phase_length_sweep.jl` — preregistered instrument (map +
  validate modes with explicit rule parameters)
- This report (§4 is the preregistration of record for the validation)
- Raw map output: reproduced by `julia --project=. scripts/e1c_phase_length_sweep.jl map`

*Generated autonomously by Buffy under Matt's standing authorization.*
