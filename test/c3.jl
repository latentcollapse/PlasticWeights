using Test
using PlasticWeights

_c3_bits(x::Float32) = reinterpret(UInt32, x)

function _c3_float_bits(xs)
    Tuple(_c3_bits(Float32(x)) for x in xs)
end

function _c3_state_fingerprint(mlp::Stage0MLP, state::C3TrainingState)
    return (
        q=Tuple(state.shadow.q),
        latent=_c3_float_bits(state.shadow.latent),
        shadow_m=_c3_float_bits(state.shadow.first_moment),
        shadow_v=_c3_float_bits(state.shadow.second_moment),
        shadow_step=state.shadow.step, head=_c3_float_bits(vec(mlp.H_FP32)),
        bias=_c3_float_bits(mlp.output_bias), head_m=_c3_float_bits(vec(state.head_adam.first_moment)),
        head_v=_c3_float_bits(vec(state.head_adam.second_moment)),
        head_step=state.head_adam.step, bias_m=_c3_float_bits(state.bias_adam.first_moment),
        bias_v=_c3_float_bits(state.bias_adam.second_moment),
        bias_step=state.bias_adam.step,
    )
end

@testset "C3 — configuration and state invariants" begin
    @test_throws ErrorException C3ShadowAdamConfig(learning_rate=0.0f0)
    @test_throws ErrorException C3ShadowAdamConfig(beta1=-0.1f0)
    @test_throws ErrorException C3ShadowAdamConfig(beta1=1.0f0)
    @test_throws ErrorException C3ShadowAdamConfig(beta2=1.0f0)
    @test_throws ErrorException C3ShadowAdamConfig(epsilon=0.0f0)

    @test_throws ErrorException AdamConfig(learning_rate=0.0f0)
    @test_throws ErrorException AdamConfig(beta1=1.0f0)
    @test_throws ErrorException AdamConfig(beta2=-0.1f0)
    @test_throws ErrorException AdamConfig(epsilon=0.0f0)

    @test_throws ErrorException initialize_c3_shadow_adam(0)
    @test_throws ErrorException initialize_c3_shadow_adam(4; q=2)
    @test_throws ErrorException initialize_c3_shadow_adam(Int8[0, 1, 2])

    state = initialize_c3_shadow_adam(Int8[-1, 0, 1])
    @test state.q == Int8[-1, 0, 1]
    @test state.latent == Float32[-1, 0, 1]
    @test all(iszero, state.first_moment)
    @test all(iszero, state.second_moment)
    @test state.step == 0
    @test check_invariants(state)

    # q must always be the visible quantization of the continuous shadow.
    state.latent[2] = 0.75f0
    @test_throws ErrorException check_invariants(state)
end

@testset "C3 — exposure snapshots are defensive and next-tick only" begin
    state = initialize_c3_shadow_adam(4)
    snapshot0 = c3_exposure_snapshot(state)

    cfg = C3ShadowAdamConfig(
        learning_rate=0.25f0,
        beta1=0.9f0,
        beta2=0.999f0,
        epsilon=1.0f-8,
    )

    g = Float32[1, -1, 1, -1]

    c3_shadow_adam_step!(state, g, cfg)
    @test snapshot0 == Int8[0, 0, 0, 0]

    # Mutating a returned snapshot must not mutate live C3 state.
    snapshot0[1] = 1
    @test state.q[1] == 0

    # Shadow can move without immediately changing the visible ternary value.
    @test any(!iszero, c3_shadow_values(state))
    @test all(iszero, c3_exposure_snapshot(state))

    # Repeated updates eventually cross ±0.5 and become visible next tick.
    for _ in 1:2
        c3_shadow_adam_step!(state, g, cfg)
    end
    @test any(!iszero, c3_exposure_snapshot(state))
end

