#!/usr/bin/env python3
"""Multi-Agent RL Training Runner (2 AMRs, 4 Boxes) with Live Visual 60 FPS Display."""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import Any, Dict, List, Optional

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    import torch
    from stable_baselines3 import PPO
    from stable_baselines3.common.callbacks import BaseCallback, CheckpointCallback
    from stable_baselines3.common.monitor import Monitor
except ImportError as e:
    print(f"Error importing RL packages: {e}")
    sys.exit(1)

from src.envs.multi_agent_gym_env import MultiAgentGymEnv


class MultiAgentLiveCallback(BaseCallback):
    """Logs live multi-agent delivery KPIs during training."""

    def __init__(self, verbose: int = 1) -> None:
        super().__init__(verbose)
        self.episode_count: int = 0
        self.ep_delivered: List[int] = []
        self.ep_collisions: List[int] = []

    def _on_step(self) -> bool:
        infos = self.locals.get("infos", [])
        dones = self.locals.get("dones", [])

        if isinstance(dones, (bool, np.bool_)):
            dones = [dones]

        for idx, (done, info) in enumerate(zip(dones, infos)):
            if done and isinstance(info, dict):
                self.episode_count += 1
                deliv = int(info.get("delivered_count", 0))
                col = int(info.get("robot_collisions", 0))
                all_deliv = bool(info.get("all_delivered", False))

                self.ep_delivered.append(deliv)
                self.ep_collisions.append(col)

                status_mark = "✔ ALL 4 DELIVERED!" if all_deliv else f"Delivered {deliv}/4"
                print(f"[MARL Ep {self.episode_count:03d}] Step {self.num_timesteps:6d} | {status_mark} | Collisions: {col:2d}")

        return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Multi-Agent RL (2 AMRs, 4 Boxes) Training with Visual Display.")
    parser.add_argument("--steps", type=int, default=50000, help="Total training steps")
    parser.add_argument("--port", type=int, default=11050, help="TCP port for Godot bridge")
    parser.add_argument("--fps", type=float, default=60.0, help="Visual playback pacing rate (actions per second)")
    parser.add_argument("--headless", action="store_true", help="Run headless without opening Godot window")
    parser.add_argument("--lr", type=float, default=3e-4, help="PPO learning rate")
    parser.add_argument("--batch-size", type=int, default=64, help="PPO batch size")
    parser.add_argument("--n-steps", type=int, default=1024, help="PPO rollout steps")
    parser.add_argument("--device", type=str, default="cpu", choices=["auto", "cuda", "cpu"])
    parser.add_argument("--warm-start", type=str, default="", help="Path to checkpoint model to warm-start from")
    parser.add_argument("--model-dir", type=str, default="src/training/logs/checkpoints/marl", help="Save directory")
    parser.add_argument("--tb-log", type=str, default="src/training/logs/tb/marl", help="TensorBoard log dir")

    args = parser.parse_args()

    os.makedirs(args.model_dir, exist_ok=True)
    os.makedirs(args.tb_log, exist_ok=True)

    print("=" * 65)
    print("   MULTI-AGENT REINFORCEMENT LEARNING (MARL) TRAINING")
    print("   Fleet: 2 AMRs | Target: 4 Boxes | Mode: Cooperative Delivery")
    print(f"   Visual Display: {'Headless (Off - Maximum Speed)' if args.headless else 'ENABLED (Godot Window Active)'}")
    print(f"   Port: {args.port} | Total Target Steps: {args.steps}")
    print("=" * 65 + "\n")

    # Instantiate Environment
    raw_env = MultiAgentGymEnv(
        port=args.port,
        ticks_per_step=4,
        headless=args.headless,
        autostart=True,
        fps=args.fps,
    )
    env = Monitor(raw_env)

    # Callbacks
    live_cb = MultiAgentLiveCallback()
    save_cb = CheckpointCallback(
        save_freq=max(1024, args.steps // 10),
        save_path=args.model_dir,
        name_prefix="mappo_2amr_4boxes",
    )

    # Initialize or Load PPO Model
    if args.warm_start and os.path.isfile(args.warm_start):
        print(f">> Resuming / Warm-starting weights from: {args.warm_start}")
        model = PPO.load(
            args.warm_start,
            env=env,
            learning_rate=args.lr,
            tensorboard_log=args.tb_log,
            device=args.device,
        )
    else:
        model = PPO(
            policy="MlpPolicy",
            env=env,
            learning_rate=args.lr,
            n_steps=args.n_steps,
            batch_size=args.batch_size,
            gamma=0.99,
            gae_lambda=0.95,
            clip_range=0.2,
            ent_coef=0.01,
            verbose=0,
            tensorboard_log=args.tb_log,
            device=args.device,
        )

    try:
        print(">> Training started! Observe both AMRs operating live in Godot...")
        model.learn(
            total_timesteps=args.steps,
            callback=[live_cb, save_cb],
            progress_bar=False,
        )
        final_model_path = os.path.join(args.model_dir, "mappo_2amr_4boxes_final.zip")
        model.save(final_model_path)
        print(f"\n✔ Training complete! Final weights saved to: {final_model_path}")
    finally:
        env.close()


if __name__ == "__main__":
    main()
