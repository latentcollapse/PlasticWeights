abstract type AbstractSiteState end

"""
    SiteState

Logical Stage-0 parameter-site state:

    (q, allocated, superplastic, hot_handle)

`q` is always one of -1, 0, +1. A superplastic site must own a nonzero
hot-pool handle; a non-superplastic site must not own one. Cross-checking that
a nonzero handle is actually allocated in a particular `HotPool` is performed
by `check_invariants(substrate)`.
"""
mutable struct SiteState <: AbstractSiteState
    q::Int8
    allocated::Bool
    superplastic::Bool
    hot_handle::Int32

    function SiteState(q::Integer, allocated::Bool=false,
                       superplastic::Bool=false, hot_handle::Integer=0)
        q in (-1, 0, 1) || error("HardFailure: site q must be in {-1,0,+1}, got $q")
        hot_handle >= 0 || error("HardFailure: hot_handle must be >= 0, got $hot_handle")
        !allocated && superplastic && error("HardFailure: vacant site cannot be superplastic")
        superplastic && hot_handle == 0 && error("HardFailure: superplastic site lacks hot handle")
        !superplastic && hot_handle != 0 && error("HardFailure: non-superplastic site owns hot handle $hot_handle")
        new(Int8(q), allocated, superplastic, Int32(hot_handle))
    end
end

SiteState(; q::Integer=0, allocated::Bool=false,
          superplastic::Bool=false, hot_handle::Integer=0) =
    SiteState(q, allocated, superplastic, hot_handle)

is_valid_q(site::SiteState)::Bool = site.q in (-1, 0, 1)
has_valid_hot_handle(site::AbstractSiteState)::Bool = site.hot_handle != 0

function check_invariants(site::SiteState)
    is_valid_q(site) || error("HardFailure: site q must be in {-1,0,+1}, got $(site.q)")
    !site.allocated && site.superplastic && error("HardFailure: vacant site cannot be superplastic")
    site.superplastic && site.hot_handle == 0 && error("HardFailure: superplastic site lacks hot handle")
    !site.superplastic && site.hot_handle != 0 && error("HardFailure: non-superplastic site owns hot handle $(site.hot_handle)")
    return true
end

"""
    FPSiteState

Continuous floating-point parameter-site state for non-Newtonian viscoplasticity:

    (w, allocated, superplastic, hot_handle)

plus the E0c symbolic phase record (Pass 2 of the gate-fix programme):

    phase               -- :plastic (hot residual open) or :committed
    consolidation_tick  -- tick of the last commit (0 = no recorded commit)
    last_commit_delta   -- residual δ merged at that commit (ramp reference)
    commit_sign         -- sign of the gradient EMA at consolidation time; the
                           site's minimal consolidation reference. Conflict
                           (sustained opposed load) is measured against this,
                           not against the moving EMA, so it survives the EMA
                           zero-crossing. Generalized by Pass-3 tags.
    plastic_since       -- tick at which the site last (re)entered the plastic
                           phase (stamped at MELT); 0 while committed and for
                           unstamped direct manipulation. Drives the commit
                           dwell (chattering hysteresis).
    commit_stress       -- stress EMA at consolidation time. The conflict
                           certificate's floor is relative to this (opposed
                           load must be at least CONFLICT_FLOOR × the load the
                           site consolidated under), because "sustained
                           disagreement" is a statement about the site's own
                           load regime, not about the region's yield.
    ramp_ticks          -- length of the current exposure transition (E0c
                           P5′/P5″): max(ramp_k, ceil(|δ_eff|/m_max)) where
                           δ_eff is the remaining VISIBLE distance to w at
                           stamp time. 0 = no transition in progress (also the
                           unstamped/hand-built state, which falls back to the
                           policy's fixed ramp_k). The record SURVIVES melt
                           (P5″ trajectory continuity): lifecycle events
                           redirect the exposure trajectory, never interrupt
                           it.
    exposed_base::Float32 -- visible value when the current transition started
                           (P5″). With (transition_start, ramp_ticks) it fully
                           determines the exposure trajectory
                           x(t) = exposed_base + (w − exposed_base)·b(t),
                           valid for BOTH phases: a plastic site glides from
                           its pre-melt visible value to w at the melt; a
                           committed site glides from its pre-commit value.
                           0 when no transition is in flight (bit-0 sentinel,
                           safe: real bases are generally nonzero).
    transition_start::Int32 -- tick at which the current transition started.
                           0 = none.

The phase alphabet is deliberately two-symbol: Plastic ↔ Committed (plus
Vacant). Dwell/hysteresis live in the telemetry counters and the controller;
what the site itself persists is *what it consolidated under, when, and how
long it has been plastic*.
"""
mutable struct FPSiteState <: AbstractSiteState
    w::Float32
    allocated::Bool
    superplastic::Bool
    hot_handle::Int32
    phase::Symbol
    consolidation_tick::Int32
    last_commit_delta::Float32
    commit_sign::Int8
    plastic_since::Int32
    commit_stress::Float32
    ramp_ticks::Int32
    exposed_base::Float32
    transition_start::Int32

    function FPSiteState(w::Real, allocated::Bool=false,
                         superplastic::Bool=false, hot_handle::Integer=0;
                         last_commit_delta::Real=0.0, commit_sign::Integer=0,
                         commit_stress::Real=0.0)
        wf = Float32(w)
        isfinite(wf) || error("HardFailure: site w must be finite, got $wf")
        hot_handle >= 0 || error("HardFailure: hot_handle must be >= 0, got $hot_handle")
        !allocated && superplastic && error("HardFailure: vacant site cannot be superplastic")
        superplastic && hot_handle == 0 && error("HardFailure: superplastic site lacks hot handle")
        !superplastic && hot_handle != 0 && error("HardFailure: non-superplastic site owns hot handle $hot_handle")
        lcd = Float32(last_commit_delta)
        isfinite(lcd) || error("HardFailure: last_commit_delta must be finite, got $lcd")
        commit_sign in (-1, 0, 1) || error("HardFailure: commit_sign must be in {-1,0,1}, got $commit_sign")
        cs = Float32(commit_stress)
        isfinite(cs) && cs >= 0.0f0 || error("HardFailure: commit_stress must be finite and >= 0, got $cs")
        # Phase is derived, never supplied: a site with an open hot residual is
        # Plastic; everything else is Committed material. consolidation_tick is
        # meaningful only for committed sites; plastic_since only for plastic
        # ones (0 = unstamped).
        phase = superplastic ? :plastic : :committed
        consolidation_tick = Int32(0)
        plastic_since = superplastic ? Int32(0) : Int32(0)
        new(wf, allocated, superplastic, Int32(hot_handle), phase,
            consolidation_tick, lcd, Int8(commit_sign), plastic_since, cs,
            Int32(0), 0.0f0, Int32(0))
    end
