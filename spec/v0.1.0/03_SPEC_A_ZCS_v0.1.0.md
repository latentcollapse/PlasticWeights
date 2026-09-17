# PlasticWeights.jl — Spec A: Zero-Centered Superplasticity v0.1.0

## 1. Policy

\[
\boxed{\text{uncertain}\Rightarrow\text{abstain}}
\]

While superplastic:

\[
q_i^{vis}=0
\]

## 2. Exposure

\[
\operatorname{exposure}_{ZCS}(q,a,p)=
\begin{cases}
0 & a=0\\
0 & a=1,p=1\\
q & a=1,p=0
\end{cases}
\]

## 3. Residual Base

\[
b_i=0
\]

so:

\[
s_i=\delta_i
\]

## 4. Counterfactual Learning

The site is forward-dark while learning in shadow.

The surrogate answers:

> If this abstaining connection later became active, which coefficient direction would reduce current loss?

## 5. Melt Lesion

For prior q:

\[
q_{prior}\rightarrow0
\]

on next exposure snapshot.

\[
\ell_i=|q_{prior}|
\]

## 6. Preregistered Signature

On nonzero remelts:

- nonzero immediate lesion,
- sharper immediate melt-time loss/performance change than VPS,
- stronger temporary credit shadowing,
- stale prior contribution removed during relearning.

The lesion is a mechanism prediction, not a superiority claim.

## 7. ZCS Falsification

ZCS is disfavored if, across informative conflict settings:

- lesion/shadow cost consistently dominates later benefit,
- VPS dominates the stability–plasticity frontier with no compensating ZCS advantage,
- dark intervals behave as persistent accidental sparsity,
- relevant-depth learning becomes impractical because of credit shadowing.

Failure of ZCS does not reject the shared substrate.

