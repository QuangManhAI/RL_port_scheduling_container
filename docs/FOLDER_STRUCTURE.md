# Folder Structure — Smart Logistics & Fleet Coordination Platform

- **Motivation/Background**: This repository implements an RL-based smart logistics platform with multiple interconnected subsystems (port simulation, warehouse simulation, RL training pipeline, Godot 3D digital twin, and UI). A documented folder structure prevents structural drift by defining where every artifact belongs.
- **Purpose**: Define the authoritative directory layout for this specific project, mapping each existing or planned folder to its purpose.
- **Overview Pipeline**: Derived from auditing the current workspace against the project's constitutional rules (`agents/rules/CREATE_FOLDER_STRUCTURE_TEMPLATE.md`; formerly `FOLDER_STRUCTURE.md`).
- **Detailed Plan**: §1 Current State Layout; §2 Directory Inventory & Purpose Map; §3 Naming Conventions; §4 Artifact Placement Rules.
- **References**: `agents/rules/MD_CONVENTION.md`, `agents/rules/LOGGING_CHECKPOINT_RULES.md`.
- **Created**: 2026-09-16T10:40:00+07:00
- **Last Updated**: 2026-09-16T10:40:00+07:00

---

## Table of Contents

- [1. Current State Layout](#1-current-state-layout)
- [2. Directory Inventory & Purpose Map](#2-directory-inventory--purpose-map)
- [3. Naming Conventions](#3-naming-conventions)
- [4. Artifact Placement Rules](#4-artifact-placement-rules)

---

## 1. Current State Layout

This project follows the **Single-Track / Monolithic** archetype from `agents/rules/CREATE_FOLDER_STRUCTURE_TEMPLATE.md`. The root layout is:

```text
RL_port_scheduling_container/
├── .github/workflows/ci.yml          # CI pipeline
├── .kilo/                            # Kilo AI worktrees (gitignored)
├── .gitignore                        # Tracked ignore rules
├── pyproject.toml                    # Packaging/tool config
├── requirements.txt                  # Unified dep proxy -> requirements/dev.txt
├── pytest.ini                        # Pytest configuration
├── SETUP.md                          # Project setup guide
├── DREAM.txt                         # Original startup concept doc
│
├── agents/                           # Immutable governance (RULES & TEMPLATES)
│   ├── README.md
│   ├── rules/                        # Constitutional AI rules
│   │   ├── AGENT_AI.md               # Agent behavior philosophy
│   │   ├── COMMIT_CONVENTION.md      # Git commit standard
│   │   ├── CREATE_FOLDER_STRUCTURE_TEMPLATE.md  # Folder layout template (renamed from FOLDER_STRUCTURE.md)
│   │   ├── CODEBASE_AUDIT.md         # Drift audit procedure
│   │   ├── LOGGING_CHECKPOINT_RULES.md  # Training log/checkpoint rules
│   │   ├── MD_CONVENTION.md          # Markdown header & metadata standard
│   │   ├── NAMING_CONVENTION.md      # Naming standards for files/code/experiments
│   │   ├── NOTEBOOK_HEADER_CONVENTION.md  # Notebook first-cell header rule
│   │   └── RESULTS_REPORTING.md      # 5W1H metric reporting rules
│   └── templates/                    # Document templates
│       ├── BUG_TEMPLATE.md
│       ├── CODEBASE_AUDIT_TEMPLATE.md
│       ├── EXPERIMENT_TEMPLATE.md
│       ├── PHASE_DOC_TEMPLATE.md
│       ├── PROGRESS_STATUS_TEMPLATE.md
│       ├── PROJECT_ROADMAP_TEMPLATE.md
│       └── REFERENCE_TEMPLATE.md
│
├── docs/                             # Project documentation (evolving)
│   ├── README.md                     # Master index
│   ├── PURPOSE.md                    # Strategic charter & mission
│   ├── OVERVIEW.md                   # Living roadmap
│   ├── FOLDER_STRUCTURE.md           # <--- THIS FILE: project-specific layout guide
│   ├── audit_codebase.md             # Codebase drift audits
│   ├── walkthrough.md                # Project walkthrough docs
│   ├── TEMPLATE_README.md            # README template
│   ├── DREAM/                        # DREAM doc artifacts
│   │   └── DREAM.md
│   ├── phases/                       # Phase specification docs
│   │   ├── .gitkeep                  # Sentinel
│   │   ├── 02_UI_DIGITAL_TWIN.md
│   │   ├── 03_GODOT_3D_DIGITAL_TWIN.md
│   │   ├── 04_WAREHOUSE_SIMULATION_ENVIRONMENT.md
│   │   ├── 05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md
│   │   └── 06_RL_TRAINING_CURRICULUM_AND_SCENES.md
│   ├── progress/                     # Live session trackers (*_STATUS.md)
│   │   ├── .gitkeep                  # Sentinel
│   │   └── README.md
│   ├── experiments/                  # Experiment writeups & hypotheses
│   │   ├── .gitkeep                  # Sentinel
│   │   ├── README.md
│   │   └── robot_design.png
│   ├── bugs/                         # Bug post-mortems
│   │   ├── .gitkeep                  # Sentinel
│   │   └── README.md
│   ├── references/                   # Reusable guides
│   │   ├── .gitkeep                  # Sentinel
│   │   ├── README.md
│   │   ├── DYNAMIC_ROBOTIC_ARM_DESIGN_DECISIONS.md
│   │   ├── GIT_AND_RELEASE_BEST_PRACTICES.md
│   │   └── OPTUNA_DB_GUIDE.md
│   └── shared/                       # Universal SOPs (agent setup, handoffs)
│       ├── HANDOFF_TEMPLATE.md
│       ├── HOW_TO_SETUP_AI_AGENT.md
│       └── ML_PIPELINE_REFERENCE_v3.md
│
├── src/                              # Python package (flat layers per FOLDER_STRUCTURE template)
│   ├── README.md
│   ├── __init__.py
│   ├── data/                         # Data processing & loaders
│   │   ├── README.md
│   │   └── __init__.py
│   ├── envs/                         # RL environments, gym wrappers
│   │   ├── chained_cycle_env.py
│   │   ├── dropoff_env.py
│   │   ├── godot_env_bridge.py
│   │   ├── godot_gym_env.py
│   │   ├── navigate_carrying_env.py
│   │   ├── navigate_to_item_env.py
│   │   ├── pickup_env.py
│   │   └── __init__.py
│   ├── eval/                         # Baseline agents & evaluation
│   │   ├── heuristic_agent_trace.py
│   │   ├── random_agent.py
│   │   ├── README.md
│   │   └── __init__.py
│   ├── experiments/                  # Multi-experiment orchestration scripts
│   │   ├── README.md
│   │   └── __init__.py
│   ├── models/                       # Model architectures / policy heads
│   │   ├── README.md
│   │   └── __init__.py
│   ├── port_sim/                     # Port simulation engine (cranes, yard, scheduling)
│   │   ├── config.py
│   │   ├── cranes.py
│   │   ├── env.py
│   │   ├── models.py
│   │   ├── scheduler.py
│   │   ├── yard.py
│   │   └── __init__.py
│   ├── training/                     # Training scripts, sequencers, checkpoints/logs
│   │   ├── chained_sequencer.py
│   │   ├── run_curriculum.py
│   │   ├── train_rl.py
│   │   ├── train_stage.py
│   │   ├── view_policy.py
│   │   ├── terminal_state_buffer.py
│   │   ├── README.md
│   │   └── __init__.py
│   ├── utils/                        # Shared utilities
│   │   ├── generate_warehouse_shell.py
│   │   ├── warehouse_bridge.py
│   │   ├── README.md
│   │   └── __init__.py
│   └── warehouse/                    # Warehouse domain logic (grid maps, inventory)
│       ├── core/                     # Core domain modules
│       │   ├── grid_map.py
│       │   ├── inventory_manager.py
│       │   └── __init__.py
│       └── __init__.py
│
├── godot/                            # Godot 4 digital twin project
│   ├── project.godot
│   ├── README.md
│   ├── icon.svg
│   ├── scenes/                       # .tscn scene files (organized by type)
│   │   ├── main.tscn
│   │   ├── entities/                 # AMR robot scenes
│   │   ├── environment/              # Warehouse/shelf/tote box scenes
│   │   ├── training/                 # Training exercise scenes
│   │   └── ui/                      # HUD/camera overlay scenes
│   ├── scripts/                      # GDScript source (organized by type)
│   │   ├── main.gd                  # Entry point
│   │   ├── bridge/                  # Simulation client bridge
│   │   ├── entities/                # AMR logic, arm solver, IK
│   │   ├── environment/             # Procedural warehouse, shelf/tote logic
│   │   ├── training/                # Training env GDScript
│   │   ├── ui/                      # HUD/camera scripts
│   │   └── utils/                   # Sound manager
│   ├── audio/                        # SFX & UI sound files
│   │   ├── sfx/                     # Game/environment sounds
│   │   └── ui/                      # Menu/UI interaction sounds
│   └── tests/                       # Godot GDUnit test scripts
│       ├── test_main_warehouse_shell.gd
│       └── test_training_scenes.gd
│
├── port_sim/                         # Standalone port simulator (separate project root)
│   └── __init__.py                   # Entry point
│
├── ui/                               # Web UI / Digital Twin dashboard
│   ├── ui_server.py                  # Backend server (Flask/FastAPI etc.)
│   └── static/                      # Frontend assets
│       ├── index.html, style.css, app.js
│       ├── dashboard/               # Dashboard JS modules
│       ├── port/                    # Port scene JS module
│       └── state/                   # State management JS modules
│
├── experiments/                      # Runtime outputs (per LOGGING_CHECKPOINT_RULES.md)
│   ├── checkpoints/                  # Legacy flat location (read-only fallback)
│   │   └── .gitkeep
│   ├── runs/                        # Actual run directories: <ts>_<run_name>/
│   │   └── .gitkeep
│   ├── results/                     # Consolidated cross-run outputs
│   │   └── README.md                # Artifact index with 5W1H context
│   ├── plots/                       # Generated figures
│   │   └── .gitkeep
│   └── metrics/                     # Compressed NPZ arrays, feature caches (NEW)
│       └── .gitkeep
│
├── configs/                          # YAML configurations
│   └── config.yaml                   # Centralized hyperparameters & settings
│
├── data/                             # Raw & processed data layers
│   ├── raw/                         # Immutable input (never modified by scripts)
│   │   └── .gitkeep
│   ├── processed/                   # Intermediate outputs from scripts
│   │   └── .gitkeep
│   └── external/                    # External downloads, third-party data
│       └── .gitkeep
│
├── notebooks/                        # Exploratory analysis & demos (NO training here)
│   └── .gitkeep                      # Sentinel for fresh checkouts
│
├── requirements/                     # Multi-tier dependency specs
│   ├── base.txt                     # Universal core: numpy, torch, gymnasium
│   └── dev.txt                      # Testing/lint extra deps (ruff, pytest)
│
├── tests/                            # Pytest test suite
│   ├── conftest.py                  # Shared fixtures
│   ├── test_godot_training_bridge.py
│   ├── test_scheduler.py
│   ├── test_smoke.py               # Project smoke test battery
│   ├── test_warehouse_bridge.py
│   ├── test_warehouse_core.py
│   ├── test_yard.py
│   └── .gitkeep                     # Sentinel for fresh checkouts
│
└── scratch/                          # Ad-hoc debugging notebooks & diagnostic scripts
    ├── check_failures_s3.py
    ├── debug_ep6.py
    ├── diagnose_trajectories.py
    ├── eval_s2.py
    ├── eval_s3.py
    ├── test_s2.py
    ├── test_s3.py
    └── test_trigger.py

```

## 2. Directory Inventory & Purpose Map

| Directory | Purpose | Archetype Scope |
|---|---|---|
| `agents/` | Immutable governance: rules, templates, agent entry point | **Global** — never duplicate per feature |
| `docs/` | Living project documentation (phases, experiments, bugs, progress, references) | **Global** |
| `src/data/` | Data processing pipelines, custom DataLoaders & transforms | **Colocated** — unit-scoped to core logic |
| `src/envs/` | Gymnasium-compatible RL environments, Godot bridge layer | **Colocated** |
| `src/eval/` | Baseline agent implementations (random, heuristic), evaluation harnesses | **Colocated** |
| `src/experiments/` | Multi-experiment orchestrators & sweep scripts | **Colocated** |
| `src/models/` | Model architectures & policy network heads | **Colocated** |
| `src/port_sim/` | Port simulation engine: cranes, yard scheduling, environment API | **Colocated** — core domain layer |
| `src/training/` | RL training scripts (MAPPO stage pipelines, curriculum runs) | **Colocated** |
| `src/utils/` | Cross-cutting helpers (warehouse generator, Godot bridge) | **Global helper** |
| `src/warehouse/` | Warehouse domain models (grid maps, inventory management, shelf logic) | **Colocated** |
| `godot/` | Godot 4 source for the 3D digital twin (scenes + GDScript code + audio) | **Colocated** (Godot project root) |
| `port_sim/` | Standalone port simulator (PySDL2 / game engine implementation) | **Colocated** (separate mini-project root) |
| `ui/` | Web-based digital twin dashboard (backend server + static frontend assets) | **Colocated** |
| `configs/` | Centralized YAML configurations | **Global** |
| `data/{raw,processed,external}/` | Data layers per the `data/` pattern: raw is immutable, processed is script-generated | **Global** |
| `experiments/runs/` | Per-run runtime state: `<ts>_<run_name>/` with checkpoints/{ best.pt,last.pt }, logs/, metrics/ | **Isolated** — `.gitignore` heavy output |
| `experiments/results/` | Consolidated cross-run outputs (combined histories, NPZ feature caches) | **Global** |
| `experiments/plots/` | Generated figures & analysis plots | **Global** |
| `experiments/checkpoints/` | Legacy flat fallback location for checkpoints (read-only) | **Isolated** — `.gitignore` |
| `notebooks/` | Exploratory Jupyter notebooks (analysis ONLY — no training loops per rules) | **Global** |
| `requirements/base.txt,dev.txt` | Split dependency tiers | **Global** |
| `tests/` | Centralized unit & smoke test suite | **Global** cross-cutting |
| `scratch/` | Ad-hoc debugging: temporary scripts, quick diagnostics | **Ephemeral** — `.gitignore`d |

## 3. Naming Conventions (per NAMING_CONVENTION.md)

| Element Type | Convention | Example |
|---|---|---|
| Python modules | `snake_case.py` | `train_rl.py`, `warehouse_bridge.py` |
| Python packages | `lower_snake_case/` | `src/envs/`, `src/training/` |
| Tests | `test_<target>.py` | `test_warehouse_core.py` |
| Godot scenes | `<snake_case_shortname>.tscn` | `amr_robot.tscn` |
| Godot scripts | `<snake_case_shortname>.gd` | `amr_robot.gd`, `arm_ik_solver.gd` |
| Phase docs | Two-digit padded prefix + `UPPER_SNAKE_CASE.md` | `04_WAREHOUSE_SIMULATION_ENVIRONMENT.md` |
| Run directories | `<YYYYMMDD_HHMMSS>_<run_name>` | `20260915_140300_ppo_stage1_final` |
| Config files | `config.yaml` or `config_<module>.yaml` | `config.yaml` (root), not `config_example.yaml` |

## 4. Artifact Placement Rules

All artifact placement decisions follow this hierarchy from `agents/rules/CREATE_FOLDER_STRUCTURE_TEMPLATE.md`:

1. **Immutable governance artifacts** → Always in `agents/rules/` or `agents/templates/`. Never duplicate.
2. **Cross-cutting documents** → `docs/` (PURPOSE, OVERVIEW, shared SOPs).
3. **Unit-scoped code/tests/configs** → Colocated within the unit's directory. For this project, every subsystem is colocated:
   - Port simulation domain code: `src/port_sim/` + `port_sim/` (standalone)
   - Warehouse domain code: `src/warehouse/` + `godot/scenes/environment/`
   - Godot 3D scenes/scripts: `godot/` root — its own project structure
   - Web UI: `ui/` root — backend server + static frontend assets
4. **Runtime outputs** → Never in `src/` or root. Always under:
   - Training checkpoints: `experiments/runs/<YYYYMMDD_HHMMSS>_<run>/<run>`.pt and `.last.pt`
   - Logs: within the same run directory under `logs/`
5. **Consolidated results** → `experiments/results/` and `experiments/metrics/ — NPZ arrays, feature caches.
