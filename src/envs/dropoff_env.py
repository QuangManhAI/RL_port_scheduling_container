#!/usr/bin/env python3
"""Gymnasium Environment for Stage S4: Drop-Off."""

from src.envs.godot_gym_env import GodotGymEnv


class DropoffEnv(GodotGymEnv):
    """Stage S4: Drop-Off Environment."""

    def __init__(
        self,
        port: int = 11000,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
    ) -> None:
        super().__init__(
            scene_path="res://scenes/training/training_dropoff.tscn",
            port=port,
            ticks_per_step=ticks_per_step,
            headless=headless,
            autostart=autostart,
        )
