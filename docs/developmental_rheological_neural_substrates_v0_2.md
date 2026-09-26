# Developmental Rheological Neural Substrates
## Formal Model and Adversarial Hardening of a Developmental Pentanary Architecture

**White Paper Draft v0.2**  
**Date:** 2026-09-15  
**Status:** speculative research architecture; no implementation or performance claim  
**Revision focus:** formal model, anti-cheating constraints, controller separation, hardware realism, and adversarial falsifiability  

---

## Abstract

Most neural-network systems separate several concerns that are treated as fundamentally different: trainable weights, optimizer state, quantization state, sparsity masks, continual-learning protection, growth rules, routing, hardware budgets, and provenance. The previous DRNS v0.1 draft asked whether these concerns could instead be expressed as a single developmental substrate in which parameters have explicit lifecycle and material semantics. Three hostile review passes then attacked that proposal from complementary directions: reduction to existing optimization machinery, systems-level coupling and hardware failure, and lack of a minimal empirical separation claim.

This revision accepts the strongest parts of those attacks. It does **not** claim that a pentanary state alphabet is a new primitive in a computability-theoretic sense, that rheological equations are irreducible to stateful optimizers, or that a developmental state machine is novel merely because it unifies familiar operations. Instead, DRNS v0.2 makes a narrower and stronger scientific claim:

> **The research question is whether allocation, precision, plasticity, consolidation, and bounded structural capacity perform better when governed as one coupled local developmental state machine than when implemented as independently coordinated subsystems under the same data, memory, active-compute, and tuning budgets.**

The proposed substrate uses the developmental alphabet

\[
\mathcal P=\{⊥,-1,0,+1,★\},
\]

where \(⊥\) denotes vacancy, \(-1,0,+1\) denote crystallized ternary states, and \(★\) denotes allocated but unresolved/plastic structure. The primary lifecycle is

\[
⊥\rightarrow★\rightarrow\{-1,0,+1\},
\]

with controlled reverse transitions, reclamation, and block-level growth. The system explicitly separates **numeric state**, **developmental state**, **material state**, **history**, **topology**, and **controller state**. A crystallized block may be mechanically rigid while remaining diagnostically live: its forward value need not change, but its stress history can continue accumulating until a deconsolidation condition is met.

The revision introduces five hardening mechanisms that were missing or underspecified in v0.1. First, \(★\) capacity is bounded simultaneously by count, memory, and active compute, preventing the architecture from silently degenerating into a full-precision model. Second, developmental stress is split into endogenous and exogenous channels so the system does not judge its own failures only through representations it already controls. Third, structural transitions are mediated by a resource shield with hard memory/FLOP/latency constraints, while the developmental controller itself remains replaceable and separately ablated. Fourth, rollback is transactional over the complete developmental state, not merely the numeric weights. Fifth, the first experimental program is narrowed to birth, crystallization, deconsolidation, reclamation, and resource-bounded growth; fusion, fission, multimodal development, portable deltas, procedural star resolvers, and learned meta-RL controllers are explicitly deferred.

The central empirical target is a **developmental efficiency frontier** over adaptation, retention, capability, wall-clock cost, active FLOPs, memory, and latency. The key adversarial comparator is an "Everything Bagel" baseline that combines ternary/QAT, dynamic sparsity, continual-learning regularization or replay, expandable adapters or modules, and a resource controller. If DRNS cannot produce a better Pareto frontier than that matched stack, then its strongest architectural claim fails and the framework should be treated as an engineering ontology rather than a new architecture class.

This paper therefore turns DRNS from a broad architectural vision into a falsifiable research program. Its purpose is not to assert that developmental rheological substrates work. Its purpose is to specify the smallest version that could prove that they do - or prove that they do not.

---

## 1. Revision rationale: what changed after adversarial review

DRNS v0.1 deliberately over-mapped the design space. It explored rheological learning laws, developmental pentanary states, topological growth, fusion and fission, developmental sleep, failure memory, resource-aware scaling, lineage, multimodality, and a Julia-native implementation. That breadth was useful for discovering the space, but it created a predictable weakness: a skeptical reviewer could reduce nearly every component to a known mechanism and then argue that the unification merely concentrated complexity.

The hostile reviews raised four classes of objections.

### 1.1 Reduction objections

The developmental alphabet can be represented as familiar metadata: a vacancy mask, a ternary value, and a precision/plasticity flag. Rheological state can often be represented as optimizer state. Birth can look like dynamic sparsity or expandable networks. Crystallization can look like progressive quantization. Deconsolidation can look like restoring a continuous residual. Reclamation can look like pruning. These reductions are valid observations.

v0.2 therefore does not use irreducibility as its novelty criterion. The relevant question is not whether a conventional program can simulate DRNS. The relevant question is whether the **coupled developmental organization** induces better learning dynamics, lower coordination cost, or better resource tradeoffs under fair budgets.

### 1.2 Dynamical objections

A hard yield law can create dead zones. Local coupling can create phase avalanches. Early crystallization can create rich-get-richer lock-in. Endogenous telemetry can produce self-confirming stress signals. Repeated crystallization and deconsolidation can cause generational loss. These are not peripheral implementation details; they are core dynamical risks.

v0.2 therefore distinguishes forward immobility from diagnostic liveness, requires hysteresis and dwell time, splits endogenous from exogenous evidence, and adds explicit cycle-loss measurements.

### 1.3 Systems objections

Dynamic topology, sparse star computation, ternary kernels, journaling, and continual consolidation can form an accelerator-hostile workload. Metadata can erase compression gains. Per-scalar state can destroy memory locality. Bit-exact replay can conflict with highly parallel kernels. Dynamic specialization can cause compilation-cache growth.

v0.2 therefore moves the minimum architecture to **block granularity**, uses bounded precompiled kernel families, requires real byte and wall-clock accounting, separates decision reproducibility from bit-exact arithmetic reproducibility, and treats layout compaction as an epoch-level operation rather than a token-level operation.

### 1.4 Scientific-claim objections

The strongest criticism was that v0.1 did not identify the smallest result that would establish non-triviality. A collection of known mechanisms can be scientifically interesting only if the coupling produces measurable behavior that a well-matched modular stack does not.

v0.2 makes that challenge central. The first goal is not fusion, self-modification, or multimodality. It is a controlled empirical separation on non-stationary learning under equal resource budgets.

---

## 2. Scope and claim hierarchy

The paper distinguishes four possible outcomes. These should not be conflated.

### 2.1 Outcome A - architectural separation

DRNS produces a strictly better adaptation-retention-resource Pareto frontier than matched conventional stacks across multiple non-stationary task families, with gains surviving controller ablations and hardware accounting.

If this result is repeatable, DRNS may justify treatment as a distinct architecture family.

### 2.2 Outcome B - systems integration advantage

DRNS does not improve the fundamental learning frontier but makes a coordinated stack easier to implement, inspect, constrain, or tune.

That would be a legitimate systems contribution, but not evidence of a new learning-theoretic primitive.

### 2.3 Outcome C - notational or API value only

The developmental ontology provides a useful vocabulary and software abstraction, but matched systems achieve the same results with equal engineering effort.

This is still useful as tooling, but the architecture claim fails.

### 2.4 Outcome D - negative result

The coupling creates worse dynamics, higher metadata cost, unstable star fractions, hardware inefficiency, or poorer continual-learning performance than modular baselines.

This is a clean falsification and should terminate or substantially redirect the architecture.

The white paper is written to make all four outcomes possible.

---

## 3. Relationship to the existing Julia plasticity architecture

DRNS remains adjacent to, but distinct from, the previously specified Julia plasticity engine around SubQuad.

The prior architecture separates:

