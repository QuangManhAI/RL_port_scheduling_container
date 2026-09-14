# Coursework & Project Research Documentation (`/docs`)

| Field | Value |
| :--- | :--- |
| **Document Type** | Master Documentation Index |
| **Status** | Active Index |
| **Owner** | Research Team & AI Agent |
| **Scope** | Global Research & Engineering Documentation |
| **Created** | 2026-07-25T00:00:00+07:00 |
| **Last Updated** | 2026-09-06T21:15:00+07:00 |
| **Reference** | [agents/rules/FOLDER_STRUCTURE.md](../agents/rules/FOLDER_STRUCTURE.md), [agents/rules/MD_CONVENTION.md](../agents/rules/MD_CONVENTION.md) |

---

## 1. Documentation Architecture

All evolving project-specific research artifacts, engineering plans, roadmaps, and experiment specifications live outside constitutional `/agents` rules.

The documentation system supports both **Single-Track** and **Multi-Track / Feature-Modular** architectures:

### Global Documentation Root (`/docs`)

```text
docs/
├── README.md                          # This file (master research index)
├── PURPOSE.md                         # Project brief, success criteria, and constraints
├── OVERVIEW.md                        # Living roadmap indexing all tracks/phases
├── shared/                            # Universal agent setup and workflow SOPs
│   ├── HOW_TO_SETUP_AI_AGENT.md       # 10-step agent onboarding and setup SOP
│   ├── HANDOFF_TEMPLATE.md            # Inter-agent task handoff specification
│   └── ML_PIPELINE_REFERENCE_v3.md    # Complete 18-step ML engineering guide
├── phases/                            # Milestone & pipeline phase specifications (global/single-track)
├── progress/                          # Active session status trackers (*_STATUS.md)
├── experiments/                       # Comparative benchmarks & global experiment writeups
├── bugs/                              # Repository-wide or system bug post-mortems
└── references/                        # Tool guides, API recipes, & Git/CI SOPs
    ├── GIT_AND_RELEASE_BEST_PRACTICES.md # Git commits, human approval gate, & releases
    └── OPTUNA_DB_GUIDE.md             # Optuna SQLite persistence & analysis guide
```

### Modular Track Documentation (For Multi-Lab / Multi-Feature Projects)

When a project is partitioned into distinct tracks, features, or labs (e.g. `tracks/<name>/` or `labs/<name>/`):
- Unit-specific experiment notes, hypotheses, and local phase specs are **colocated** within that unit's folder (e.g., `<unit>/docs/` or namespaced in `docs/experiments/<unit>/`).
- Cross-cutting benchmarks, system-wide roadmaps, and universal SOPs remain in the global `/docs` root.
- All unit-scoped documents MUST be indexed in [docs/OVERVIEW.md](OVERVIEW.md) so they remain discoverable from the repository root.

---

## 2. Research & Engineering Lifecycle

1. **Project Initiation:** Complete [PURPOSE.md](PURPOSE.md) and establish baseline milestones in [OVERVIEW.md](OVERVIEW.md).
2. **Phase Planning:** Instantiate phase docs from [agents/templates/PHASE_DOC_TEMPLATE.md](../agents/templates/PHASE_DOC_TEMPLATE.md) before writing code (in `docs/phases/` for single-track, or inside `<unit>/docs/phases/` for modular tracks).
3. **Session Tracking:** Maintain status trackers with active ISO 8601 timestamps and next steps.
4. **Hypothesis Testing:** Record experiments using [agents/templates/EXPERIMENT_TEMPLATE.md](../agents/templates/EXPERIMENT_TEMPLATE.md).
5. **Defect Management:** Log bugs using [agents/templates/BUG_TEMPLATE.md](../agents/templates/BUG_TEMPLATE.md) with root-cause analysis and reproducible tests.

---

## 3. Document Lifecycle & Timestamp Standard

To eliminate ambiguity across multi-session agent invocations:
- Every Markdown file in this repository starts with the mandatory 7-field metadata header.
- `Last Updated` MUST use extended ISO 8601 with timezone offset (e.g. `YYYY-MM-DDTHH:MM:SS+07:00`).
- Superseded documents must be stamped with `[STATUS: SUPERSEDED]` and point to their active replacement.
