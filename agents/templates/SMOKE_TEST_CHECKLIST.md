# SMOKE_TEST_CHECKLIST.md — Pre-Execution Verification Checklist

- **Motivation/Background**: Running full dataset training or long-running experiment pipelines without prior validation risks wasting hours of compute and agent context on elementary syntax or tensor shape errors.
- **Purpose**: Define strict smoke test criteria that every data, model, and training script must satisfy prior to full-budget execution.
- **Overview Pipeline**: Executed locally on CPU or dev GPU before triggering heavy jobs.
- **Detailed Plan**: §1 Definition of Smoke Tests; §2 Minimum Acceptance Criteria; §3 Hard Agent Enforcement Rule; §4 Exemptions.
- **References**: `agents/rules/AGENT_AI.md`, `agents/rules/LOGGING_CHECKPOINT_RULES.md`.
- **Created**: 2026-07-25T00:00:00+07:00
- **Last Updated**: 2026-09-06T20:55:00+07:00

---

## 1. What Counts as a Smoke Test

- **Data Pipelines:** Run on a synthetic slice or micro-subset (e.g. 50–100 rows). Assert output shape, channel dimensions, tensor dtypes, and non-NaN values.
- **Model Builders:** Forward pass a single batch of dummy inputs (`x = torch.randn(2, C, H, W)`). Assert logits shape matches `(2, num_classes)`.
- **Training Scripts:** Execute CLI with `--smoke` or `--epochs 1` on tiny batch size. Verify:
  - Checkpoint files (`<run>_best.pt`, `<run>_last.pt`) are created on disk.
  - Run log and JSONL metrics are generated in `experiments/runs/<ts>_<run_name>/`.
  - Loss is finite (not NaN or Inf).
  - Finishes in under ~60 seconds.
- **Evaluation Scripts:** Run inference on small held-out batch. Verify confusion matrix, metric dict, and plots write properly without Tkinter or GUI dependency errors.

---

## 2. Hard Agent Enforcement Rule

Before triggering full training or launching long experiments:
1. The agent MUST either verify that a smoke test has already succeeded for the current script revision, OR
2. Execute the smoke test explicitly and verify clean output in the session.

---

## 3. Exemptions

- Pure read-only inspection commands (`df.info()`, `df.describe()`).
- Trivial helper functions with dedicated unit tests.
