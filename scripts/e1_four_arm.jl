# ---------------------------------------------------------------------------
# E1 — Four-arm comparison on an extended multi-task stream.
# PREREGISTERED BEFORE EXECUTION.
#
# Arms (identical Stage0MLP(2,32,2), feature_size=2, seed 71; identical head
# optimizer AdamConfig(learning_rate=0.02) everywhere; arms differ ONLY in the
# material branch):
#
#   ARM_SUB   — FP viscoplastic substrate: BinghamInspired(1e-5),
#               PHASE_MACHINE_CONTROLLER(2), RampedVPS(2; m_max=0.02),
#               conflict_k=2, region params (τ=0.2, η=1.0, settle=0.8,
#               hard=0.01, eps_δ=0.02, k_yield=2, k_settle=2).
#               Parameterization is FROZEN from the E0c′ grid: the grid point
#               with the highest positive return-trip asymmetry among
#               all-criteria-passing learners (+1.0637, mB=22/mA3=15). No
#               further tuning of this arm is permitted in E1.
#   ARM_C3    — frozen shadow-latent ternary + STE + Adam control
#               (DEFAULT_C3_SHADOW_ADAM, lr=1e-3). The frozen reference
#               control: its defaults are part of its contract and are not
#               tuned.
#   ARM_FP32  — conventional free FP32 material vector trained directly by
#               Adam. Because its lr is NOT frozen by any prior contract, it
#               is tuned in the arm's favor: lr_mat ∈
#               {0.001, 0.003, 0.01, 0.03, 0.1, 0.3} on the identical stream,
#               best-by-mean-phase-final-loss is used in the comparison and
#               reported. This is the anti-sandbagging protocol.
#   ARM_FIXED — controller ablation (spec §"gains surviving controller
#               ablations"): identical substrate/law/policy/ramp to ARM_SUB
#               but dcp = FIXED_RULE_CONTROLLER. Isolates the symbolic phase
#               machine's contribution from the constitutive machinery.
#
# Extended multi-task stream (8 phases x 150 ticks = 1200 ticks):
#   A -> B -> A -> C -> B -> A -> C -> A
#   X shared: [1 0 -1; 1 0 -1]; Y_A = [1 0 -1; -1 0 1]; Y_B = -Y_A;
#   Y_C = [1 0 -1; 1 0 -1]. All three task pairs are jointly unrealizable by
#   the linear-tanh head (same structural-conflict argument as E0b, extended:
#   A vs C disagree on y2 at x1 while agreeing on y1). Every task transition
#   is a structural conflict; no rest phases; the lifecycle is the only
#   additional non-stationarity.
#
# Metrics (per arm):
#   phase_final  — mean loss over the last 20 ticks of each phase, averaged
#                  over phases (adaptation quality under churn).
#   entry[k]     — loss at the first tick of phase k (pre-update).
#   ret_mean     — mean probe loss on ALL tasks sampled every 10 ticks
#                  (off-task probes only; retention under churn).
#   gain(task)   — PREREGISTERED METRIC CORRECTION (canary, before any arm
#                  comparison ran): the E0b asymmetry form
#                  (entry_first − entry_return) is broken here because task A
#                  runs FIRST: its entry[1] is the seed/chance loss, so every
#                  return looks catastrophically worse by construction
#                  (cold-start trap). Honest analog: baseline(task) = the
#                  task's FIRST entry occurring at phase >= 2 (i.e. from a
#                  trained, not seed, state); gains are baseline − entry for
#                  all subsequent entries of that task. Positive = repeated
#                  visits get cheaper = accumulated task-specific structure.
#   max_mid_jump — max |Δloss| between consecutive ticks inside phases.
#   hot_frac     — mean fraction of superplastic sites (substrate arms only).
#
# PREREGISTERED HYPOTHESES (v0.2 §2: strictly better adaptation-retention
# Pareto position vs matched conventional stacks, surviving controller
# ablation):
#   H1 adaptation: ARM_SUB phase_final <= min(ARM_C3, ARM_FP32_best).
#   H2 retention:  ARM_SUB ret_mean  <  min(ARM_C3, ARM_FP32_best).
#   H3 history:    ARM_SUB median return-gain > 0 for task A, and
#                  ARM_SUB asym(A) > ARM_FIXED asym(A) (the lifecycle, not
#                  raw gradient dynamics, produces the history effect).
#   H4 stability:  ARM_SUB max_mid_jump < 1.0.
#   H5 locality:   ARM_SUB hot_frac <= 0.5 (plasticity stays local while
#                  learning three conflicting tasks).
# Failure of any hypothesis is reported as a defect-ledger entry, not
# reinterpreted. The FP32 arm is EXPECTED to win single-phase adaptation
# (more expressive material); the claim under test is the multi-task
# Pareto position, not per-phase supremacy.
# ---------------------------------------------------------------------------

