# NOTEBOOK_HEADER_CONVENTION.md — Standardized Notebook Headers

- **Motivation/Background**: Jupyter notebooks frequently lack context, obscuring where their inputs come from, what scripts they depend on, or which experiment they analyze.
- **Purpose**: Define the mandatory first-cell markdown header for all interactive notebooks.
- **Overview Pipeline**: Validated during pre-commit reviews and codebase audits.
- **Detailed Plan**: §1 Standard First-Cell Template; §2 Mandatory References Block; §3 Prohibited Notebook Behaviors.
- **References**: `agents/rules/MD_CONVENTION.md`, `agents/rules/LOGGING_CHECKPOINT_RULES.md`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## Table of Contents

- [1. Standard First-Cell Template](#1-standard-first-cell-template)
- [2. Mandatory References Block](#2-mandatory-references-block)
- [3. Prohibited Notebook Behaviors](#3-prohibited-notebook-behaviors)

---

## 1. Standard First-Cell Template

The very first cell of every Jupyter notebook in `notebooks/` MUST be a Markdown cell with the following structure:

```markdown
# <Notebook Title>
### <Subtitle / Context>

- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Author**: <Author / Team>
- **Objective**: 1–2 sentences explaining what this notebook explores or validates.

---

## References & Consumed Artifacts

- **Source Code**: [`src/...`](../src/...)
- **Checkpoints**: [`experiments/runs/...`](../experiments/runs/...)
- **Configuration**: [`configs/...`](../configs/...)
- **Governing Rule**: [`agents/rules/LOGGING_CHECKPOINT_RULES.md`](../agents/rules/LOGGING_CHECKPOINT_RULES.md)
```

---

## 2. Mandatory References Block

- Every notebook must explicitly list and link all upstream Python modules from `src/` that it imports.
- Every notebook analyzing trained models must link the exact checkpoint or results file under `experiments/`.
- All links must use working relative paths.

---

## 3. Prohibited Notebook Behaviors

1. **NO TRAINING IN NOTEBOOKS:** Training loops (`for epoch in range(epochs):`) are strictly prohibited in notebooks. All training must be executed from scripts.
2. **NO UNTRACKED OUTPUTS:** Derived figures or tables intended for reports must be exported by scripts into `experiments/results/`.
