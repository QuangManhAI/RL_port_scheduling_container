#!/usr/bin/env python3
"""Vectorized Gymnasium Environment for Multi-Agent Awareness (2 AMRs sharing PPO policy).

Wraps Godot 4 multi_agent_env.gd with `--s6` flag into a Stable-Baselines3 VecEnv with 2 agents.
Each agent observes 17 continuous dimensions and produces 3 continuous actions.
"""

from __future__ import annotations

import os
import sys
from typing import Any, Dict, List, Optional, Sequence, Tuple, Type, Union

import numpy as np

try:
    import gymnasium as gym
    from gymnasium import spaces
except ImportError:
    import gym  # type: ignore
    from gym import spaces  # type: ignore

from stable_baselines3.common.vec_env import VecEnv
from stable_baselines3.common.vec_env.base_vec_env import VecEnvStepReturn

from src.envs.godot_env_bridge import GodotEnvBridge


class MARLAwarenessVecEnv(VecEnv):
    """VecEnv representing 2 decentralized AMRs with teammate awareness and parameter sharing."""

    def __init__(
        self,
        port: int = 11050,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
        max_steps: int = 1800,
    ) -> None:
        self.num_envs = 2
        self.port = port
        self.ticks_per_step = ticks_per_step
        self.headless = headless
        self.autostart = autostart
        self.max_steps = max_steps

        # Per-agent observation: 17 dimensions (13 base S5 + 4 teammate awareness)
        observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(17,),
            dtype=np.float32,
        )

        # Per-agent action: [v_lin, v_ang, trigger]
        action_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(3,),
            dtype=np.float32,
        )

        super().__init__(self.num_envs, observation_space, action_space)

        self.bridge: Optional[GodotEnvBridge] = None
        self._actions: Optional[np.ndarray] = None
        self._current_obs: np.ndarray = np.zeros((2, 17), dtype=np.float32)

        if autostart:
            self._init_bridge()

    def _init_bridge(self) -> None:
        if self.bridge is None:
            self.bridge = GodotEnvBridge(
                scene_path="res://scenes/training/training_multi_agent.tscn",
                port=self.port,
                ticks_per_step=self.ticks_per_step,
                headless=self.headless,
                autostart=self.autostart,
                extra_args=["--s6", f"--max_steps={self.max_steps}"],
            )

    def reset(self) -> np.ndarray:
        self._init_bridge()
        seed_val = int(np.random.randint(0, 1000000))
        raw_obs, _info = self.bridge.reset(seed=seed_val, difficulty=0.0)
        self._current_obs = self._unpack_obs(raw_obs)
        return self._current_obs.copy()

    def step_async(self, actions: np.ndarray) -> None:
        self._actions = np.asarray(actions, dtype=np.float32)

    def step_wait(self) -> VecEnvStepReturn:
        if self._actions is None:
            raise RuntimeError("step_async must be called before step_wait.")

        # Pack 2 agents' actions into 6-element joint action: [v1, w1, t1, v2, w2, t2]
        act_1 = self._actions[0]
        act_2 = self._actions[1]
        joint_action = [
            float(act_1[0]), float(act_1[1]), float(act_1[2]),
            float(act_2[0]), float(act_2[1]), float(act_2[2]),
        ]

        raw_obs, reward, terminated, truncated, info = self.bridge.step(joint_action)
        done = bool(terminated or truncated)

        obs_2 = self._unpack_obs(raw_obs)
        rews_2 = np.array([reward, reward], dtype=np.float32)
        dones_2 = np.array([done, done], dtype=bool)

        infos_2: List[Dict[str, Any]] = [dict(info), dict(info)]

        if done:
            # Save terminal observation in info dicts (standard SB3 behavior)
            infos_2[0]["terminal_observation"] = obs_2[0].copy()
            infos_2[1]["terminal_observation"] = obs_2[1].copy()
            # Auto-reset environment for continuous rollouts
            seed_val = int(np.random.randint(0, 1000000))
            reset_obs, _ = self.bridge.reset(seed=seed_val, difficulty=0.0)
            obs_2 = self._unpack_obs(reset_obs)

        self._current_obs = obs_2
        return obs_2.copy(), rews_2, dones_2, infos_2

    def _unpack_obs(self, raw_obs: List[float]) -> np.ndarray:
        arr = np.array(raw_obs, dtype=np.float32)
        if len(arr) >= 34:
            return np.stack([arr[:17], arr[17:34]])
        elif len(arr) == 17:
            return np.stack([arr, arr])
        else:
            padded = np.zeros((2, 17), dtype=np.float32)
            lim = min(len(arr) // 2, 17)
            if lim > 0:
                padded[0, :lim] = arr[:lim]
                padded[1, :lim] = arr[lim:2 * lim]
            return padded

    def close(self) -> None:
        if self.bridge is not None:
            self.bridge.close()
            self.bridge = None

    def env_is_wrapped(self, wrapper_class: Type[gym.Wrapper], indices: Optional[Sequence[int]] = None) -> List[bool]:
        return [False] * self.num_envs

    def env_method(self, method_name: str, *method_args: Any, indices: Optional[Sequence[int]] = None, **method_kwargs: Any) -> List[Any]:
        return []

    def get_attr(self, attr_name: str, indices: Optional[Sequence[int]] = None) -> List[Any]:
        return [getattr(self, attr_name, None)] * self.num_envs

    def set_attr(self, attr_name: str, value: Any, indices: Optional[Sequence[int]] = None) -> None:
        setattr(self, attr_name, value)
