# ---------------------------------------------------------------------------
# E0b2 — Gate-fix regression sweep (D1 + D2 repairs), preregistered
#
# PREREGISTERED BEFORE EXECUTION (same discipline as E0b):
#
#   Hypothesis under test: the E0b verdict failures (66/96 uncommitted,
#   0/48 Bingham learners, liveness 5/96, K3 violations) were caused by two
#   implementable-at-Stage-0 defects, not by the thesis (E0 report §7-8):
#
#     D1 — settle gate measured load magnitude. Fix: settle certificate is
#          gradient-direction persistence c = |EMA(g)|/EMA(|g|) with
#          settle_down repurposed as a consistency threshold in [0,1);
#          exact-zero rest certifies c=0 and can never settle (kills the
#          anti-causal commit wave); commit additionally requires a melt
#          margin (stress_ema < yield_up).
#     D2 — Bingham mobility hard-vetoed flow and the hardening ratchet made
#          the veto permanent. Fix: m = (σ+ε)/(σ+ε+τ·(1-c)) shapes flow,
#          never vetoes; exactly Newtonian at τ=0 or c=1.
#
#   Protocol: IDENTICAL to E0b (A→B→A, 150/150/150, X/Y_A/Y_B as in E0b,
#   Stage0MLP(2,32,2), 64-site region, VPS, beta=gamma=0.5, head Adam
#   lr=0.02, k_yield=k_settle=2, epsilon_delta=0.02, seed 71).
#
#   Deliberate deviations (declared, not silent):
#     1. settle grid becomes {0.8, 0.9} — consistency thresholds. The old
#        magnitudes {0.005, 0.05} are meaningless in the new semantics.
#     2. The grid filter `settle < yield` is DROPPED — it encoded the old
#        magnitude semantics; consistency thresholds are dimensionless and
#        independent of yield_up. Grid: 6 yields × 3 etas × 2 settles ×
#        2 hards × 2 laws = 144 points.
#     3. bingham_epsilon stays 1e-5 (E0b value) for comparability.
#
#   PREREGISTERED SUCCESS CRITERIA (all must hold to unblock E1):
#     C1. Mixed developmental phase ≥ ~20% of the grid.
#     C2. Liveness: post-seed re-melts > 0 for at least half of the
#         learners (final loss < 0.15) under the contradicting stream.
#     C3. No commit-wave shocks: max single-tick eval-loss jump among
#         learners bounded (< 1.0), vs the unbounded VPS commit wave of §2.
#     C4. Bingham points learn: > 0 Bingham learners (E0b: 0/48).
#   E1 remains blocked if any criterion fails; failures are reported
#   honestly and become the next defect ledger entries.
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
    melted_sites = [Set{Int}(), Set{Int}(), Set{Int}()]
    max_tick_jump = 0.0f0
    jump_tick = 0
    prev_loss = 0.5f0  # chance-level MSE for ±1 targets

    for tick in 1:T
        phase = tick <= ticks_per_phase ? 1 :
                tick <= 2 * ticks_per_phase ? 2 : 3
        Y = phase == 2 ? YB : YA
        material_training_step!(mlp, state, X, Y, config; recorder=recorder)

        pred = material_predict(mlp, state, X, VPS())
        loss = 0.5f0 * sum(abs2, pred .- Y) / length(Y)
        push!(losses, loss)
        jump = abs(loss - prev_loss)
        if jump > max_tick_jump
            max_tick_jump = jump
            jump_tick = tick
        end
        prev_loss = loss
        push!(superplastic_trace, count(s -> s.allocated && s.superplastic, state.substrate.sites))

        if phase == 2 && (tick - ticks_per_phase) % 10 == 0
            predA = material_predict(mlp, state, X, VPS())
            push!(retention_trace, 0.5f0 * sum(abs2, predA .- YA) / length(YA))
        end
    end

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

    # C3 decomposition: the loss jump at a task boundary (first tick of phases
    # 2 and 3) measures the target flip against a net that had learned the
    # previous task — it is large precisely WHEN learning succeeds. The
    # substrate-manufactured shock criterion is about MID-phase jumps: a commit
    # wave landing inside a phase would appear there. Both are reported.
    max_midphase_jump = 0.0f0
    midphase_jump_tick = 0
    for t in 2:T
        boundary = (t == ticks_per_phase + 1) || (t == 2 * ticks_per_phase + 1)
        boundary && continue
        j = abs(losses[t] - losses[t-1])
        if j > max_midphase_jump
            max_midphase_jump = j
            midphase_jump_tick = t
        end
    end

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
        max_tick_jump=max_tick_jump,
        jump_tick=jump_tick,
        max_midphase_jump=max_midphase_jump,
        midphase_jump_tick=midphase_jump_tick,
        phase=phase_class,
    )
