# ---------------------------------------------------------------------------
# E0 — Phase sweep + diagnostic-liveness probe (continuous FP substrate)
#
# Questions this script answers (preregistered before running):
#
#   Q1 (liveness).  Does a committed (crystallized) region retain a legal path
#                   back to superplastic under sustained load, or does global
#                   crystallization + hardening lock the substrate shut?
#                   Falsification criterion #1 / kill K3.
#
#   Q2 (phase).     Over (yield_up, eta, settle_down, hardening, law), does a
#                   mixed developmental phase exist (bounded churn, learning
#                   progresses, substrate neither frozen nor thrashing)?
#                   Falsification criterion: "no stable mixed phase".
#
#   Q3 (return trip).  On a cyclic task A->B->A, is re-adaptation to A on its
#                   return faster than learning A from scratch? This is the
#                   signature metric of the plasticity-allocation claim: only a
#                   history-preserving mechanism can win it. A reset-style or
#                   amnesiac substrate flatlines at first-visit cost.
#
# Protocol (identical for every grid point):
#   - Stage0MLP(2, 32, 1), material sites = 64, one region.
#   - Task A: X=[1 -1; 1 -1], Y=[1 -1]   (probe task, versioned by E_fixed)
#   - Task B: X=[-1 1; -1 1], Y=[-1 1]   (incompatible mapping)
#   - Stream: 150 ticks A (learn) -> 150 ticks B (learn) -> 150 ticks A (return)
#     No rest phases: the lifecycle's own commit behavior is what we are
#     testing, not a curated load/rest schedule.
#   - Head: Adam lr=0.02 (unchanged). Material: injected-gradient tick,
#     VPS exposure, beta=gamma=0.5.
#
# Metrics per run:
#   lossA1  = mean loss over first 20 ticks of A, visit 1  (cold)
#   lossA3  = mean loss over first 20 ticks of A, visit 2  (return)
#   gain    = lossA1 - lossA3          (>0 means history helped)
#   lossB   = mean loss over first 20 ticks of B       (transfer cost)
#   churn   = total melt+commit events (mixed-phase proxy)
#   liveness= fraction of committed sites that re-melt at least once during B
#             or the A return (K3 detection: 0 under sustained load = lock-in)
#   final   = mean loss over last 20 ticks of A visit 3
# ---------------------------------------------------------------------------

using PlasticWeights
using Statistics
using Printf
using Random

const A_X = Float32[1 -1; 1 -1]
const A_Y = Float32[1 -1]
const B_X = Float32[-1 1; -1 1]
const B_Y = Float32[-1 1]

window_mean(x; k=20) = mean(x[max(1, end - k + 1):end])

function run_point(law_name::Symbol, yield_up::Float32, eta::Float32,
                   settle_down::Float32, hardening::Float32;
                   ticks_per_phase::Int=150, seed::Int=71)
    law = law_name === :bingham ? BinghamInspired(Float32(1e-5)) : NEWTONIAN
    mlp = Stage0MLP(2, 32, 1; feature_size=2, rng_seed=seed)
    N = num_material_sites(mlp)  # 64, single region

    substrate = initialize_fp_seed(N;
        region_size=64,
        yield_up=yield_up,
        settle_down=settle_down,
        eta=eta,
        hardening_increment=hardening,
        epsilon_delta=0.02f0,
        k_yield=2,
        k_settle=2,
    )

    state = initialize_material_training(mlp, substrate)
    recorder = DevelopmentalRecorder()

    config = MaterialTrainingConfig(
        law=law,
        dcp=FIXED_RULE_CONTROLLER,
        policy=VPS(),
        head=AdamConfig(learning_rate=0.02f0),
        beta=0.5f0,
        gamma=0.5f0,
    )

    losses = Float32[]
    phase_of = Int[]           # 1 = A1, 2 = B, 3 = A2 (return)
    superplastic_trace = Int[]
    retention_trace = Float32[]   # A-task loss evaluated (read-only) during B

    for tick in 1:(3 * ticks_per_phase)
        X, Y, phase = tick <= ticks_per_phase ? (A_X, A_Y, 1) :
                      tick <= 2 * ticks_per_phase ? (B_X, B_Y, 2) :
                      (A_X, A_Y, 3)
        material_training_step!(mlp, state, X, Y, config; recorder=recorder)
        pred = material_predict(mlp, state, X, VPS())
        push!(losses, 0.5f0 * sum(abs2, pred .- Y) / length(Y))
        push!(phase_of, phase)
        push!(superplastic_trace, count(s -> s.allocated && s.superplastic, state.substrate.sites))
        if phase == 2 && (tick - ticks_per_phase) % 10 == 0
            predA = material_predict(mlp, state, A_X, VPS())
            push!(retention_trace, 0.5f0 * sum(abs2, predA .- A_Y) / length(A_Y))
        end
    end

    first20(v) = mean(v[1:20])
    A1 = view(losses, 1:ticks_per_phase)
    Bv = view(losses, ticks_per_phase+1:2*ticks_per_phase)
    A2 = view(losses, 2*ticks_per_phase+1:3*ticks_per_phase)

    lossA1 = first20(A1)
    lossA3 = first20(A2)
    lossB  = first20(Bv)
    final  = window_mean(losses; k=20)

    summary = summarize_events(recorder)

    # Liveness: distinct sites that re-melted after having committed at least
    # once. The recorder gives us event streams; a site that melted during B or
    # A2 had to have been committed before (all sites commit eventually in the
    # seed; liveness = any melt activity after tick ticks_per_phase).
    post_seed_melts = count(e -> e isa FPMeltEvent && event_tick(e) > ticks_per_phase, recorder.events)

    n_super_final = superplastic_trace[end]
    melts_total = summary.melt_count
    commits_total = summary.commit_count

    # Entry losses: exact boundary ticks, before any learning in the new phase.
    entryB  = losses[ticks_per_phase + 1]      # first tick of B
    entryA3 = losses[2 * ticks_per_phase + 1]  # first tick of A return

    # Phase classification (honest labels):
    #   uncommitted  — substrate never consolidated under this schedule
    #                  (network never became functional; distinct from runaway)
    #   frozen       — fully committed, no post-seed melts, no plastic capacity
    #   consolidated — committed with residual plastic sites, but no re-melts
    #                  ("one-shot warm-up", NOT a dynamically mixed phase)
    #   mixed        — ongoing lifecycle churn after seed (post-seed melts > 0)
    #   runaway      — sustained high churn with majority plastic
    phase_class = if melts_total == 0 && commits_total == 0
        :uncommitted
    elseif post_seed_melts > 0
        n_super_final > 32 ? :runaway : :mixed
    elseif n_super_final == 0
        :frozen
    else
        :consolidated
    end

    return (
        law=law_name,
        yield_up=yield_up,
        eta=eta,
        settle_down=settle_down,
        hardening=hardening,
        lossA1=lossA1,
        lossA3=lossA3,
        gain=lossA1 - lossA3,
        entryB=entryB,
        entryA3=entryA3,
        asym=entryB - entryA3,   # >0: return re-adapts faster than fresh task
        lossB=lossB,
        final=final,
        churn=melts_total + commits_total,
        melts=melts_total,
        commits=commits_total,
        retention_mean=isempty(retention_trace) ? NaN32 : mean(retention_trace),
        retention_last=isempty(retention_trace) ? NaN32 : retention_trace[end],
        hardening_total=summary.total_hardening,
        post_seed_melts=post_seed_melts,
        super_final=n_super_final,
        phase=phase_class,
    )
