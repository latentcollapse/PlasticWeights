# PlasticWeights.jl — v0.1.0 Freeze Changelog

v0.1.0 promotes the v0.0.3 candidate to an implementation-frozen Stage-0 protocol.

## Final blocker patches

### 1. Loss-scale covariance

The constitutive law now has explicit computational unit semantics.

Under:

\[
L' = kL
\]

transform:

\[
(\tau,\epsilon,\eta)
\rightarrow
(k\tau,k\epsilon,k\eta)
\]

A new S1b requires trajectory invariance under this transformation.

This avoids introducing an additional RMS normalizer into Stage 0.

### 2. S3b determinism

The causal negative control runs on a deterministic single-threaded CPU reference path and requires **bitwise trajectory identity** after operative state and material history are equalized.

No floating-point tolerance is needed for the reference causal test.

## Additional accepted clarifications

- Added S3c in-network Twin-History as ecological validation.
- Branch-at-remelt now distinguishes exposure-only forward effect from later short-horizon total effects.
- SESOI must come from external/practical reasoning, not pilot treatment effect.
- Task conflict is structurally defined before treatment comparison.
- C6 uses pilot-frozen lifecycle-rate matching and reports actual event-count deviation.
- Region “freezing” replaced by a global-stress-relative responsiveness ratio.
- S5b uses random/sign-shuffled comparison and discrete intervention regret instead of arbitrary agreement bands.

## Intentionally deferred despite reviewer suggestions

- C9/C10 decomposition of region sharing vs hardening spillover.
- hardening decay / softening,
- deeper material stacks,
- learned DCP,
- alternative constitutive law families,
- inference-time learning,
- dynamic region topology,
- hardware-specific optimization.

These enter the issue ledger unless data creates a direct need.

## Freeze declaration

**STAGE-0 SPEC FROZEN AT v0.1.0**

Changes after this point require:
- implementation defect,
- empirical malformed-test evidence,
- or newly discovered causal confound.

