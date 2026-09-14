# src/eval — Evaluation Layer

What belongs here:

- `evaluate_model.py` — test-set evaluation: loss, top-1 accuracy, per-class
  accuracy, confusion matrix, optional isolated-subset metrics.

## Rules

- Evaluation functions are pure: take (model, loader, device) and return
  metric dicts — no training side effects.
- Every reported metric carries 5W1H context
  ([agents/rules/RESULTS_REPORTING.md](../../agents/rules/RESULTS_REPORTING.md)).

See [agents/phases/EVAL.md](../../agents/phases/EVAL.md).
