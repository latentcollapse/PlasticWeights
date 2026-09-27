using Test
using PlasticWeights

_mt_bits(x::Float32) = reinterpret(UInt32, x)
_mt_float_bits(xs) = Tuple(_mt_bits(Float32(x)) for x in xs)

function _mt_substrate_fingerprint(s::SubstrateState)
    sites = Tuple(
        (site.q, site.allocated, site.superplastic, site.hot_handle)
        for site in s.sites
    )

    telemetry = Tuple(
        (
            _mt_bits(t.stress_ema),
            _mt_bits(t.signed_stress_ema),
            _mt_bits(t.residual_motion_ema),
            t.consecutive_above_yield,
            t.consecutive_stable,
        )
        for t in s.telemetry
    )

    regions = Tuple(
        (
            r.id,
            Tuple(r.site_indices),
            r.region_size,
            _mt_bits(r.yield_up),
            _mt_bits(r.settle_down),
            _mt_bits(r.eta),
            _mt_bits(r.hardening_increment),
            _mt_bits(r.epsilon_delta),
            r.k_yield,
            r.k_settle,
        )
        for r in s.region_map.regions
    )

    pool = (
        Tuple(_mt_bits(x) for x in s.pool.residuals),
        Tuple(s.pool.free_list),
        Tuple(s.pool.allocated),
        s.pool.capacity,
    )

    return (
        sites=sites,
        telemetry=telemetry,
        regions=regions,
        pool=pool,
        max_superplastic=s.max_superplastic,
    )
end

function _mt_state_fingerprint(
    mlp::Stage0MLP,
    state::MaterialTrainingState,
)
    return (
        substrate=_mt_substrate_fingerprint(state.substrate), head=_mt_float_bits(vec(mlp.H_FP32)),
        bias=_mt_float_bits(mlp.output_bias), head_m=_mt_float_bits(vec(state.head_adam.first_moment)),
        head_v=_mt_float_bits(vec(state.head_adam.second_moment)),
        head_step=state.head_adam.step, bias_m=_mt_float_bits(state.bias_adam.first_moment),
        bias_v=_mt_float_bits(state.bias_adam.second_moment),
        bias_step=state.bias_adam.step, step=state.step,
    )
end

_mt_action_fingerprint(actions) =
    Tuple(action_code(action) for action in actions)

function _fast_commit_material_config(;
    head_learning_rate::Real=0.02f0,
)
    return MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=FIXED_RULE_CONTROLLER,
        policy=ZCS(),
        head=AdamConfig(
            learning_rate=head_learning_rate,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        beta=0.0f0,
        gamma=0.0f0,
    )
end

function _fast_commit_material_state(
    mlp::Stage0MLP,
)
    # This fixture deliberately makes the *lifecycle timing* easy to test:
    # settle_down = 0.0 makes the consistency certificate vacuously true
    # (D1 semantics: settle_down is a gradient-consistency threshold), residual
    # movement is far below epsilon_delta, and k_settle=2. Thus the all-star
    # seed commits on tick 2.
    #
    # It is a test fixture, not the primary experiment hyperparameter set.
    return initialize_material_training(
        mlp;
        region_size=64,
        yield_up=100.0f0,
        settle_down=0.0f0,
        eta=0.01f0,
        hardening_increment=0.05f0,
        epsilon_delta=1.0f6,
        k_yield=2,
        k_settle=2,
    )
end

@testset "Material training — configuration and state invariants" begin
    @test_throws ErrorException MaterialTrainingConfig(beta=-0.1f0)
    @test_throws ErrorException MaterialTrainingConfig(beta=1.1f0)
    @test_throws ErrorException MaterialTrainingConfig(gamma=-0.1f0)
    @test_throws ErrorException MaterialTrainingConfig(gamma=1.1f0)

    mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=41,
    )

    state = initialize_material_training(
        mlp;
        region_size=64,
    )

    @test length(state.substrate.sites) == num_material_sites(mlp)
    @test state.step == 0
    @test state.head_adam.step == 0
    @test state.bias_adam.step == 0
    @test check_invariants(state, mlp)

    # The initializer must reject a substrate that does not match the model.
    wrong = initialize_stage0_seed(128; region_size=64)
    @test_throws ErrorException initialize_material_training(mlp, wrong)

    # The training clock is part of the state contract.
    state.step = 1
    @test_throws ErrorException check_invariants(state, mlp)
