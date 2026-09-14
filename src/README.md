# src — Core Modules (SoC Layers)

- **Motivation/Background**: Separation of Concerns keeps data, models,
  training, evaluation, experiments, and utilities decoupled so each layer can
  be developed, tested, and audited independently.
- **Purpose**: Document the layer layout and the rule that training runs only
  from scripts — never from notebooks.
- **Overview Pipeline**: `src/data` → `src/models` → `src/training` →
  `src/eval`; `src/experiments` orchestrates; `src/utils` shared helpers.
- **Detailed Plan**: one section per layer with its responsibility and links.
- **References**: `agents/rules/FOLDER_STRUCTURE.md`,
  `agents/rules/LOGGING_CHECKPOINT_RULES.md`.

---

## Layers

| Package | Responsibility | Phase doc |
|---|---|---|
| [src/data](data/README.md) | Loading, transforms, dataloaders, statistics | `agents/phases/DATA_PREP.md` |
| [src/models](models/README.md) | Model builders, freeze/unfreeze strategies | `agents/phases/MODEL.md` |
| [src/training](training/README.md) | Training loop, full-state checkpoints, CLI entry points | `agents/phases/TRAINING_INFO.md` |
| [src/eval](eval/README.md) | Metrics, confusion matrices, evaluation scripts | `agents/phases/EVAL.md` |
| [src/experiments](experiments/README.md) | Long-running experiment scripts | `agents/phases/*` |
| [src/utils](utils/README.md) | run_logger, checkpoint_utils, shared helpers | — |

## Rules

- **Training happens only in scripts** — notebooks load artifacts and analyze.
- Every script must pass a smoke test before a real run
  ([agents/templates/SMOKE_TEST_CHECKLIST.md](../../agents/templates/SMOKE_TEST_CHECKLIST.md)).
- Checkpoint/logging format follows
  [agents/rules/LOGGING_CHECKPOINT_RULES.md](../../agents/rules/LOGGING_CHECKPOINT_RULES.md).
