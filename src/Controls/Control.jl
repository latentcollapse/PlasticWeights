"""
    Control

Abstract base type for all control mechanisms.

Controls implement various optimization and regulation strategies:
- C1_Adam: Adam optimizer
- C2_SGD: SGD optimizer  
- C3_ShadowAdam: Shadow Adam dynamics
- C4_AdaptiveScalar: Adaptive hyperparameters
- C5_Newtonian: Newtonian dynamics control
- C6_FixedSchedule: Fixed schedules
- C7_HistoryReset: History-based resets
- C8_PerSiteThreshold: Per-site thresholds
"""
abstract type Control end

# Include concrete implementations
include("C1_Adam.jl")
include("C2_SGD.jl")
include("C3_ShadowAdam.jl")
include("C4_AdaptiveScalar.jl")
include("C5_Newtonian.jl")
include("C6_FixedSchedule.jl")
include("C7_HistoryReset.jl")
include("C8_PerSiteThreshold.jl")

# Export types
export Control, C1_Adam, C2_SGD, C3_ShadowAdam, C4_AdaptiveScalar,
       C5_Newtonian, C6_FixedSchedule, C7_HistoryReset, C8_PerSiteThreshold

# Export default instances
export C1_ADAM_DEFAULT, C2_SGD_DEFAULT, C3_SHADOW_ADAM_DEFAULT,
       C4_ADAPTIVE_DEFAULT, C5_NEWTONIAN_DEFAULT, C6_FIXED_DEFAULT,
       C7_HISTORY_RESET_DEFAULT, C8_PER_SITE_DEFAULT