end

@testset "Material training — prediction is pure" begin
    mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=43,
    )
    state = _fast_commit_material_state(mlp)

    before = _mt_state_fingerprint(mlp, state)
    y1 = material_predict(mlp, state, Float32[1, -1], ZCS())
    y2 = material_predict(mlp, state, Float32[1, -1], ZCS())
    after = _mt_state_fingerprint(mlp, state)

    @test _mt_float_bits(y1) == _mt_float_bits(y2)
    @test before == after
end

@testset "Material training — zero-exposure gradient island" begin
    mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=7,
    )

    state = initialize_material_training(
        mlp;
        region_size=64,
        eta=1.0f0,
        k_yield=2,
        k_settle=2,
    )

    recorder = DevelopmentalRecorder()

    cfg = MaterialTrainingConfig(
        law=NEWTONIAN,
        dcp=FIXED_RULE_CONTROLLER,
        policy=ZCS(),
        head=AdamConfig(
            learning_rate=1.0f-5,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        beta=0.0f0,
        gamma=0.0f0,
    )

    x = Float32[1, 1]
    target = Float32[1]

    H0 = copy(mlp.H_FP32)
    b0 = copy(mlp.output_bias)

    r1 = material_training_step!(
        mlp,
        state,
        x,
        target,
        cfg;
        recorder=recorder,
    )

    @test all(iszero, r1.exposures)
    @test all(iszero, r1.grad_head)
    @test any(!iszero, r1.grad_bias)
    @test any(!iszero, r1.grad_material)
    @test all(iszero, r1.grad_features)

    @test any(!iszero, r1.delta_updates)
    @test first_delta_tick(recorder) == 1

    @test wake_tick(recorder) === nothing
    @test credit_unlock_tick(recorder) === nothing

    @test mlp.H_FP32 == H0
    @test mlp.output_bias != b0

    @test state.step == 1
    @test state.head_adam.step == 1
    @test state.bias_adam.step == 1
    @test check_invariants(state, mlp)
end

@testset "Material training — commit becomes visible next tick" begin
    mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=47,
    )
    state = _fast_commit_material_state(mlp)
    recorder = DevelopmentalRecorder()
    cfg = _fast_commit_material_config(head_learning_rate=1.0f-5)

    # Symmetric targets make the output-bias gradient exactly zero at q=0,
    # keeping the first two ticks focused on the material path.
    X = Float32[
        1 -1
        1 -1
    ]
    Y = Float32[
        1 -1
    ]

    r1 = material_training_step!(
        mlp, state, X, Y, cfg;
        recorder=recorder,
    )

    @test all(iszero, r1.exposures)
    @test all(iszero, r1.next_exposures)
    @test commit_count(event_trace(recorder)) == 0
    @test wake_tick(recorder) === nothing
    @test credit_unlock_tick(recorder) === nothing

    r2 = material_training_step!(
        mlp, state, X, Y, cfg;
        recorder=recorder,
    )

    # Tick 2 used the already-frozen all-zero exposure, then committed.
    @test all(iszero, r2.exposures)
    @test any(!iszero, r2.next_exposures)
    @test commit_count(event_trace(recorder)) == 64

    # A commit cannot retroactively create wake/credit during its own tick.
    @test wake_tick(recorder) === nothing
    @test credit_unlock_tick(recorder) === nothing

    committed = copy(r2.next_exposures)

    r3 = material_training_step!(
        mlp, state, X, Y, cfg;
        recorder=recorder,
    )

    @test r3.exposures == committed
    @test wake_tick(recorder) == 3
    @test any(!iszero, r3.grad_features)
    @test credit_unlock_tick(recorder) == 3

    @test state.step == 3
    @test state.head_adam.step == 3
    @test state.bias_adam.step == 3
    @test check_invariants(state, mlp)
end

