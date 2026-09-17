# PlasticWeights.jl — Spec B: Value-Preserving Superplasticity v0.1.0

## 1. Policy

\[
\boxed{\text{uncertain}\Rightarrow\text{retain prior}}
\]

While superplastic:

\[
q_i^{vis}=q_i^{prior}
\]

## 2. Exposure

\[
\operatorname{exposure}_{VPS}(q,a,p)=
\begin{cases}
0 & a=0\\
q & a=1,p=1\\
q & a=1,p=0
\end{cases}
\]

## 3. Residual Base

\[
b_i=q_i^{prior}
\]

so:

\[
s_i=q_i^{prior}+\delta_i
\]

## 4. Semantics

The site continues executing the prior committed ternary value while a shadow replacement develops.

## 5. Melt Continuity

\[
q_i^{vis}(t^+)=q_i^{vis}(t^-)
\]

VPS lesion size is zero by construction.

## 6. Preregistered Signature

On nonzero remelts:

- no instantaneous lesion,
- smoother immediate transition,
- preserved upstream credit availability,
- potentially longer stale interference,
- visible correction delayed until commit.

## 7. VPS Falsification

VPS is disfavored if:

- stale behavior systematically blocks adaptation,
- latent disagreement grows without compensating retention,
- ZCS dominates the stability–plasticity frontier despite lesion cost,
- visible corrections occur too slowly for the intended developmental timescale.

Failure of VPS does not reject the shared substrate.