end

function main()
    println("="^78)
    println("E0 — FP viscoplastic substrate: phase sweep + liveness + return trip")
    println("="^78)
    printf_row(r) = @printf("%-8s τ=%7.3f η=%6.2f σ=%6.3f h=%6.4f | A1=%7.4f A3=%7.4f eB=%7.4f eA3=%7.4f asym=%+7.4f fin=%7.4f | m=%3d c=%3d ret=%6.3f ★end=%2d %s\n",
        r.law, r.yield_up, r.eta, r.settle_down, r.hardening,
        r.lossA1, r.lossA3, r.entryB, r.entryA3, r.asym, r.final,
        r.melts, r.commits, r.retention_mean, r.super_final, String(r.phase))

    header = @sprintf("%-8s %9s %9s %9s %9s | %9s %9s %9s %9s %9s | %8s %5s %6s %s",
        "law", "yield", "eta", "settle", "hard", "lossA1", "lossA3", "gain", "lossB", "final", "churn", "live", "★end", "phase")
    println(header)
    println("-"^length(header))

    results = []

    # Grid: coarse, chosen to span "yield binds immediately" .. "yield never binds"
    yields  = Float32[0.001, 0.01, 0.05, 0.2, 1.0, 10.0]
    etas    = Float32[0.1, 1.0, 10.0]
    settles = Float32[0.005, 0.05]
    hards   = Float32[0.001, 0.01]

    for law in (:bingham, :newtonian)
        for y in yields, e in etas, s in settles, h in hards
            s < y || continue  # region invariant: yield_up must exceed settle_down
            r = run_point(law, y, e, s, h)
            push!(results, r)
            printf_row(r)
        end
    end

    println("\n" * "="^78)
    println("AGGREGATE — by (law, hardening), best final-loss points")
    println("="^78)
    for law in (:bingham, :newtonian), h in hards
        pts = filter(r -> r.law == law && r.hardening == h, results)
        sort!(pts; by=r -> r.final)
        println("\n[$(law), hardening=$(h)] top 5 by final loss:")
        for r in pts[1:min(5, end)]
            @printf("  τ=%7.3f η=%7.3f σ=%7.3f | A1=%7.4f A3=%7.4f gain=%+7.4f fin=%7.4f churn=%4d live=%3d %s\n",
                r.yield_up, r.eta, r.settle_down, r.lossA1, r.lossA3, r.gain, r.final, r.churn, r.post_seed_melts, String(r.phase))
        end
    end

    println("\n" * "="^78)
    println("VERDICT CHECKS (preregistered)")
    println("="^78)

    # Q1 liveness: any lifecycle churn at all after the seed commits?
    live_pts  = filter(r -> r.post_seed_melts > 0, results)
    @printf("Points with post-seed melt activity (LIVENESS):  %d / %d\n", length(live_pts), length(results))

    # Phase census
    for ph in (:uncommitted, :frozen, :consolidated, :mixed, :runaway)
        pts = filter(r -> r.phase == ph, results)
        @printf("%-13s points:  %d / %d\n", String(ph), length(pts), length(results))
    end

    # Q3 return trip: among points that learned, is the warm-state asymmetry real?
    learners = filter(r -> r.final < 0.1, results)
    @printf("Points that learned the task (final < 0.1):      %d / %d\n", length(learners), length(results))
    if !isempty(learners)
        for r in learners
            @printf("  τ=%7.3f η=%6.2f σ=%6.3f | entryB=%7.4f entryA3=%7.4f asym=%+7.4f | ret_mean(A during B)=%6.3f ret_last=%6.3f\n",
                r.yield_up, r.eta, r.settle_down, r.entryB, r.entryA3, r.asym, r.retention_mean, r.retention_last)
        end
    end
end

main()
