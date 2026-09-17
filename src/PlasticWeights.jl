"""
    PlasticWeights

Stage-0 Implementation of the PlasticWeights substrate.

A reference implementation following the Stage-0 Implementation Contract v0.1.0:
- Hot/cold site storage with deterministic allocation
- Exposure policies (ZCS/VPS) for variant-specific forward semantics
- Constitutive laws (Newtonian, Bingham-inspired) for material response
- Decision-making Control Processes (DCP) for lifecycle transitions
- Deterministic reference execution mode for causal testing
"""
module PlasticWeights

# Standard library imports
using Random
using Statistics

# ============================================================================
# Core exports
# ============================================================================
export SiteState, RegionState, RegionMap, HotPool
export ZCS, VPS, exposure, get_exposure
export SiteTelemetry

# ============================================================================
# Constitutive exports
# ============================================================================
export ConstitutiveLaw, response
export Newtonian, NEWTONIAN
export BinghamInspired, BINGHAM_INSPIRED

# ============================================================================
# DCP exports
# ============================================================================
export DCP, Snapshot, Action
export decide, apply_action!
export FixedRuleController

# ============================================================================
# Model exports
# ============================================================================
export Stage0MLP

# ============================================================================
# Telemetry exports
# ============================================================================
export Event, Metric, TraceWriter
export TickEvent, MeltEvent, CommitEvent, HardeningEvent, QChangeEvent, LossEvent
export collect_metrics

# ============================================================================
# Test runners (for direct access)
# ============================================================================
export run_sanity_tests, run_causal_tests, run_invariant_tests
export run_seed_tests, run_exposure_tests, run_hotpool_tests
export run_constitutive_tests, run_dcp_tests

# ============================================================================
# Include submodules in dependency order
# ============================================================================

# Core types (no dependencies)
include("Core/SiteState.jl")
include("Core/SiteTelemetry.jl")
include("Core/RegionState.jl")
include("Core/HotPool.jl")
include("Core/Exposure.jl")

# Constitutive laws (depend on RegionState, SiteTelemetry)
include("Constitutive/Law.jl")
include("Constitutive/Newtonian.jl")
include("Constitutive/BinghamInspired.jl")

# DCP (depends on Core, Telemetry)
include("DCP/Snapshot.jl")
include("DCP/Actions.jl")
include("DCP/FixedRuleController.jl")
include("DCP/DCP.jl")

# Models (standalone)
include("Models/Stage0MLP.jl")

# Telemetry
include("Telemetry/Events.jl")
include("Telemetry/Metrics.jl")
include("Telemetry/TraceWriter.jl")
include("Telemetry/Telemetry.jl")

# Tasks (TODO - placeholder)
# include("Tasks/SyntheticConflictFamily.jl")

# Controls (TODO - unimplemented per spec requirement 14)
# These are placeholders only - not implemented in this pass
# include("Controls/Control.jl")

# Tests
include("Tests/Sanity/runtests.jl")
include("Tests/Causal/runtests.jl")
include("Tests/Invariants/runtests.jl")

end # module PlasticWeights
