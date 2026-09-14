# SETUP.md — How to Bootstrap a New Project from This Template

- **Motivation/Background**: Every new deep-learning project repeats scaffolding work: directory layout, governance constitution, lint/test config, packaging, and CI. This template packages all verified patterns so a new project starts with an audited architecture already wired.
- **Purpose**: Provide one-time instructions for turning this template into a working repository — copy the template, configure environment, fill placeholders, and follow the agent setup SOP.
- **Overview Pipeline**: Copy template → create virtual environment & editable install → initialize git → wire agent constitution → follow 6-stage lifecycle.
- **Detailed Plan**: §1 Prerequisites; §2 Instantiation; §3 Key Placeholders; §4 Environment Setup & Packaging; §5 Git Initialization; §6 Agent Governance Wiring; §7 Verification Checklist.
- **References**: `docs/shared/HOW_TO_SETUP_AI_AGENT.md`, `agents/rules/FOLDER_STRUCTURE.md`, `pyproject.toml`, `requirements.txt`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T21:05:00+07:00


---

## Table of Contents

- [1. Prerequisites](#1-prerequisites)
- [2. Instantiate a New Project](#2-instantiate-a-new-project)
- [3. Fill In the Placeholders](#3-fill-in-the-placeholders)
- [4. Environment Setup & Packaging](#4-environment-setup--packaging)
- [5. Initialize Git](#5-initialize-git)
- [6. Wire Up the AI Agent Workflow](#6-wire-up-the-ai-agent-workflow)
- [7. Verification Checklist](#7-verification-checklist)

---

## 1. Prerequisites

- Python 3.11 or 3.12 installed.
- Git installed.
- GitHub account if continuous integration is desired.

---

## 2. Instantiate a New Project

1. Copy `Deep_learning_template` to the new project location (e.g. `My_Project`).
2. Navigate into the new repository root.

---

## 3. Fill In the Placeholders

| File | What to replace / configure |
| :--- | :--- |
| [`README.md`](README.md) | `[PROJECT_NAME]`, project description, architecture overview |
| [`agents/rules/FOLDER_STRUCTURE.md`](agents/rules/FOLDER_STRUCTURE.md) | Select architectural archetype: Single-Track vs Multi-Track |
| [`docs/PURPOSE.md`](docs/PURPOSE.md) | The project brief / objective (Step 2 of the setup SOP) |
| [`docs/OVERVIEW.md`](docs/OVERVIEW.md) | Living roadmap and phase/track index |
| [`configs/config.yaml.example`](configs/config.yaml.example) | Copy to `configs/config.yaml` and specify dataset/training params |
| [`pyproject.toml`](pyproject.toml) | `name`, `description`, package find rules |
| [`requirements.txt`](requirements.txt) | Point to appropriate tiered requirements |
| [`agents/rules/RESULTS_REPORTING.md`](agents/rules/RESULTS_REPORTING.md) | Define your specific domain metrics in §3 |


---

## 4. Environment Setup & Packaging

Create a dedicated virtual environment, install dependencies, and install the repository in editable mode:

```bash
# 1. Create and activate virtual environment
python -m venv .venv
.\.venv\Scripts\activate      # Windows  (source .venv/bin/activate on Linux)

# 2. Upgrade pip
python -m pip install --upgrade pip

# 3. Standard / CPU Installation:
pip install -r requirements.txt
pip install -e .

# 4. (Optional) For NVIDIA GPU Workstations:
# pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130
# pip install -r requirements.txt
# pip install -e .
```

Verify the environment:
```bash
pytest tests/ -q
ruff check src tests
python -c "import src; print('Package discovery verified!')"
```

---

## 5. Initialize Git

```bash
git init
git add .
git commit -m "chore: bootstrap project from Deep_learning_template"
git branch -M main
```

*Note:* Do not commit `data/`, `experiments/runs/`, `.venv/`, or binary weights — `.gitignore` already excludes them.

---

## 6. Wire Up the AI Agent Workflow

Follow [`docs/shared/HOW_TO_SETUP_AI_AGENT.md`](docs/shared/HOW_TO_SETUP_AI_AGENT.md) step by step:
1. Immutable constitutional rules under [`agents/rules/`](agents/rules/) are always-on.
2. Evolving research notes, phases, and experiment plans live in [`docs/`](docs/).
3. Execute all work through the 6-stage lifecycle: `AUDIT → PLAN → IMPLEMENT → VERIFY → COMMIT → MERGE`.

---

## 7. Verification Checklist

- [ ] `pytest tests/ -q` passes cleanly.
- [ ] `python -m pip check` reports no broken requirements.
- [ ] `python -c "import src"` succeeds via editable packaging.
- [ ] `configs/config.yaml` exists with valid paths.
- [ ] `agents/rules/` contains only universal rules and templates.
- [ ] `docs/` is established for evolving phases and progress.
