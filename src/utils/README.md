# src/utils — Shared Helpers

Cross-cutting utilities used by the other layers:

- `run_logger.py` — real-time logging + rotating files + JSONL history.
- `checkpoint_utils.py` — safe loading (`weights_only=True`), best/last
  checkpoint discovery, run registry lookups.
- Other small helpers as needed (device selection, seeds, path helpers).

Do not put domain logic here — it belongs in the layer that owns it.
