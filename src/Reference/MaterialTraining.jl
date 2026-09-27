"""
    MaterialTrainingConfig

End-to-end Stage-0 material-arm training configuration.

The material branch is parameterized by:
- a constitutive law,
- a DCP,
- an exposure policy,
- stress/residual EMA coefficients,

while the conventional FP32 head uses the same `AdamConfig` helper as C3.

Keeping the head optimizer separate from the material dynamics makes the
treatment fork narrow and auditable:

    shared backward pass
        ├── grad_material -> material substrate
        ├── grad_H        -> ordinary Adam
        └── grad_bias     -> ordinary Adam
"""
struct MaterialTrainingConfig{
    L<:ConstitutiveLaw,
    D<:DCP,
    P<:ExposurePolicy,
}
    law::L
    dcp::D
    policy::P
    head::AdamConfig
    beta::Float32
    gamma::Float32

    function MaterialTrainingConfig(
        law::L,
        dcp::D,
        policy::P,
        head::AdamConfig,
        beta::Real,
        gamma::Real,
    ) where {
        L<:ConstitutiveLaw,
        D<:DCP,
        P<:ExposurePolicy,
    }
        β = Float32(beta)
        γ = Float32(gamma)

        isfinite(β) && 0.0f0 <= β <= 1.0f0 ||
            error("HardFailure: material beta must be finite and in [0,1]")
        isfinite(γ) && 0.0f0 <= γ <= 1.0f0 ||
            error("HardFailure: material gamma must be finite and in [0,1]")

        new{L,D,P}(law, dcp, policy, head, β, γ)
    end
end

MaterialTrainingConfig(;
    law::ConstitutiveLaw=BINGHAM_INSPIRED,
    dcp::DCP=FIXED_RULE_CONTROLLER,
    policy::ExposurePolicy=ZCS(),
    head::AdamConfig=DEFAULT_ADAM,
    beta::Real=0.9f0,
    gamma::Real=0.9f0,
) = MaterialTrainingConfig(law, dcp, policy, head, beta, gamma)

const DEFAULT_MATERIAL_TRAINING = MaterialTrainingConfig()

"""
    MaterialTrainingState

Complete mutable training state for the Stage-0 material arm.

`substrate` owns the developmental/material state.
`head_adam` and `bias_adam` own conventional optimizer history for the shared
FP32 output head.
`step` is the authoritative training-tick counter for this end-to-end path.
"""
mutable struct MaterialTrainingState
    substrate::SubstrateState
    head_adam::AdamState{2}
    bias_adam::AdamState{1}
    step::Int64
end

"""
    initialize_material_training(mlp, substrate)

Attach conventional head optimizer state to an already-constructed material
substrate. This is the preferred initializer for causal experiments because the
substrate construction remains explicit and inspectable.
"""
function initialize_material_training(
    mlp::Stage0MLP,
    substrate::SubstrateState,
)::MaterialTrainingState
    length(substrate.sites) == num_material_sites(mlp) ||
        error("HardFailure: material substrate/site count does not match Stage0MLP")

    state = MaterialTrainingState(
        substrate,
        initialize_adam_state(mlp.H_FP32),
        initialize_adam_state(mlp.output_bias),
        Int64(0),
    )

    check_invariants(state, mlp)
    return state
end

"""
    initialize_material_training(mlp; region_size=64, ...)

Convenience constructor for the normative all-superplastic Stage-0 seed.
Experiments that need custom checkpoint/history construction should use the
two-argument initializer instead.
"""
function initialize_material_training(
    mlp::Stage0MLP;
    region_size::Integer=64,
    yield_up::Real=0.5f0,
    settle_down::Real=0.3f0,
    eta::Real=1.0f0,
    hardening_increment::Real=0.05f0,
    epsilon_delta::Real=0.1f0,
    k_yield::Integer=3,
    k_settle::Integer=3,
)::MaterialTrainingState
    substrate = initialize_stage0_seed(
        num_material_sites(mlp);
        region_size=region_size,
        yield_up=yield_up,
        settle_down=settle_down,
        eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta,
        k_yield=k_yield,
        k_settle=k_settle,
    )
    return initialize_material_training(mlp, substrate)
end

"""
    check_invariants(state::MaterialTrainingState, mlp)

Validate the substrate, head optimizer shapes, and synchronized training clock.
"""
function check_invariants(
    state::MaterialTrainingState,
    mlp::Stage0MLP,
)
    length(state.substrate.sites) == num_material_sites(mlp) ||
        error("HardFailure: material substrate/material-site length mismatch")

    check_invariants(state.substrate)
    check_invariants(state.head_adam, mlp.H_FP32)
    check_invariants(state.bias_adam, mlp.output_bias)

    state.step >= 0 ||
        error("HardFailure: material training step must be nonnegative")
    state.head_adam.step == state.step ||
        error("HardFailure: material head Adam/training steps diverged")
    state.bias_adam.step == state.step ||
        error("HardFailure: material bias Adam/training steps diverged")

    return true
end

"""
    material_predict(mlp, state, X, policy)

Forward-only prediction from the current material exposure state.

No material, telemetry, optimizer, or lifecycle state is mutated.
"""
function material_predict(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
    X::AbstractMatrix{<:Real},
    policy::ExposurePolicy,
)
    check_invariants(state, mlp)
    exposures = exposure_snapshot(state.substrate.sites, policy)
    return forward(mlp, X, exposures).y
