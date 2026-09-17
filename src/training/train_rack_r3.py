#!/usr/bin/env python3
"""Stage R3: Rack Box Pick & Stow PPO Training.

Warm-starts directly from Stage R2 (16-D PPO checkpoint) to learn the active
trigger timing, robotic arm pre-grasp extraction from the assigned shelf tier,
and stowing into the onboard cargo tray without toppling the rack.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any, Callable, Dict, List, Optional

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    import torch
    from stable_baselines3 import PPO
    from stable_baselines3.common.callbacks import BaseCallback, CheckpointCallback
    from stable_baselines3.common.monitor import Monitor
    from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv
except ImportError as e:
    print(f"Error importing RL packages: {e}")
    sys.exit(1)

from src.envs.rack_pick_gym_env import RackPickGymEnv
from src.utils.config_loader import get_clock_config, get_paths_config, get_training_config
from src.utils.weight_transfer import warm_start_rack_policy
from src.utils.export_policy_to_godot import export_ppo_model


class RackPickSuccessCallback(BaseCallback):
    """Monitors arm pick extraction, tray stowing success rate, and rack toppling."""

    def __init__(self, verbose: int = 1) -> None:
        super().__init__(verbose)
        self.pick_successes: List[bool] = []
        self.stow_successes: List[bool] = []
        self.topple_events: List[bool] = []
        self.recent_window: int = 50

    def _on_step(self) -> bool:
        infos = self.locals.get("infos", [])
        dones = self.locals.get("dones", [])

        for idx, done in enumerate(dones):
            if done and idx < len(infos):
                info = infos[idx]
                picked = bool(info.get("is_picked", False))
                stowed = bool(info.get("is_stowed", False))
                toppled = bool(info.get("rack_toppled", False))

                self.pick_successes.append(picked)
                self.stow_successes.append(stowed)
                self.topple_events.append(toppled)

                # Keep sliding window
                if len(self.pick_successes) > self.recent_window:
                    self.pick_successes.pop(0)
                    self.stow_successes.pop(0)
                    self.topple_events.pop(0)

                if len(self.pick_successes) >= 10 and len(self.pick_successes) % 10 == 0:
                    pick_rate = float(np.mean(self.pick_successes))
                    stow_rate = float(np.mean(self.stow_successes))
                    topple_rate = float(np.mean(self.topple_events))
                    print(
                        f"  [Rack R3] Steps: {self.num_timesteps:6d} | "
                        f"Pick Success: {pick_rate * 100:5.1f}% | "
                        f"Stow Success: {stow_rate * 100:5.1f}% | "
                        f"Topple Rate: {topple_rate * 100:4.1f}%"
                    )
        return True


def make_env_thunk(port: int, physics_hz: int = 200, action_hz: int = 60) -> Callable[[], Any]:
    def _thunk():
        env = RackPickGymEnv(
            port=port,
            physics_hz=physics_hz,
            action_hz=action_hz,
            headless=True,
            autostart=True,
        )
        return Monitor(env)

    return _thunk


def main() -> None:
    train_cfg = get_training_config()
    clock_cfg = get_clock_config()
    paths_cfg = get_paths_config()

    def_steps = int(train_cfg.get("target_timesteps_r1", 35000))
    def_lr = float(train_cfg.get("learning_rate", 3e-4))
    def_workers = int(train_cfg.get("workers", 2))
    def_base_port = int(train_cfg.get("base_port", 11110)) + 30
    def_warm_start = "src/training/logs/checkpoints/ppo_r2_final.zip"
    physics_hz = int(clock_cfg.get("physics_fps", 200))
    action_hz = int(clock_cfg.get("action_fps", 60))

    parser = argparse.ArgumentParser(description="Train Stage R3 Rack Box Pick & Stow")
    parser.add_argument("--steps", type=int, default=def_steps, help=f"Total training timesteps (default: {def_steps})")
    parser.add_argument("--workers", type=int, default=def_workers, help=f"Parallel Godot instances (default: {def_workers})")
    parser.add_argument("--base-port", type=int, default=def_base_port, help=f"Starting TCP port (default: {def_base_port})")
    parser.add_argument("--lr", type=float, default=def_lr, help=f"Learning rate (default: {def_lr})")
    parser.add_argument("--n-steps", type=int, default=1024, help="PPO rollout buffer size per worker")
    parser.add_argument("--batch-size", type=int, default=64, help="Minibatch size")
    parser.add_argument("--warm-start", type=str, default=def_warm_start, help="Source checkpoint (default: ppo_r2_final.zip)")
    parser.add_argument("--no-warm-start", action="store_true", help="Train from scratch without warm-starting")
    parser.add_argument("--model-dir", type=str, default="src/training/logs/checkpoints")
    parser.add_argument("--tb-log", type=str, default="src/training/logs/tensorboard")
    parser.add_argument("--device", type=str, default="cpu")

    args = parser.parse_args()

    os.makedirs(args.model_dir, exist_ok=True)
    os.makedirs(args.tb_log, exist_ok=True)

    print("=" * 68)
    print("   STAGE R3: RACK BOX PICK & STOW PPO TRAINING")
    print(f"   Target Steps:              {args.steps}")
    print(f"   Parallel Workers:          {args.workers} (Ports {args.base_port} to {args.base_port + args.workers - 1})")
    print(f"   Simulation Clock:          {physics_hz} Hz Physics | Action Decision: {action_hz} Hz")
    print(f"   Warm-Start Source:         {args.warm_start if not args.no_warm_start else 'None (From Scratch)'}")
    print("=" * 68 + "\n")

    # Build Vectorized Environments
    env_thunks = [make_env_thunk(args.base_port + i, physics_hz, action_hz) for i in range(args.workers)]
    if args.workers == 1:
        vec_env = DummyVecEnv(env_thunks)
    else:
        vec_env = SubprocVecEnv(env_thunks)

    success_callback = RackPickSuccessCallback()
    checkpoint_callback = CheckpointCallback(
        save_freq=max(2048, args.steps // 10),
        save_path=os.path.join(args.model_dir, "r3"),
        name_prefix="ppo_r3",
    )

    # Initialize 16-D PPO Model
    model = PPO(
        policy="MlpPolicy",
        env=vec_env,
        learning_rate=args.lr,
        n_steps=args.n_steps,
        batch_size=args.batch_size,
        gamma=0.99,
        gae_lambda=0.95,
        clip_range=0.2,
        ent_coef=0.01,
        verbose=1,
        tensorboard_log=args.tb_log,
        device=args.device,
    )

    # Transfer pre-trained foundation weights
    if not args.no_warm_start and os.path.isfile(args.warm_start):
        print(f">> Warm-starting R3 policy from: {args.warm_start}")
        model = warm_start_rack_policy(model, args.warm_start, base_dim=16)
        if "r2" in args.warm_start.lower():
            with torch.no_grad():
                # Prime trigger action head with neutral-positive bias to encourage active grasping
                model.policy.action_net.bias[2] = 0.15
    elif not args.no_warm_start:
        print(f"⚠️ Warm-start file '{args.warm_start}' not found. Training from scratch.")

    try:
        model.learn(
            total_timesteps=args.steps,
            callback=[success_callback, checkpoint_callback],
            progress_bar=False,
        )
        final_path = os.path.join(args.model_dir, "ppo_r3_final.zip")
        model.save(final_path)
        print(f"\n✔ Stage R3 training complete! Model saved to: {final_path}")

        # Export native in-engine JSON policy for zero-latency execution
        json_path = "godot/models/ppo_r3_policy.json"
        export_ppo_model(final_path, json_path)
        print(f"✔ Native in-engine policy exported to: {json_path}")
    finally:
        vec_env.close()


if __name__ == "__main__":
    main()
