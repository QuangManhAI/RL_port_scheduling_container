# AI Agent Constitution (`/agents`)

- **Motivation/Background**: This directory serves as the immutable project-wide governance layer for AI coding agents. Mixing dynamic project status, research notes, and experiment outputs into `/agents` causes severe drift, context overload, and high consolidation overhead.
- **Purpose**: Define permanent behavior rules, quality gates, coding standards, and document skeletons that remain stable across all project phases.
- **Overview Pipeline**: Consulted at session initialization → enforced during implementation → verified before commits and merges.
- **Detailed Plan**: §1 Constitutional Architecture; §2 Active Rules Directory; §3 Standard Document Templates; §4 Strict Boundary Between `/agents` and `/docs`.
- **References**: `agents/rules/`, `agents/templates/`, `docs/`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## 1. Constitutional Architecture

Per verified engineering standards, `/agents` is strictly an **immutable constitution**, containing only universal rules and reusable templates:

```text
agents/
├── README.md                          # This file (governance index)
├── rules/                             # What the AI agent MUST consistently do
│   ├── AGENT_AI.md                    # Core behavior layer, 6-stage workflow & prompting rules
│   ├── CODEBASE_AUDIT.md              # Drift audit procedure & gate
│   ├── COMMIT_CONVENTION.md           # Commit messages & Companion-Doc standard
│   ├── FOLDER_STRUCTURE.md            # Canonical repository directory layout
│   ├── LOGGING_CHECKPOINT_RULES.md    # Script-only training & full-state checkpoint rules
│   ├── MD_CONVENTION.md               # Markdown formatting, timestamps & clickable link standards
│   ├── NAMING_CONVENTION.md           # File, code, and experiment naming rules
│   ├── NOTEBOOK_HEADER_CONVENTION.md  # Standardized notebook first-cell headers
│   ├── PYTORCH_FRAMEWORK_RULES.md     # PyTorch device/seed/VRAM/eval rules
│   └── RESULTS_REPORTING.md           # 5W1H empirical reporting protocol
└── templates/                         # Standardized document skeletons
    ├── BUG_TEMPLATE.md                # Bug report skeleton
    ├── CODEBASE_AUDIT_TEMPLATE.md     # Audit report skeleton
    ├── EXPERIMENT_TEMPLATE.md         # Experiment report skeleton
    ├── PHASE_DOC_TEMPLATE.md          # Pipeline phase specification skeleton
    ├── PROGRESS_STATUS_TEMPLATE.md    # Phase progress tracking skeleton
    ├── PROJECT_ROADMAP_TEMPLATE.md    # Milestone & execution roadmap skeleton
    └── SMOKE_TEST_CHECKLIST.md        # Pre-execution verification checklist
```

---

## 2. Distinction Between `/agents` and `/docs`

To keep projects clean, verifiable, and free of context rot:

- **`/agents` (The Constitution):** Contains ONLY universal rules and document templates that dictate what the agent **MUST** consistently do. It does NOT change or accumulate project outputs between phases.
- **`/docs` (The Evolving Research Memory):** Contains all evolving project knowledge, research briefs, stage phase specifications, experiment reports, bug reports, and progress tracking files:
  - `docs/phases/`: Technical phase specifications (`<PHASE>.md`).
  - `docs/progress/`: Live task status files (`<PHASE>_STATUS.md`).
  - `docs/experiments/`: Empirical logs and hypothesis reports.
  - `docs/bugs/`: Documented bug reports (`BUG_<NN>_<SHORT>.md`).
  - `docs/shared/`: Shared SOPs, setup manuals (`HOW_TO_SETUP_AI_AGENT.md`), and handoffs.

---

## 3. Working Rules Summary

1. **Mandatory Codebase Audit**: Run [rules/CODEBASE_AUDIT.md](rules/CODEBASE_AUDIT.md) before multi-file tasks to prevent drift.
2. **Six-Stage Lifecycle**: Execute every task through `AUDIT → PLAN → IMPLEMENT → VERIFY → COMMIT → MERGE` ([rules/AGENT_AI.md](rules/AGENT_AI.md)).
3. **Script-Only Training**: Training loops must run from `src/` scripts with full-state checkpointing; notebooks are strictly for testing, visualization, and analysis ([rules/LOGGING_CHECKPOINT_RULES.md](rules/LOGGING_CHECKPOINT_RULES.md)).
4. **Markdown Timestamps & Links**: All `.md` files must carry 7-field headers with ISO 8601 timestamps and active cross-reference links ([rules/MD_CONVENTION.md](rules/MD_CONVENTION.md)).
5. **5W1H Results Reporting**: Every reported metric must include What, Why, When, Where, Who, and How context ([rules/RESULTS_REPORTING.md](rules/RESULTS_REPORTING.md)).
6. **PyTorch Framework Hygiene**: Enforce `set_seed()`, device-agnostic execution, `weights_only=True`, and VRAM targets ([rules/PYTORCH_FRAMEWORK_RULES.md](rules/PYTORCH_FRAMEWORK_RULES.md)).
