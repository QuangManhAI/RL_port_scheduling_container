# 06_RL_TRAINING_CURRICULUM_AND_SCENES.md — Skill-Curriculum RL Training & Minor Scene Setup Specification

- **Motivation/Background**: The AMR fleet's target behavior (traverse → pick up box → avoid collision → drop off box) is too large a task to learn as one flat policy from scratch. `PURPOSE.md` §3.1 already locks the fleet-level architecture as Hybrid AI (MAPPO + GNN dynamic layer, deterministic OR safety guardrail), but individual robot *skills* (pick-up, drop-off, point-to-point navigation) still need to be trained and validated before they're composed into that fleet-level system.
- **Purpose**: Specify (a) the RL algorithm choice and rationale for skill-level training, (b) the skill decomposition into a "multi-shot" curriculum (pick-up first, drop-off next, then chained), and (c) concrete, buildable **minor scenes** — small isolated Godot training environments, one per skill stage — so each skill can be trained and iterated on independently of the full warehouse digital twin.
- **Overview Pipeline**: Each minor scene in `godot/scenes/training/` is a stripped-down environment (a handful of meters, one agent, no fleet, no full racking) exposing a `reset()`/`step()` contract to a Python RL trainer over the same style of Python↔Godot bridge already established in `PHASE-03`. Stages are trained independently, then chained per §8, and only the final chained/fine-tuned policy graduates into the full `PHASE-03`/`PHASE-05` warehouse scene as one agent inside the eventual MAPPO fleet.
- **Detailed Plan**: §1 Scope & Objective; §2 Algorithm Selection & Rationale; §3 Skill Decomposition & Curriculum Stages; §4 Minor Scene Architecture (shared contract); §5 Per-Stage Minor Scene Specifications; §6 Observation & Action Space Contracts; §7 Training Infrastructure & Python Bridge; §8 Curriculum Progression & Skill Chaining; §9 Scene Node Map; §10 Acceptance Criteria.
- **References**: [`PURPOSE.md`](./PURPOSE.md) §3.1, §6; [`03_GODOT_3D_DIGITAL_TWIN.md`](./03_GODOT_3D_DIGITAL_TWIN.md); [`04_WAREHOUSE_SIMULATION_ENVIRONMENT.md`](./04_WAREHOUSE_SIMULATION_ENVIRONMENT.md); [`05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md`](./05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md).
- **Created**: 2026-09-16
- **Last Updated**: 2026-09-16 (alignment decisions locked: hierarchical trigger action space, TCP bridge protocol, multi-worker vectorization)

---

## Metadata

- **Phase ID**: `PHASE-06`
- **Phase Name**: `Skill-Curriculum RL Training & Minor Scene Setup`
- **Status**: Locked (algorithm, action-space, observation contract, bridge protocol, and vectorization decisions confirmed)
- **Target Directories**: [`godot/scenes/training/`](../../godot/scenes/training), [`src/training/`](../../src/training), [`src/envs/`](../../src/envs)

---

## 1. Scope & Objective

Current state: `PHASE-03`/`PHASE-04` deliver a full multi-agent warehouse digital twin (fleet of AMRs, procedural racking, VDA 5050 telemetry). That scene is the right target for *fleet-level* MARL, but it is the wrong place to start training a single robot's basic skills — too many moving parts, too sparse a reward signal, too slow to reset for the thousands of short episodes early skill training needs.

Target state: a small family of **minor scenes** — one per skill — each a minimal, fast-resetting Godot environment with exactly one agent, one clear objective, and a dense reward signal, wired to a standard RL trainer (Stable-Baselines3 or RLlib) via `gymnasium`-style `reset()`/`step()` semantics. Skills are trained **part by part** ("multi-shot" per your framing): pick-up first, drop-off next, navigation stages bracketing both, then a chained scene that composes them.

This phase does not change the fleet-level MAPPO/GNN architecture in `PURPOSE.md` §3.1 — it produces the *building-block skill policies* that architecture will eventually orchestrate, and the minor-scene pattern this phase establishes.

