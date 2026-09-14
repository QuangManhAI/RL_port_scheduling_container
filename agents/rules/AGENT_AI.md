# AGENT_AI.md — AI Agent Behavior, Engineering Philosophy & Workflow

- **Motivation/Background**: AI agent interactions often suffer from ungrounded assumptions, silent hallucinated path changes, drift between documentation and code, and lack of structured verification before code execution.
- **Purpose**: Define the binding engineering philosophy, communication rules, six-stage workflow lifecycle, and operational constraints for AI agents working in this repository.
- **Overview Pipeline**: Derived from lessons learned in multi-phase project consolidation and codified as an immutable constitutional governance rule.
- **Detailed Plan**: §1 Core Agent Philosophy; §2 Six-Stage Engineering Workflow (AUDIT → PLAN → IMPLEMENT → VERIFY → COMMIT → MERGE); §3 Inter-Agent Handoff Standards; §4 Hard Operational Constraints.
- **References**: `agents/rules/FOLDER_STRUCTURE.md`, `agents/rules/CODEBASE_AUDIT.md`, `agents/rules/MD_CONVENTION.md`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## Table of Contents

- [1. Core Agent Philosophy](#1-core-agent-philosophy)
- [2. The Six-Stage Workflow Lifecycle](#2-the-six-stage-workflow-lifecycle)
- [3. Inter-Agent Handoff Protocol](#3-inter-agent-handoff-protocol)
- [4. Hard Operational Constraints](#4-hard-operational-constraints)

---

## 1. Core Agent Philosophy

1. **Second Brain, Not Second-Guesser:** The agent maintains project memory through structured documentation so human engineers and subsequent agents do not suffer context burnout.
2. **Read First, Act Second:** Before executing code changes, the agent must read the constitutional rules under `agents/rules/` and current project state in `docs/`.
3. **No Silent Drift:** Any divergence between documentation and code is a blocker to be reported, not something to silently "fix" without human alignment.
4. **Verified Evidence Over Claims:** Never state that tests passed or a model works without citing exact commands, execution logs, and 5W1H empirical context.

---

## 2. The Six-Stage Workflow Lifecycle

All non-trivial engineering tasks MUST progress through these six distinct stages:

```text
AUDIT ──► PLAN ──► IMPLEMENT ──► VERIFY ──► COMMIT ──► MERGE
```

### Stage 1: AUDIT (Strictly Read-Only)
- Inspect the current working tree, Git status, and active dependencies.
- Catch drift between documentation claims and real source code per [agents/rules/CODEBASE_AUDIT.md](CODEBASE_AUDIT.md).
- Identify risks, constraints, and dependencies before modifying any file.

### Stage 2: PLAN (Proposal & Design)
- Formulate a minimal, concrete implementation plan.
- Map out files to be created, modified, or moved.
- State verification steps in advance.
- Present plan to human engineer for approval when design choices exist.

### Stage 3: IMPLEMENT (Minimal Targeted Execution)
- Modify only authorized files.
- Adhere strictly to [agents/rules/FOLDER_STRUCTURE.md](FOLDER_STRUCTURE.md) and [agents/rules/NAMING_CONVENTION.md](NAMING_CONVENTION.md).
- Keep implementation modular, preserving existing working interfaces.
- Update timestamps on all touched `.md` files per [agents/rules/MD_CONVENTION.md](MD_CONVENTION.md).

### Stage 4: VERIFY (Local Non-Destructive Testing)
- Run smoke tests on modified scripts before full execution.
- Run the test suite: `pytest tests/ -q`.
- Check dependency integrity: `python -m pip check`.
- Verify package imports cleanly from root: `python -c "import src"`.
- Run restricted linter: `ruff check`.

### Stage 5: COMMIT (Atomic & Descriptive)
- Stage only intended files (never stage secrets, `.venv`, or untracked binary data).
- Write conventional commit messages: `feat(...)`, `fix(...)`, `chore(...)`, `docs(...)`.
- Verify clean working tree after commit.

### Stage 6: MERGE (Controlled Integration Gate)
- Run pre-merge verification.
- Always use `--no-ff` when merging feature/consolidation branches into `main` to preserve explicit architectural history.
- Tag significant release milestones (e.g. `v1.0.0`).

---

## 3. Inter-Agent Handoff Protocol

When work is paused, interrupted, or handed off between sessions/agents:
1. **Document Current State:** Update the active status file (`docs/progress/<PHASE>_STATUS.md`) or write a dedicated handoff note (`docs/shared/HANDOFF_<TOPIC>.md`).
2. **Record 5 Key Anchors:**
   - Exact Git branch and HEAD commit hash.
   - Cleanliness of working tree.
   - Exact state of passing/failing tests.
   - Blockers or open decisions requiring human resolution.
   - Immediate next step command to resume execution.

---

## 4. Hard Operational Constraints

1. **Never Train in Notebooks:** All training loops must execute as reproducible scripts with full-state checkpointing ([agents/rules/LOGGING_CHECKPOINT_RULES.md](LOGGING_CHECKPOINT_RULES.md)).
2. **Never Overwrite Raw Data:** `data/raw/` is strictly read-only.
3. **No Unbounded Package Versions:** Avoid unpinned wildcards in core deep learning dependencies.
4. **No Destructive Operations Without Confirmation:** Never reset Git history, delete checkpoints, or purge runs directories without explicit human authorization.
