# Git, CI, and Release Best Practices

| Field | Value |
| :--- | :--- |
| **Document Type** | Engineering Standards & Release Workflow |
| **Status** | Active Reference |
| **Owner** | Repository Maintainers & AI Agent |
| **Scope** | Git Operations, CI, and Release Packaging |
| **Created** | 2026-08-11T18:15:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/references/README.md](README.md), [.github/workflows/ci.yml](../../.github/workflows/ci.yml) |

---
> ## ⚠️ MANDATORY HUMAN-APPROVAL GATE (read this first)
>
> **An AI agent must NEVER push source code — no `git push` of commits,
> branches, or tags that change source, and no release creation that ships
> source — without first obtaining explicit human approval.**
>
> - "Explicit approval" means the human has reviewed the exact changes and
>   answered "yes, commit/push". A silent, automatic, or assumed approval does
>   not count.
> - This applies to **every** push: feature branches, `main`, tags, and release
>   triggers. There are no exceptions for "small" or "obvious" changes.
> - **Before committing:** present the proposed commit message and the file
>   list, and ask for approval (e.g. via the `question` tool).
> - **Before pushing:** the commit must already exist locally AND the human must
>   approve the push. Approval to *commit* is not automatically approval to
>   *push*.
> - **Release assets** (model weights, binaries) uploaded to an existing release
>   are artifacts, not source code; but if a release also touches or ships
>   source, treat the whole release as a source push and get approval first.

---

## Table of Contents

