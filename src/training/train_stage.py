#!/usr/bin/env python3
"""Stage-by-stage PPO training runner for Godot 4 skill curriculum."""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any, Dict, List, Optional

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
    print("Please ensure .venv is active and dependencies are installed.")
    sys.exit(1)

from src.envs.chained_cycle_env import ChainedCycleEnv
from src.envs.dropoff_env import DropoffEnv
from src.envs.navigate_carrying_env import NavigateCarryingEnv
from src.envs.navigate_to_item_env import NavigateToItemEnv
from src.envs.pickup_env import PickupEnv
from src.training.terminal_state_buffer import TerminalStateBuffer

STAGE_REGISTRY = {
    "s1": NavigateToItemEnv,
    "navigate_to_item": NavigateToItemEnv,
    "s2": PickupEnv,
    "pickup": PickupEnv,
    "s3": NavigateCarryingEnv,
    "navigate_carrying": NavigateCarryingEnv,
    "s4": DropoffEnv,
    "dropoff": DropoffEnv,
    "s5": ChainedCycleEnv,
    "chained_cycle": ChainedCycleEnv,
}


class StageSuccessCallback(BaseCallback):
    """Logs success rate and records terminal states for downstream curriculum seeding."""

    def __init__(self, stage_name: str, terminal_buffer: TerminalStateBuffer, verbose: int = 1) -> None:
        super().__init__(verbose)
        self.stage_name = stage_name
        self.terminal_buffer = terminal_buffer
        self.episode_successes: List[bool] = []
        self.recent_window: int = 100

    def _on_step(self) -> bool:
        infos = self.locals.get("infos", [])
        dones = self.locals.get("dones", [])

        # Ensure dones is iterable
        if isinstance(dones, (bool, np.bool_)):
            dones = [dones]

        for idx, (done, info) in enumerate(zip(dones, infos)):
            if not done or not isinstance(info, dict):
                continue

            # Record success flags only at episode termination
            success = False
            if "goal_reached" in info:
                success = bool(info["goal_reached"])
            elif "is_picked" in info:
                success = bool(info["is_picked"])
            elif "is_placed" in info:
                success = bool(info["is_placed"])
            elif "cycle_success" in info:
                success = bool(info["cycle_success"])

            self.episode_successes.append(success)

            # Record terminal pose if episode finished
            if "terminal_pose" in info and info["terminal_pose"]:
                self.terminal_buffer.record_terminal_state(self.stage_name, info["terminal_pose"], info)

            if len(self.episode_successes) % 10 == 0:
                recent = self.episode_successes[-self.recent_window:]
                rate = float(np.mean(recent))
                print(f"[{self.stage_name.upper()}] Episodes: {len(self.episode_successes)} | Step: {self.num_timesteps} | Recent Success Rate: {rate:.1%} ({sum(recent)}/{len(recent)})")

        if len(self.episode_successes) > 0:
            rate = float(np.mean(self.episode_successes[-self.recent_window:]))
            self.logger.record("curriculum/success_rate", rate)

        return True


def make_env_thunk(stage_key: str, port: int, ticks: int):
    """Helper to instantiate environment in worker process."""
    def _init():
        env_cls = STAGE_REGISTRY[stage_key.lower()]
        env = env_cls(port=port, ticks_per_step=ticks, headless=True, autostart=True)
        return Monitor(env)
    return _init


def main() -> None:
    parser = argparse.ArgumentParser(description="Train PPO policy for Godot skill stage.")
    parser.add_argument("--stage", type=str, default="s1", choices=list(STAGE_REGISTRY.keys()), help="Stage to train")
    parser.add_argument("--workers", type=int, default=4, help="Number of parallel Godot instances")
    parser.add_argument("--steps", type=int, default=100000, help="Total training timesteps")
    parser.add_argument("--lr", type=float, default=3e-4, help="Learning rate")
    parser.add_argument("--batch-size", type=int, default=64, help="PPO mini-batch size")
    parser.add_argument("--n-steps", type=int, default=2048, help="PPO rollout steps per worker")
    parser.add_argument("--base-port", type=int, default=11000, help="Starting TCP port for Godot bridge")
    parser.add_argument("--ticks", type=int, default=4, help="Physics ticks per action step")
    parser.add_argument("--device", type=str, default="cpu", choices=["auto", "cuda", "cpu"], help="Training device (cpu recommended for MLP)")
    parser.add_argument("--warm-start", type=str, default="", help="Path to checkpoint model to warm-start from")
    parser.add_argument("--tb-log", type=str, default="src/training/logs/tb", help="TensorBoard log dir")
    parser.add_argument("--model-dir", type=str, default="src/training/logs/checkpoints", help="Model checkpoint dir")

    args = parser.parse_args()

    stage_name = args.stage.lower()
    os.makedirs(args.model_dir, exist_ok=True)
    os.makedirs(args.tb_log, exist_ok=True)

    print(f"=== Starting Phase 06 Skill Training: Stage {stage_name.upper()} ===")
    print(f"Workers: {args.workers} (Ports {args.base_port} to {args.base_port + args.workers - 1})")
    print(f"Target steps: {args.steps}, Device: {args.device}")

    # Build Vectorized Environments
    env_thunks = [make_env_thunk(stage_name, args.base_port + i, args.ticks) for i in range(args.workers)]
    if args.workers == 1:
        vec_env = DummyVecEnv(env_thunks)
    else:
        vec_env = SubprocVecEnv(env_thunks)

    terminal_buffer = TerminalStateBuffer()
    success_callback = StageSuccessCallback(stage_name, terminal_buffer)
    checkpoint_callback = CheckpointCallback(
        save_freq=max(2048, args.steps // 10),
        save_path=os.path.join(args.model_dir, stage_name),
        name_prefix=f"ppo_{stage_name}",
    )

    # Ent coef: slightly higher for navigation (0.01), lower for manipulation (0.005)
    ent_coef = 0.01 if stage_name in ["s1", "s3", "navigate_to_item", "navigate_carrying"] else 0.005

    # Initialize or Load PPO Model
    if args.warm_start and os.path.isfile(args.warm_start):
        print(f"Loading warm-start weights from: {args.warm_start}")
        model = PPO.load(
            args.warm_start,
            env=vec_env,
            learning_rate=args.lr,
            tensorboard_log=args.tb_log,
            device=args.device,
        )
    else:
        model = PPO(
            policy="MlpPolicy",
            env=vec_env,
            learning_rate=args.lr,
            n_steps=args.n_steps,
            batch_size=args.batch_size,
            gamma=0.99,
            gae_lambda=0.95,
            clip_range=0.2,
            ent_coef=ent_coef,
            verbose=1,
            tensorboard_log=args.tb_log,
            device=args.device,
        )

    try:
        model.learn(
            total_timesteps=args.steps,
            callback=[success_callback, checkpoint_callback],
            progress_bar=False,
        )
        final_path = os.path.join(args.model_dir, f"ppo_{stage_name}_final.zip")
        model.save(final_path)
        print(f"✔ Stage {stage_name.upper()} training complete! Model saved to {final_path}")
    finally:
        vec_env.close()


if __name__ == "__main__":
    main()