---

## 2. Algorithm Selection & Rationale

**Recommendation: PPO (Proximal Policy Optimization) for every single-agent skill stage in this phase.**

- **Mixed action space**: each skill needs continuous movement (velocity/heading, or grid-cell selection) plus a near-discrete actuator action (engage/disengage lift). PPO handles this combination far more cleanly than pure value-based methods (DQN) — no need to discretize continuous motion or force a continuous relaxation onto the lift trigger.
- **Stability under curriculum change**: every time you move to a new stage, the environment (and often the observation/reward shape) changes underneath the policy. PPO's clipped-objective on-policy updates tolerate this far better than off-policy methods (SAC, TD3), which are more sample-efficient in a *fixed* environment but more fragile when the task distribution shifts stage to stage.
- **One algorithm family end to end**: `PURPOSE.md` §3.1 already commits the fleet-level layer to **MAPPO** (multi-agent PPO) + GNN. Training every skill stage with plain PPO means the same codebase, reward-shaping intuition, and hyperparameters carry forward almost unchanged when a skill policy graduates into the multi-agent fleet — no algorithm-family rewrite at the handoff point.
- **Collision avoidance is explicitly not this layer's job.** Per `PURPOSE.md` §3.1, hard collision/kinematic safety is enforced by the deterministic OR guardrail, not learned via penalty shaping. None of the minor scenes below should rely on a large negative reward as the *only* thing preventing collisions — treat near-miss shaping as a soft signal, not a safety mechanism, consistent with the platform's hybrid-AI design.

**Deliberately out of scope for this phase**: hierarchical RL frameworks (options/feudal RL) that learn a *meta-controller* to select among skills. §8 below uses a simple scripted/state-machine sequencer instead of a learned meta-controller — cheaper to build, fully interpretable, and sufficient until the chained policy proves the skills compose at all.

**Action-space granularity for S2/S4 (locked decision)**: the RL policy does **not** control raw arm-joint angles or end-effector deltas. It controls mobile-base velocity plus a `lift_trigger` scalar; once triggered within reach, an analytical `ArmIKSolver` executes the deterministic 3D grasp/stow/place kinematics. RL is responsible for learned approach, alignment, and timing — not for rediscovering inverse kinematics the project already has a closed-form solution for. This keeps the §6 observation/action contract identical across all five stages (no arm-joint dimensions to add or remove between stages) and keeps S2/S4 sample-efficient by not asking PPO to solve a manipulator-control problem it doesn't need to.

---

## 3. Skill Decomposition & Curriculum Stages

| Stage        | Skill                    | Starts from                                                                    | Ends when                                              | Reward signal                                                                                       |
| :----------- | :----------------------- | :----------------------------------------------------------------------------- | :----------------------------------------------------- | :-------------------------------------------------------------------------------------------------- |
| **S1** | Navigate-to-item         | Random position in a bounded arena                                             | Within grasp range of the box, or timeout              | Dense: progress toward box + time penalty                                                           |
| **S2** | Pick-up                  | Positioned near a box (seeded from S1 terminal states)                         | Box successfully lifted, or timeout/drop               | Dense: approach-alignment shaping + sparse grasp-success bonus                                      |
| **S3** | Navigate-while-carrying  | Carrying a box, random start (seeded from S2 terminal states)                  | Within drop range of the target zone, or timeout       | Dense: progress toward drop zone + time penalty; small penalty for excess sway/speed while carrying |
| **S4** | Drop-off                 | Carrying a box, positioned near the drop zone (seeded from S3 terminal states) | Box placed accurately in the zone, or timeout/mis-drop | Dense: placement-alignment shaping + sparse placement-success bonus                                 |
| **S5** | Chained (S1→S2→S3→S4) | Random position, no box held                                                   | Full cycle complete, or timeout at any sub-stage       | Sparse: full-cycle completion bonus + carried-over per-stage shaping terms                          |

