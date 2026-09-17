"""
PlasticWeights.jl — Stage-0 Implementation

A reference implementation of the PlasticWeights substrate with:
- Hot/cold site storage
- Exposure policies (ZCS/VPS)
- Constitutive laws (Newtonian, Bingham-inspired)
- Decision-making Control Processes (DCP)
- Deterministic reference execution mode
"""
module PlasticWeights

# Core module exports
export SiteState, RegionState, HotPool, ExposurePolicy, ZCS, VPS

# Constitutive exports
export ConstitutiveLaw, Newtonian, BinghamInspired, response

# DCP exports
export DCP, Snapshot, Action, decide, apply_action!

# Models exports
export Stage0MLP

# Tasks exports
export SyntheticConflictFamily

# Telemetry exports
export Event, Metric, TraceWriter

# Controls exports
export Control, C1_Adam, C2_SGD, C3_ShadowAdam, C4_AdaptiveScalar,
       C5_Newtonian, C6_FixedSchedule, C7_HistoryReset, C8_PerSiteThreshold

# Test utilities
export run_sanity_tests, run_causal_tests, run_invariant_tests

# Submodules
include("Core/SiteState.jl")
include("Core/RegionState.jl")
include("Core/HotPool.jl")
include("Core/Exposure.jl")

include("Constitutive/Law.jl")

include("DCP/DCP.jl")

include("Models/Stage0MLP.jl")

include("Tasks/SyntheticConflictFamily.jl")

include("Telemetry/Telemetry.jl")

include("Controls/Control.jl")

include("Tests/Sanity/runtests.jl")
include("Tests/Causal/runtests.jl")
include("Tests/Invariants/runtests.jl")

end # module PlasticWeights
