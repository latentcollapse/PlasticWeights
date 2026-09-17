"""
    SyntheticConflictFamily

A family of synthetic conflict tasks for Stage-0 testing.

Used to test:
- S2 seed learnability
- History-dependent credit assignment
- Material dynamics under conflict
"""
struct SyntheticConflictFamily
    num_sites::Int32
    num_patterns::Int32
    conflict_level::Float32
    patterns::Vector{Vector{Int8}}  # ternary patterns {-1, 0, +1}
    targets::Vector{Float32}
    
    function SyntheticConflictFamily(num_sites::Integer=64, num_patterns::Integer=8;
                                    conflict_level::Real=0.5, rng_seed::UInt32=123)
        if num_sites <= 0 || num_patterns <= 0
            error("HardFailure: num_sites and num_patterns must be positive")
        end
        
        rng = Xoshiro(rng_seed)
        
        # Generate random ternary patterns
        patterns = [rand(rng, [-1, 0, 1], num_sites) for _ in 1:num_patterns]
        
        # Generate targets with controlled conflict
        targets = randn(rng, Float32, num_patterns) .* Float32(conflict_level)
        
        new(Int32(num_sites), Int32(num_patterns), Float32(conflict_level), patterns, targets)
    end
end

"""
    get_pattern(family::SyntheticConflictFamily, pattern_idx::Int) -> Vector{Int8}

Returns the specified pattern from the family.
"""
function get_pattern(family::SyntheticConflictFamily, pattern_idx::Int)::Vector{Int8}
    if pattern_idx < 1 || pattern_idx > family.num_patterns
        error("HardFailure: pattern_idx $pattern_idx out of range [1, $(family.num_patterns)]")
    end
    return family.patterns[pattern_idx]
end

"""
    get_target(family::SyntheticConflictFamily, pattern_idx::Int) -> Float32

Returns the target value for the specified pattern.
"""
function get_target(family::SyntheticConflictFamily, pattern_idx::Int)::Float32
    if pattern_idx < 1 || pattern_idx > family.num_patterns
        error("HardFailure: pattern_idx $pattern_idx out of range [1, $(family.num_patterns)]")
    end
    return family.targets[pattern_idx]
end

"""
    evaluate(family::SyntheticConflictFamily, predictions::Vector{Float32}) -> Float32

Computes mean squared error between predictions and targets.
"""
function evaluate(family::SyntheticConflictFamily, predictions::Vector{Float32})::Float32
    if length(predictions) != family.num_patterns
        error("HardFailure: predictions length $(length(predictions)) != num_patterns $(family.num_patterns)")
    end
    
    mse = 0.0f0
    for i in 1:family.num_patterns
        diff = predictions[i] - family.targets[i]
        mse += diff * diff
    end
    
    return mse / family.num_patterns
end

"""
    batch_forward(family::SyntheticConflictFamily, model, sites::Vector{SiteState}) -> Vector{Float32}

Runs batch forward pass through all patterns.
"""
function batch_forward(family::SyntheticConflictFamily, model, sites::Vector{SiteState})::Vector{Float32}
    predictions = zeros(Float32, family.num_patterns)
    
    for p in 1:family.num_patterns
        pattern = family.patterns[p]
        
        # Create input from site states and pattern
        input = zeros(Float32, family.num_sites)
        for i in 1:family.num_sites
            # Combine pattern with site state
            input[i] = Float32(pattern[i]) * Float32(sites[i].q)
        end
        
        # Forward pass
        output = forward(model, input)
        
        # Take first output as prediction (scalar regression)
        predictions[p] = output[1]
    end
    
    return predictions
end
