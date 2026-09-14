# RESULTS_REPORTING.md — 5W1H Rules for Every Reported Result

- **Motivation/Background**: Results shown to teammates or teachers were often bare numbers (e.g. `test_acc=97.21%`) with no context, making them unverifiable and hard to interpret.
- **Purpose**: Make the 5W1H principle (What, Why, When, Where, Who, How) mandatory for every metric presented in docs, notebooks, or reports.
- **Overview Pipeline**: Applies to every result in `agents/experiments/*.md`, `experiments/results/*`, and analysis notebooks.
- **Detailed Plan**: §1 the 5W1H rule; §2 the required block format; §3 metric-description pairs (project-definable); §4 where it applies; §5 checklist.
- **References**: `agents/experiments/README.md`, `experiments/results/README.md`, `agents/rules/MD_CONVENTION.md`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## Table of Contents

- [1. The Rule](#1-the-rule)
- [2. Required 5W1H Block](#2-required-5w1h-block)
- [3. Metric Description Pairs](#3-metric-description-pairs)
- [4. Where It Applies](#4-where-it-applies)
- [5. Checklist](#5-checklist)

---

## 1. The Rule

Every result value reported to teammates or teachers MUST be accompanied by a
5W1H explanation. A number alone is not a result — it is a claim.

- **What** — which metric, computed on which data split, which model variant.
- **Why** — the question this metric answers / why it matters.
- **When** — when it was measured (date, checkpoint, epoch, seed).
- **Where** — where the artifact lives (file/notebook/plot path) and where it was run (device).
- **Who** — who produced it (author/team) and who it is for.
- **How** — how it was computed (evaluation protocol, hyperparameters, leakage notes).

## 2. Required 5W1H Block

Insert this block (or the equivalent table) before any results table in a report:

```markdown
> **5W1H — <Result headline>**
> - **What**: ...
> - **Why**: ...
> - **When**: measured <date> on checkpoint <name> (epoch <n>, seed <s>).
> - **Where**: artifacts in `experiments/results/<file>.json`; run on <device>.
> - **Who**: <author> — for <audience>.
> - **How**: <evaluation protocol, hyperparameters, leakage guarantees>.
```

For per-metric explanations use the table form in §3.

## 3. Metric Description Pairs

Every metric in a table must have a companion "what it means / how it is
computed" line. **Extend this table per project** — add every metric your
project actually reports (e.g. per-class accuracy, confusion counts, latency,
throughput, F1 per class). Common starting points:

| Metric | 5W1H description |
|---|---|
| `test_acc` | What: top-1 accuracy on the official test split. How: argmax over softmax, no TTA unless stated. Why: headline generalization. |
| `val_acc` / `val_loss` | What: metrics on the fixed validation split (seed 42). How: computed every epoch after the training step. Why: model selection. |
| `F1 (macro)` | What: mean per-class F1. Why: class-balance-aware summary. |
| `precision` / `recall` | What: per-class precision/recall. Why: reveals minority-class failure modes (report for imbalanced data, never just accuracy). |
| `dAcc` | What: delta vs a fixed reference baseline. How: `metric - baseline`. Why: isolates the added method's gain. |
| `params (M)` | What: total parameter count. Why: model size / memory cost. |
| `latency (ms)` | What: mean±std wall-clock per inference batch. How: `time.perf_counter`, warmup iterations, fixed batch size. Why: deployment cost. |
| `img/s` | What: throughput = batch/latency. Why: efficiency at serving time. |

> **Note (from experience):** measured `GFLOPs` proved unstable (dataloader
> noise dominated the 1–2% spread) and did not reflect real cost — prefer
> params + latency + throughput as the meaningful, reproducible efficiency
> metrics.

## 4. Where It Applies

- `agents/experiments/*.md` result tables (add the block above each table).
- `experiments/results/README.md` metric index (every file gets What/Why/How).
- Notebook analysis sections that present numbers to an audience.
- Any message to teammates/teachers quoting a metric.

## 5. Checklist

- [ ] Every table has a 5W1H block (or header row with context).
- [ ] Every metric has a companion description (§3 table or inline).
- [ ] Split, seed, checkpoint, and evaluation protocol are stated.
- [ ] Artifact file paths are given.
- [ ] No bare numbers without context.
