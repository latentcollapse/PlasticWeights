using PlasticWeights

# ---------------------------------------------------------------------------
# PlasticWeights Stage-0 exploratory probe
#
# Goal:
#   Observe whether the *actual* Bingham-inspired material arm can wake and
#   learn end-to-end from the normative all-superplastic ZCS seed.
#
# This is deliberately NOT a regression test and NOT a preregistered result.
# It is a diagnostic instrument. We calibrate the material scale from the
# frozen seed gradient, print the calibration, and then run three trajectories:
#
#   1. Newtonian / continuous task pressure
#   2. Bingham-inspired / continuous task pressure
#   3. Bingham-inspired / load-rest cycles
#
# Arms 1 and 2 differ only in constitutive law. Arm 3 is a liveness diagnostic:
# it asks whether explicit low-stress intervals permit a Bingham-plastic region
# to settle and expose a committed ternary phenotype.
# ---------------------------------------------------------------------------

const PROBE_SEED = 71
const DEFAULT_TICKS = 120

const ACTIVE_X = Float32[
    1 -1
    1 -1
]

const ACTIVE_Y = Float32[
    1 -1
]

const REST_X = zeros(Float32, 2, 2)
const REST_Y = zeros(Float32, 1, 2)

function probe_loss(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
    X::AbstractMatrix{<:Real}=ACTIVE_X,
    Y::AbstractMatrix{<:Real}=ACTIVE_Y,
)
    prediction = material_predict(mlp, state, X, ZCS())
    return 0.5f0 * sum(abs2, prediction .- Y) / length(Y)
end

function seed_gradient_calibration(mlp::Stage0MLP)
    exposures = zeros(Float32, num_material_sites(mlp))
    backward = backward_mse(mlp, ACTIVE_X, exposures, ACTIVE_Y)

    magnitudes = sort!(
        Float32[
            abs(Float32(g))
            for g in backward.grad_material
            if !iszero(g)
        ],
    )

    isempty(magnitudes) &&
        error("ProbeFailure: seed material gradient is identically zero")

    n = length(magnitudes)
    q50 = magnitudes[clamp(cld(n, 2), 1, n)]
    q90 = magnitudes[clamp(ceil(Int, 0.90 * n), 1, n)]
    gmax = last(magnitudes)

    # Exploratory scale calibration, not a proposed training recipe.
    #
    # yield_up is placed below the median nonzero seed gradient so that the
    # first tick contains both mobile and immobile sites.
    #
    # eta is tied to the upper gradient scale so the largest Bingham updates
    # are O(0.1–1), large enough to cross a ternary threshold in a small number
    # of active ticks without an arbitrary absolute learning-rate guess.
    yield_up = max(0.25f0 * q50, 1.0f-8)
    settle_down = 0.50f0 * yield_up
    eta = max(2.0f0 * q90, 1.0f-8)

    # Keep mandatory work-hardening real but modest for this liveness probe.
    # If every site in the 64-site region commits once, total hardening is only
    # one quarter of the initial yield threshold.
    hardening_increment = max(yield_up / 256.0f0, 1.0f-10)

    # Residual-motion threshold is expressed in Δδ units. Given eta above,
    # active updates can be O(0.1), while zero-gradient rest ticks decay the
    # motion EMA rapidly with gamma=0.5.
    epsilon_delta = 0.02f0

    bingham_epsilon = max(0.01f0 * yield_up, 1.0f-10)

    return (
        q50=q50,
        q90=q90,
        gmax=gmax,
        yield_up=yield_up,
        settle_down=settle_down,
        eta=eta,
        hardening_increment=hardening_increment,
        epsilon_delta=epsilon_delta,
        bingham_epsilon=bingham_epsilon,
    )
end

function make_state(
    mlp::Stage0MLP,
    calibration,
)
    return initialize_material_training(
        mlp;
        region_size=64,
        yield_up=calibration.yield_up,
        settle_down=calibration.settle_down,
        eta=calibration.eta,
        hardening_increment=calibration.hardening_increment,
        epsilon_delta=calibration.epsilon_delta,
        k_yield=2,
        k_settle=2,
    )
end

