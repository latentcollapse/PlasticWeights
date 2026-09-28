# ---------------------------------------------------------------------------
# E0g — Pass 3d: per-phase commit budget. PREREGISTERED BEFORE EXECUTION.
#
# Targets E0f-D1: at L=15 the deficit is commit-RATE-bound — the phase
# machine's 1/tick budget throttles re-adaptation, and the only prior budget
# lift (TAGR's, E0e) fixed short L (+0.1226 vs PHASE −0.0903) but poisoned
# long L (−0.085 at L=150) because an UNBOUNDED budget destroys the churn
# pacing that carries the large-L gain (E0e-D2). E0g shapes the budget as a
# PHASE-LEVEL QUOTA instead of lifting it wholesale:
#
#   admitted(tick) = min(1, Q − commits_so_far_in_current_phase),  Q = quota_fraction·L
#
# The commit rule is EXACTLY the phase machine's (settle + dwell k_commit +
# melt margin, NO remission) and per-tick admission stays ≤ 1 — the E0b2
# coordinated-commit-wave failure mode stays impossible by construction, and
# any behavioral difference is attributable to the budget SHAPE alone. The
# spent-quota counter is derived kernel-side from live consolidation stamps
# (commits stamp consolidation_tick, melts zero it) in ((p−1)L, tick]: the
# controller stays stateless, the quota refills at every phase boundary.
#
# Calibration (committed rows, docs/e0e_rows.csv + docs/e0f_rows.csv):
# PHASE spends 5.1/28.8/45.8/28.2 commits per phase at L=15/40/75/150, so
# Q = ceil(0.5·L) = 8/20/38/75 lifts the short-L rate while binding nowhere
# at long L — the arm degrades to the phase machine BY ARITHMETIC where the
# quota does not bind.
#
# Arms (identical MLP seed 71, head Adam lr=0.02; only the lifecycle varies):
#   PHASE   — PhaseMachineController(2)    (baseline + reproduction canary)
#   QUOTA   — PhaseQuotaController(2; quota_fraction=0.5)   (the quota lever)
#   QUOTA_A — PhaseQuotaController(2; quota_fraction=1.0)   (rate-unbound-
#          within-phase ablation: per-phase commit ceiling = L, adjudicates
#          whether the 0.5·L bound is doing any work at long L)
#   FIXED   — FixedRuleController          (substrate floor control)
#
# Grid: L ∈ {15, 40, 75, 150} on the E1b/E1c/E0d/E0e/E0f four-task family
# and stream (identical protocol: seed 71, Stage0MLP(2,32,2), Adam lr=0.02,
# Bingham(1e-5), RampedVPS(2; m_max=0.02), beta=gamma=0.5, SUB-frozen region
# parameters, conflict_k=2, phase_length=L declared to every arm).
#
# PREREGISTERED RESULTS (declared before any run):
#   C0 (canary reproduction): PHASE(150) meanGain == +0.4067 (±1e-3) AND
#      PHASE(150) melts_total == 218. Otherwise the harness drifted and NO
#      new-arm row is interpretable.
#   R1 (short-window win — THE target): QUOTA(15) > PHASE(15) AND
#      QUOTA(40) > PHASE(40). If the short-L deficit is commit-rate-bound
#      (E0f-D1), a rate lift bounded per phase must move it.
#   R2 (long-window parity): QUOTA(150) >= PHASE(150) − 0.05·|PHASE(150)|.
#      The commit rule, pacing (≤1/tick), and melt side are all PHASE-exact;
#      if the quota never binds at long L, the arm must not cost the
#      large-L gain the way TAGR's unbounded lift did (E0e-R2).
#   R3 (volume parity at 150): |QUOTA(150) melts − PHASE(150) melts| <=
#      0.15·PHASE(150) melts AND |QUOTA(150) commits − PHASE(150) commits|
#      <= 0.15·PHASE(150) commits — the quota must shift commit timing, not
#      the total churn the run performs.
#   R4 (ablation adjudication): QUOTA_A(150) >= PHASE(150) − 0.05·|PHASE(150)|
#      AND |QUOTA_A(150) melts − PHASE(150) melts| <= 0.15·PHASE(150) melts.
#      With Q = L = 150 vs a PHASE spend of 282 total (28.2/phase), the
#      ceiling is far from binding at long L: QUOTA_A must be statistically
#      the same arm as QUOTA there. (At L=15, Q_A = 15 vs spend 5.1 — also
#      above demand; the ablation is expected inert at every L, and any
#      deviation is itself a finding about hidden budget interactions.)
#   R5 (mechanistic link — quota actually consumed at short L):
#      1.5·PHASE(15) commits <= QUOTA(15) commits <= 3·PHASE(15) commits,
#      i.e. the win, if any, is delivered through the commit rate the
#      quota licenses (PHASE spends ~5.1 commits/phase at L=15; the quota
#      allows up to 8), and not through some second-order effect.
#
# Failure modes get ledger IDs (E0g-D1, ...) and are NOT reinterpreted.
#
# Usage (chunked foreground; every (arm, L) row is cached to
# docs/e0g_rows.csv and runs are resumable):
#   julia --project=. scripts/e0g_phase_quota.jl canary
#   julia --project=. scripts/e0g_phase_quota.jl ensure 15:PHASE 15:QUOTA ...
#   julia --project=. scripts/e0g_phase_quota.jl grid75 / grid150 / grid
#   julia --project=. scripts/e0g_phase_quota.jl checks
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
        phase_length=L,
    )
    state = initialize_material_training(mlp, substrate)
    config = MaterialTrainingConfig(
        law=BinghamInspired(Float32(1e-5)),
        dcp=dcp,
        policy=RampedVPS(2; m_max=0.02f0),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.5f0,
        gamma=0.5f0,
        phase_length=L,
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
    commits_total = melts_total = 0
    commits_young = melts_young = 0
    # E0g diagnostics: per-phase commit counts (quota consumption profile).
    commits_per_phase = zeros(Int, n_phases)

    young_boundary = cld(L, 2)   # = _young_boundary_ticks(0.5f0, L)
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
        tip = mod(tick - 1, L)
        is_young = tip < young_boundary
        for a in result.actions
            if a isa CommitAction
                commits_total += 1
                commits_per_phase[phase_idx] += 1
                is_young && (commits_young += 1)
            elseif a isa MeltAction
                melts_total += 1
                is_young && (melts_young += 1)
            end
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

    # Quota consumption profile: mean and max per-phase spend (diagnostic).
    quota_used_mean = mean(commits_per_phase)
    quota_used_max = maximum(commits_per_phase)

    return (
        label=label, L=L,
        mean_phase_final=mean(phase_final),
        ret_matched=isempty(ret_matched) ? NaN32 : mean(ret_matched),
        mean_task_gain=mean(task_gain[name] for name in TASK_ORDER),
        hot_frac_mean=mean(hot_trace) / 64.0f0,
        max_mid_jump=max_mid,
        commits_total=commits_total, melts_total=melts_total,
        melts_young=melts_young, melts_deep=melts_total - melts_young,
        commits_young=commits_young, commits_deep=commits_total - commits_young,
        commits_phase_mean=quota_used_mean, commits_phase_max=quota_used_max,
    )
end

function print_row(r)
    @printf("%-8s L=%3d | pf=%7.4f retM=%7.4f gain=%+7.4f | hot=%5.2f jump=%5.3f | C=%4d (y%3d/d%3d) M=%4d (y%3d/d%3d) | C/phase μ=%5.2f max=%3d\n",
        r.label, r.L, r.mean_phase_final, r.ret_matched, r.mean_task_gain,
        r.hot_frac_mean, r.max_mid_jump,
        r.commits_total, r.commits_young, r.commits_deep,
        r.melts_total, r.melts_young, r.melts_deep,
        r.commits_phase_mean, r.commits_phase_max)
end

const ARMS = [
    (:PHASE,    () -> PhaseMachineController(2)),
    (:QUOTA,    () -> PhaseQuotaController(2; quota_fraction=0.5)),
    (:QUOTA_A,  () -> PhaseQuotaController(2; quota_fraction=1.0)),
    (:FIXED,    () -> FIXED_RULE_CONTROLLER),
]

# --------------------------- resumable row cache ---------------------------
const ROWS_CSV = joinpath(@__DIR__, "..", "docs", "e0g_rows.csv")
const ROW_FIELDS = (:label, :L, :mean_phase_final, :ret_matched, :mean_task_gain,
                    :hot_frac_mean, :max_mid_jump, :commits_total, :melts_total,
                    :melts_young, :melts_deep, :commits_young, :commits_deep,
                    :commits_phase_mean, :commits_phase_max)

arm_maker(name::Symbol) = ARMS[findfirst(a -> a[1] == name, ARMS)][2]

function append_row_csv(r)
    isfile(ROWS_CSV) ||
        write(ROWS_CSV, join(ROW_FIELDS, ','), "\n")
    open(ROWS_CSV, "a") do io
        println(io, r.label, ',', r.L, ',', r.mean_phase_final, ',', r.ret_matched,
            ',', r.mean_task_gain, ',', r.hot_frac_mean, ',', r.max_mid_jump,
            ',', r.commits_total, ',', r.melts_total,
            ',', r.melts_young, ',', r.melts_deep,
            ',', r.commits_young, ',', r.commits_deep,
            ',', r.commits_phase_mean, ',', r.commits_phase_max)
    end
    return nothing
end

function load_rows()
    rows = Dict{Tuple{Symbol,Int},Any}()
    isfile(ROWS_CSV) || return rows
    for line in eachline(ROWS_CSV)
        startswith(line, "label") && continue
        f = split(strip(line), ',')
        length(f) == length(ROW_FIELDS) || continue
        rows[(Symbol(f[1]), parse(Int, f[2]))] = (
            label=Symbol(f[1]), L=parse(Int, f[2]),
            mean_phase_final=parse(Float32, f[3]), ret_matched=parse(Float32, f[4]),
            mean_task_gain=parse(Float32, f[5]), hot_frac_mean=parse(Float32, f[6]),
            max_mid_jump=parse(Float32, f[7]), commits_total=parse(Int, f[8]),
            melts_total=parse(Int, f[9]), melts_young=parse(Int, f[10]),
            melts_deep=parse(Int, f[11]), commits_young=parse(Int, f[12]),
            commits_deep=parse(Int, f[13]),
            commits_phase_mean=parse(Float32, f[14]),
            commits_phase_max=parse(Int, f[15]))
    end
    return rows
end

ensure_row!(results, name::Symbol, L::Int) = begin
    haskey(results, (name, L)) && return
    r = run_arm(arm_maker(name)(); L=L, label=name)
    results[(name, L)] = r
    append_row_csv(r)
    print("[fresh] ")
    print_row(r)
    return
end

function main()
    mode = length(ARGS) >= 1 ? ARGS[1] : "canary"
    println("="^128)
    println("E0g — per-phase commit budget (Pass 3d): quota-shaped 1/tick budget, PHASE commit rule — preregistered [mode: $mode]")
    println("="^128)

    results = load_rows()

    if mode == "canary"
        ensure_row!(results, :PHASE, 150)
    elseif mode == "short"
        for L in (15, 40), (name, _) in ARMS
            ensure_row!(results, name, L)
        end
    elseif mode == "grid75"
        for (name, _) in ARMS
            ensure_row!(results, name, 75)
        end
    elseif mode == "grid150"
        for (name, _) in ARMS
            ensure_row!(results, name, 150)
        end
    elseif mode == "grid"
        for L in L_GRID, (name, _) in ARMS
            ensure_row!(results, name, L)
        end
    elseif mode == "ensure"
        length(ARGS) >= 2 || error("usage: ensure L:ARM")
        for spec in ARGS[2:end]
            f = split(spec, ':')
            length(f) == 2 || error("usage: ensure L:ARM (got $spec)")
            ensure_row!(results, Symbol(f[2]), parse(Int, f[1]))
        end
    elseif mode == "checks"
        # evaluate from the cache alone
    else
        error("unknown mode $mode")
    end

    println("\n" * "="^128)
    println("ALL CACHED ROWS")
    println("="^128)
    for L in L_GRID
        for (name, _) in ARMS
            haskey(results, (name, L)) && print_row(results[(name, L)])
        end
    end

    println("\n" * "="^128)
    println("PREREGISTERED RESULT CHECKS (evaluated on available rows)")
    println("="^128)

    for L in L_GRID
        all(haskey(results, (n, L)) for (n, _) in ARMS) || continue
        ph = results[(:PHASE, L)]
        q  = results[(:QUOTA, L)]
        qa = results[(:QUOTA_A, L)]
        fx = results[(:FIXED, L)]
        @printf("\nL=%d:  PHASE %+ .4f  QUOTA %+ .4f  QUOTA_A %+ .4f  FIXED %+ .4f  (meanGain)\n",
            L, ph.mean_task_gain, q.mean_task_gain, qa.mean_task_gain, fx.mean_task_gain)
        @printf("       pf:  PHASE %.4f  QUOTA %.4f  QUOTA_A %.4f  FIXED %.4f\n",
            ph.mean_phase_final, q.mean_phase_final, qa.mean_phase_final, fx.mean_phase_final)
        @printf("       commits: PHASE %d (μ/ph %.1f, max %d)  QUOTA %d (μ/ph %.1f, max %d)  QUOTA_A %d (μ/ph %.1f, max %d)\n",
            ph.commits_total, ph.commits_phase_mean, ph.commits_phase_max,
            q.commits_total, q.commits_phase_mean, q.commits_phase_max,
            qa.commits_total, qa.commits_phase_mean, qa.commits_phase_max)
        @printf("       melts (young/total): PHASE %d/%d  QUOTA %d/%d  QUOTA_A %d/%d\n",
            ph.melts_young, ph.melts_total, q.melts_young, q.melts_total,
            qa.melts_young, qa.melts_total)
    end

    if haskey(results, (:PHASE, 150))
        ph150 = results[(:PHASE, 150)]
        c0 = abs(ph150.mean_task_gain - 0.4067f0) <= 1.0f-3 && ph150.melts_total == 218
        @printf("\nC0 canary reproduction (PHASE@150 == E0d committed):   gain %+.4f melts %d  [%s]\n",
            ph150.mean_task_gain, ph150.melts_total, c0 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, L)) for (n, L) in ((:QUOTA, 15), (:PHASE, 15),
                                                  (:QUOTA, 40), (:PHASE, 40)))
        r1 = results[(:QUOTA, 15)].mean_task_gain > results[(:PHASE, 15)].mean_task_gain &&
             results[(:QUOTA, 40)].mean_task_gain > results[(:PHASE, 40)].mean_task_gain
        @printf("R1 short-window win (QUOTA>PHASE at 15 and 40): %+ .4f/%+.4f vs %+ .4f/%+.4f  [%s]\n",
            results[(:QUOTA, 15)].mean_task_gain, results[(:QUOTA, 40)].mean_task_gain,
            results[(:PHASE, 15)].mean_task_gain, results[(:PHASE, 40)].mean_task_gain,
            r1 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 150)) for (n, _) in ARMS)
        phg = results[(:PHASE, 150)].mean_task_gain
        qg  = results[(:QUOTA, 150)].mean_task_gain
        qag = results[(:QUOTA_A, 150)].mean_task_gain
        phm = results[(:PHASE, 150)].melts_total
        phc = results[(:PHASE, 150)].commits_total
        qm  = results[(:QUOTA, 150)].melts_total
        qc  = results[(:QUOTA, 150)].commits_total
        qam = results[(:QUOTA_A, 150)].melts_total
        r2 = qg >= phg - 0.05f0 * abs(phg)
        @printf("R2 long-window parity (QUOTA(150) >= PHASE(150) − 5%%):        %+ .4f vs %+ .4f  [%s]\n",
            qg, phg, r2 ? "PASS" : "FAIL")

        r3 = abs(qm - phm) <= 0.15 * phm && abs(qc - phc) <= 0.15 * phc
        @printf("R3 volume parity at 150 (melts %d vs %d, commits %d vs %d; both <= 15%%):  [%s]\n",
            qm, phm, qc, phc, r3 ? "PASS" : "FAIL")

        r4 = qag >= phg - 0.05f0 * abs(phg) && abs(qam - phm) <= 0.15 * phm
        @printf("R4 ablation adjudication (QUOTA_A(150) >= PHASE(150) − 5%%, melts <= 15%%): %+ .4f, melts %d  [%s]\n",
            qag, qam, r4 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 15)) for (n,) in ((:QUOTA,), (:PHASE,)))
        pc = results[(:PHASE, 15)].commits_total
        qc = results[(:QUOTA, 15)].commits_total
        r5 = 1.5 * pc <= qc <= 3 * pc
        @printf("R5 mechanistic link (PHASE(15) <= QUOTA(15) commits <= 3·PHASE(15)): %d in [%d, %d]  [%s]\n",
            qc, Int(ceil(1.5 * pc)), Int(floor(3 * pc)), r5 ? "PASS" : "FAIL")
    end
    return results
end

main()
