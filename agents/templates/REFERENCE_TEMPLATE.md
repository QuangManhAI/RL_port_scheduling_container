# [Reference Title] — Reference Guide Template

| Field | Value |
| :--- | :--- |
| **Document Type** | Reference Guide Template |
| **Status** | Active Template |
| **Owner** | AI Agent & Engineering Team |
| **Scope** | Global Repository / Reusable Knowledge |
| **Created** | 2026-09-06T21:05:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/references/README.md](../../docs/references/README.md) |

---

## 1. Context & Purpose

Document reusable architectural guides, external API quirks, tool configurations, dataset formats, or operational recipes here. When instantiated, save as `docs/references/<NAME>.md`.

- **Primary Purpose:** [Why does this reference exist and what problem or misunderstanding does it prevent?]
- **Target Audience:** [AI agents, human practitioners, or both]
- **Relevant Project Scope:** [Specific phases, models, or global project lifecycle]

---

## 2. Core Concepts & Architectural Rules

[Detail the core facts, architectural assumptions, invariants, and guidelines.]

---

## 3. Practical Implementation & Code Snippets

```python
# Provide concrete, production-grade snippets or CLI commands
```

---

## 4. Known Pitfalls & Edge Cases

| Anti-Pattern / Pitfall | Expected Failure | Correct Handling |
| :--- | :--- | :--- |
| [e.g., Unpinned dependency] | Silent build failure | Explicit pinning in requirements/base.txt |
| [e.g., Implicit CUDA assumptions] | Test crash on CPU CI | Conditional device detection (`get_device()`) |

---

## 5. Related Documentation

- Master References Index: [docs/references/README.md](../../docs/references/README.md)
- Constitutional Rules: [agents/rules/FOLDER_STRUCTURE.md](../rules/FOLDER_STRUCTURE.md)