- immutable or slow base weights;
- fast contextual state;
- persistent low-rank adapters;
- a symbolic scaffold;
- typed update-rule specifications;
- isolated validation, journaling, commit, and rollback.

That architecture is **controller-level plasticity**. It asks which bounded rule should update a set of model states.

DRNS is **substrate-level plasticity**. It asks what states a parameter region is allowed to inhabit, what transitions are legal, how plasticity is represented locally, and when topology itself may change.

The two layers can ultimately compose:

```text
plasticity controller / policy
            |
            v
 developmental action request
            |
            v
 DRNS transition + resource shield
            |
            v
 bounded kernel/state mutation
```

However, the DRNS-v0 experiments defined later in this paper deliberately avoid dependence on the full plasticity engine. Otherwise a positive result could be attributed to the controller rather than the substrate.

---

## 4. The reduction concession: what DRNS does not claim

The developmental alphabet

\[
\mathcal P=\{⊥,-1,0,+1,★\}
\]

can be decomposed into more conventional metadata. For example, one can represent a site using an allocation bit, a ternary code when crystallized, and a plasticity/precision flag. Likewise, many material variables can be represented as running optimizer statistics.

This observation is accepted rather than resisted.

DRNS does **not** claim:

- that \(⊥\) cannot be implemented by a sparsity mask;
- that \(-1,0,+1\) are new quantization values;
- that \(★\) is computationally impossible to represent as a continuous shadow parameter;
- that history-dependent update laws cannot be written as optimizer state;
- that birth, pruning, quantization, or expansion are individually unprecedented;
- that a conventional computer cannot simulate the entire system.

The scientific hypothesis is instead about **coordination and inductive bias**. Architectural novelty in machine learning rarely depends on computability-theoretic impossibility. The relevant test is whether a particular organization of state and transitions produces superior learnability, stability, efficiency, or controllability.

This gives the paper a stricter burden of proof: DRNS must outperform a deliberately strong composition of the techniques to which it can be reduced.

---

## 5. Formal object: site state, block state, and global developmental state

### 5.1 Site-level state

A conceptual site is represented as

\[
p_i=(s_i,u_i),
\]

where

\[
s_i\in\{⊥,-1,0,+1,★\}
\]

and \(u_i\) is present only when the site is unresolved/plastic or when an implementation retains a latent for validation.

The site state is intentionally minimal. Expensive material metadata should not be replicated per scalar unless an experiment demonstrates that scalar-level state is necessary.

### 5.2 Block-level state

The primary unit of DRNS-v0 is a block \(B\), not an individual scalar:

\[
B=(S_B,U_B,M_B,H_B,T_B,L_B),
\]

where:

- \(S_B\): packed developmental codes for the block;
- \(U_B\): sparse or structured unresolved star latents;
- \(M_B\): material/rheological variables;
- \(H_B\): compact diagnostic history;
- \(T_B\): topology/routing/allocation metadata;
- \(L_B\): lineage and validation identifiers.

A block size should be chosen to balance three opposing objectives:

1. fine-grained plasticity;
2. metadata amortization;
3. hardware locality.

Candidate initial ranges are 64-256 weights per block for low-level experiments, followed by hardware-driven tuning.

### 5.3 Global developmental state

The complete mutable model state at developmental time \(t\) is

\[
X_t=(\Theta_t,\mathcal B_t,\Pi_t,R_t,J_t),
\]

where:

- \(\Theta_t\): ordinary trainable state not represented by DRNS blocks;
- \(\mathcal B_t\): all DRNS blocks and their complete coupled state;
- \(\Pi_t\): developmental controller state;
- \(R_t\): current resource-accounting state;
- \(J_t\): journal/checkpoint lineage state.

This full object is the unit of transactional rollback. Restoring only numeric weights is not a valid rollback.

---

## 6. Operational semantics: a developmental transition system

v0.1 described the substrate largely through analogy. v0.2 makes the transition semantics explicit.

Let \(\mathcal A\) be the set of legal developmental actions:

\[
\mathcal A=
\{\text{birth},\text{crystallize},\text{deconsolidate},\text{reclaim},\text{noop}\}
\]

for DRNS-v0.

Later extensions may add fusion, fission, rerouting, resolver mutation, or cross-lineage import, but those are not part of the minimum scientific claim.

A developmental transition is written

\[
X_t\xrightarrow{a_t,e_t}X_{t+1},
\]

where \(a_t\in\mathcal A\) and \(e_t\) is the evidence bundle used to justify the action.

Each action has three layers of semantics:

1. **preconditions** - whether the action is legal;
2. **effect** - what state changes if committed;
3. **validation** - what evidence is required before the effect becomes durable.

This is closer to a typed operational semantics than to unrestricted self-modification. A controller proposes actions; it does not directly mutate arbitrary tensors.

### 6.1 Birth

\[
⊥\rightarrow★
\]

Preconditions include vacancy, sufficient resource budget, minimum persistence of capacity pressure, and a valid target region.

### 6.2 Crystallization

\[
★\rightarrow q,\qquad q\in\{-1,0,+1\}
\]

The candidate ternary state must be derived from the unresolved latent and pass a validation gate.

### 6.3 Deconsolidation

\[
q\rightarrow★
\]

A mature site or block is reopened only after sustained evidence of mismatch, not a single noisy gradient.

### 6.4 Reclamation

\[
0\rightarrow⊥
\]

or, in restricted cases,

\[
★\rightarrow⊥.
\]

Reclamation requires a persistence condition, low measured utility, and a rollback-safe snapshot.

### 6.5 No direct sign reversal

For the minimum substrate, a mature sign change must pass through the unresolved state:

\[
+1\rightarrow★\rightarrow-1
\]

and vice versa. This is not asserted to be inherently superior; it is a scheduling constraint to be tested directly against unrestricted ternary sign updates.

---

## 7. Forward semantics of the pentanary block

For a block scale \(\alpha_B\), the effective scalar contribution is

\[
\hat w_i=
\begin{cases}
0,&s_i=⊥,\\
-\alpha_B,&s_i=-1,\\
0,&s_i=0,\\
+\alpha_B,&s_i=+1,\\
R_i(u_i,x,M_B),&s_i=★.
\end{cases}
\]

The equality of the immediate forward value of \(⊥\) and \(0\) is intentional. Their difference is developmental rather than arithmetic:

- \(0\) is allocated neutral structure with retained identity and transition rights;
- \(⊥\) is unallocated capacity.

This distinction must justify its metadata cost experimentally.

For DRNS-v0, the star resolver should be intentionally boring:

\[
R_i(u_i,x,M_B)=u_i,
\]

or a blockwise affine variant. Procedural or input-conditioned resolvers are deferred because they create an easy escape hatch in which \(★\) becomes arbitrary computation.

The block output is therefore conceptually

\[
y_B=y_B^{\text{ternary}}+y_B^{★},
\]

with the two paths implemented by separate bounded kernels.

---

## 8. Stress telemetry: operational definitions and an external witness

A developmental system should not use vague terms such as novelty or interference without measurable definitions.

For block \(B\), define the telemetry vector

\[
\sigma_B=(g_B,n_B,c_B,i_B,e_B,q_B).
\]

### 8.1 Gradient pressure

\[
g_B=\|\nabla_{\theta_B}L\|_2.
\]

For crystallized blocks whose value is not currently trainable, the diagnostic gradient may be computed through a shadow path or local sensitivity probe without immediately applying deformation.

### 8.2 Novelty

Novelty must be defined by a fixed instrument. Candidate v0 definitions include activation prediction error or representation reconstruction error:

\[
n_B=\|h_B-\hat h_B\|_2.
\]

An even simpler baseline is normalized token/task surprise. Multiple novelty definitions should be ablated rather than silently mixed.

### 8.3 Conflict

