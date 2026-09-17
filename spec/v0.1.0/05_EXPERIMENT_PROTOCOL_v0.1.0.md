# PlasticWeights.jl — Stage-0 Experiment Protocol v0.1.0

---

## 1. Primary Arms

- Material ZCS
- Material VPS

Paired primary runs share:

- architecture,
- seed,
- data order,
- region map,
- law parameters,
- DCP,
- budget,
- canonical loss convention.

After first policy intervention, trajectory divergence is expected and is part of the total policy effect.

---

## 2. Controls

### C1 — FP32 + Adam
Conventional adaptive baseline.

### C2 — FP32 + SGD
Conventional non-adaptive baseline.

### C3 — Shadow-Latent + STE + Adam, no constitutive law
Tests whether rheology adds beyond shadow-latent learning.

### C4 — AdaptiveScalarBaseline
Tests whether behavior reduces to simpler adaptive scalar scheduling.

### C5 — Newtonian material calibration
Must reproduce SGD-shadow under \(lr=1/\eta\).

### C6 — Fixed-Schedule DCP
Tests state-dependent lifecycle timing vs exogenous matched timing.

### C7 — History-Reset Ablation
After commit, persistent material-history variables reset to seed values while current neural/developmental state remains intact.

### C8 — Per-Site Persistent Threshold Control
Same:
- shadow residual,
- stress definition,
- threshold functional form,
- exposure policy,
- hysteresis,
- hardening semantics,
- DCP logic,

but each site owns its own persistent threshold \(\tau_i\).

On commit:

\[
\tau_i\leftarrow\tau_i+\kappa_H
\]

Purpose: test the whole region-shared material-state package against per-site persistent thresholding.

Further decomposition of shared threshold vs hardening spillover is deferred unless C8 produces an informative difference.

---

## 3. Primary Positive Prediction

The primary material-vs-C3 prediction is:

> **Across a preregistered adaptation-pressure sweep, the material arm shifts the empirical stability–plasticity Pareto frontier outward rather than merely selecting a different point on the same frontier.**

For each configuration plot:

\[
(\text{Task-B acquisition},\text{Task-A retention})
\]

Primary scalar summary:

### Retention at Matched Acquisition — \(R@B^*\)

1. choose a feasible acquisition target \(B^*\) during pilot task design,
2. freeze \(B^*\) before primary seeds,
3. compare Task-A retention among settings reaching \(B^*\).

If material dynamics only move along the same frontier, the positive prediction fails.

---

## 4. Exploratory Decision Framework

Five paired seeds are prototype/effect-discovery only.

Before primary seeds:

- task family frozen,
- \(B^*\) frozen,
- comparison direction frozen,
- SESOI frozen from **external/practical reasoning**, not observed pilot treatment effect.

### Prototype-positive

A prespecified effect:

- has predicted direction in at least 4/5 paired primary seeds, and
- paired median effect meets/exceeds the SESOI.

This triggers a powered confirmatory study.

### Prototype-negative

The estimated effect is below the SESOI, direction is inconsistent, and corresponding mechanistic/ablation evidence also fails.

This argues against further investment in that mechanism but is not proof of exact equivalence.

### Inconclusive

Everything else.

No alpha-level confirmatory claim is made from five seeds.

---

## 5. Structural Task Conflict

Conflict is defined structurally before treatment comparison.

Let:

\[
c=
\frac{\#\{\text{shared inputs requiring incompatible outputs under A and B}\}}
{\#\{\text{shared inputs}\}}
\]

or an equivalent preregistered structural construction.

The exact task generator definition of \(c\) MUST be frozen before treatment pilots.

Pilot runs may verify:

- learnability,
- no bias-only shortcut,
- sufficient consolidation,
- sufficient nonzero-remelt fuel.

Pilot runs may **not** select \(c\) based on observed material-vs-control performance gaps.

---

## 6. Divergence Fuel

Report remelts from prior:

- \(-1\),
- \(0\),
- \(+1\).

A ZCS/VPS comparison without the preregistered minimum prior-\(\pm1\) remelt count is non-informative.

---

## 7. Long-Run Exposure-Policy Estimand

The paired ZCS/VPS run estimates the **total policy effect**.

Post-intervention gradient/state divergence is part of that effect.

---

## 8. Branch-at-Remelt Mechanistic Estimand

At the first informative remelt:

1. checkpoint complete state immediately before branch-specific exposure,
2. clone into ZCS and VPS,
3. preserve identical future data/RNG.

### Clean mechanism measurement

The first post-branch forward pass **before any parameter update** is the cleanest exposure-only mechanistic measurement.

### Short-horizon total effects

Measurements after 1 training update and at longer horizons (e.g. 5/20 ticks) are explicitly labeled **short-horizon total effects from a common checkpoint**, not pure exposure-only effects.

### Frozen-network diagnostic

Optionally hold all trainable state fixed for several forwards while changing only exposure policy. This isolates repeated forward-only consequences of exposure.

---

## 9. Stability–Plasticity Surface

Characterize:

\[
f(T_{switch},c)
\]

where:

- \(T_{switch}\): task-switch interval,
- \(c\): structural conflict.

Expected qualitative regime:

- stable/compatible demands may benefit from hardening,
- conflict increases pressure to relearn,
- fast switching plus high conflict should expose hardening-induced adaptation inertia.

The goal is a regime map, not a single handpicked win point.

---

## 10. Metrics

Required:

- Task-A acquisition,
- Task-B acquisition,
- Task-A retention,
- Task-A' reacquisition,
- \(R@B^*\),
- empirical Pareto frontier,
- melt/yield counts,
- remelts by prior q,
- superplastic fraction,
- superplastic duration,
- reconsolidation count,
- commit flip-flop count,
- ZCS lesion size,
- performance during melting,
- active FP32 hot storage,
- total state memory,
- update sparsity,
- `first_delta_tick`,
- `wake_tick`,
- `credit_unlock_tick`,
- stress/yield trajectories,
- region responsiveness ratio,
- DCP action counts,
- conformance failures,
- S5a/S5b surrogate metrics.

---

## 11. Parameter Sensitivity

Inspect local sensitivity to:

- \(\eta\),
- initial yield,
- \(\kappa_H\),
- \(\beta\),
- \(\epsilon\).

Primary conclusions must not rely on one knife-edge configuration.

---

## 12. Cost Accounting

Report memory by:

- cold ternary state,
- site flags/handles,
- hot pool,
- stress telemetry,
- region/per-site persistent state,
- optimizer/control state.

Report approximate additional per-tick operations.

No energy-efficiency claim is permitted from Stage-0 software timing.

---

## 13. Reproducibility

Record:

- Julia version,
- manifest,
- git commit,
- CPU/GPU,
- RNG algorithm,
- seeds,
- deterministic flags,
- task generator revision,
- all hyperparameters,
- region size,
- DCP config,
- constitutive config,
- pilot vs primary seed split.

