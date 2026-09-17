# PlasticWeights.jl — Developmental Control Plane v0.1.0

---

## 1. Definition

The DCP is a fixed, hand-specified rule module that:

1. receives one immutable typed snapshot,
2. emits discrete lifecycle actions,
3. performs no neural forward/backward computation,
4. does not directly update \(\delta\),
5. cannot access undeclared substrate globals.

The DCP and constitutive law are modular but dynamically coupled through declared state.

---

## 2. Declared Inputs

A DCP snapshot may include only declared fields such as:

- allocation flag,
- superplastic flag,
- committed q,
- site stress EMA,
- residual-motion EMA,
- eligibility counters,
- region yield/settle state,
- hardening state,
- hot-pool availability,
- global superplastic budget.

No semantic task label is available.

---

## 3. Actions

Stage 0:

- `HOLD`
- `MELT(site)`
- `COMMIT(site, q_new)`
- `ALLOCATE_HOT(site)`
- `RELEASE_HOT(site)`

Deferred:

- `VACATE`
- `FISSION`
- `FUSE`
- routing actions.

---

## 4. Melt

A consolidated site becomes eligible when:

\[
\sigma_i>\text{yield\_up}_R
\]

for \(K_{yield}\) consecutive ticks and budget allows.

Atomic melt:

1. allocate hot slot,
2. \(\delta_i\leftarrow0\),
3. set `p=1`,
4. preserve prior q,
5. log prior q,
6. branch-specific exposure begins next tick.

---

## 5. Commit

Eligible when:

\[
\sigma_i<\text{settle\_down}_R
\]

and:

\[
EMA(|\Delta\delta_i|)<\epsilon_\delta
\]

for \(K_{settle}\) consecutive ticks.

Atomic commit:

1. compute \(s=b+\delta\),
2. quantize to \(q'\),
3. write q,
4. set `p=0`,
5. release hot slot,
6. reset declared lifecycle counters,
7. apply work-hardening,
8. expose new q next tick.

---

## 6. Work-Hardening

Every successful commit applies:

\[
\text{yield\_up}_R
\leftarrow
\text{yield\_up}_R+\kappa_H
\]

---

## 7. Module Boundaries

### Constitutive law

Produces continuous:

\[
\Delta\delta
\]

### DCP

Produces discrete lifecycle action.

### Exposure policy

Determines visible value while superplastic.

These modules are distinct in code and specification.

---

## 8. DCP Conformance

### DCP-C1 — Replay

Same typed snapshot -> exact same action.

### DCP-C2 — No hidden state

A fresh DCP instance reconstructed from declared state must replay the same action sequence for the same snapshot sequence.

### DCP-C3 — HOLD swap

Replacing the DCP with `HOLD` must not change the equations or executability of forward/backward and continuous constitutive update code.

### DCP-C4 — Threshold boundary properties

Synthetic snapshots immediately below/above melt/settle thresholds must produce documented actions.

These are software/architecture invariants, not evidence that the DCP is useful.

---

## 9. Fixed-Schedule Control Contract (C6)

C6 tests:

\[
\text{state-dependent lifecycle timing}
\quad\text{vs}\quad
\text{exogenous lifecycle timing}
\]

Pilot-only runs estimate lifecycle event-rate targets.

Before primary seeds:

- the fixed schedule is frozen,
- the expected total melt/commit counts are frozen,
- the hot-state budget is identical,
- no primary treatment outcomes are used to construct the schedule.

During analysis report actual event-count deviation between C6 and the matched material arm.

C6 does not test uniqueness of the chosen DCP rule.

