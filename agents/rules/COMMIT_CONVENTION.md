# COMMIT_CONVENTION.md — Git Commit Message & Companion Document Standard

- **Motivation/Background**: In AI-assisted and machine learning codebases, Git history easily degrades into fragmented diffs where the technical rationale, experimental context, or audit trail is lost. Conventional commit messages provide structural consistency, but non-trivial engineering changes require deep context that exceeds the brevity limits of a commit body.
- **Purpose**: Define the mandatory commit message conventions, the Companion Markdown Document rule (the "Documented-Commit" mandate), the tiered triggering policy, and the `Companion-Doc:` Git trailer standard for human and AI contributors.
- **Overview Pipeline**: Formulated during project consolidation and audit hardening to ensure every commit in repository history provides an immediate, machine-parseable pointer to its authoritative documentation summary.
- **Detailed Plan**: §1 Conventional Commit Message Anatomy; §2 The Companion Markdown Document Rule; §3 Tiered Documentation Scope Matrix; §4 Standard Git Trailer Specification (`Companion-Doc:`); §5 Machine Parseability & Audit Automation; §6 Concrete Good vs. Bad Examples; §7 Pre-Commit Quality Checklist.
- **References**: `agents/rules/FOLDER_STRUCTURE.md`, `agents/rules/MD_CONVENTION.md`, `agents/rules/AGENT_AI.md`, `docs/references/GIT_AND_RELEASE_BEST_PRACTICES.md`.
- **Created**: 2026-09-08T11:05:00+07:00
- **Last Updated**: 2026-09-08T11:05:00+07:00

---

## Table of Contents

