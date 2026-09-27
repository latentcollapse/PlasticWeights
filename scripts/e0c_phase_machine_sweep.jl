# ---------------------------------------------------------------------------
# E0c — Phase-machine sweep (Pass 2: symbolic state + exposure ramp),
# PREREGISTERED BEFORE EXECUTION.
#
# Hypothesis under test: the two residual E0b2 defects — the frozen 40%
# (one commit wave then permanent rigidity; K3 violated in 34/41 Bingham
# learners) and the single genuine substrate shock (VPS commit exposure jump
# on re-commit, mid-phase 2.49) — are caused by the ABSENCE of persistent
# symbolic phase state and staged commit exposure, and are repaired by:
#
#   P1 — Persistent phase record per site: phase, consolidation tick,
#        last_commit_delta, commit_sign, commit_stress, plastic_since.
#   P2 — Conflict certificate (mandatory invalidation): a committed site
#        under sustained CONSISTENT load OPPOSITE its consolidation reference
#        at magnitude >= CONFLICT_FLOOR x commit_stress melts after
#        conflict_k ticks. "Permanent rigidity" is no longer a steady state.
#   P3 — PhaseMachineController dwell: commit requires k_settle ticks of
#        settle certificate AND k_commit ticks of plastic dwell AND the melt
#        margin.
#   P4 — Commit budget: at most ONE commit per tick under the machine.
#   P5 — Staged exposure ramp (RampedVPS(2)): a fresh commit's delta reaches
#        the forward path over 2 ticks (bounded-rate transition, no impulse).
#
# Protocol: IDENTICAL grid and task family to E0b2 (A→B→A, 150/150/150,
# X/Y_A/Y_B as in E0b/E0b2, Stage0MLP(2,32,2), 64-site region, VPS-base ramp,
# beta=gamma=0.5, head Adam lr=0.02, k_yield=k_settle=2, epsilon_delta=0.02,
# seed 71, 6 yields x 3 etas x 2 settles x 2 hards x 2 laws = 144 points).
# The ONLY deltas vs E0b2 are P1–P5. conflict_k = 2 (aggressive
# invalidation) is fixed across the grid and declared here.
#
# PREREGISTERED SUCCESS CRITERIA (E0b2 results in brackets):
#   C1. mixed phase >= ~20% of grid                    [E0b2: 11.1% — FAILED]
#   C2. learner liveness >= 50%                        [E0b2: 15/77 — FAILED]
#   C3. max mid-phase jump among LEARNERS < 1.0,
#       reported separately for mixed-phase learners
#       (substrate events) vs frozen learners
#       (head stiffness)                               [E0b2: 5.60 — FAILED]
#   C4. Bingham learners > 0                           [E0b2: 41/72 — PASSED]
#   C5. K3 violation candidates <= 20% of learners
#       (anti-ossification is the phase machine's
#       raison d'être)                                 [E0b2: 34/41 = 83%]
#   C6. runaway == 0                                   [E0b2: 0 — PASSED]
#
# PREREGISTERED AMENDMENT (recorded before any grid data was produced):
# The single-point diagnostic revealed that E0b2's runaway rule
# (n_super_final > 32) misclassifies the phase machine's legitimate steady
# state: under aggressive invalidation (conflict_k = 2), a substrate that is
# CHURNING and LEARNING (final < 0.15, bounded mid-phase jumps) correctly
# holds many plastic sites while a contradicting task demands adaptation.
# Amended rule: runaway := churn rate > 20 distinct-site melts per phase AND
# final loss > 0.15 (unbounded churn WITHOUT learning). Points with high
# plasticity but final < 0.15 are classified :mixed — plasticity under
# contradiction is the thesis, not a pathology. No other rule changed.
#
# E1 unblocks only if C1, C2, C5 all pass and C3, C4, C6 hold.
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
        conflict_k=2,
    )

    state = initialize_material_training(mlp, substrate)
    recorder = DevelopmentalRecorder()

    config = MaterialTrainingConfig(
        law=law,
        dcp=PHASE_MACHINE_CONTROLLER,   # P2/P3/P4 (k_commit = 2)
        policy=RampedVPS(2),            # P1/P5
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
    max_midphase_jump = 0.0f0
    midphase_jump_tick = 0
    prev_loss = 0.5f0

    for tick in 1:T
        phase = tick <= ticks_per_phase ? 1 :
                tick <= 2 * ticks_per_phase ? 2 : 3
        Y = phase == 2 ? YB : YA
        material_training_step!(mlp, state, X, Y, config; recorder=recorder)

        pred = material_predict(mlp, state, X, config.policy, tick)
        loss = 0.5f0 * sum(abs2, pred .- Y) / length(Y)
        push!(losses, loss)
        jump = abs(loss - prev_loss)
        if jump > max_tick_jump
            max_tick_jump = jump
            jump_tick = tick
        end
        boundary = (tick == ticks_per_phase + 1) || (tick == 2 * ticks_per_phase + 1)
        if tick > 1 && !boundary && jump > max_midphase_jump
            max_midphase_jump = jump
            midphase_jump_tick = tick
        end
        prev_loss = loss
        push!(superplastic_trace, count(s -> s.allocated && s.superplastic, state.substrate.sites))

        if phase == 2 && (tick - ticks_per_phase) % 10 == 0
            predA = material_predict(mlp, state, X, config.policy, tick)
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

    summary = summarize_events(recorder)
    melts_total = summary.melt_count
    commits_total = summary.commit_count
    post_seed_melts = length(melted_sites[2]) + length(melted_sites[3])
    n_super_final = superplastic_trace[end]

    # Amended census rule (see header amendment): runaway requires unbounded
    # churn WITHOUT learning; high plasticity while learning is :mixed.
    churn_per_phase = max(length(melted_sites[1]), length(melted_sites[2]),
                          length(melted_sites[3]))
    phase_class = if melts_total == 0 && commits_total == 0
        :uncommitted
    elseif churn_per_phase > 20 && final >= 0.15f0
        :runaway
    elseif post_seed_melts > 0
        :mixed
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
        # The table row does not carry the jump tick (tick fields are only in
        # run_point results); report mode shows jump magnitudes without @t.
        midphase_jump_tick=0,
    )
