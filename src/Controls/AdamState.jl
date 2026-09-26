"""
    AdamConfig

Conventional Adam hyperparameters for ordinary FP32 parameters in the Stage-0
experimental harness.

This helper is intentionally substrate-agnostic. It has no knowledge of
material sites, rheology, exposure policies, DCP state, or developmental
history. The same implementation can therefore be shared by control arms and
the conventional FP32 head without changing the causal treatment.
"""
struct AdamConfig
    learning_rate::Float32
    beta1::Float32
    beta2::Float32
    epsilon::Float32

    function AdamConfig(; learning_rate::Real=1.0f-3,
        beta1::Real=0.9f0,
        beta2::Real=0.999f0,
        epsilon::Real=1.0f-8)
        lr = Float32(learning_rate)
        b1 = Float32(beta1)
        b2 = Float32(beta2)
        eps = Float32(epsilon)

        isfinite(lr) && lr > 0.0f0 ||
            error("HardFailure: Adam learning_rate must be finite and > 0")
        isfinite(b1) && 0.0f0 <= b1 < 1.0f0 ||
            error("HardFailure: Adam beta1 must be finite and in [0,1)")
        isfinite(b2) && 0.0f0 <= b2 < 1.0f0 ||
            error("HardFailure: Adam beta2 must be finite and in [0,1)")
        isfinite(eps) && eps > 0.0f0 ||
            error("HardFailure: Adam epsilon must be finite and > 0")

        new(lr, b1, b2, eps)
    end
end

const DEFAULT_ADAM = AdamConfig()

"""
    AdamState{N}

Optimizer state for an N-dimensional FP32 parameter array.

The moment buffers are concrete `Array{Float32,N}` values so the deterministic
CPU reference path does not hide optimizer state behind abstract containers.
"""
mutable struct AdamState{N}
    first_moment::Array{Float32,N}
    second_moment::Array{Float32,N}
    step::Int64
end

"""
    initialize_adam_state(parameters)

Allocate zeroed Adam moment buffers with exactly the same shape as `parameters`.

The Stage-0 conventional trainable parameters are FP32 arrays; accepting any
real-valued input here is useful for tests/initialization, while `adam_step!`
itself deliberately requires FP32 parameters so updates cannot silently round
through a different storage precision.
"""
function initialize_adam_state(
    parameters::AbstractArray{<:Real},
)::AdamState
    isempty(parameters) &&
        error("HardFailure: Adam parameter array cannot be empty")

    dims = size(parameters)
    state = AdamState(
        zeros(Float32, dims),
        zeros(Float32, dims),
        Int64(0),
    )
    check_invariants(state, parameters)
    return state
end

"""
    check_invariants(state::AdamState)
    check_invariants(state::AdamState, parameters)

Validate optimizer-local invariants, optionally including shape agreement with
a parameter array.
"""
function check_invariants(state::AdamState)
    size(state.first_moment) == size(state.second_moment) ||
        error("HardFailure: Adam moment-buffer shape mismatch")
    !isempty(state.first_moment) ||
        error("HardFailure: Adam state cannot be empty")
    state.step >= 0 ||
        error("HardFailure: Adam step must be nonnegative")

    for i in eachindex(state.first_moment, state.second_moment)
        m = state.first_moment[i]
        v = state.second_moment[i]

        isfinite(m) ||
            error("HardFailure: Adam first moment is not finite at index $i")
        isfinite(v) && v >= 0.0f0 ||
            error("HardFailure: Adam second moment is invalid at index $i")
    end

    return true
end

function check_invariants(state::AdamState,
    parameters::AbstractArray)
    check_invariants(state)
    size(parameters) == size(state.first_moment) ||
        error("HardFailure: Adam parameter/state shape mismatch")
    return true
end

"""
    reset_adam!(state)

Reset optimizer history without modifying the parameters it was associated
with. This is useful for explicit ablations; normal training should not call it.
"""
function reset_adam!(state::AdamState)
    fill!(state.first_moment, 0.0f0)
    fill!(state.second_moment, 0.0f0)
    state.step = Int64(0)
    return state
end

"""
    adam_step!(parameters, gradients, state, config=DEFAULT_ADAM)

Apply one conventional Adam update in-place:

    m_t = β₁ m_{t-1} + (1-β₁) g_t
    v_t = β₂ v_{t-1} + (1-β₂) g_t²

    m̂_t = m_t / (1-β₁^t)
    v̂_t = v_t / (1-β₂^t)

    θ_t = θ_{t-1} - α m̂_t / (sqrt(v̂_t) + ε)

The update performs no per-parameter-array temporary allocation. It mutates the
FP32 parameter storage and the associated moment buffers in place.
"""
function adam_step!(
    parameters::AbstractArray{Float32},
    gradients::AbstractArray{<:Real},
    state::AdamState,
    config::AdamConfig=DEFAULT_ADAM,
)
    axes(parameters) == axes(gradients) ||
        error("HardFailure: Adam gradient/parameter axes mismatch")
    size(parameters) == size(state.first_moment) ||
        error("HardFailure: Adam parameter/state shape mismatch")

    next_step = state.step + 1
    next_step > 0 ||
        error("HardFailure: Adam step overflow")

    β1 = config.beta1
    β2 = config.beta2
    one_minus_β1 = 1.0f0 - β1
    one_minus_β2 = 1.0f0 - β2

    bias1 = 1.0f0 - β1^next_step
    bias2 = 1.0f0 - β2^next_step

    bias1 > 0.0f0 ||
        error("HardFailure: Adam invalid beta1 bias correction")
    bias2 > 0.0f0 ||
        error("HardFailure: Adam invalid beta2 bias correction")

    for i in eachindex(
        parameters,
        gradients,
        state.first_moment,
        state.second_moment,
    )
        g = Float32(gradients[i])
        isfinite(g) ||
            error("HardFailure: Adam gradient is not finite at index $i")

        m = β1 * state.first_moment[i] + one_minus_β1 * g
        v = β2 * state.second_moment[i] + one_minus_β2 * (g * g)

        state.first_moment[i] = m
        state.second_moment[i] = v

        m̂ = m / bias1
        v̂ = v / bias2
        update = config.learning_rate * m̂ / (sqrt(v̂) + config.epsilon)

        θ = parameters[i] - update
        isfinite(θ) ||
            error("HardFailure: Adam parameter became non-finite at index $i")
        parameters[i] = θ
    end

    state.step = next_step
    check_invariants(state, parameters)
    return parameters
end
