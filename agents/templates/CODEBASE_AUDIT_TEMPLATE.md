# Codebase Audit Report — <Project or Branch Name>

- **Motivation/Background**: Why this audit exists — e.g. a major release, branch merge, security review, or post-mortem. 1–3 sentences.
- **Purpose**: One sentence — what this report establishes (baseline of code quality, security, deps, architecture, tests, performance for <branch>).
- **Overview Pipeline**: 1–2 sentences — the audit process: git-tree inspection, static grep of `src/`/`tests`/`notebooks`, dependency matrix vs active environment, compliance check against the project rulebase.
- **Detailed Plan**: sections covered — Executive Summary, Findings Summary, per-area findings (code quality, security, dependencies, architecture, tests, performance), Compliance, Risk Analysis, Overall Health, Prioritized Action Plan.
- **References**: `git`, `grep`, `pip`/`importlib.metadata`, project rulebase (`agents/rules/`), previous audit.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

> **AI-era audit perspective (read first):** In an Agent-AI-driven codebase,
> strict lint / style / naming conformance is a **low-priority** signal — most
> code is read and maintained by AI, which tolerates stylistic variance. Focus
> findings on what actually matters: **correctness, reproducibility, security,
> and runtime behavior**. Lint-only items (whitespace, import order, line
> length, unused-import nits) are informational at most and must never block a
> release. If a lint gate exists (e.g. ruff), treat it as a hygiene helper for
> humans, not as an audit acceptance criterion.

---

## Table of Contents