end

"""Tick-aware read-only prediction (E0c): ramped policies report staged
visibility at `tick`; legacy policies ignore the tick."""
function material_predict(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
    X::AbstractMatrix{<:Real},
    policy::ExposurePolicy,
    tick::Integer,
)
    check_invariants(state, mlp)
    exposures = exposure_snapshot(state.substrate.sites, policy, tick)
    return forward(mlp, X, exposures).y
end

function material_predict(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
    x::AbstractVector{<:Real},
    policy::ExposurePolicy,
)
    check_invariants(state, mlp)
    exposures = exposure_snapshot(state.substrate.sites, policy)
    return forward(mlp, x, exposures).y
end

"""
    material_training_step!(mlp, state, X, target,
                            config=DEFAULT_MATERIAL_TRAINING;
                            recorder=nothing)

Execute one complete frozen-order Stage-0 material learning tick.

The important causal ordering is:

    1. immutable exposure snapshot
    2. forward
    3. MSE loss
    4. backward
    5. material coefficient gradients
    6-14. material stress/constitutive/DCP/lifecycle path
    15. observer logging
    16. next-tick exposure

The conventional FP32 head is updated from the *same pre-update backward pass*
using ordinary Adam. Thus C3 and the material arm share the network, loss,
backward equations, and head optimizer; only the `grad_material` treatment
differs.

If a recorder is supplied:
- PHENOTYPIC_WAKE is observed from the same snapshot used by the forward pass,
- CREDIT_UNLOCK is observed from the explicit upstream `grad_features`,
- FIRST_DELTA and lifecycle events are emitted by `reference_material_tick!`.

The return value exposes both the immutable pre-update exposure and the
post-lifecycle exposure that the next tick will observe.
"""
function material_training_step!(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
    X::AbstractMatrix{<:Real},
    target::AbstractMatrix{<:Real},
    config::MaterialTrainingConfig=DEFAULT_MATERIAL_TRAINING;
    recorder::Union{Nothing,DevelopmentalRecorder}=nothing,
)
    check_invariants(state, mlp)

    next_tick = state.step + 1
    next_tick > 0 ||
        error("HardFailure: material training step overflow")

    # Step 1: this exact snapshot is consumed by forward/backward. Tick-aware
    # overload (E0c): ramped policies stage commit visibility by tick; legacy
    # policies ignore the tick and return the frozen 2-arg result.
    exposures = exposure_snapshot(
        state.substrate.sites,
        config.policy,
        state.step + 1,
    )

    recorder === nothing ||
        record_wake!(recorder, next_tick, exposures)

    # Steps 2-5: shared network/loss/backward path.
    backward = backward_mse(
        mlp,
        X,
        exposures,
        target,
    )

    recorder === nothing ||
        record_credit_unlock!(
            recorder,
            next_tick,
            backward.grad_features,
        )

    # Steps 6-14: material-only treatment path.
    material = reference_material_tick!(
        state.substrate,
        backward.grad_material,
        config.law,
        config.dcp,
        config.policy;
        beta=config.beta,
        gamma=config.gamma,
        tick=next_tick,
        recorder=recorder,
    )

    # `reference_material_tick!` takes its own immutable snapshot. It must be
    # exactly the one used by this tick's forward/backward path; otherwise the
    # experiment has a torn exposure.
    material.exposures == exposures ||
        error("HardFailure: material training tick observed torn exposure")

    # Shared conventional FP32 head update. Gradients were already computed
    # before either branch mutated state.
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

    state.step = next_tick
    check_invariants(state, mlp)

    # What the NEXT tick's immutable snapshot will expose (E0c: tick-aware so
    # ramped policies report the staged visibility, not the final value).
    next_exposures = exposure_snapshot(
        state.substrate.sites,
        config.policy,
        state.step + 1,
    )

    return (
        loss=backward.loss,
        prediction=backward.forward.y,
        exposures=exposures,
        next_exposures=next_exposures,
        grad_material=backward.grad_material,
        grad_features=backward.grad_features,
        grad_head=backward.grad_H,
        grad_bias=backward.grad_bias,
        delta_updates=material.delta_updates,
        actions=material.actions,
        step=state.step,
    )
end

function material_training_step!(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
    x::AbstractVector{<:Real},
    target::AbstractVector{<:Real},
    config::MaterialTrainingConfig=DEFAULT_MATERIAL_TRAINING;
    recorder::Union{Nothing,DevelopmentalRecorder}=nothing,
)
    result = material_training_step!(
        mlp,
        state,
        reshape(Float32.(x), length(x), 1),
        reshape(Float32.(target), length(target), 1),
        config;
        recorder=recorder,
    )

    return (
        loss=result.loss,
        prediction=vec(result.prediction),
        exposures=result.exposures,
        next_exposures=result.next_exposures,
        grad_material=result.grad_material,
        grad_features=vec(result.grad_features),
        grad_head=result.grad_head,
        grad_bias=result.grad_bias,
        delta_updates=result.delta_updates,
        actions=result.actions,
        step=result.step,
    )
end
