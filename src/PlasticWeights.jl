"""
    PlasticWeights

Deterministic Stage-0 reference kernel for the frozen PlasticWeights v0.1.0
specification. This package surface intentionally stops at the causal reference
kernel (S0/S1/S1b/S2/S3/S3b); long-run tasks, controls, and experiment
telemetry are not loaded yet.
"""
module PlasticWeights

using Random

# Core
export SiteState, SiteTelemetry, RegionState, RegionMap, HotPool, SubstrateState
export check_invariants, get_region_id, get_region, get_region_for_site
export allocate!, release!, get_residual, set_residual!, integrate_residual!
export num_allocated, available_count, has_capacity, is_valid_handle
export update_stress_ema!, update_residual_motion_ema!, update_counters!, reset_lifecycle_counters!
export ternary_round
export ExposurePolicy, ZCS, VPS, exposure, exposure_snapshot
export initialize_stage0_seed, initialize_consolidated_substrate

# Constitutive laws
export ConstitutiveLaw, response, Newtonian, NEWTONIAN
export BinghamInspired, BINGHAM_INSPIRED

# DCP
export DCP, Snapshot, Action, NoAction, MeltAction, CommitAction
export FixedRuleController, FIXED_RULE_CONTROLLER
export create_snapshot, decide, apply_action!, action_code

# Model/reference path
export Stage0MLP, num_material_sites, material_exposures, build_W_material
export forward, backward_mse, reference_material_tick!

include("Core/SiteState.jl")
include("Core/SiteTelemetry.jl")
include("Core/RegionState.jl")
include("Core/HotPool.jl")
include("Core/Quantizer.jl")
include("Core/Exposure.jl")
include("Core/Initialization.jl")

include("Constitutive/Law.jl")
include("Constitutive/Newtonian.jl")
include("Constitutive/BinghamInspired.jl")

include("DCP/DCP.jl")
include("DCP/Snapshot.jl")
include("DCP/Actions.jl")
include("DCP/FixedRuleController.jl")

include("Models/Stage0MLP.jl")
include("Reference/ReferenceKernel.jl")

end # module PlasticWeights
