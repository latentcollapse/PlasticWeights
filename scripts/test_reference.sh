#!/usr/bin/env bash
set -euo pipefail
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
