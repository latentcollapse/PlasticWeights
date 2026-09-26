abstract type AbstractSnapshot end

"""
    Snapshot

Immutable declared DCP input. The controller has no access to substrate globals
or latent residual values outside this typed value object.
"""
struct Snapshot <: AbstractSnapshot
    site_index::Int32
    q::Int8
    allocated::Bool
    superplastic::Bool
    stress_ema::Float32
    residual_motion_ema::Float32
    consecutive_above_yield::Int32
    consecutive_stable::Int32
    yield_up::Float32
    settle_down::Float32
    k_yield::Int32
    k_settle::Int32
    epsilon_delta::Float32
    melt_budget_available::Bool
    tick::Int32

    function Snapshot(site_index::Integer, q::Integer,
                      allocated::Bool, superplastic::Bool,
                      stress_ema::Real, residual_motion_ema::Real,
                      consecutive_above_yield::Integer, consecutive_stable::Integer,
                      yield_up::Real, settle_down::Real,
                      k_yield::Integer, k_settle::Integer,
                      epsilon_delta::Real, melt_budget_available::Bool,
                      tick::Integer)
        q in (-1, 0, 1) || error("HardFailure: snapshot q must be ternary")
        new(Int32(site_index), Int8(q), allocated, superplastic,
            Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable),
            Float32(yield_up), Float32(settle_down), Int32(k_yield), Int32(k_settle),
            Float32(epsilon_delta), melt_budget_available, Int32(tick))
    end
end

"""
    FPSnapshot

Immutable declared DCP input for continuous floating-point parameter sites.
"""
struct FPSnapshot <: AbstractSnapshot
    site_index::Int32
    w::Float32
    allocated::Bool
    superplastic::Bool
    stress_ema::Float32
    residual_motion_ema::Float32
    consecutive_above_yield::Int32
    consecutive_stable::Int32
    yield_up::Float32
    settle_down::Float32
    k_yield::Int32
    k_settle::Int32
    epsilon_delta::Float32
    melt_budget_available::Bool
    tick::Int32

    function FPSnapshot(site_index::Integer, w::Real,
                        allocated::Bool, superplastic::Bool,
                        stress_ema::Real, residual_motion_ema::Real,
                        consecutive_above_yield::Integer, consecutive_stable::Integer,
                        yield_up::Real, settle_down::Real,
                        k_yield::Integer, k_settle::Integer,
                        epsilon_delta::Real, melt_budget_available::Bool,
                        tick::Integer)
        wf = Float32(w)
        isfinite(wf) || error("HardFailure: snapshot w must be finite, got $wf")
        new(Int32(site_index), wf, allocated, superplastic,
            Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable),
            Float32(yield_up), Float32(settle_down), Int32(k_yield), Int32(k_settle),
            Float32(epsilon_delta), melt_budget_available, Int32(tick))
    end
end

function create_snapshot(site_index::Integer, region::RegionState,
                         site::SiteState, telemetry::SiteTelemetry,
                         melt_budget_available::Bool, tick::Integer)::Snapshot
    return Snapshot(site_index, site.q, site.allocated, site.superplastic,
        telemetry.stress_ema, telemetry.residual_motion_ema,
        telemetry.consecutive_above_yield, telemetry.consecutive_stable,
        region.yield_up, region.settle_down, region.k_yield, region.k_settle,
        region.epsilon_delta, melt_budget_available, tick)
end

function create_snapshot(site_index::Integer, region::RegionState,
                         site::FPSiteState, telemetry::SiteTelemetry,
                         melt_budget_available::Bool, tick::Integer)::FPSnapshot
    return FPSnapshot(site_index, site.w, site.allocated, site.superplastic,
        telemetry.stress_ema, telemetry.residual_motion_ema,
        telemetry.consecutive_above_yield, telemetry.consecutive_stable,
        region.yield_up, region.settle_down, region.k_yield, region.k_settle,
        region.epsilon_delta, melt_budget_available, tick)
end
