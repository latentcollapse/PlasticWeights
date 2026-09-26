"""
    C3TrainingConfig

Optimizer configuration for the end-to-end Stage-0 C3 control.

The material-coefficient branch and the conventional FP32 head are configured
separately so later experiments can match the head optimizer across treatment
arms without conflating it with the C3 shadow optimizer.
"""
struct C3TrainingConfig
    shadow::C3ShadowAdamConfig
    head::AdamConfig
end

C3TrainingConfig(; shadow::C3ShadowAdamConfig=DEFAULT_C3_SHADOW_ADAM,
    head::AdamConfig=DEFAULT_ADAM) =
    C3TrainingConfig(shadow, head)

const DEFAULT_C3_TRAINING = C3TrainingConfig()

"""
    C3TrainingState

Complete optimizer/control state for the Stage-0 C3 arm.

`shadow` owns the FP32 master values and Adam moments behind the visible
ternary material coefficients. `head_adam` and `bias_adam` own the optimizer
history for the shared conventional FP32 head.

No material-substrate state appears here: no stress, regions, yield, DCP,
hot pool, hysteresis, hardening, or developmental lifecycle.
"""
mutable struct C3TrainingState
    shadow::C3ShadowAdamState
    head_adam::AdamState{2}
    bias_adam::AdamState{1}
end

"""
    initialize_c3_training(mlp; q=0)
    initialize_c3_training(mlp, q_values)

Create the full C3 training state for a `Stage0MLP`.

The visible material layer begins from the requested ternary checkpoint while
the ordinary head/bias Adam moments begin at zero.
"""
function initialize_c3_training(mlp::Stage0MLP;
    q::Integer=0)::C3TrainingState
    shadow = initialize_c3_shadow_adam(num_material_sites(mlp); q=q)
    state = C3TrainingState(
        shadow,
        initialize_adam_state(mlp.H_FP32),
        initialize_adam_state(mlp.output_bias),
    )
    check_invariants(state, mlp)
    return state
end

function initialize_c3_training(
    mlp::Stage0MLP,
    q_values::AbstractVector{<:Integer},
)::C3TrainingState
    length(q_values) == num_material_sites(mlp) ||
        error("HardFailure: C3 checkpoint/material-site length mismatch")

    state = C3TrainingState(
        initialize_c3_shadow_adam(q_values),
        initialize_adam_state(mlp.H_FP32),
        initialize_adam_state(mlp.output_bias),
    )
    check_invariants(state, mlp)
    return state
end

"""
    check_invariants(state::C3TrainingState, mlp)

Validate the C3 control, head optimizer shapes, and synchronized training-step
counters.
"""
function check_invariants(state::C3TrainingState,
    mlp::Stage0MLP)
    length(state.shadow.q) == num_material_sites(mlp) ||
        error("HardFailure: C3 shadow/material-site length mismatch")

    check_invariants(state.shadow)
    check_invariants(state.head_adam, mlp.H_FP32)
    check_invariants(state.bias_adam, mlp.output_bias)

    step = state.shadow.step
    state.head_adam.step == step ||
        error("HardFailure: C3 shadow/head Adam steps diverged")
    state.bias_adam.step == step ||
        error("HardFailure: C3 shadow/bias Adam steps diverged")

    return true
end

"""
    c3_predict(mlp, state, X)

Run the Stage-0 network using an immutable snapshot of C3's currently visible
ternary coefficients. No optimizer state is modified.
"""
function c3_predict(mlp::Stage0MLP,
    state::C3TrainingState,
    X::AbstractMatrix{<:Real})
    check_invariants(state, mlp)
    exposures = c3_exposure_snapshot(state.shadow)
    return forward(mlp, X, exposures).y
end

function c3_predict(mlp::Stage0MLP,
    state::C3TrainingState,
    x::AbstractVector{<:Real})
    check_invariants(state, mlp)
    exposures = c3_exposure_snapshot(state.shadow)
    return forward(mlp, x, exposures).y
end

"""
    c3_training_step!(mlp, state, X, target,
                      config=DEFAULT_C3_TRAINING)

Execute one complete Stage-0 C3 learning tick:

    1. snapshot visible ternary C3 coefficients,
    2. forward through the shared `Stage0MLP`,
    3. compute explicit MSE gradients,
    4. apply the STE by feeding `grad_material` directly to the FP32 shadow,
    5. update the shadow with Adam and requantize for the next tick,
    6. update `H_FP32` and `output_bias` with ordinary Adam.

All gradients are computed from the same pre-update forward state. Therefore
parameter-update order cannot contaminate the gradients for another branch.
The returned `exposures` and `prediction` are the immutable pre-update values;
`next_exposures` are what the next tick will see.
"""
function c3_training_step!(
    mlp::Stage0MLP,
    state::C3TrainingState,
    X::AbstractMatrix{<:Real},
    target::AbstractMatrix{<:Real},
    config::C3TrainingConfig=DEFAULT_C3_TRAINING,
)
    check_invariants(state, mlp)

    exposures = c3_exposure_snapshot(state.shadow)
    backward = backward_mse(mlp, X, exposures, target)

    # Same local STE convention as the frozen Stage-0 material interface:
    # ∂L/∂shadow := ∂L/∂q_visible.
    c3_shadow_adam_step!(
        state.shadow,
        backward.grad_material,
        config.shadow,
    )

    # The conventional FP32 head is shared experimental infrastructure. Its
    # optimizer must be matched across treatment/control arms.
    adam_step!(
        mlp.H_FP32,
        backward.grad_H,
        state.head_adam,
        config.head,
    )
    adam_step!(
        mlp.output_bias,
        backward.grad_bias,
        state.bias_adam,
        config.head,
    )

    check_invariants(state, mlp)

    return (
        loss=backward.loss,
        prediction=backward.forward.y,
        exposures=exposures,
        next_exposures=c3_exposure_snapshot(state.shadow),
        grad_material=backward.grad_material,
        grad_head=backward.grad_H,
        grad_bias=backward.grad_bias,
        step=state.shadow.step,
    )
end

function c3_training_step!(
    mlp::Stage0MLP,
    state::C3TrainingState,
    x::AbstractVector{<:Real},
    target::AbstractVector{<:Real},
    config::C3TrainingConfig=DEFAULT_C3_TRAINING,
)
    result = c3_training_step!(
        mlp,
        state,
        reshape(Float32.(x), length(x), 1),
        reshape(Float32.(target), length(target), 1),
        config,
    )

    return (
        loss=result.loss,
        prediction=vec(result.prediction),
        exposures=result.exposures,
        next_exposures=result.next_exposures,
        grad_material=result.grad_material,
        grad_head=result.grad_head,
        grad_bias=result.grad_bias,
        step=result.step,
    )
end
