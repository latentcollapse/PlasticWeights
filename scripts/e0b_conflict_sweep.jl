# ---------------------------------------------------------------------------
# E0b — Phase sweep on a symmetry-safe CONFLICTING task family
#
# What changed vs e0_phase_sweep.jl and why (preregistered before running):
#
#   FAULT FOUND IN E0: task A and task B were the same function with the two
#   batch samples swapped. There was no conflict, so the liveness question
#   (does a committed region ever re-melt under persistent contradicting
#   load?) was never actually tested. E0's static-load findings stand
#   (66/96 never commit; 0/96 re-melt under static load); K3 was untested.
#
#   Task family v2 (symmetry-safe):
#     X shared: [1 0 -1; 1 0 -1]  (three non-antipodal samples)
#     Y_A = [1 0 -1; -1 0 1]      (odd function)
#     Y_B = [-1 0 1; 1 0 -1]      (label swap; Y_B = -Y_A)
#   The material layer W (feature 2x2) is identical across tasks, so no
#   feature remapping can absorb the swap. Only the head H (2x2, trained by
#   Adam) could absorb it — and it cannot: absorbing a swap means H must
#   implement the permutation [2 1] on hidden units AND negate, and
#   [2 1] != -[2 1] with tanh an odd function. A and B are jointly
#   unrealizable by the linear head. Conflict is structural.
#
#   Protocol per grid point: A (150) -> B (150) -> A (150). No rest phases.
#   The substrate's own lifecycle is the only source of non-stationarity
#   beyond the task switches.
#
# Metrics:
#   entryB / entryA3  — exact boundary-tick losses from matched warm states.
#   asym = entryB - entryA3 — >0 means re-adapting to A (return) is faster
#                       than adapting to a fresh conflicting task B.
#   ret_mean / ret_last — A loss evaluated (read-only) during B: forgetting.
#   melts_by_phase   — distinct-site melt census per phase (liveness = melts
#                      in phases 2/3, i.e., AFTER the A1 consolidation wave).
#   churn, phase class, final loss as before.
# ---------------------------------------------------------------------------

using PlasticWeights
using Statistics
using Printf

const X = Float32[1 0 -1; 1 0 -1]
const YA = Float32[1 0 -1; -1 0 1]
const YB = Float32[-1 0 1; 1 0 -1]

window_mean(x; k=20) = mean(x[max(1, end - k + 1):end])

function run_point(law_name::Symbol, yield_up::Float32, eta::Float32,
                   settle_down::Float32, hardening::Float32;
                   ticks_per_phase::Int=150, seed::Int=71)
    law = law_name === :bingham ? BinghamInspired(Float32(1e-5)) : NEWTONIAN
    mlp = Stage0MLP(2, 32, 2; feature_size=2, rng_seed=seed)
    N = num_material_sites(mlp)

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

    T = 3 * ticks_per_phase
    losses = Float32[]
    superplastic_trace = Int[]
    retention_trace = Float32[]
    melted_sites = [Set{Int}(), Set{Int}(), Set{Int}()]  # distinct sites per phase

    for tick in 1:T
        phase = tick <= ticks_per_phase ? 1 :
                tick <= 2 * ticks_per_phase ? 2 : 3
        Y = phase == 2 ? YB : YA
        material_training_step!(mlp, state, X, Y, config; recorder=recorder)

        pred = material_predict(mlp, state, X, VPS())
        push!(losses, 0.5f0 * sum(abs2, pred .- Y) / length(Y))
        push!(superplastic_trace, count(s -> s.allocated && s.superplastic, state.substrate.sites))

        if phase == 2 && (tick - ticks_per_phase) % 10 == 0
            predA = material_predict(mlp, state, X, VPS())
            push!(retention_trace, 0.5f0 * sum(abs2, predA .- YA) / length(YA))
        end
    end

    # Distinct-site melt census per phase from the event stream.
    for e in recorder.events
        if e isa FPMeltEvent
            t = event_tick(e)
            phase = t <= ticks_per_phase ? 1 : t <= 2 * ticks_per_phase ? 2 : 3
            push!(melted_sites[phase], event_site(e))
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

    entryB  = losses[ticks_per_phase + 1]
    entryA3 = losses[2 * ticks_per_phase + 1]

    summary = summarize_events(recorder)
    melts_total = summary.melt_count
    commits_total = summary.commit_count
    post_seed_melts = length(melted_sites[2]) + length(melted_sites[3])

    n_super_final = superplastic_trace[end]

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
        law=law_name, yield_up=yield_up, eta=eta,
        settle_down=settle_down, hardening=hardening,
        lossA1=lossA1, lossA3=lossA3, gain=lossA1 - lossA3,
        entryB=entryB, entryA3=entryA3, asym=entryB - entryA3,
        lossB=lossB, final=final,
        melts=melts_total, commits=commits_total,
        melts_p2=length(melted_sites[2]), melts_p3=length(melted_sites[3]),
        retention_mean=isempty(retention_trace) ? NaN32 : mean(retention_trace),
        retention_last=isempty(retention_trace) ? NaN32 : retention_trace[end],
        post_seed_melts=post_seed_melts,
        super_final=n_super_final,
        phase=phase_class,
    )
