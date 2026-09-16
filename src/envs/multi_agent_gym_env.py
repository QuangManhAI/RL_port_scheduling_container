#!/usr/bin/env python3
"""Gymnasium environment wrapper for Multi-Agent RL Training Scene (2 AMRs, 4 Boxes)."""

from __future__ import annotations

import time
from typing import Any, Dict, Optional, Tuple

import numpy as np

try:
    import gymnasium as gym
    from gymnasium import spaces
except ImportError:
    import gym  # type: ignore
    from gym import spaces  # type: ignore

from src.envs.godot_gym_env import GodotGymEnv


class MultiAgentGymEnv(GodotGymEnv):
    """Gymnasium environment for 2 AMRs picking and delivering 4 ToteBoxes."""

    def __init__(
        self,
        port: int = 11050,
        ticks_per_step: int = 4,
        headless: bool = False,
        autostart: bool = True,
        fps: float = 60.0,
    ) -> None:
        self.fps = fps
        super().__init__(
            scene_path="res://scenes/training/training_multi_agent.tscn",
            port=port,
            ticks_per_step=ticks_per_step,
            headless=headless,
            autostart=autostart,
        )

        # Action space: 6 continuous controls
        # [v1, w1, trig1, v2, w2, trig2]
        self.action_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(6,),
            dtype=np.float32,
        )

        # Observation space: 26 dimensions (13 dims per AMR, S5-compatible)
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(26,),
            dtype=np.float32,
        )

    def step(self, action: np.ndarray) -> Tuple[np.ndarray, float, bool, bool, Dict[str, Any]]:
        obs, reward, terminated, truncated, info = super().step(action)
        if not self.headless and self.fps > 0:
            time.sleep(1.0 / max(1.0, self.fps))
        return obs, reward, terminated, truncated, info
