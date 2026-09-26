"""
    Stage0MLP(input_size, hidden_size, output_size; feature_size=input_size, rng_seed=42)

Deterministic Stage-0 reference network:

    x -> E_fixed -> W_material -> tanh -> H_FP32 -> y

`E_fixed` is a frozen nonzero FP32 projection. `W_material` is never stored as
an FP32 trainable parameter: it is reconstructed from a tick's material
exposure snapshot. `H_FP32` and `output_bias` are the trainable conventional
head.
"""
struct Stage0MLP
    E_fixed::Matrix{Float32}      # feature_size × input_size (frozen)
    H_FP32::Matrix{Float32}       # output_size × hidden_size (trainable)
    output_bias::Vector{Float32}  # output_size (trainable)
    input_size::Int32
    feature_size::Int32
    hidden_size::Int32
    output_size::Int32

    function Stage0MLP(input_size::Integer, hidden_size::Integer, output_size::Integer;
                       feature_size::Integer=input_size, rng_seed::Integer=42)
        input_size > 0 || error("HardFailure: input_size must be positive")
        feature_size > 0 || error("HardFailure: feature_size must be positive")
        hidden_size > 0 || error("HardFailure: hidden_size must be positive")
        output_size > 0 || error("HardFailure: output_size must be positive")

        rng = Xoshiro(rng_seed)
        e_scale = sqrt(2.0f0 / Float32(input_size))
        h_scale = sqrt(2.0f0 / Float32(hidden_size))
        E_fixed = randn(rng, Float32, feature_size, input_size) .* e_scale
        H_FP32 = randn(rng, Float32, output_size, hidden_size) .* h_scale

        # Exact zeros are extraordinarily unlikely, but the architectural gate
        # is explicit: the fixed projection and head are nonzero at seed.
        for i in eachindex(E_fixed)
            E_fixed[i] == 0.0f0 && (E_fixed[i] = eps(Float32))
        end
        for i in eachindex(H_FP32)
            H_FP32[i] == 0.0f0 && (H_FP32[i] = eps(Float32))
        end

        bias = zeros(Float32, output_size)
        new(E_fixed, H_FP32, bias, Int32(input_size), Int32(feature_size),
            Int32(hidden_size), Int32(output_size))
    end
end

num_material_sites(mlp::Stage0MLP)::Int = Int(mlp.hidden_size) * Int(mlp.feature_size)

function material_exposures(sites::AbstractVector{SiteState},
                            policy::ExposurePolicy)::Vector{Float32}
    return Float32.(exposure_snapshot(sites, policy))
end

function build_W_material(mlp::Stage0MLP,
                          exposures::AbstractVector{<:Real})
    expected = num_material_sites(mlp)
    length(exposures) == expected ||
        error("HardFailure: exposure count $(length(exposures)) != material-site count $expected")
    # Julia's column-major reshape is the canonical logical site order for the
    # Stage-0 reference path; backward uses the same order via `vec`.
    return reshape(Float32.(exposures), Int(mlp.hidden_size), Int(mlp.feature_size))
end

"""
    forward(mlp, X, exposures)

`X` is `input_size × batch`. Returns a named tuple containing the output and
intermediates required by the explicit reference backward pass.
"""
function forward(mlp::Stage0MLP, X::AbstractMatrix{<:Real},
                 exposures::AbstractVector{<:Real})
    size(X, 1) == Int(mlp.input_size) ||
        error("HardFailure: input first dimension $(size(X,1)) != $(mlp.input_size)")
    Xf = Float32.(X)
    features = mlp.E_fixed * Xf
    W_material = build_W_material(mlp, exposures)
    preactivation = W_material * features
    hidden = tanh.(preactivation)
    y = mlp.H_FP32 * hidden .+ reshape(mlp.output_bias, Int(mlp.output_size), 1)
    return (y=y, features=features, preactivation=preactivation,
            hidden=hidden, W_material=W_material)
end

function forward(mlp::Stage0MLP, x::AbstractVector{<:Real},
                 exposures::AbstractVector{<:Real})
    f = forward(mlp, reshape(Float32.(x), length(x), 1), exposures)
    return (y=vec(f.y), features=vec(f.features),
            preactivation=vec(f.preactivation), hidden=vec(f.hidden),
            W_material=f.W_material)
end

"""
    backward_mse(mlp, X, exposures, target)

Explicit CPU reference backward for the canonical Stage-0 loss convention:

    L = 1/2 * mean((y - target)^2)

The mean is over every output element in the batch. No AD framework is used.
"""
function backward_mse(mlp::Stage0MLP, X::AbstractMatrix{<:Real},
                      exposures::AbstractVector{<:Real},
                      target::AbstractMatrix{<:Real})
    size(target, 1) == Int(mlp.output_size) ||
        error("HardFailure: target first dimension mismatch")
    size(target, 2) == size(X, 2) || error("HardFailure: target batch mismatch")

    f = forward(mlp, X, exposures)
    target_f = Float32.(target)
    diff = f.y .- target_f
    normalization = Float32(length(diff))
    loss = 0.5f0 * sum(abs2, diff) / normalization

    grad_y = diff ./ normalization
    grad_H = grad_y * f.hidden'
    grad_bias = vec(sum(grad_y; dims=2))
    grad_hidden = mlp.H_FP32' * grad_y
    grad_preactivation = grad_hidden .* (1.0f0 .- f.hidden .^ 2)
    grad_W_material = grad_preactivation * f.features'
    grad_material = vec(grad_W_material)
    grad_features = f.W_material' * grad_preactivation

    return (loss=loss,
            grad_material=grad_material,
            grad_features=grad_features,
            grad_H=grad_H,
            grad_bias=grad_bias,
            forward=f)
end

function backward_mse(mlp::Stage0MLP, x::AbstractVector{<:Real},
                      exposures::AbstractVector{<:Real},
                      target::AbstractVector{<:Real})
    b = backward_mse(mlp, reshape(Float32.(x), length(x), 1), exposures,
                     reshape(Float32.(target), length(target), 1))
    return (loss=b.loss,
            grad_material=b.grad_material,
            grad_features=vec(b.grad_features),
            grad_H=b.grad_H,
            grad_bias=b.grad_bias,
            forward=(y=vec(b.forward.y), features=vec(b.forward.features),
                     preactivation=vec(b.forward.preactivation),
                     hidden=vec(b.forward.hidden),
                     W_material=b.forward.W_material))
end