end

function main()
    println("="^100)
    println("E0b — FP viscoplastic substrate: CONFLICTING task family (A→B→A), symmetry-safe")
    println("="^100)
    header = @sprintf("%-8s %7s %6s %6s %7s | %7s %7s %7s %7s %7s %7s | %5s %5s %5s %6s %6s %6s %s",
        "law", "yield", "eta", "settle", "hard",
        "lossA1", "lossA3", "entryB", "entryA3", "asym", "final",
        "m", "mB", "mA3", "retMn", "retL", "★end", "phase")
    println(header)
    println("-"^length(header))

    results = []

    yields  = Float32[0.001, 0.01, 0.05, 0.2, 1.0, 10.0]
    etas    = Float32[0.1, 1.0, 10.0]
    settles = Float32[0.005, 0.05]
    hards   = Float32[0.001, 0.01]

    for law in (:bingham, :newtonian)
        for y in yields, e in etas, s in settles, h in hards
            s < y || continue
            r = run_point(law, y, e, s, h)
            push!(results, r)
            @printf("%-8s %7.3f %6.2f %6.3f %7.4f | %7.4f %7.4f %7.4f %7.4f %+7.4f %7.4f | %5d %5d %5d %6.3f %6.3f %6d %s\n",
                r.law, r.yield_up, r.eta, r.settle_down, r.hardening,
                r.lossA1, r.lossA3, r.entryB, r.entryA3, r.asym, r.final,
                r.melts, r.melts_p2, r.melts_p3, r.retention_mean, r.retention_last,
                r.super_final, String(r.phase))
        end
    end

    println("\n" * "="^100)
    println("BEST LEARNERS (final < 0.15), sorted by final loss")
    println("="^100)
    learners = filter(r -> r.final < 0.15, results)
    sort!(learners; by=r -> r.final)
    for r in learners
        @printf("%-8s τ=%7.3f η=%6.2f σ=%6.3f h=%6.4f | A3=%7.4f entryB=%7.4f entryA3=%7.4f asym=%+7.4f | mB=%2d mA3=%2d ret=%6.3f→%6.3f %s\n",
            r.law, r.yield_up, r.eta, r.settle_down, r.hardening,
            r.lossA3, r.entryB, r.entryA3, r.asym,
            r.melts_p2, r.melts_p3, r.retention_mean, r.retention_last, String(r.phase))
    end

    println("\n" * "="^100)
    println("VERDICT CHECKS (preregistered)")
    println("="^100)

    live = filter(r -> r.post_seed_melts > 0, results)
    @printf("LIVENESS (post-seed distinct-site re-melts):     %d / %d\n", length(live), length(results))
    for ph in (:uncommitted, :frozen, :consolidated, :mixed, :runaway)
        pts = filter(r -> r.phase == ph, results)
        @printf("%-13s points:  %d / %d\n", String(ph), length(pts), length(results))
    end

    learned = filter(r -> r.final < 0.15, results)
    @printf("Points that learn the task (final < 0.15):       %d / %d\n", length(learned), length(results))
    if !isempty(learned)
        asyms = [r.asym for r in learned]
        @printf("Return-trip asymmetry among learners: min=%+.4f median=%+.4f max=%+.4f; positive: %d/%d\n",
            minimum(asyms), median(asyms), maximum(asyms), count(>(0), asyms), length(asyms))
    end

    # K3: persistent contradiction must eventually reopen structure.
    # Look specifically at points where B was actually being learned
    # (final < 0.15 requires B learning) but no site ever re-melted.
    k3_violations = filter(r -> r.final < 0.15 && r.post_seed_melts == 0, results)
    @printf("K3 violation candidates (learned B but zero re-melts): %d\n", length(k3_violations))
end

main()
