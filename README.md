# PlasticWeights.jl — Stage-0 Implementation

A reference implementation of the PlasticWeights substrate following the Stage-0 Implementation Contract v0.1.0.

## Overview

PlasticWeights is a substrate for studying history-dependent credit assignment through material dynamics. This Stage-0 implementation provides:

- **Hot/cold site storage** with deterministic allocation
- **Exposure policies** (ZCS/VPS) for variant-specific forward semantics
- **Constitutive laws** (Newtonian, Bingham-inspired) for material response
- **Decision-making Control Processes (DCP)** for lifecycle transitions
- **Deterministic reference execution mode** for causal testing

## Module Structure

```
PlasticWeights
├── Core
│   ├── SiteState        # Ternary site storage (-1, 0, +1)
│   ├── RegionState      # Strict region partitioning
│   ├── HotPool          # FP32 residual management
│   └── Exposure         # ZCS/VPS exposure policies
├── Constitutive
│   ├── Newtonian        # Linear viscous response
│   └── BinghamInspired  # Yield-threshold plastic flow
├── DCP
│   ├── Snapshot         # Immutable state snapshots
│   ├── Actions          # Lifecycle transition actions
│   └── FixedRuleController  # Rule-based decisions
├── Models
│   └── Stage0MLP        # Deterministic MLP
├── Tasks
│   └── SyntheticConflictFamily  # Test task family
├── Telemetry
│   ├── Events           # Substrate events
│   ├── Metrics          # Performance metrics
│   └── TraceWriter      # Trace logging
├── Controls
│   ├── C1_Adam          # Adam optimizer
│   ├── C2_SGD           # SGD optimizer
│   ├── C3_ShadowAdam    # Shadow dynamics
│   ├── C4_AdaptiveScalar # Adaptive hyperparameters
│   ├── C5_Newtonian     # Newtonian control
│   ├── C6_FixedSchedule # Fixed schedules
│   ├── C7_HistoryReset  # History resets
│   └── C8_PerSiteThreshold # Per-site thresholds
└── Tests
    ├── Sanity           # Basic correctness tests
    ├── Causal           # Determinism tests
    └── Invariants       # Hard failure gate tests
```

## Key Contracts

### Site State
- `q::Int8` - ternary state in {-1, 0, +1}
- `allocated::Bool` - allocation status
- `superplastic::Bool` - plasticity state
- `hot_handle::Int32` - hot pool handle (0 = invalid)

### Hot Pool
- One FP32 residual per superplastic site
- Handle 0 reserved as invalid sentinel
- Deterministic free-list behavior
- Commit releases exactly once, melt allocates exactly once

### Tick Order (Normative)
1. Snapshot exposure
2. Forward pass
3. Loss computation
4. Backward pass
5. Compute coefficient gradients
6. Update stress EMA
7. Compute constitutive response
8. Integrate residuals
9. Update residual-motion telemetry
10. Create immutable DCP snapshots
11. Emit DCP actions
12. Apply transitions atomically
13. Apply hardening
14. Allocate/release hot slots
15. Log telemetry
16. Next tick

## Usage

```julia
using PlasticWeights

# Create sites and hot pool
sites = [SiteState(0) for _ in 1:64]
pool = HotPool(32)
region_map = RegionMap(64, 8)

# Run sanity tests
run_sanity_tests()

# Run causal tests  
run_causal_tests()

# Run invariant tests
run_invariant_tests()
```

## Reference Mode

All causal/sanity tests use:
- CPU execution
- Single-threaded where required
- Deterministic iteration order
- Deterministic RNG (Xoshiro)
- No unordered hash-map iteration in state transition paths

S3b requires bitwise identity across runs.

## Hard Failure Gates

The implementation aborts if:
- Site q leaves {-1, 0, +1}
- Superplastic site lacks valid hot handle
- Non-superplastic site owns hot handle
- Region partition invalid
- Budget exceeded
- DCP snapshot contains undeclared mutable reference
- Exposure changes mid-tick
- S2 seed learnability fails
- Deterministic reference invariants fail

## Build Order

Implementation follows the recommended sequence:
1. Core site/region state ✓
2. Hot pool ✓
3. Exposure policies ✓
4. Constitutive laws ✓
5. Stage-0 MLP ✓
6. DCP ✓
7. Controls ✓
8. Telemetry ✓
9. Tests ✓

## License

Stage-0 Implementation Contract v0.1.0
