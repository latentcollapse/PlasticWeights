"""
    C8_PerSiteThreshold

Per-site threshold control for Stage-0.

Implements per-site adaptive thresholds for melt/commit decisions.
Contrasts with region-shared thresholds.
"""
struct C8_PerSiteThreshold <: Control
    base_threshold::Float32
    adaptation_rate::Float32
    min_threshold::Float32
    max_threshold::Float32
    
    C8_PerSiteThreshold(base_threshold::Real=0.5, adaptation_rate::Real=0.01,
                        min_threshold::Real=0.01, max_threshold::Real=10.0) =
        new(Float32(base_threshold), Float32(adaptation_rate),
            Float32(min_threshold), Float32(max_threshold))
end

# Placeholder implementation
const C8_PER_SITE_DEFAULT = C8_PerSiteThreshold()
