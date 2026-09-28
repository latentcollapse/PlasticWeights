# ---------------------------------------------------------------------------
# E0i — Pass 3f: burst-within-quota composite budget. PREREGISTERED BEFORE
# EXECUTION. (No BQ grid row ran before this header was written; pre-script
# work was limited to unit fixtures and an R0 sanity: PHASE@150 = 282/218
# reproduced exactly after the kernel change, and the composite's quota was
# shown to bound the FIRST tick of a 64-wide settle burst to Q commits —
# the E0b2 wave is structurally impossible. A first implementation that
# gated only later ticks (admitting the wave) was caught by that sanity and
# fixed to cap = min(burst cap, remaining quota) BEFORE any grid run.)
#
# Motivation. E0h-D1: TAGR ≡ batch admission (remission redundant). E0h-D2:
# the burst lever's dose-response is threshold-like at short L (0.5·W inert,
# 1.0·W = TAGR) and toxic at long L (melts collapse, arms converge to the
# FIXED floor). E0g-D2: a per-phase quota is long-L-free. The composite:
#
#   cap(tick) = min( max(1, floor(bf·W)), Q − spent )   if spent < Q, else 0
#
# bf = burst_fraction, Q = ceil(qf·L), spent = live-stamp commits this phase
# (melts refund). Per-site rule byte-exact PHASE; melts untouched; position-
# gated (undeclared L HardFails, like QUOTA).
#
# DECLARED DESIGN TENSION (from committed rows): BURST_A per-phase demand is
# NON-MONOTONIC in L — 10.0/40.6/43.0/12.7 commits/phase at L=15/40/75/150
# (PHASE: 5.1/28.8/45.8/28.2) — while any constant-fraction quota is linear.
# A quota that binds at short L (≥ 8 at L=15) CANNOT bind at long L (needs
# < 13 at L=150). The composite therefore maps a trade-off LINE, not a free
# win; this preregistration declares its endpoints and accepts the long-L
# cost as bounded ONLY IF the melt collapse stays inside the R2 band.
#
# Arms (identical MLP seed 71, head Adam lr=0.02; only the lifecycle varies):
#   PHASE   — PhaseMachineController(2)    (baseline + reproduction canary)
#   BQ10    — BurstQuotaController(2; burst_fraction=1.0, quota_fraction=0.1)
#   BQ50    — BurstQuotaController(2; burst_fraction=1.0, quota_fraction=0.5)
#   FIXED   — FixedRuleController          (substrate floor control)
#
# Defaults bf = 1.0 (E0h-D2: only the full batch moves short L; sub-batch
# drains are inert there — the quota, not the drain, is this pass's knob).
#
# Grid: L ∈ {15, 40, 75, 150} on the E1b/E1c/E0d–E0h four-task family and
# stream (identical protocol: seed 71, Stage0MLP(2,32,2), Adam lr=0.02,
# Bingham(1e-5), RampedVPS(2; m_max=0.02), beta=gamma=0.5, SUB-frozen region
# parameters, conflict_k=2, phase_length=L declared to every arm).
#
# PREREGISTERED RESULTS (declared before any run):
#   C0 (canary reproduction): PHASE(150) meanGain == +0.4067 (±1e-3) AND
#      PHASE(150) melts_total == 218. Otherwise the harness drifted and NO
#      new-arm row is interpretable.
#   R1 (short-window win): BQ10(15) > PHASE(15) AND BQ10(40) > PHASE(40).
#      The quota (Q = 2 at L=15? NO — ceil(0.1·15) = 2 is refuted by
#      calibration: PHASE spends 5.1/phase, so Q = 2 THROTTLES below PHASE
#      demand and the arm degenerates toward a starved machine. Declared
#      honestly: R1 is expected to FAIL at L=15 for BQ10 by this arithmetic
#      (Q10(15) = 2 < 5.1). It is retained as a written-down falsification
#      of "small quota suffices" — the informative short-L arm is BQ50
#      (Q = 8, matching E0g's never-consumed quota BUT now draining bursts
#      into it). The BQ50(15) row is therefore the real short-L test:
#      BQ50(15) > PHASE(15) is the short-L hypothesis this pass actually
#      stakes (burst-shaped admission into the same quota E0g showed inert
#      under 1/tick pacing).
#   R2 (long-L melt-collapse band — EXPECTED FAIL, declared): BQ50(150)
#      melts >= 0.85 · PHASE(150) melts (= 185.3). By the non-monotonicity
#      arithmetic (demand 12.7/phase < Q = 75) BQ50(150) will be
#      behaviorally BURST_A(150) (127 commits / 63 melts), which fails this
#      band. The check is retained to MEASURE the failure and pin the
#      trade-off line's long-L endpoint on the record (ledger E0i-D1 if it
#      fails as declared). An unexpected PASS would mean the quota DID bind
#      at L=150 (live-stamp refunds) and would falsify the declared
#      arithmetic instead.
#   R3 (mid-L: quota does not undo the burst win): BQ50(40) >= BURST_A(40)
#      − 0.05·|BURST_A(40)| vs committed BURST_A(40) = +0.1372
#      (docs/e0h_rows.csv). Q = 20 < demand 40.6/phase, so BQ50(40) is
#      quota-bound; the question is whether capping the batch VOLUME at 20
#      per phase (with refunds) keeps most of the +0.1372.
#   R4 (decomposition sanity on-arm): BQ10 == BQ50 at every L where
#      ceil(0.1·L) >= BURST_A's per-phase demand max (none on the grid:
#      Q10 = 2/4/8/15 vs demand maxima 12/40/72?/— — so BQ10 must differ
#      from BQ50 at every grid L). Declared: BQ10(15) < BQ50(15) gain AND
#      BQ10(150) >= BQ50(150) − 0.02·|BQ50(150)| (the 150 pair should be
#      nearly identical: both quotas exceed demand there... Q10(150) = 15 >
#      12.7 demand — so BQ10(150) must ALSO be BURST_A-identical. Declared:
#      BQ10(150) == BQ50(150) == BURST_A(150) on commits/melts).
#   R5 (drain signature + quota consumption): BQ50(15) commits_per_phase_max
#      <= 8 AND >= 2; BQ50(40) commits_per_phase_mean > PHASE(40)
#      commits_per_phase_mean (the quota licenses more spend than the
#      machine's pacing allowed: 28.8 → up to 20/phase gross... ceiling
#      BELOW machine demand — declared: BQ50(40) commits_per_phase_mean is
#      between 15 and 20 inclusive). These windows pin where the composite
#      actually bound.
#
# Failure modes get ledger IDs (E0i-D1, ...) and are NOT reinterpreted.
#
# Usage (chunked foreground; every (arm, L) row is cached to
# docs/e0i_rows.csv and runs are resumable):
#   julia --project=. scripts/e0i_burst_quota.jl canary
#   julia --project=. scripts/e0i_burst_quota.jl ensure 15:PHASE 15:BQ10 ...
#   julia --project=. scripts/e0i_burst_quota.jl grid75 / grid150 / grid
#   julia --project=. scripts/e0i_burst_quota.jl checks
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
const BURST_A_40_GAIN = 0.13720974f0     # committed E0h row (docs/e0h_rows.csv)

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
    commits_per_tick_max = 0
    commit_ticks = 0
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
        tick_commits = 0
        for a in result.actions
            if a isa CommitAction
                commits_total += 1
                commits_per_phase[phase_idx] += 1
                tick_commits += 1
                is_young && (commits_young += 1)
            elseif a isa MeltAction
                melts_total += 1
                is_young && (melts_young += 1)
            end
        end
        commits_per_tick_max = max(commits_per_tick_max, tick_commits)
        tick_commits > 0 && (commit_ticks += 1)

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
        commits_per_tick_max=commits_per_tick_max, commit_ticks=commit_ticks,
        commits_phase_mean=mean(commits_per_phase),
        commits_phase_max=maximum(commits_per_phase),
    )
