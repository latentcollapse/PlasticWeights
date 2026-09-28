# ---------------------------------------------------------------------------
# E0h — Pass 3e: burst-width commit allowance. PREREGISTERED BEFORE EXECUTION.
#
# (No BURST grid row ran before this header was written; the pre-script work
# was limited to unit fixtures and an R0 byte-exactness sanity confirming the
# two-pass kernel restructure leaves PHASE@150 at 282 commits / 218 melts.)
#
# Targets E0g-D1: the short-L deficit is NOT per-phase-volume-bound (the E0g
# quota never consumed at L=15 — PHASE spends ~5.1 commits/phase against Q=8)
# and not dwell (E0f-D1: remission inert under the budget). E0g-D1 pinned the
# constraint to the 1/tick PACING across the BURST STRUCTURE of settle-
# certificate arrivals: up to 12 commit-intent sites crowd into a single short
# phase, all drained at one per tick. E0h shapes admission WITHIN the tick's
# burst:
#
#   cap(tick) = max(1, floor(burst_fraction · W)),  W = raw commit-intent count
#
# W is observed statelessly in a discarded intent pass (decide() is pure);
# the kernel admits the leading `cap` intent sites in canonical order, denied
# sites keep their persistent counters. Per-tick admission ≤ W and the
# fractional cap bounds the drain rate (geometric, not the E0b2 wave). The
# per-site rule is EXACTLY the phase machine's (settle + dwell + melt margin,
# NO remission); melts untouched. The budget is POSITION-BLIND (no phase_length
# consulted). This is the controlled decomposition of TAGR's lift: TAGR =
# burst admission (this lever) + dwell remission; E0h turns the first knob
# alone, so any short-L gain is attributable to admission shape, and the R4
# ablation (burst_fraction = 1.0, batch-every-intent) is "TAGR minus
# remission" exactly.
#
# Arms (identical MLP seed 71, head Adam lr=0.02; only the lifecycle varies):
#   PHASE   — PhaseMachineController(2)    (baseline + reproduction canary)
#   BURST   — BurstCommitController(2; burst_fraction=0.5)  (the burst lever)
#   BURST_A — BurstCommitController(2; burst_fraction=1.0)  (batch-every-intent
#          ablation: the full TAGR-shaped admission, remission excluded)
#   FIXED   — FixedRuleController          (substrate floor control)
#
# Grid: L ∈ {15, 40, 75, 150} on the E1b/E1c/E0d–E0g four-task family and
# stream (identical protocol: seed 71, Stage0MLP(2,32,2), Adam lr=0.02,
# Bingham(1e-5), RampedVPS(2; m_max=0.02), beta=gamma=0.5, SUB-frozen region
# parameters, conflict_k=2, phase_length=L declared to every arm).
#
# PREREGISTERED RESULTS (declared before any run):
#   C0 (canary reproduction): PHASE(150) meanGain == +0.4067 (±1e-3) AND
#      PHASE(150) melts_total == 218. Otherwise the harness drifted and NO
#      new-arm row is interpretable.
#   R1 (short-window win — THE target): BURST(15) > PHASE(15) AND
#      BURST(40) > PHASE(40). The E0g-D1 pacing account predicts the drain
#      lift moves exactly the regimes where intent crowds (L=15: max 12
#      commit-intents/phase vs 1/tick admission).
#   R2 (long-window non-toxicity): BURST(150) >= PHASE(150) − 0.05·|PHASE(150)|.
#      E0e-D2 says the deep window needs churn PACING; the geometric drain
#      front-loads recommits, so this is the real risk of the arm. TAGR failed
#      here via remission; E0h tests whether admission shape ALONE is also
#      toxic (ledger either way).
#   R3 (mechanism decomposition): |BURST_A(15) − TAGR(15)| < |PHASE(15) −
#      TAGR(15)|, where each term is |gain difference| against the E0e
#      committed TAGR(15) = +0.1226 row (docs/e0e_rows.csv). If batch-shaped
#      admission WITHOUT remission recovers most of TAGR's short-L advantage,
#      mechanism A was admission shape; if not, remission carries it.
#   R4 (ablation adjudication): BURST_A(15) > PHASE(15) — the batch limit
#      must not be worse than the phase machine at short L (it admits a
#      superset of PHASE's actions whenever W >= 1; behavioral divergence
#      enters only through timing).
#   R5 (drain signature): BURST(15) max single-tick commits >= 2 AND
#      BURST(150) max single-tick commits >= 2 — the lever actually fired
#      (1/tick would make max == 1; if the cap never exceeded 1, R1/R2
#      outcomes are uninterpretable as burst effects).
#
# Failure modes get ledger IDs (E0h-D1, ...) and are NOT reinterpreted.
#
# Usage (chunked foreground; every (arm, L) row is cached to
# docs/e0h_rows.csv and runs are resumable):
#   julia --project=. scripts/e0h_burst_commit.jl canary
#   julia --project=. scripts/e0h_burst_commit.jl ensure 15:PHASE 15:BURST ...
#   julia --project=. scripts/e0h_burst_commit.jl grid75 / grid150 / grid
#   julia --project=. scripts/e0h_burst_commit.jl checks
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
const TAGR_15_GAIN = 0.12255643f0        # committed E0e row (docs/e0e_rows.csv)

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
    commits_per_tick_max = 0          # E0h drain signature: busiest single tick
    commit_ticks = 0                  # ticks admitting >= 1 commit

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
    )