using PlasticWeights
using Statistics
using Printf

const X = Float32[1 0 -1; 1 0 -1]
const TASKS = (
    A = Float32[1 0 -1; -1 0 1],
    B = Float32[-1 0 1; 1 0 -1],
    C = Float32[1 0 -1; 1 0 -1],
)
const STREAM = (:A, :B, :A, :C, :B, :A, :C, :A)
const TICKS_PER_PHASE = 150

task_target(name::Symbol) = getfield(TASKS, name)

mse_loss(pred, Y) = 0.5f0 * sum(abs2, pred .- Y) / length(Y)

# ---------------------------------------------------------------------------
# Arm runners. Each returns a uniform result record.
# ---------------------------------------------------------------------------

function run_substrate_arm(; dcp=PHASE_MACHINE_CONTROLLER, label::Symbol=:sub)
    mlp = Stage0MLP(2, 32, 2; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)
    substrate = initialize_fp_seed(N;
        region_size=64,
        yield_up=0.2f0,
        settle_down=0.8f0,
        eta=1.0f0,
        hardening_increment=0.01f0,
        epsilon_delta=0.02f0,
        k_yield=2,
        k_settle=2,
        conflict_k=2,
    )
    state = initialize_material_training(mlp, substrate)
    config = MaterialTrainingConfig(
        law=BinghamInspired(Float32(1e-5)),
        dcp=dcp,
        policy=RampedVPS(2; m_max=0.02f0),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.5f0,
        gamma=0.5f0,
    )
    policy = config.policy

    T = length(STREAM) * TICKS_PER_PHASE
    losses = Float32[]
    hot_trace = Int[]
    probe_trace = Tuple{Int,Float32,Float32,Float32}[]  # (tick, lA, lB, lC)
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}() # (phase, entry loss)
    for name in (:A, :B, :C)
        entries[name] = Tuple{Int,Float32}[]
    end

    for tick in 1:T
        phase_idx = cld(tick, TICKS_PER_PHASE)
        task = STREAM[phase_idx]
        Y = task_target(task)

        result = material_training_step!(mlp, state, X, Y, config)

        if (tick - 1) % TICKS_PER_PHASE == 0
            push!(entries[task], (phase_idx, result.loss))
        end
        push!(losses, result.loss)
        push!(hot_trace, count(s -> s.allocated && s.superplastic, state.substrate.sites))

        if tick % 10 == 0
            lA = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.A)
            lB = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.B)
            lC = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.C)
            push!(probe_trace, (tick, lA, lB, lC))
        end
    end

    return _assemble_result(label, losses, entries, probe_trace, hot_trace)
end

function run_c3_arm(; label::Symbol=:c3)
    mlp = Stage0MLP(2, 32, 2; feature_size=2, rng_seed=71)
    state = initialize_c3_training(mlp)
    config = C3TrainingConfig(
        shadow=DEFAULT_C3_SHADOW_ADAM,
        head=AdamConfig(learning_rate=0.02f0),
    )

    T = length(STREAM) * TICKS_PER_PHASE
    losses = Float32[]
    hot_trace = Int[]
    probe_trace = Tuple{Int,Float32,Float32,Float32}[]
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in (:A, :B, :C)
        entries[name] = Tuple{Int,Float32}[]
    end

    for tick in 1:T
        phase_idx = cld(tick, TICKS_PER_PHASE)
        task = STREAM[phase_idx]
        Y = task_target(task)

        result = c3_training_step!(mlp, state, X, Y, config)

        if (tick - 1) % TICKS_PER_PHASE == 0
            push!(entries[task], (phase_idx, result.loss))
        end
        push!(losses, result.loss)

        if tick % 10 == 0
            lA = mse_loss(c3_predict(mlp, state, X), TASKS.A)
            lB = mse_loss(c3_predict(mlp, state, X), TASKS.B)
            lC = mse_loss(c3_predict(mlp, state, X), TASKS.C)
            push!(probe_trace, (tick, lA, lB, lC))
        end
    end

    return _assemble_result(label, losses, entries, probe_trace, hot_trace)
end