@testset "Material training — deterministic replay" begin
    mlp_a = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=53,
    )
    mlp_b = deepcopy(mlp_a)

    state_a = _fast_commit_material_state(mlp_a)
    state_b = deepcopy(state_a)
    cfg = _fast_commit_material_config(head_learning_rate=0.01f0)

    batches = (
        (
            Float32[1, 1],
            Float32[1],
        ),
        (
            Float32[-1, -1],
            Float32[-1],
        ),
        (
            Float32[1, -1],
            Float32[1],
        ),
        (
            Float32[-1, 1],
            Float32[-1],
        ),
    )

    for step in 1:16
        x, y = batches[mod1(step, length(batches))]

        ra = material_training_step!(mlp_a, state_a, x, y, cfg)
        rb = material_training_step!(mlp_b, state_b, x, y, cfg)

        @test _mt_bits(Float32(ra.loss)) == _mt_bits(Float32(rb.loss))
        @test Tuple(ra.exposures) == Tuple(rb.exposures)
        @test Tuple(ra.next_exposures) == Tuple(rb.next_exposures)
        @test _mt_float_bits(ra.prediction) ==
              _mt_float_bits(rb.prediction)
        @test _mt_float_bits(ra.delta_updates) ==
              _mt_float_bits(rb.delta_updates)
        @test _mt_action_fingerprint(ra.actions) ==
              _mt_action_fingerprint(rb.actions)
        @test _mt_state_fingerprint(mlp_a, state_a) ==
              _mt_state_fingerprint(mlp_b, state_b)
    end
end

@testset "Material training — recorder is causally inert" begin
    plain_mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=59,
    )
    observed_mlp = deepcopy(plain_mlp)

    plain = _fast_commit_material_state(plain_mlp)
    observed = deepcopy(plain)
    recorder = DevelopmentalRecorder()
    cfg = _fast_commit_material_config(head_learning_rate=0.01f0)

    X = Float32[
        1 -1
        1 -1
    ]
    Y = Float32[
        1 -1
    ]

    for _ in 1:8
        rp = material_training_step!(
            plain_mlp, plain, X, Y, cfg,
        )
        ro = material_training_step!(
            observed_mlp, observed, X, Y, cfg;
            recorder=recorder,
        )

        @test _mt_bits(Float32(rp.loss)) ==
              _mt_bits(Float32(ro.loss))
        @test Tuple(rp.exposures) ==
              Tuple(ro.exposures)
        @test Tuple(rp.next_exposures) ==
              Tuple(ro.next_exposures)
        @test _mt_float_bits(rp.prediction) ==
              _mt_float_bits(ro.prediction)
        @test _mt_float_bits(rp.delta_updates) ==
              _mt_float_bits(ro.delta_updates)
        @test _mt_action_fingerprint(rp.actions) ==
              _mt_action_fingerprint(ro.actions)
        @test _mt_state_fingerprint(plain_mlp, plain) ==
              _mt_state_fingerprint(observed_mlp, observed)
    end

    @test !isempty(recorder)
    @test first_delta_tick(recorder) == 1
    @test wake_tick(recorder) == 3
    @test credit_unlock_tick(recorder) == 3
end

@testset "Material training — tiny deterministic mapping is learnable" begin
    mlp = Stage0MLP(
        2, 32, 1;
        feature_size=2,
        rng_seed=61,
    )
    state = _fast_commit_material_state(mlp)
    cfg = _fast_commit_material_config(head_learning_rate=0.02f0)

    # Bias alone cannot solve this antisymmetric mapping.
    X = Float32[
        1 -1
        1 -1
    ]
    Y = Float32[
        1 -1
    ]

    prediction0 = material_predict(mlp, state, X, ZCS())
    initial_loss = 0.5f0 * sum(abs2, prediction0 .- Y) / length(Y)

    # Two ticks permit the seed material to accumulate δ and reconsolidate.
    # From tick 3 onward the committed ternary material is forward-visible and
    # the ordinary head can learn against it.
    for _ in 1:200
        material_training_step!(mlp, state, X, Y, cfg)
    end

    prediction1 = material_predict(mlp, state, X, ZCS())
    final_loss = 0.5f0 * sum(abs2, prediction1 .- Y) / length(Y)

    @test final_loss < initial_loss
    @test final_loss < 0.25f0 * initial_loss
    @test prediction1[1, 1] > 0.0f0
    @test prediction1[1, 2] < 0.0f0
    @test any(!iszero, exposure_snapshot(state.substrate.sites, ZCS()))

    @test state.step == 200
    @test state.head_adam.step == 200
    @test state.bias_adam.step == 200
    @test check_invariants(state, mlp)
end
