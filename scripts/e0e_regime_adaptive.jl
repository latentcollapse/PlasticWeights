# ---------------------------------------------------------------------------
# E0e — Pass 3b: regime-adaptive routing. PREREGISTERED BEFORE EXECUTION.
#
# Synthesizes E0d's two-mechanism result:
#   Mechanism A — tag-carried memory (TAGR): dominates SHORT phases
#                 (L=15: TAGR +0.123 vs PHASE −0.090; L=40: +0.137 vs +0.021).
#   Mechanism B — melt/recommit churn (PHASE): dominates LONG phases
#                 (L=150: PHASE +0.407 vs TAGR +0.325; melts 218 vs 63).
# Both mechanisms are direction-gated (E0d-R3), so the open question is only
# WHICH mechanism a phase needs. E0e routes by phase position:
#
#   REGIME — RegimeAdaptiveController(k_commit=2; young_fraction=0.5):
#     while ticks_into_phase <  L/2  → tag-aligned melted sites commit on the
#                                      first certified settle tick (dwell
#                                      REMITTED — mechanism A, the TAGR rule);
#     at or beyond the boundary      → behaviorally the phase machine
#                                      (dwell applies — mechanism B).
#     The melt side is byte-identical to PHASE's; REGIME joins the phase
#     machine's 1/tick commit budget, so the ONLY difference from PHASE is
#     remission timing inside the young window. Regime position is
#     harness-declared metadata (config/region `phase_length=L`,
#     `ticks_into_phase` derived per snapshot); the controller stays stateless.
#
# Arms (identical MLP seed 71, head Adam lr=0.02; only the lifecycle varies):
#   PHASE — PhaseMachineController(2)      (baseline; ALSO the reproduction
#          canary: must reproduce E0d's committed numbers bit-exactly)
#   REGIME — RegimeAdaptiveController(2; budgeted=false): the preregistered
#          SYNTHESIS arm. Young window = the TAGR rule IN FULL (dwell
#          remitted, no commit budget); deep window = the PHASE rule in full
#          (dwell applies, 1/tick budget). The budget follows the window
#          because of E0e-D1 (declared pre-grid, below).
#   REGIME_B — RegimeAdaptiveController(2; budgeted=true): protocol-parity
#          ablation. 1/tick budget in BOTH windows. Tests the budget's share
#          of the young-window effect (R5) and guards window parity (R6).
#   TAGR  — TagRoutingController(2)        (mechanism A everywhere: reference;
#          unbudgeted, per the committed E0d contract)
#   FIXED — FixedRuleController            (substrate floor control)
#
# AMENDMENT E0e-D1 (declared BEFORE the L=75/150 runs; the short-window run
# is saved in docs/e0e_short_output.txt): the short-window run showed REGIME
# (then budgeted, per the original preregistration) byte-identical to PHASE
# at L=15 and L=40, and a diagnostic showed even young_fraction=1.0 identical
# to PHASE (commits 288 / melts 248 at L=40 both arms) while committed E0d
# TAGR numbers differ strongly (406/345). Conclusion: under the 1/tick commit
# budget, dwell remission is behaviorally INERT in this protocol — the budget
# queue, not k_commit, gates recommit timing. E0d's mechanism-A effect is
# budget-mediated. The synthesis arm therefore carries the TAGR rule in full
# in the young window (remission AND no budget) and the PHASE rule in full in
# the deep window (dwell AND budget). Nothing about the checks below was
# reinterpreted to fit data: R1-R4 are unchanged in form; R5/R6 were added to
# attribute the effect the amendment predicts.
#
# Grid: L ∈ {15, 40, 75, 150} on the E1b/E1c/E0d four-task family and stream
# (identical protocol: seed 71, Stage0MLP(2,32,2), Adam lr=0.02, Bingham(1e-5),
# RampedVPS(2; m_max=0.02), beta=gamma=0.5, SUB-frozen region parameters,
# conflict_k=2; gain = baseline-cold-start-corrected mean per-task gain).
#
# PREREGISTERED RESULTS (declared before any run):
#   C0 (canary reproduction): PHASE(150) meanGain == +0.4067 (±1e-3) AND
#      PHASE(150) melts_total == 218. If the committed E0d baseline does not
#      reproduce, the harness is broken and NO new-arm row is interpretable.
#   R1 (short-window win): REGIME(15) > PHASE(15) AND REGIME(40) > PHASE(40)
#      AND REGIME(15) > 0 — remission extends the gain window as TAGR did.
#   R2 (long-window parity): REGIME(150) >= PHASE(150) − 0.05·|PHASE(150)|
#      — letting churn run deep preserves the phase machine's large-L gain
#      (E0d-R2's failure was the whole point of adapting the regime).
#   R3 (churn-trace parity): |REGIME(150) melts − PHASE(150) melts| <=
#      0.15·PHASE(150) melts — the deep window must actually look like churn.
#   R4 (adaptivity attribution): REGIME(150) > TAGR(150) — beating pure
#      remission at long L shows the regime switch itself carries value.
#   R5 (budget attribution, post-D1): REGIME(15) > REGIME_B(15) — with the
#      budget lifted in the young window, the short-L gain must APPEAR where
#      the budgeted arm is byte-identical to PHASE.
#   R6 (window parity, post-D1): REGIME(150) == REGIME_B(150) exactly on
#      meanGain and melts — with no remittable melts deep in a phase, the
#      budget flag must be behaviorally irrelevant at long L.
#
# Failure modes get ledger IDs (E0e-D1, ...) and are NOT reinterpreted.
#
# Usage (chunked foreground; background processes die between tool calls):
#   julia --project=. scripts/e0e_regime_adaptive.jl canary          # C0 only
#   julia --project=. scripts/e0e_regime_adaptive.jl short           # ensure L=15,40 rows
#   julia --project=. scripts/e0e_regime_adaptive.jl ensure 150:PHASE  # ensure one row
#   julia --project=. scripts/e0e_regime_adaptive.jl grid75 / grid150 / grid
#   julia --project=. scripts/e0e_regime_adaptive.jl checks          # evaluate from cache
#
# Every completed (arm, L) row is appended to docs/e0e_rows.csv; runs are
# RESUMABLE — `ensure` runs only missing rows — so the grid can be executed in
# foreground chunks smaller than the tool-call timeout. Checks always evaluate
# from the union of cached rows and are guarded on row presence.
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