- [1. Conventional Commit Message Anatomy](#1-conventional-commit-message-anatomy)
- [2. The Companion Markdown Document Rule](#2-the-companion-markdown-document-rule)
- [3. Tiered Documentation Scope Matrix](#3-tiered-documentation-scope-matrix)
- [4. Standard Git Trailer Specification (`Companion-Doc:`)](#4-standard-git-trailer-specification-companion-doc)
- [5. Machine Parseability &amp; Audit Automation](#5-machine-parseability--audit-automation)
- [6. Concrete Good vs. Bad Examples](#6-concrete-good-vs-bad-examples)
- [7. Pre-Commit Quality Checklist](#7-pre-commit-quality-checklist)

---

## 1. Conventional Commit Message Anatomy

Every commit message in the repository MUST adhere to the Conventional Commits specification:

```text
<type>(<scope>): <imperative subject line ≤ 72 chars>

<optional body explaining the motivation, context, and key decisions>

Companion-Doc: docs/<path_to_companion_document>.md
```

### 1.1 Commit Types

- `feat`: New feature, pipeline stage, or user-facing capability.
- `fix`: Bug fix, error resolution, or data-patching remediation.
- `refactor`: Code reorganization or cleanup without altering functional behavior.
- `docs`: Documentation addition, specification update, or report generation.
- `chore`: Governance synchronization, template alignment, dependency lockfile refresh.
- `test`: Addition or modification of unit, integration, or smoke tests.
- `perf`: Performance optimization, memory reduction, or throughput acceleration.
- `ci`: Continuous integration workflow or runner configuration changes.

### 1.2 Subject Line Rules

- **Imperative Mood**: Use "fix", "add", "update", "refactor" (not "fixed", "added", "updating").
- **Length Constraint**: Strictly **≤ 72 characters**. If the subject line cannot fit within 72 characters, the commit is likely attempting multiple unrelated changes.
- **Punctuation**: No trailing period.
- **Scope Discipline**: A commit must represent **one logical atomic change**. Never bundle unrelated changes (e.g. model bug fix + documentation cleanup) into a single commit.

---

## 2. The Companion Markdown Document Rule

> ### The "Documented-Commit" Mandate
>
> **For every non-trivial commit, code modifications MUST be accompanied by a companion Markdown document (or an update to an existing authoritative document in `docs/`) staged and committed together with the code.**
>
> The commit message MUST explicitly cite the companion Markdown document using the standard Git trailer:
>
> ```text
> Companion-Doc: docs/<path>.md
> ```

### 2.1 Why This Rule Exists

1. **Traceability for Future Agents & Humans**: When scanning `git log` months later, developers and autonomous agents can immediately inspect the companion report to understand *why* architectural decisions were made, *how* data was filtered, and *what* empirical validation was executed.
2. **Preventing Code-Documentation Drift**: Committing code and documentation in separate commits leads to stranded documentation branches and uncommitted reports. Committing them atomically guarantees that repository documentation accurately mirrors the codebase state at every commit.
3. **Dual-Paradigm Architectural Discipline**: Reinforces the separation between immutable agent governance (`/agents`) and project knowledge memory (`docs/`). Companion documents reside in `docs/`, never in `/agents`.

---

## 3. Tiered Documentation Scope Matrix

To prevent documentation bloat on trivial tasks while ensuring comprehensive records for substantial engineering milestones, commits are categorized into two tiers:

| Tier                                                | Commit Classification                             | Examples                                                                                                                                                                                     | Documentation Requirement                                                                                                                                                                                                                                      | Git Trailer Requirement                                                                                                                           |
| :-------------------------------------------------- | :------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Tier 1: Major & Structural Commits**        | **Mandatory Dedicated or Updated Document** | - Architectural refactors- PR integration & merges- Multi-file features & training pipelines- Bug incident diagnoses & fixes- Codebase audit re-baselines- Completed experimental iterations | **Must create or update a dedicated document in `docs/`**: e.g.,- `docs/PR_<NN>_AUDIT_AND_MERGE_REPORT.md`- `docs/CODEBASE_AUDIT_REPORT.md`- `docs/bugs/BUG_<NN>_<DESC>.md`- `docs/experiments/EXP_<NN>_<DESC>.md`- `docs/phases/<PHASE>.md` | **Mandatory**:`Companion-Doc: docs/...`*(Optional secondary: `Report: docs/...`)*                                                     |
| **Tier 2: Routine Maintenance & Minor Edits** | **Existing Progress Doc / In-line Citing**  | - Single-line typo or lint fixes- Minor configuration parameter adjustments- Test fixture updates- Routine documentation touchups                                                            | **May update an existing status tracker in `docs/progress/` or cite the parent phase document.** No new dedicated Markdown file required.                                                                                                              | **Optional / Recommended**:Cite parent tracker (e.g. `Companion-Doc: docs/progress/<PHASE>_STATUS.md`) or omit if purely self-describing. |

---

## 4. Standard Git Trailer Specification (`Companion-Doc:`)

Git trailers are standard key-value metadata pairs placed at the very end of the commit message body (following an empty line), recognized natively by Git tools and automation scripts.

### 4.1 Canonical Trailer Keys

- `Companion-Doc:`: Primary pointer to the authoritative Markdown document documenting the commit.
- `Report:`: Secondary pointer for formal reports (e.g. audit, merge, or benchmark evaluations).
- `Fixes:`: Links to GitHub issue or bug incident tracker (e.g. `Fixes: docs/bugs/BUG_01_CELEBDF_TEST_LABEL_FIX.md`).

### 4.2 Formatting Rules

1. Preceded by an empty line following the commit body.
2. Follows format: `Key: <relative_path_from_repo_root>`.
3. Target file must be committed within the same commit or exist on `main`.

```text
refactor(docs): migrate project documentation from agents/ to docs/ hierarchy

Reorganize repository layout to comply with Archetype A Dual-Paradigm rules.
Move all evolving project specifications, research guides, and experiment reports
into docs/, reserving /agents strictly for immutable rules and templates.

Companion-Doc: docs/FOLDER_STRUCTURE.md
Report: docs/PR_05_AUDIT_AND_MERGE_REPORT.md
```

---

## 5. Machine Parseability & Audit Automation

By adhering to standard Git trailers, agents and CI/CD pipelines can programmatically extract documentation links:

```bash
# Extract all companion documents from recent commits
git log -n 10 --format="%(trailers:key=Companion-Doc,valueonly)"

# Verify every non-trivial commit has a companion document
git log --grep="feat" --format="%h %s %(trailers:key=Companion-Doc)"
```

This guarantees that automated codebase audit agents can inspect Git history and verify that every feature, refactor, and bug fix has verifiable documentation evidence.

---

## 6. Concrete Good vs. Bad Examples

### Example 1: Bug Fix with Incident Report

- **Good**:
  ```text
  fix(data): resolve Celeb-DF test set labeling inversion

  Correct substring matching in prepare_df40_splits.py to properly identify
  'celeb_test_fake_' prefixes, preventing 1,700 fakes from mislabeling as real.
  Regenerate all balanced test split manifests.

  Companion-Doc: docs/bugs/BUG_01_CELEBDF_TEST_LABEL_FIX.md
  ```
- **Bad**:
  ```text
  fix bug in test split
  ```

  *(Missing type scope, missing rationale, no companion incident report)*

### Example 2: PR Merge & Conflict Stabilization

- **Good**:
  ```text
  merge: resolve conflicts between main and PR #5 (bush-le:main)

  Resolve 32 conflicting files across data scripts, models, and notebooks.
  Adopt FlashAttention in dinov3_vit.py and preserve portable path resolution.

  Companion-Doc: docs/PR_05_AUDIT_AND_MERGE_REPORT.md
  ```
- **Bad**:
  ```text
  merged pr5 and fixed stuff
  ```

  *(Untraceable conflict resolution decisions; no audit report)*

### Example 3: Experimental Benchmark Evaluation

- **Good**:
  ```text
  feat(eval): add 44-methods zero-leakage balanced coursework evaluation

  Integrate DINOv3 ViT-S/16 and ConvNeXt-Tiny comparative evaluation harness
  across 21.4k balanced and 50k full test sets.

  Companion-Doc: docs/experiments/EXP_04_COURSEWORK_44METHODS_BENCHMARK.md
  Report: docs/CODEBASE_AUDIT_REPORT.md
  ```

---

## 7. Pre-Commit Quality Checklist

Before running `git commit`, verify:

- [ ] Subject line uses imperative mood, lowercase (except proper nouns), and is **≤ 72 characters**.
- [ ] The commit represents **one logical atomic change**.
- [ ] Tier 1 changes include a companion Markdown document created or updated in `docs/`.
- [ ] The commit message contains the `Companion-Doc: docs/<path>.md` Git trailer.
- [ ] The companion document adheres to the 7-field header standard defined in `agents/rules/MD_CONVENTION.md`.
- [ ] No temporary files, credentials, or large binary weights are staged.
