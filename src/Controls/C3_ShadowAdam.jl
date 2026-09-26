"""
    C3ShadowAdamConfig

Hyperparameters for the frozen Stage-0 C3 control:

    Shadow-Latent + STE + Adam, no constitutive law.

C3 is intentionally *not* a material substrate. It has:
- one continuous FP32 shadow value per material coefficient,
- one visible balanced-ternary coefficient per shadow value,
- the same STE interpretation of coefficient gradients,
- conventional Adam updates of the shadow values.

It has no rheology, stress state, yield threshold, hysteresis, DCP lifecycle,
hot pool, work-hardening, or material-history state.

The purpose of C3 is to test whether the material arm contributes anything
beyond ordinary shadow-latent quantized learning.
"""
struct C3ShadowAdamConfig
    learning_rate::Float32
    beta1::Float32
    beta2::Float32
    epsilon::Float32

    function C3ShadowAdamConfig(; learning_rate::Real=1.0f-3,
        beta1::Real=0.9f0,
        beta2::Real=0.999f0,
        epsilon::Real=1.0f-8)
        lr = Float32(learning_rate)
        b1 = Float32(beta1)
        b2 = Float32(beta2)
        eps = Float32(epsilon)

        isfinite(lr) && lr > 0.0f0 ||
            error("HardFailure: C3 learning_rate must be finite and > 0")
        isfinite(b1) && 0.0f0 <= b1 < 1.0f0 ||
            error("HardFailure: C3 beta1 must be finite and in [0,1)")
        isfinite(b2) && 0.0f0 <= b2 < 1.0f0 ||
            error("HardFailure: C3 beta2 must be finite and in [0,1)")
        isfinite(eps) && eps > 0.0f0 ||
            error("HardFailure: C3 epsilon must be finite and > 0")

        new(lr, b1, b2, eps)
    end
end

const DEFAULT_C3_SHADOW_ADAM = C3ShadowAdamConfig()

"""
    C3ShadowAdamState

State owned by the C3 control.

`latent[i]` is the absolute continuous shadow value for visible coefficient
`q[i]`; it is not the material residual δ used by the PlasticWeights substrate.

Invariant:

    q[i] == ternary_round(latent[i])

Adam moment buffers are conventional optimizer state, not material history.
"""
mutable struct C3ShadowAdamState
    q::Vector{Int8}
    latent::Vector{Float32}
    first_moment::Vector{Float32}
    second_moment::Vector{Float32}
    step::Int64
end

"""
    initialize_c3_shadow_adam(num_sites; q=0)

Create a C3 state with every visible coefficient initialized to `q` and every
continuous shadow initialized to the same numeric value.
"""
function initialize_c3_shadow_adam(num_sites::Integer;
    q::Integer=0)::C3ShadowAdamState
    num_sites > 0 || error("HardFailure: C3 num_sites must be positive")
    q in (-1, 0, 1) || error("HardFailure: C3 q must be ternary")

    qv = fill(Int8(q), Int(num_sites))
    latent = fill(Float32(q), Int(num_sites))
    state = C3ShadowAdamState(
        qv,
        latent,
        zeros(Float32, Int(num_sites)),
        zeros(Float32, Int(num_sites)),
        Int64(0),
    )
    check_invariants(state)
    return state
end

"""
    initialize_c3_shadow_adam(q_values)

Create C3 from an explicit ternary checkpoint. Each shadow value begins exactly
at its corresponding visible ternary value.
"""
function initialize_c3_shadow_adam(
    q_values::AbstractVector{<:Integer},
)::C3ShadowAdamState
    isempty(q_values) && error("HardFailure: C3 q_values cannot be empty")

    qv = Vector{Int8}(undef, length(q_values))
    latent = Vector{Float32}(undef, length(q_values))

    for i in eachindex(q_values)
        qi = q_values[i]
        qi in (-1, 0, 1) ||
            error("HardFailure: C3 q_values[$i] must be ternary")
        qv[i] = Int8(qi)
        latent[i] = Float32(qi)
    end

    state = C3ShadowAdamState(
        qv,
        latent,
        zeros(Float32, length(qv)),
        zeros(Float32, length(qv)),
        Int64(0),
    )
    check_invariants(state)
    return state
