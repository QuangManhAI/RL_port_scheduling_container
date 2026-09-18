#!/usr/bin/env python3
"""Integration tests for Phase 08 Fleet Aisle Godot Environment over TCP Bridge."""

import os
import sys
import numpy as np
import pytest

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.envs.fleet.fleet_mappo_gym_env import FleetMappoGymEnv


def test_fleet_aisle_env_lifecycle():
    port = 11350
    env = FleetMappoGymEnv(
        port=port,
        num_agents=2,
        headless=True,
        autostart=True,
    )

    try:
        # Reset check
        obs, info = env.reset(seed=42)
        assert isinstance(obs, np.ndarray), "Obs must be numpy array"
        assert obs.shape == (2, 37), f"Expected (2, 37) observation shape, got {obs.shape}"
        assert "global_state" in info, "Global state must be present in info dictionary"

        # Step check with zero actions
        zero_actions = np.zeros((2, 2), dtype=np.float32)
        next_obs, rewards, terminated, truncated, next_info = env.step(zero_actions)

        assert next_obs.shape == (2, 37), f"Next obs shape must be (2, 37), got {next_obs.shape}"
        assert rewards.shape == (2,), f"Rewards shape must be (2,), got {rewards.shape}"
        assert not terminated, "Initial step should not be terminated"
        assert not truncated, "Initial step should not be truncated"

        # Step check with forward motion actions
        drive_actions = np.array([[0.5, 0.0], [-0.5, 0.0]], dtype=np.float32)
        next_obs, rewards, terminated, truncated, next_info = env.step(drive_actions)
        assert next_obs.shape == (2, 37)

    finally:
        env.close()