This is exactly the "multi-shot" order you described — pick-up (S1→S2) trained and validated first, drop-off (S3→S4) next, using the *same* minor-scene pattern, then chained in S5 once both halves work independently.

---

## 4. Minor Scene Architecture (shared contract)

Every minor scene under `godot/scenes/training/` follows the same skeleton so the Python trainer can treat them interchangeably (swap the `scene_path` and observation/reward config, keep the training script identical):

- **Small bounded arena**: a flat floor plus low boundary walls, sized just large enough for the skill (roughly 8–15 m per side) — not the full `140×100 m` warehouse footprint from `PHASE-04`. Fast to load, fast to reset, cheap to run thousands of parallel instances of.
- **Exactly one agent** (`amr_robot.tscn`, reused unmodified from `PHASE-03`) — no fleet, no MARL, no GNN state encoder needed at this stage.
- **A `TrainingEnv` root node** exposing three GDScript entry points the Python bridge calls every step:
  - `reset(seed, difficulty) -> Dictionary` (observation)
  - `apply_action(action: Dictionary) -> void`
  - `get_step_result() -> Dictionary` (observation, reward, terminated, truncated, info)
- **A `SpawnRandomizer` node** — every reset randomizes agent start pose, box pose, and (from S3 onward) target-zone pose within stage-specific ranges (§5), so the policy never overfits a single fixed layout.
- **A `DifficultyRamp` resource** — a single scalar (0.0–1.0) that widens the randomization ranges over training, implementing curriculum-*within*-a-stage (start with box 1–2 m away, ramp to the full arena) separately from curriculum-*across*-stages (§3's S1→S5 progression).
- **No procedural racking, no charging docks, no pick-station props from `PHASE-03`/`PHASE-05`** — minor scenes intentionally strip all zone dressing; it adds nothing to skill acquisition and only slows resets.

---

## 5. Per-Stage Minor Scene Specifications

### 5.1 S1 — `training_navigate_to_item.tscn`

- **Arena**: 12 m × 12 m flat floor, low walls, no obstacles initially (`DifficultyRamp` adds 0–3 static box obstacles as difficulty increases).
- **Spawn randomization**: agent anywhere in the arena; box anywhere ≥ 2 m from agent spawn.
- **Reward**: `+Δdistance_to_box` per step (potential-based shaping), `-0.01` per step (time penalty), `+1.0` on reaching grasp range, `-1.0` on timeout (600 steps) or wall collision.
- **Terminates**: agent within grasp range of box, or timeout.

### 5.2 S2 — `training_pickup.tscn`

- **Arena**: 4 m × 4 m — small on purpose; this stage is about approach/alignment/timing, not travel.
- **Box elevation**: floor/staging height (Y ≈ 0.2 m) for this stage and all others through S5; multi-tier rack elevations are deferred to later `DifficultyRamp` stages, not introduced here (see §6).
- **Seeding**: agent spawn pose sampled from S1's terminal-state distribution, jittered ±0.3 m position / ±25° heading, so S2 never trains from unrealistic "already perfectly aligned" starts.
- **Action handling**: `lift_trigger > 0.5` while within reach hands off to the `ArmIKSolver`, which queries the box's true 3D position and executes the grasp/stow sequence deterministically — RL never sees or controls the vertical/arm-joint component of this action.
- **Reward**: shaping term on approach-angle alignment each step, `+2.0` sparse bonus on successful lift-and-stow (box sensor confirms tray-stowed for ≥ 0.5 s), `-0.5` on a premature/failed trigger, `-1.0` on timeout (300 steps).
- **Terminates**: box in tray sensor for ≥ 0.5 s, or timeout, or box knocked out of reachable zone.

### 5.3 S3 — `training_navigate_carrying.tscn`

- **Arena**: 12 m × 12 m, mirrors S1's layout but the agent spawns already carrying a box mesh.
- **Seeding**: agent spawn pose (with box attached) sampled from S2's terminal states.
- **Reward**: same progress-shaping pattern as S1 but toward a drop-zone marker instead of a box, plus a small `-0.02 × |angular_velocity|` penalty discouraging violent turns that would plausibly drop a carried box (a *soft* stability cue — actual carry-physics/drop-on-collision behavior belongs to `PHASE-04`'s manipulator layer, not this reward term).
- **Terminates**: agent within drop range of the target zone, or timeout, or box lost/dropped early.

### 5.4 S4 — `training_dropoff.tscn`

- **Arena**: 4 m × 4 m, mirrors S2's scale and box-elevation convention (Y ≈ 0.2 m staging height).
- **Seeding**: agent spawn pose (carrying box) sampled from S3's terminal states.
- **Action handling**: same trigger/IK-handoff pattern as S2 — `lift_trigger` commits to the IK-driven place sequence once within reach of the drop-zone marker; RL controls approach and timing only.
- **Reward**: alignment shaping toward the drop-zone marker, `+2.0` sparse bonus on accurate placement (position + orientation tolerance), `-0.5` on mis-drop (box lands outside tolerance), `-1.0` on timeout (300 steps).
- **Terminates**: box placed within tolerance, or timeout, or mis-drop.

### 5.5 S5 — `training_chained_cycle.tscn`

- **Arena**: 16 m × 16 m — large enough to contain one navigate-pick-navigate-drop cycle end to end.
- **Sequencer**: a lightweight scripted state machine (not a learned meta-controller, per §2) that swaps which policy checkpoint is active based on the agent's current sub-goal (holding box or not) — this is orchestration, not a new trainable component.
- **Reward**: sparse `+5.0` on full-cycle completion, plus the same per-stage shaping terms as S1–S4 carried over so the signal isn't purely sparse across a 4-phase episode.
- **Terminates**: full cycle complete, or timeout (1200 steps), or a hard failure in any sub-stage (box lost, wall collision).
- **Purpose of this stage is validation, not primary training**: if S1–S4 policies were trained well, S5 should need only light fine-tuning to compose them. A S5 that fails badly signals a seeding/reward mismatch between adjacent stages (§8) rather than a reason to retrain everything as one flat policy.

---

## 6. Observation & Action Space Contracts

Keep this identical in shape across all five stages — this is what makes S5's policy warm-start from S1–S4 checkpoints a direct weight load instead of a from-scratch retrain.

**Observation vector — 13 floats, normalized to [-1.0, 1.0]:**

| Index  | Field                                                      | Notes                                                       |
| :----- | :--------------------------------------------------------- | :---------------------------------------------------------- |
| 0–3   | Agent local pose`[x/w, z/h, sin(θ), cos(θ)]`           | Normalized to arena bounds                                  |
| 4–5   | Agent velocity`[v_lin/v_max, v_ang/ω_max]`              |                                                             |
| 6–8   | Relative vector to active sub-goal`[dx, dz, distance]`   | **Deliberately 2D/horizontal only** — see note below |
| 9      | Carrying-status flag                                       | 0.0 = empty, 1.0 = carrying                                 |
| 10     | Gripper/lift status                                        | 0.0 = rest/folded, 1.0 = stowed in tray                     |
| 11–12 | Nearest obstacle/wall vector`[distance, relative_angle]` | Active from S1's difficulty ramp onward                     |

**Action vector — 3 floats, continuous [-1.0, 1.0]:**

| Index | Field                | Notes                                                                                    |
| :---- | :------------------- | :--------------------------------------------------------------------------------------- |
| 0     | `linear_velocity`  | Mapped to`[-v_max, +v_max]`                                                            |
| 1     | `angular_velocity` | Mapped to`[-ω_max, +ω_max]`                                                          |
| 2     | `lift_trigger`     | `> 0.5` commits to the `ArmIKSolver`'s deterministic grasp/stow/place sequence (§2) |

**Why the sub-goal vector (fields 6–8) stays 2D by design, not just for now**: because the `ArmIKSolver` — not the observation space — is what resolves the box's true 3D position and reach geometry once `lift_trigger` fires, RL never needs vertical target information to act correctly. This also keeps rack-elevation variation and navigation/approach difficulty as separable curriculum axes: `DifficultyRamp` (§4) is what widens box height across shelf tiers (0.2 m – 2.2 m) in later ramps, without ever changing the observation vector's shape. A policy that struggles once elevation is introduced can be diagnosed as an IK/reach issue, not conflated with a navigation regression, because the two are never varied by the same mechanism.

---

## 7. Training Infrastructure & Python Bridge

- **Bridge protocol (locked decision): native TCP, not WebSocket, not a third-party RL-Godot library.** `godot/scripts/training/training_env_base.gd` opens a `StreamPeerTCP` listener on a port passed via a `--port=XXXX` CLI arg; `src/envs/godot_env_bridge.py` is a plain Python `socket` client. Messages are 4-byte length-prefixed JSON in both directions (`[Action]` client→server, `[Obs, Reward, Done, Info]` server→client). This is a deliberately different channel from `PHASE-03`'s one-way VDA 5050 telemetry broadcast (`warehouse_bridge.py`) — training needs strict synchronous lockstep (Python blocks on `step()`, Godot advances exactly one action-step, replies once), which async/WebSocket framing is the wrong tool for, and a vendored RL-Godot addon would cut against the zero-Python-coupling precedent `PHASE-03` already set. Target: sub-millisecond round-trip, one physics step at 60 Hz mapped to a 15 Hz action rate (4 physics ticks per action).
- **Gymnasium wrapper**: a base `src/envs/godot_gym_env.py` (Gymnasium API, space definitions, observation normalization) with one thin subclass per stage (`navigate_to_item_env.py`, `pickup_env.py`, `navigate_carrying_env.py`, `dropoff_env.py`, `chained_cycle_env.py`), each pointing at its corresponding minor scene and reusing the shared §6 contract unchanged.
- **Local training environment**: a project-root `.venv` (not a shared/system Python) with PyTorch (CUDA build matching the local NVIDIA GPU), `gymnasium`, `stable-baselines3`, and `tensorboard` — verify `torch.cuda.is_available()` before launching any real training run.
- **Trainer**: Stable-Baselines3 `PPO` for individual stages (fast iteration, simple checkpointing); reserve RLlib's multi-agent PPO (MAPPO) for when a skill policy graduates into the full fleet scene per `PURPOSE.md` §3.1 — no need to introduce RLlib's added complexity for single-agent skill stages.
- **Starting hyperparameters** (per stage, tune from here): `n_steps=2048`, `batch_size=64`, `learning_rate=3e-4`, `gamma=0.99`, `gae_lambda=0.95`, `clip_range=0.2`, `ent_coef=0.01` (slightly higher entropy coefficient for S1/S3 navigation stages to encourage exploration of the arena; lower, ~0.005, for S2/S4 fine-motor stages where excess exploration wastes samples).
- **Vectorization (locked decision): configurable multi-instance headless Godot workers, not in-engine multi-arena batching, not a single accelerated instance.** Each worker is a separate headless Godot process (`--headless`, `Engine.max_fps = 0` to unlock tick rate) on its own port (`11000 + worker_id`), driven through SB3's `SubprocVecEnv`. Default 4–8 workers for training rollouts, scalable down to 1 worker for step-by-step debugging (stepping through a single instance is far easier when a reward function misbehaves than debugging inside a batched multi-arena process), and up toward 8–16 for higher-throughput runs once a stage's setup is validated at small scale. In-engine batched arenas would save per-instance engine overhead but require a custom batched `VecEnv` and a spatial-isolation arena manager on the Godot side — worthwhile only once training moves to full-fleet scale, not for these small single-agent minor scenes.
- **Logging**: log terminal-state distributions per stage (agent pose, carrying-state, box/zone pose at episode end) to `src/training/logs/terminal_states/` via `terminal_state_buffer.py` — this is the seeding data §5.2/§5.3/§5.4 need to bootstrap the next stage's spawn randomization.

---

## 8. Curriculum Progression & Skill Chaining

1. Train **S1** to a success-rate threshold (e.g., ≥ 90% of episodes reach grasp range within timeout) before moving on — don't chain from an unreliable stage.
2. Train **S2** seeded from S1's logged terminal states. Gate on grasp success rate, not just reward — reward can look fine while grasp reliability is still poor.
3. Train **S3** seeded from S2's logged terminal states (carrying = true).
4. Train **S4** seeded from S3's logged terminal states.
5. Assemble **S5** using the scripted sequencer (§5.5) with S1–S4's trained checkpoints as warm starts (same observation/action shape per §6 makes this a direct weight load, not a retrain). Fine-tune briefly end-to-end with the sparse full-cycle reward.
6. **Only after S5 succeeds reliably** does a skill policy become a candidate to run *inside* an individual AMR in the full `PHASE-03` warehouse scene, at which point `PURPOSE.md` §3.1's MAPPO + GNN layer takes over fleet-level coordination around it (routing, yielding, intersection negotiation) — this phase's policies remain the per-agent skill layer, not the fleet coordinator.
7. **Regression check when graduating to the fleet scene**: re-run each stage's success-rate metric inside the full warehouse (with other agents present but the OR guardrail active) before trusting the policy in a multi-agent run — the minor scenes deliberately don't include other agents, so this is the first point multi-agent interference could surface.

---

## 9. Scene Node Map (implementation contract)

New, parallel to (not replacing) the `godot/scenes/environment/` tree from `PHASE-03`/`PHASE-05`:

```
godot/scenes/training/
├── training_navigate_to_item.tscn      (S1)
├── training_pickup.tscn                (S2)
├── training_navigate_carrying.tscn     (S3)
├── training_dropoff.tscn               (S4)
├── training_chained_cycle.tscn         (S5)
└── shared/
    ├── spawn_randomizer.gd
    └── difficulty_ramp.tres

godot/scripts/training/
└── training_env_base.gd                (StreamPeerTCP listener; reset/apply_action/get_step_result contract, §7)

src/envs/
├── godot_env_bridge.py                 (sync reset/step TCP client, distinct from PHASE-03's telemetry bridge)
├── godot_gym_env.py                    (shared Gymnasium base: spaces, normalization)
├── navigate_to_item_env.py
├── pickup_env.py
├── navigate_carrying_env.py
├── dropoff_env.py
└── chained_cycle_env.py

src/training/
├── train_stage.py                      (--stage, --workers, --steps, --device flags)
└── logs/terminal_states/               (per-stage terminal-state logs used for seeding, §7)
```

Each `training_*.tscn` reuses `amr_robot.tscn` from `PHASE-03` unmodified — the only new assets are the minimal arena geometry and the `SpawnRandomizer`/`DifficultyRamp` helpers, so there is nothing here that duplicates or forks the existing robot logic.

---

## 10. Acceptance Criteria

- [ ] All five minor scenes load headless and complete a `reset()`/`step()` cycle round-trip in under the target per-step latency needed for 16+ parallel vectorized instances.
- [ ] S1 and S3 (navigation stages) reach ≥ 90% goal-reach success rate before S2/S4 training begins on their seeded terminal states.
- [ ] S2 and S4 (manipulation stages) reach a defined grasp/placement success-rate threshold, tracked separately from raw episode reward.
- [ ] S5's chained cycle succeeds at a rate consistent with the product of S1–S4's individual success rates (a large drop-off indicates a seeding/observation mismatch between stages, not a training-budget problem).
- [ ] Observation and action vector shapes are identical (per §6) across all five `gymnasium.Env` wrappers, so S5's warm start is a direct checkpoint load with no architecture changes.
- [ ] No minor scene introduces new robot logic, physics layers, or manipulator mechanics beyond what `PHASE-03`/`PHASE-04` already define — this phase adds training scaffolding only.
- [ ] A graduated skill policy's success rate is re-validated inside the full multi-agent warehouse scene (§8 step 7) before being trusted in a live fleet run.
