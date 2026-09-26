# PlasticWeights.jl — Causal & Sanity Tests v0.1.0

---

## S0 — Quantizer

Verify exact ternary boundaries.

---

## S1 — Newtonian Equivalence

Newtonian material shadow dynamics must match SGD-shadow under:

\[
lr=1/\eta
\]

Failure is an implementation bug.

---

## S1b — Loss-Scale Covariance

Construct two otherwise identical reference runs:

\[
L
\]

and:

\[
L'=kL
\]

with transformed constitutive parameters:

\[
\tau'=k\tau,\quad
\epsilon'=k\epsilon,\quad
\eta'=k\eta
\]

Require identical lifecycle and residual trajectories on the deterministic CPU reference path.

This test validates unit consistency.

---

## S2 — Seed Local-Learning Island

At all-superplastic ZCS seed:

- material coefficient gradients nonzero on a nondegenerate batch,
- `tanh'(0)` path live,
- upstream fixed-feature gradient zero,
- head-weight gradient initially zero at zero hidden activation,
- head-bias gradient nonzero.

---

## S3 — Twin-History Mechanism Isolation

### Purpose

\[
X_{op}^{A}=X_{op}^{B},\qquad
M_{hist}^{A}\neq M_{hist}^{B}
\]

under identical subsequent load.

### Procedure

1. generate distinct histories,
2. explicitly enumerate \(X_{op}\) and \(M_{hist}\),
3. canonicalize every \(X_{op}\) field,
4. preserve only \(M_{hist}\),
5. feed identical predetermined signed-gradient sequence \(g(t)\),
6. record lifecycle/deformation trajectories.

### Success condition

History-divergent systems differ in the direction predicted by \(M_{hist}\).

---

## S3b — Equal-History Negative Control

Set:

\[
X_{op}^{A}=X_{op}^{B}
\]

and:

\[
M_{hist}^{A}=M_{hist}^{B}
\]

Run on the deterministic single-threaded CPU reference path with fixed iteration order.

**Requirement: bitwise trajectory identity.**

Any divergence is an implementation/conformance failure.

GPU or parallel variants may later use explicit tolerances, but they are not the Stage-0 causal reference.

---

## S3c — In-Network Twin-History

Repeat Twin-History after canonicalization, but use actual identical input batches and network forward/backward instead of injected gradients.

Purpose:

- S3 establishes mechanism-level history sensitivity,
- S3c tests whether the effect survives in the learning loop.

S3c is supportive/ecological validation, not a replacement for S3.

---

## S4 — ZCS/VPS Identity Before Informative Remelt

Paired arms must remain identical until first prior-\(\pm1\) remelt.

Earlier divergence is a bug.

---

## S5a — Local Surrogate Consistency

Use a minimal graph with a linear downstream path.

For a selected site:

1. compute STE direction,
2. evaluate forced \(-1,0,+1\),
3. compare direction/ranking.

This is a controlled local test.

---

## S5b — Global Discrete-Intervention Utility

In the real Stage-0 network:

1. checkpoint state,
2. force \(-1,0,+1\) alternatives,
3. evaluate full-network loss,
4. compare STE preference to globally beneficial intervention.

Report:

- directional agreement,
- discrete intervention regret,
- performance relative to a sign-shuffled/random-choice baseline.

No arbitrary 50/60/70% quality bands are used.

### Practical failure condition

The STE is considered practically unacceptable for Stage 0 if it is not reliably better than the preregistered random/sign-shuffled baseline on informative sites, or if its discrete intervention regret is consistently harmful at a magnitude exceeding the SESOI for this diagnostic.

---

## S6 — DCP Conformance

### S6a Replay
Same declared snapshot -> exact same action.

### S6b No Hidden State
Fresh DCP reconstructed from declared state replays same action sequence.

### S6c HOLD Swap
Continuous substrate equations remain executable with DCP replaced by HOLD.

### S6d Boundary Properties
Synthetic threshold-adjacent snapshots produce documented actions.

---

## S7 — Branch-at-Remelt

From identical pre-remelt state:

- measure exposure-only next-forward difference before updates,
- then measure short-horizon total effects,
- optionally run frozen-network exposure-only diagnostic.

---

## S8 — History Reset

If C7 matches full material history on lifecycle and frontier metrics within the practical-effect criterion, persistent material history is not supported as load-bearing.

---

## S9 — Region Sharing

Compare full region-shared material state against C8 per-site persistent threshold/hardening.

If C8 reproduces the full material frontier and lifecycle signatures with equal/lower complexity, region-level material state is weakened.

Further C9/C10 decomposition is deferred until S9 shows an effect worth decomposing.

---

## S10 — C6 Event-Matching Audit

Before primary evaluation, verify that the frozen exogenous schedule targets pilot-estimated lifecycle rates.

During primary analysis report:

- total melts,
- total commits,
- per-region event counts where applicable,
- deviation from planned rate.

Interpret C6 cautiously if event counts differ materially.