Let \(g_B^{\text{now}}\) be the current gradient prototype and \(g_B^{\text{ref}}\) a consolidated or replay-derived reference. Then

\[
c_B=\max\left(0,-\cos(g_B^{\text{now}},g_B^{\text{ref}})\right).
\]

Alternative conflict estimators such as PCGrad-like pairwise gradient disagreement can be compared.

### 8.4 Interference or retention pressure

Let \(L_{\text{ret},B}\) be a block-attributed regression loss on replay or held-out probes. Then

\[
i_B=\Delta L_{\text{ret},B}.
\]

This is intentionally distinct from current-task loss.

### 8.5 Exogenous evidence

\(e_B\) contains information not generated solely by the model's current internal representation. Examples include:

- regression probes from protected replay data;
- delayed task outcome or reward;
- teacher disagreement when a teacher is part of the experiment;
- a validation stream inaccessible to the developmental policy;
- calibrated external constraints.

The architecture therefore distinguishes

\[
\sigma_B^{\text{endo}}
\quad\text{and}\quad
\sigma_B^{\text{exo}}.
\]

Structural changes that threaten mature structure should normally require exogenous corroboration or a policy-defined exception.

### 8.6 Quantization residual

For star latent \(u_B\) and ternary candidate \(Q(u_B)\),

\[
q_B=\|u_B-Q(u_B)\|_2.
\]

This directly informs crystallization readiness.

---

## 9. Material state without dead zones: deformation and diagnostic liveness

The original hard Bingham analogy

\[
|\sigma|<\tau_y\Rightarrow\Delta=0
\]

is useful as an extreme ablation but dangerous as a default. If the same gate blocks both deformation and diagnostic state updates, a region can self-seal and lose the information required to discover that it should reopen.

v0.2 therefore separates two channels.

### 9.1 Deformation channel

A smooth yield gate is

\[
y_B=\operatorname{sigmoid}\big(\kappa(|\bar\sigma_B|-\tau_B)\big),
\]

with large \(\kappa\) approximating a hard threshold.

A plastic latent update may then be

\[
\Delta u_B=-\eta\,y_B\,D_B^{-1}g_B,
\]

where \(D_B\) is an effective viscosity/preconditioner.

### 9.2 Diagnostic channel

Even when \(y_B\approx0\), the material history continues updating:

\[
H_{B,t+1}=\lambda_H H_{B,t}+(1-\lambda_H)\psi(\sigma_{B,t}).
\]

Thus a crystallized block can be **mechanically rigid but diagnostically live**.

This distinction is central. Mature structure does not need to move in order to accumulate evidence that it is wrong.

### 9.3 Hysteresis

Use separate thresholds for crystallization and deconsolidation:

\[
\tau_{\text{melt}}>\tau_{\text{crystal}}
\]

or, more generally, state-dependent transition thresholds. This reduces rapid back-and-forth oscillation.

### 9.4 Material laws as an ablation family

The initial research program should compare:

- Newtonian/linear response;
- hard-threshold response;
- smooth-yield response;
- shear-thinning response;
- shear-thickening response;
- history-conditioned response.

The physical terminology is a design vocabulary, not evidence that the more exotic law is better.

---

## 10. The star state: anti-cheating constraints

The star-state catch-22 is the most serious structural criticism of DRNS. If too little capacity remains plastic, DRNS collapses into a ternary model with overhead. If too much remains plastic, the architecture becomes a disguised full-precision model.

v0.2 therefore places three independent hard budgets on \(★\).

### 10.1 Count budget

\[
N_{★}\le B_N,
\qquad
\rho_{★}=\frac{N_{★}}{N_{\text{alloc}}}\le\rho_{\max}.
\]

### 10.2 Memory budget

\[
M_{★}\le B_M.
\]

This includes latent values, sparse indices, alignment padding, and star-specific metadata.

### 10.3 Active-compute budget

\[
F_{★}\le B_F.
\]

This prevents a small number of star sites from hiding arbitrarily expensive resolvers.

### 10.4 Honest memory accounting

A minimum accounting model is

\[
M_{\text{total}}
=
M_{S}+M_{U}+M_{M}+M_{H}+M_{T}+M_{L}+M_{\text{optimizer}}+M_{\text{journal-amortized}}.
\]

No claim of "1.58-bit" efficiency is permitted unless all material and indexing overhead is separately reported.

---

## 11. The star-equilibrium hypothesis

Rather than assuming that a useful star fraction exists, v0.2 elevates this to a primary experimental hypothesis.

Let the coarse developmental dynamics be

\[
\rho_{★,t+1}
=
ho_{★,t}
+b_t-d_t,
\]

where \(b_t\) is normalized birth/deconsolidation flow into \(★\) and \(d_t\) is normalized crystallization/reclamation flow out of \(★\).

A useful substrate requires an operating regime with

\[
0<\rho_{★}^*<\rho_{\max}
\]

such that the equilibrium is dynamically stable for a meaningful range of workloads and hyperparameters.

The first serious DRNS experiment should therefore produce a **phase diagram**, not a language benchmark.

Candidate axes include:

\[
(\lambda_{★},\tau_{\text{crystal}},\tau_{\text{melt}},\rho_{\max},\kappa).
\]

Observed phases may include:

```text
frozen regime      mixed developmental regime      runaway plasticity
rho_star ~ 0       0 < rho_star < rho_max          rho_star -> rho_max
```

If the mixed phase exists only in an extremely narrow or non-transferable hyperparameter ridge, that is evidence against the architecture.

---

## 12. Crystallization as validated compilation

Crystallization converts expensive unresolved state into cheap discrete structure:

\[
★\rightarrow q,
\qquad
q=Q(u_B)\in\{-1,0,+1\}.
\]

The operation has three distinct parts.

### 12.1 Candidate formation

A blockwise ternary quantizer produces \(q\) and scale \(\alpha_B\).

### 12.2 Local readiness test

The quantization residual \(q_B\), confidence, stability duration, and regression sensitivity determine whether the candidate is eligible for external validation.

### 12.3 Validation gate

Let a protected regression suite contain \(m\) independent or approximately independent probe examples. Suppose the observed degradation is \(\hat\epsilon\). A simple Hoeffding-style bound gives

\[
\epsilon_{\text{true}}
\lesssim
\hat\epsilon+
\sqrt{\frac{\log(1/\delta)}{2m}}
\]

under the usual bounded-loss assumptions.

This is not a complete safety proof, but it formalizes the idea that crystallization is a statistical hypothesis test rather than an unconditional quantization step.

### 12.4 Validation cost is part of the budget

The cost of the regression suite must be reported. A system that saves inference FLOPs but spends enormous offline compute validating every transition may not be more efficient overall.

---

## 13. Deconsolidation and liveness

A mature block must be capable of reopening when sustained evidence shows that its discrete representation is no longer adequate.

Define a deconsolidation score

\[
D_B=w_c c_B+w_i i_B+w_e e_B+w_q q_B+w_h H_B.
\]

A block becomes eligible for deconsolidation only if

\[
D_B>\tau_{\text{melt}}
\]

for a minimum dwell duration \(T_{\text{melt}}\), and if the resource shield can allocate the resulting star capacity.

Critically, diagnostic history continues to update while the block is crystallized. This gives a liveness condition:

> If persistent exogenous contradiction remains above a fixed lower bound and the star resource budget eventually has free capacity, then the controller must have a legal path to propose deconsolidation.

This condition is weaker than a theorem of eventual correction, but it prevents permanent self-locking by construction.

---

## 14. Growth, vacancy, and capacity pressure

DRNS distinguishes numerical neutrality from structural vacancy:

\[
0\neq⊥
\]

in the developmental state machine even though both may contribute zero to the immediate forward pass.

### 14.1 Capacity pressure