end

function print_row(r)
    @printf("%-8s L=%3d | pf=%7.4f retM=%7.4f gain=%+7.4f | hot=%5.2f jump=%5.3f | C=%4d (y%3d/d%3d) M=%4d (y%3d/d%3d) | tickCmax=%3d ticks=%4d | C/ph μ=%5.2f max=%3d\n",
        r.label, r.L, r.mean_phase_final, r.ret_matched, r.mean_task_gain,
        r.hot_frac_mean, r.max_mid_jump,
        r.commits_total, r.commits_young, r.commits_deep,
        r.melts_total, r.melts_young, r.melts_deep,
        r.commits_per_tick_max, r.commit_ticks,
        r.commits_phase_mean, r.commits_phase_max)
end

const ARMS = [
    (:PHASE, () -> PhaseMachineController(2)),
    (:BQ10,  () -> BurstQuotaController(2; burst_fraction=1.0, quota_fraction=0.1)),
    (:BQ50,  () -> BurstQuotaController(2; burst_fraction=1.0, quota_fraction=0.5)),
    (:FIXED, () -> FIXED_RULE_CONTROLLER),
]

# --------------------------- resumable row cache ---------------------------
const ROWS_CSV = joinpath(@__DIR__, "..", "docs", "e0i_rows.csv")
const ROW_FIELDS = (:label, :L, :mean_phase_final, :ret_matched, :mean_task_gain,
                    :hot_frac_mean, :max_mid_jump, :commits_total, :melts_total,
                    :melts_young, :melts_deep, :commits_young, :commits_deep,
                    :commits_per_tick_max, :commit_ticks,
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
            ',', r.commits_per_tick_max, ',', r.commit_ticks,
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
            commits_per_tick_max=parse(Int, f[14]),
            commit_ticks=parse(Int, f[15]),
            commits_phase_mean=parse(Float32, f[16]),
            commits_phase_max=parse(Int, f[17]))
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
    println("="^138)
    println("E0i — burst-within-quota composite (Pass 3f): batch admission capped per phase — preregistered [mode: $mode]")
    println("="^138)

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

    println("\n" * "="^138)
    println("ALL CACHED ROWS")
    println("="^138)
    for L in L_GRID
        for (name, _) in ARMS
            haskey(results, (name, L)) && print_row(results[(name, L)])
        end
    end

    println("\n" * "="^138)
    println("PREREGISTERED RESULT CHECKS (evaluated on available rows)")
    println("="^138)

    for L in L_GRID
        all(haskey(results, (n, L)) for (n, _) in ARMS) || continue
        ph = results[(:PHASE, L)]
        b10 = results[(:BQ10, L)]
        b50 = results[(:BQ50, L)]
        fx = results[(:FIXED, L)]
        @printf("\nL=%d:  PHASE %+ .4f  BQ10 %+ .4f  BQ50 %+ .4f  FIXED %+ .4f  (meanGain)\n",
            L, ph.mean_task_gain, b10.mean_task_gain, b50.mean_task_gain, fx.mean_task_gain)
        @printf("       pf:  PHASE %.4f  BQ10 %.4f  BQ50 %.4f  FIXED %.4f\n",
            ph.mean_phase_final, b10.mean_phase_final, b50.mean_phase_final, fx.mean_phase_final)
        @printf("       commits: PHASE %d (μ/ph %.1f max %d)  BQ10 %d (μ/ph %.1f max %d)  BQ50 %d (μ/ph %.1f max %d)\n",
            ph.commits_total, ph.commits_phase_mean, ph.commits_phase_max,
            b10.commits_total, b10.commits_phase_mean, b10.commits_phase_max,
            b50.commits_total, b50.commits_phase_mean, b50.commits_phase_max)
        @printf("       melts (young/total): PHASE %d/%d  BQ10 %d/%d  BQ50 %d/%d\n",
            ph.melts_young, ph.melts_total, b10.melts_young, b10.melts_total,
            b50.melts_young, b50.melts_total)
    end

    if haskey(results, (:PHASE, 150))
        ph150 = results[(:PHASE, 150)]
        c0 = abs(ph150.mean_task_gain - 0.4067f0) <= 1.0f-3 && ph150.melts_total == 218
        @printf("\nC0 canary reproduction (PHASE@150 == E0d committed):   gain %+.4f melts %d  [%s]\n",
            ph150.mean_task_gain, ph150.melts_total, c0 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, L)) for (n, L) in ((:BQ50, 15), (:PHASE, 15),
                                                  (:BQ50, 40), (:PHASE, 40)))
        r1 = results[(:BQ50, 15)].mean_task_gain > results[(:PHASE, 15)].mean_task_gain &&
             results[(:BQ50, 40)].mean_task_gain > results[(:PHASE, 40)].mean_task_gain
        @printf("R1 short-window win (BQ50>PHASE at 15 and 40): %+ .4f/%+.4f vs %+ .4f/%+.4f  [%s]\n",
            results[(:BQ50, 15)].mean_task_gain, results[(:BQ50, 40)].mean_task_gain,
            results[(:PHASE, 15)].mean_task_gain, results[(:PHASE, 40)].mean_task_gain,
            r1 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 150)) for (n, L) in ((:BQ50, 150), (:PHASE, 150)))
        phm = results[(:PHASE, 150)].melts_total
        bmm = results[(:BQ50, 150)].melts_total
        r2 = bmm >= 0.85 * phm
        @printf("R2 long-L melt-collapse band (BQ50(150) melts >= 0.85·PHASE(150)): %d vs %d  [%s] (expected FAIL by declared arithmetic)\n",
            bmm, phm, r2 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 40)) for n in (:BQ50, :PHASE))
        bag = results[(:BQ50, 40)].mean_task_gain
        r3 = bag >= BURST_A_40_GAIN - 0.05f0 * abs(BURST_A_40_GAIN)
        @printf("R3 mid-L quota keeps the burst win (BQ50(40) >= BURST_A(40) − 5%% = %.4f): %+ .4f  [%s]\n",
            BURST_A_40_GAIN - 0.05f0 * abs(BURST_A_40_GAIN), bag, r3 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 150)) for n in (:BQ10, :BQ50))
        c10 = (results[(:BQ10, 150)].commits_total, results[(:BQ10, 150)].melts_total)
        c50 = (results[(:BQ50, 150)].commits_total, results[(:BQ50, 150)].melts_total)
        r4 = c10 == c50
        @printf("R4 quota-unbound identity at 150 (BQ10 == BQ50 on commits/melts): %s vs %s  [%s]\n",
            c10, c50, r4 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 15)) for n in (:BQ50, :PHASE))
        mx = results[(:BQ50, 15)].commits_phase_max
        r5a = 2 <= mx <= 8
        @printf("R5a drain+quota signature at 15 (2 <= BQ50 commits_phase_max <= 8): %d  [%s]\n",
            mx, r5a ? "PASS" : "FAIL")
    end
    if all(haskey(results, (n, 40)) for n in (:BQ50, :PHASE))
        mu = results[(:BQ50, 40)].commits_phase_mean
        r5b = 15.0 <= mu <= 20.0
        @printf("R5b quota consumption at 40 (15 <= BQ50 commits_phase_mean <= 20): %.2f  [%s]\n",
            mu, r5b ? "PASS" : "FAIL")
    end
    return results
end

main()
