# <TITLE> — Bug Report Template

- **Motivation/Background**: Runtime failures, environment incompatibilities, and logic bugs must be documented with actionable root-cause analysis and verification evidence.
- **Purpose**: Provide a structured template for capturing bug symptoms, root causes, remediations, and verification tests.
- **Overview Pipeline**: Copy this skeleton into `docs/bugs/BUG_<NN>_<SHORT_NAME>.md` when diagnosing any non-trivial issue.
- **Detailed Plan**: §1 Symptom & Traceback; §2 Root Cause Analysis; §3 Solution & Code Changes; §4 Verification Evidence; §5 Related Links.
- **References**: `agents/rules/MD_CONVENTION.md`.
- **Created**: YYYY-MM-DDTHH:MM:SS±HH:MM
- **Last Updated**: YYYY-MM-DDTHH:MM:SS±HH:MM

---

## Metadata

- **Bug ID**: `BUG-<NN>`
- **Title**: <Short bug title, e.g. "DataLoader BrokenPipeError on Windows">
- **Status**: [Open | In Progress | Resolved | Won't Fix]
- **Severity**: [Low | Medium | High | Critical]
- **Category**: [Environment | Data | Architecture | Training | Evaluation | CI/CD]
- **Target Component**: [`src/...`](...)

---

## 1. Symptom & Error Traceback

<Describe what happened, the command run, and paste the exact traceback or error output.>

```text
<paste full traceback here>
```

---

## 2. Root Cause Analysis

<Detailed explanation of why the failure occurred. Cite specific file lines and environmental conditions.>

1. Cause item 1
2. Cause item 2

---

## 3. Solution & Remediation

<Explain the architectural or code changes made to fix the issue. Include code diffs or links to modified files.>

- Modified [`src/...`](...) to handle ...

---

## 4. Verification Evidence

<Command executed to verify the fix and its output.>

```bash
pytest tests/test_<module>.py -v
```

**Output:**
```text
<paste passing test log here>
```

---

## 5. Related Links

- Bug Directory Index: [`docs/bugs/README.md`](README.md)
- Related Modules: [`src/...`](...)
