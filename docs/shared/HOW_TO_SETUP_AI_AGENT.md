# How to Set Up an AI Agent Workflow (SOP)

- **Motivation/Background**: AI coding agents deliver optimal engineering leverage only when initialized with a structured interview, explicit scope, immutable rules, and a disciplined stage-gated lifecycle.
- **Purpose**: Provide a step-by-step Standard Operating Procedure (SOP) for setting up and working with an AI agent in a new or existing deep learning project.
- **Overview Pipeline**: 10-step sequential workflow from initial purpose formulation to audited phase completion.
- **Detailed Plan**: §1 Rules Setup; §2 Purpose Clarification Interview; §3 Roadmap & Phase Planning; §4 Stage-Gated Implementation; §5 Inter-Agent Handoffs.
- **References**: `agents/rules/AGENT_AI.md`, `agents/rules/FOLDER_STRUCTURE.md`, `agents/rules/MD_CONVENTION.md`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## Step 1: Initialize Default Rules for the AI Agent

Ensure `agents/rules/` contains the immutable constitutional rules:
- `AGENT_AI.md` (6-stage engineering lifecycle)
- `FOLDER_STRUCTURE.md` (canonical layout)
- `CODEBASE_AUDIT.md` (pre-task audit gate)
- `MD_CONVENTION.md` (Markdown timestamps & links)
- `LOGGING_CHECKPOINT_RULES.md` (script-only training)
- `PYTORCH_FRAMEWORK_RULES.md` (device/seed/VRAM standards)
- `RESULTS_REPORTING.md` (5W1H empirical reporting)

---

## Step 2: Define Project Objective in `docs/PURPOSE.md`

State the core problem, expected deliverables, and constraints.

---

## Step 3: Clarifying Interview via AI Agent

Conduct a short (3–5 question) clarifying interview covering:
1. **Problem & Motivation**: What gap or baseline this project addresses.
2. **Success Criteria**: Exact target metrics (e.g. `val_acc >= 95.0%`, latency `< 20ms`).
3. **Scope Boundaries**: What is explicitly excluded.
4. **Hardware Constraints**: GPU VRAM ceilings, CPU-only CI runner requirements.

Lock the refined goals into `docs/PURPOSE.md`.

---

## Step 4: Prompt the AI to Generate the Project Roadmap

Generate `docs/PROJECT_ROADMAP.md` using `agents/templates/PROJECT_ROADMAP_TEMPLATE.md` with explicit milestones and phase breakdowns.

---

## Step 5: Draft Pipeline Phase Specifications

Create individual phase technical contracts under `docs/phases/<PHASE>.md` using `agents/templates/PHASE_DOC_TEMPLATE.md`.

---

## Step 6: Verify and Maintain `agents/rules/FOLDER_STRUCTURE.md`

Ensure all planned module paths align with the canonical folder layout.

---

## Step 7: Create the Root `README.md`

Provide an executive portfolio overview, architecture diagram, installation commands, and testing instructions.

---

## Step 8: Execute Work via the 6-Stage Lifecycle

For every task, enforce:
```text
AUDIT ──► PLAN ──► IMPLEMENT ──► VERIFY ──► COMMIT ──► MERGE
```
1. **AUDIT**: Catch drift before touching code.
2. **PLAN**: Propose minimal file changes and verification steps.
3. **IMPLEMENT**: Write modular code in `src/`, maintaining full tests in `tests/`.
4. **VERIFY**: Run smoke tests and pytest battery.
5. **COMMIT**: Atomic commit with conventional message.
6. **MERGE**: Integrate via `--no-ff` merge commits.

---

## Step 9: Update Live Progress Tracking

Log updates, blockers, and concrete next actions in `docs/progress/<PHASE>_STATUS.md` with active ISO 8601 timestamps.

---

## Step 10: Audit BEFORE Marking a Phase Complete

Execute `agents/templates/CODEBASE_AUDIT_TEMPLATE.md` to gate phase completion:
- If clean, mark the phase `[STATUS: COMPLETED]`.
- If issues or trade-offs remain, document them explicitly.
