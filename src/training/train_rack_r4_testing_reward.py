#!/usr/bin/env python3
"""Stage R4: Full Rack Cycle Training with Sparse Truck Delivery Reward (r4_testing_reward).

In this mode, the agent receives a reward ONLY when a retrieved box is placed onto the
motorized conveyor belt, transported down the chute, and successfully loaded into the
outbound cargo truck (#LOG-882).

Model Checkpoint: src/training/logs/checkpoints/ppo_r4_testing_reward_final.zip
Native Godot JSON: godot/models/ppo_r4_testing_reward_policy.json
"""

from __future__ import annotations

import argparse
import csv
import datetime
import os
import sys
import time
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

from src.envs.rack_cycle_gym_env import RackCycleGymEnv
from src.utils.config_loader import get_clock_config, get_paths_config, get_training_config
from src.utils.weight_transfer import warm_start_rack_policy
from src.utils.export_policy_to_godot import export_ppo_model


class R4TestingRewardCallback(BaseCallback):
    """Monitors truck loading events and logs sparse delivery reward metrics."""

    def __init__(
        self,
        csv_path: str = "experiments/metrics/r4_testing_reward_metrics.csv",
        verbose: int = 1,
    ) -> None:
        super().__init__(verbose)
        self.csv_path = csv_path
        self.total_truck_deliveries: int = 0
        self.episodes_completed: int = 0
        self.episode_rewards: List[float] = []
        self.cur_ep_reward: float = 0.0
        self.start_time: float = time.time()
        self.last_step_time: float = time.time()

        os.makedirs(os.path.dirname(os.path.abspath(csv_path)), exist_ok=True)
        if not os.path.exists(csv_path):
            with open(csv_path, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow([
                    "timestamp", "step", "episode", "ep_reward", "truck_boxes_loaded",
                    "cycle_success", "sps", "elapsed_sec"
                ])

    def _on_step(self) -> bool:
        rewards = self.locals.get("rewards", [0.0])
        self.cur_ep_reward += float(np.sum(rewards))

        infos = self.locals.get("infos", [])
        dones = self.locals.get("dones", [])

        for idx, done in enumerate(dones):
            if idx < len(infos):
                info = infos[idx]
                truck_loaded = int(info.get("truck_boxes_loaded", 0))

                if done:
                    self.episodes_completed += 1
                    self.total_truck_deliveries += truck_loaded
                    self.episode_rewards.append(self.cur_ep_reward)

                    cycle_ok = bool(info.get("cycle_success", False))
                    elapsed = time.time() - self.start_time
                    sps = int(self.num_timesteps / max(0.1, elapsed))

                    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    target_cnt = int(info.get("target_delivery_count", 1))
                    picked = bool(info.get("is_picked", False))
                    stowed = bool(info.get("is_stowed", False))
                    toppled = bool(info.get("rack_toppled", False))
                    print(
                        f"[{now_str}] [Ep #{self.episodes_completed:03d}] Steps: {self.num_timesteps:6d} | "
                        f"Truck: {truck_loaded}/{target_cnt} | Pick: {int(picked)} | Stow: {int(stowed)} | "
                        f"Topple: {int(toppled)} | Ep Rew: {self.cur_ep_reward:+6.1f} | SPS: {sps}"
                    )

                    with open(self.csv_path, "a", newline="", encoding="utf-8") as f:
                        writer = csv.writer(f)
                        writer.writerow([
                            now_str, self.num_timesteps, self.episodes_completed,
                            f"{self.cur_ep_reward:.2f}", truck_loaded,
                            int(cycle_ok), sps, f"{elapsed:.1f}"
                        ])

                    self.cur_ep_reward = 0.0

        return True


import gymnasium as gym


class ResetWrapperEnv(gym.Wrapper):
    """Gym wrapper ensuring every reset passes reward_mode='r4_testing_reward' and multi-box delivery_count."""

    def __init__(self, env: RackCycleGymEnv, delivery_count: int = 2) -> None:
        super().__init__(env)
        self.delivery_count = delivery_count

    def reset(self, **kwargs):
        options = kwargs.get("options", {}) or {}
        options["reward_mode"] = "r4_testing_reward"
        options["randomize_layout"] = True
        options["delivery_count"] = self.delivery_count
        kwargs["options"] = options
        return self.env.reset(**kwargs)


def make_testing_reward_env_thunk(
    port: int,
    physics_hz: int = 200,
    action_hz: int = 60,
    delivery_count: int = 2,
    headless: bool = True,
) -> Callable[[], Any]:
    def _thunk():
        env = RackCycleGymEnv(
            port=port,
            physics_hz=physics_hz,
            action_hz=action_hz,
            headless=headless,
            autostart=True,
        )
        return Monitor(ResetWrapperEnv(env, delivery_count=delivery_count))

    return _thunk


def main() -> None:
    train_cfg = get_training_config()
    clock_cfg = get_clock_config()

    def_steps = 100000
    def_lr = 3e-4
    def_workers = 1
    def_base_port = 11250
    physics_hz = int(clock_cfg.get("physics_fps", 200))
    action_hz = int(clock_cfg.get("action_fps", 60))

    # Priority warm-start: existing stable R4 final foundation policy, falling back to R3
    def_warm_start = "src/training/logs/checkpoints/ppo_r4_final.zip"
    if not os.path.exists(def_warm_start):
        def_warm_start = "src/training/logs/checkpoints/ppo_r4_testing_reward.zip"
    if not os.path.exists(def_warm_start):
        def_warm_start = "src/training/logs/checkpoints/ppo_r3_final.zip"

    parser = argparse.ArgumentParser(description="Train R4 with r4_testing_reward (Truck Delivery Sparse Reward)")
    parser.add_argument("--steps", type=int, default=def_steps, help=f"Total training timesteps (default: {def_steps})")
    parser.add_argument("--delivery-count", type=int, default=2, help="Number of boxes to deliver per episode (-1 or 8 for all boxes, default: 2)")
    parser.add_argument("--workers", type=int, default=def_workers, help=f"Parallel Godot instances (default: {def_workers})")
    parser.add_argument("--base-port", type=int, default=def_base_port, help=f"Starting TCP port (default: {def_base_port})")
    parser.add_argument("--lr", type=float, default=def_lr, help=f"Learning rate (default: {def_lr})")
    parser.add_argument("--n-steps", type=int, default=1024, help="PPO rollout buffer size per worker")
    parser.add_argument("--batch-size", type=int, default=64, help="Minibatch size")
    parser.add_argument("--warm-start", type=str, default=def_warm_start, help="Source checkpoint to warm-start from")
    parser.add_argument("--no-warm-start", action="store_true", help="Train from scratch without warm-starting")
    parser.add_argument("--model-dir", type=str, default="src/training/logs/checkpoints")
    parser.add_argument("--tb-log", type=str, default="src/training/logs/tensorboard")
    parser.add_argument("--device", type=str, default="cpu", help="PyTorch compute device ('cpu' or 'cuda')")
    parser.add_argument("--headless", action="store_true", default=True, help="Run Godot in headless mode")

    args = parser.parse_args()

    out_ckpt_dir = os.path.join(args.model_dir, "r4_testing_reward")
    os.makedirs(out_ckpt_dir, exist_ok=True)
    os.makedirs(args.tb_log, exist_ok=True)

    print("=" * 75)
    print("   STAGE R4: TRUCK DELIVERY SPARSE REWARD TRAINING (r4_testing_reward)")
    print(f"   Target Steps:              {args.steps}")
    print(f"   Delivery Target:           {args.delivery_count if args.delivery_count > 0 else 'ALL 8'} Boxes per Episode")
    print(f"   Observation Space:         32-D (16 Ego/Task + 16-Ray 360° LiDAR)")
    print(f"   Reward Condition:          ONLY when boxes are transported onto conveyor and into truck")
    print(f"   Workers:                   {args.workers} (Ports {args.base_port} to {args.base_port + args.workers - 1})")
    print(f"   Simulation Clock:          {physics_hz} Hz Physics | Action Decision: {action_hz} Hz")
    print(f"   Compute Device:            {args.device.upper()}")
    print(f"   Warm-Start Source:         {args.warm_start if not args.no_warm_start else 'None (From Scratch)'}")
    print(f"   Output Checkpoint:         {os.path.join(out_ckpt_dir, 'ppo_r4_testing_reward_final.zip')}")
    print("=" * 75 + "\n")

    env_thunks = [
        make_testing_reward_env_thunk(args.base_port + i, physics_hz, action_hz, delivery_count=args.delivery_count, headless=args.headless)
        for i in range(args.workers)
    ]
    if args.workers == 1:
        vec_env = DummyVecEnv(env_thunks)
    else:
        vec_env = SubprocVecEnv(env_thunks)

    reward_callback = R4TestingRewardCallback()
    checkpoint_callback = CheckpointCallback(
        save_freq=max(2048, args.steps // 5),
        save_path=out_ckpt_dir,
        name_prefix="ppo_r4_testing_reward",
    )

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

    if not args.no_warm_start and os.path.isfile(args.warm_start):
        print(f">> Warm-starting policy weights from: {args.warm_start}")
        model = warm_start_rack_policy(model, args.warm_start, base_dim=16)
    elif not args.no_warm_start:
        print(f"⚠️ Notice: Warm-start file '{args.warm_start}' not found. Initializing from scratch.")

    try:
        model.learn(
            total_timesteps=args.steps,
            callback=[reward_callback, checkpoint_callback],
            progress_bar=False,
        )

        # Save final models in both specific and root checkpoint folders
        final_path_sub = os.path.join(out_ckpt_dir, "ppo_r4_testing_reward_final.zip")
        final_path_root = os.path.join(args.model_dir, "ppo_r4_testing_reward.zip")
        model.save(final_path_sub)
        model.save(final_path_root)
        print(f"\n✔ Stage R4 testing reward training complete!")
        print(f"   Saved to: {final_path_sub}")
        print(f"   Saved to: {final_path_root}")

        # Export native in-engine JSON policy for zero-latency execution
        json_path = "godot/models/ppo_r4_testing_reward_policy.json"
        export_ppo_model(final_path_root, json_path)
        print(f"✔ Native in-engine policy exported to: {json_path}")
    finally:
        vec_env.close()


if __name__ == "__main__":
    main()
