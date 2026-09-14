"""Smoke tests: verify the project skeleton imports and the layout is intact.

These pass out of the box right after bootstrapping — they are the first
line of defense that a fresh checkout is wired correctly.
"""
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def test_src_packages_importable():
    import src.data  # noqa: F401
    import src.eval  # noqa: F401
    import src.experiments  # noqa: F401
    import src.models  # noqa: F401
    import src.training  # noqa: F401
    import src.utils  # noqa: F401


def test_core_directories_exist():
    for rel in (
        "agents/rules",
        "agents/templates",
        "configs",
        "data/raw",
        "data/processed",
        "data/external",
        "docs/phases",
        "docs/progress",
        "docs/experiments",
        "docs/bugs",
        "docs/references",
        "docs/shared",
        "notebooks",
        "experiments/runs",
        "experiments/results",
        "experiments/plots",
        "experiments/checkpoints",
        "requirements",
        "tests",
    ):
        assert (PROJECT_ROOT / rel).is_dir(), f"missing directory: {rel}"


def test_constitutional_agents_isolation():
    """Assert agents/ strictly contains rules, templates, and README.md with no mutable project files."""
    agents_dir = PROJECT_ROOT / "agents"
    assert (agents_dir / "README.md").is_file()
    assert (agents_dir / "rules").is_dir()
    assert (agents_dir / "templates").is_dir()

    # Forbidden mutable directories inside agents/
    forbidden_dirs = ("phases", "progress", "experiments", "bugs", "references")
    for d in forbidden_dirs:
        assert not (agents_dir / d).exists(), f"mutable directory '{d}' must not exist in agents/"

    # Forbidden mutable root docs inside agents/
    forbidden_files = ("PURPOSE.md", "OVERVIEW.md", "HOW_TO_SETUP_AI_AGENT.md", "ML_PIPELINE_REFERENCE_v3.md")
    for f in forbidden_files:
        assert not (agents_dir / f).exists(), f"mutable file '{f}' must be under docs/, not agents/"


def test_documentation_files_exist():
    for rel in (
        "agents/README.md",
        "docs/README.md",
        "docs/PURPOSE.md",
        "docs/OVERVIEW.md",
        "docs/shared/HOW_TO_SETUP_AI_AGENT.md",
        "docs/shared/HANDOFF_TEMPLATE.md",
        "agents/rules/FOLDER_STRUCTURE.md",
        "agents/rules/LOGGING_CHECKPOINT_RULES.md",
        "agents/rules/RESULTS_REPORTING.md",
        "agents/rules/CODEBASE_AUDIT.md",
        "agents/rules/NAMING_CONVENTION.md",
        "agents/rules/MD_CONVENTION.md",
        "agents/rules/PYTORCH_FRAMEWORK_RULES.md",
        "agents/templates/SMOKE_TEST_CHECKLIST.md",
        "agents/templates/PROJECT_ROADMAP_TEMPLATE.md",
        "agents/templates/PHASE_DOC_TEMPLATE.md",
        "agents/templates/PROGRESS_STATUS_TEMPLATE.md",
        "agents/templates/EXPERIMENT_TEMPLATE.md",
        "agents/templates/BUG_TEMPLATE.md",
        "agents/templates/REFERENCE_TEMPLATE.md",
        "requirements/base.txt",
        "requirements/dev.txt",
        "requirements.txt",
        "pyproject.toml",
    ):
        assert (PROJECT_ROOT / rel).is_file(), f"missing file: {rel}"
