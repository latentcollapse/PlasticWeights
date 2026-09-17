"""
    Metrics

Telemetry metrics for tracking substrate state and performance.

Collected at step 15 of the tick order.
"""
struct Metrics
    tick::Int32
    
    # Site statistics
    num_allocated::Int32
    num_superplastic::Int32
    num_consolidated::Int32
    
    # Hot pool statistics
    hot_pool_usage::Float32  # fraction of hot slots in use
    
    # Q distribution
    q_neg_count::Int32
    q_zero_count::Int32
    q_pos_count::Int32
    
    # Performance metrics
    loss::Float32
    gradient_norm::Float32
    stress_ema_mean::Float32
    stress_ema_std::Float32
    
    # Residual statistics
    residual_mean::Float32
    residual_std::Float32
    residual_max::Float32
end

function Metrics(tick::Integer; 
                 num_allocated::Integer=0, num_superplastic::Integer=0,
                 num_consolidated::Integer=0, hot_pool_usage::Real=0.0,
                 q_neg_count::Integer=0, q_zero_count::Integer=0,
                 q_pos_count::Integer=0, loss::Real=0.0,
                 gradient_norm::Real=0.0, stress_ema_mean::Real=0.0,
                 stress_ema_std::Real=0.0, residual_mean::Real=0.0,
                 residual_std::Real=0.0, residual_max::Real=0.0)
    Metrics(Int32(tick), Int32(num_allocated), Int32(num_superplastic),
            Int32(num_consolidated), Float32(hot_pool_usage),
            Int32(q_neg_count), Int32(q_zero_count), Int32(q_pos_count),
            Float32(loss), Float32(gradient_norm), Float32(stress_ema_mean),
            Float32(stress_ema_std), Float32(residual_mean),
            Float32(residual_std), Float32(residual_max))
end

# Default empty metrics
Metrics() = Metrics(0)

"""
    collect_metrics(sites, hot_pool, tick, loss=0, grad_norm=0) -> Metrics

Collects current metrics from the substrate state.
"""
function collect_metrics(sites::Vector{SiteState}, hot_pool::HotPool, 
                        tick::Integer, loss::Real=0.0, grad_norm::Real=0.0)::Metrics
    num_sites = length(sites)
    
    num_allocated = 0
    num_superplastic = 0
    num_consolidated = 0
    q_neg = 0
    q_zero = 0
    q_pos = 0
    
    stress_values = Float32[]
    residual_values = Float32[]
    
    for (i, site) in enumerate(sites)
        if site.allocated
            num_allocated += 1
        end
        
        if site.superplastic
            num_superplastic += 1
        else
            num_consolidated += 1
        end
        
        if site.q == -1
            q_neg += 1
        elseif site.q == 0
            q_zero += 1
        else
            q_pos += 1
        end
        
        # Collect stress/residual for superplastic sites
        if site.superplastic && site.hot_handle != 0
            push!(residual_values, get_residual(hot_pool, site.hot_handle))
        end
    end
    
    hot_pool_usage = num_superplastic / length(hot_pool.allocated)
    
    stress_mean = isempty(stress_values) ? 0.0f0 : mean(stress_values)
    stress_std = isempty(stress_values) ? 0.0f0 : std(stress_values)
    residual_mean = isempty(residual_values) ? 0.0f0 : mean(residual_values)
    residual_std = isempty(residual_values) ? 0.0f0 : std(residual_values)
    residual_max = isempty(residual_values) ? 0.0f0 : maximum(residual_values)
    
    return Metrics(tick;
                   num_allocated=num_allocated,
                   num_superplastic=num_superplastic,
                   num_consolidated=num_consolidated,
                   hot_pool_usage=hot_pool_usage,
                   q_neg_count=q_neg,
                   q_zero_count=q_zero,
                   q_pos_count=q_pos,
                   loss=loss,
                   gradient_norm=grad_norm,
                   stress_ema_mean=stress_mean,
                   stress_ema_std=stress_std,
                   residual_mean=residual_mean,
                   residual_std=residual_std,
                   residual_max=residual_max)
end

# Helper functions
mean(v::Vector{Float32}) = isempty(v) ? 0.0f0 : sum(v) / length(v)
std(v::Vector{Float32}) = isempty(v) ? 0.0f0 : sqrt(sum((x - mean(v))^2 for x in v) / length(v))