@testset "C3 — zero-exposure gradient island" begin
    mlp = Stage0MLP(
        2, 2, 1;
        feature_size=2,
        rng_seed=7,
    )
    state = initialize_c3_training(mlp)

    cfg = C3TrainingConfig(
        shadow=C3ShadowAdamConfig(
            learning_rate=0.10f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        head=AdamConfig(
            learning_rate=1.0f-5,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
    )

    x = Float32[1, 1]
    target = Float32[1]

    H0 = copy(mlp.H_FP32)
    b0 = copy(mlp.output_bias)

    result = c3_training_step!(mlp, state, x, target, cfg)

    @test all(iszero, result.exposures)
    @test all(iszero, result.grad_head)
    @test any(!iszero, result.grad_bias)
    @test any(!iszero, result.grad_material)

    # Head matrix is initially gradient-isolated, while the bias can learn.
    @test mlp.H_FP32 == H0
    @test mlp.output_bias != b0

    # STE moves the continuous C3 shadows even before q necessarily changes.
    @test any(!iszero, c3_shadow_values(state.shadow))

    # All optimizer clocks advance together.
    @test state.shadow.step == 1
    @test state.head_adam.step == 1
    @test state.bias_adam.step == 1
    @test check_invariants(state, mlp)
end

@testset "C3 — end-to-end ternary emergence" begin
    mlp = Stage0MLP(
        2, 2, 1;
        feature_size=2,
        rng_seed=7,
    )
    state = initialize_c3_training(mlp)

    cfg = C3TrainingConfig(
        shadow=C3ShadowAdamConfig(
            learning_rate=0.25f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        head=AdamConfig(
            learning_rate=1.0f-5,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
    )

    x = Float32[1, 1]
    target = Float32[1]

    initial_snapshot = c3_exposure_snapshot(state.shadow)

    for _ in 1:4
        c3_training_step!(mlp, state, x, target, cfg)
    end

    @test initial_snapshot == Int8[0, 0, 0, 0]
    @test any(!iszero, c3_exposure_snapshot(state.shadow))
    @test state.shadow.step == 4
    @test state.head_adam.step == 4
    @test state.bias_adam.step == 4
    @test check_invariants(state, mlp)
end

@testset "C3 — deterministic replay" begin
    mlp_a = Stage0MLP(
        2, 2, 1;
        feature_size=2,
        rng_seed=19,
    )
    mlp_b = deepcopy(mlp_a)

    state_a = initialize_c3_training(mlp_a)
    state_b = initialize_c3_training(mlp_b)

    cfg = C3TrainingConfig(
        shadow=C3ShadowAdamConfig(
            learning_rate=0.12f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        head=AdamConfig(
            learning_rate=0.01f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
    )

    xs = (
        Float32[1, 1],
        Float32[-1, -1],
        Float32[1, -1],
        Float32[-1, 1],
    )
    ys = (
        Float32[1],
        Float32[-1],
        Float32[1],
        Float32[-1],
    )

    for step in 1:24
        i = mod1(step, length(xs))

        ra = c3_training_step!(mlp_a, state_a, xs[i], ys[i], cfg)
        rb = c3_training_step!(mlp_b, state_b, xs[i], ys[i], cfg)

        @test _c3_bits(Float32(ra.loss)) == _c3_bits(Float32(rb.loss))
        @test Tuple(ra.exposures) == Tuple(rb.exposures)
        @test Tuple(ra.next_exposures) == Tuple(rb.next_exposures)
        @test _c3_float_bits(ra.prediction) == _c3_float_bits(rb.prediction)
        @test _c3_state_fingerprint(mlp_a, state_a) ==
              _c3_state_fingerprint(mlp_b, state_b)
    end
end

@testset "C3 — tiny deterministic mapping is learnable" begin
    mlp = Stage0MLP(
        2, 2, 1;
        feature_size=2,
        rng_seed=23,
    )
    state = initialize_c3_training(mlp)

    cfg = C3TrainingConfig(
        shadow=C3ShadowAdamConfig(
            learning_rate=0.08f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
        head=AdamConfig(
            learning_rate=0.02f0,
            beta1=0.9f0,
            beta2=0.999f0,
            epsilon=1.0f-8,
        ),
    )

    # Two opposing samples prevent output bias alone from solving the task.
    X = Float32[
        1 -1
        1 -1
    ]
    Y = Float32[
        1 -1
    ]

    prediction0 = c3_predict(mlp, state, X)
    initial_loss = sum(abs2, prediction0 .- Y) / length(Y)

    for _ in 1:200
        c3_training_step!(mlp, state, X, Y, cfg)
    end

    prediction1 = c3_predict(mlp, state, X)
    final_loss = sum(abs2, prediction1 .- Y) / length(Y)

    @test final_loss < initial_loss
    @test final_loss < 0.75f0 * initial_loss
    @test any(!iszero, c3_exposure_snapshot(state.shadow))
    @test state.shadow.step == 200
    @test check_invariants(state, mlp)
end

@testset "C3 — no material-state leakage" begin
    mlp = Stage0MLP(
        2, 2, 1;
        feature_size=2,
        rng_seed=31,
    )
    state = initialize_c3_training(mlp)

    # C3 may own optimizer history, but not PlasticWeights material history.
    forbidden = Set((
        :stress_ema,
        :residual_motion_ema,
        :yield_up,
        :settle_down,
        :hardening_increment,
        :epsilon_delta,
        :hot_handle,
        :superplastic,
        :region_map,
        :pool,
        :dcp,
    ))

    training_fields = Set(fieldnames(typeof(state)))
    shadow_fields = Set(fieldnames(typeof(state.shadow)))
    head_fields = Set(fieldnames(typeof(state.head_adam)))
    bias_fields = Set(fieldnames(typeof(state.bias_adam)))

    @test isempty(intersect(training_fields, forbidden))
    @test isempty(intersect(shadow_fields, forbidden))
    @test isempty(intersect(head_fields, forbidden))
    @test isempty(intersect(bias_fields, forbidden))
end
