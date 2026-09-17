#!/usr/bin/env python3
"""Gymnasium Multi-Agent Environment Wrapper for Phase 08 Fleet Coordination.

Exposes a decentralized multi-agent interface (N_agents, 37) with Centralized Critic
global state support for MAPPO training.
"""

from __future__ import annotations

import os
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from pathlib import Path
project_root = str(Path(__file__).resolve().parents[3])
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.envs.godot_env_bridge import GodotEnvBridge
from src.utils.config_loader import get_clock_config


class FleetMappoGymEnv(gym.Env):
    """Multi-Agent Fleet Coordination Environment (Phase 08 - MAPPO).
    
    Attributes:
        num_agents (int): Number of AMRs in the fleet (default: 2).
        obs_dim (int): 37-dimensional ego-centric observation per agent.
        act_dim (int): 2-dimensional continuous velocity controls [v_lin, v_ang].
    """

    metadata = {"render_modes": ["headless"]}

    def __init__(
        self,
        scene_path: str = "res://scenes/training/fleet/training_fleet_aisle.tscn",
        port: int = 11300,
        ticks_per_step: int = 4,
        physics_hz: Optional[int] = None,
        action_hz: Optional[int] = None,
        headless: bool = True,
        autostart: bool = True,
        num_agents: int = 2,
        fps: float = 0.0,
    ) -> None:
        super().__init__()
        clock_cfg = get_clock_config()
        self.physics_hz = physics_hz if physics_hz is not None else int(clock_cfg.get("physics_fps", 200))
        self.action_hz = action_hz if action_hz is not None else int(clock_cfg.get("action_fps", 60))
        self.scene_path = scene_path
        self.port = port
        self.ticks_per_step = ticks_per_step
        self.headless = headless
        self.autostart = autostart
        self.num_agents = num_agents
        self.fps = fps
        self.obs_dim = 37
        self.act_dim = 2

        # Per-agent continuous action space: [v_lin, v_ang] for each AMR
        self.action_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(self.num_agents, self.act_dim),
            dtype=np.float32,
        )

        # Per-agent observation space: fixed 37 dimensions for each AMR
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(self.num_agents, self.obs_dim),
            dtype=np.float32,
        )

        # Single agent spaces (convenience accessors for Actor networks)
        self.single_action_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(self.act_dim,),
            dtype=np.float32,
        )
        self.single_observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(self.obs_dim,),
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
        assert self.bridge is not None and self.bridge.client is not None

        seed_val = seed if seed is not None else 0
        difficulty = float(options.get("difficulty", 0.0)) if options else 0.0
        extra_kwargs: Dict[str, Any] = {}
        if options:
            for k, v in options.items():
                if k not in ["difficulty"]:
                    extra_kwargs[k] = v

        raw_obs, info = self.bridge.client.reset(
            seed=seed_val,
            difficulty=difficulty,
            physics_hz=self.physics_hz,
            action_hz=self.action_hz,
            **extra_kwargs,
        )
        fleet_obs = self._format_fleet_obs(raw_obs)
        return fleet_obs, info

    def step(
        self,
        actions: np.ndarray,
    ) -> Tuple[np.ndarray, np.ndarray, bool, bool, Dict[str, Any]]:
        """Advance multi-agent simulation by one decision step.
        
        Args:
            actions: Array of shape (num_agents, 2) or flattened (num_agents * 2,).
        
        Returns:
            fleet_obs: Array of shape (num_agents, 37).
            rewards: Array of shape (num_agents,) or float team reward.
            terminated: Boolean episode completion flag.
            truncated: Boolean step limit flag.
            info: Dictionary containing global_state and per-agent metrics.
        """
        assert self.bridge is not None and self.bridge.client is not None

        # Ensure actions is a nested list or 2D array
        if isinstance(actions, np.ndarray):
            actions_list = actions.tolist()
        elif isinstance(actions, list):
            actions_list = actions
        else:
            actions_list = [[0.0, 0.0] for _ in range(self.num_agents)]

        raw_obs, team_reward, terminated, truncated, info = self.bridge.client.step(actions_list)

        fleet_obs = self._format_fleet_obs(raw_obs)
        rewards = np.full((self.num_agents,), team_reward, dtype=np.float32)

        if not self.headless and self.fps > 0:
            time.sleep(1.0 / max(1.0, self.fps))

        return fleet_obs, rewards, terminated, truncated, info

    def _format_fleet_obs(self, raw_obs: Any) -> np.ndarray:
        """Ensure observations match (num_agents, 37) numpy shape."""
        if isinstance(raw_obs, list):
            if len(raw_obs) > 0 and isinstance(raw_obs[0], list):
                arr = np.array(raw_obs, dtype=np.float32)
                if arr.shape == (self.num_agents, self.obs_dim):
                    return arr
            elif len(raw_obs) == self.num_agents * self.obs_dim:
                return np.array(raw_obs, dtype=np.float32).reshape(self.num_agents, self.obs_dim)

        return np.zeros((self.num_agents, self.obs_dim), dtype=np.float32)

    def close(self) -> None:
        if self.bridge:
            self.bridge.close()
            self.bridge = None
