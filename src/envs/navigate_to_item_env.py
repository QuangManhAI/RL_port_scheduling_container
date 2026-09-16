#!/usr/bin/env python3
"""Gymnasium Environment for Stage S1: Navigate-to-Item."""

from src.envs.godot_gym_env import GodotGymEnv


class NavigateToItemEnv(GodotGymEnv):
    """Stage S1: Navigate to Item Environment."""

    def __init__(
        self,
        port: int = 11000,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
    ) -> None:
        super().__init__(
            scene_path="res://scenes/training/training_navigate_to_item.tscn",
            port=port,
            ticks_per_step=ticks_per_step,
            headless=headless,
            autostart=autostart,
        )