end

"""
    c3_exposure_snapshot(state)

Immutable-for-this-tick visible ternary coefficient snapshot.

C3 has no superplastic exposure policy: forward exposure is always the current
quantized shadow value.
"""
c3_exposure_snapshot(state::C3ShadowAdamState)::Vector{Int8} = copy(state.q)

"""Return a defensive copy of the continuous C3 shadow values."""
c3_shadow_values(state::C3ShadowAdamState)::Vector{Float32} = copy(state.latent)

function check_invariants(state::C3ShadowAdamState)
    n = length(state.q)
    n > 0 || error("HardFailure: C3 state cannot be empty")
    length(state.latent) == n ||
        error("HardFailure: C3 q/latent length mismatch")
    length(state.first_moment) == n ||
        error("HardFailure: C3 q/first-moment length mismatch")
    length(state.second_moment) == n ||
        error("HardFailure: C3 q/second-moment length mismatch")
    state.step >= 0 || error("HardFailure: C3 step must be nonnegative")

    for i in eachindex(state.q)
        qi = state.q[i]
        qi in (-1, 0, 1) ||
            error("HardFailure: C3 q[$i] left {-1,0,+1}")

        li = state.latent[i]
        mi = state.first_moment[i]
        vi = state.second_moment[i]

        isfinite(li) ||
            error("HardFailure: C3 latent[$i] is not finite")
        isfinite(mi) ||
            error("HardFailure: C3 first_moment[$i] is not finite")
        isfinite(vi) && vi >= 0.0f0 ||
            error("HardFailure: C3 second_moment[$i] is invalid")

        qi == ternary_round(li) ||
            error("HardFailure: C3 q/latent quantization mismatch at site $i")
    end

    return true
end

"""
    c3_shadow_adam_step!(state, gradients, config=DEFAULT_C3_SHADOW_ADAM)

Apply one conventional Adam update to the continuous C3 shadows, then quantize
the updated shadows to produce the visible coefficients for the *next* tick.

The supplied `gradients` are the Stage-0 material-coefficient gradients
`∂L/∂q_visible`. C3 uses the same straight-through estimator convention as the
material arm:

    ∂L/∂latent := ∂L/∂q_visible

No derivative through `ternary_round` is taken.

This operation is deliberately free of all constitutive/material concepts:
there is no stress EMA, yield, viscosity, DCP, melt/commit event, hardening, or
hot residual.
"""
function c3_shadow_adam_step!(
    state::C3ShadowAdamState,
    gradients::AbstractVector{<:Real},
    config::C3ShadowAdamConfig=DEFAULT_C3_SHADOW_ADAM,
)::C3ShadowAdamState
    n = length(state.q)
    length(gradients) == n ||
        error("HardFailure: C3 gradient/state length mismatch")

    next_step = state.step + 1
    next_step > 0 || error("HardFailure: C3 Adam step overflow")

    beta1 = config.beta1
    beta2 = config.beta2
    one_minus_beta1 = 1.0f0 - beta1
    one_minus_beta2 = 1.0f0 - beta2

    # Bias-correction denominators are scalar for the entire vector.
    bias1 = 1.0f0 - beta1^next_step
    bias2 = 1.0f0 - beta2^next_step

    bias1 > 0.0f0 || error("HardFailure: C3 invalid Adam beta1 correction")
    bias2 > 0.0f0 || error("HardFailure: C3 invalid Adam beta2 correction")

    for i in eachindex(state.q)
        g = Float32(gradients[i])
        isfinite(g) ||
            error("HardFailure: C3 gradient[$i] is not finite")

        m = beta1 * state.first_moment[i] + one_minus_beta1 * g
        v = beta2 * state.second_moment[i] + one_minus_beta2 * (g * g)

        state.first_moment[i] = m
        state.second_moment[i] = v

        mhat = m / bias1
        vhat = v / bias2
        update = config.learning_rate * mhat / (sqrt(vhat) + config.epsilon)

        latent = state.latent[i] - update
        isfinite(latent) ||
            error("HardFailure: C3 latent[$i] became non-finite")

        state.latent[i] = latent
        state.q[i] = ternary_round(latent)
    end

    state.step = next_step
    check_invariants(state)
    return state
end
