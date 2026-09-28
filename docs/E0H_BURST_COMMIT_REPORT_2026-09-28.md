# E0h — Burst-Width Commit Allowance (Pass 3e)

**Date:** 2026-09-28 · **Status:** COMPLETE (grid done, ledger written)
**Preregistration:** `scripts/e0h_burst_commit.jl` header (declared before any run; no BURST grid row ran before it)
**Rows:** `docs/e0h_rows.csv` (16 rows, resumable cache) · **Checks:** `docs/e0h_checks_output.txt`
**Suite:** full `Pkg.test()` green before the grid (7 new E0h testsets, 30 assertions); the kernel's two-pass restructure was verified byte-safe by an R0 sanity (PHASE@150 = 282 commits / 218 melts reproduced exactly) before any new arm ran.

## 1. Mechanism under test

E0g-D1 pinned the short-L constraint: NOT per-phase volume (the E0g quota never
consumed at L=15), NOT dwell (E0f-D1) — but the **1/tick pacing draining the
burst structure** of settle-certificate arrivals (up to 12 commit-intents crowd
a single short phase). E0h shapes admission WITHIN each tick's burst:

```
cap(tick) = max(1, floor(burst_fraction · W)),   W = raw commit-intent count
```

W is observed statelessly in a discarded intent pass (decide() pure, snapshots
immutable); the kernel admits the leading `cap` intent sites in canonical order;
denied sites keep their persistent counters. Per-site rule byte-exact PHASE (no
remission), melts untouched, budget position-blind (no phase_length consulted).
The arm is the controlled decomposition of TAGR: **TAGR = burst admission (this
lever) + dwell remission**. R0 discipline: the budget is computed before the
admission loop for every arm and one truncation pass applies to all arms, so
previously committed arms are bit-identical (verified).

## 2. Results (mean per-task gain; commits/melts; busiest single tick)

| L   | PHASE               | BURST (0.5)          | BURST_A (1.0)        | FIXED          |
|-----|---------------------|----------------------|----------------------|----------------|
| 15  | −0.0903 (51/46, t1) | −0.0912 (60/48, t3)  | **+0.1226** (100/73, t8) | −0.0572 (41/7) |
| 40  | +0.0205 (288/248, t1)| **+0.1241** (451/393, t7) | **+0.1372** (406/345, t12) | +0.1618 (70/6) |
| 75  | +0.0461 (458/396, t1)| +0.0335 (475/414, t8) | **+0.0720** (430/368, t19) | +0.0647 (70/6) |
| 150 | +0.4067 (282/218, t1)| +0.2278 (157/93, t9)  | +0.3254 (127/63, t8)  | +0.3215 (71/7) |

- **C0 PASS** (+0.4067 / 218, bit-exact) · **R3 PASS, R4 PASS, R5 PASS**
- **R1 FAIL** (half-drain inert at L=15: −0.0912 vs −0.0903) ·
  **R2 FAIL** (half-drain toxic at L=150: +0.2278, −44% melts).

## 3. The decomposition result (E0h-D1)

**BURST_A reproduces the committed TAGR rows byte-exactly at every L:**

| L   | TAGR (committed, E0e)      | BURST_A (E0h)              |
|-----|----------------------------|----------------------------|
| 15  | +0.1226 · pf 0.2798 · 100/73 | +0.1226 · pf 0.2798 · 100/73 |
| 40  | +0.1372 · 406/345          | +0.1372 · 406/345          |
| 75  | +0.0720 · 430/368          | +0.0720 · 430/368          |
| 150 | +0.3254 · 127/63           | +0.3254 · 127/63           |

Batch-admission-without-remission IS tag routing, on this protocol and at every
regime. **E0d's mechanism A is the admission shape; dwell remission is
behaviorally redundant** — under TAGR, tag-aligned remitted sites simply join
the same-tick batch of dwell-expired sites and are all admitted together; the
per-tick stagger the budget otherwise imposes is never visible in aggregate.
E0d's causal attribution ("tag-carried memory") re-reads as batch admission of
a direction-filtered subset; the load-direction gating still selects *who*
batches, but the *benefit* comes from admission, not from the remitted dwell.

## 4. Ledger

### E0h-D1 — mechanism decomposition (R3/R4 PASS)
See §3: BURST_A ≡ TAGR byte-exact at L = 15/40/75/150. TAGR's lift decomposes
entirely into admission shape; remission contributes nothing observable beyond
selecting the batch subset. Future probes need not model remission as a
mechanism — only as a subset filter.

### E0h-D2 — dose-response is regime-dependent and threshold-like (R1/R2 FAIL)
Half-drain (0.5) is inert at L=15 (−0.0912 vs −0.0903) despite lifting commits
51→60 — a ~50% rate lift is *not sufficient*; the short-L response is
threshold-like and only the full batch moves it. At L=40 the half-drain is a
large win (+0.1241 vs +0.0205) — the best PHASE-rule arm measured at mid-L. At
L=150 both burst arms are toxic: BURST collapses melts 218→93 (churn dies when
committed sites rebatch), BURST_A 218→63 with young melts 196→27 — both land
near FIXED (+0.3215/+0.3254), i.e. at long L a permissive budget converts the
phase machine into the substrate floor. The TAGR-shaped regime fork (E0e-D2)
is therefore entirely a budget-shape fork.

### E0h-D3 — deep-window pacing evidence, with a caveat
At L=150, commits 282→157/127 while melts collapse harder — commit admission is
not the direct long-L bottleneck; the pacing value of 1/tick at large L runs
through sustaining the melt/recommit churn (melts fall BECAUSE young recommits
batch and then resist re-invalidation). Caveat: BURST_A(150) ≈ FIXED(150)
(+0.3254 vs +0.3215) while BURST_A reproduces TAGR exactly — so at L=150 the
committed TAGR arm was already substrate-floor-equivalent on gain; PHASE's
+0.4067 remains the best long-L result and no batch-shaped arm approaches it.

## 5. Verdict

E0h set out to lift short L by easing within-burst pacing. The preregistered
half-drain arm failed its target (R1) and its long-L safety check (R2), but the
pass delivers the programme's cleanest mechanistic result: **the TAGR arm is
batch admission in disguise** (E0h-D1), and **budget shape alone spans the
entire PHASE↔TAGR↔FIXED behavioral range** (E0h-D2). The committed arms remain
PHASE (long-L champion +0.4067) and — if short/mid L is ever the objective —
the budget-shaped equivalents already shipped (QUOTA at L=40, BURST/BURST_A
elsewhere), with no remission machinery required. Next probes should compose
budget shapes (e.g. burst-within-quota) rather than revisit routing.
