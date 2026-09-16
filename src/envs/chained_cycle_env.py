#!/usr/bin/env python3
"""Gymnasium Environment for Stage S5: Chained Cycle."""

from src.envs.godot_gym_env import GodotGymEnv


class ChainedCycleEnv(GodotGymEnv):
    """Stage S5: Chained Full Cycle Environment."""

    def __init__(
        self,
        port: int = 11000,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
    ) -> None:
        super().__init__(
            scene_path="res://scenes/training/training_chained_cycle.tscn",
            port=port,
            ticks_per_step=ticks_per_step,
            headless=headless,
            autostart=autostart,
        )
