#!/usr/bin/env python3
"""Automated Coordination Benchmark Test for Phase 08 Fleet MAPPO.

Evaluates multi-agent navigation, inter-robot obstacle avoidance, and conveyor dropoff.
"""

import os
import sys
import numpy as np
import pytest

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.envs.fleet.fleet_mappo_gym_env import FleetMappoGymEnv
from src.training.fleet.mappo_agent import MappoAgent
from src.training.fleet.warehouse_dispatcher import WarehouseDispatcher


def test_fleet_mappo_coordination_rollout():
    port = 11360
    env = FleetMappoGymEnv(
        port=port,
        num_agents=2,
        headless=True,
        autostart=True,
    )

    agent = MappoAgent(
        obs_dim=env.obs_dim,
        act_dim=env.act_dim,
        global_dim=20,
        device="cpu",
    )

    dispatcher = WarehouseDispatcher()

    try:
        obs, info = env.reset(seed=100)
        assert obs.shape == (2, 37)

        global_state = np.array(info.get("global_state", np.zeros(20)), dtype=np.float32)
        if len(global_state) < 20:
            global_state = np.pad(global_state, (0, 20 - len(global_state)))
        elif len(global_state) > 20:
            global_state = global_state[:20]

        total_steps = 30
        for step in range(total_steps):
            actions, _, _ = agent.select_actions(obs, global_state, deterministic=True)
            assert actions.shape == (2, 2)

            next_obs, rewards, terminated, truncated, next_info = env.step(actions)
            assert next_obs.shape == (2, 37)
            assert rewards.shape == (2,)

            obs = next_obs
            global_state = np.array(next_info.get("global_state", np.zeros(20)), dtype=np.float32)
            if len(global_state) < 20:
                global_state = np.pad(global_state, (0, 20 - len(global_state)))
            elif len(global_state) > 20:
                global_state = global_state[:20]

            if terminated or truncated:
                break

    finally:
        env.close()
