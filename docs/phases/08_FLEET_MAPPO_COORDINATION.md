# 08_FLEET_MAPPO_COORDINATION.md — Fleet-Level Multi-Agent Coordination Specification

- **Motivation/Background**: `PHASE-06` produces individually-trained, independently-checkpointed single-robot skills (navigate, pick-up, navigate-carrying, drop-off) via isolated minor scenes with zero weight warm-starting between stages. Those skills are necessary but not sufficient — none of them address what happens when 10+ AMRs share the same floor: aisle traffic, mutual yielding, anti-deadlock, and conveyor dock queuing. `PURPOSE.md` §3.1 already locks the target architecture for this problem as Hybrid AI (MAPPO + GNN dynamic layer over a deterministic OR safety guardrail); this phase is where that architecture actually gets built and trained.
- **Purpose**: Specify (a) the division of responsibility between a high-level dispatcher and the MAPPO coordination layer, (b) the training scene used to teach coordination behavior, (c) the observation design that lets a policy trained on a small roster generalize to a 10+ agent fleet without retraining, and (d) how this layer composes with `PHASE-06`'s graduated skill checkpoints and the existing OR safety guardrail.
- **Overview Pipeline**: A scripted/rule-based **Warehouse Dispatcher** assigns box manifests (which robot fetches which item from where to where) — this is task allocation, not learned. Once a robot has an assigned task, **MAPPO** governs its moment-to-moment spatial coordination (which lane, when to yield, how to avoid intersection deadlock) using an ego-centric, k-nearest-neighbor observation so the same trained policy scales from a small training roster to the full fleet. `PHASE-06`'s graduated skill checkpoints execute the actual pick-up/drop-off mechanics once MAPPO has navigated the robot to the right place; the **OR guardrail** (unchanged, pre-existing) still has final veto power over every proposed action regardless of which layer proposed it.
- **Detailed Plan**: §1 Scope & Objective; §2 Responsibility Split (Dispatcher vs. MAPPO); §3 Training Scene: Dual-Rack Aisle with Conveyor Bottleneck; §4 Scalable Observation Design (Ego-Centric + k-NN/LiDAR); §5 Observation & Action Contracts; §6 Reward Design for Coordination; §7 Training Progression (Small Roster → Full Fleet); §8 Composition with `PHASE-06` Skills & the OR Guardrail; §9 Open Parameters; §10 Acceptance Criteria.
- **References**: [`PURPOSE.md`](./PURPOSE.md) §2.1, §3.1, §3.3; [`06_RL_TRAINING_CURRICULUM_AND_SCENES.md`](./06_RL_TRAINING_CURRICULUM_AND_SCENES.md); [`05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md`](./05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md); [`04_WAREHOUSE_SIMULATION_ENVIRONMENT.md`](./04_WAREHOUSE_SIMULATION_ENVIRONMENT.md).
- **Created**: 2026-09-17
- **Last Updated**: 2026-09-17

---

## Metadata

- **Phase ID**: `PHASE-08`
- **Phase Name**: `Fleet-Level MAPPO Coordination & Scalable Observation Design`
- **Status**: Proposed
- **Target Directories**: [`godot/scenes/training/fleet/`](../../godot/scenes/training/fleet), [`src/envs/fleet/`](../../src/envs/fleet), [`src/training/fleet/`](../../src/training/fleet)

---

## 1. Scope & Objective

Current state: `PHASE-06` gives you four independently-working single-robot skills and a scripted sequencer that chains them for one robot at a time. None of that addresses multi-robot interaction — a fleet of skill-equipped robots dropped onto the same floor with no coordination layer will still collide, deadlock at intersections, and queue chaotically at conveyor docks.

Target state: a trained MAPPO policy that governs each robot's local movement decisions (lane choice, speed, yielding) well enough to keep 10+ robots moving without deadlock, layered *underneath* a non-learned task dispatcher and *on top of* the deterministic OR safety guardrail — exactly the three-layer split `PURPOSE.md` §3.1 already specifies.

This phase does not retrain or modify `PHASE-06`'s skill checkpoints, and does not touch the OR guardrail's verification logic — it is purely the new middle layer between task assignment and safety verification.

---

## 2. Responsibility Split (Dispatcher vs. MAPPO)

**Locked decision**: task allocation and spatial coordination are two different problems and get two different solutions — one scripted, one learned.

| Layer | Responsibility | Learned? |
| :--- | :--- | :--- |
| **Warehouse Dispatcher** | Assigns box manifests to robots (which robot fetches which item, from where, to where) — effectively a WMS/auction-style task allocator | No — scripted/rule-based |
| **MAPPO coordination layer** | Given an assigned task, decides moment-to-moment movement: which lane, when to yield, how to avoid intersection deadlock, how to queue at a conveyor dock | Yes — this phase's trained policy |
| **`PHASE-06` skill checkpoints** | Executes the actual pick-up/drop-off mechanics once MAPPO has navigated the robot into position | Yes — already trained, unchanged here |
| **OR safety guardrail** (pre-existing) | Deterministically verifies every proposed action against kinematic/collision constraints before execution | No — hard-coded verification, final authority |