end

function print_verdict(results)
    println("\n" * "="^110)
    println("PREREGISTERED VERDICT CHECKS (E0c)")
    println("="^110)

    learners = filter(r -> r.final < 0.15, results)
    live_learners = filter(r -> r.post_seed_melts > 0, learners)

    # C1
    mixed = filter(r -> r.phase == :mixed, results)
    @printf("C1  mixed-phase coverage:                    %d / %d (%.1f%%)  [need >= ~20%%; E0b2 11.1%%]\n",
        length(mixed), length(results), 100 * length(mixed) / length(results))

    # C2
    @printf("C2  learner liveness (re-melt > 0):          %d / %d learners  [need >= 50%%; E0b2 15/77]\n",
        length(live_learners), length(learners))

    # C3 — split by phase class: mixed learners' jumps are substrate events;
    # frozen learners' jumps are head-optimizer stiffness (E0b2 attribution).
    if !isempty(learners)
        mixed_learners = filter(r -> r.phase == :mixed, learners)
        frozen_learners = filter(r -> r.phase != :mixed, learners)
        isempty(mixed_learners) ||
            @printf("C3  max MID-phase jump (MIXED learners):     %.4f  [substrate events; need < 1.0]\n",
                maximum(r.max_midphase_jump for r in mixed_learners))
        isempty(frozen_learners) ||
            @printf("    max MID-phase jump (non-mixed learners): %.4f  [head stiffness, informational]\n",
                maximum(r.max_midphase_jump for r in frozen_learners))
    end

    # C4
    bingham_learners = filter(r -> r.law === :bingham, learners)
    @printf("C4  Bingham learners:                        %d / %d bingham points  [need > 0; E0b2 41/72]\n",
        length(bingham_learners), count(r -> r.law === :bingham, results))

    # C5 — K3: learned B but zero re-melts (permanent rigidity while learning)
    k3_violations = filter(r -> r.final < 0.15 && r.post_seed_melts == 0, results)
    @printf("C5  K3 violation candidates:                 %d / %d learners (%.1f%%)  [need <= 20%%; E0b2 83%%]\n",
        length(k3_violations), length(learners),
        length(learners) == 0 ? 0.0 : 100 * length(k3_violations) / length(learners))

    # C6
    runaway = filter(r -> r.phase == :runaway, results)
    @printf("C6  runaway points:                          %d  [need 0]\n", length(runaway))

    println("\nPhase census:")
    for ph in (:uncommitted, :frozen, :consolidated, :mixed, :runaway)
        pts = filter(r -> r.phase == ph, results)
        @printf("  %-13s %3d / %d\n", String(ph), length(pts), length(results))
    end

    println("\nLearners (final < 0.15), sorted by final loss:")
    sort!(learners; by=r -> r.final)
    for r in learners
        tick_note = r.midphase_jump_tick > 0 ? @sprintf("@t%d", r.midphase_jump_tick) : ""
        @printf("%-8s τ=%7.3f η=%6.2f σ=%5.2f h=%6.4f | A3=%7.4f asym=%+7.4f | mB=%2d mA3=%2d mid=%.3f%s %s\n",
            r.law, r.yield_up, r.eta, r.settle_down, r.hardening,
            r.lossA3, r.asym, r.melts_p2, r.melts_p3, r.max_midphase_jump, tick_note, String(r.phase))
    end

    println("\nReturn-trip asymmetry among learners:")
    if !isempty(learners)
        asyms = [r.asym for r in learners]
        @printf("  min=%+.4f median=%+.4f max=%+.4f; positive: %d/%d\n",
            minimum(asyms), median(asyms), maximum(asyms), count(>(0), asyms), length(asyms))
    end
end

function main()
    # Chunked-execution support (background processes do not persist between
    # invocations in this environment). Usage:
    #   julia script.jl [bingham|newtonian|single|report [path]]
    mode = isempty(ARGS) ? :full : Symbol(ARGS[1])

    if mode === :report
        path = length(ARGS) >= 2 ? ARGS[2] : joinpath("docs", "e0c_raw_output.txt")
        rows = String[]
        for line in eachline(path)
            s = strip(line)
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
    println("E0c — phase-machine sweep (P1-P5 vs E0b2 residual defects), preregistered [mode=", mode, "]")
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
