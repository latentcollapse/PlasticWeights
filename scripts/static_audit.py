#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
TEST = ROOT / "test" / "runtests.jl"

errors = []

def require(cond, msg):
    if not cond:
        errors.append(msg)

all_jl = list(SRC.rglob("*.jl")) + [TEST]
text = {p: p.read_text() for p in all_jl}

# No fake submodules: source tree is one PlasticWeights module in reference mode.
for p, s in text.items():
    require("using .." not in s and "import .." not in s,
            f"relative pseudo-module import remains: {p.relative_to(ROOT)}")

# Frozen Stage-0 architecture / exposure hazards.
model = text[SRC / "Models" / "Stage0MLP.jl"]
require(not re.search(r"\brelu\b", model, re.I), "ReLU remains in Stage0MLP")
for needle in ["E_fixed", "W_material", "tanh", "H_FP32", "backward_mse"]:
    require(needle in model, f"Stage0MLP missing {needle}")

exp = text[SRC / "Core" / "Exposure.jl"]
require("return site.q" in exp, "VPS prior-q exposure not visible")
require("Int8(2)" not in exp and "2 * site.q" not in exp and "2*site.q" not in exp,
        "amplified ±2 exposure semantics detected")

# HotPool is the only state object that owns latent residual storage.
for p, s in text.items():
    if p.name == "HotPool.jl":
        continue
    require(not re.search(r"\bdelta::Float32\b|\bresiduals::Vector\{Float32\}", s),
            f"duplicate latent residual storage detected in {p.relative_to(ROOT)}")

# Required reference-kernel artifacts.
required_files = [
    SRC / "Core" / "Quantizer.jl",
    SRC / "Core" / "Initialization.jl",
    SRC / "Reference" / "ReferenceKernel.jl",
]
for p in required_files:
    require(p.exists(), f"missing required file {p.relative_to(ROOT)}")

required_symbols = {
    SRC / "DCP" / "Actions.jl": ["apply_action!", "MeltAction", "CommitAction"],
    SRC / "Core" / "SiteTelemetry.jl": ["update_stress_ema!", "update_residual_motion_ema!", "update_counters!"],
    SRC / "Core" / "Initialization.jl": ["initialize_stage0_seed", "SubstrateState"],
    SRC / "Reference" / "ReferenceKernel.jl": ["reference_material_tick!"],
}
for p, symbols in required_symbols.items():
    s = p.read_text()
    for sym in symbols:
        require(sym in s, f"{p.relative_to(ROOT)} missing {sym}")

# Every include on the active package path appears once.
main = (SRC / "PlasticWeights.jl").read_text()
includes = re.findall(r'include\("([^"]+)"\)', main)
require(len(includes) == len(set(includes)), "duplicate include in src/PlasticWeights.jl")
for inc in includes:
    require((SRC / inc).exists(), f"active include does not exist: {inc}")

# Tests should contain the actual causal test concepts, not only labels.
t = TEST.read_text()
for needle in ["S1b", "loss-scale covariance", "S2", "grad_material", "S3", "M_hist", "S3b", "trajectory_A"]:
    require(needle in t, f"test suite missing evidence for {needle}")

# Deferred controls/tasks are not on the active include path.
# (Telemetry/ is intentionally active as of v0.1.0 reference pass.)
control_includes = [
    inc for inc in includes
    if inc.startswith("Controls/")
]

require(
    control_includes == [
        "Controls/AdamState.jl",
        "Controls/C3_ShadowAdam.jl",
        "Controls/C3_Training.jl",
    ],
    f"unexpected active controls: {control_includes}",
)

require(
    not any(inc.startswith("Tasks/") for inc in includes),
    "deferred Tasks subtree loaded by active package",
)

if errors:
    print("STATIC AUDIT FAILED")
    for e in errors:
        print(f" - {e}")
    sys.exit(1)

print("STATIC AUDIT PASSED")
print(f"active includes: {len(includes)}")
print(f"Julia files inspected: {len(all_jl)}")
