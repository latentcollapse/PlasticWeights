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
export AbstractSiteState, SiteState, FPSiteState, SiteTelemetry, RegionState, RegionMap, HotPool, SubstrateState
export check_invariants, get_region_id, get_region, get_region_for_site
export allocate!, release!, get_residual, set_residual!, integrate_residual!
export num_allocated, available_count, has_capacity, is_valid_handle
export update_stress_ema!, update_residual_motion_ema!, update_counters!, reset_lifecycle_counters!
export update_signed_stress_ema!, gradient_consistency
export ternary_round
export ExposurePolicy, ZCS, VPS, RampedZCS, RampedVPS
export exposure, exposure_snapshot, commit_base, commit_blend
export effective_ramp_ticks, adaptive_ramp_ticks, stamp_transition!
export PhaseMachineController, PHASE_MACHINE_CONTROLLER
export TagRoutingController, TAG_ROUTING_CONTROLLER
export RegimeAdaptiveController, REGIME_ADAPTIVE_CONTROLLER
export MeltRoutingController, MELT_ROUTING_CONTROLLER
export UndirectedController, UNDIRECTED_CONTROLLER
export update_undirected_conflict!
export initialize_stage0_seed, initialize_consolidated_substrate
export initialize_fp_seed, initialize_fp_consolidated_substrate

# Constitutive laws
export ConstitutiveLaw, response, Newtonian, NEWTONIAN
export BinghamInspired, BINGHAM_INSPIRED

# DCP
export DCP, AbstractSnapshot, Snapshot, FPSnapshot, Action, NoAction, MeltAction, CommitAction, LifecycleAction
export FixedRuleController, FIXED_RULE_CONTROLLER
export create_snapshot, decide, apply_action!, action_code

# Model/reference path
export Stage0MLP, num_material_sites, material_exposures, build_W_material
export forward, backward_mse, reference_material_tick!

# Material end-to-end training
export MaterialTrainingConfig, MaterialTrainingState, DEFAULT_MATERIAL_TRAINING
export initialize_material_training, material_predict, material_training_step!

# Telemetry
export DevelopmentalEvent, MilestoneKind, EventRecord
export FIRST_DELTA, PHENOTYPIC_WAKE, CREDIT_UNLOCK
export MilestoneEvent, MeltEvent, CommitEvent, FPMeltEvent, FPCommitEvent
export event_tick, event_site, is_lifecycle_event
export TelemetrySummary, melt_count, commit_count, nonzero_prior_remelt_count
export commit_flip_count, zcs_lesion_total, hardening_total
export superplastic_durations, mean_superplastic_duration
export milestone_tick, first_delta_tick, wake_tick, credit_unlock_tick
export summarize_events
export DevelopmentalRecorder, event_trace, reset_recorder!
export record_wake!, record_credit_unlock!, record_first_delta!
export observe_action_before, record_action_after!

# Conventional Adam helper
export AdamConfig, AdamState, DEFAULT_ADAM
export initialize_adam_state, reset_adam!, adam_step!

# C3 control
export C3ShadowAdamConfig, C3ShadowAdamState, DEFAULT_C3_SHADOW_ADAM
export initialize_c3_shadow_adam, c3_exposure_snapshot, c3_shadow_values
export c3_shadow_adam_step!

# C3 end-to-end training
export C3TrainingConfig, C3TrainingState, DEFAULT_C3_TRAINING
export initialize_c3_training, c3_predict, c3_training_step!

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

include("Controls/AdamState.jl")
include("Controls/C3_ShadowAdam.jl")
include("Controls/C3_Training.jl")

include("Telemetry/Events.jl")
include("Telemetry/Metrics.jl")
include("Telemetry/Recorder.jl")

include("Reference/ReferenceKernel.jl")
include("Reference/MaterialTraining.jl")

end # module PlasticWeights