end

function print_row(r)
    @printf("%-8s L=%3d | pf=%7.4f retM=%7.4f gain=%+7.4f | hot=%5.2f jump=%5.3f | C=%4d (y%3d/d%3d) M=%4d (y%3d/d%3d) | tickC max=%3d ticks=%4d\n",
        r.label, r.L, r.mean_phase_final, r.ret_matched, r.mean_task_gain,
        r.hot_frac_mean, r.max_mid_jump,
        r.commits_total, r.commits_young, r.commits_deep,
        r.melts_total, r.melts_young, r.melts_deep,
        r.commits_per_tick_max, r.commit_ticks)
end

const ARMS = [
    (:PHASE,   () -> PhaseMachineController(2)),
    (:BURST,   () -> BurstCommitController(2; burst_fraction=0.5)),
    (:BURST_A, () -> BurstCommitController(2; burst_fraction=1.0)),
    (:FIXED,   () -> FIXED_RULE_CONTROLLER),
]

# --------------------------- resumable row cache ---------------------------
const ROWS_CSV = joinpath(@__DIR__, "..", "docs", "e0h_rows.csv")
const ROW_FIELDS = (:label, :L, :mean_phase_final, :ret_matched, :mean_task_gain,
                    :hot_frac_mean, :max_mid_jump, :commits_total, :melts_total,
                    :melts_young, :melts_deep, :commits_young, :commits_deep,
                    :commits_per_tick_max, :commit_ticks)

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
            ',', r.commits_per_tick_max, ',', r.commit_ticks)
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
            commit_ticks=parse(Int, f[15]))
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
    println("E0h — burst-width commit allowance (Pass 3e): within-burst admission, PHASE commit rule — preregistered [mode: $mode]")
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
        b  = results[(:BURST, L)]
        ba = results[(:BURST_A, L)]
        fx = results[(:FIXED, L)]
        @printf("\nL=%d:  PHASE %+ .4f  BURST %+ .4f  BURST_A %+ .4f  FIXED %+ .4f  (meanGain)\n",
            L, ph.mean_task_gain, b.mean_task_gain, ba.mean_task_gain, fx.mean_task_gain)
        @printf("       pf:  PHASE %.4f  BURST %.4f  BURST_A %.4f  FIXED %.4f\n",
            ph.mean_phase_final, b.mean_phase_final, ba.mean_phase_final, fx.mean_phase_final)
        @printf("       commits: PHASE %d (tickCmax %d)  BURST %d (tickCmax %d)  BURST_A %d (tickCmax %d)\n",
            ph.commits_total, ph.commits_per_tick_max,
            b.commits_total, b.commits_per_tick_max,
            ba.commits_total, ba.commits_per_tick_max)
        @printf("       melts (young/total): PHASE %d/%d  BURST %d/%d  BURST_A %d/%d\n",
            ph.melts_young, ph.melts_total, b.melts_young, b.melts_total,
            ba.melts_young, ba.melts_total)
    end

    if haskey(results, (:PHASE, 150))
        ph150 = results[(:PHASE, 150)]
        c0 = abs(ph150.mean_task_gain - 0.4067f0) <= 1.0f-3 && ph150.melts_total == 218
        @printf("\nC0 canary reproduction (PHASE@150 == E0d committed):   gain %+.4f melts %d  [%s]\n",
            ph150.mean_task_gain, ph150.melts_total, c0 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, L)) for (n, L) in ((:BURST, 15), (:PHASE, 15),
                                                  (:BURST, 40), (:PHASE, 40)))
        r1 = results[(:BURST, 15)].mean_task_gain > results[(:PHASE, 15)].mean_task_gain &&
             results[(:BURST, 40)].mean_task_gain > results[(:PHASE, 40)].mean_task_gain
        @printf("R1 short-window win (BURST>PHASE at 15 and 40): %+ .4f/%+.4f vs %+ .4f/%+.4f  [%s]\n",
            results[(:BURST, 15)].mean_task_gain, results[(:BURST, 40)].mean_task_gain,
            results[(:PHASE, 15)].mean_task_gain, results[(:PHASE, 40)].mean_task_gain,
            r1 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 150)) for (n, L) in ((:BURST, 150), (:PHASE, 150)))
        phg = results[(:PHASE, 150)].mean_task_gain
        bg  = results[(:BURST, 150)].mean_task_gain
        r2 = bg >= phg - 0.05f0 * abs(phg)
        @printf("R2 long-window non-toxicity (BURST(150) >= PHASE(150) − 5%%): %+ .4f vs %+ .4f  [%s]\n",
            bg, phg, r2 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 15)) for (n,) in ((:BURST_A,), (:PHASE,)))
        bag = results[(:BURST_A, 15)].mean_task_gain
        phg = results[(:PHASE, 15)].mean_task_gain
        d_ba = abs(bag - TAGR_15_GAIN)
        d_ph = abs(phg - TAGR_15_GAIN)
        r3 = d_ba < d_ph
        @printf("R3 mechanism decomposition (|BURST_A−TAGR| %.4f < |PHASE−TAGR| %.4f at 15):  [%s]\n",
            d_ba, d_ph, r3 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, 15)) for (n,) in ((:BURST_A,), (:PHASE,)))
        r4 = results[(:BURST_A, 15)].mean_task_gain > results[(:PHASE, 15)].mean_task_gain
        @printf("R4 ablation (BURST_A(15) > PHASE(15)): %+ .4f vs %+ .4f  [%s]\n",
            results[(:BURST_A, 15)].mean_task_gain,
            results[(:PHASE, 15)].mean_task_gain, r4 ? "PASS" : "FAIL")
    end

    if all(haskey(results, (n, L)) for (n, L) in ((:BURST, 15), (:BURST, 150)))
        m15 = results[(:BURST, 15)].commits_per_tick_max
        m150 = results[(:BURST, 150)].commits_per_tick_max
        r5 = m15 >= 2 && m150 >= 2
        @printf("R5 drain signature (BURST max single-tick commits >= 2 at 15 and 150): %d/%d  [%s]\n",
            m15, m150, r5 ? "PASS" : "FAIL")
    end
    return results
end

main()