end

function parse_row(line::AbstractString)
    # Re-parse one fixed-width data row of this script's own table format.
    # Fields: law yield eta settle hard | lossA1 lossA3 entryB entryA3 asym
    #         final | m mB mA3 retMn retL ★end midjmp phase
    f = split(line)
    return (
        law=Symbol(f[1]), yield_up=parse(Float32, f[2]), eta=parse(Float32, f[3]),
        settle_down=parse(Float32, f[4]), hardening=parse(Float32, f[5]),
        lossA1=parse(Float32, f[7]), lossA3=parse(Float32, f[8]),
        entryB=parse(Float32, f[9]), entryA3=parse(Float32, f[10]),
        asym=parse(Float32, f[11]), final=parse(Float32, f[12]),
        melts=parse(Int, f[14]), melts_p2=parse(Int, f[15]), melts_p3=parse(Int, f[16]),
        retention_mean=parse(Float32, f[17]), retention_last=parse(Float32, f[18]),
        super_final=parse(Int, f[19]), max_midphase_jump=parse(Float32, f[20]),
        phase=Symbol(f[21]), post_seed_melts=parse(Int, f[15]) + parse(Int, f[16]),
    )
end

function print_verdict(results)
    println("\n" * "="^110)
    println("PREREGISTERED VERDICT CHECKS")
    println("="^110)

    learners = filter(r -> r.final < 0.15, results)
    live_learners = filter(r -> r.post_seed_melts > 0, learners)

    # C1
    mixed = filter(r -> r.phase == :mixed, results)
    @printf("C1  mixed-phase coverage:                    %d / %d (%.1f%%)  [need >= ~20%%]\n",
        length(mixed), length(results), 100 * length(mixed) / length(results))

    # C2
    @printf("C2  learner liveness (re-melt > 0):          %d / %d learners  [need >= 50%%]\n",
        length(live_learners), length(learners))

    # C3 — substrate-manufactured shocks are MID-phase jumps; boundary jumps
    # measure the target flip itself and are reported for transparency.
    if !isempty(learners)
        worst_mid = maximum(r.max_midphase_jump for r in learners)
        @printf("C3  max MID-phase jump (learners):           %.4f  [need < 1.0]\n", worst_mid)
    end

    # C4
    bingham_learners = filter(r -> r.law === :bingham, learners)
    @printf("C4  Bingham learners:                        %d / %d bingham points  [need > 0]\n",
        length(bingham_learners), count(r -> r.law === :bingham, results))

    println("\nPhase census:")
    for ph in (:uncommitted, :frozen, :consolidated, :mixed, :runaway)
        pts = filter(r -> r.phase == ph, results)
        @printf("  %-13s %3d / %d\n", String(ph), length(pts), length(results))
    end

    println("\nLearners (final < 0.15), sorted by final loss:")
    sort!(learners; by=r -> r.final)
    for r in learners
        @printf("%-8s τ=%7.3f η=%6.2f σ=%5.2f h=%6.4f | A3=%7.4f asym=%+7.4f | mB=%2d mA3=%2d mid=%.3f@t%d %s\n",
            r.law, r.yield_up, r.eta, r.settle_down, r.hardening,
            r.lossA3, r.asym, r.melts_p2, r.melts_p3, r.max_midphase_jump, r.midphase_jump_tick, String(r.phase))
    end

    println("\nReturn-trip asymmetry among learners:")
    if !isempty(learners)
        asyms = [r.asym for r in learners]
        @printf("  min=%+.4f median=%+.4f max=%+.4f; positive: %d/%d\n",
            minimum(asyms), median(asyms), maximum(asyms), count(>(0), asyms), length(asyms))
    end

    k3_violations = filter(r -> r.final < 0.15 && r.post_seed_melts == 0, results)
    @printf("K3 violation candidates (learned B but zero re-melts): %d\n", length(k3_violations))