Rather than a single hand-wavy scalar, define a vector

\[
P_B=(C_B,S_B,N_B,R_B,A_B),
\]

where candidate components include persistent conflict, saturation, novelty, retention failure, and local allocation pressure.

A controller may scalarize these features, but the raw vector should remain available for analysis.

### 14.2 Growth must not be driven by training loss alone

A birth action is eligible only if:

1. pressure persists for a minimum dwell interval;
2. a matched no-growth optimization step has failed to resolve the pressure;
3. protected validation does not indicate pure memorization;
4. hard resource budgets permit allocation;
5. the controller can identify a target block or neighboring reserve region.

### 14.3 Growth objective

A practical developmental objective can be written

\[
J_{\text{dev}}
=
L_{\text{val}}
+\lambda_A C_{\text{alloc}}
+\lambda_{★} C_{★}
+\lambda_F C_{\text{FLOPs}}
+\lambda_L C_{\text{latency}}
+\lambda_C C_{\text{churn}}.
\]

This objective is not claimed to be a theorem. PAC-Bayes or MDL analyses may later characterize the complexity cost of growth, but v0.2 does not require an online PAC-Bayes oracle.

### 14.4 Structural birth

Approved growth performs

\[
⊥\rightarrow★
\]

at block granularity or within a bounded reserve block.

The new structure starts unresolved and must earn crystallization through use and validation.

---

## 15. Reclamation and two-stage forgetting

A crystallized zero is not immediately deleted. This creates a two-stage forgetting process:

\[
\{-1,+1\}\rightarrow0\rightarrow⊥.
\]

The intermediate zero state preserves identity and allows rapid reactivation while signaling low current utility.

A block or site is reclaimable only after:

- low utilization for a dwell interval;
- low contribution under attribution or ablation probes;
- low conflict with protected retention data;
- no active lineage dependency that would invalidate imported deltas or rollback;
- successful transactional checkpoint creation.

Reclamation should be significantly slower than birth in early prototypes. Aggressive pruning can create oscillatory capacity churn that obscures the developmental dynamics.

---

## 16. Developmental control as a constrained decision process

The substrate and controller must be experimentally separable.

Let the controller observe

\[
o_t=(\sigma_t,M_t,H_t,R_t),
\]

and propose

\[
a_t\in\mathcal A.
\]

The environment then applies a **resource and safety shield** \(\mathcal S\):

\[
\tilde a_t=\mathcal S(o_t,a_t).
\]

An unsafe action is rejected or replaced by `noop` regardless of controller preference.

### 16.1 Hard resource constraints

At minimum:

\[
M_t\le M_{\max},
\qquad
F_t\le F_{\max},
\qquad
L_t\le L_{\max}.
\]

The shield enforces these by construction.

### 16.2 Controller progression

The research sequence should be:

1. deterministic hand-authored policy;
2. learned scoring model for candidate transitions;
3. optional learned developmental policy;
4. only later, meta-RL or planning over long-horizon structural actions.

A positive DRNS result at stage 1 is much easier to attribute to the substrate than a result obtained only with an elaborate learned controller.

---

## 17. Optional self-model: predictive metacognition, not consciousness

A self-model is an optional subsystem

\[
S_\phi(o,a)
\rightarrow
(\widehat{\Delta L},\widehat{\Delta M},\widehat{\Delta F},\widehat{\Delta R}_{\text{ret}}).
\]

It predicts the consequences of a proposed developmental action using the journal as supervised training data.

The controller may use these predictions to rank candidates before expensive validation.

This capability is intentionally **not** part of DRNS-v0. Otherwise a reviewer could reasonably argue that an intelligent model-based controller, rather than the developmental substrate, produced any observed gain.

The required ablation is therefore:

\[
\text{DRNS}_{\text{heuristic}}
\quad\text{vs}\quad
\text{DRNS}_{S_\phi}.
\]

If the self-model improves results, that becomes a second research contribution rather than a hidden dependency of the first.

---

## 18. Stability: hysteresis, dwell time, and bounded coupling

A universal Lyapunov function for the entire developmental process is not assumed. In a non-stationary environment, useful adaptation may temporarily increase a static energy-like objective.

Instead, v0.2 separates hard invariants from soft dynamical stability.

### 18.1 Hard invariants

Examples:

- resource limits cannot be exceeded;
- invalid state transitions cannot be committed;
- protected regression loss cannot exceed a configured catastrophic threshold during commit;
- every committed mutation has a parent snapshot;
- star budgets cannot be exceeded.

### 18.2 Hysteresis

Use different open/close thresholds and minimum dwell times:

\[
T_{\text{birth}},
T_{\text{crystal}},
T_{\text{melt}},
T_{\text{reclaim}}.
\]

### 18.3 Bounded neighborhood coupling

Material-state diffusion is optional in v0.2 and should begin with

\[
M_{i,t+1}
=f(M_{i,t},\sigma_{i,t})
+\lambda\sum_{j\in N(i)}w_{ij}(M_{j,t}-M_{i,t}),
\]

with

\[
0\le\lambda<\lambda_{\max}
\]

chosen to avoid phase avalanches.

Because pure diffusion homogenizes rather than differentiates, emergent modularity is **not** claimed from this term alone. Any symmetry-breaking mechanism must be explicit and separately tested.

---

## 19. Transactional journaling and rollback

The developmental state is coupled. Therefore rollback is a consistency operation, not checkpoint arithmetic.

A durable version \(V_k\) records at minimum:

\[
V_k=(\Theta_k,\mathcal B_k,\Pi_k,R_k,\text{RNG}_k,\text{layout}_k,\text{hashes}_k).
\]

A rollback performs

\[
X_t\rightarrow X_k
\]

atomically.

No component is allowed to retain future state such as hysteresis, failure traces, controller statistics, or routing metadata unless the rollback mode explicitly declares that behavior.

### 19.1 Decision reproducibility vs. bit-exact reproducibility

Real accelerators may use nondeterministic floating-point reductions. v0.2 therefore distinguishes:

- **decision reproducibility:** the developmental action, evidence bundle, candidate version, and validation decision are journaled and replayable;
- **bit-exact arithmetic reproducibility:** every floating-point intermediate reproduces identically.

The first is required. The second is a stronger optional mode whose cost must be reported.

---

## 20. Hardware execution model

DRNS must be judged on the hardware that actually executes it, not on theoretical bits per weight.

### 20.1 Block granularity

State transitions occur at block, segment, or consolidation boundaries. Per-scalar transition dispatch in the hot path is out of scope for v0.

### 20.2 Bounded kernel family

The minimum runtime should have a small set of precompiled kernels:

1. crystallized ternary block kernel;
2. sparse/structured star block kernel;
3. mixed-block composition kernel if necessary.

The controller selects among these kernels using compact state tags. It does not synthesize a fresh kernel for every changing block.

### 20.3 Layout epochs

Topology changes accumulate within a developmental epoch. Physical compaction and remapping occur only at explicit layout boundaries.

This reduces cache invalidation and lets the hot path operate over relatively stable memory layouts.

### 20.4 Required hardware metrics

Every experiment reports:

- allocated bytes;
- peak training bytes;
- star-index bytes;
- metadata bytes;
- journal bytes amortized over time;
- active FLOPs/token;
- measured memory bandwidth;
- kernel occupancy where available;
- wall-clock tokens/s;
- consolidation time;
- transition-validation time.

Nominal ternary bit-width is never reported as the sole memory metric.

---

## 21. Julia-native execution strategy

Julia remains attractive because DRNS is simultaneously a numerical system, a typed state machine, and a compiler/runtime experiment. The design must nevertheless respect Julia's performance model.

### 21.1 Closed rheology tags in hot state

