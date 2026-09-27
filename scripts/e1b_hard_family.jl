# ---------------------------------------------------------------------------
# E1b — Four-arm comparison on a HARD multi-task family.
# PREREGISTERED BEFORE EXECUTION.
#
# Addresses the two E1 defect-ledger entries:
#
#   E1-D1 (FP32 saturation): with 150-tick phases, the best FP32 arm reached
#   phaseFinal 0.0000 at EVERY learning rate — it fully re-solves within a
#   phase, so no adaptation/retention trade exists to observe. E1b hardens
#   the family along two axes:
#     (a) phase length 150 -> 40 ticks (a priori ~1/4 of E1's, chosen so the
#         re-solve budget is cut hard; the canary verifies phase 1 remains
#         learnable for the best FP32 arm — if phase-1 final > 0.15, phase
#         length is raised to 60 for ALL arms identically and recorded; this
#         is the only permitted adjustment);
#
#     PREREGISTERED AMENDMENT (canary result, recorded before the full run):
#     at 40 ticks the FP32 arm STILL saturates (phase-1 final 0.0014-0.0039
#     at every lr in the canary sweep) — the family is easy, not hard. The
#     permitted-adjustment clause only anticipated the opposite direction,
#     so this amendment extends the same lever in the measured direction:
#     phase length 40 -> 15 ticks for ALL arms identically (re-solve budget
#     ~10x below E1), probes every 5 ticks (3 per phase) so the retention
#     tercile band stays populated (10 probes). No other change. The canary
#     is rerun before the comparison; if FP32 phase-1 final is now inside
#     (0.05, 0.5] the family is valid per H1's intent (hard but learnable).
#     (b) four pairwise-conflicting tasks instead of three.
#   H1 preregisters family validity: best baseline mean phaseFinal > 0.05.
#
#   E1-D2 (retention confounded by current-task ceiling): retMean rewarded
#   arms that solve less and therefore forget less (C3 won by
#   under-training). E1b measures TER ACILE-MATCHED retention: for each arm,
#   off-task probe losses are averaged over the tercile of probe ticks with
#   the LOWEST current-task loss — i.e., "how much do you forget when you are
#   at your most on-task competent." Each arm is matched at its own best
#   operating point; the tercile's mean current-loss is reported for
#   transparency. Raw retMean is kept for the record.
#
# Task family (shared X = [1 0 -1; 1 0 -1], u = [1 0 -1]):
#   A: [u; -u]      B: [-u; u] = -A
#   C: [u;  u]      D: [-u; -u] = -C
#   Every pair conflicts on exactly one output row; the four tasks demand
#   four distinct output vectors at the same input (x=1), so the shared
#   linear-tanh head cannot realize them jointly (same structural argument
#   as E0b, extended). Stream (10 phases x 40 ticks = 400 ticks):
#       A B C D B A C D A B
#   Every task is visited >= 2x (A:3, B:3, C:2, D:2), so return-trip gains
#   are computable for all four.
#
# Arms (identical Stage0MLP(2,32,2) seed 71, head Adam lr=0.02 everywhere;
# arms differ only in the material branch):
#   SUB   — frozen E0c-prime parameterization (Bingham 1e-5, phase machine
#           k_commit=2, RampedVPS(2; m_max=0.02), tau=0.2, eta=1.0,
#           settle=0.8, hard=0.01, eps_delta=0.02, conflict_k=2). NO tuning.
#   C3    — shadow-ternary + STE + Adam. Frozen-contract row reported
#           (lr=1e-3) AND lr swept {0.001, 0.003, 0.01, 0.03} with the best
#           used in comparisons (anti-sandbagging, same as FP32 in E1).
#   FP32  — free FP32 material vector + Adam, lr swept
#           {0.001, 0.003, 0.01, 0.03, 0.1, 0.3}, best kept.
#   FIXED — controller ablation: SUB minus the phase machine
#           (FixedRuleController), identical everything else.
#
# PREREGISTERED HYPOTHESES:
#   H1 family validity: best-baseline mean phaseFinal > 0.05 (the family is
#      hard; FP32 cannot re-solve within a phase). Validity check, not an
#      arm claim.
#   H2 Pareto (the v0.2 thesis claim, operationalized): SUB is non-dominated
#      on the (mean phaseFinal, tercile-matched retention) plane — no single
#      baseline has BOTH lower phaseFinal AND lower retMatched than SUB.
#   H3 history: SUB return-gain > 0 for >= 2 of 4 tasks, and SUB's mean
#      task-gain > FIXED's mean task-gain (lifecycle attribution).
#   H4 stability: SUB max mid-phase jump < 1.0.
#   H5 locality: SUB hotMean <= 0.5.
# Failures are ledgered, not reinterpreted.
# ---------------------------------------------------------------------------

