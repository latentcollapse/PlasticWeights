"""
    SiteTelemetry

Declared site-level operative telemetry used by the Stage-0 constitutive law
and DCP. The latent residual δ is deliberately *not* stored here; HotPool is
its sole source of truth.
"""
mutable struct SiteTelemetry
    stress_ema::Float32
    signed_stress_ema::Float32
    residual_motion_ema::Float32
    consecutive_above_yield::Int32
    consecutive_stable::Int32
    consecutive_conflicted::Int32
    consecutive_conflicted_undirected::Int32

    function SiteTelemetry(stress_ema::Real=0.0,
                           residual_motion_ema::Real=0.0,
                           consecutive_above_yield::Integer=0,
                           consecutive_stable::Integer=0;
                           signed_stress_ema::Real=NaN,
                           consecutive_conflicted::Integer=0,
                           consecutive_conflicted_undirected::Integer=0)
        stress_ema >= 0 || error("HardFailure: stress EMA cannot be negative")
        residual_motion_ema >= 0 || error("HardFailure: residual-motion EMA cannot be negative")
        consecutive_above_yield >= 0 || error("HardFailure: negative above-yield counter")
        consecutive_stable >= 0 || error("HardFailure: negative stable counter")
        consecutive_conflicted >= 0 || error("HardFailure: negative conflict counter")
        consecutive_conflicted_undirected >= 0 ||
            error("HardFailure: negative undirected conflict counter")
        # signed_stress_ema defaults to NaN ("unknown"): hand-constructed
        # telemetry that specifies only magnitudes is treated as fresh state
        # (consistency 0), not as a silently wrong directional statistic.
        # update_signed_stress_ema! derives it from stress_ema when unset.
        ss = Float32(signed_stress_ema)
        isfinite(ss) || (ss = Float32(NaN32))
        new(Float32(stress_ema), ss, Float32(residual_motion_ema),
            Int32(consecutive_above_yield), Int32(consecutive_stable),
            Int32(consecutive_conflicted),
            Int32(consecutive_conflicted_undirected))
    end
end

const _SIGNED_STRESS_NAN = Float32(NaN32)

"""Consistency c = |EMA(g)| / EMA(|g|) in [0,1]; 0 when unknown."""
function gradient_consistency(telemetry::SiteTelemetry)::Float32
    s = telemetry.signed_stress_ema
    isfinite(s) || return 0.0f0
    telemetry.stress_ema > 0.0f0 || return 0.0f0
    return min(1.0f0, abs(s) / telemetry.stress_ema)
end

"""
Update s_t = β s_{t-1} + (1-β) g_t. On first use (NaN sentinel) the EMA is
initialized from zero prior: s_0 = (1-β) g_0, exactly matching the magnitude
EMA's own first-step convention, so a constant-signed gradient stream has
c = 1 bit-exactly from the first tick. Zero-gradient rest never contaminates
the ratio: both EMAs decay at the same geometric rate, so c persists at its
last learned value (rest is "quiet", not "conflicted").
"""
function update_signed_stress_ema!(telemetry::SiteTelemetry, g::Real, beta::Real)::Float32
    b = _check_ema_factor("beta", beta)
    gf = Float32(g)
    if !isfinite(telemetry.signed_stress_ema)
        telemetry.signed_stress_ema = (1.0f0 - b) * gf
        return telemetry.signed_stress_ema
    end
    telemetry.signed_stress_ema = b * telemetry.signed_stress_ema + (1.0f0 - b) * gf
    return telemetry.signed_stress_ema
end

function _check_ema_factor(name::AbstractString, x::Real)::Float32
    xf = Float32(x)
    0.0f0 <= xf <= 1.0f0 || error("HardFailure: $name must be in [0,1], got $x")
    return xf
end

"""Update σ_t = β σ_{t-1} + (1-β)|g_t|."""
function update_stress_ema!(telemetry::SiteTelemetry, g::Real, beta::Real)::Float32
    b = _check_ema_factor("beta", beta)
    telemetry.stress_ema = b * telemetry.stress_ema + (1.0f0 - b) * abs(Float32(g))
    return telemetry.stress_ema
end

"""Update r_t = γ r_{t-1} + (1-γ)|Δδ_t|."""
function update_residual_motion_ema!(telemetry::SiteTelemetry,
                                     delta_delta::Real, gamma::Real)::Float32
    g = _check_ema_factor("gamma", gamma)
    telemetry.residual_motion_ema =
        g * telemetry.residual_motion_ema + (1.0f0 - g) * abs(Float32(delta_delta))
    return telemetry.residual_motion_ema
