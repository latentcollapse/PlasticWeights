# PlasticWeights.jl — Shared Substrate v0.1.0

**Normative for Stage 0**

---

## 1. Hierarchy

\[
\text{Site}\subset\text{Material Region}\subset\text{Substrate}
\]

The DCP is separate from continuous constitutive dynamics.

Functional circuits are emergent and are not first-class Stage-0 objects.

---

## 2. Site

\[
P_i=(q_i,a_i,p_i,h_i)
\]

where:

- \(q_i\in\{-1,0,+1\}\): committed balanced-ternary value,
- \(a_i\in\{0,1\}\): allocated flag,
- \(p_i\in\{0,1\}\): superplastic flag,
- \(h_i\): hot-pool handle, valid iff \(p_i=1\).

### 2.1 Derived developmental phenotype

\[
\operatorname{phenotype}(q,a,p)=
\begin{cases}
\bot & a=0\\
\star & a=1,\ p=1\\
- & a=1,\ p=0,\ q=-1\\
0 & a=1,\ p=0,\ q=0\\
+ & a=1,\ p=0,\ q=+1
\end{cases}
\]

The phenotype is telemetry/debug output only.

---

## 3. Material Region

A region is the smallest persistent group of sites sharing constitutive parameters and material history.

\[
R=(P_R,M_R,\mathcal C_R)
\]

Stage-0 regions:

- fixed,
- contiguous in logical parameter order,
- 64–256 sites,
- strict non-overlapping partition,
- no split/merge/reassignment.

### 3.1 Persistent material state

At minimum:

- `yield_up`,
- `settle_down`,
- `viscosity` / constitutive rate parameter,
- `hardening_increment`,
- declared region-level lifecycle counters if required.

The exact fields designated persistent material history MUST be enumerated before S3.

---

## 4. Operative State vs Material History

Define:

\[
X_{op}
\]

as every currently stored variable whose value can causally affect the next constitutive or DCP action under the test.

Examples include:

- \(q,a,p,\delta\),
- stress EMA \(\sigma\),
- residual-motion EMA,
- consecutive-above-yield counter,
- consecutive-stable counter,
- site age if read by controller/law,
- hot-pool occupancy if it affects eligibility,
- budget state if it affects eligibility,
- declared DCP state.

Define:

\[
M_{hist}
\]

as only the persistent historical variables intentionally left different in the causal intervention.

Twin-History requires:

\[
X_{op}^{A}=X_{op}^{B}
\]

while:

\[
M_{hist}^{A}\neq M_{hist}^{B}
\]

No other intentionally unmatched causal state is permitted.

---

## 5. Superplastic Residual

A superplastic site owns exactly one FP32 residual:

\[
\delta_i\in\mathbb R
\]

At melt:

\[
\delta_i\leftarrow0
\]

The residual is shadow-only in Stage 0.

Exposure base:

- ZCS: \(b_i=0\)
- VPS: \(b_i=q_i^{prior}\)

Commit candidate:

\[
s_i=b_i+\delta_i
\]

---

## 6. Forward Exposure

Consolidated allocated:

\[
q_i^{vis}=q_i
\]

Vacant:

\[
q_i^{vis}=0
\]

Superplastic exposure is variant-defined.

One immutable exposure snapshot is used for the whole training tick.

---

## 7. Surrogate Backward Rule

Let:

\[
g_i=\frac{\partial L}{\partial q_i^{vis}}
\]

For a superplastic site:

\[
\frac{\partial L}{\partial\delta_i}:=g_i
\]

This is an explicit surrogate rule.

---

## 8. Stress

Signed load:

\[
g_i=\frac{\partial L}{\partial q_i^{vis}}
\]

Stress EMA:

\[
\sigma_i(t)=\beta\sigma_i(t-1)+(1-\beta)|g_i(t)|
\]

Directional conflict may be logged, but does not affect Stage-0 lifecycle transitions.

---

## 9. Loss / Constitutive Unit Convention

The constitutive dynamics are **covariant to arbitrary constant rescaling of the loss** when parameters are transformed consistently.

If:

\[
L' = kL,\quad k>0
\]

then:

