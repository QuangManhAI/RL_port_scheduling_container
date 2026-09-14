# HANDOFF_TEMPLATE.md — Inter-Agent Task Handoff Specification Template

- **Motivation/Background**: When tasks span multiple sessions, agent instances, or context windows, incomplete state handoffs cause repeated audits, lost momentum, and regression errors.
- **Purpose**: Provide a standardized checkpoint template for capturing exact git state, verified test results, completed work, blockers, and immediate resumption commands.
- **Overview Pipeline**: Copy to `docs/shared/HANDOFF_<TOPIC>.md` upon task interruption, milestone completion, or before session handover.
- **Detailed Plan**: §1 Checkpoint Metadata; §2 Exact Git Topology; §3 Verification State; §4 Completed & Remaining Work; §5 Exact Resumption Command.
- **References**: `agents/rules/AGENT_AI.md`, `agents/rules/MD_CONVENTION.md`.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

## 1. Checkpoint Metadata

- **Handoff Topic**: `<e.g. Phase 2 Data Pipeline Integration>`
- **Current Branch**: `<e.g. feature/cifar10-loaders>`
- **HEAD Commit**: `<commit_hash>`
- **Working Tree State**: `[Clean | N files modified/untracked]`
- **Author / Source Agent**: `<Agent / User>`

---

## 2. Checkpoint Status Matrix

| Task / Sub-phase | Status | Target Path | Evidence / Notes |
| :--- | :---: | :--- | :--- |
| Data Loading | **DONE** | [`src/data/dataloader.py`](../../src/data/dataloader.py) | Unit tests passing |
| Model Architecture | **IN_PROGRESS** | [`src/models/build_model.py`](../../src/models/build_model.py) | Head replacement verified |
| Training Script | **NOT_STARTED** | [`src/training/train.py`](../../src/training/train.py) | Waiting on model builder |

---

## 3. Verification State

- **Unit / Smoke Tests**: `pytest tests/ -q` → `<N> passed, 0 failed`
- **Package Imports**: `python -c "import src"` → `OK`
- **Lint Check**: `ruff check` → `All checks passed`
- **Known Failing Tests / Warnings**: `<None or details>`

---

## 4. Completed Work & Key Decisions

1. Completed decision 1.
2. Completed decision 2.

---

## 5. Active Blockers & Open Decisions

- Blocker: `<e.g. Waiting on choice between Optuna SQLite vs in-memory storage>`
- Action Required: `<Decision for human engineer>`

---

## 6. Immediate Resumption Protocol (Next Steps)

To resume execution immediately without re-auditing:

```bash
# 1. Verify working branch
git status

# 2. Execute next step command
python -m src.training.train --smoke
```