const ARMS = [
    (:PHASE,    () -> PhaseMachineController(2)),
    (:REGIME,   () -> RegimeAdaptiveController(2; budgeted=false)),
    (:REGIME_B, () -> RegimeAdaptiveController(2; budgeted=true)),
    (:TAGR,     () -> TagRoutingController(2)),
    (:FIXED,    () -> FIXED_RULE_CONTROLLER),
]

# --------------------------- resumable row cache ---------------------------
const ROWS_CSV = joinpath(@__DIR__, "..", "docs", "e0e_rows.csv")
const ROW_FIELDS = (:label, :L, :mean_phase_final, :ret_matched, :mean_task_gain,
                    :hot_frac_mean, :max_mid_jump, :commits_total, :melts_total)

arm_maker(name::Symbol) = ARMS[findfirst(a -> a[1] == name, ARMS)][2]

function append_row_csv(r)
    isfile(ROWS_CSV) ||
        write(ROWS_CSV, join(ROW_FIELDS, ','), "\n")
    open(ROWS_CSV, "a") do io
        println(io, r.label, ',', r.L, ',', r.mean_phase_final, ',', r.ret_matched,
            ',', r.mean_task_gain, ',', r.hot_frac_mean, ',', r.max_mid_jump,
            ',', r.commits_total, ',', r.melts_total)
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
            melts_total=parse(Int, f[9]))
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
    println("="^110)
    println("E0e — regime-adaptive routing (Pass 3b): young remission, deep churn — preregistered [mode: $mode]")
    println("="^110)

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

    println("\n" * "="^110)
    println("ALL CACHED ROWS")
    println("="^110)
    for L in L_GRID
        for (name, _) in ARMS
            haskey(results, (name, L)) && print_row(results[(name, L)])
        end
    end

    println("\n" * "="^110)
    println("PREREGISTERED RESULT CHECKS (evaluated on available rows)")
    println("="^110)

    for L in L_GRID
        all(haskey(results, (n, L)) for (n, _) in ARMS) || continue
        ph = results[(:PHASE, L)]
        rg = results[(:REGIME, L)]
        rb = results[(:REGIME_B, L)]
        tg = results[(:TAGR, L)]
        fx = results[(:FIXED, L)]
        @printf("\nL=%d:  PHASE %+ .4f  REGIME %+ .4f  REGIME_B %+ .4f  TAGR %+ .4f  FIXED %+ .4f  (meanGain)\n",
            L, ph.mean_task_gain, rg.mean_task_gain, rb.mean_task_gain, tg.mean_task_gain, fx.mean_task_gain)
        @printf("       pf:   PHASE %.4f  REGIME %.4f  REGIME_B %.4f  TAGR %.4f  FIXED %.4f\n",
            ph.mean_phase_final, rg.mean_phase_final, rb.mean_phase_final, tg.mean_phase_final, fx.mean_phase_final)
        @printf("       melts: PHASE %d  REGIME %d  REGIME_B %d  TAGR %d | commits: PHASE %d  REGIME %d  REGIME_B %d  TAGR %d\n",
            ph.melts_total, rg.melts_total, rb.melts_total, tg.melts_total,
            ph.commits_total, rg.commits_total, rb.commits_total, tg.commits_total)
    end

    # C0 (canary) whenever the baseline row exists.
    if haskey(results, (:PHASE, 150))
        ph150 = results[(:PHASE, 150)]
        c0 = abs(ph150.mean_task_gain - 0.4067f0) <= 1.0f-3 && ph150.melts_total == 218
        @printf("\nC0 canary reproduction (PHASE@150 == E0d committed):   gain %+.4f melts %d  [%s]\n",
            ph150.mean_task_gain, ph150.melts_total, c0 ? "PASS" : "FAIL")
    end

    # R1 whenever the short-window rows exist.
    if all(haskey(results, (n, L)) for (n, L) in ((:REGIME, 15), (:PHASE, 15),
                                                  (:REGIME, 40), (:PHASE, 40)))
        r1 = results[(:REGIME, 15)].mean_task_gain > results[(:PHASE, 15)].mean_task_gain &&
             results[(:REGIME, 40)].mean_task_gain > results[(:PHASE, 40)].mean_task_gain &&
             results[(:REGIME, 15)].mean_task_gain > 0
        @printf("R1 short-window win (REGIME>PHASE at 15 and 40, REGIME(15)>0): %+ .4f/%+.4f vs %+ .4f/%+.4f  [%s]\n",
            results[(:REGIME, 15)].mean_task_gain, results[(:REGIME, 40)].mean_task_gain,
            results[(:PHASE, 15)].mean_task_gain, results[(:PHASE, 40)].mean_task_gain,
            r1 ? "PASS" : "FAIL")
    end

    # R2/R3/R4 whenever the long-window rows exist.
    if all(haskey(results, (n, 150)) for (n, _) in ARMS)
        phg = results[(:PHASE, 150)].mean_task_gain
        rgg = results[(:REGIME, 150)].mean_task_gain
        r2 = rgg >= phg - 0.05f0 * abs(phg)
        @printf("R2 long-window parity (REGIME(150) >= PHASE(150) − 5%%):       %+ .4f vs %+ .4f  [%s]\n",
            rgg, phg, r2 ? "PASS" : "FAIL")

        pm = results[(:PHASE, 150)].melts_total
        rgm = results[(:REGIME, 150)].melts_total
        r3 = abs(rgm - pm) <= 0.15 * pm
        @printf("R3 churn-trace parity (|REGIME−PHASE| melts <= 15%% at 150):   %d vs %d  [%s]\n",
            rgm, pm, r3 ? "PASS" : "FAIL")

        r4 = rgg > results[(:TAGR, 150)].mean_task_gain
        @printf("R4 adaptivity attribution (REGIME(150) > TAGR(150)):           %+ .4f vs %+ .4f  [%s]\n",
            rgg, results[(:TAGR, 150)].mean_task_gain, r4 ? "PASS" : "FAIL")

        same = results[(:REGIME, 150)].mean_task_gain == results[(:REGIME_B, 150)].mean_task_gain &&
               results[(:REGIME, 150)].melts_total == results[(:REGIME_B, 150)].melts_total
        @printf("R6 window parity (REGIME(150) == REGIME_B(150) gain and melts): %s\n",
            same ? "PASS" : "FAIL")
    end

    # R5 whenever the L=15 rows exist.
    if all(haskey(results, (n, 15)) for (n, _) in ARMS)
        rg15 = results[(:REGIME, 15)].mean_task_gain
        rb15 = results[(:REGIME_B, 15)].mean_task_gain
        ph15 = results[(:PHASE, 15)].mean_task_gain
        r5 = rg15 > rb15
        @printf("R5 budget attribution (REGIME(15) > REGIME_B(15) ≈ PHASE(15)): %+ .4f vs %+ .4f (PHASE %+ .4f)  [%s]\n",
            rg15, rb15, ph15, r5 ? "PASS" : "FAIL")
    end
    return results
end

main()