function run_fp32_arm(; lr_mat::Real=0.01f0, label::Symbol=:fp32)
    mlp = Stage0MLP(2, 32, 2; feature_size=2, rng_seed=71)
    N = num_material_sites(mlp)

    w = zeros(Float32, N)
    w_adam = initialize_adam_state(w)
    head_adam = initialize_adam_state(mlp.H_FP32)
    bias_adam = initialize_adam_state(mlp.output_bias)
    head_cfg = AdamConfig(learning_rate=0.02f0)
    mat_cfg = AdamConfig(learning_rate=lr_mat)

    T = length(STREAM) * TICKS_PER_PHASE
    losses = Float32[]
    hot_trace = Int[]
    probe_trace = Tuple{Int,Float32,Float32,Float32}[]
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in (:A, :B, :C)
        entries[name] = Tuple{Int,Float32}[]
    end

    for tick in 1:T
        phase_idx = cld(tick, TICKS_PER_PHASE)
        task = STREAM[phase_idx]
        Y = task_target(task)

        # Immutable pre-update snapshot consumed by forward/backward.
        exposures = copy(w)
        backward = backward_mse(mlp, X, exposures, Y)

        if (tick - 1) % TICKS_PER_PHASE == 0
            push!(entries[task], (phase_idx, backward.loss))
        end
        push!(losses, backward.loss)

        adam_step!(w, backward.grad_material, w_adam, mat_cfg)
        adam_step!(mlp.H_FP32, backward.grad_H, head_adam, head_cfg)
        adam_step!(mlp.output_bias, backward.grad_bias, bias_adam, head_cfg)

        if tick % 10 == 0
            lA = mse_loss(forward(mlp, X, copy(w)).y, TASKS.A)
            lB = mse_loss(forward(mlp, X, copy(w)).y, TASKS.B)
            lC = mse_loss(forward(mlp, X, copy(w)).y, TASKS.C)
            push!(probe_trace, (tick, lA, lB, lC))
        end
    end

    return _assemble_result(label, losses, entries, probe_trace, hot_trace)
end

function _assemble_result(label, losses, entries, probe_trace, hot_trace)
    # phase_final: mean loss over last 20 ticks of each phase, then averaged.
    phase_final = Float32[]
    for p in 1:length(STREAM)
        lo = (p - 1) * TICKS_PER_PHASE + TICKS_PER_PHASE - 19
        hi = p * TICKS_PER_PHASE
        push!(phase_final, mean(losses[lo:hi]))
    end

    # Off-task retention: mean over probes of the mean loss on the two
    # non-current tasks.
    rets = Float32[]
    for (tick, lA, lB, lC) in probe_trace
        phase_idx = cld(tick, TICKS_PER_PHASE)
        current = STREAM[phase_idx]
        vals = Float32[]
        current === :A || push!(vals, lA)
        current === :B || push!(vals, lB)
        current === :C || push!(vals, lC)
        push!(rets, mean(vals))
    end

    # Mid-phase jumps.
    max_mid = 0.0f0
    for t in 2:length(losses)
        (t - 1) % TICKS_PER_PHASE == 0 && continue
        max_mid = max(max_mid, abs(losses[t] - losses[t-1]))
    end

    # Return-trip gains (preregistered correction): baseline(task) is the
    # task's first POST-SEED entry (phase >= 2); gains are measured for every
    # later entry of that task. Positive = returns get cheaper.
    gains = Dict{Symbol,Vector{Float32}}()
    for name in (:A, :B, :C)
        e = entries[name]
        post_seed = filter(p -> p[1] >= 2, e)
        if length(post_seed) >= 2
            baseline = first(post_seed)[2]
            gains[name] = Float32[baseline - p[2] for p in post_seed[2:end]]
        else
            gains[name] = Float32[]
        end
    end

    return (
        label=label,
        phase_final=phase_final,
        mean_phase_final=mean(phase_final),
        entries=entries,
        ret_mean=mean(rets),
        ret_last=rets[end],
        max_mid_jump=max_mid,
        gains=gains,
        median_gain_A=isempty(gains[:A]) ? NaN32 : median(gains[:A]),
        median_gain_B=isempty(gains[:B]) ? NaN32 : median(gains[:B]),
        median_gain_C=isempty(gains[:C]) ? NaN32 : median(gains[:C]),
        hot_frac_mean=isempty(hot_trace) ? NaN32 : mean(hot_trace) / 64.0f0,
        hot_frac_end=isempty(hot_trace) ? NaN32 : hot_trace[end] / 64.0f0,
    )
end

