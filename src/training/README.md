# src/training — Training Layer (scripts only)

What belongs here:

- `train_model.py` — the generic training loop: full-state checkpointing
  (model + optimizer + scheduler + RNG + history + config), early stopping,
  resume, TensorBoard hook.
- `run_logger.py` — zero-dependency real-time logging (console progress,
  rotating log files, JSONL per-epoch history).
- `<feature>_train.py` — per-feature CLI entry points that wire data + model +
  loop together and are run with `python -m src.training.<feature>_train`.

## Hard rule

**Training runs only from these scripts.** Notebooks never contain a training
loop; they load artifacts produced here. See
[agents/rules/LOGGING_CHECKPOINT_RULES.md](../../agents/rules/LOGGING_CHECKPOINT_RULES.md).

See [agents/phases/TRAINING_INFO.md](../../agents/phases/TRAINING_INFO.md).
