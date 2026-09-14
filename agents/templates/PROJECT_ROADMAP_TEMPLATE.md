# Project Roadmap Template

- **Motivation/Background**: A single, living roadmap keeps any project's milestones,
  phases, dependencies, resources, and timeline visible in one place. This template is
  generic and reusable across project types (software, data/AI, product, research).
- **Purpose**: A copy-and-adapt Markdown skeleton with tables/outlines for every roadmap
  section plus brief instructions on how to populate each one effectively.
- **Overview Pipeline**: Copy the file → fill the Overview → keep the milestones, phases,
  tasks, dependencies, resources, and timeline updated as the project progresses.
- **Detailed Plan**: (0) at-a-glance summary; (1) how to use; (2) project overview;
  (3) key milestones; (4) major phases; (5) task breakdown; (6) task dependencies;
  (7) resource allocation; (8) estimated timeline; (9) risks & mitigations;
  (10) maintenance.
- **References**: Markdown (GitHub-flavoured tables/checklists), `agents/rules/MD_CONVENTION.md`.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

## Table of Contents

- [At a Glance](#at-a-glance)
1. [How to Use This Template](#1-how-to-use-this-template)
2. [Project Overview](#2-project-overview)
3. [Key Milestones](#3-key-milestones)
4. [Major Phases](#4-major-phases)
5. [Task Breakdown](#5-task-breakdown)
6. [Task Dependencies](#6-task-dependencies)
7. [Resource Allocation](#7-resource-allocation)
8. [Estimated Timeline](#8-estimated-timeline)
9. [Risks & Mitigations](#9-risks--mitigations)
10. [Maintenance & Status](#10-maintenance--status)

---

## At a Glance

> **How to populate:** the "elevator view" — a reader should grasp the whole
> project flow in under 30 seconds without reading the detailed sections. Keep
> one line per phase, reuse the phase names and order from
> [§4 Major Phases](#4-major-phases), and mark each with the
> [§1](#1-how-to-use-this-template) status legend. Update the progress bar and
> count whenever you tick a phase in §4.

**Progress: `<N> / <M>` phases complete** — `<one-line summary of what is delivered so far>`.

```
██████░░░░░░░░░░   <N/M> (<pct>%)     █ = done, ░ = remaining
```

1. **`<Phase 1 name>`** — `<short description>` — `[X]` — [<PHASE>.md](#)
2. **`<Phase 2 name>`** — `<short description>` — `[ ]` — [<PHASE>.md](#)
3. **`<Phase 3 name>`** — `<short description>` — `[ ]` — [<PHASE>.md](#)
...

> Status legend: `[X]` done · `[ ]` not started · `[~]` in progress · `[!]` blocked
> (see [§1 How to Use This Template](#1-how-to-use-this-template)).

**Next:** `<the next unstarted phase or task>`.

---

## 1. How to Use This Template

- **Copy** this file (e.g. `project_roadmap.md` at your project root or in `docs/`).
- Replace every `[Fill in]` placeholder with your project's data.
- Use the **status legend** everywhere:
  - `[ ]` = not started, `[~]` = in progress, `[X]` = done, `[!]` = blocked/on hold.
  - Effort units: **d** = person-days, **w** = person-weeks.
- **Update the date stamp** in §10 every time you touch it, and keep a short "last
  updated" line near the top.
- Add/remove rows freely — the tables are templates, not a fixed schema.

---

## 2. Project Overview

> **How to populate:** one or two sentences per field. Be specific about the success
> criterion — how will you *know* the project succeeded? Revisit this section when scope
> changes.

| Field | Value |
|---|---|
| Project name | `[Fill in]` |
| Problem / motivation | `[Fill in — why this project exists]` |
| Goal (1 sentence) | `[Fill in — what it achieves]` |
| Success criteria | `[Fill in — measurable definition of done, e.g. metric ≥ X]` |
| Non-goals (out of scope) | `[Fill in — what it explicitly will NOT do]` |
| Sponsor / product owner | `[Fill in]` |
| Start date | `[YYYY-MM-DD]` |
| Target end date | `[YYYY-MM-DD]` |
| Key constraints | `[e.g. budget, privacy, latency, local-only, headcount]` |

---

## 3. Key Milestones

> **How to populate:** a milestone is a *point in time* with an externally verifiable
> deliverable — not a phase. One row per milestone. "Deliverable / definition of done"
> should be something an outsider can confirm (a demo, a release, a report, a passing test).
> Dates are `YYYY-MM-DD`.

| Milestone | Target date | Deliverable / definition of done | Status | Owner |
|---|---|---|---|---|
| `[e.g. M1 — Project kickoff]` | `[date]` | `[stakeholders aligned, charter signed]` | `[ ]` | `[name]` |
| `[M2 — Prototype]` | `[date]` | `[working demo on real data]` | `[ ]` | `[name]` |
| `[M3 — ...]` | `[date]` | `[...]` | `[ ]` | `[name]` |

---

## 4. Major Phases

> **How to populate:** phases are *sequential or parallel blocks of work*, each producing
> an output consumed by the next. Order them top-to-bottom by workflow. If two phases run in
> parallel, note it in "Depends on".

| Phase | Description | Input (from) | Output (feeds) | Status |
|---|---|---|---|---|
| `[Phase 1 — ...]` | `[what happens]` | `[raw data / prior phase]` | `[artifact used downstream]` | `[ ]` |
| `[Phase 2 — ...]` | `[what happens]` | `[Phase 1 output]` | `[artifact used downstream]` | `[ ]` |
| `[Phase 3 — ...]` | `[what happens]` | `[...]` | `[...]` | `[ ]` |

---

## 5. Task Breakdown

> **How to populate:** the most granular level. One row per unit of work. Give each task a
> **unique ID** (e.g. `T1`, `T2`) so dependencies (§6) and resources (§7) can reference it.
> Effort is a best-effort estimate; revisit after each phase.
> Priority: **P0** (blocker/critical), **P1** (high), **P2** (medium), **P3** (nice-to-have).

| Task ID | Phase | Description | Owner / role | Effort | Dependencies | Priority | Status |
|---|---|---|---|---|---|---|---|
| `T1` | `[Phase 1]` | `[what + acceptance]` | `[name/role]` | `[5d]` | `—` | `P0` | `[ ]` |
| `T2` | `[Phase 1]` | `[...]` | `[name/role]` | `[3d]` | `T1` | `P1` | `[ ]` |
| `T3` | `[Phase 2]` | `[...]` | `[name/role]` | `[2w]` | `T2` | `P0` | `[ ]` |

---

## 6. Task Dependencies

> **How to populate:** list every dependency that must be *finished before another task can
> start*. This is what makes the timeline (§8) realistic. For each edge, say which task
> waits on which, and why. Keep it to the meaningful links, not every trivial one.

| Wait | Depends on | Reason |
|---|---|---|
| `T2` | `T1` | `[e.g. T1 produces the schema T2 reads]` |
| `T3` | `T2` | `[e.g. T3 benchmarks the model built in T2]` |
| `T5` | `T2`, `T4` | `[e.g. needs both artifacts]` |

**Critical path hint:** trace the longest chain of dependencies; that chain determines the
minimum project duration. Flag it here: `[e.g. T1 → T2 → T3 is the critical path]`.

---

## 7. Resource Allocation

> **How to populate:** who works on what, when, and at what intensity. "Allocation" is the
> % of a person's time in the relevant period (or a date range). If the project has named
> owners, list them; otherwise list roles. This section exposes over-allocation and skill
> gaps before they block the plan.

| Person / role | Skills | Allocation | Period | Primary tasks |
|---|---|---|---|---|
| `[name]` | `[domain, tools]` | `[50%]` | `[M1–M3]` | `T1, T2` |
| `[name]` | `[domain, tools]` | `[100%]` | `[M2–M5]` | `T3, T4` |
| `[external/outsource]` | `[...]` | `[ad hoc]` | `[...]` | `T5` |

---

## 8. Estimated Timeline

> **How to populate:** two complementary views — a **phase timeline** (start/end/duration)
> and an **ASCII Gantt** for a visual scan. Derive dates from §5–§7 (effort × allocation,
> sequenced by dependencies). Keep the Gantt coarse (phase/week granularity); don't micro-
> manage it.

### 8.1 Phase timeline

| Phase / milestone | Start | End | Duration |
|---|---|---|---|
| `[Phase 1]` | `[date]` | `[date]` | `[2w]` |
| `[M2]` | `[date]` | `[date]` | `—` |
| `[Phase 2]` | `[date]` | `[date]` | `[4w]` |

### 8.2 ASCII Gantt (weeks)

```
Week        1   2   3   4   5   6   7   8
Phase 1     ████
Phase 2         ████ ████
Phase 3                  ████ ████
M3 (demo)                              ◆
```

---

## 9. Risks & Mitigations

> **How to populate:** for each risk, estimate likelihood (L/M/H) and impact (L/M/H) —
> they multiply into a priority (H×H = highest). Name the person who owns the mitigation.
> Update likelihoods as the project progresses; a risk that materialises moves to §5 as a
> task.

| Risk | Likelihood | Impact | Priority | Mitigation | Owner |
|---|---|---|---|---|---|
| `[e.g. key dependency slips]` | `M` | `H` | `High` | `[replan / buffer / fallback]` | `[name]` |
| `[e.g. data unavailable]` | `H` | `H` | `Critical` | `[use proxy dataset]` | `[name]` |

---

## 10. Maintenance & Status

- **Last updated:** `[YYYY-MM-DD]`
- **Update cadence:** `[weekly / per milestone]`
- **Who updates it:** `[owner]`

> **How to populate / keep alive:** at each review, (1) tick off completed milestones/tasks,
> (2) move any new work into §5 with an ID, (3) re-check dependencies and the critical path
> in §6, (4) re-derive the §8 dates, (5) refresh risk likelihoods in §9, (6) bump the date
> here. A roadmap that isn't updated is a fiction — keep it a living document.

---

## Appendix — Copy checklist

- [ ] Overview §2 is specific (success criterion measurable)
- [ ] Every milestone has a verifiable definition of done
- [ ] Every task has a unique ID referenced by §6 and §7
- [ ] The critical path (§6) is identified and reflected in §8 dates
- [ ] No person is over-allocated (§7)
- [ ] Top risks have named owners and mitigations (§9)
- [ ] "Last updated" is current (§10)
