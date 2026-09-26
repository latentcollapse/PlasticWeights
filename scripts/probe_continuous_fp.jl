using PlasticWeights
using Statistics
using Printf

# ---------------------------------------------------------------------------
# Continuous FP Viscoplasticity Probe
#
# Comparing continuous floating-point consolidation against the ternary arm
# on the exact same load-rest developmental schedule.
# ---------------------------------------------------------------------------

const ACTIVE_X = Float32[
    1 -1
    1 -1
]

const ACTIVE_Y = Float32[
    1 -1
]

const REST_X = zeros(Float32, 2, 2)
const REST_Y = zeros(Float32, 1, 2)

function load_rest_schedule(tick::Int)
    phase = mod1(tick, 24)
    if phase <= 6
        return (ACTIVE_X, ACTIVE_Y, true)
    end
    return (REST_X, REST_Y, false)
end

function run_continuous_probe(; ticks=120)
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    # Initial continuous weights (small random or zero seed)
    substrate = initialize_fp_seed(N;
        region_size=64,
        yield_up=0.05f0,
        settle_down=0.025f0,
        eta=0.5f0,
        hardening_increment=0.001f0,
        epsilon_delta=0.02f0,
        k_yield=2,
        k_settle=2,
    )

    state = initialize_material_training(mlp, substrate)
    recorder = DevelopmentalRecorder()

    config = MaterialTrainingConfig(
        law=BinghamInspired(1.0f-5),
        dcp=FIXED_RULE_CONTROLLER,
        policy=VPS(),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.5f0,
        gamma=0.5f0,
    )

    initial_loss = 0.5f0 * sum(abs2, material_predict(mlp, state, ACTIVE_X, VPS()) .- ACTIVE_Y) / length(ACTIVE_Y)
    println(@sprintf("Initial active-task loss = %.6f", initial_loss))

    best_loss = initial_loss
    best_tick = 0

    for tick in 1:ticks
        X, Y, is_active = load_rest_schedule(tick)
        res = material_training_step!(mlp, state, X, Y, config; recorder=recorder)

        eval_pred = material_predict(mlp, state, ACTIVE_X, VPS())
        eval_loss = 0.5f0 * sum(abs2, eval_pred .- ACTIVE_Y) / length(ACTIVE_Y)

        if eval_loss < best_loss
            best_loss = eval_loss
            best_tick = tick
        end

        plastic = count(s -> s.allocated && s.superplastic, state.substrate.sites)
        region = state.substrate.region_map.regions[1]

        if tick in (1, 2, 5, 6, 8, 10, 12, 24, 25, 30, 36, 48, 60, 72, 96, 120)
            phase = is_active ? "load" : "rest"
            println(@sprintf("t=%3d %4s  eval_loss=%.6f  ★=%2d  τ=%.5f  melts=%2d  commits=%2d",
                tick, phase, eval_loss, plastic, region.yield_up,
                melt_count(recorder.events), commit_count(recorder.events)))
        end
    end

    eval_final = 0.5f0 * sum(abs2, material_predict(mlp, state, ACTIVE_X, VPS()) .- ACTIVE_Y) / length(ACTIVE_Y)
    summary = summarize_events(recorder)

    println("\n================================================================")
    println("SUMMARY — Continuous FP Viscoplasticity (Bingham VPS)")
    println("================================================================")
    println(@sprintf("  initial loss          = %.6f", initial_loss))
    println(@sprintf("  best loss             = %.6f @ tick %d", best_loss, best_tick))
    println(@sprintf("  final loss            = %.6f", eval_final))
    println(@sprintf("  total commits         = %d", summary.commit_count))
    println(@sprintf("  total melts           = %d", summary.melt_count))
    println(@sprintf("  total hardening       = %.6f", summary.total_hardening))
    println(@sprintf("  final region yield    = %.5f", state.substrate.region_map.regions[1].yield_up))
    println("================================================================")

    return (initial=initial_loss, best=best_loss, final=eval_final, summary=summary)
end

run_continuous_probe()
