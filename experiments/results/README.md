# experiments/results — Metrics Index & Descriptions

Every file below is described with the 5W1H principle (What / Why / When /
Where / Who / How) — see
[agents/rules/RESULTS_REPORTING.md](../../agents/rules/RESULTS_REPORTING.md).
Training-state logs and checkpoints live in `experiments/runs/`, NOT here.

## Metric files

| File | 5W1H description |
|---|---|
| `<experiment>.json` | **What**: <metrics> on <split>. **Why**: <question it answers>. **When**: written by <script> on <date/run>. **Where**: <path>. **Who**: <author> → <audience>. **How**: <protocol, seed, leakage notes>. |
| `<experiment>/` | **What**: <artifacts — npz/pt/config/history>. **Why**: <analysis without re-training>. **How**: `python -m src.experiments.<experiment>`. **Note**: `.npz`/`.pt` are regenerable by that script and gitignored. |

## Storage rules

- One JSON/JSONL file per **logical unit** (run history, config, experiment), never per epoch.
- Large probability/feature arrays use **compressed NPZ** (`np.savez_compressed`).
- Files > 10 MB may be gzip-archived (`file.json.gz`); keep this index current.
- Never write training state into this folder — it belongs in `experiments/runs/`.
