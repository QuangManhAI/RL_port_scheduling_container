#!/usr/bin/env python3
"""Training script for the PortEnv reinforcement learning environment."""

import argparse
import os
import sys
from typing import Any

import numpy as np

# Ensure project root is in python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from port_sim import PortEnv, default_config, medium_config

try:
    import gymnasium as gym
    from stable_baselines3 import PPO
    from stable_baselines3.common.callbacks import BaseCallback
    from stable_baselines3.common.monitor import Monitor
    from stable_baselines3.common.env_checker import check_env
except ImportError as e:
    print(f"Error: Missing required packages: {e}")
    print("Please make sure Stable-Baselines3 and TensorBoard are installed in your virtualenv.")
    sys.exit(1)


class RewardBreakdownCallback(BaseCallback):
    """Callback to log detailed reward breakdown components to TensorBoard."""

    def __init__(self, verbose: int = 0) -> None:
        super().__init__(verbose)
        self.episode_breakdown: dict[str, float] = {}

    def _on_step(self) -> bool:
        # self.locals["infos"] is a list of dicts (one for each environment in the vector)
        for info in self.locals.get("infos", []):
            if "reward_breakdown" in info:
                breakdown = info["reward_breakdown"]
                for k, v in breakdown.items():
                    self.episode_breakdown[k] = self.episode_breakdown.get(k, 0.0) + v

            # When an episode ends, the Monitor wrapper adds an 'episode' key
            if "episode" in info:
                # Log the cumulative components for the completed episode
                for k, v in self.episode_breakdown.items():
                    self.logger.record(f"reward_breakdown/ep_{k}", v)
                
                # Reset accumulator for the next episode
                self.episode_breakdown = {}
                
        return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Train PPO agent on PortEnv.")
    parser.add_argument(
        "--scenario",
        type=str,
        choices=["default", "medium"],
        default="default",
        help="Scenario config to use (default or medium)",
    )
    parser.add_argument(
        "--steps",
        type=int,
        default=100000,
        help="Total number of steps to train",
    )
    parser.add_argument(
        "--tb-log",
        type=str,
        default="logs/tb",
        help="TensorBoard log directory",
    )
    parser.add_argument(
        "--model-path",
        type=str,
        default="logs/models/ppo_port_scheduling",
        help="Path to save the trained model",
    )
    parser.add_argument(
        "--lr",
        type=float,
        default=3e-4,
        help="Learning rate for PPO",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed",
    )

    # Allow overriding reward weights from CLI
    parser.add_argument("--w-valid", type=float, default=None, help="Weight for valid placement")
    parser.add_argument("--w-invalid", type=float, default=None, help="Weight for invalid placement")
    parser.add_argument("--w-ship-complete", type=float, default=None, help="Weight for ship complete")
    parser.add_argument("--w-rehandling", type=float, default=None, help="Weight for rehandling penalty")
    parser.add_argument("--w-delay", type=float, default=None, help="Weight for delay penalty")
    parser.add_argument("--w-idle", type=float, default=None, help="Weight for crane idle penalty")
    parser.add_argument("--w-distance", type=float, default=None, help="Weight for distance penalty")

    args = parser.parse_args()

    # 1. Setup config
    if args.scenario == "medium":
        cfg = medium_config()
    else:
        cfg = default_config()

    # Override weights if provided
    overrides = {}
    if args.w_valid is not None:
        overrides["weight_valid_placement"] = args.w_valid
    if args.w_invalid is not None:
        overrides["weight_invalid_placement"] = args.w_invalid
    if args.w_ship_complete is not None:
        overrides["weight_ship_complete"] = args.w_ship_complete
    if args.w_rehandling is not None:
        overrides["weight_rehandling_penalty"] = args.w_rehandling
    if args.w_delay is not None:
        overrides["weight_delay_penalty"] = args.w_delay
    if args.w_idle is not None:
        overrides["weight_idle_penalty"] = args.w_idle
    if args.w_distance is not None:
        overrides["weight_distance_penalty"] = args.w_distance

    if overrides:
        # Create a new config with overridden values
        from dataclasses import replace
        cfg = replace(cfg, **overrides)
        print("Using custom reward weights:")
        for k, v in overrides.items():
            print(f"  {k}: {v}")

    # 2. Initialize environment
    print(f"Initializing PortEnv with {args.scenario} scenario...")
    raw_env = PortEnv(cfg)
    
    # Run a quick check_env to verify compliance
    print("Verifying environment compatibility with Gymnasium...")
    check_env(raw_env)
    print("Environment compatibility verified successfully.")

    # Wrap the environment with Monitor to collect episode statistics
    env = Monitor(raw_env)

    # 3. Create model
    print(f"Creating PPO model with learning_rate={args.lr}, seed={args.seed}...")
    model = PPO(
        policy="MultiInputPolicy",
        env=env,
        learning_rate=args.lr,
        seed=args.seed,
        tensorboard_log=args.tb_log,
        verbose=1,
    )

    # 4. Train
    print(f"Starting training for {args.steps} steps...")
    try:
        model.learn(
            total_timesteps=args.steps,
            callback=RewardBreakdownCallback(),
            tb_log_name=f"ppo_{args.scenario}",
        )
        print("Training completed successfully.")
    except KeyboardInterrupt:
        print("Training interrupted by user. Saving current model...")

    # 5. Save model
    os.makedirs(os.path.dirname(args.model_path), exist_ok=True)
    model.save(args.model_path)
    print(f"Model saved to {args.model_path}")

    # 6. Evaluation run with the trained policy
    print("\nRunning a test episode with the trained model...")
    obs, info = raw_env.reset(seed=args.seed + 100)
    terminated = False
    truncated = False
    total_reward = 0.0
    steps = 0
    
    while not (terminated or truncated):
        action, _ = model.predict(obs, deterministic=True)
        obs, reward, terminated, truncated, info = raw_env.step(int(action))
        total_reward += reward
        steps += 1
        
    print(f"Test run finished. Steps: {steps}, Total Reward: {total_reward:.2f}")
    print(f"Final Info: {info}")


if __name__ == "__main__":
    main()