- [1. Mandatory Human-Approval Gate](#1-mandatory-human-approval-gate)
- [2. Commit Messages](#2-commit-messages)
- [3. GitHub Actions](#3-github-actions)
- [4. Release Pushes](#4-release-pushes)
- [5. Updating or Fixing an Existing Release](#5-updating-or-fixing-an-existing-release)
- [6. Checklist](#6-checklist)

---

## 1. Mandatory Human-Approval Gate

The single most important rule in this guide, stated once more and unambiguously:

> **AI agents must never push source code without explicit human approval.**

Follow this sequence on every change:

1. **Write** the change locally (edits in the working tree).
2. **Present** the diff summary + proposed commit message to the human.
3. **Ask** for explicit approval (use the `question` tool). Do not proceed on a
   default or implied yes.
4. **Commit only after approval.**
5. **Ask again before pushing** to a remote (a new explicit approval for the
   push). Never fold "commit" and "push" approval into one silent action unless
   the human explicitly authorized both.
6. Only after that push (and only if the human asked) create tags or releases.

Rationale: a push is a public, near-irreversible action on shared state. Human
oversight at commit time is not enough — the push itself must be authorized.

## 2. Commit Messages

### 2.1 Use Conventional Commits
Format: `type(scope): subject`

- **type**: `feat` (feature), `fix` (bug fix), `chore` (maintenance),
  `docs` (documentation), `refactor`, `test`, `perf`, `ci`, `build`, `revert`.
- **scope** (optional): the affected area, e.g. `<feature>`, `train_<feature>`,
  `dataloader`. Use the same scope style as the rest of the repo.
- **subject**: imperative, present tense, lowercase unless it is a proper noun.

Examples:
- `fix(<feature>): apply finetune mode so the last block is actually trained`
- `feat(train_<feature>): add --force-resume to rewind to the best epoch`
- `docs(rules): document mandatory human-approval gate for pushes`

### 2.2 Subject line rules
- Imperative mood: "fix", "add", "update" (not "fixed", "adds", "updating").
- **≤ 72 characters**. If it does not fit, the change is probably too big.
- No trailing period. Do not state "and" too much — split large subjects.
- Capitalize only the first letter and proper nouns.

### 2.3 Body rules
- Blank line after the subject, then a short body that explains **why** and
  **what**, not just *how*.
- Bullet the concrete changes; reference issue/PR numbers when available.
- Note caveats the reviewer must know (e.g. "finetune not yet retrained",
  "SOTA metrics reflect original weights, not a fresh retrain").
- Follow the [5W1H reporting](../rules/RESULTS_REPORTING.md) spirit for any numbers in
  the body: state split, seed, and how a metric was computed.

### 2.4 Companion Markdown Document Rule & Git Trailers
Per [agents/rules/COMMIT_CONVENTION.md](../../agents/rules/COMMIT_CONVENTION.md), every non-trivial commit (Tier 1: refactors, PR merges, multi-file features, bug incident fixes, audits) MUST have a companion Markdown document in `docs/` staged and committed together with the code changes.

Every such commit MUST include a standard Git trailer in the footer:
```text
Companion-Doc: docs/<path_to_document>.md
```
Optional secondary trailers:
- `Report: docs/<path_to_report>.md`
- `Fixes: docs/bugs/BUG_<NN>_<NAME>.md`

For minor single-line chores or typos (Tier 2), cite an existing tracking doc (e.g. `docs/progress/<PHASE>_STATUS.md`) or omit if purely self-describing.

### 2.5 Scope discipline (one logical change per commit)
- A commit should contain **one logical change**. Do not mix an unrelated
  bug fix with a doc update in the same commit.
- Split mixed working trees into separate commits (e.g. fix + results refresh +
  docs), and get approval for each.
- Stage deliberately with explicit paths: `git add <paths>` — avoid blind
  `git add -A` that could sweep unintended files (secrets, generated outputs)
  into the commit.

### 2.6 Avoid shell-quoting pitfalls
Multi-line messages with quotes or em-dashes are easily mangled by PowerShell.
Write the message to a file and commit with `git commit -F <file>`; do not
inline complex messages in `git commit -m "..."`.

### 2.7 Good vs bad
- Good: `fix(<feature>): raise finetune base LR to 1e-3 so head trains`
- Bad: `did stuff`, `update`, `fixed the thing that was broken earlier and also
  changed docs and bumped epochs`

## 3. GitHub Actions

### 3.1 Workflow anatomy
A workflow is `name`, `on` (triggers), `jobs` (each with `runs-on` and `steps`).

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - run: pip install -r requirements.txt ruff
      - run: ruff check src tests
      - run: pytest
```

### 3.2 Triggers
- Run on `push` to important branches and on `pull_request` for pre-merge checks.
- Limit branch lists; a wildcard trigger on every push can waste CI minutes.
- Do not put secrets or long-lived tokens into workflow files.

### 3.3 Pin action versions
- Pin third-party actions to a **full commit SHA** (or a verified tag) to avoid
  supply-chain drift: `uses: actions/checkout@v4` is a tag; prefer a SHA in
  production. Never reference untrusted/unofficial actions.
- Keep the Python/runner versions explicit and reproducible.

### 3.4 Secrets and least privilege
- Use `secrets.*` for tokens; never hardcode or `echo` them.
- Give workflows the **minimum `permissions:`** needed (e.g.
  `contents: read`), and avoid granting `contents: write` or broad scopes
  unless the job genuinely needs them.
- Never upload secrets as build artifacts or release assets.

### 3.5 CI runs lint and tests
- Enforce the project lint config ([pyproject.toml](../../pyproject.toml)) and
  the test suite. Fail the job on violations.
- Keep CI deterministic and fast: cache dependencies, run data-independent
  tests (skip when `data/raw` is absent, see
  [tests/conftest.py](../../tests/conftest.py)).

### 3.6 References
The project's CI lives in
[.github/workflows/ci.yml](../../.github/workflows/ci.yml) (lint + pytest on
push/PR). Extend it, do not duplicate it.

## 4. Release Pushes

### 4.1 Versioning and tags
- Use **Semantic Versioning**: `vMAJOR.MINOR.PATCH` (e.g. `v1.0.0`, `v1.1.0`).
- Use **annotated tags** so the tag carries a message and author:
  `git tag -a v1.0.0 -m "..."`.
- A tag must point at a commit that already exists on the remote. If a release
  API rejects `target_commitish`, the commit is not on the remote — push the
  branch (with approval) first, or push the tag.

### 4.2 Release assets vs git
- **Never commit large binaries to git.** Model weights, feature caches, and
  logs belong in release assets or git-lfs, not in the source tree.
  (See [LOGGING_CHECKPOINT_RULES.md](../rules/LOGGING_CHECKPOINT_RULES.md) and the
  artifact-storage policy in [.gitignore](../../.gitignore).)
- Publish checkpoints/weights as **release assets**; add a table in the release
  body mapping each asset to its metric.

### 4.3 Draft and pre-release flow
- Create **draft** releases while assembling; flip to published once verified.
- Use `prerelease: true` for in-progress versions so they are not treated as
  stable.

### 4.4 Creating a release (workflow)
1. (With approval) push the source branch that contains the work.
2. Create and push an annotated tag at the target commit.
3. Create the release for that tag (REST `POST /repos/{owner}/{repo}/releases`
   or `gh release create`), with release notes.
4. Upload large binaries as assets (`POST <upload_url>?name=<file>` with
   `Content-Type: application/octet-stream`).
5. **Every one of these steps that ships source requires human approval**; even
   a pure asset upload to an existing release is best confirmed with the human.

### 4.5 Assets are artifacts, not source
Uploading a model-weight `.pt` to an existing release is not a source-code
push. However, if you are unsure whether an action touches source (tag moves,
release rebuilds, branch pushes), get approval — ambiguity is not an exception.

## 5. Updating or Fixing an Existing Release

Releases are mutable via the API, but any change must be deliberate and, when it
touches source, human-approved.

### 5.1 Edit release notes
`PATCH /repos/{owner}/{repo}/releases/{release_id}` updates `name`, `body`, etc.
Keep the notes accurate; correct stale numbers or add missing context.

### 5.2 Add or replace assets
- **Add**: `POST <upload_url>?name=<file>`.
- **Replace**: GitHub does not overwrite assets — a same-name upload returns
  HTTP 422. To replace, `DELETE` the old asset, then upload the new one.
- **Delete**: `DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}`.
- Verify after each operation by listing the release assets.

### 5.3 Delete a release and its tag
To fully retract: delete the release, then delete the tag ref
(`DELETE /repos/{owner}/{repo}/git/refs/tags/{tag}` and/or
`git push origin :<tag>`). This is destructive — get explicit approval.

### 5.4 ⚠️ Approval still applies
> Even when only fixing or updating an existing release — editing notes,
> replacing an asset, or deleting a tag — **the AI agent must NOT push source
> code without human authorization.** If the update involves any source change
> (rebuilding a checkpoint, amending a commit, moving a tag onto new source),
> stop and obtain explicit human approval before pushing anything.

## 6. Checklist

- [ ] Proposed commit message + file list shown to the human before committing.
- [ ] Explicit human approval obtained **before every source push** (commit and
      push are separate approvals).
- [ ] Commit is a single logical change with a Conventional-Commits subject ≤ 72 chars.
- [ ] No secrets or large binaries committed to git.
- [ ] CI workflow pins versions, uses least-privilege `permissions`, and never
      logs secrets.
- [ ] Release uses an annotated SemVer tag pointing at a remote-visible commit.
- [ ] Updating/fixing a release still required human approval for any source push.

