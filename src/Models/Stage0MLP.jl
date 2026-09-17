"""
    Stage0MLP

A deterministic Stage-0 MLP following the frozen architecture:

    x → E_fixed → W_material → tanh → H_FP32 → y

Where:
- E_fixed: FP32, nonzero deterministic, frozen
- W_material: constructed from site exposures (not stored as trainable weights)
- Activation: tanh ONLY
- H_FP32: FP32, nonzero deterministic, trainable
- Output bias: trainable

No Flux/Zygote/GPU. Explicit MSE forward/backward.
"""
struct Stage0MLP
    E_fixed::Matrix{Float32}      # hidden_size × input_size, frozen
    H_FP32::Matrix{Float32}       # output_size × hidden_size, trainable
    output_bias::Vector{Float32}  # output_size, trainable
    input_size::Int32
    hidden_size::Int32
    output_size::Int32
    
    function Stage0MLP(input_size::Integer, hidden_size::Integer, output_size::Integer;
                       rng_seed::UInt32=42)
        if input_size <= 0 || hidden_size <= 0 || output_size <= 0
            error("HardFailure: MLP dimensions must be positive")
        end
        
        rng = Xoshiro(rng_seed)
        
        # E_fixed: nonzero deterministic initialization, frozen
        E_fixed = randn(rng, Float32, hidden_size, input_size) .* sqrt(2.0f0 / input_size)
        # Ensure nonzero
        for i in eachindex(E_fixed)
            if E_fixed[i] == 0.0f0
                E_fixed[i] = 1.0f-6
            end
        end
        
        # H_FP32: nonzero deterministic initialization, trainable
        H_FP32 = randn(rng, Float32, output_size, hidden_size) .* sqrt(2.0f0 / hidden_size)
        for i in eachindex(H_FP32)
            if H_FP32[i] == 0.0f0
                H_FP32[i] = 1.0f-6
            end
        end
        
        # Output bias: trainable
        output_bias = zeros(Float32, output_size)
        
        new(Float32.(E_fixed), Float32.(H_FP32), Float32.(output_bias),
            Int32(input_size), Int32(hidden_size), Int32(output_size))
    end
end

"""
    build_W_material(mlp::Stage0MLP, exposures::Vector{Float32}) -> Matrix{Float32}

Constructs W_material from site exposures.
Number of material sites = hidden_size * feature_size.
exposures must have length = hidden_size * input_size.
"""
function build_W_material(mlp::Stage0MLP, exposures::Vector{Float32})::Matrix{Float32}
    expected_len = mlp.hidden_size * mlp.input_size
    if length(exposures) != expected_len
        error("HardFailure: exposures length $(length(exposures)) != expected $expected_len")
    end
    # Reshape exposures into hidden_size × input_size matrix
    return reshape(exposures, mlp.hidden_size, mlp.input_size)
end

"""
    forward(mlp::Stage0MLP, x::Vector{Float32}, exposures::Vector{Float32}) -> (y, hidden_pre, hidden_post)

Performs forward pass: x → E_fixed → W_material → tanh → H_FP32 → y

Returns:
- y: output vector
- hidden_pre: pre-tanh activations (W_material * (E_fixed * x))
- hidden_post: post-tanh activations

Deterministic: same input always produces same output.
"""
function forward(mlp::Stage0MLP, x::Vector{Float32}, exposures::Vector{Float32})
    if length(x) != mlp.input_size
        error("HardFailure: input size $(length(x)) != expected $(mlp.input_size)")
    end
    
    # Step 1: E_fixed * x (fixed feature transformation)
    e_fixed_x = mlp.E_fixed * x  # hidden_size vector
    
    # Step 2: Build W_material from exposures and apply
    W_mat = build_W_material(mlp, exposures)
    hidden_pre = W_mat * e_fixed_x  # hidden_size vector
    
    # Step 3: tanh activation
    hidden_post = tanh.(hidden_pre)
    
    # Step 4: H_FP32 * hidden_post + output_bias
    y = mlp.H_FP32 * hidden_post .+ mlp.output_bias
    
    return y, hidden_pre, hidden_post
end

"""
    backward_mse(mlp::Stage0MLP, x::Vector{Float32}, exposures::Vector{Float32}, 
                 target::Vector{Float32}) -> (loss, grad_material, grad_e_fixed_x, grad_H, grad_bias)

Explicit MSE backward pass returning:
- loss: MSE loss
- grad_material: gradient wrt material coefficients (exposures)
- grad_e_fixed_x: gradient wrt fixed feature vector e = E_fixed * x
- grad_H: gradient wrt H_FP32
- grad_bias: gradient wrt output bias

No AD framework. Pure explicit Julia math.
"""
function backward_mse(mlp::Stage0MLP, x::Vector{Float32}, exposures::Vector{Float32},
                      target::Vector{Float32})
    # Forward pass
    y, hidden_pre, hidden_post = forward(mlp, x, exposures)
    
    # MSE loss: L = 0.5 * ||y - target||^2
    diff = y .- target
    loss = 0.5f0 * sum(diff .^ 2)
    
    # Gradient wrt y
    grad_y = diff  # dL/dy = y - target
    
    # Gradient wrt H_FP32: dL/dH = grad_y * hidden_post'
    grad_H = grad_y * hidden_post'  # output_size × hidden_size
    
    # Gradient wrt output_bias
    grad_bias = copy(grad_y)
    
    # Gradient wrt hidden_post: dL/dhidden_post = H_FP32' * grad_y
    grad_hidden_post = mlp.H_FP32' * grad_y
    
    # Gradient through tanh: dL/dhidden_pre = grad_hidden_post .* (1 - hidden_post.^2)
    grad_hidden_pre = grad_hidden_post .* (1.0f0 .- hidden_post .^ 2)
    
    # Gradient wrt W_material: dL/dW = grad_hidden_pre * e_fixed_x'
    e_fixed_x = mlp.E_fixed * x
    grad_W_mat = grad_hidden_pre * e_fixed_x'  # hidden_size × input_size
    
    # Gradient wrt material coefficients (exposures):
    # Since W_mat[i,j] = exposures[(i-1)*input_size + j], gradient flows directly
    grad_material = vec(grad_W_mat)
    
    # Gradient wrt e_fixed_x: dL/de_fixed_x = W_mat' * grad_hidden_pre
    W_mat = build_W_material(mlp, exposures)
    grad_e_fixed_x = W_mat' * grad_hidden_pre
    
    return loss, grad_material, grad_e_fixed_x, grad_H, grad_bias
end

"""
    get_trainable_params(mlp::Stage0MLP) -> Vector{Float32}

Returns all trainable parameters (H_FP32 and output_bias) as a flat vector.
E_fixed is frozen and not included.
"""
function get_trainable_params(mlp::Stage0MLP)::Vector{Float32}
    return vcat(vec(mlp.H_FP32), mlp.output_bias)
end

"""
    set_trainable_params!(mlp::Stage0MLP, params::Vector{Float32})

Sets trainable parameters from a flat vector.
"""
function set_trainable_params!(mlp::Stage0MLP, params::Vector{Float32})
    h_size = mlp.output_size * mlp.hidden_size
    if length(params) != h_size + mlp.output_size
        error("HardFailure: param vector length mismatch")
    end
    mlp.H_FP32 .= reshape(params[1:h_size], mlp.output_size, mlp.hidden_size)
    mlp.output_bias .= params[h_size+1:end]
end
