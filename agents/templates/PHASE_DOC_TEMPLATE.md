# <PHASE_NAME>.md — Pipeline Phase Technical Specification Template

- **Motivation/Background**: Deep learning pipeline phases (data prep, feature engineering, modeling, training, evaluation) fail when interfaces, expected shapes, and failure modes are unstated.
- **Purpose**: Provide a comprehensive specification of a single pipeline phase, including I/O contracts, execution commands, and edge cases.
- **Overview Pipeline**: Copy to `docs/phases/<PHASE_NAME>.md` when planning a new pipeline stage.
- **Detailed Plan**: §1 Name & Scope; §2 Input & Output Contracts; §3 Execution Pipeline; §4 Technical Specification & Edge Cases; §5 Associated Links.
- **References**: `agents/rules/MD_CONVENTION.md`, `agents/rules/FOLDER_STRUCTURE.md`.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

## Metadata

- **Phase ID**: `<e.g. PHASE-02>`
- **Phase Name**: `<e.g. Data Loading & Augmentation Pipeline>`
- **Status**: [To Do | In Progress | Completed | Blocked]
- **Target Modules**: [`src/data/...`](...)

---

## 1. Scope & Objective

### Background
<Why this phase exists. What problem it addresses in the overall project lifecycle.>

### Goals & Acceptance Criteria
- [ ] Concretely what "done" looks like for this phase
- [ ] Deterministic output shapes and types verified
- What this phase explicitly does **NOT** attempt to solve

---

## 2. Input & Output Contracts

- **Inputs**:
  - Source data: [`data/raw/...`](...)
  - Config file: [`configs/...`](...)
- **Outputs**:
  - Processed artifacts: [`data/processed/...`](...)
  - Verified schema: tensor shape `(B, C, H, W)`, dtype `torch.float32`

---

## 3. Execution Pipeline

```text
src/data/dataset.py ──► src/data/transforms.py ──► src/data/dataloader.py
```

Command-line invocation:
```bash
python -m src.data.inspection --config configs/data.yaml
```

---

## 4. Technical Specification & Edge Cases

- **Parameters & Hyperparameters**: <e.g. batch size, num workers, normalization constants>
- **Known Gotchas & Failure Modes**: <e.g. multi-processing worker deadlocks, memory leaks>
- **Code Links**: [`src/data/transforms.py`](...)

---

## 5. Associated Links

- Live Progress Status: [`docs/progress/<PHASE>_STATUS.md`](...)
- Unit Tests: [`tests/test_dataloader.py`](...)
- Master Overview: [`docs/README.md`](...)
