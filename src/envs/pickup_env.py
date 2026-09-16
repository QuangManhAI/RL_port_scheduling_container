#!/usr/bin/env python3
"""Gymnasium Environment for Stage S2: Pick-Up."""

from src.envs.godot_gym_env import GodotGymEnv


class PickupEnv(GodotGymEnv):
    """Stage S2: Pick-Up Environment."""

    def __init__(
        self,
        port: int = 11000,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
    ) -> None:
        super().__init__(
            scene_path="res://scenes/training/training_pickup.tscn",
            port=port,
            ticks_per_step=ticks_per_step,
            headless=headless,
            autostart=autostart,
        )
