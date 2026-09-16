#!/usr/bin/env python3
"""Base Gymnasium environment wrapper for Godot 4 RL training scenes."""

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


class GodotGymEnv(gym.Env):
    """Gymnasium environment wrapping a headless Godot 4 training scene."""

    metadata = {"render_modes": ["headless"]}

    def __init__(
        self,
        scene_path: str,
        port: int = 11000,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
    ) -> None:
        super().__init__()
        self.scene_path = scene_path
        self.port = port
        self.ticks_per_step = ticks_per_step
        self.headless = headless

        # Action Space: [v_lin, v_ang, lift_trigger]
        self.action_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(3,),
            dtype=np.float32,
        )

        # Observation Space: 13 normalized floats
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(13,),
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
                headless=self.headless,
                autostart=True,
            )

    def reset(
        self,
        *,
        seed: Optional[int] = None,
        options: Optional[Dict[str, Any]] = None,
    ) -> Tuple[np.ndarray, Dict[str, Any]]:
        super().reset(seed=seed)
        self._init_bridge()

        seed_val = seed if seed is not None else int(np.random.randint(0, 1000000))
        difficulty = float(options.get("difficulty", 0.0)) if options else 0.0

        assert self.bridge is not None
        raw_obs, info = self.bridge.reset(seed=seed_val, difficulty=difficulty)

        obs = np.array(raw_obs, dtype=np.float32)
        if obs.shape != (13,):
            # Pad or truncate if needed
            padded = np.zeros(13, dtype=np.float32)
            padded[: min(13, len(obs))] = obs[:13]
            obs = padded

        return obs, info

    def step(self, action: np.ndarray) -> Tuple[np.ndarray, float, bool, bool, Dict[str, Any]]:
        assert self.bridge is not None
        act_list = [float(a) for a in action]
        raw_obs, reward, terminated, truncated, info = self.bridge.step(act_list)

        obs = np.array(raw_obs, dtype=np.float32)
        if obs.shape != (13,):
            padded = np.zeros(13, dtype=np.float32)
            padded[: min(13, len(obs))] = obs[:13]
            obs = padded

        return obs, float(reward), terminated, truncated, info

    def close(self) -> None:
        if self.bridge:
            self.bridge.close()
            self.bridge = None
