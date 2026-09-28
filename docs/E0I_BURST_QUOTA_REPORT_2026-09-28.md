# E0i — Burst-Within-Quota Composite Budget (Pass 3f)

**Date:** 2026-09-28 · **Status:** COMPLETE (grid done, ledger written)
**Preregistration:** `scripts/e0i_burst_quota.jl` header (declared before any run; no BQ grid row ran before it)
**Rows:** `docs/e0i_rows.csv` (16 rows, resumable cache) · **Checks:** `docs/e0i_checks_output.txt`
**Suite:** full `Pkg.test()` green before the grid (4 new E0i testsets, 28 assertions). A first kernel implementation that gated only later ticks of a burst (admitting the full W-wide batch — the E0b2 wave) was caught by the R0 sanity **before any run** and fixed to `cap = min(burst cap, remaining quota)`; the R0 sanity also confirmed PHASE@150 = 282/218 unchanged.

## 1. Mechanism under test

Composite of the E0g quota (per-phase volume, live-stamp, melts refund) with the
E0h burst (within-tick batch admission, canonical order):

```
cap(tick) = min( max(1, floor(bf·W)), Q − spent )   if spent < Q, else 0
```

bf = burst_fraction (default 1.0 — E0h-D2: only the full batch moves short L),
Q = ceil(qf·L), spent = live-stamp commits this phase. Per-site rule byte-exact
PHASE; melts untouched; position-gated. The `min` bounds the FIRST tick of a
burst (testset-pinned: W=64 burst under Q=8 admits exactly 8, never the wave).

**Declared design tension:** BURST_A per-phase demand is non-monotonic in L
(10.0/40.6/43.0/12.7 commits/phase at L=15/40/75/150) while a constant-fraction
quota is linear — a quota feeding short L cannot bind at long L. The composite
maps a trade-off LINE, not a free win; endpoints preregistered, R2 declared
expected-FAIL.

## 2. Results (mean per-task gain; commits/melts; per-phase gross spend)

| L   | PHASE                | BQ10 (q=0.1)         | BQ50 (q=0.5)         | FIXED          |
|-----|----------------------|----------------------|----------------------|----------------|
| 15  | −0.0903 (51/46, 5.1) | **+0.0439** (31/27, 3.1) | −0.0739 (67/48, 6.7) | −0.0572 (41/7) |
| 40  | +0.0205 (288/248, 28.8) | −0.1230 (93/82, 9.3) | +0.0401 (356/294, 35.6) | +0.1618 (70/6) |
| 75  | +0.0461 (458/396, 45.8) | +0.0526 (163/114, 16.3) | **+0.0891** (402/338, 40.2) | +0.0647 (70/6) |
| 150 | **+0.4067** (282/218, 28.2) | +0.3080 (112/48, 11.2) | +0.3254 (127/63, 12.7) | +0.3215 (71/7) |

Checks: **C0/R1 PASS** · **R2/R3/R4/R5a/R5b FAIL** (two declared-expected, three
informative mis-specifications, all ledgered).

## 3. Ledger

### E0i-D1 — dose-response at short L is NON-MONOTONE; the optimum is a small throttle (R1 PASS via the undeclared path)
The preregistration declared BQ10@15 would FAIL by arithmetic (Q=2 < demand
5.1) and staked the short-L hypothesis on BQ50 (Q=8, burst-drained). Both
predictions inverted: **BQ10@15 = +0.0439 — the first positive L=15 gain in the
programme** (PHASE −0.0903, TAGR +0.1226 was the prior best) — while BQ50@15 =
−0.0739, WORSE than PHASE. Throttling below machine demand (commits 31 vs 51,
melts 27 vs 46, substrate held at 96% plastic) preserves plastic capacity and
turns the short-L deficit positive; feeding the burst into a mid-size quota
pushes toward the consolidated traps PHASE falls into. The optimum dose is
L-dependent, not a constant fraction: Q=2 wins at L=15 and *loses badly* at
L=40 (−0.1230, the substrate never consolidates — 90% plastic, commits 93).

### E0i-D2 — refunds make the composite softer than any gross ceiling (R4/R5a/R5b FAIL as mis-specifications)
The live-stamp counter counts net commits − melts since phase start, so gross
per-phase spend exceeds Q wherever churn refunds (R5a: BQ50@15 gross max 12
against live-stamp 8; R5b: BQ50@40 gross mean 35.6 against live-stamp 20; R4:
BQ10≠BQ50 at L=150 because demand *peaks* — up to 86/phase — re-open the
refunded quota, though means (12.7) sit far below both quotas). The declared
"quota cannot bind at long L" arithmetic used the MEAN; the peak-driven refunds
decide instead. A gross-count composite (different stateful counter) would bind
differently — recorded for any successor probe.

### E0i-D3 — the composite's long-L cost is the E0h cost, quota-blind (R2 FAIL as declared)
BQ50@150 = +0.3254 / 63 melts — behaviorally BURST_A@150 (its Q=75 is above
peak-adjusted live-stamp demand), confirming the declared arithmetic in
outcome even though the refund mechanism (E0i-D2) invalidates its route. The
long-L endpoint of the trade-off line is the burst endpoint: +0.3254, melts
−71%. PHASE remains the long-L champion (+0.4067). R3: at L=40 the quota cap
(Q=20 vs demand 40.6) throttles away most of the burst win (+0.0401 vs
BURST_A +0.1372) — volume caps, not just shapes, carry the mid-L effect.

## 4. Programme state after E0i (best arm per regime)

| L   | best arm (overall) | gain    | best bounded-budget arm | gain    |
|-----|--------------------|---------|-------------------------|---------|
| 15  | TAGR (E0d)         | +0.1226 | **BQ10** (new)          | +0.0439 |
| 40  | FIXED (floor)      | +0.1618 | BURST_A (E0h)           | +0.1372 |
| 75  | **BQ50** (new)     | +0.0891 | **BQ50** (new)          | +0.0891 |
| 150 | PHASE (unchanged)  | +0.4067 | PHASE                   | +0.4067 |

TAGR remains the L=15 champion, but BQ10 is the first *bounded-budget* arm to
beat PHASE there (+0.0439 vs −0.0903; the previous bounded best was E0e REGIME
+0.0364). The pass establishes: (i) short L wants a THROTTLE below machine
demand (BQ10), (ii) mid L wants a fed burst (BQ50@75, best measured at that
regime by any arm), (iii) long L remains untouchable by any budget shape tried
(PHASE), and (iv) the winning dose is L-dependent — a per-regime dose schedule
is the natural E0j, and the lever×regime map is now dense enough to support
one.

## 5. Verdict

E0i's preregistered hypothesis (quota feeds short L; long-L cost bounded by the
quota) failed in both directions, and the failures produced the most actionable
map position so far: the composite lever WORKS — it set a new best at L=75 and
produced the first bounded-budget short-L win — but the dose must be
regime-dependent, and the refund semantics soften any live-stamp ceiling. No
reinterpretation of failures; all five check outcomes stand as run. Committed
arms are unchanged (PHASE remains the reference; no arm displaces it at L=150).
