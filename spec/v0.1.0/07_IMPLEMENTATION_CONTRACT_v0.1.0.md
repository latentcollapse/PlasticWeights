# PlasticWeights.jl — Stage-0 Implementation Contract v0.1.0

This document translates the science spec into implementation boundaries.

---

## 1. Recommended Module Boundaries

```text
PlasticWeights
├── Core
│   ├── SiteState
│   ├── RegionState
│   ├── HotPool
│   └── Exposure
├── Constitutive
│   ├── Newtonian
│   └── BinghamInspired
├── DCP
│   ├── Snapshot
│   ├── Actions
│   └── FixedRuleController
├── Models
│   └── Stage0MLP
├── Tasks
│   └── SyntheticConflictFamily
├── Telemetry
│   ├── Events
│   ├── Metrics
│   └── TraceWriter
├── Controls
│   ├── C1_Adam
│   ├── C2_SGD
│   ├── C3_ShadowAdam
│   ├── C4_AdaptiveScalar
│   ├── C5_Newtonian
│   ├── C6_FixedSchedule
│   ├── C7_HistoryReset
│   └── C8_PerSiteThreshold
└── Tests
    ├── Sanity
    ├── Causal
    └── Invariants
```

Exact package naming may differ; boundaries must not.

---

## 2. Core Site Storage — Logical Contract

Logical fields:

```julia
q::Int8              # -1, 0, +1
allocated::Bool
superplastic::Bool
hot_handle::Int32
```

Prototype storage does not need final bit-packing.

Correctness before compression.

---

## 3. Hot Pool

Contract:

- one FP32 residual per superplastic site,
- handle 0 reserved as invalid sentinel,
- no consolidated/vacant site owns a hot slot,
- commit releases exactly once,
- melt allocates exactly once,
- deterministic free-list behavior in reference mode.

---

## 4. Region Map

- strict partition,
- deterministic site -> region lookup,
- fixed region size for a run,
- no overlap.

---

## 5. Exposure API

Conceptual contract:

```julia
exposure(site, ::ZCS) -> Int8
exposure(site, ::VPS) -> Int8
```

This is the only variant-specific forward semantic.

---

## 6. Constitutive API

Conceptual contract:

```julia
response(law, region_state, site_telemetry, g) -> Δδ
```

The constitutive function:

- cannot commit,
- cannot melt,
- cannot allocate,
- cannot release,
- cannot mutate exposure directly.

---

## 7. DCP API

Conceptual contract:

```julia
action = decide(dcp, snapshot)
```

The DCP sees only immutable declared snapshot fields.

Lifecycle application is separate:

```julia
apply_action!(substrate, action)
```

---

## 8. Reference Execution Mode

All causal/sanity tests use:

- CPU,
- single-threaded execution where required,
- deterministic iteration order,
- deterministic RNG,
- no unordered hash-map iteration in state transition paths.

S3b requires bitwise identity.

---

## 9. Tick Order

Normative:

1. snapshot exposure,
2. forward,
3. loss,
4. backward,
5. compute coefficient gradients,
6. update stress EMA,
7. compute constitutive response,
8. integrate residuals,
9. update residual-motion telemetry,
10. create immutable DCP snapshots,
11. emit DCP actions,
12. apply transitions atomically,
13. apply hardening,
14. allocate/release hot slots,
15. log telemetry,
16. next tick.

---

## 10. Hard Failure Gates

Abort a run if:

- site q leaves \{-1,0,+1\},
- superplastic site lacks valid hot handle,
- non-superplastic site owns hot handle,
- region partition invalid,
- budget exceeded,
- DCP snapshot contains undeclared mutable reference,
- exposure changes mid-tick,
- S2 seed learnability fails,
- deterministic reference invariants fail.

---

## 11. Build Order

Recommended implementation sequence:

1. core site/region state,
2. hot pool,
3. exposure policies,
4. quantizer,
5. deterministic Stage-0 MLP,
6. Newtonian shadow dynamics,
7. S0/S1/S1b,
8. Bingham-inspired law,
9. DCP,
10. lifecycle transitions,
11. S2/S3/S3b,
12. telemetry,
13. controls C3/C7/C8,
14. task family,
15. long-run experiment harness,
16. remaining controls,
17. branch-at-remelt,
18. full Stage-0 sweep.

Do not optimize kernels before the reference path passes all causal tests.

