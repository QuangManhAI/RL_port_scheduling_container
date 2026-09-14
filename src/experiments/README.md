# src/experiments — Experiment Scripts

Long-running experiment pipelines (benchmarks, meta-model training, ablations)
live here as CLI scripts: `python -m src.experiments.<experiment>`.

## Rules

- Every experiment script persists its own outputs (JSON/NPZ/state dicts)
  under `experiments/results/<experiment>/` and indexes them in
  [experiments/results/README.md](../../experiments/results/README.md) with
  5W1H context.
- Document each experiment in
  [agents/experiments/README.md](../../agents/experiments/README.md) from
  [EXPERIMENT_TEMPLATE.md](../../agents/experiments/EXPERIMENT_TEMPLATE.md).
- Smoke-test before real runs
  ([SMOKE_TEST_CHECKLIST.md](../../agents/templates/SMOKE_TEST_CHECKLIST.md)).