function print_result(r)
    @printf("%-8s | phaseFinal=%7.4f retMean=%7.4f retLast=%7.4f | midJump=%6.3f | gainA=%+7.4f gainB=%+7.4f gainC=%+7.4f | hotMean=%5.2f hotEnd=%5.2f\n",
        r.label, r.mean_phase_final, r.ret_mean, r.ret_last, r.max_mid_jump,
        r.median_gain_A, r.median_gain_B, r.median_gain_C,
        r.hot_frac_mean, r.hot_frac_end)
    print("         entries: ")
    for name in (:A, :B, :C)
        e = r.entries[name]
        # (phase, loss) pairs: the phase tag matters for the gain baseline.
        print(name, "=[", join([@sprintf("p%d:%.3f", p, x) for (p, x) in e], ", "), "] ")
    end
    println()
end

function main()
    mode = isempty(ARGS) ? :full : Symbol(ARGS[1])

    println("="^110)
    println("E1 — four-arm comparison on extended multi-task stream (A→B→A→C→B→A→C→A), preregistered [mode=", mode, "]")
    println("="^110)

    if mode === :canary
        r = run_substrate_arm()
        print_result(r)
        return
    end

    results = []

    println("\n--- ARM_SUB (frozen E0c-prime parameterization) ---")
    r_sub = run_substrate_arm()
    print_result(r_sub)
    push!(results, r_sub)

    println("\n--- ARM_C3 (frozen shadow-ternary control) ---")
    r_c3 = run_c3_arm()
    print_result(r_c3)
    push!(results, r_c3)

    println("\n--- ARM_FP32 (material-lr sweep, best kept) ---")
    sweep = Float32[0.001, 0.003, 0.01, 0.03, 0.1, 0.3]
    best = nothing
    for lr in sweep
        r = run_fp32_arm(; lr_mat=lr)
        @printf("  lr=%6.3f phaseFinal=%7.4f retMean=%7.4f\n", lr, r.mean_phase_final, r.ret_mean)
        if best === nothing || r.mean_phase_final < best.mean_phase_final
            best = r
        end
    end
    best = merge(best, (label=:fp32,))
    print_result(best)
    push!(results, best)

    println("\n--- ARM_FIXED (controller ablation: substrate minus phase machine) ---")
    r_fix = run_substrate_arm(; dcp=FIXED_RULE_CONTROLLER, label=:fixed)
    print_result(r_fix)
    push!(results, r_fix)

    # -----------------------------------------------------------------------
    println("\n" * "="^110)
    println("PREREGISTERED HYPOTHESIS CHECKS")
    println("="^110)
    controls_best = min(r_c3.mean_phase_final, best.mean_phase_final)
    controls_ret = min(r_c3.ret_mean, best.ret_mean)

    @printf("H1 adaptation:  SUB %.4f %s min(C3 %.4f, FP32 %.4f) = %.4f  [%s]\n",
        r_sub.mean_phase_final, r_sub.mean_phase_final <= controls_best ? "<=" : "> ",
        r_c3.mean_phase_final, best.mean_phase_final, controls_best,
        r_sub.mean_phase_final <= controls_best ? "PASS" : "FAIL")
    @printf("H2 retention:   SUB %.4f %s min(C3 %.4f, FP32 %.4f) = %.4f  [%s]\n",
        r_sub.ret_mean, r_sub.ret_mean < controls_ret ? "< " : ">=",
        r_c3.ret_mean, best.ret_mean, controls_ret,
        r_sub.ret_mean < controls_ret ? "PASS" : "FAIL")
    @printf("H3 history:     SUB gainA=%+.4f [%s]; SUB vs FIXED: %+.4f vs %+.4f [%s]\n",
        r_sub.median_gain_A, r_sub.median_gain_A > 0 ? "PASS" : "FAIL",
        r_sub.median_gain_A, r_fix.median_gain_A,
        r_sub.median_gain_A > r_fix.median_gain_A ? "PASS" : "FAIL")
    @printf("H4 stability:   SUB midJump=%.4f  [%s]\n",
        r_sub.max_mid_jump, r_sub.max_mid_jump < 1.0f0 ? "PASS" : "FAIL")
    @printf("H5 locality:    SUB hotMean=%.3f  [%s]\n",
        r_sub.hot_frac_mean, r_sub.hot_frac_mean <= 0.5f0 ? "PASS" : "FAIL")

    println("\nController-ablation deltas (SUB − FIXED):")
    @printf("  phaseFinal %+.4f  retMean %+.4f  gainA %+.4f\n",
        r_sub.mean_phase_final - r_fix.mean_phase_final,
        r_sub.ret_mean - r_fix.ret_mean,
        r_sub.median_gain_A - r_fix.median_gain_A)
end

main()