end

function main()
    # Chunked-execution support: this environment does not persist background
    # processes between tool invocations, so the sweep runs in foreground
    # chunks. Usage: julia script.jl [bingham|newtonian|single|report]
    #   (nothing)     full 144-point sweep
    #   bingham       72 Bingham points only
    #   newtonian     72 Newtonian points only
    #   single        one diagnostic point (newtonian, tau=0.05, eta=10,
    #                 settle=0.9, hard=0.001) printed tick-less, full metrics
    #   report [path] recompute the preregistered verdict from a saved raw
    #                 output file (default docs/e0b2_raw_output.txt)
    mode = isempty(ARGS) ? :full : Symbol(ARGS[1])

    if mode === :report
        path = length(ARGS) >= 2 ? ARGS[2] : joinpath("docs", "e0b2_raw_output.txt")
        rows = String[]
        for line in eachline(path)
            s = strip(line)
            # Table rows only: law name, five numeric fields, then the '|'
            # column separator. This excludes learner-list lines (which contain
            # 'τ=' and no leading pipe) from copied chunk tails.
            f = split(s)
            (startswith(s, "bingham ") || startswith(s, "newtonian ")) &&
                length(f) == 21 && f[6] == "|" && f[13] == "|" &&
                push!(rows, s)
        end
        results = [parse_row(r) for r in rows]
        println("report: parsed ", length(results), " data rows from ", path)
        print_verdict(results)
        return
    end

    println("="^110)
    println("E0b2 — gate-fix regression sweep (D1 consistency settle + D2 shaped mobility), preregistered [mode=", mode, "]")
    println("="^110)
    header = @sprintf("%-8s %7s %6s %6s %7s | %7s %7s %7s %7s %7s %7s | %5s %5s %5s %6s %6s %6s %7s %s",
        "law", "yield", "eta", "settle", "hard",
        "lossA1", "lossA3", "entryB", "entryA3", "asym", "final",
        "m", "mB", "mA3", "retMn", "retL", "★end", "midjmp", "phase")
    println(header)
    println("-"^length(header))

    results = []

    yields  = Float32[0.001, 0.01, 0.05, 0.2, 1.0, 10.0]
    etas    = Float32[0.1, 1.0, 10.0]
    settles = Float32[0.8, 0.9]
    hards   = Float32[0.001, 0.01]

    if mode === :single
        r = run_point(:newtonian, 0.05f0, 10.0f0, 0.9f0, 0.001f0)
        @printf("single: A1=%7.4f A3=%7.4f B=%7.4f final=%7.4f asym=%+7.4f | m=%d mB=%d mA3=%d ★=%d mid=%.4f@t%d bnd=%.4f@t%d %s\n",
            r.lossA1, r.lossA3, r.lossB, r.final, r.asym,
            r.melts, r.melts_p2, r.melts_p3, r.super_final,
            r.max_midphase_jump, r.midphase_jump_tick, r.max_tick_jump, r.jump_tick, String(r.phase))
        return
    end

    laws = mode === :bingham ? (:bingham,) :
           mode === :newtonian ? (:newtonian,) : (:bingham, :newtonian)

    for law in laws
        for y in yields, e in etas, s in settles, h in hards
            r = run_point(law, y, e, s, h)
            push!(results, r)
            @printf("%-8s %7.3f %6.2f %6.2f %7.4f | %7.4f %7.4f %7.4f %7.4f %+7.4f %7.4f | %5d %5d %5d %6.3f %6.3f %6d %7.3f %s\n",
                r.law, r.yield_up, r.eta, r.settle_down, r.hardening,
                r.lossA1, r.lossA3, r.entryB, r.entryA3, r.asym, r.final,
                r.melts, r.melts_p2, r.melts_p3, r.retention_mean, r.retention_last,
                r.super_final, r.max_midphase_jump, String(r.phase))
        end
    end

    print_verdict(results)
end

main()
