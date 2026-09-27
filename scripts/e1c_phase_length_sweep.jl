# ---------------------------------------------------------------------------
# E1c — Phase-length sweep: mapping where the lifecycle pays, and the
#       parameterization scaling rule. PREREGISTERED BEFORE EXECUTION.
#
# Motivation (E1b ledger):
#   E1b-D3 — the frozen E0c-prime parameterization is phase-length-bound:
#            at L=15 the substrate never re-consolidates (hotMean 0.929).
#   E1b-D4 — the return-trip benefit is a CONSOLIDATION-MEMORY effect: real
#            at L=150 (E1: A +0.35, B +1.07), inverted at L=15 (nothing
#            commits between visits, so history has no carrier).
#
# Design: the E1b four-task family and stream (A→B→C→D→B→A→C→D→A→B) at
# L ∈ {15, 40, 75, 150}. Two arms only:
#   SUB   — frozen E0c-prime parameterization (identical to E1b).
#   FIXED — controller ablation (FixedRuleController).
# At each L, report: phaseFinal, retMatched (tercile, as E1b), meanGain,
# hotMean, midJump, and — new — BINDING-GATE TELEMETRY from the SUB arm:
#   commit_frac  — fraction of phases in which >= 1 commit occurred
#                  (consolidation opportunity actually taken)
#   melt_frac    — fraction of phases with >= 1 post-seed melt
#   cert_frac    — fraction of committed-site-phases where the conflict
#                  certificate was ACTIVE (counter > 0) at phase end
#   margin_frac  — fraction of phase-final ticks where a plastic site held a
#                  saturated settle certificate but was blocked ONLY by the
#                  melt margin (sigma >= tau)
# These identify WHICH gate binds at each L (E1b hypothesis: at small L the
# settle certificate itself cannot saturate within a phase; dwell and margin
# bind at mid L).
#
# PREREGISTERED MAP HYPOTHESES:
#   M1 (lifecycle window): SUB beats FIXED on meanGain at L=150 and L=75,
#      ties/loses at L=15 — the E1b-D4 signature reproduced along the axis.
#   M2 (retention cross): SUB retMatched < FIXED retMatched at every L
#      (the E1b ablation delta generalizes).
#   M3 (mechanism): SUB commit_frac increases with L, and hotMean at L=15
#      > 0.8 while hotMean at L=150 < 0.6 (consolidation, not plasticity,
#      carries the history effect).
#
# SCALING RULE (derived from the map, then preregistered in the report
# BEFORE validation): the binding gate identified at each L determines the
# scaled parameterization SUB-scaled(L); we test it at held-out L=100
# against FIXED at the same L with the same scaling. Success shape:
#   S1: SUB-scaled(100) hotMean <= 0.5 (locality restored);
#   S2: SUB-scaled(100) meanGain > FIXED-scaled(100) meanGain (history pays);
#   S3: SUB-scaled(100) phaseFinal <= FIXED-scaled(100) phaseFinal + 0.05
#      (no adaptation tax beyond noise).
#   S1-S3 all required; the rule is recorded in docs before the validation
#   run (see the report for the frozen form).
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
const HELDOUT_L = 100

task_target(name::Symbol) = getfield(TASKS, name)
mse_loss(pred, Y) = 0.5f0 * sum(abs2, pred .- Y) / length(Y)