Do not create an unbounded zoo of runtime concrete types. A practical hot representation is a compact tag or small isbits union:

```julia
@enum RheologyID::UInt8 begin
    R_LINEAR
    R_SMOOTH_YIELD
    R_THINNING
    R_THICKENING
    R_HISTORY
end
```

Kernel families can still use multiple dispatch at coarse boundaries where types are stable.

### 21.2 Concrete callable fields

Avoid abstract `Function` fields in performance-critical structs. Parameterize callable types or use concrete model objects.

```julia
struct DevController{F,G,H}
    score_birth::F
    score_melt::G
    score_crystal::H
end
```

### 21.3 Generated functions are not a runtime oracle

`@generated` functions specialize on types and compile-time information; they should not be treated as a magical mechanism that inspects arbitrary runtime star distributions.

Runtime specialization should instead choose from a bounded kernel catalog, with optional compilation at coarse checkpoints when a genuinely new specialization is justified.

### 21.4 Restricted generated code

`RuntimeGeneratedFunctions.jl` or related techniques may later support bounded procedural resolvers, but generated code is not a security boundary. Any model-derived program must pass through a restricted IR, capability checks, quotas, and an isolated worker process.

### 21.5 AD

Enzyme.jl or another AD system may differentiate continuous star latents and learnable material parameters. Structural transitions remain discrete outer-loop events in the minimum architecture.

### 21.6 Candidate package boundaries

```text
DRNS.jl/
  src/
    States.jl              # pentanary codes and packed block state
    Blocks.jl              # block containers and views
    Stress.jl              # operational telemetry definitions
    Rheology.jl            # constitutive response families
    Transitions.jl         # typed developmental actions
    Shield.jl              # hard resource and safety constraints
    Consolidation.jl       # candidate quantization + regression gates
    Topology.jl            # vacancy/birth/reclamation
    Kernels.jl             # ternary + star runtime kernels
    Controller.jl          # replaceable developmental policies
    SelfModel.jl           # optional consequence predictor
    Journal.jl             # transactional versions and rollback
    Metrics.jl             # developmental and hardware accounting
  test/
    semantics/
    liveness/
    phase_diagrams/
    continual_learning/
    determinism/
    hardware/
    falsification/
```

The package architecture should make each mechanism individually disable-able.

---

## 22. Training semantics

DRNS introduces three timescales.

### 22.1 Fast numeric learning

Continuous star latents and ordinary trainable parameters update at standard optimizer cadence.

### 22.2 Developmental observation

Stress, material history, utilization, and resource metrics update continuously or once per small chunk.

### 22.3 Structural transition cadence

Birth, crystallization, deconsolidation, reclamation, and layout changes occur at much coarser boundaries.

This separation prevents the architecture from recompiling or rearranging topology every token.

### 22.4 Wake/consolidation distinction

A useful operational mode is:

```text
wake / online phase:
    learn star latents
    collect stress
    allow bounded birth or deconsolidation

consolidation boundary:
    propose crystallization
    run regression gates
    reclaim stale neutral structure
    compact layout if needed
    commit transactional version
```

"Developmental sleep" remains a metaphor for this offline consolidation phase, not a claim of biological equivalence.

---

## 23. Mathematical hypotheses and propositions

v0.2 does not invent a grand theorem whose assumptions silently guarantee success. It instead states several progressively stronger propositions.

### 23.1 Conflict-gap proposition

Let \(K\) task contexts have losses \(L_k(\theta)\) and mixture weights \(p_k\). Define

\[
\Delta_{\text{conflict}}
=
\min_\theta\sum_{k=1}^Kp_kL_k(\theta)
-
\sum_{k=1}^Kp_k\min_{\theta_k}L_k(\theta_k).
\]

If task optima are incompatible, then

\[
\Delta_{\text{conflict}}>0.
\]

A system with sufficient conditional capacity and correct context routing can in principle approach the second term more closely than a system forced to use one shared parameter solution.

This proposition does **not** establish DRNS superiority by itself. It only formalizes the potential value of allocating separate structure under persistent conflict.

### 23.2 Bounded-star memory proposition

Let \(b_c\) be average bytes per crystallized site including state code and scaling overhead, \(b_{★}\) be average bytes per star site including indices and latent state, and \(\rho_{★}\le\rho_{\max}\). Then

\[
M
\le
N_{\text{alloc}}
\left[
 b_c+
ho_{\max}(b_{★}-b_c)
\right]
+M_{\text{block-metadata}}.
\]

This bound is elementary but important: DRNS cannot claim cheap mature computation unless \(\rho_{\max}\), \(b_{★}\), and metadata are all controlled.

### 23.3 Safe-crystallization proposition

Under bounded-loss and approximately independent regression probes, a candidate whose observed degradation is \(\hat\epsilon\) on \(m\) probes has true degradation bounded with high probability by a standard concentration term. This provides a statistical commit gate, not a guarantee of global safety.

### 23.4 Liveness proposition

Given persistent contradiction above a configured threshold, continuing diagnostic updates, finite dwell time, and eventual availability of star budget, there must exist a legal path from crystallized state to \(★\).

The point is architectural: a rigid state must not be absorbing unless explicitly declared immutable.

### 23.5 Minimal empirical separation proposition

There exists at least one preregistered non-stationary task distribution \(\mathcal D\) and budget tuple \(B\) such that the DRNS-v0 Pareto frontier is not dominated by the matched Everything-Bagel baseline over

\[
(\text{capability},\text{retention},\text{adaptation speed},\text{active FLOPs},\text{peak memory},\text{latency}).
\]

A stronger result would show this across multiple qualitatively different task families and model scales.

### 23.6 What v0.2 explicitly does not claim

It does not claim a general \(O(\sqrt T)\) regret bound against all fixed-topology models. Such a statement would require restrictive assumptions on the task process, comparator class, routing information, and available capacity. Regret theory may become useful after the empirical mechanisms are understood.

---

## 24. The adversarial baseline: the Everything Bagel

Weak baselines would make the project scientifically meaningless. The primary comparator should deliberately absorb as much of DRNS as possible without adopting the unified developmental substrate.

A candidate Bagel stack is:

```text
ternary / QAT backbone
+ dynamic sparsity or structured pruning/regrowth
+ AdamW or another strong optimizer
+ EWC or replay-based continual-learning protection
+ expandable adapters / modules
+ fixed or expandable expert routing where appropriate
+ explicit resource controller
+ matched validation and tuning budget
```

The exact components should be preregistered before the final experiment.

The test is not whether DRNS beats a dense Transformer. The test is whether the coupled substrate produces a measurable advantage over a strong modular system solving the same problems.

### 24.1 Controller fairness

The DRNS controller and Bagel controller receive the same telemetry family where possible, the same validation access, and comparable hyperparameter search budgets.

### 24.2 Human-effort fairness

"Equal human effort" is difficult to operationalize. Rather than pretending it can be measured perfectly, experiments should report:

- number of tuned hyperparameters;
- search trials;
- wall-clock tuning budget;
- manual interventions;
- architecture-specific code paths.

This at least exposes asymmetry.

---

## 25. Experimental program

### Stage 0 - deterministic semantics simulator

No neural language model. Implement only the developmental state machine, budgets, liveness, dwell time, transactional rollback, and synthetic stress signals.

Success criteria:

- no illegal transitions;
- rollback restores complete coupled state;
- resource shield is inductively safe;
- state churn remains bounded under stationary input;
- diagnostic liveness remains active under rigid forward state.

### Stage A - star-equilibrium phase diagrams

Use a tiny differentiable network and sweep the star-control parameters.

Primary outputs:

- \(\rho_{★}(t)\);
- transition rates;
- retention;
- adaptation speed;
- metadata bytes;
- wall-clock overhead.

