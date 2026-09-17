#!/usr/bin/env python3
"""Gymnasium environment wrapper for Stage R2: Tier-Aware Fine Positioning & Arm IK Targeting."""

from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

import numpy as np

try:
    import gymnasium as gym
    from gymnasium import spaces
except ImportError:
    import gym  # type: ignore
    from gym import spaces  # type: ignore

from src.envs.godot_env_bridge import GodotEnvBridge
from src.utils.config_loader import get_clock_config


class RackTargetingGymEnv(gym.Env):
    """Gymnasium environment wrapping Godot 4 Stage R2 Rack Targeting scene."""

    metadata = {"render_modes": ["headless"]}

    def __init__(
        self,
        scene_path: str = "res://scenes/training/training_rack_targeting.tscn",
        port: int = 11102,
        ticks_per_step: int = 4,
        physics_hz: Optional[int] = None,
        action_hz: Optional[int] = None,
        headless: bool = True,
        autostart: bool = True,
        fixed_fps: Optional[int] = None,
    ) -> None:
        super().__init__()
        clock_cfg = get_clock_config()
        self.physics_hz = physics_hz if physics_hz is not None else int(clock_cfg.get("physics_fps", 200))
        self.action_hz = action_hz if action_hz is not None else int(clock_cfg.get("action_fps", 60))
        self.fixed_fps = fixed_fps if fixed_fps is not None else self.physics_hz

        self.scene_path = scene_path
        self.port = port
        self.ticks_per_step = ticks_per_step
        self.headless = headless
        self.autostart = autostart

        # Action Space: [v_lin, v_ang, trigger]
        self.action_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(3,),
            dtype=np.float32,
        )

        # Observation Space: 16 normalized floats
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(16,),
            dtype=np.float32,
        )

        self.bridge: Optional[GodotEnvBridge] = None
        if autostart:
            self._init_bridge()

    def _init_bridge(self) -> None:
        if self.bridge is None:
            self.bridge = GodotEnvBridge(
                scene_path=self.scene_path,
                port=self.port,
                ticks_per_step=self.ticks_per_step,
                physics_hz=self.physics_hz,
                action_hz=self.action_hz,
                headless=self.headless,
                autostart=self.autostart,
            )

    def reset(
        self,
        *,
        seed: Optional[int] = None,
        options: Optional[Dict[str, Any]] = None,
    ) -> Tuple[np.ndarray, Dict[str, Any]]:
        super().reset(seed=seed)
        self._init_bridge()

        seed_val = seed if seed is not None else 0
        difficulty = 0.0
        if options and "difficulty" in options:
            difficulty = float(options["difficulty"])

        assert self.bridge is not None
        raw_obs, info = self.bridge.reset(seed=seed_val, difficulty=difficulty)

        obs = np.array(raw_obs, dtype=np.float32)
        if obs.shape != self.observation_space.shape:
            padded = np.zeros(self.observation_space.shape, dtype=np.float32)
            n = min(len(padded), len(obs))
            padded[:n] = obs[:n]
            obs = padded

        return obs, info

    def step(self, action: np.ndarray) -> Tuple[np.ndarray, float, bool, bool, Dict[str, Any]]:
        assert self.bridge is not None
        act_list = [float(a) for a in action]
        raw_obs, reward, terminated, truncated, info = self.bridge.step(act_list)

        obs = np.array(raw_obs, dtype=np.float32)
        if obs.shape != self.observation_space.shape:
            padded = np.zeros(self.observation_space.shape, dtype=np.float32)
            n = min(len(padded), len(obs))
            padded[:n] = obs[:n]
            obs = padded

        return obs, reward, terminated, truncated, info

    def close(self) -> None:
        if self.bridge:
            self.bridge.close()
            self.bridge = None