using PlasticWeights
using Statistics
using Printf

const X = Float32[1 0 -1; 1 0 -1]
const U = Float32[1 0 -1]
const TASKS = (
    A = Float32[1 0 -1; -1 0 1],
    B = Float32[-1 0 1; 1 0 -1],
    C = Float32[1 0 -1; 1 0 -1],
    D = Float32[-1 0 -1; -1 0 1],
)
const STREAM = (:A, :B, :C, :D, :B, :A, :C, :D, :A, :B)
const TICKS_PER_PHASE = 15   # Amendment: 40 -> 15 (see header)
const PROBE_EVERY = 5        # Amendment: 10 -> 5 (3 probes per phase)
const N_TASKS = 4

task_target(name::Symbol) = getfield(TASKS, name)
mse_loss(pred, Y) = 0.5f0 * sum(abs2, pred .- Y) / length(Y)

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
    probe4 = Tuple{Int,Int,NTuple{4,Float32}}[]  # (tick, phase, (lA,lB,lC,lD))
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in (:A, :B, :C, :D)
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

        if tick % PROBE_EVERY == 0
            lA = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.A)
            lB = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.B)
            lC = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.C)
            lD = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.D)
            push!(probe4, (tick, phase_idx, (lA, lB, lC, lD)))
        end
    end

    return _assemble_result(label, losses, entries, probe4, hot_trace)
end

function run_c3_arm(; lr_shadow::Real=1.0f-3, label::Symbol=:c3)
    mlp = Stage0MLP(2, 32, 2; feature_size=2, rng_seed=71)
    state = initialize_c3_training(mlp)
    config = C3TrainingConfig(
        shadow=C3ShadowAdamConfig(learning_rate=lr_shadow),
        head=AdamConfig(learning_rate=0.02f0),
    )

    T = length(STREAM) * TICKS_PER_PHASE
    losses = Float32[]
    hot_trace = Int[]
    probe4 = Tuple{Int,Int,NTuple{4,Float32}}[]
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in (:A, :B, :C, :D)
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

        if tick % PROBE_EVERY == 0
            lA = mse_loss(c3_predict(mlp, state, X), TASKS.A)
            lB = mse_loss(c3_predict(mlp, state, X), TASKS.B)
            lC = mse_loss(c3_predict(mlp, state, X), TASKS.C)
            lD = mse_loss(c3_predict(mlp, state, X), TASKS.D)
            push!(probe4, (tick, phase_idx, (lA, lB, lC, lD)))
        end
    end

    return _assemble_result(label, losses, entries, probe4, hot_trace)
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
    probe4 = Tuple{Int,Int,NTuple{4,Float32}}[]
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in (:A, :B, :C, :D)
        entries[name] = Tuple{Int,Float32}[]
    end

    task_index = Dict(:A => 1, :B => 2, :C => 3, :D => 4)

    for tick in 1:T
        phase_idx = cld(tick, TICKS_PER_PHASE)
        task = STREAM[phase_idx]
        Y = task_target(task)

        exposures = copy(w)
        backward = backward_mse(mlp, X, exposures, Y)

        if (tick - 1) % TICKS_PER_PHASE == 0
            push!(entries[task], (phase_idx, backward.loss))
        end
        push!(losses, backward.loss)

        adam_step!(w, backward.grad_material, w_adam, mat_cfg)
        adam_step!(mlp.H_FP32, backward.grad_H, head_adam, head_cfg)
        adam_step!(mlp.output_bias, backward.grad_bias, bias_adam, head_cfg)

        if tick % PROBE_EVERY == 0
            wv = copy(w)
            lA = mse_loss(forward(mlp, X, wv).y, TASKS.A)
            lB = mse_loss(forward(mlp, X, wv).y, TASKS.B)
            lC = mse_loss(forward(mlp, X, wv).y, TASKS.C)
            lD = mse_loss(forward(mlp, X, wv).y, TASKS.D)
            push!(probe4, (tick, phase_idx, (lA, lB, lC, lD)))
        end
    end

    return _assemble_result(label, losses, entries, probe4, hot_trace)
end

const TASK_ORDER = (:A, :B, :C, :D)