The goal is to determine whether a stable mixed developmental phase exists.

### Stage B - controlled non-stationary toy tasks

Use task families designed to induce known forms of conflict:

- alternating incompatible label mappings;
- recurring permutations;
- class-incremental streams;
- associative mappings with controlled collisions;
- synthetic contexts with explicit latent task identity withheld from the learner.

Compare:

- fixed full-precision;
- fixed ternary;
- dynamic sparse;
- continual-learning baselines;
- expandable module baseline;
- Everything Bagel;
- DRNS with fixed controller;
- DRNS with individual mechanisms ablated.

### Stage C - small sequence model, roughly 1M-20M parameters

Before a 60M-100M language model, run enough scale to expose block-locality, kernel, and gradient-noise effects that toy MLPs hide.

Use synthetic language or small corpora with explicit distribution shifts.

### Stage D - 60M-100M language model

Only after the developmental phase is stable.

Train from scratch under fixed data and compute budgets.

Possible non-stationary protocols:

- domain sequence A->B->A;
- language/domain specialization with recurring return;
- code/general-language alternation;
- synthetic skill injection followed by protected regression;
- continual pretraining streams with known distribution shifts.

### Stage E - 300M to 1B scaling

Scale only if the DRNS frontier remains competitive after full hardware accounting. Re-establish stability at every scale; do not assume small-scale dynamics compose automatically.

### Stage F - deferred extensions

Only after the core substrate succeeds:

- fusion/fission;
- learned self-model;
- learned developmental policy;
- portable deltas;
- procedural star resolvers;
- multimodality;
- larger model families.

---

## 26. Metrics

The central object is a frontier, not a single benchmark score.

### 26.1 Learning metrics

- current-task loss or accuracy;
- retained-task loss or accuracy;
- forward transfer;
- backward transfer;
- adaptation samples to target performance;
- recovery after returning to an earlier distribution;
- catastrophic-regression count.

### 26.2 Developmental metrics

- \(\rho_{★}\) over time;
- birth rate;
- crystallization rate;
- deconsolidation rate;
- reclamation rate;
- mean dwell time per state;
- transition rejection rate;
- validation-failure rate;
- fraction of capacity in each developmental phase.

### 26.3 Efficiency metrics

- total bytes;
- active bytes/token;
- active FLOPs/token;
- tokens/s;
- latency;
- energy where measurable;
- validation compute;
- consolidation compute;
- total training compute, including developmental overhead.

### 26.4 Stability metrics

- oscillation frequency;
- maximum transition avalanche size;
- long-horizon drift;
- repeated crystallization cycle loss;
- rollback recovery error;
- star-equilibrium sensitivity to hyperparameters.

### 26.5 Accounting metrics

A model is described by at least:

\[
(P_{\text{addressable}},
P_{\text{allocated}},
P_{★},
P_{\text{active/token}},
M_{\text{total}}).
\]

A single "parameter count" is insufficient.

---

## 27. Falsification criteria

DRNS-v0 should be considered falsified or materially weakened if any of the following hold under competent implementation.

1. **No stable mixed phase.** \(\rho_{★}\) consistently collapses toward zero or saturates at the cap across useful workloads.
2. **Bagel dominance.** The matched modular baseline dominates DRNS on the adaptation-retention-efficiency frontier.
3. **Metadata erases compression.** Real memory use is comparable to or worse than dense low-precision baselines with no compensating capability gain.
4. **Growth is memorization.** Added capacity improves training loss without improving protected validation or long-horizon retention.
5. **Controller dependence.** Gains disappear when the controller is replaced by a simple matched policy, indicating that the controller rather than the substrate carries the result.
6. **Deadlock.** Mature regions fail to reopen under persistent exogenous contradiction despite available resources.
7. **Thrashing.** Hysteresis and dwell time cannot prevent frequent state oscillation without freezing useful adaptation.
8. **Generational loss.** Repeated melt/crystallize cycles accumulate unacceptable degradation.
9. **Hardware loss.** Wall-clock throughput or latency is substantially worse than matched baselines despite nominal FLOP or bit savings.
10. **Scale instability.** Dynamics that appear useful at toy scale fail repeatedly as block count and gradient noise grow.
11. **Vacancy redundancy.** \(⊥\) and allocated-zero semantics provide no measurable advantage over conventional structured masks.
12. **Lifecycle redundancy.** The enforced \(⊥\rightarrow★\rightarrow\{-1,0,+1\}\) schedule provides no benefit over unconstrained progressive quantization and dynamic sparsity.

A single failed experiment does not prove the entire research direction impossible, but repeated failure on these core criteria should prevent claim escalation.

---

## 28. Major failure modes and required diagnostics

### 28.1 Rich-get-richer lock-in

Early crystallized paths may receive more useful gradient flow and become progressively harder to challenge.

Required diagnostics:

- age vs. utilization curves;
- age vs. deconsolidation probability;
- controlled perturbation tests on old and young blocks;
- protected exogenous probes.

### 28.2 Endogenous confirmation loops

The model's own structure shapes the gradients used to judge that structure.

Mitigation:

- explicit exogenous stress channel;
- frozen evaluation probes;
- delayed outcome signals;
- policy ablations with telemetry channels removed.

### 28.3 Star explosion

Mitigation is not merely a penalty; it is a hard triple budget plus rejection of births/deconsolidations when the budget is exhausted.

### 28.4 Premature crystallization

Measure performance as a function of crystallization age and confidence. Require minimum dwell and regression support.

### 28.5 Phase avalanches

Record the number of transitions triggered within a causal window. Cap neighborhood coupling and optionally limit transitions per block group per consolidation epoch.

### 28.6 Fragmentation

Dynamic growth can destroy locality. Report physical block fragmentation and bytes moved during compaction.

### 28.7 Journal explosion

Store deltas and summaries rather than full high-frequency snapshots. Checkpoint full transactional state only at configured commit boundaries.

### 28.8 Provenance without attribution

Lineage tells where a block came from, not why a behavior exists. The paper therefore does not claim full causal interpretability. Attribution remains a separate research problem.

### 28.9 Scale-dependent behavior

Re-run the phase diagram and liveness tests at every major scale increase. No stability result is assumed to transfer automatically.

---

## 29. Long-term cycle loss

A long-lived developmental system may repeatedly execute

\[
\text{crystallize}\rightarrow\text{deconsolidate}\rightarrow\text{crystallize}.
\]

If each cycle loses information, the model can degrade slowly even without dramatic catastrophic forgetting.

Define per-cycle distortion for block \(B\):

\[
d_B^{(k)}
=
D\big(f_B^{(k,\text{before})},f_B^{(k,\text{after})}\big),
\]

where \(D\) may be output divergence, representation distance, or regression loss.

Track cumulative distortion

\[
D_B^{(K)}=\sum_{k=1}^K d_B^{(k)}
\]

and compare it with a continuously trained low-precision or full-precision baseline.

A practical design may cap the number of deconsolidation cycles for mature blocks or retain a higher-precision parent snapshot for rare high-value regions.

---

## 30. Deferred extension: fusion and fission

Fusion and fission remain interesting but are no longer part of the first architectural claim.

### 30.1 Why fusion is deferred

Lineage identity does not imply basis alignment. Two descendants of the same seed can rotate, permute, or otherwise reorganize representations.

Any future fusion system must distinguish:

1. **identity-preserving fusion** - blocks whose representation basis was constrained to remain aligned;
2. **aligned fusion** - correspondence established by weight matching, activation matching, optimal transport, or related methods;
3. **functional fusion** - no direct tensor merge; retain separate modules and distill or route functionally.

Failure to align should count as evidence for modular separation rather than as a mandate to average incompatible tensors.

### 30.2 Why fission is deferred

