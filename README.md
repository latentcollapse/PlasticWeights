# PlasticWeights.jl — Stage-0 reference kernel

This is an experimental repo. Just a wacky idea that I had I wanted to test out

This repository is implementing the **frozen PlasticWeights v0.1.0 Stage-0 specification**. The current milestone is deliberately narrow: a deterministic CPU reference kernel and the causal sanity suite through S3b.

## Implemented in this pass

- Parameter-site state: ternary `q`, allocation, superplastic flag, hot handle.
- Deterministic FP32 hot pool with one residual per superplastic site.
- Fixed contiguous Stage-0 regions (64–256 sites) with persistent yield/settle/viscosity/hardening state.
- ZCS and VPS exposure semantics.
- Exact ternary reconsolidation quantizer (`±0.5 -> 0`).
- Newtonian calibration law and Bingham-inspired constitutive law.
- Immutable typed DCP snapshots and stateless fixed-rule controller.
- Atomic MELT/COMMIT transitions with mandatory work-hardening.
- Normative all-superplastic Stage-0 seed initializer.
- Stage-0 network:

  `x -> E_fixed -> W_material -> tanh -> H_FP32 -> y`

  `W_material` is built only from material-site exposures; the reference backward pass is explicit Julia code with no AD framework.
- Injected-gradient deterministic material tick used for causal mechanism tests.
- Developmental event telemetry: `DevelopmentalRecorder`, `DevelopmentalEvent` hierarchy
  (`MilestoneEvent`, `MeltEvent`, `CommitEvent`), O(1) cached milestone queries on the
  live recorder, O(N) single-pass `summarize_events` for arbitrary persisted traces.
- Tests S0, S1, S1b, S2, S3, S3b, and six telemetry test suites (2 629 assertions total).

## Not implemented yet

The following exist only as future/deferred source scaffolding where present and are **not loaded by `PlasticWeights`**:

- C1–C8 control arms,
- synthetic conflict task family and long-run A/B harness,
- S3c and S4–S10,
- branch-at-remelt experiment,
- Pareto/frontier analysis,
- optimized kernels/GPU execution.

No claim is made that those components work yet.

## Scientific boundaries

The implementation keeps these boundaries explicit:

```text
exposure snapshot
    -> network forward/backward
    -> coefficient gradients
    -> stress telemetry
    -> constitutive response
    -> hot residual integration
    -> residual-motion telemetry
    -> immutable DCP snapshot
    -> DCP action
    -> atomic lifecycle transition
    -> next-tick exposure
```

The constitutive law cannot melt, commit, allocate, release, or mutate exposure. The DCP cannot read undeclared mutable globals or raw latent residuals. `HotPool` is the only source of truth for `delta`.

## Running the reference suite

```bash
./scripts/test_reference.sh
```

Equivalent explicit command:

```bash
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

This package has been execution-verified: `Pkg.test()` passes all 2 629 assertions with zero failures or errors.

## Frozen specification

The normative research specification is vendored unchanged under `spec/v0.1.0/`. Changes to the scientific semantics should follow the freeze rule rather than being silently introduced as implementation conveniences.