end

FPSiteState(; w::Real=0.0f0, allocated::Bool=false,
            superplastic::Bool=false, hot_handle::Integer=0,
            last_commit_delta::Real=0.0, commit_sign::Integer=0,
            commit_stress::Real=0.0) =
    FPSiteState(w, allocated, superplastic, hot_handle;
                last_commit_delta=last_commit_delta, commit_sign=commit_sign,
                commit_stress=commit_stress)

function check_invariants(site::FPSiteState)
    isfinite(site.w) || error("HardFailure: site w must be finite, got $(site.w)")
    !site.allocated && site.superplastic && error("HardFailure: vacant site cannot be superplastic")
    site.superplastic && site.hot_handle == 0 && error("HardFailure: superplastic site lacks hot handle")
    !site.superplastic && site.hot_handle != 0 && error("HardFailure: non-superplastic site owns hot handle $(site.hot_handle)")
    site.superplastic == (site.phase === :plastic) ||
        error("HardFailure: phase $(site.phase) inconsistent with superplastic=$(site.superplastic)")
    # P5″: a plastic site may carry the PREVIOUS commit's record only while an
    # exposure transition is in flight (ramp_ticks > 0) — the visible value is
    # still gliding to w. A stale record without a transition is a bug.
    site.superplastic && site.consolidation_tick != Int32(0) && site.ramp_ticks == Int32(0) &&
        error("HardFailure: stale consolidation record on plastic site without transition")
    site.consolidation_tick >= Int32(0) ||
        error("HardFailure: negative consolidation tick $(site.consolidation_tick)")
    site.plastic_since >= Int32(0) ||
        error("HardFailure: negative plastic_since $(site.plastic_since)")
    !site.superplastic && site.plastic_since != Int32(0) &&
        error("HardFailure: committed site carries plastic_since $(site.plastic_since)")
    isfinite(site.last_commit_delta) ||
        error("HardFailure: last_commit_delta must be finite, got $(site.last_commit_delta)")
    site.commit_sign in (-1, 0, 1) ||
        error("HardFailure: commit_sign must be in {-1,0,1}, got $(site.commit_sign)")
    isfinite(site.commit_stress) && site.commit_stress >= 0.0f0 ||
        error("HardFailure: commit_stress must be finite and >= 0, got $(site.commit_stress)")
    site.ramp_ticks >= Int32(0) ||
        error("HardFailure: negative ramp_ticks $(site.ramp_ticks)")
    isfinite(site.exposed_base) ||
        error("HardFailure: exposed_base must be finite, got $(site.exposed_base)")
    site.transition_start >= Int32(0) ||
        error("HardFailure: negative transition_start $(site.transition_start)")
    # Transition record coherence: a transition needs both its length and its
    # start; no transition means neither.
    ((site.ramp_ticks > Int32(0)) == (site.transition_start > Int32(0))) ||
        error("HardFailure: incoherent transition record (ramp_ticks=$(site.ramp_ticks), transition_start=$(site.transition_start))")
    return true
end

