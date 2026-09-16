#!/usr/bin/env python3
"""Automated tests for Godot 4 RL training bridge, gymnasium wrappers, and stage scenes."""

import os
import sys
import time
import numpy as np
try:
    import pytest
except ImportError:
    pytest = None

# Add project root to sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.envs.godot_env_bridge import GodotEnvBridge, find_godot_binary
from src.envs.navigate_to_item_env import NavigateToItemEnv
from src.envs.pickup_env import PickupEnv
from src.envs.navigate_carrying_env import NavigateCarryingEnv
from src.envs.dropoff_env import DropoffEnv
from src.envs.chained_cycle_env import ChainedCycleEnv
from src.training.terminal_state_buffer import TerminalStateBuffer


def test_godot_binary_found():
    """Verify that Godot 4 binary is detected properly."""
    binary_path = find_godot_binary()
    assert os.path.isfile(binary_path), f"Godot binary does not exist at {binary_path}"


def test_godot_tcp_bridge_connect_and_roundtrip():
    """Test low-level GodotEnvBridge lifecycle, reset, and step roundtrips."""
    bridge = GodotEnvBridge(
        scene_path="res://scenes/training/training_navigate_to_item.tscn",
        port=11099,
        headless=True,
        ticks_per_step=4,
        autostart=True,
    )
    try:
        # 1. Reset
        obs, info = bridge.reset(seed=42, difficulty=0.0)
        assert len(obs) == 13, f"Expected 13 observation floats, got {len(obs)}"
        assert isinstance(info, dict)

        # 2. Sequential steps with latency measurement
        latencies = []
        for _ in range(10):
            t0 = time.perf_counter()
            action = [0.5, 0.1, 0.0]
            next_obs, reward, terminated, truncated, step_info = bridge.step(action)
            latencies.append(time.perf_counter() - t0)

            assert len(next_obs) == 13
            assert isinstance(reward, float)
            assert isinstance(terminated, bool)
            assert isinstance(truncated, bool)

        avg_latency_ms = (sum(latencies) / len(latencies)) * 1000.0
        print(f"\n[BENCHMARK] Average step roundtrip latency: {avg_latency_ms:.2f} ms")
        assert avg_latency_ms < 50.0, f"Step latency too high: {avg_latency_ms:.2f} ms"

    finally:
        bridge.close()


def test_gym_env_spaces_and_step():
    """Test Gymnasium API conformance on NavigateToItemEnv."""
    env = NavigateToItemEnv(port=11098, headless=True)
    try:
        assert env.observation_space.shape == (13,)
        assert env.action_space.shape == (3,)

        obs, info = env.reset(seed=123)
        assert isinstance(obs, np.ndarray)
        assert obs.shape == (13,)
        assert env.observation_space.contains(obs)

        action = env.action_space.sample()
        next_obs, reward, terminated, truncated, step_info = env.step(action)
        assert isinstance(next_obs, np.ndarray)
        assert next_obs.shape == (13,)
        assert isinstance(reward, float)
        assert isinstance(terminated, bool)
        assert isinstance(truncated, bool)
    finally:
        env.close()


def test_terminal_state_buffer(tmp_path):
    """Test recording and sampling terminal states."""
    buffer = TerminalStateBuffer(log_dir=str(tmp_path))
    buffer.record_terminal_state("s1", [1.2, 3.4, 0.5], {"reward": 1.0})
    buffer.record_terminal_state("s1", [-0.8, 2.1, -1.2], {"reward": 0.5})

    poses = buffer.load_states("s1")
    assert len(poses) == 2
    assert poses[0] == [1.2, 3.4, 0.5]

    sample = buffer.sample_pose("s1")
    assert sample in poses


if __name__ == "__main__":
    print("[RUNNING] test_godot_binary_found...")
    test_godot_binary_found()
    print("✔ test_godot_binary_found passed.")

    print("\n[RUNNING] test_godot_tcp_bridge_connect_and_roundtrip...")
    test_godot_tcp_bridge_connect_and_roundtrip()
    print("✔ test_godot_tcp_bridge_connect_and_roundtrip passed.")

    print("\n[RUNNING] test_gym_env_spaces_and_step...")
    test_gym_env_spaces_and_step()
    print("✔ test_gym_env_spaces_and_step passed.")

    print("\n[RUNNING] test_terminal_state_buffer...")
    import tempfile
    with tempfile.TemporaryDirectory() as tmp_dir:
        test_terminal_state_buffer(tmp_dir)
    print("✔ test_terminal_state_buffer passed.")

    print("\n[ALL PYTHON BRIDGE TESTS PASSED] 100% operational!")
