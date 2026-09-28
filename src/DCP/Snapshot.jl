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
    conflict_k::Int32
    consecutive_conflicted::Int32
    consolidation_tick::Int32
    commit_sign::Int8
    plastic_since::Int32
    commit_stress::Float32
    melt_tag_agrees::Bool
    consecutive_conflicted_undirected::Int32
    phase_length::Int32
    ticks_into_phase::Int32

    function FPSnapshot(site_index::Integer, w::Real,
                        allocated::Bool, superplastic::Bool,
                        stress_ema::Real, residual_motion_ema::Real,
                        consecutive_above_yield::Integer, consecutive_stable::Integer,
                        yield_up::Real, settle_down::Real,
                        k_yield::Integer, k_settle::Integer,
                        epsilon_delta::Real, melt_budget_available::Bool,
                        tick::Integer;
                        conflict_k::Integer=1,
                        consecutive_conflicted::Integer=0,
                        consolidation_tick::Integer=0,
                        commit_sign::Integer=0,
                        plastic_since::Integer=0,
                        commit_stress::Real=0.0,
                        melt_tag_agrees::Bool=false,
                        consecutive_conflicted_undirected::Integer=0,
                        phase_length::Integer=0,
                        ticks_into_phase::Integer=-1)
        wf = Float32(w)
        isfinite(wf) || error("HardFailure: snapshot w must be finite, got $wf")
        commit_sign in (-1, 0, 1) ||
            error("HardFailure: snapshot commit_sign must be in {-1,0,1}")
        # E0e phase-position metadata (harness-declared, DCP-inert):
        # phase_length is the declared length of the current training phase;
        # ticks_into_phase is DERIVED from the authoritative tick unless a
        # caller with an out-of-band clock supplies it explicitly.
        L = Int32(phase_length)
        L >= 0 || error("HardFailure: snapshot phase_length must be >= 0, got $L")
        tip = Int32(ticks_into_phase)
        if L == 0
            tip == 0 || error("HardFailure: snapshot with no declared phase_length must report 0 ticks_into_phase, got $tip")
        else
            if tip < 0
                tip = Int32(mod(tick - 1, L))
            end
            Int32(0) <= tip < L ||
                error("HardFailure: snapshot ticks_into_phase $tip out of range [0, $(L-1)] for phase_length $L")
        end
        new(Int32(site_index), wf, allocated, superplastic,
            Float32(stress_ema), Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable),
            Float32(yield_up), Float32(settle_down), Int32(k_yield), Int32(k_settle),
            Float32(epsilon_delta), melt_budget_available, Int32(tick),
            Int32(conflict_k), Int32(consecutive_conflicted),
            Int32(consolidation_tick), Int8(commit_sign), Int32(plastic_since),
            Float32(commit_stress), Bool(melt_tag_agrees),
            Int32(consecutive_conflicted_undirected), L, tip)
    end
end

function create_snapshot(site_index::Integer, region::RegionState,
                         site::SiteState, telemetry::SiteTelemetry,
                         melt_budget_available::Bool, tick::Integer;
                         phase_length::Union{Nothing,Integer}=nothing)::Snapshot
    # Ternary sites carry no regime metadata (the phase family decides only on
    # FPSnapshots); the keyword is accepted for kernel call uniformity.
    return Snapshot(site_index, site.q, site.allocated, site.superplastic,
        telemetry.stress_ema, telemetry.residual_motion_ema,
        telemetry.consecutive_above_yield, telemetry.consecutive_stable,
        region.yield_up, region.settle_down, region.k_yield, region.k_settle,
        region.epsilon_delta, melt_budget_available, tick)
end

"""
    create_snapshot(...; phase_length=nothing)

E0e: the effective declared phase length is the caller's `phase_length` when
positive (the harness's per-run declaration wins), else the region's declared
`phase_length`. 0 from both sources means "not declared" and is passed through
so the snapshot constructor's validation decides what it means per controller.
"""
function create_snapshot(site_index::Integer, region::RegionState,
                         site::FPSiteState, telemetry::SiteTelemetry,
                         melt_budget_available::Bool, tick::Integer;
                         phase_length::Union{Nothing,Integer}=nothing)::FPSnapshot
    declared = phase_length === nothing ? Int(region.phase_length) : Int(phase_length)
    effective = declared > 0 ? declared : Int(region.phase_length)
    return FPSnapshot(site_index, site.w, site.allocated, site.superplastic,
        telemetry.stress_ema, telemetry.residual_motion_ema,
        telemetry.consecutive_above_yield, telemetry.consecutive_stable,
        region.yield_up, region.settle_down, region.k_yield, region.k_settle,
        region.epsilon_delta, melt_budget_available, tick;
        conflict_k=region.conflict_k,
        consecutive_conflicted=telemetry.consecutive_conflicted,
        consolidation_tick=site.consolidation_tick,
        commit_sign=site.commit_sign,
        plastic_since=site.plastic_since,
        commit_stress=site.commit_stress,
        melt_tag_agrees=(site.commit_sign != 0 && isfinite(telemetry.signed_stress_ema) &&
                         telemetry.signed_stress_ema != 0.0f0 &&
                         sign(telemetry.signed_stress_ema) == site.commit_sign),
        consecutive_conflicted_undirected=telemetry.consecutive_conflicted_undirected,
        phase_length=effective,
        ticks_into_phase=(effective > 0 ? mod(tick - 1, effective) : 0))
end
