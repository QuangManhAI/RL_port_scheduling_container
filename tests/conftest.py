"""Pytest fixtures: skip data-dependent tests when data/raw is absent.

Allows CI (and fresh checkouts) to run the synthetic unit suite without the
dataset present.
"""
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_RAW = PROJECT_ROOT / "data" / "raw"

needs_data = pytest.mark.skipif(
    not DATA_RAW.exists() or not any(DATA_RAW.iterdir()),
    reason="data/raw is absent — data-dependent test skipped",
)
