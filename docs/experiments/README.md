# Experiment Specifications & Analysis Records

| Field | Value |
| :--- | :--- |
| **Document Type** | Documentation Subsystem Index |
| **Status** | Active Index |
| **Owner** | AI Agent & Human Practitioner |
| **Scope** | Experiments & Hypotheses |
| **Created** | 2026-09-06T21:05:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/README.md](../README.md), [agents/templates/EXPERIMENT_TEMPLATE.md](../../agents/templates/EXPERIMENT_TEMPLATE.md) |

---

## Purpose & Conventions

This directory contains human-readable experiment specifications, design rationales, and post-run analysis reports.

> [!NOTE]
> This directory houses Markdown analysis specifications and summaries. Raw model weights, tensorboard logs, and checkpoints live in `experiments/runs/` and `experiments/checkpoints/` and are excluded from git.

### Rules for Experiment Logging

1. Copy [agents/templates/EXPERIMENT_TEMPLATE.md](../../agents/templates/EXPERIMENT_TEMPLATE.md) into this directory:
   - e.g., `EXP_01_BASELINE_CONVNET.md`, `EXP_02_COSINE_ANNEALING.md`.
2. Clearly formulate hypotheses before launching training runs.
3. Once training completes, document quantitative results, failure analysis, and next steps in the designated sections.