function _assemble_result(label, losses, entries, probe4, hot_trace)
    n_phases = length(STREAM)

    phase_final = Float32[]
    for p in 1:n_phases
        lo = (p - 1) * TICKS_PER_PHASE + TICKS_PER_PHASE - 9
        hi = p * TICKS_PER_PHASE
        push!(phase_final, mean(losses[lo:hi]))
    end

    # Tercile-matched retention: probes sorted by CURRENT-task loss; the
    # lowest tercile is the arm's "at its best" operating band; retMatched is
    # the mean OFF-task loss over those probes.
    # The loss tuple is indexed by TASK (A,B,C,D -> 1,2,3,4); the probe's
    # second field is the PHASE number, so map phase -> task -> index.
    task_index = Dict(:A => 1, :B => 2, :C => 3, :D => 4)
    current_loss(p) = p[3][task_index[STREAM[p[2]]]]
    ordered = sort(probe4; by=current_loss)
    n_band = max(1, length(ordered) ÷ 3)
    band = ordered[1:n_band]
    ret_matched = Float32[]
    for (tick, phase_idx, ls) in band
        cur = STREAM[phase_idx]
        vals = Float32[]
        for (ti, name) in enumerate(TASK_ORDER)
            name === cur || push!(vals, ls[ti])
        end
        push!(ret_matched, mean(vals))
    end
    band_current = mean(current_loss(p) for p in band)

    # Raw retention (all probes, off-task mean) for the record.
    ret_raw = Float32[]
    for (tick, phase_idx, ls) in probe4
        cur = STREAM[phase_idx]
        vals = Float32[]
        for (ti, name) in enumerate(TASK_ORDER)
            name === cur || push!(vals, ls[ti])
        end
        push!(ret_raw, mean(vals))
    end

    max_mid = 0.0f0
    for t in 2:length(losses)
        (t - 1) % TICKS_PER_PHASE == 0 && continue
        max_mid = max(max_mid, abs(losses[t] - losses[t-1]))
    end

    # Return-trip gains: baseline = task's first POST-SEED entry (phase >= 2);
    # gains on later entries (correction preregistered in E1).
    gains = Dict{Symbol,Vector{Float32}}()
    for name in TASK_ORDER
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
        ret_matched=mean(ret_matched),
        band_current=band_current,
        ret_raw=mean(ret_raw),
        max_mid_jump=max_mid,
        gains=gains,
        task_gain=Dict{Symbol,Float32}(
            name => isempty(gains[name]) ? NaN32 : mean(gains[name])
            for name in TASK_ORDER),
        mean_task_gain=mean(values(Dict{Symbol,Float32}(
            name => isempty(gains[name]) ? 0.0f0 : mean(gains[name])
            for name in TASK_ORDER))),
        hot_frac_mean=isempty(hot_trace) ? NaN32 : mean(hot_trace) / 64.0f0,
        hot_frac_end=isempty(hot_trace) ? NaN32 : hot_trace[end] / 64.0f0,
    )
end

function print_result(r)
    @printf("%-8s | phaseFinal=%7.4f retMatched=%7.4f (band %6.4f) retRaw=%7.4f | midJump=%6.3f | hotMean=%5.2f hotEnd=%4.2f\n",
        r.label, r.mean_phase_final, r.ret_matched, r.band_current, r.ret_raw,
        r.max_mid_jump, r.hot_frac_mean, r.hot_frac_end)
    print("         gains:   ")
    for name in TASK_ORDER
        @printf("%s=%+7.4f  ", name, r.task_gain[name])
    end
    @printf("mean=%+7.4f\n", r.mean_task_gain)
    print("         entries: ")
    for name in TASK_ORDER
        e = r.entries[name]
        print(name, "=[", join([@sprintf("p%d:%.3f", p, x) for (p, x) in e], ", "), "] ")
    end
    println()
end

