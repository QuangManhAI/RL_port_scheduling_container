#!/usr/bin/env python3
"""Utility for loading and accessing configs/config.yaml."""

from __future__ import annotations

import os
from typing import Any, Dict

import yaml

_CONFIG_CACHE: Dict[str, Any] | None = None
_DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "configs",
    "config.yaml",
)


def load_config(config_path: str = _DEFAULT_CONFIG_PATH) -> Dict[str, Any]:
    """Loads configuration dictionary from YAML file."""
    global _CONFIG_CACHE
    if not os.path.isfile(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        _CONFIG_CACHE = yaml.safe_load(f) or {}

    return _CONFIG_CACHE


def get_config() -> Dict[str, Any]:
    """Returns cached configuration dictionary, loading if necessary."""
    global _CONFIG_CACHE
    if _CONFIG_CACHE is None:
        return load_config()
    return _CONFIG_CACHE


def get_clock_config() -> Dict[str, Any]:
    """Returns dual-clock simulation parameters."""
    return get_config().get("clock", {})


def get_amr_config() -> Dict[str, Any]:
    """Returns AMR robot parameters and docking thresholds."""
    return get_config().get("amr", {})


def get_rack_config() -> Dict[str, Any]:
    """Returns rack dimensions, tier heights, and arm reach limits."""
    return get_config().get("rack", {})


def get_training_config() -> Dict[str, Any]:
    """Returns PPO training hyperparameters."""
    return get_config().get("training", {})


def get_paths_config() -> Dict[str, Any]:
    """Returns paths for models and logs."""
    return get_config().get("paths", {})


if __name__ == "__main__":
    cfg = get_config()
    print("Successfully loaded config.yaml:")
    import pprint
    pprint.pprint(cfg)
