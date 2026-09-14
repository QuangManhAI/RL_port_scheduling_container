# Session Progress & Status Tracking

| Field | Value |
| :--- | :--- |
| **Document Type** | Documentation Subsystem Index |
| **Status** | Active Index |
| **Owner** | AI Agent & Human Practitioner |
| **Scope** | Session Status & Phase Progression |
| **Created** | 2026-09-06T21:05:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/README.md](../README.md), [agents/templates/PROGRESS_STATUS_TEMPLATE.md](../../agents/templates/PROGRESS_STATUS_TEMPLATE.md) |

---

## Purpose & Conventions

This directory tracks active working status, completed steps, blockers, and next actions across agent turns and human sessions.

### Rules for Progress Tracking

1. Copy [agents/templates/PROGRESS_STATUS_TEMPLATE.md](../../agents/templates/PROGRESS_STATUS_TEMPLATE.md) into this directory when starting a phase:
   - e.g., `01_DATA_PREP_STATUS.md`, `02_MODEL_BASELINE_STATUS.md`.
2. Update the **Last Updated** timestamp in the header at the conclusion of every session or major milestone.
3. Record blockers, failed attempts, and key insights so context persists seamlessly across agent reboots.
