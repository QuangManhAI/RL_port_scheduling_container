# <PHASE_NAME>_STATUS.md — Phase Progress Status Tracking Template

- **Motivation/Background**: Engineers and agents require an instantaneous, high-level status check on active work without needing to parse multi-page technical documentation.
- **Purpose**: Record live implementation status, blockers, session work logs, and the immediate next action for a specific phase.
- **Overview Pipeline**: Maintained in `docs/progress/<PHASE_NAME>_STATUS.md` and updated after every meaningful code or test change.
- **Detailed Plan**: §1 Status Badge & Phase Link; §2 Chronological Activity Log; §3 Active Blockers; §4 Immediate Next Step.
- **References**: `agents/rules/MD_CONVENTION.md`, `agents/rules/AGENT_AI.md`.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

## Status Overview

- **Governing Phase**: [`docs/phases/<PHASE_NAME>.md`](../phases/<PHASE_NAME>.md)
- **Current Lifecycle State**: `[STATUS: IN_PROGRESS]`  *(Options: DRAFT | IN_PROGRESS | COMPLETED | BLOCKED | CANCELED)*
- **Primary Assignee**: <Agent / Engineer>

---

## 1. Chronological Activity Log

- **YYYY-MM-DDTHH:MM:SS±HH:MM**: Initialized module scaffolding and unit tests.
- **YYYY-MM-DDTHH:MM:SS±HH:MM**: Fixed data normalization edge case; all smoke tests passed.

---

## 2. Active Blockers & Decisions Needed

- None currently blocking execution.
*(Or describe blocker, impact, and unblocking requirements).*

---

## 3. Immediate Next Step

- [ ] Execute `pytest tests/test_<module>.py -v` and record output.
*(State a single concrete action, not a broad backlog).*