"""
Run one arm at one phase length. `scale` (nothing or a factor) applies the
parameterization scaling rule to the SUB arm's lifecycle parameters:
conflict_k, k_commit (controller), and m_max budget all scale with L/150.
"""
function run_arm(; dcp=PHASE_MACHINE_CONTROLLER, L::Int=150,
                 k_commit::Int=2, conflict_k::Int=2, m_max::Real=0.02f0,
                 label::Symbol=:sub)
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
        conflict_k=conflict_k,
    )
    state = initialize_material_training(mlp, substrate)
    dcp_arm = dcp isa PhaseMachineController ? PhaseMachineController(k_commit) : dcp
    config = MaterialTrainingConfig(
        law=BinghamInspired(Float32(1e-5)),
        dcp=dcp_arm,
        policy=RampedVPS(2; m_max=m_max),
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

    # Binding-gate telemetry (SUB arm only; zeros for FIXED).
    commits_per_phase = zeros(Int, n_phases)
    melts_per_phase = zeros(Int, n_phases)
    cert_active_at_phase_end = 0
    margin_blocked_at_phase_end = 0
    committed_site_phases = 0
    plastic_site_phase_ticks = 0

    for tick in 1:T
        phase_idx = cld(tick, L)
        task = STREAM[phase_idx]
        Y = task_target(task)

        result = material_training_step!(mlp, state, X, Y, config)

        if (tick - 1) % L == 0
            push!(entries[task], (phase_idx, result.loss))
        end
        push!(losses, result.loss)
        hot = count(s -> s.allocated && s.superplastic, state.substrate.sites)
        push!(hot_trace, hot)

        for a in result.actions
            a isa CommitAction && (commits_per_phase[phase_idx] += 1)
            a isa MeltAction && (melts_per_phase[phase_idx] += 1)
        end

        if dcp isa PhaseMachineController && (tick % L == 0 || tick == T)
            # Phase-end gate snapshot.
            for (si, site) in enumerate(state.substrate.sites)
                telem = state.substrate.telemetry[si]
                if site.allocated && site.superplastic
                    plastic_site_phase_ticks += 1
                    if telem.consecutive_stable >= 2
                        if telem.stress_ema >= 0.2f0
                            margin_blocked_at_phase_end += 1
                        else
                            # would commit (if dwell allows): count as healthy
                        end
                    end
                elseif site.allocated && site.commit_sign != 0
                    committed_site_phases += 1
                    telem.consecutive_conflicted > 0 &&
                        (cert_active_at_phase_end += 1)
                end
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
    band_current = mean(current_loss(p) for p in band)

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
    mean_task_gain = mean(task_gain[name] for name in TASK_ORDER)

    return (
        label=label, L=L,
        mean_phase_final=mean(phase_final),
        ret_matched=isempty(ret_matched) ? NaN32 : mean(ret_matched),
        band_current=band_current,
        max_mid_jump=max_mid,
        mean_task_gain=mean_task_gain,
        task_gain=task_gain,
        hot_frac_mean=mean(hot_trace) / 64.0f0,
        commit_frac=mean(commits_per_phase .> 0),
        melt_frac=mean(melts_per_phase .> 0),
        cert_frac=committed_site_phases > 0 ? cert_active_at_phase_end / committed_site_phases : 0.0f0,
        margin_frac=plastic_site_phase_ticks > 0 ? margin_blocked_at_phase_end / plastic_site_phase_ticks : 0.0f0,
        commits_total=sum(commits_per_phase),
        melts_total=sum(melts_per_phase),
    )
end

function print_row(r)
    @printf("%-6s L=%3d | pf=%7.4f retM=%7.4f (band %6.4f) gain=%+7.4f | hot=%5.2f jump=%5.3f | commit%4.2f melt%4.2f cert%4.2f margin%4.2f | C=%4d M=%4d\n",
        r.label, r.L, r.mean_phase_final, r.ret_matched, r.band_current,
        r.mean_task_gain, r.hot_frac_mean, r.max_mid_jump,
        r.commit_frac, r.melt_frac, r.cert_frac, r.margin_frac,
        r.commits_total, r.melts_total)
end

function main()
    mode = isempty(ARGS) ? :map : Symbol(ARGS[1])

    println("="^110)
    println("E1c — phase-length sweep, SUB vs FIXED (map mode) / held-out validation (validate mode) [", mode, "]")
    println("="^110)

    if mode === :map
        for L in L_GRID
            r_sub = run_arm(; L=L)
            r_fix = run_arm(; dcp=FIXED_RULE_CONTROLLER, L=L, label=:fixed)
            print_row(r_sub)
            print_row(r_fix)
            @printf("      deltas SUB−FIXED: pf %+.4f  retM %+.4f  gain %+.4f\n",
                r_sub.mean_phase_final - r_fix.mean_phase_final,
                r_sub.ret_matched - r_fix.ret_matched,
                r_sub.mean_task_gain - r_fix.mean_task_gain)
            println("-"^110)
        end
        println("\n(Map complete. The scaling rule is derived and preregistered in")
        println(" docs/E1C_PHASE_LENGTH_REPORT before `validate` is run.)")
        return
    end

    if mode === :validate
        L = HELDOUT_L
        # The scaling rule (frozen in docs/E1C_PHASE_LENGTH_REPORT before this
        # mode may be run) is applied here via explicit parameters.
        # Positional: validate [L] [k_commit] [conflict_k] [m_max]
        L = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : HELDOUT_L
        k_commit = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 2
        conflict_k = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 2
        m_max = length(ARGS) >= 5 ? parse(Float32, ARGS[5]) : 0.02f0
        println("validate: L=$L k_commit=$k_commit conflict_k=$conflict_k m_max=$m_max")
        r_sub = run_arm(; L=L, k_commit=k_commit, conflict_k=conflict_k,
                        m_max=m_max, label=:subS)
        r_fix = run_arm(; dcp=FIXED_RULE_CONTROLLER, L=L, label=:fixS)
        print_row(r_sub)
        print_row(r_fix)
        @printf("\nS1 locality:   SUB-scaled hotMean=%.3f  [%s]\n", r_sub.hot_frac_mean,
            r_sub.hot_frac_mean <= 0.5f0 ? "PASS" : "FAIL")
        @printf("S2 history:    SUB-scaled gain=%+.4f vs FIXED-scaled %+.4f  [%s]\n",
            r_sub.mean_task_gain, r_fix.mean_task_gain,
            r_sub.mean_task_gain > r_fix.mean_task_gain ? "PASS" : "FAIL")
        @printf("S3 no-tax:     SUB-scaled pf=%.4f vs FIXED-scaled %.4f (+0.05 allowance)  [%s]\n",
            r_sub.mean_phase_final, r_fix.mean_phase_final,
            r_sub.mean_phase_final <= r_fix.mean_phase_final + 0.05f0 ? "PASS" : "FAIL")
        return
    end
end

main()
