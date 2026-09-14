# src/data — Data Pipeline Layer

What belongs here:

- `transforms.py` — train/eval augmentation and normalization pipelines.
- `dataloader.py` — the canonical loader(s): dataset → `(train, val, test)`
  `DataLoader`s, download gated on an empty `data/raw/`.
- `dataset.py` / `statistics.py` / `inspection.py` — dataset wrappers,
  statistics, and validation helpers.
- `config.py` — configuration loader (reads `configs/config.yaml`).

Data is stored once under `data/raw/` (single source of truth) — no
re-download and no duplicate copies.

## Usage pattern

```python
from src.data.dataloader import get_loaders
train_loader, val_loader, test_loader = get_loaders(batch_size=64)
```

## Performance notes

- `num_workers = 0` by default (main-process loading) — the safe choice on
  Python 3.14 (see [agents/bugs](../../agents/bugs/README.md) for the
  BrokenPipeError case). Raise it on a stable runtime.
- Never fit scalers/statistics on the full dataset — fit on train only
  (leakage boundary, see
  [agents/ML_PIPELINE_REFERENCE_v3.md](../../agents/ML_PIPELINE_REFERENCE_v3.md) §10).

See [agents/phases/DATA_PREP.md](../../agents/phases/DATA_PREP.md).
