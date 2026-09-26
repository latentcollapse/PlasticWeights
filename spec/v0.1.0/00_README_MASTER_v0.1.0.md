# PlasticWeights.jl — Stage-0 Science & Implementation Specification v0.1.0

**Status:** FROZEN FOR PROTOTYPE IMPLEMENTATION  
**Version:** 0.1.0  
**Scope:** Stage-0 causal prototype  
**Primary variants:** Zero-Centered Superplasticity (ZCS), Value-Preserving Superplasticity (VPS)

---

## 1. Freeze Rule

This document set is the implementation baseline.

After v0.1.0, the Stage-0 scientific spec changes only for:

1. an implementation defect that makes a stated invariant impossible or incorrect,
2. an empirical result demonstrating that a required test/control is malformed,
3. a newly discovered causal confound that would make a primary result uninterpretable.

New features, richer laws, deeper models, learned controllers, additional controls, or deployment-oriented mechanisms do **not** modify Stage 0 unless one of the three conditions above is met.

Everything else goes to the post-freeze issue ledger.

---

## 2. Central Thesis

PlasticWeights separates a site's **committed arithmetic value** from its **developmental state**.

Arithmetic remains balanced ternary:

\[
q\in\{-1,0,+1\}
\]

The human-facing false-pentanary phenotype is:

\[
\{\bot,\star,-,0,+\}
\]

> **Five observable developmental states, three arithmetic states.**

The phenotype is derived from:

- ternary arithmetic value,
- allocation state,
- superplasticity state.

It is never stored as a five-valued arithmetic quantity.

---

## 3. Superplasticity

**Superplasticity** is the developmental regime in which a site's committed ternary value is temporarily decoupled from its latent continuous state.

During superplasticity:

- the site owns an FP32 shadow residual \(\delta\),
- \(\delta\) accumulates evidence for a future ternary commitment,
- the forward-visible contribution is determined by the exposure policy,
- reconsolidation commits a ternary value only when the settling conditions are satisfied.

The term intentionally combines computational plasticity with an unresolved / superposition-inspired developmental metaphor.

It is not quantum superposition and is not a literal physical superplasticity model.

---

## 4. Stage-0 Scientific Claim

The narrow causal claim is:

> **If all presently operative neural/developmental state is held fixed, changing only persistent material history can change future lifecycle or deformation behavior under the same subsequent load.**

The broader Stage-0 question is whether that history-bearing material structure produces a useful stability–plasticity tradeoff that cannot be behaviorally reduced to simpler matched stateful-learning mechanisms.

---

## 5. Material Framing

“Material” is an operational abstraction for a system with:

- persistent regional state,
- yield thresholds,
- hysteresis,
- stress-conditioned mobility,
- work-hardening,
- discrete lifecycle transitions.

Any such system can ultimately be expressed algorithmically.

> **Algorithmic representability as an optimizer is not falsification. Behavioral reducibility to a simpler matched optimizer/control is.**

If simpler matched controls reproduce the same causal behavior and stability–plasticity frontier, the material abstraction loses scientific value.

---

## 6. ZCS / VPS A/B

The two variants differ in exactly one forward semantic while a site is superplastic:

\[
\text{ZCS}: q^{vis}=0
\]

\[
\text{VPS}: q^{vis}=q_{prior}
\]

All other machinery is shared.

The full paired run estimates the **total policy effect** of choosing one exposure policy.

The branch-at-remelt test estimates the **immediate / short-horizon mechanistic effect** from an identical checkpoint.

---

## 7. Stage-0 Neurosymbolic Position

Stage 0 does **not** claim a full neurosymbolic cognitive architecture.

It contains:

- a neural/material data plane,
- a deterministic rule-based Developmental Control Plane (DCP),
- discrete readable lifecycle states and actions.

Stronger symbolic properties — compositional symbolic operations, semantic binding, explicit reasoning over region identities — are deferred.

---

## 8. Document Set

1. `01_SHARED_SUBSTRATE_v0.1.0.md`
2. `02_DCP_v0.1.0.md`
3. `03_SPEC_A_ZCS_v0.1.0.md`
4. `04_SPEC_B_VPS_v0.1.0.md`
5. `05_EXPERIMENT_PROTOCOL_v0.1.0.md`
6. `06_CAUSAL_TESTS_v0.1.0.md`
7. `07_IMPLEMENTATION_CONTRACT_v0.1.0.md`
8. `08_FREEZE_CHANGELOG_v0.1.0.md`
9. `09_POST_FREEZE_ISSUE_LEDGER.md`