Naively duplicating a block creates highly correlated twins and may reproduce expert-collapse problems from MoE systems. Future fission must include symmetry breaking, routing specialization, and hardware-locality constraints.

---

## 31. Deferred extension: developmental deltas and model lineage ecosystems

Portable developmental deltas remain a compelling long-term systems idea, but v0.2 acknowledges a combinatorial validation problem.

If delta \(A\) and delta \(B\) each pass independently, it does not follow that

\[
A\circ B
\]

is safe or useful.

Future delta ecosystems therefore need one of:

- compatibility manifests restricting composition classes;
- bounded dependency graphs;
- compositional regression suites;
- functional isolation through routing;
- curated signed release channels.

Hardware-specific topology growth also reduces delta portability. For that reason the first lineage system should track **semantic capability patches** separately from **physical layout patches**.

---

## 32. Deferred extension: multimodality

Multimodal DRNS is not part of the core experiment because different modalities operate at different temporal rates and may generate confounded stress signals.

A future system must define:

- separate modality clocks;
- synchronization points for shared developmental state;
- attribution of capacity pressure by modality;
- rules for partially crystallized shared concepts;
- validation costs that do not grow combinatorially with modality count.

Until those problems are solved, multimodal results cannot be used as evidence for the core DRNS claim.

---

## 33. Safety and governance boundaries

DRNS is not permission for arbitrary self-modification.

### 33.1 No unrestricted code generation in the core architecture

The substrate manipulates typed developmental actions and bounded state, not arbitrary Julia source.

### 33.2 Resource shielding is external to learned preference

The model cannot vote itself more memory or bypass latency caps.

### 33.3 Commit/rollback is mandatory

Every durable mutation has a parent version, evaluation record, resource record, and complete transactional snapshot or reconstructable delta chain.

### 33.4 Protected evaluations remain inaccessible during proposal

A developmental policy must not optimize directly against the final holdout suite.

### 33.5 Capability claims remain empirical

No transition from successful adaptation to claims of recursive self-improvement, agency, or consciousness is warranted. The minimum architecture is a bounded adaptive learner.

---

## 34. Model identity and honest size reporting

A developmental model is better described as a lineage than as a single immutable checkpoint:

\[
\mathcal M_t=(\mathcal M_0,V_1,V_2,\ldots,V_t).
\]

However, this does not justify loose statements such as "a 27B model became a 44B model" without further accounting.

A mature reporting format should include:

```text
addressable capacity
allocated capacity
star / unresolved capacity
active parameters per token
physical memory footprint
material-state overhead
journal overhead
peak training footprint
```

Two models with the same allocated parameter count may have radically different active compute and unresolved-state fractions.

---

## 35. Roadmap

### Phase 0 - v0.2 semantics

Implement the state machine, stress instrumentation, shield, complete rollback, and accounting in a deterministic simulator.

### Phase 1 - star-phase experiment

Map the frozen / mixed / runaway regimes and identify whether a stable mixed phase exists.

### Phase 2 - continual-learning microbenchmarks

Test whether lifecycle coupling improves the adaptation-retention frontier against strong baselines.

### Phase 3 - 1M-20M sequence models

Stress hardware layout, gradient noise, and block dynamics.

### Phase 4 - 60M-100M language model

Train from scratch only after the primitive survives prior stages.

### Phase 5 - 300M-1B

Re-establish stability and hardware advantage at larger scale.

### Phase 6 - advanced controllers

Add learned consequence prediction and learned developmental policies only after simple-controller DRNS has demonstrated independent value.

### Phase 7 - topology extensions

Investigate alignment-aware fusion, symmetry-broken fission, and expert formation.

### Phase 8 - lineage ecosystem and multimodality

Treat both as separate research programs contingent on core success.

---

## 36. Strongest claim allowed before experiments

The strongest defensible pre-experimental statement is:

> **Hypothesis:** On non-stationary workloads, a block-level developmental substrate that jointly controls allocation, plasticity, precision, consolidation, and reclamation under hard resource budgets may achieve a better adaptation-retention-efficiency frontier than matched modular systems implementing those operations independently.

It is not yet defensible to claim:

- that DRNS is computationally irreducible to conventional training systems;
- that the pentanary alphabet is a new mathematical number system;
- that rheology provides inherently superior optimization;
- that DRNS is smarter per nominal parameter;
- that growth prevents catastrophic forgetting;
- that the architecture will outperform Transformers at equal pretraining compute;
- that fusion or fission will work at scale;
- that Julia itself creates a learning-theoretic advantage;
- that the system performs recursive self-improvement.

---

## 37. What would count as a meaningful positive result?

A meaningful result is not "DRNS trains." It is one of the following.

### 37.1 Minimal positive result

On preregistered non-stationary tasks, DRNS with a simple controller reaches a retention-adaptation point that the Everything Bagel baseline cannot reach under equal peak memory, active compute, data, and tuning budgets.

### 37.2 Strong systems result

DRNS matches the Bagel frontier but requires materially less controller complexity, fewer tuning trials, or lower transition-validation overhead.

### 37.3 Strong architectural result

The advantage persists across multiple task families and scales, survives replacement of the hand-authored controller, and is associated with a stable mixed star phase rather than hidden growth or full-precision escape.

### 37.4 Transformative result

At larger scale, the same local lifecycle yields robust capacity growth, stable long-term learning, and useful emergent modularity without explicit task partitioning while retaining favorable active-compute and hardware costs.

The final category is intentionally aspirational. Nothing in v0.2 assumes it will occur.

---

## 38. Conclusion

DRNS began with a deliberately strange metaphor: what if learned weights behaved less like passive numbers and more like computational material?

The adversarial reviews were valuable because they stripped away the parts of that metaphor that were too easy to mistake for novelty. Vacancy can be represented as a mask. Ternary states are quantization. Star latents can resemble unquantized shadow weights. Material history can resemble optimizer state. Growth can resemble dynamic sparsity or expandable networks. None of these observations kills the project; they clarify the experiment.

The architecture now stands or falls on a more precise proposition. It treats several operations that are usually independent - allocation, precision, plasticity, consolidation, and structural capacity - as state transitions inside one bounded local developmental system. It then asks whether that coupling yields a measurable advantage under honest resource accounting.

The core lifecycle remains:

\[
\boxed{⊥\rightarrow★\rightarrow\{-1,0,+1\}}
\]

but v0.2 adds the conditions that make the lifecycle scientifically testable:

- star capacity is bounded by count, memory, and compute;
- rigid structure remains diagnostically live;
- exogenous evidence can challenge endogenous beliefs;
- growth is gated by validation and hard resource shields;
- rollback restores the full coupled developmental state;
- hardware costs are measured in real bytes and wall-clock time;
- the controller is replaceable and separately ablated;
- a deliberately strong modular baseline is treated as the main adversary;
- fusion, fission, multimodality, portable deltas, and learned self-models are deferred until the substrate earns them.

The resulting research question is narrower than the original vision, but much harder to dismiss:

> **Can a neural network benefit when its computational substrate has a bounded lifecycle for becoming plastic, crystallizing, reopening, growing, and disappearing - and when those operations are coordinated locally rather than bolted together globally?**

If the answer is no, DRNS becomes a useful negative result or software ontology. If the answer is yes only as an engineering abstraction, it becomes a systems contribution. If the answer is yes under matched compute, memory, and data budgets across scales, then the idea begins to justify the stronger language of a developmental neural architecture.

The next step is not another conceptual expansion. It is implementation of the smallest system capable of proving this paper wrong.

---

## References

[1] T. Miconi, K. Stanley, J. Clune. "Differentiable plasticity: training plastic neural networks with backpropagation." ICML / PMLR 80, 2018. https://proceedings.mlr.press/v80/miconi18a.html

