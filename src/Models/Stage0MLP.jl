"""
    Stage0MLP

A deterministic Stage-0 MLP (Multi-Layer Perceptron) for the reference implementation.

Follows the build order requirement:
- Deterministic in reference mode
- CPU, single-threaded execution
- Deterministic iteration order
- Deterministic RNG

This is a simple prototype - not optimized for performance.
"""
struct Stage0MLP
    weights::Vector{Float32}
    biases::Vector{Float32}
    input_size::Int32
    hidden_size::Int32
    output_size::Int32
    
    function Stage0MLP(input_size::Integer, hidden_size::Integer, output_size::Integer; 
                       rng_seed::UInt32=42)
        if input_size <= 0 || hidden_size <= 0 || output_size <= 0
            error("HardFailure: MLP dimensions must be positive")
        end
        
        # Deterministic initialization with fixed seed
        rng = Xoshiro(rng_seed)
        
        # Xavier/Glorot initialization
        total_params = (input_size * hidden_size + hidden_size * output_size + 
                       hidden_size + output_size)
        weights = randn(rng, Float32, total_params) .* sqrt(2.0f0 / (input_size + output_size))
        biases = zeros(Float32, hidden_size + output_size)
        
        new(Int32(input_size), Int32(hidden_size), Int32(output_size), weights, biases)
    end
end

"""
    forward(mlp::Stage0MLP, input::Vector{Float32}) -> Vector{Float32}

Performs a forward pass through the MLP.

Deterministic: same input always produces same output.
"""
function forward(mlp::Stage0MLP, input::Vector{Float32})::Vector{Float32}
    if length(input) != mlp.input_size
        error("HardFailure: input size $(length(input)) != expected $(mlp.input_size)")
    end
    
    # Hidden layer: ReLU(W1 * x + b1)
    hidden = zeros(Float32, mlp.hidden_size)
    for h in 1:mlp.hidden_size
        sum = mlp.biases[h]
        for i in 1:mlp.input_size
            idx = (h - 1) * mlp.input_size + i
            sum += mlp.weights[idx] * input[i]
        end
        hidden[h] = relu(sum)
    end
    
    # Output layer: W2 * hidden + b2
    output = zeros(Float32, mlp.output_size)
    bias_offset = mlp.hidden_size
    weight_offset = mlp.input_size * mlp.hidden_size
    
    for o in 1:mlp.output_size
        sum = mlp.biases[bias_offset + o]
        for h in 1:mlp.hidden_size
            idx = weight_offset + (o - 1) * mlp.hidden_size + h
            sum += mlp.weights[idx] * hidden[h]
        end
        output[o] = sum
    end
    
    return output
end

# Simple ReLU activation
relu(x::Real) = x > 0 ? Float32(x) : 0.0f0

"""
    get_params(mlp::Stage0MLP) -> Vector{Float32}

Returns all parameters (weights and biases) as a flat vector.
"""
function get_params(mlp::Stage0MLP)::Vector{Float32}
    return vcat(mlp.weights, mlp.biases)
end

"""
    set_params!(mlp::Stage0MLP, params::Vector{Float32})

Sets all parameters from a flat vector.
"""
function set_params!(mlp::Stage0MLP, params::Vector{Float32})
    expected_len = length(mlp.weights) + length(mlp.biases)
    if length(params) != expected_len
        error("HardFailure: param vector length $(length(params)) != expected $expected_len")
    end
    
    n_weights = length(mlp.weights)
    mlp.weights .= params[1:n_weights]
    mlp.biases .= params[n_weights+1:end]
end
