# Living Project Overview & Roadmap

| Field | Value |
| :--- | :--- |
| **Document Type** | Project Roadmap & Phase Index |
| **Status** | Active Template |
| **Owner** | Research Lead / AI Agent |
| **Scope** | Global Repository Scope |
| **Created** | 2026-09-06T21:05:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/PURPOSE.md](PURPOSE.md), [docs/README.md](README.md) |

---

## 1. Project Summary

- **Project Name:** [Fill in — e.g. Vision Transformer Transfer Learning Baseline]
- **Target Domain:** [Fill in — e.g. Computer Vision / NLP / Tabular]
- **Primary Goal:** [Fill in — concise summary derived from PURPOSE.md §4]

---

## 2. Technical Blueprint

- **Dataset:** [Name, source, train/val/test split sizes, pre-processing requirements]
- **Model Architectures:** [Baseline vs. Proposed architectures, pre-trained weights source]
- **Evaluation Metrics:** [Primary metric, secondary diagnostic metrics, baseline benchmarks]
- **Infrastructure & Environment:** [Target hardware, batch size limits, mixed-precision settings]

---

## 3. Research Phases

Each phase is documented in `docs/phases/` according to [agents/templates/PHASE_DOC_TEMPLATE.md](../../agents/templates/PHASE_DOC_TEMPLATE.md).

| Phase | Specification Document | Description | Target Deliverable | Status |
| :--- | :--- | :--- | :--- | :--- |
| Phase 1 | [docs/phases/01_DATA_PIPELINE.md](phases/01_DATA_PIPELINE.md) | Data loading, transforms, validation splits | Deterministic DataLoader & tests | Not Started |
| Phase 2 | [docs/phases/02_MODEL_BASELINE.md](phases/02_MODEL_BASELINE.md) | Model architecture & forward pass verification | PyTorch Module & unit tests | Not Started |
| Phase 3 | [docs/phases/03_TRAINING_PIPELINE.md](phases/03_TRAINING_PIPELINE.md) | Script-driven training with full-state checkpointing | Reproducible train CLI script | Not Started |
| Phase 4 | [docs/phases/04_EXPERIMENTS_ANALYSIS.md](phases/04_EXPERIMENTS_ANALYSIS.md) | Systematic ablations & hyperparameter search | Verified checkpoints, logs, & plots | Not Started |

---

## 4. Operational Progress Status

Active session updates and task trackers are maintained in `docs/progress/` according to [agents/templates/PROGRESS_STATUS_TEMPLATE.md](../../agents/templates/PROGRESS_STATUS_TEMPLATE.md).

- [Phase 1 Progress](progress/01_DATA_PIPELINE_STATUS.md)
- [Phase 2 Progress](progress/02_MODEL_BASELINE_STATUS.md)
- [Phase 3 Progress](progress/03_TRAINING_PIPELINE_STATUS.md)
- [Phase 4 Progress](progress/04_EXPERIMENTS_ANALYSIS_STATUS.md)

---

## 5. Known Constraints & Pitfalls

- [Record compute limits, dataset oddities, Python compatibility caveats, or package version constraints early to prevent silent failures.]