Why split it this way rather than asking MAPPO to also learn task assignment: task allocation is a well-solved combinatorial/auction problem with cheap, interpretable, provably-correct classical solutions — there's no reason to spend RL training budget re-deriving what a scripted assignment algorithm already does reliably. This mirrors the same reasoning `PHASE-06` §2 already applied to inverse kinematics: don't make RL relearn something you already have a closed-form or classical answer for. MAPPO's job is scoped to exactly the part that's genuinely hard to hand-code well at scale — emergent multi-agent yielding and deadlock avoidance.

---

## 3. Training Scene: Dual-Rack Aisle with Conveyor Bottleneck

**Locked decision**: two parallel multi-tier racks flanking a single aisle, plus one central motorized conveyor dock — a scene deliberately designed to force both of the coordination problems that matter:

- **Narrow-aisle passing**: two robots approaching each other in the same aisle must negotiate who yields, since the aisle is too narrow to pass side by side. This is the minimal case for "mutual yielding" behavior.
- **Conveyor dock queuing/contention**: the conveyor is a single shared bottleneck resource — multiple robots arriving to drop off or pick up at the same dock must queue and sequence access rather than collide or deadlock at the dock entrance.

Scene sizing note: start this training scene deliberately small (roughly aisle-plus-dock scale, not the full `140×100 m` warehouse from `PHASE-04`) — same rationale as `PHASE-06`'s minor scenes: fast resets, cheap parallelization, and a scene focused enough that a coordination failure is easy to diagnose (two robots deadlocked in one aisle is legible; a failure somewhere in a 10-robot warehouse-scale scene is not).

---

## 4. Scalable Observation Design (Ego-Centric + k-NN / LiDAR)

**Locked decision**: each robot's observation is **ego-centric** — its own state plus local information about its **k nearest neighboring robots** plus **360° LiDAR/raycast** sensing of static obstacles (racking, walls, conveyor structure) — rather than a fixed-size global fleet vector or a warehouse-wide occupancy grid.

Why this is the only one of the three options actually compatible with what's already locked in: `PURPOSE.md` §3.1 specifies a **GNN** state encoder for the MAPPO layer. A GNN operates on a graph — each agent is a node, edges connect it to some local neighborhood, and message-passing aggregates neighbor information. An ego-centric + k-NN observation *is* that graph's per-node input; it's not an independent design choice layered on top of the GNN decision, it's what the GNN decision actually requires.

This is also what makes the core scaling claim possible: **train on a small roster (2–3 robots in the dual-rack-aisle scene from §3), deploy on a fleet of 10+**, with no architecture change. Because the network only ever sees "me + my k nearest neighbors + local raycasts," the input shape is identical regardless of how many robots exist elsewhere on the floor — the policy has no fixed notion of total fleet size baked into its input layer.

**Why not the alternatives, for the record:**
- *Global fixed-fleet observation* (hardcoded N-robot vector, masked when fewer are present): directly breaks the "train small, deploy large" requirement — the input layer is architecturally capped at whatever N was chosen at training time.
- *Spatial grid / BEV with a CNN*: scales in agent-count only nominally — a warehouse-scale occupancy grid is either expensive (fine resolution) or loses exactly the fine relative-velocity/heading detail that close-quarters yielding depends on (coarse resolution), and doesn't carry per-neighbor identity or intent the way a GNN's per-node features do.

---

## 5. Observation & Action Contracts

Extends (does not replace) `PHASE-06` §6's single-robot schema — the ego state block reuses that shape so a robot's own local skill checkpoints and the fleet layer stay consistent about what "my state" means:

**Per-agent observation (ego-centric):**
- **Own state** (reuses `PHASE-06` §6 fields 0–10): local pose, velocity, relative vector to current sub-goal, carrying-status, gripper status.
- **k-nearest-neighbor block** (repeated per neighbor, k = TBD per §9): relative position `[dx, dz]`, relative velocity `[dv_x, dv_z]`, neighbor's carrying-status flag. Padded/masked when fewer than k neighbors are present within sensing range.
- **LiDAR/raycast block**: a fixed number of raycasts spanning 360° (count TBD per §9), each returning normalized distance-to-obstacle — covers static racking/walls/conveyor structure, not other robots (those are covered by the k-NN block).

**Action vector**: `[linear_velocity, angular_velocity]`, same normalization convention as `PHASE-06` §6 — this layer does not add a `lift_trigger`; pick-up/drop-off remains `PHASE-06`'s skill checkpoints' responsibility, invoked once the dispatcher/MAPPO layer has navigated the robot into position.

---