- [1. Executive Summary](#1-executive-summary)
- [2. Findings Summary](#2-findings-summary)
- [3. Code Quality](#3-code-quality)
- [4. Security Vulnerabilities](#4-security-vulnerabilities)
- [5. Dependency Health](#5-dependency-health)
- [6. Architecture Consistency](#6-architecture-consistency)
- [7. Test Coverage](#7-test-coverage)
- [8. Performance Bottlenecks](#8-performance-bottlenecks)
- [9. Compliance with Policies and Procedures](#9-compliance-with-policies-and-procedures)
- [10. Detailed Risk Analysis](#10-detailed-risk-analysis)
- [11. Overall Project Health](#11-overall-project-health)
- [12. Prioritized Action Plan](#12-prioritized-action-plan)

---

## 1. Executive Summary

> **Scope:** branch/revision audited, date, method (1–2 sentences).

Brief verdict: what is strong (≤3 bullets) and what blocks maturity (≤3 bullets), plus the one-line health rating. Links: overall rating in [§11](#11-overall-project-health), top actions in [§12](#12-prioritized-action-plan).

---

## 2. Findings Summary

> ### Finding Resolution Status Vocabulary
> The **Status** column tracks whether **that specific finding/defect** has been remediated, independent of whether the broader audit or milestone is complete:
> - **`RESOLVED`**: The specific defect/risk has been completely remediated, validated by automated tests or physical inspection, and verified on disk.
> - **`PARTIALLY RESOLVED`**: An interim mitigation, partial patch, or workaround has been applied, but remaining work or pending verification is required for complete resolution.
> - **`NOT RESOLVED`**: The finding has been diagnosed and documented, but no corrective engineering action has yet been taken.

| ID | Area | Severity | Status | Title | Section |
|---|---|---|---|---|---|
| `<ID>-1` | Code quality | **High** | `NOT RESOLVED` | <short title> | [3. Code Quality](#3-code-quality) |
| `<ID>-2` | Security | **Medium** | `PARTIALLY RESOLVED` | <short title> | [4. Security Vulnerabilities](#4-security-vulnerabilities) |
| `<ID>-3` | Dependencies | **Low** | `RESOLVED` | <short title> | [5. Dependency Health](#5-dependency-health) |
| ... | ... | ... | ... | ... | ... |

Cross-reference: severity totals by area → [risk analysis §10](#10-detailed-risk-analysis) and [compliance §9](#9-compliance-with-policies-and-procedures).

---

## 3. Code Quality

> **Scoring guidance:** per the AI-era perspective above, treat pure lint/style
> issues as **Info** (or omit them). Reserve Medium+ for duplication with real
> drift risk, dead code that breaks behavior, or maintainability that blocks
> correctness/reproducibility.

### `<ID>-1`: <Short title>
- **Severity:** [Critical | High | Medium | Low | Info]
- **Status:** [RESOLVED | PARTIALLY RESOLVED | NOT RESOLVED]
- **Description:** <what the issue is and why it matters>
- **Affected:** <file(s) / component(s)>
- **Remediation:** <concrete fix> — tracked in [Action P1.x](#12-prioritized-action-plan)
- **Resolution Evidence:** <if RESOLVED/PARTIALLY RESOLVED: commit hash, test run, or verification diff>


> Repeat for each finding. Positive findings use severity `Info`.

---

## 4. Security Vulnerabilities

### `<ID>-2`: <Short title>
- **Severity:** ...
- **Status:** [RESOLVED | PARTIALLY RESOLVED | NOT RESOLVED]
- **Description:** ...
- **Affected:** ...
- **Remediation:** ... — tracked in [Action P0.x](#12-prioritized-action-plan)
- **Resolution Evidence:** ...

---

## 5. Dependency Health

### `<ID>-3`: <Short title>
- **Severity:** ...
- **Status:** [RESOLVED | PARTIALLY RESOLVED | NOT RESOLVED]
- **Description:** ...
- **Affected:** ...
- **Remediation:** ... — tracked in [Action P0.x](#12-prioritized-action-plan)
- **Resolution Evidence:** ...

---

## 6. Architecture Consistency

### `<ID>-4`: <Short title>
- **Severity:** ...
- **Status:** [RESOLVED | PARTIALLY RESOLVED | NOT RESOLVED]
- **Description:** ...
- **Affected:** ...
- **Remediation:** ... — tracked in [Action P1.x](#12-prioritized-action-plan)
- **Resolution Evidence:** ...

---

## 7. Test Coverage

### `<ID>-5`: <Short title>
- **Severity:** ...
- **Status:** [RESOLVED | PARTIALLY RESOLVED | NOT RESOLVED]
- **Description:** ...
- **Affected:** ...
- **Remediation:** ... — tracked in [Action P0.x](#12-prioritized-action-plan)
- **Resolution Evidence:** ...

---

## 8. Performance Bottlenecks

### `<ID>-6`: <Short title>
- **Severity:** ...
- **Status:** [RESOLVED | PARTIALLY RESOLVED | NOT RESOLVED]
- **Description:** ...
- **Affected:** ...
- **Remediation:** ... — tracked in [Action P1.x](#12-prioritized-action-plan)
- **Resolution Evidence:** ...

---


## 9. Compliance with Policies and Procedures

Assessed against the project rulebase (`agents/rules/*`, `Docs/Rulebase.md`).

| Policy / procedure | Compliance | Evidence / gap | Related finding |
|---|---|---|---|
| <Rulebase §N — name> | [Compliant \| Partial \| Non-compliant] | <evidence> | [<ID>-x](#2-findings-summary) |

Cross-reference: non-compliance items map to [risk §10](#10-detailed-risk-analysis) and [action §12](#12-prioritized-action-plan).

---

## 10. Detailed Risk Analysis

| Risk | Likelihood | Impact | Overall | Description & mitigation | Related finding |
|---|---|---|---|---|---|
| <risk> | [Low \| Med \| High] | [Low \| Med \| High] | **Moderate** | <narrative> | [<ID>-x](#2-findings-summary) |

Cross-reference: severity ratings originate in [§2](#2-findings-summary); mitigations are scheduled in [§12](#12-prioritized-action-plan).

---

## 11. Overall Project Health

| Dimension | Rating | Notes |
|---|---|---|
| <Dimension> | [Strong \| Good \| Fair \| Weak \| None] | <1-line note> |

Cross-reference: per-dimension evidence in [§3](#3-code-quality)–[§8](#8-performance-bottlenecks).

---

## 12. Prioritized Action Plan

### P0 — Fix now (blocks trust / reproducibility / security)
- **P0.1** <action> — addresses [<ID>-x](#2-findings-summary)
- **P0.2** ...

### P1 — Next iteration (raises confidence)
- **P1.1** <action> — addresses [<ID>-x](#2-findings-summary)

### P2 — Polish (when time permits)
- **P2.1** <action> — addresses [<ID>-x](#2-findings-summary)

> Lint/tooling actions (ruff, mypy, CI niceties) belong here at most — per the
> AI-era perspective, they are hygiene for humans, never blocking criteria.

Cross-reference: each item links back to its finding; the summary table is in [§2](#2-findings-summary).

---

## Self-review checklist (before finalizing)

- [ ] All 5 header fields present
- [ ] TOC anchors resolve (lowercase, strip punctuation, spaces → hyphens)
- [ ] Cross-reference links between related sections resolve (summary ↔ detail ↔ action plan)
- [ ] Metrics match source; file/notebook paths relative to project root
- [ ] Dates in `YYYY-MM-DD`; `---` separators between major sections
