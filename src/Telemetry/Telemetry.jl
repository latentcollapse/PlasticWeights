"""
    Telemetry

Telemetry module for tracking substrate dynamics.

Exports events, metrics, and trace writing functionality.
"""

# Include submodules
include("Events.jl")
include("Metrics.jl")
include("TraceWriter.jl")

# Export types
export Event, TickEvent, MeltEvent, CommitEvent, HardeningEvent, QChangeEvent, LossEvent
export Metrics, collect_metrics
export TraceWriter, log_event!, log_metric!, clear!, get_events, get_metrics, write_to_file

# Export factory functions
export make_tick_event, make_melt_event, make_commit_event, 
       make_hardening_event, make_q_change_event, make_loss_event
