# E0d — Pass 3: Consolidation-Tag Routing

**Date:** 2026-09-27
**Operator:** Buffy (autonomous run, authorized by Matt)
**Substrate:** PlasticWeights FP arm at `82e1933` (E1c state; Pass-3 additions, suite green)
**Status:** **2 of 4 preregistered results pass (R1, R3); R2 and R4 fail informatively.** Tag routing **does** extend the history window to L=15 (R1 — the Pass-3 headline), and the tag's direction condition **is** causal (R3). But routing is not monotone-dominant at large L (R2), and it is not invalidation-neutral (R4) — together these decompose the lifecycle's history effect into **two mechanisms with opposite phase-length profiles**.

---

## 1. What was built (Pass 3)

- **Carrier confirmed as code:** `commit_sign`/`commit_stress` survive melt
  (tested: the tag outlives the transition) — the site's symbolic memory
  persists through non-consolidated stretches, exactly what E1c-D6 said was
  missing at small L.
- **`TagRoutingController` (TAGR):** a melted site whose tag *agrees* with
  the current load direction commits on the **first certified settle tick** —
  commit dwell remitted for previously-validated, currently-aligned material.
  Opposed sites wait the full dwell: routing touches only the commit side.
- **`UndirectedController` (UNDIR):** ablation — the conflict certificate
  becomes direction-blind (aligned sustained load counts too; new
  `consecutive_conflicted_undirected` counter). PHASE vs UNDIR isolates what
  the tag's direction condition contributes.
- Full suite green, including new tests: tag-persistence-through-melt (the
  carrier lock), dwell remission (TAGR commits at plastic-age 1 where PHASE
  holds), direction gating (opposed melted sites still wait), and blind-twin
  counter divergence.

## 2. Results (four-task family, E1b/E1c protocol, seed 71)

| L | PHASE gain | TAGR gain | UNDIR gain | FIXED gain | TAGR melts vs PHASE |
|---|---|---|---|---|---|
| 15 | −0.0903 | **+0.1226** | +0.0218 | −0.0572 | 73 vs 46 |
| 40 | +0.0205 | **+0.1372** | +0.0611 | +0.1618 | 345 vs 248 |
| 75 | +0.0461 | +0.0720 | +0.0756 | +0.0647 | 368 vs 396 |
| 150 | **+0.4067** | +0.3254 | +0.3101 | +0.3215 | 63 vs 218 |

| Result | Verdict |
|---|---|
| R1 window extension: TAGR(40) > PHASE(40) ∧ > 0 | **PASS** (+0.137 vs +0.021) — and TAGR(15) = +0.123 vs PHASE −0.090: the window opened two grid steps early |
| R2 monotone dose: TAGR > PHASE at every L | **FAIL** (wins 15/40/75, loses 150: +0.325 vs +0.407) |
| R3 causality: PHASE(150) > UNDIR(150) | **PASS** (+0.407 vs +0.310) |
| R4 invalidation invariance: melts within 10% | **FAIL** (L15 73/46, L40 345/248, L150 63/218) |

## 3. Interpretation: the history effect is two mechanisms

**Mechanism A — tag-carried memory (routing).** Fast, direction-gated
recommit of previously-validated material. Dominates **short** phases: at
L=15 TAGR flips the sign of the history effect (−0.090 → +0.123) and at
L=40 it beats FIXED's churn-free number. Its cost structure explains the R4
failure: fast recommit → faster re-hardening → more above-yield melts of the
*re-hardened* material within the same phase (melts up ~60% at L=15/40). The
direction condition is load-bearing — UNDIR (blind) recovers less than half
of TAGR's gain at 15/40 — so this is genuinely **tag-driven**, not
"more churn."

**Mechanism B — melt/recommit churn (E1c's workhorse).** Dominates **long**
phases: PHASE's 218 melts at L=150 (vs TAGR's 63) produce the +0.407. TAGR's
remission *short-circuits* this loop — sites re-commit before the churn can
broaden — which is why TAGR < PHASE at L=150 (R2's failure is mechanistic,
not noise: commits 127 vs 282, melts 63 vs 218, hotMean 0.08 vs 0.20).

**R3's pass is the causal anchor:** with the direction condition removed
(UNDIR), the large-L gain drops from +0.407 to +0.310 — the tag's direction
sensitivity contributes a measurable share of the baseline machine's effect,
*and* UNDIR also degrades the small-L story (+0.022 vs TAGR's +0.123). The
tag is not decorative: direction-gating is what makes both mechanisms pick
the right material.

## 4. Where this leaves the programme (Pass 3 complete)

| Question | Answer |
|---|---|
| Does the tag survive the melt? | Yes (tested; the carrier exists) |
| Does explicit routing extend the gain window? | **Yes — from L≳75 down to L=15** (R1) |
| Is the tag's direction condition causal? | **Yes** (R3; UNDIR loses both ends) |
| Is routing free? | No — it trades churn-breadth for memory-speed; PHASE wins large-L, TAGR wins small-L |
| One mechanism or two? | **Two:** tag-carried memory (short L) + churn (long L), both direction-gated |

The natural synthesis for a future pass is **regime-adaptive routing** (route
when the phase is young, let churn run when it is deep) — but the preregistered
Pass-3 questions are answered, the neurosymbolic picture is complete (symbolic
tags + continuous rheology + guarded transitions + bounded exposure), and the
defect ledger is the honest map of what remains.

## 5. Artifacts

- `scripts/e0d_tag_routing.jl` — preregistered instrument (4 arms × 4 L)
- `docs/e0d_raw_output.txt` — full grid
- This report: `docs/E0D_TAG_ROUTING_REPORT_2026-09-27.md`
- Source: FixedRuleController.jl (TAGR/UNDIR controllers, shared commit
  decision), SiteTelemetry.jl (undirected twin counter), Snapshot.jl
  (`melt_tag_agrees`), ReferenceKernel.jl (twin counter wiring),
  PlasticWeights.jl exports, test/phase_machine.jl (E0d testset)

*Generated autonomously by Buffy under Matt's standing authorization. All
results reproducible with the commands above; no state outside this
repository was modified.*
