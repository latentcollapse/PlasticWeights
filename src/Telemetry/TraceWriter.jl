"""
    TraceWriter

Writes telemetry events and metrics to a trace for later analysis.

Follows deterministic reference mode requirements:
- Deterministic iteration order
- No unordered hash-map iteration in state transition paths
"""
mutable struct TraceWriter
    events::Vector{Event}
    metrics::Vector{Metrics}
    max_events::Int32
    max_metrics::Int32
    
    function TraceWriter(max_events::Integer=10000, max_metrics::Integer=1000)
        if max_events <= 0 || max_metrics <= 0
            error("HardFailure: TraceWriter limits must be positive")
        end
        
        events = Vector{Event}(undef, 0)
        metrics = Vector{Metrics}(undef, 0)
        
        new(events, metrics, Int32(max_events), Int32(max_metrics))
    end
end

"""
    log_event!(writer::TraceWriter, event::Event)

Logs an event to the trace.
"""
function log_event!(writer::TraceWriter, event::Event)
    if length(writer.events) >= writer.max_events
        # Circular buffer: remove oldest
        popfirst!(writer.events)
    end
    push!(writer.events, event)
end

"""
    log_metric!(writer::TraceWriter, metric::Metrics)

Logs a metric snapshot to the trace.
"""
function log_metric!(writer::TraceWriter, metric::Metrics)
    if length(writer.metrics) >= writer.max_metrics
        # Circular buffer: remove oldest
        popfirst!(writer.metrics)
    end
    push!(writer.metrics, metric)
end

"""
    clear!(writer::TraceWriter)

Clears all logged events and metrics.
"""
function clear!(writer::TraceWriter)
    empty!(writer.events)
    empty!(writer.metrics)
end

"""
    get_events(writer::TraceWriter) -> Vector{Event}

Returns all logged events.
"""
get_events(writer::TraceWriter)::Vector{Event} = copy(writer.events)

"""
    get_metrics(writer::TraceWriter) -> Vector{Metrics}

Returns all logged metrics.
"""
get_metrics(writer::TraceWriter)::Vector{Metrics} = copy(writer.metrics)

"""
    write_to_file(writer::TraceWriter, filename::String)

Writes the trace to a file (simple text format for now).
"""
function write_to_file(writer::TraceWriter, filename::String)
    open(filename, "w") do io
        writeln(io, "# PlasticWeights Trace")
        writeln(io, "# Events: $(length(writer.events))")
        writeln(io, "# Metrics: $(length(writer.metrics))")
        writeln(io, "")
        
        writeln(io, "## Events")
        for event in writer.events
            writeln(io, event)
        end
        
        writeln(io, "")
        writeln(io, "## Metrics")
        for metric in writer.metrics
            writeln(io, metric)
        end
    end
end

# Simple writeln helper
writeln(io, x) = println(io, x)