## 6. Reward Design for Coordination

Coordination-specific reward terms, layered on top of (not replacing) each robot's underlying task-progress shaping:

- **Progress toward assigned task location**: same potential-based distance shaping pattern as `PHASE-06`'s navigation stages.
- **Yielding/near-miss shaping** (soft signal only): a small penalty for maintaining unsafe following distance or closing velocity toward a neighbor, similar in spirit to `PHASE-06` §5.3's sway penalty — this *encourages* cautious behavior but, consistent with `PURPOSE.md` §3.1's hybrid design, is not what actually prevents collisions. The OR guardrail remains the hard safety mechanism; this reward term only shapes learned behavior toward guardrail-friendly trajectories so the guardrail has to intervene less often.
- **Deadlock/stall penalty**: a per-step penalty for near-zero velocity while not at a legitimate stop (queued at a dock, waiting at a yield point) — this is the signal that specifically targets the "10+ robots gridlocked in an intersection" failure mode `PURPOSE.md` §2.1 identifies as the core industry bottleneck.
- **Conveyor dock queuing bonus**: reward for maintaining correct queue order/spacing at the shared conveyor bottleneck rather than clustering or cutting in.

---

## 7. Training Progression (Small Roster → Full Fleet)

1. **Validate single-robot competence first**: confirm `PHASE-06`'s graduated skill checkpoints are working reliably (per that phase's §8 gating) before layering coordination training on top — a fleet-coordination failure is much harder to diagnose if the underlying skills themselves are still unreliable.
2. **Train MAPPO on a small roster** (2–3 robots) in the dual-rack-aisle scene from §3 — small enough that yielding/passing behavior is easy to inspect and debug directly.
3. **Evaluate zero-shot scaling**: run the small-roster-trained policy at 10+ robots *without retraining* and measure deadlock frequency, throughput, and near-miss rate. This is the actual test of whether the ego-centric + k-NN observation design (§4) delivers on its scaling claim.
4. **Fine-tune at scale only if needed**: if zero-shot scaling underperforms, fine-tune the existing checkpoint at the target fleet size rather than retraining from scratch — the observation shape hasn't changed, so this is a continuation, not a new architecture.
5. **Regression-check against `PHASE-06`'s skills in the full warehouse scene**: once MAPPO reliably navigates a fleet without deadlock, re-validate that each robot's skill checkpoints still execute correctly when invoked mid-fleet (same regression-check principle as `PHASE-06` §8 step 7, now one layer up).

---

## 8. Composition with `PHASE-06` Skills & the OR Guardrail

- MAPPO's action output (`[linear_velocity, angular_velocity]`) and a skill checkpoint's action output (`[linear_velocity, angular_velocity, lift_trigger]`) are reconciled by a simple runtime rule, not a learned handoff: while a robot is *traveling* to a task location, MAPPO's velocity output drives the robot; once within the skill checkpoint's own operating range (the same proximity condition `PHASE-06` §5.2/§5.4 already define for triggering pick-up/drop-off), control passes to the relevant skill checkpoint until that skill's episode terminates, then returns to MAPPO.
- Every action from either layer — MAPPO's navigation output or a skill checkpoint's manipulation output — still passes through the pre-existing OR guardrail unchanged. This phase adds a new *proposer* of actions; it does not add a new *verifier*.

---

## 9. Open Parameters

Left for empirical tuning once the dual-rack-aisle scene is running, not decided here:
- **k** (number of nearest neighbors observed) — start at 2–3 per the original recommendation, tune against training stability and deadlock-avoidance performance.
- **LiDAR raycast count and range** — enough to reliably detect aisle walls/racking and the conveyor structure at the scene's scale; exact count TBD.
- **Neighbor sensing range** (distance beyond which a neighbor isn't included in the k-NN block) — should roughly match the aisle width/intersection scale from §3, not the full warehouse.

---

## 10. Acceptance Criteria

- [ ] A MAPPO policy trained on 2–3 robots in the dual-rack-aisle scene achieves zero-deadlock passage in that scene before any scaling test is attempted.
- [ ] The same checkpoint, run at 10+ robots with no retraining, is evaluated for deadlock frequency, throughput, and near-miss rate — this is the primary pass/fail signal for the observation design in §4, not just small-roster performance.
- [ ] Observation vector shape is identical regardless of total fleet size (padding/masking for fewer-than-k neighbors, never a resize).
- [ ] No collision is prevented *only* by the learned yielding-reward shaping — spot-check that the OR guardrail is still the layer actually vetoing unsafe actions, consistent with `PURPOSE.md` §3.1's hybrid design.
- [ ] `PHASE-06` skill checkpoints execute unchanged when invoked mid-fleet — this phase adds a navigation layer around them, not a replacement for them.
- [ ] Dispatcher task-assignment logic remains scripted/rule-based, with no part of it folded into MAPPO's learned policy.
