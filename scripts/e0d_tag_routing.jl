# ---------------------------------------------------------------------------
# E0d — Pass 3: consolidation-tag routing. PREREGISTERED BEFORE EXECUTION.
#
# Targets E1c-D6 (history = consolidation-memory; gain window L >= 75) and
# E1c-D5 (the certificate is a backstop; churn carries gains). The E0c/E1
# lineage already contains an IMPLICIT routing fact: the phase machine's
# committed-side melt fires only via the direction-sensitive conflict
# certificate, so tag-aligned material is protected forever while opposed
# material is invalidated. E0d asks whether that implicit routing is CAUSAL
# (R3) and whether making it EXPLICIT (commit-side dwell remission for
# tag-aligned melts) extends the gain window (R1/R2).
#
# Arms (identical MLP seed 71, head Adam lr=0.02; only the lifecycle varies):
#   PHASE — PhaseMachineController (baseline: Pass-2 machine, no remission)
#   TAGR  — TagRoutingController: melted sites whose TAG AGREES with current
#           load commit on the first certified settle tick (dwell remitted)
#   UNDIR — UndirectedController: direction-BLIND certificate (ablation —
#           same thresholds, no tag direction). Isolates the tag's role.
#   FIXED — FixedRuleController (substrate, no machine; floor control)
#
# Grid: L ∈ {15, 40, 75, 150} on the E1b/E1c four-task family and stream
# (identical protocol, so every E1c row doubles as the PHASE row's replicate).
#
# PREREGISTERED RESULTS:
#   R1 (window extension): TAGR meanGain at L=40 > PHASE meanGain at L=40
#      AND TAGR(40) > 0. (E1c showed the window opens between 40 and 75; if
#      routing carries memory explicitly, TAGR should open it one grid step
#      early.)
#   R2 (monotone dose): TAGR meanGain > PHASE meanGain at EVERY L (remission
#      never hurts: it only fast-tracks previously-validated material).
#   R3 (causality): PHASE meanGain > UNDIR meanGain at L=150 (where the
#      effect is largest). If UNDIR ~ PHASE, the tag's direction condition
#      is NOT the carrier and the implicit-routing story dies.
#   R4 (invalidation invariance): TAGR melts_total ≈ PHASE melts_total at
#      every L (within 10%) — routing touches only the commit side.
# Failures are ledgered, not reinterpreted.
# ---------------------------------------------------------------------------

using PlasticWeights
using Statistics
using Printf

const X = Float32[1 0 -1; 1 0 -1]
const TASKS = (
    A = Float32[1 0 -1; -1 0 1],
    B = Float32[-1 0 1; 1 0 -1],
    C = Float32[1 0 -1; 1 0 -1],
    D = Float32[-1 0 -1; -1 0 1],
)
const STREAM = (:A, :B, :C, :D, :B, :A, :C, :D, :A, :B)
const TASK_ORDER = (:A, :B, :C, :D)
const L_GRID = (15, 40, 75, 150)
const PROBE_EVERY = 5

task_target(name::Symbol) = getfield(TASKS, name)
mse_loss(pred, Y) = 0.5f0 * sum(abs2, pred .- Y) / length(Y)

function run_arm(dcp; L::Int, label::Symbol)
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

    n_phases = length(STREAM)
    T = n_phases * L
    losses = Float32[]
    hot_trace = Int[]
    probe4 = Tuple{Int,Int,NTuple{4,Float32}}[]
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in TASK_ORDER
        entries[name] = Tuple{Int,Float32}[]
    end
    commits_total = 0
    melts_total = 0

    for tick in 1:T
        phase_idx = cld(tick, L)
        task = STREAM[phase_idx]
        Y = task_target(task)

        result = material_training_step!(mlp, state, X, Y, config)

        if (tick - 1) % L == 0
            push!(entries[task], (phase_idx, result.loss))
        end
        push!(losses, result.loss)
        push!(hot_trace, count(s -> s.allocated && s.superplastic, state.substrate.sites))
        for a in result.actions
            a isa CommitAction && (commits_total += 1)
            a isa MeltAction && (melts_total += 1)
        end

        if tick % PROBE_EVERY == 0
            lA = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.A)
            lB = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.B)
            lC = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.C)
            lD = mse_loss(material_predict(mlp, state, X, policy, tick), TASKS.D)
            push!(probe4, (tick, phase_idx, (lA, lB, lC, lD)))
        end
    end

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

    phase_final = Float32[]
    for p in 1:n_phases
        lo = (p - 1) * L + max(1, L - 9)
        hi = p * L
        push!(phase_final, mean(losses[lo:hi]))
    end

    max_mid = 0.0f0
    for t in 2:length(losses)
        (t - 1) % L == 0 && continue
        max_mid = max(max_mid, abs(losses[t] - losses[t-1]))
    end

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
    task_gain = Dict{Symbol,Float32}(name => isempty(gains[name]) ? NaN32 : mean(gains[name]) for name in TASK_ORDER)

    return (
        label=label, L=L,
        mean_phase_final=mean(phase_final),
        ret_matched=isempty(ret_matched) ? NaN32 : mean(ret_matched),
        max_mid_jump=max_mid,
        task_gain=task_gain,
        mean_task_gain=mean(task_gain[name] for name in TASK_ORDER),
        hot_frac_mean=mean(hot_trace) / 64.0f0,
        commits_total=commits_total,
        melts_total=melts_total,
    )
