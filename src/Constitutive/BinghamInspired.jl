"""
    BinghamInspired(epsilon=1f-6)

Stage-0 computational mobility law (D2 fix, E0 report §8.2):

    c   = |EMA(g)| / EMA(|g|)          (gradient-direction persistence)
    m   = (σ + ε) / (σ + ε + τ·(1-c))
    Δδ  = -(g / η) * m

The legacy law `m = max(0, 1 - τ/σ)` hard-vetoed flow below the yield stress.
Because the DCP settle gate already restricts residual motion to low-stress
regimes and work-hardening monotonically inflates τ, that veto eventually
suppressed all flow fleet-wide (E0b: 0 learners in 48 Bingham points — the
hardening ratchet converts τ into a permanent flow ban).

The repaired law *shapes* motion instead of vetoing it:

- τ = 0                → m = 1          (exactly Newtonian)
- unconflicted (c = 1) → m = 1          (yield does not throttle aligned flow)
- hardened + conflict  → m ≈ (σ+ε)/τ    (small but strictly > 0: no deadlock)

Mobility is scale-covariant in (σ, τ, ε): scaling gradients by k scales σ, and
scaling both τ and ε by k leaves m invariant. This preserves the S1b
loss-scale covariance contract (test doubles ε alongside τ).

Conflict here is *self-referenced* (recent gradient direction vs its own
persistent EMA). The v0.2 §8.3 consolidated-reference conflict estimator
(cᴮ = max(0, -cos(g_now, g_ref))) requires per-site reference gradients and
arrives with the Pass-3 consolidation-tag work; this law is its Stage-0
substrate.
"""
struct BinghamInspired <: ConstitutiveLaw
    epsilon::Float32
    function BinghamInspired(epsilon::Real=1.0f-6)
        epsf = Float32(epsilon)
        epsf > 0.0f0 || error("HardFailure: Bingham epsilon must be > 0")
        new(epsf)
    end
end

const BINGHAM_INSPIRED = BinghamInspired()

function response(law::BinghamInspired, region::RegionState,
                  telemetry::SiteTelemetry, g::Real)::Float32
    sigma = telemetry.stress_ema
    c = gradient_consistency(telemetry)
    denom = sigma + law.epsilon + region.yield_up * (1.0f0 - c)
    mobility = (sigma + law.epsilon) / denom
    return -(Float32(g) / region.eta) * mobility
end