function make_config(law::ConstitutiveLaw)
    return MaterialTrainingConfig(
        law=law,
        dcp=FIXED_RULE_CONTROLLER,
        policy=ZCS(),
        head=AdamConfig(
            learning_rate=0.02f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        beta=0.5f0,
        gamma=0.5f0,
    )
end

function active_schedule(::Int)
    return (ACTIVE_X, ACTIVE_Y, true)
end

function load_rest_schedule(tick::Int)
    # Six active ticks followed by eighteen zero-gradient rest ticks.
    # This is intentionally a diagnostic developmental "sleep" rhythm, not a
    # candidate benchmark protocol.
    phase = mod1(tick, 24)
    if phase <= 6
        return (ACTIVE_X, ACTIVE_Y, true)
    end
    return (REST_X, REST_Y, false)
end

function arm_snapshot(state::MaterialTrainingState)
    visible = exposure_snapshot(state.substrate.sites, ZCS())
    nonzero_q = count(x -> !iszero(x), visible)
    plastic = count(site -> site.allocated && site.superplastic,
        state.substrate.sites)

    mean_stress =
        sum(Float64(t.stress_ema) for t in state.substrate.telemetry) /
        length(state.substrate.telemetry)

    region = state.substrate.region_map.regions[1]

    return (
        nonzero_q=nonzero_q,
        plastic=plastic,
        mean_stress=mean_stress,
        yield_up=Float64(region.yield_up),
    )
end

function print_tick(
    name,
    tick,
    active,
    eval_loss,
    snap,
    summary,
    max_abs_delta,
    commit_delta,
    melt_delta,
)
    phase = active ? "load" : "rest"
    println(
        rpad(name, 20),
        " t=", lpad(tick, 3),
        " ", rpad(phase, 4),
        "  loss=", round(eval_loss; digits=6),
        "  q≠0=", lpad(snap.nonzero_q, 2),
        "  ★=", lpad(snap.plastic, 2),
        "  σ̄=", round(snap.mean_stress; digits=6),
        "  τ=", round(snap.yield_up; digits=6),
        "  |Δδ|max=", round(max_abs_delta; digits=6),
        "  +C=", commit_delta,
        "  +M=", melt_delta,
        "  wake=", summary.wake_tick,
    )
end

function run_arm(
    name::String,
    base_mlp::Stage0MLP,
    calibration,
    law::ConstitutiveLaw,
    schedule::Function,
    ticks::Int,
)
    mlp = deepcopy(base_mlp)
    state = make_state(mlp, calibration)
    recorder = DevelopmentalRecorder()
    config = make_config(law)

    initial_loss = Float64(probe_loss(mlp, state))
    best_loss = initial_loss
    best_tick = 0
    max_nonzero_q = 0
    max_abs_delta_seen = 0.0
    active_steps = 0

    previous_commits = 0
    previous_melts = 0

    println()
    println("================================================================")
    println(name)
    println("================================================================")
    println("initial active-task loss = ", initial_loss)

    for tick in 1:ticks
        X, Y, active = schedule(tick)
        active && (active_steps += 1)

        result = material_training_step!(
            mlp,
            state,
            X,
            Y,
            config;
            recorder=recorder,
        )

        eval_loss = Float64(probe_loss(mlp, state))
        if eval_loss < best_loss
            best_loss = eval_loss
            best_tick = tick
        end

        snap = arm_snapshot(state)
        max_nonzero_q = max(max_nonzero_q, snap.nonzero_q)

        tick_max_delta =
            isempty(result.delta_updates) ?
            0.0 :
            maximum(abs, result.delta_updates)
        max_abs_delta_seen = max(max_abs_delta_seen, Float64(tick_max_delta))

        summary = summarize_events(recorder)
        commit_delta = summary.commit_count - previous_commits
        melt_delta = summary.melt_count - previous_melts

        interesting =
            tick <= 3 ||
            tick % 10 == 0 ||
            commit_delta != 0 ||
            melt_delta != 0 ||
            summary.wake_tick == tick ||
            summary.credit_unlock_tick == tick

        interesting && print_tick(
            name,
            tick,
            active,
            eval_loss,
            snap,
            summary,
            Float64(tick_max_delta),
            commit_delta,
            melt_delta,
        )

        previous_commits = summary.commit_count
        previous_melts = summary.melt_count
    end

    final_loss = Float64(probe_loss(mlp, state))
    summary = summarize_events(recorder)
    final_snap = arm_snapshot(state)

    status =
        summary.first_delta_tick === nothing ? :no_deformation :
        summary.wake_tick === nothing ? :deforms_but_never_wakes :
        best_loss < 0.25 * initial_loss ? :learned :
        :woke_but_not_yet_learned

    println()
    println("SUMMARY — ", name)
    println("  status                    = ", status)
    println("  active training steps     = ", active_steps)
    println("  initial loss              = ", initial_loss)
    println("  best loss                 = ", best_loss, " @ tick ", best_tick)
    println("  final loss                = ", final_loss)
    println("  max visible q≠0           = ", max_nonzero_q)
    println("  final visible q≠0         = ", final_snap.nonzero_q)
    println("  final superplastic sites  = ", final_snap.plastic)
    println("  max |Δδ| seen             = ", max_abs_delta_seen)
    println("  commits                   = ", summary.commit_count)
    println("  melts                     = ", summary.melt_count)
    println("  nonzero-prior remelts     = ", summary.nonzero_prior_remelts)
    println("  commit flips              = ", summary.commit_flip_count)
    println("  total hardening           = ", summary.total_hardening)
    println("  first Δδ tick             = ", summary.first_delta_tick)
    println("  phenotypic wake tick      = ", summary.wake_tick)
    println("  credit unlock tick        = ", summary.credit_unlock_tick)
    println("  final region yield        = ", final_snap.yield_up)

    check_invariants(state, mlp)

    return (
        name=name,
        status=status,
        initial_loss=initial_loss,
        best_loss=best_loss,
        best_tick=best_tick,
        final_loss=final_loss,
        max_nonzero_q=max_nonzero_q,
        active_steps=active_steps,
        summary=summary,
        final_snapshot=final_snap,
    )
end

function main()
    ticks = isempty(ARGS) ? DEFAULT_TICKS : parse(Int, first(ARGS))
    ticks >= 1 || error("ProbeFailure: tick count must be positive")

    base_mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=PROBE_SEED,
    )

    num_material_sites(base_mlp) == 64 ||
        error("ProbeFailure: expected exactly one 64-site Stage-0 region")

    calibration = seed_gradient_calibration(base_mlp)

    println("PlasticWeights — Bingham end-to-end liveness probe")
    println("EXPLORATORY ONLY: this script is instrumentation, not benchmark evidence.")
    println()
    println("Frozen seed-gradient scale:")
    println("  median nonzero |g|        = ", calibration.q50)
    println("  90th percentile |g|      = ", calibration.q90)
    println("  max |g|                  = ", calibration.gmax)
    println()
    println("Probe material parameters:")
    println("  yield_up                 = ", calibration.yield_up)
    println("  settle_down              = ", calibration.settle_down)
    println("  eta                      = ", calibration.eta)
    println("  hardening_increment      = ", calibration.hardening_increment)
    println("  epsilon_delta            = ", calibration.epsilon_delta)
    println("  Bingham epsilon          = ", calibration.bingham_epsilon)
    println("  beta / gamma             = 0.5 / 0.5")
    println("  k_yield / k_settle       = 2 / 2")

    newtonian = run_arm(
        "Newtonian continuous",
        base_mlp,
        calibration,
        NEWTONIAN,
        active_schedule,
        ticks,
    )

    bingham = run_arm(
        "Bingham continuous",
        base_mlp,
        calibration,
        BinghamInspired(calibration.bingham_epsilon),
        active_schedule,
        ticks,
    )

    bingham_rest = run_arm(
        "Bingham load/rest",
        base_mlp,
        calibration,
        BinghamInspired(calibration.bingham_epsilon),
        load_rest_schedule,
        ticks,
    )

    println()
    println("================================================================")
    println("COMPARATIVE DIAGNOSTIC")
    println("================================================================")
    for result in (newtonian, bingham, bingham_rest)
        println(
            rpad(result.name, 20),
            "  status=", rpad(string(result.status), 28),
            "  best_loss=", round(result.best_loss; digits=6),
            "  wake=", result.summary.wake_tick,
            "  credit=", result.summary.credit_unlock_tick,
            "  commits=", result.summary.commit_count,
            "  melts=", result.summary.melt_count,
            "  max_q≠0=", result.max_nonzero_q,
        )
    end

    println()
    println("Interpretation guide:")
    println("  • Bingham continuous wakes:")
    println("      The constitutive+DCP+hardening loop is end-to-end live under")
    println("      stationary pressure. Next step is a regression test.")
    println("  • Bingham continuous deforms but never wakes, load/rest wakes:")
    println("      The current ZCS+Bingham lifecycle requires pressure relief to")
    println("      expose accumulated latent evidence. That is a real architectural")
    println("      result worth understanding before changing anything.")
    println("  • Neither Bingham arm wakes:")
    println("      Do NOT tune blindly. Inspect stress, mobility, δ, and commit")
    println("      conditions; the probe has isolated a liveness failure.")
    println("  • Bingham wakes but loss does not improve:")
    println("      Lifecycle works; representation/optimization after wake is the")
    println("      next thing to isolate.")
end

main()
