# ---------------------------------------------------------------------------
# E0f — Pass 3c: melt-side routing. PREREGISTERED BEFORE EXECUTION.
#
# Targets E0e-D2: the deep window cannot be selected independently of the
# young one on the COMMIT side (young-window rule choices fork the whole phase
# trajectory), which located the open lever on the MELT side. E0f moves that
# lever while holding the commit side at EXACTLY the phase machine's semantics
# (dwell, no remission, 1/tick budget in both windows), so any behavioral
# difference is attributable to melts by construction.
#
# The lever: a committed site's conflict certificate fires at k_eff = 1 while
# the phase is YOUNG (one tick of sustained, consistent, above-floor OPPOSED
# load invalidates immediately) and at the phase machine's pace
# (region.conflict_k) once deep. Direction sensitivity, magnitude floor, and
# melt budget are untouched — only young stale material (whose consolidation
# reference OPPOSES the current load) fast-tracks; aligned material keeps the
# phase machine's protection (E0d's implicit routing).
#
# Arms (identical MLP seed 71, head Adam lr=0.02; only the lifecycle varies):
#   PHASE   — PhaseMachineController(2)    (baseline + reproduction canary)
#   MROUTE  — MeltRoutingController(2; young_fraction=0.5)  (the melt lever)
#   MROUTE_A — MeltRoutingController(2; young_fraction=1.0) (accelerate-
#          everywhere ablation: adjudicates position-gating on the melt side)
#   FIXED   — FixedRuleController          (substrate floor control)
#
# Grid: L ∈ {15, 40, 75, 150} on the E1b/E1c/E0d/E0e four-task family and
# stream (identical protocol: seed 71, Stage0MLP(2,32,2), Adam lr=0.02,
# Bingham(1e-5), RampedVPS(2; m_max=0.02), beta=gamma=0.5, SUB-frozen region
# parameters, conflict_k=2, phase_length=L declared to every arm).
#
# PREREGISTERED RESULTS (declared before any run):
#   C0 (canary reproduction): PHASE(150) meanGain == +0.4067 (±1e-3) AND
#      PHASE(150) melts_total == 218. Otherwise the harness drifted and NO
#      new-arm row is interpretable.
#   R1 (short-window win): MROUTE(15) > PHASE(15) AND MROUTE(40) > PHASE(40).
#      Faster young invalidation of stale (opposed) material should extend
#      the gain window the way commit-side routing did in E0d/E0e — without
#      touching the commit side at all.
#   R2 (long-window parity): MROUTE(150) >= PHASE(150) − 0.05·|PHASE(150)|.
#      The deep window and the whole commit side are PHASE-exact; if young
#      melts already dominate churn (E0e-D2), accelerating them must not
#      cost the large-L gain the way commit-side remission did (E0e-R2).
#   R3 (timing, not volume): |MROUTE(150) melts − PHASE(150) melts| <=
#      0.15·PHASE(150) melts — the lever shifts WHEN stale material melts,
#      not HOW MUCH total churn the phase runs.
#   R4 (melt-lever safety): MROUTE_A(150) >= PHASE(150) − 0.05·|PHASE(150)|
#      — accelerating melts EVERYWHERE must also preserve the large-L gain.
#      PASS on both R2 and R4 would show the melt side, unlike the commit
#      side, is position-insensitive at long L (the position-gating question).
#   R5 (E0e-D2 premise check): PHASE(150) young melt fraction > 0.5 — direct
#      measurement of "melts concentrate in the young window". If this fails,
#      E0e-D2's trajectory-fork story is defective and the E0e interpretation
#      must be re-examined (ledger, not reinterpretation).
#
# Failure modes get ledger IDs (E0f-D1, ...) and are NOT reinterpreted.
#
# Usage (chunked foreground; every (arm, L) row is cached to
# docs/e0f_rows.csv and runs are resumable):
#   julia --project=. scripts/e0f_melt_routing.jl canary
#   julia --project=. scripts/e0f_melt_routing.jl ensure 15:PHASE 15:MROUTE ...
#   julia --project=. scripts/e0f_melt_routing.jl grid75 / grid150 / grid
#   julia --project=. scripts/e0f_melt_routing.jl checks
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
    young_boundary = cld(L, 2)   # = _young_boundary_ticks(0.5f0, L)
    losses = Float32[]
    hot_trace = Int[]
    probe4 = Tuple{Int,Int,NTuple{4,Float32}}[]
    entries = Dict{Symbol,Vector{Tuple{Int,Float32}}}()
    for name in TASK_ORDER
        entries[name] = Tuple{Int,Float32}[]
    end
    commits_total = melts_total = 0
    commits_young = melts_young = 0

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
    )
end

function print_row(r)
    @printf("%-8s L=%3d | pf=%7.4f retM=%7.4f gain=%+7.4f | hot=%5.2f jump=%5.3f | C=%4d (y%3d/d%3d) M=%4d (y%3d/d%3d)\n",
        r.label, r.L, r.mean_phase_final, r.ret_matched, r.mean_task_gain,
        r.hot_frac_mean, r.max_mid_jump,
        r.commits_total, r.commits_young, r.commits_deep,
        r.melts_total, r.melts_young, r.melts_deep)
end

const ARMS = [
    (:PHASE,    () -> PhaseMachineController(2)),
    (:MROUTE,   () -> MeltRoutingController(2; young_fraction=0.5)),
    (:MROUTE_A, () -> MeltRoutingController(2; young_fraction=1.0)),
    (:FIXED,    () -> FIXED_RULE_CONTROLLER),
]

