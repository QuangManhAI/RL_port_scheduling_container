# <EXPERIMENT_ID>: <TITLE> — Experiment Specification & Report Template

- **Motivation/Background**: Systematic deep learning experimentation requires formal hypotheses, isolated variables, and reproducible artifacts to prevent confounding results.
- **Purpose**: Document the objective, single variable changed, baseline comparison, 5W1H results, and findings for an individual experiment.
- **Overview Pipeline**: Copy into `docs/experiments/<EXP_ID>_<NAME>.md` prior to executing the experiment, then populate results upon completion.
- **Detailed Plan**: §1 Objective & Hypothesis; §2 Controlled Variables; §3 Setup & Hyperparameters; §4 Empirical Results (5W1H); §5 Key Findings & Regressions; §6 Reproduction Protocol.
- **References**: `agents/rules/MD_CONVENTION.md`, `agents/rules/RESULTS_REPORTING.md`, `agents/rules/LOGGING_CHECKPOINT_RULES.md`.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

## Metadata

- **Experiment ID**: `<e.g. EXP-01>`
- **Title**: `<e.g. RandAugment + Cutout on ConvNeXt-Tiny>`
- **Status**: [To Do | In Progress | Completed | Superseded | Canceled]
- **Target Script**: [`src/experiments/...`](...)
- **Output Directory**: [`experiments/runs/...`](...)

---

## 1. Objective & Hypothesis

- **Hypothesis**: <Clear statement of expected performance shift, e.g. "Introducing RandAugment (N=2, M=9) will reduce validation overfitting and improve top-1 accuracy by ≥0.5%">
- **Success Criteria**: <Quantifiable metric threshold, e.g. "Val accuracy ≥ 95.0% without training divergence">

---

## 2. Controlled Variables (Single-Variable Principle)

- **Variable Changed**: `<the single experimental modification, e.g. data augmentation transform>`
- **Held Constant**: `<model backbone, learning rate schedule, seed, optimizer, batch size>`

---

## 3. Setup & Hyperparameters

- **Dataset Split**: <Train / Val / Test sizes, seed>
- **Model Architecture**: [`src/models/...`](...)
- **Hyperparameters**:
  - `epochs`: <int>
  - `batch_size`: <int>
  - `lr`: <float>
  - `optimizer`: <name, weight_decay>
  - `seed`: 42

---

## 4. Empirical Results (5W1H)

> **5W1H — <Headline Result>**
> - **What**: Top-1 Accuracy on test split
> - **Why**: Measure generalization gain over baseline
> - **When**: Measured YYYY-MM-DD on checkpoint `<run_name>_best.pt`
> - **Where**: Artifacts in `experiments/runs/<run_dir>/`; run on `<device>`
> - **Who**: `<author/team>`
> - **How**: Evaluated with deterministic evaluation protocol, no TTA

### Comparison Table

| Model / Configuration | Val Loss | Val Acc (%) | Test Acc (%) | Δ Acc (%) | Checkpoint |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Baseline** | 0.245 | 94.20 | 94.10 | — | `baseline_best.pt` |
| **Experiment (<EXP_ID>)** | **0.210** | **94.85** | **94.70** | **+0.60** | `<exp_best>.pt` |

---

## 5. Key Findings & Regressions

- **Primary Finding**: <Plain-language summary of what occurred>
- **Regressions / Caveats**: <Any unexpected training slowdown, VRAM spikes, or per-class drops>
- **Decision**: [ADOPTED | REJECTED | NEEDS_FURTHER_STUDY]

---

## 6. Reproduction Protocol

```bash
# Execute training script
python -m src.experiments.<script_name> --epochs 30 --seed 42

# Evaluate checkpoint
python -m src.eval.evaluate_model --checkpoint experiments/runs/<run_dir>/checkpoints/<run>_best.pt
```

---

## 7. Associated Links

- Interactive Notebook Analysis: [`notebooks/...`](...)
- Task Status: [`docs/progress/<PHASE>_STATUS.md`](...)
- Master Experiment Index: [`docs/experiments/README.md`](README.md)
