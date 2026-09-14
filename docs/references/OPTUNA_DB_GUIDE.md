# Optuna SQLite Study Reference & Analysis Guide

| Field | Value |
| :--- | :--- |
| **Document Type** | Tool Reference & Analysis SOP |
| **Status** | Active Reference |
| **Owner** | AI Agent & Human Practitioner |
| **Scope** | Hyperparameter Optimization & Study Persistence |
| **Created** | 2026-08-09T19:40:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/references/README.md](README.md), [agents/rules/LOGGING_CHECKPOINT_RULES.md](../../agents/rules/LOGGING_CHECKPOINT_RULES.md) |

---

Quick reference for loading, analyzing, and exporting an Optuna SQLite study.
Read on demand when doing HPO analysis — not part of always-on rules.
Runnable script version: `src/utils/optuna_db_report.py`

## Load
```python
import optuna
study = optuna.load_study(study_name='<name>', storage='sqlite:///<path>.db')
```
`load_study` reads persisted trials only — doesn't re-run optimization.
`study_name` must match what was passed to `create_study()`.

## Inspect
```python
from optuna.trial import TrialState
complete = [t for t in study.trials if t.state == TrialState.COMPLETE]
pruned   = [t for t in study.trials if t.state == TrialState.PRUNED]

best = study.best_trial   # .number, .value, .params, .user_attrs, .duration
df = study.trials_dataframe()   # columns: number, value, datetime_*, duration,
                                 # params_<hp>, user_attrs_<key>, state
```

## Filter
```python
good   = [t for t in complete if t.params.get('dropout', 0) >= 0.2]
normal = [t for t in complete if t.duration.total_seconds() < 600]  # drop hw outliers
```
Trials taking 10×+ longer than same-config peers are usually hardware
hiccups — exclude before analysis.

## Hyperparameter importance (FANOVA)
```python
from optuna.importance import get_param_importances
imp = get_param_importances(study)  # default target = objective value
imp_val = get_param_importances(study, target=lambda t: t.user_attrs.get('val_acc', 0)/100)
```
⚠️ Has internal randomness — re-running shifts values slightly; needs ≥5
complete trials for a stable ranking. **Target metric choice matters a
lot** — objective value vs. `val_acc` can reorder importance drastically.

## Pattern checks
- **Top-N**: `sorted(complete, key=lambda t: -t.value)[:5]`
- **Dead zones** (100% pruned configs): crosstab `state` against each
  `params_*` column, flag any value where pruned fraction == 1.0
- **LR distribution**: compare min/median/max of `t.params['lr']` between
  COMPLETE and PRUNED groups
- **Per-epoch curves**: `trial.intermediate_values` (dict of epoch→value) —
  use to check convergence speed or whether pruning fired too early

## Visualize
```python
from optuna.visualization import plot_param_importances, plot_parallel_coordinate
plot_param_importances(study).write_html('param_importance.html')
```
`write_image()` needs `kaleido` installed; use `write_html()` otherwise.

## Export (to /agents or similar)
Write three files: a JSON summary (`best_trial`, counts, params), a full
`trials_dataframe().to_csv(...)`, and an importance CSV. Full working
version: `src/utils/optuna_db_report.py`.

## Pitfalls
| Symptom | Fix |
|---|---|
| FANOVA ranking changes each run | Average multiple runs; need ≥5 complete trials |
| Dashboard vs script disagree on importance | Check target metric (val_acc vs objective) |
| `StudyNotFound` on `load_study` | Verify `study_name` and DB path match `create_study()` |
| `params_<x>` mostly NaN, FANOVA warns | Conditional HPs — FANOVA handles NaN by design, but double check |
| One trial 10×+ longer than peers | Filter by `duration.total_seconds() < threshold` |
| Pruned trial has no `.value` | Trial never reported — check for `None` before using |
| `write_image` fails | Install `kaleido`, or use `write_html` |