end

function print_row(r)
    @printf("%-6s L=%3d | pf=%7.4f retM=%7.4f gain=%+7.4f | hot=%5.2f jump=%5.3f | C=%4d M=%4d\n",
        r.label, r.L, r.mean_phase_final, r.ret_matched, r.mean_task_gain,
        r.hot_frac_mean, r.max_mid_jump, r.commits_total, r.melts_total)
end

function main()
    println("="^110)
    println("E0d — tag routing: PHASE vs TAGR vs UNDIR vs FIXED across the phase-length grid, preregistered")
    println("="^110)

    arms = [
        (:PHASE, () -> PhaseMachineController(2)),
        (:TAGR,  () -> TagRoutingController(2)),
        (:UNDIR, () -> UndirectedController(2)),
        (:FIXED, () -> FIXED_RULE_CONTROLLER),
    ]

    results = Dict{Tuple{Symbol,Int},Any}()
    for L in L_GRID
        println("\n--- L = $L ---")
        for (name, mk) in arms
            r = run_arm(mk(); L=L, label=name)
            results[(name, L)] = r
            print_row(r)
        end
    end

    println("\n" * "="^110)
    println("PREREGISTERED RESULT CHECKS")
    println("="^110)

    for L in L_GRID
        ph = results[(:PHASE, L)]
        tg = results[(:TAGR, L)]
        un = results[(:UNDIR, L)]
        fx = results[(:FIXED, L)]
        @printf("\nL=%d:  PHASE gain=%+.4f  TAGR %+.4f  UNDIR %+.4f  FIXED %+.4f\n",
            L, ph.mean_task_gain, tg.mean_task_gain, un.mean_task_gain, fx.mean_task_gain)
        @printf("       PHASE pf=%.4f  TAGR %.4f  UNDIR %.4f  FIXED %.4f\n",
            ph.mean_phase_final, tg.mean_phase_final, un.mean_phase_final, fx.mean_phase_final)
    end

    # R1
    r1 = results[(:TAGR, 40)].mean_task_gain > results[(:PHASE, 40)].mean_task_gain &&
         results[(:TAGR, 40)].mean_task_gain > 0
    @printf("\nR1 window extension (TAGR(40) > PHASE(40) and > 0):  %+ .4f vs %+ .4f  [%s]\n",
        results[(:TAGR, 40)].mean_task_gain, results[(:PHASE, 40)].mean_task_gain,
        r1 ? "PASS" : "FAIL")

    # R2
    r2_all = [results[(:TAGR, L)].mean_task_gain > results[(:PHASE, L)].mean_task_gain for L in L_GRID]
    @printf("R2 monotone dose (TAGR > PHASE at every L):           %s  [%s]\n",
        join([@sprintf("L%d:%s", L, r2_all[i] ? "+" : "-") for (i, L) in enumerate(L_GRID)], " "),
        all(r2_all) ? "PASS" : "FAIL")

    # R3
    r3 = results[(:PHASE, 150)].mean_task_gain > results[(:UNDIR, 150)].mean_task_gain
    @printf("R3 causality (PHASE(150) > UNDIR(150)):               %+ .4f vs %+ .4f  [%s]\n",
        results[(:PHASE, 150)].mean_task_gain, results[(:UNDIR, 150)].mean_task_gain,
        r3 ? "PASS" : "FAIL")

    # R4
    r4_all = [abs(results[(:TAGR, L)].melts_total - results[(:PHASE, L)].melts_total) <=
              0.1 * results[(:PHASE, L)].melts_total for L in L_GRID]
    @printf("R4 invalidation invariance (|TAGR-PHASE| melts <=10%%): %s  [%s]\n",
        join([@sprintf("L%d:%d/%d", L, results[(:TAGR, L)].melts_total, results[(:PHASE, L)].melts_total) for (i, L) in enumerate(L_GRID)], " "),
        all(r4_all) ? "PASS" : "FAIL")
end

main()
