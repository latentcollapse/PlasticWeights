# PlasticWeights.jl — local verification handoff

This workspace contains the first direct repair pass after the Qwen scaffold.

## Status

**Static audit: passed. Julia execution: not yet verified in this environment.**

The active package path is intentionally limited to the deterministic reference kernel and tests S0/S1/S1b/S2/S3/S3b. Generated control/task/experiment-telemetry placeholders were removed from the active source tree and replaced with explicit deferred notes.

## First command on a Julia machine

```bash
./scripts/test_reference.sh
```

That runs `Pkg.instantiate()` and `Pkg.test()` with Julia and OpenBLAS constrained to one thread for the deterministic reference path.

If package loading itself fails first, run:

```bash
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=. -e 'using PlasticWeights; println("LOAD_OK")'
```

## What to return for the next repair loop

Paste the **complete raw terminal output**, beginning with the command and including the first stack trace. Do not summarize it. The Julia compiler/test suite is the execution oracle for the next vibecoding pass.

## Static checks available without Julia

```bash
python scripts/static_audit.py
git diff --check
```

The static audit rejects several known failure classes from the generated passes: fake relative submodules, ReLU in `Stage0MLP`, amplified ±2 exposure semantics, duplicate latent residual storage, missing lifecycle/reference-kernel symbols, duplicate active includes, and accidental loading of deferred controls/tasks/telemetry.

## Frozen source of truth

The complete v0.1.0 frozen specification is under `spec/v0.1.0/`.