function main()
    mode = isempty(ARGS) ? :full : Symbol(ARGS[1])

    println("="^110)
    println("E1b — four-arm comparison on HARD family (4 tasks, 40-tick phases, A→B→C→D→B→A→C→D→A→B), preregistered [mode=", mode, "]")
    println("="^110)

    if mode === :canary
        # Family-validity probe: FP32 sweep; phase-1 finals and overall.
        for lr in (0.003f0, 0.01f0, 0.03f0, 0.1f0)
            r = run_fp32_arm(; lr_mat=lr)
            @printf("canary fp32 lr=%5.3f: phase1Final=%7.4f overall=%7.4f\n",
                lr, r.phase_final[1], r.mean_phase_final)
        end
        return
    end

    println("\n--- ARM_SUB (frozen E0c-prime parameterization) ---")
    r_sub = run_substrate_arm()
    print_result(r_sub)

    println("\n--- ARM_C3 (shadow-ternary control; frozen row + sweep) ---")
    r_c3_frozen = run_c3_arm(; lr_shadow=1.0f-3, label=:c3)
    @printf("  frozen lr=0.0010: phaseFinal=%7.4f retMatched=%7.4f\n",
        r_c3_frozen.mean_phase_final, r_c3_frozen.ret_matched)
    best_c3 = r_c3_frozen
    for lr in (0.003f0, 0.01f0, 0.03f0)
        r = run_c3_arm(; lr_shadow=lr)
        @printf("  swept  lr=%5.3f: phaseFinal=%7.4f retMatched=%7.4f\n", lr, r.mean_phase_final, r.ret_matched)
        if r.mean_phase_final < best_c3.mean_phase_final
            best_c3 = merge(r, (label=:c3,))
        end
    end
    println("  best C3:")
    print_result(best_c3)

    println("\n--- ARM_FP32 (material-lr sweep, best kept) ---")
    best_fp = nothing
    for lr in (0.001f0, 0.003f0, 0.01f0, 0.03f0, 0.1f0, 0.3f0)
        r = run_fp32_arm(; lr_mat=lr)
        @printf("  lr=%5.3f phaseFinal=%7.4f retMatched=%7.4f\n", lr, r.mean_phase_final, r.ret_matched)
        if best_fp === nothing || r.mean_phase_final < best_fp.mean_phase_final
            best_fp = r
        end
    end
    best_fp = merge(best_fp, (label=:fp32,))
    print_result(best_fp)

    println("\n--- ARM_FIXED (controller ablation: substrate minus phase machine) ---")
    r_fix = run_substrate_arm(; dcp=FIXED_RULE_CONTROLLER, label=:fixed)
    print_result(r_fix)

    # -----------------------------------------------------------------------
    println("\n" * "="^110)
    println("PREREGISTERED HYPOTHESIS CHECKS")
    println("="^110)

    baselines = (best_c3, best_fp, r_fix)

    # H1 — family validity.
    best_base_pf = minimum(r.mean_phase_final for r in baselines)
    @printf("H1 validity:    best baseline phaseFinal = %.4f  [%s]\n",
        best_base_pf, best_base_pf > 0.05f0 ? "PASS (>0.05: family is hard)" : "FAIL (saturated again)")

    # H2 — Pareto non-domination on (phaseFinal, retMatched).
    dominates(r) = r.mean_phase_final < r_sub.mean_phase_final &&
                   r.ret_matched < r_sub.ret_matched
    dominators = filter(dominates, baselines)
    @printf("H2 pareto:      SUB (pf=%.4f, retM=%.4f); dominators: %s  [%s]\n",
        r_sub.mean_phase_final, r_sub.ret_matched,
        isempty(dominators) ? "none" : join([String(r.label) for r in dominators], ","),
        isempty(dominators) ? "PASS" : "FAIL")

    # H3 — history.
    n_pos = count(r_sub.task_gain[name] > 0 for name in TASK_ORDER)
    @printf("H3 history:     SUB gains>0 on %d/4 tasks (%s); SUB mean %+.4f vs FIXED %+.4f  [%s]\n",
        n_pos, join([@sprintf("%s%+.3f", name, r_sub.task_gain[name]) for name in TASK_ORDER], " "),
        r_sub.mean_task_gain, r_fix.mean_task_gain,
        (n_pos >= 2 && r_sub.mean_task_gain > r_fix.mean_task_gain) ? "PASS" : "FAIL")

    # H4 — stability.
    @printf("H4 stability:   SUB midJump=%.4f  [%s]\n",
        r_sub.max_mid_jump, r_sub.max_mid_jump < 1.0f0 ? "PASS" : "FAIL")

    # H5 — locality.
    @printf("H5 locality:    SUB hotMean=%.3f  [%s]\n",
        r_sub.hot_frac_mean, r_sub.hot_frac_mean <= 0.5f0 ? "PASS" : "FAIL")

    println("\nController-ablation deltas (SUB − FIXED):")
    @printf("  phaseFinal %+.4f  retMatched %+.4f  meanGain %+.4f\n",
        r_sub.mean_phase_final - r_fix.mean_phase_final,
        r_sub.ret_matched - r_fix.ret_matched,
        r_sub.mean_task_gain - r_fix.mean_task_gain)
end

main()
