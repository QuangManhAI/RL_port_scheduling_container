# LOGGING_CHECKPOINT_RULES.md — Logging, Checkpointing & Resumability Rules

- **Motivation/Background**: Training must survive interruptions and every run must be reproducible. Training inside notebooks with only best-state `.pt` saves loses optimizer/scheduler/RNG state and history; notebooks also cannot be relied on to persist outputs.
- **Purpose**: Define the authoritative, **project-generic** rules for log files, checkpoints, directory layout, naming, the load/resume procedure, and automatic output persistence. They apply to every feature project in this repository. Project-specific examples live in the optional [Appendix A](#appendix-a-optional--project-specific-example).
- **Overview Pipeline**: Codified during the refactor that moved all training out of notebooks into script entry points and upgraded `src/training/train_model.py` with full-state checkpointing and `src/utils/run_logger.py` (zero-dependency logging).
- **Detailed Plan**: §1 policy (scripts vs notebooks, automatic persistence); §2 directory structure; §3 checkpoint file format; §4 naming rules; §5 resume procedure; §6 metrics storage & compression; §7 log levels & real-time monitoring; §8 acceptance checklist; Appendix A (optional) project-specific example.
- **References**: `torch.save`/`torch.load (weights_only=True)`, `src/utils/run_logger.py`, `src/training/train_model.py`, `numpy`, `gzip` (stdlib), `src/utils/checkpoint_utils.py`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## Table of Contents

- [1. Script-Only Runs &amp; Automatic Persistence](#1-script-only-runs--automatic-persistence)
- [2. Directory Structure](#2-directory-structure)
- [3. Checkpoint File Format](#3-checkpoint-file-format)
- [4. Naming Rules](#4-naming-rules)
- [5. Resume Procedure](#5-resume-procedure)
- [6. Metrics Storage &amp; Compression](#6-metrics-storage--compression)
- [7. Log Levels &amp; Real-Time Monitoring](#7-log-levels--real-time-monitoring)
- [8. Acceptance Checklist](#8-acceptance-checklist)
- [Appendix A (optional) — Project-Specific Example](#appendix-a-optional--project-specific-example)

---

## 1. Script-Only Runs & Automatic Persistence

- **Notebooks never train** and never re-persist run state. Notebooks are limited
  to testing, demos, unit tests, visualization and analysis; they load artifacts
  produced by scripts.
- **Every feature project exposes script entry points** (CLI modules under
  `src/`) for all training and for any long-running experiment pipeline.
- A notebook cell may *invoke* a documented script command, but must never
  contain a training loop.
- **Every required output is persisted automatically by the feature run.**
  The run must write — without any manual/notebook re-saving step — its
  checkpoints, logs, config, per-epoch history, and any derived result it
  declares in its config (`outputs` list). Nothing is "saved later" from a
  notebook.
- If results from multiple runs must be consolidated (e.g. a combined history),
  the **script** performs the consolidation and writes the aggregate artifact.

## 2. Directory Structure

```
<project>/experiments/
├── runs/                          # one directory per run (all run state lives here)
│   ├── <YYYYmmdd_HHMMSS>_<run_name>/     # e.g. 20260810_091530_<run_name>
│   │   ├── checkpoints/
│   │   │   ├── <run_name>_best.pt         # best tracked-metric state
│   │   │   └── <run_name>_last.pt         # every-epoch state (resume source)
│   │   ├── logs/
│   │   │   └── <run_name>.log             # timestamped log (+ .1.log.gz rotation)
│   │   ├── metrics/
│   │   │   ├── <run_name>_config.json     # config + 5W1H description + outputs list
│   │   │   └── <run_name>_history.jsonl   # one JSON line per epoch
│   │   └── tensorboard/                   # optional TensorBoard event files
│   └── registry.json              # run_name -> latest run dir (artifact loading)
├── results/                       # cross-run outputs, WRITTEN ONLY BY SCRIPTS
│   ├── README.md                  # index: every artifact, described (5W1H)
│   └── <experiment>/              # per-feature consolidated artifacts
├── checkpoints/                   # LEGACY flat location (read-only fallback)
└── plots/                         # generated figures
```

- The **run directory is created once by `RunLogger`**; every artifact of a run
  lives inside it, written by the run itself.
- `results/` holds **consolidated cross-run outputs that scripts produce** (e.g.
  combined histories, evaluation summaries, NPZ feature caches). Notebooks may
  *read* them for analysis; they never *write* logs, histories, or checkpoints
  back into `runs/` or `results/`.

## 3. Checkpoint File Format

Every checkpoint is a single `torch.save` dict, loaded with **`weights_only=True`** (safe against pickle RCE):

| Key                                                   | Content                                                                               |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `model_state_dict`                                  | full model parameters (required)                                                      |
| `optimizer_state_dict`                              | optimizer state — moments + step counters (required for resume)                      |
| `scheduler_state_dict`                              | scheduler state (if a scheduler is used)                                              |
| `epoch`                                             | last completed epoch                                                                  |
| `global_step`                                       | total optimizer steps so far                                                          |
| `best_val_loss` / `best_val_acc` / `best_epoch` | best tracked metrics                                                                  |
| `history`                                           | per-epoch metric lists (e.g.`{train_losses, val_losses, train_accs, val_accs}`)     |
| `config`                                            | hyperparameters, seed, transforms, 5W1H description,`outputs` list                  |
| `rng`                                               | serialized seeds + torch (CPU/GPU)/numpy/python RNG states (hex strings — JSON-safe) |
| `timestamp`                                         | ISO-8601 save time                                                                    |
| `commit`                                            | git commit the run was started from (best-effort)                                     |

Rationale: model+optimizer+scheduler+RNG+history together guarantee an **exact** resume, not just a weight reload.

## 4. Naming Rules

- Run directories: `<YYYYmmdd_HHMMSS>_<run_name>` (timestamp prefix keeps runs sortable).
- Checkpoints: `<run_name>_best.pt` (best tracked metric) and `<run_name>_last.pt` (every epoch, resume source).
- Log file: `<run_name>.log` in the run's `logs/`; rotated archives `<run_name>.<n>.log.gz`.
- Config: `<run_name>_config.json`; history: `<run_name>_history.jsonl` (in `metrics/`).
- `<run_name>` must be filesystem-safe: `[A-Za-z0-9_-]` (other chars → `_`).
- Consolidated artifacts in `results/`: lowercase `snake_case`, verb-first (e.g. `training_history.json`).

## 5. Resume Procedure

To continue an interrupted run **exactly** where it stopped:

1. Re-run the same feature command with its `--resume` flag.
2. The loader finds the latest run dir for the requested run and loads `<run_name>_last.pt`.
3. Restored in order: model weights → optimizer state → scheduler state → RNG states → history → best metrics; training continues at `epoch + 1` with `global_step` preserved.
4. Manual resume: pass the run directory or checkpoint path as `resume_from=` to `train_model(...)`; the procedure is identical.
5. Do **not** resume from `_best.pt` — it only reflects the best-epoch snapshot (model weights + optimizer at that epoch), which is still resumable but loses the latest epoch's progress; prefer `_last.pt`.

**Early stopping and resume:**
- Every checkpoint records `early_stop_triggered`. If the last checkpoint was saved
  on an early-stopped run, `--resume` **halts** (the run is complete) instead of
  silently continuing past the early-stop point — it will not retrain epochs after
  the stop.
- To **continue from the best epoch** (rewind) with a fresh early-stopping budget,
  use `--force-resume` (or `resume_from_best=True`): it loads `<run_name>_best.pt`,
  resets the early-stopping counter, and resumes at `best_epoch + 1`.

Interruption safety: `_last.pt` is written **after every epoch**, so at most one epoch of work is lost.

## 6. Metrics Storage & Compression

- **Automatic persistence is mandatory**: at the end of a successful (or
  interrupted-but-checkpointed) run, `experiments/runs/<ts>_<run>/` must already
  contain the config, the JSONL history, the log file, and both checkpoints —
  produced by the run itself, with no notebook step.
- Per-epoch metrics append as one JSON line to `<run_name>_history.jsonl` (append-only, cheap, crash-safe).
- Large derived arrays (probability matrices, features) are written automatically by the run as **compressed NPZ** (`np.savez_compressed`) — in the run's `metrics/` or the feature's `results/<experiment>/` dir, as declared in its config.
- Log files auto-rotate: when a `.log` exceeds **20 MB** it is gzip-archived (`<run_name>.<n>.log.gz`, keep 3 archives) and truncated.
- Rule of thumb: one JSON/JSONL file per *logical unit* (run history, config, consolidated results); never one file per epoch.
- Old consolidated artifacts under `results/` may be gzip-archived (`.json.gz`) when > 10 MB; keep the `results/README.md` index current.

## 7. Log Levels & Real-Time Monitoring

- Every run writes to: console (live progress line: epoch, batch, loss, acc, lr, ETA), `<run_name>.log`, and `metrics/`.
- Real-time monitoring options:
  - **Lightweight (always on, zero dependencies)**: `RunLogger.progress()` single-line updates + `epoch_summary()` per epoch.
  - **TensorBoard (optional)**: an opt-in `--tb` flag enables `SummaryWriter` per run (`runs/<ts>_<run>/tensorboard`); view with `tensorboard --logdir experiments/runs`.
- Log lines are timestamped `[HH:MM:SS] [LEVEL] message`; levels: `INFO`, `TRAIN` (epoch summaries), `WARN`, `ERROR`.

## 8. Acceptance Checklist

- [ ] Training/experiment launched from a script; notebook contains no training loop.
- [ ] Every run produced `<run>_best.pt` + `<run>_last.pt` + log + config + history **automatically**.
- [ ] The run's config declares its `outputs`; every declared output was persisted by the run itself.
- [ ] `--resume` restores and continues (verified by re-running after interruption).
- [ ] Checkpoint loads with `weights_only=True`.
- [ ] Consolidated outputs are indexed in `results/README.md` with 5W1H context.
- [ ] Registry updated: `experiments/runs/registry.json` points at the latest run dir.

---

## Appendix A (optional) — Project-Specific Example

> This appendix is a worked example for THIS project only. Fill in your own
> script entry points, run names, and result directories. Do not copy feature
> names from other projects into the core rules.

- **Deliverable training script**: `python -m src.training.<feature>_train`
  (`--epochs`, `--seed`, `--resume`, `--force-resume`, `--tb`, `--smoke`).
- **Meta-model scripts**: `python -m src.experiments.<experiment>_train` (if any).
- **Run names**: `<Model>-<variant>` (e.g. `<ModelA>-baseline`, `<ModelA>-finetune`).
- **Consolidated outputs (script-written)**: `results/<experiment>/` — JSON
  metrics, NPZ arrays, state dicts, config; index them in
  `experiments/results/README.md` with 5W1H.
- **Notebooks** (`notebooks/<analysis>.ipynb`) load these artifacts for
  analysis only.