end

"""
Update the two declared sustained-eligibility counters from current telemetry
and region thresholds.
"""
function update_counters!(telemetry::SiteTelemetry, yield_up::Real,
                          settle_down::Real, epsilon_delta::Real)
    if telemetry.stress_ema > Float32(yield_up)
        telemetry.consecutive_above_yield += Int32(1)
    else
        telemetry.consecutive_above_yield = Int32(0)
    end

    # D1 fix (E0 report §8.1): the settle certificate is gradient-direction
    # persistence, not low load magnitude. c = |EMA(g)| / EMA(|g|) is high when
    # gradients are small-but-consistent (converged learning), ~0 at rest
    # (direction noise) and under conflict (sign flips). Magnitude gates cannot
    # distinguish those regimes; c can. settle_down is therefore interpreted as
    # a consistency threshold in [0,1). Exact-zero rest (0/0) certifies 0 and
    # can never settle, which removes the anti-causal commit wave.
    if gradient_consistency(telemetry) >= Float32(settle_down) &&
       telemetry.residual_motion_ema < Float32(epsilon_delta)
        telemetry.consecutive_stable += Int32(1)
    else
        telemetry.consecutive_stable = Int32(0)
    end
    return nothing
end

"""
Five-argument counter update (E0c): adds the conflict certificate.

Conflict is measured against the site's consolidation reference, not the
moving EMA: a committed site with reference (commit_sign s, commit_stress σ_c)
is conflicted when it bears sustained, CONSISTENT load in the OPPOSITE
direction, at magnitude at least CONFLICT_FLOOR × σ_c (and never below the
tiny absolute epsilon floor, so noise cannot invalidate a site that
consolidated under near-zero load). This is what "the world now disagrees,
at comparable strength, with what this site consolidated under" means
operationally — and unlike EMA self-reference, it survives the EMA
zero-crossing that occurs when the network re-points.

Requires the owning site's reference (commit_sign, commit_stress); committed
sites without one (commit_sign == 0) can never be conflicted-certified.
"""
function update_counters!(telemetry::SiteTelemetry, yield_up::Real,
                          settle_down::Real, epsilon_delta::Real,
                          commit_sign::Integer, commit_stress::Real=0.0f0)
    update_counters!(telemetry, yield_up, settle_down, epsilon_delta)

    if commit_sign != 0
        floor = max(CONFLICT_FLOOR * Float32(commit_stress), CONFLICT_MIN_FLOOR)
        if gradient_consistency(telemetry) >= Float32(settle_down) &&
           telemetry.stress_ema >= floor
            opposite = sign(telemetry.signed_stress_ema) == -Int8(commit_sign)
            if opposite
                telemetry.consecutive_conflicted += Int32(1)
                return nothing
            end
        end
    end
    telemetry.consecutive_conflicted = Int32(0)
    return nothing
end

"""
Direction-blind conflict counter (E0d ablation): identical thresholds and
floor, but ALIGNED sustained load counts too. Comparing the two counters
isolates what the tag's direction condition contributes.
"""
function update_undirected_conflict!(telemetry::SiteTelemetry,
                                     settle_down::Real,
                                     commit_stress::Real)
    if commit_stress > 0.0f0
        floor = max(CONFLICT_FLOOR * Float32(commit_stress), CONFLICT_MIN_FLOOR)
        if gradient_consistency(telemetry) >= Float32(settle_down) &&
           telemetry.stress_ema >= floor
            telemetry.consecutive_conflicted_undirected += Int32(1)
            return nothing
        end
    end
    telemetry.consecutive_conflicted_undirected = Int32(0)
    return nothing
end

"""
Fraction of the consolidating stress that sustained opposed load must reach
before it counts toward the conflict certificate. Below this floor, small
contrary drift cannot invalidate a consolidation record.
"""
const CONFLICT_FLOOR = 0.5f0

"""
Absolute lower bound on the conflict certificate's magnitude floor: a site
that consolidated under (near-)zero load can only be invalidated by load that
is at least meaningful at Stage-0 gradient scales.
"""
const CONFLICT_MIN_FLOOR = 1.0f-3

function reset_lifecycle_counters!(telemetry::SiteTelemetry)
    telemetry.consecutive_above_yield = Int32(0)
    telemetry.consecutive_stable = Int32(0)
    telemetry.consecutive_conflicted = Int32(0)
    telemetry.consecutive_conflicted_undirected = Int32(0)
    return nothing
end