\[
g'=kg,\qquad \sigma'=k\sigma
\]

and the constitutive parameters transform as:

\[
\tau'=k\tau,\qquad \epsilon'=k\epsilon,\qquad \eta'=k\eta
\]

Under this transformation, the mobility and residual update remain invariant.

The Stage-0 reference suite MUST use one canonical loss-reduction convention.

A loss-scale covariance sanity test is mandatory.

---

## 10. Constitutive Laws

### 10.1 Newtonian calibration law

\[
\Delta\delta_i=-\frac{g_i}{\eta}
\]

with \(dt=1\).

Matched SGD-shadow must reproduce the same trajectory under:

\[
lr=\frac{1}{\eta}
\]

### 10.2 Stage-0 Bingham-inspired computational law

\[
m_i=
\max\left(
0,\,
1-\frac{\tau_R}{\sigma_i+\epsilon}
\right)
\]

\[
\Delta\delta_i=
-\frac{g_i}{\eta}m_i
\]

where:

- \(\tau_R=\text{yield\_up}_R\),
- \(\eta>0\),
- \(\epsilon>0\).

Properties:

1. zero mobility in the sub-yield regime,
2. increasing mobility above yield,
3. mobility approaches 1 at high stress,
4. \(\tau_R=0\) recovers Newtonian behavior,
5. signed gradient determines deformation direction.

This law is a computational analogue, not literal physical rheology.

---

## 11. Work-Hardening

After every successful commit in region \(R\):

\[
\text{yield\_up}_R
\leftarrow
\text{yield\_up}_R+\kappa_H
\]

with \(\kappa_H>0\).

Stage 0 uses monotonic hardening over a bounded horizon.

Long-horizon decay / softening is deferred.

---

## 12. Reconsolidation

\[
s_i=b_i+\delta_i
\]

\[
q'_i=
\begin{cases}
-1 & s_i<-0.5\\
0 & |s_i|\le0.5\\
+1 & s_i>0.5
\end{cases}
\]

Exact \(\pm0.5\) boundaries map to 0.

---

## 13. Hysteresis

Melt eligibility:

\[
\sigma_i>\text{yield\_up}_R
\]

for \(K_{yield}\) consecutive ticks.

Commit eligibility:

\[
\sigma_i<\text{settle\_down}_R
\]

and:

\[
EMA(|\Delta\delta_i|)<\epsilon_\delta
\]

for \(K_{settle}\) consecutive ticks.

Require:

\[
\text{yield\_up}_R>\text{settle\_down}_R
\]

---

## 14. Stage-0 Network

\[
x\rightarrow E_{fixed}\rightarrow W_{material}\rightarrow\tanh\rightarrow H_{FP32}\rightarrow y
\]

- `E_fixed`: nonzero FP32 input projection, frozen,
- material layer: only learned nonlinear representational layer,
- activation: `tanh`,
- `H_FP32`: nonzero trainable linear head,
- output bias: mandatory, trainable from tick 0.

### ARCH-GATE-1

\[
\phi'(0)\neq0
\]

Stage 0 uses `tanh`.

### ARCH-GATE-2

Input projection is frozen.

### TASK-GATE

Bias-only output must not meaningfully solve the task.

---

## 15. Developmental Events

Required telemetry:

- `first_delta_tick`,
- `wake_tick`,
- `credit_unlock_tick`,
- melt/commit counts,
- prior-q class for every melt,
- superplastic duration,
- region yield trajectory,
- stress trajectory,
- ZCS lesion size.

---

## 16. Region Responsiveness

Absolute “frozen region” labels are prohibited in Stage 0.

For recent global stress values, define a reference envelope:

\[
S^{global}_{p,W}
=
Q_p\left(
\{\sigma_i(t): \forall i,\ t\in W\}
\right)
\]

with preregistered percentile \(p\) and window \(W\).

Define region responsiveness ratio:

\[
\rho_R=
\frac{\text{yield\_up}_R}
{S^{global}_{p,W}+\epsilon}
\]

A region with:

\[
\rho_R>1
\]

is hardened beyond the chosen recent global stress reference.

Report \(\rho_R\) as telemetry rather than calling such a region permanently frozen.