[2] I. Schlag, K. Irie, J. Schmidhuber. "Linear Transformers Are Secretly Fast Weight Programmers." ICML / PMLR 139, 2021. https://proceedings.mlr.press/v139/schlag21a.html

[3] Y. Sun et al. "Learning to (Learn at Test Time): RNNs with Expressive Hidden States." ICML / PMLR 267, 2025. https://proceedings.mlr.press/v267/sun25h.html

[4] A. Behrouz, P. Zhong, V. Mirrokni. "Titans: Learning to Memorize at Test Time." 2025. https://arxiv.org/abs/2501.00663

[5] U. Evci, T. Gale, J. Menick, P. S. Castro, E. Elsen. "Rigging the Lottery: Making All Tickets Winners." 2019/2020. https://arxiv.org/abs/1911.11134

[6] J. Yoon, E. Yang, J. Lee, S. J. Hwang. "Lifelong Learning with Dynamically Expandable Networks." 2017. https://arxiv.org/abs/1708.01547

[7] J. Kirkpatrick et al. "Overcoming catastrophic forgetting in neural networks." Proceedings of the National Academy of Sciences 114(13), 2017. https://doi.org/10.1073/pnas.1611835114

[8] D. Ha, A. Dai, Q. V. Le. "HyperNetworks." 2016. https://arxiv.org/abs/1609.09106

[9] F. Li, B. Liu, X. Wang, B. Zhang, J. Yan. "Ternary Weight Networks." 2016. https://arxiv.org/abs/1605.04711

[10] S. Ma et al. "The Era of 1-bit LLMs: All Large Language Models are in 1.58 Bits." Microsoft Research / arXiv, 2024. https://arxiv.org/abs/2402.17764

### Related-method families requiring dedicated literature review before external submission

The adversarial review identified several additional comparison families that should be incorporated into a formal related-work matrix before any external release: Progressive Neural Networks, Net2Net-style growth, Task Arithmetic, TIES-style merging, DARE-style merging, GEM/A-GEM replay methods, PCGrad/CAGrad conflict handling, hardware-aware NAS, progressive quantization, and expandable-adapter systems. v0.2 uses these as comparison targets but does not claim bibliographic completeness.

### Companion internal materials

- *SubQuad Plasticity Architecture*, internal research design note, 2026-09-15.
- Three independent adversarial review passes of DRNS v0.1: broad architecture review, mathematical-reduction review, and systems-failure review. These critiques informed v0.2 but are not empirical evidence for the architecture.

---

## Appendix A. Compact notation

| Symbol | Meaning |
|---|---|
| \(⊥\) | vacant / unallocated developmental state |
| \(-1,0,+1\) | crystallized ternary states |
| \(★\) | unresolved / plastic developmental state |
| \(S_B\) | packed state codes for block \(B\) |
| \(U_B\) | unresolved star latent storage |
| \(M_B\) | material/rheological state |
| \(H_B\) | diagnostic history / hysteresis state |
| \(T_B\) | topology / allocation / routing metadata |
| \(L_B\) | lineage / version metadata |
| \(\sigma_B\) | stress telemetry vector |
| \(g_B\) | gradient pressure |
| \(n_B\) | novelty |
| \(c_B\) | conflict |
| \(i_B\) | retention/interference pressure |
| \(e_B\) | exogenous evaluation signal |
| \(q_B\) | quantization residual |
| \(\rho_{★}\) | star fraction among allocated sites |
| \(B_N,B_M,B_F\) | star count, memory, and compute budgets |
| \(X_t\) | complete developmental system state |
| \(\mathcal A\) | legal developmental action set |
| \(\mathcal S\) | hard resource/safety shield |

---

## Appendix B. Transition table for DRNS-v0

| Source | Target | Name | Minimum evidence | Hard checks |
|---|---|---|---|---|
| \(⊥\) | \(★\) | birth | persistent capacity pressure | star budget, resource budget, dwell |
| \(★\) | \(-1,0,+1\) | crystallize | low quantization residual + stability | regression gate, dwell |
| \(-1,0,+1\) | \(★\) | deconsolidate | sustained contradiction | star budget, exogenous corroboration, dwell |
| \(0\) | \(⊥\) | reclaim | persistent low utility | rollback snapshot, dependency check |
| \(★\) | \(⊥\) | abort/reclaim | failed or obsolete experiment | rollback snapshot |
| any | same | noop | default | always legal |

Direct \(+1\leftrightarrow-1\) transitions are disallowed in DRNS-v0 and must pass through \(★\). This is an experimental design choice, not a claimed universal law.

---

## Appendix C. Example developmental loop

```text
initialize model, budgets, journal, and protected probes

for each training chunk:
    run ordinary forward/backward computation
    update continuous star latents

    for each DRNS block:
        endo = measure_endogenous_stress(block)
        exo  = update_exogenous_probes_if_due(block)
        update_diagnostic_history!(block, endo, exo)

        proposals = controller.propose(block, endo, exo, resource_state)
        proposals = shield.filter(proposals)
        queue(proposals)

    if developmental_boundary:
        evaluate queued birth/deconsolidation proposals
        apply accepted reversible transitions to candidate state

    if consolidation_boundary:
        for each eligible star block:
            q = ternary_candidate(block.star_latent)
            if regression_gate(q, protected_probes) passes:
                commit star -> ternary candidate

        identify reclaimable neutral blocks
        checkpoint complete developmental state
        reclaim only after checkpoint succeeds
        compact layout if scheduled
        journal version hashes, resource use, and validation results
```

---

## Appendix D. Adversarial-review traceability matrix

| Review attack | v0.2 response |
|---|---|
| "Everything reduces to known machinery" | irreducibility claim dropped; matched Bagel baseline made central |
| Star-state escape hatch | count + memory + compute hard budgets |
| Star-fraction catch-22 | mixed-phase equilibrium elevated to Stage A experiment |
| Growth is memorization | growth requires persistent pressure, protected validation, and resource cost |
| Dead-zone Bingham dynamics | diagnostic liveness separated from deformation; smooth yield default |
| Endogenous confirmation loop | stress split into endogenous and exogenous channels |
| Phase avalanches | hysteresis, dwell, bounded coupling, avalanche metrics |
| Resource governor too vague | explicit shield with hard memory/FLOP/latency constraints |
| Controller carries the result | controller/substrate separation and ablations |
| Fusion alignment oracle | fusion removed from core; alignment-aware modes deferred |
| Fission twin collapse | fission removed from core; symmetry breaking required for future work |
| Dynamic topology hostile to hardware | block granularity, bounded kernel family, layout epochs |
| Bit-exact determinism impractical | decision reproducibility separated from bit-exact arithmetic |
| Rollback restores only weights | transactional full-state rollback |
| Metadata/journal overhead hidden | required byte accounting includes metadata and journal amortization |
| Repeated quantization drift | explicit cycle-loss metric and long-horizon test |
| Multimodal timescale conflicts | multimodality deferred from core claim |
| Delta composition explosion | portable deltas deferred; compatibility problem acknowledged |
| No theorem / weak formal core | conflict-gap, memory, liveness, crystallization, and empirical-separation propositions |

---

## Appendix E. Preregistration skeleton for the first decisive experiment

Before running the experiment, record:

1. task distribution and shift schedule;
2. model architecture and initial parameter count;
3. block size;
4. allowed developmental actions;
5. star count/memory/FLOP caps;
6. controller equations and thresholds;
7. Bagel baseline components;
8. hyperparameter search budget for each system;
9. protected validation stream and final holdout stream;
10. primary frontier metrics;
11. secondary diagnostics;
12. stopping conditions;
13. success criterion;
14. falsification criterion;
15. hardware configuration and software versions.

The main result should be reported whether positive or negative.