# --------------------------- resumable row cache ---------------------------
const ROWS_CSV = joinpath(@__DIR__, "..", "docs", "e0f_rows.csv")
const ROW_FIELDS = (:label, :L, :mean_phase_final, :ret_matched, :mean_task_gain,
                    :hot_frac_mean, :max_mid_jump, :commits_total, :melts_total,
                    :melts_young, :melts_deep, :commits_young, :commits_deep)

arm_maker(name::Symbol) = ARMS[findfirst(a -> a[1] == name, ARMS)][2]

function append_row_csv(r)
    isfile(ROWS_CSV) ||
        write(ROWS_CSV, join(ROW_FIELDS, ','), "\n")
    open(ROWS_CSV, "a") do io
        println(io, r.label, ',', r.L, ',', r.mean_phase_final, ',', r.ret_matched,
            ',', r.mean_task_gain, ',', r.hot_frac_mean, ',', r.max_mid_jump,
            ',', r.commits_total, ',', r.melts_total,
            ',', r.melts_young, ',', r.melts_deep,
            ',', r.commits_young, ',', r.commits_deep)
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
            commits_deep=parse(Int, f[13]))
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
    println("="^118)
    println("E0f — melt-side routing (Pass 3c): young melt acceleration, PHASE commit side — preregistered [mode: $mode]")
    println("="^118)

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

    println("\n" * "="^118)
    println("ALL CACHED ROWS")
    println("="^118)
    for L in L_GRID
        for (name, _) in ARMS
            haskey(results, (name, L)) && print_row(results[(name, L)])
        end
    end

    println("\n" * "="^118)
    println("PREREGISTERED RESULT CHECKS (evaluated on available rows)")
    println("="^118)

    for L in L_GRID
        all(haskey(results, (n, L)) for (n, _) in ARMS) || continue
        ph = results[(:PHASE, L)]
        mr = results[(:MROUTE, L)]
        ma = results[(:MROUTE_A, L)]
        fx = results[(:FIXED, L)]
        @printf("\nL=%d:  PHASE %+ .4f  MROUTE %+ .4f  MROUTE_A %+ .4f  FIXED %+ .4f  (meanGain)\n",
            L, ph.mean_task_gain, mr.mean_task_gain, ma.mean_task_gain, fx.mean_task_gain)
        @printf("       pf:  PHASE %.4f  MROUTE %.4f  MROUTE_A %.4f  FIXED %.4f\n",
            ph.mean_phase_final, mr.mean_phase_final, ma.mean_phase_final, fx.mean_phase_final)
        @printf("       melts (young/total): PHASE %d/%d  MROUTE %d/%d  MROUTE_A %d/%d | commits: PHASE %d  MROUTE %d  MROUTE_A %d\n",
            ph.melts_young, ph.melts_total, mr.melts_young, mr.melts_total,
            ma.melts_young, ma.melts_total, ph.commits_total, mr.commits_total, ma.commits_total)
    end

    if haskey(results, (:PHASE, 150))
        ph150 = results[(:PHASE, 150)]
        c0 = abs(ph150.mean_task_gain - 0.4067f0) <= 1.0f-3 && ph150.melts_total == 218
        @printf("\nC0 canary reproduction (PHASE@150 == E0d committed):   gain %+.4f melts %d  [%s]\n",
            ph150.mean_task_gain, ph150.melts_total, c0 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, L)) for (n, L) in ((:MROUTE, 15), (:PHASE, 15),
                                                  (:MROUTE, 40), (:PHASE, 40)))
        r1 = results[(:MROUTE, 15)].mean_task_gain > results[(:PHASE, 15)].mean_task_gain &&
             results[(:MROUTE, 40)].mean_task_gain > results[(:PHASE, 40)].mean_task_gain
        @printf("R1 short-window win (MROUTE>PHASE at 15 and 40): %+ .4f/%+.4f vs %+ .4f/%+.4f  [%s]\n",
            results[(:MROUTE, 15)].mean_task_gain, results[(:MROUTE, 40)].mean_task_gain,
            results[(:PHASE, 15)].mean_task_gain, results[(:PHASE, 40)].mean_task_gain,
            r1 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 150)) for (n, _) in ARMS)
        phg = results[(:PHASE, 150)].mean_task_gain
        mrg = results[(:MROUTE, 150)].mean_task_gain
        mag = results[(:MROUTE_A, 150)].mean_task_gain
        r2 = mrg >= phg - 0.05f0 * abs(phg)
        @printf("R2 long-window parity (MROUTE(150) >= PHASE(150) − 5%%):        %+ .4f vs %+ .4f  [%s]\n",
            mrg, phg, r2 ? "PASS" : "FAIL")

        pm = results[(:PHASE, 150)].melts_total
        mm = results[(:MROUTE, 150)].melts_total
        r3 = abs(mm - pm) <= 0.15 * pm
        @printf("R3 timing-not-volume (|MROUTE−PHASE| melts <= 15%% at 150):    %d vs %d  [%s]\n",
            mm, pm, r3 ? "PASS" : "FAIL")

        r4 = mag >= phg - 0.05f0 * abs(phg)
        @printf("R4 melt-lever safety (MROUTE_A(150) >= PHASE(150) − 5%%):      %+ .4f vs %+ .4f  [%s]\n",
            mag, phg, r4 ? "PASS" : "FAIL")
    end

    if haskey(results, (:PHASE, 150))
        ph150 = results[(:PHASE, 150)]
        r5 = ph150.melts_young / ph150.melts_total > 0.5
        @printf("R5 E0e-D2 premise (PHASE(150) young melt fraction > 0.5):      %d/%d = %.2f  [%s]\n",
            ph150.melts_young, ph150.melts_total,
            ph150.melts_young / ph150.melts_total, r5 ? "PASS" : "FAIL")
    end
    return results
end

main()
