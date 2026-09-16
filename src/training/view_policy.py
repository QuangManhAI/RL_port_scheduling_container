#!/usr/bin/env python3
"""Interactive visual policy viewer for Godot 4 skill stages.

Supports two modes:
1. Standalone Visual Window (default): Spawns Godot in windowed mode and runs the policy in real-time.
2. Connect to Godot Editor (--connect): Connects to a scene you launched manually via F6 in Godot.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import Any, Dict

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    from stable_baselines3 import PPO
except ImportError:
    print("Error: stable-baselines3 not installed. Please activate .venv.")
    sys.exit(1)

from src.envs.chained_cycle_env import ChainedCycleEnv
from src.envs.dropoff_env import DropoffEnv
from src.envs.navigate_carrying_env import NavigateCarryingEnv
from src.envs.navigate_to_item_env import NavigateToItemEnv
from src.envs.pickup_env import PickupEnv

STAGE_MAP = {
    "s1": (NavigateToItemEnv, "src/training/logs/checkpoints/ppo_s1_final.zip"),
    "navigate_to_item": (NavigateToItemEnv, "src/training/logs/checkpoints/ppo_s1_final.zip"),
    "s2": (PickupEnv, "src/training/logs/checkpoints/ppo_s2_final.zip"),
    "pickup": (PickupEnv, "src/training/logs/checkpoints/ppo_s2_final.zip"),
    "s3": (NavigateCarryingEnv, "src/training/logs/checkpoints/ppo_s3_final.zip"),
    "navigate_carrying": (NavigateCarryingEnv, "src/training/logs/checkpoints/ppo_s3_final.zip"),
    "s4": (DropoffEnv, "src/training/logs/checkpoints/ppo_s4_final.zip"),
    "dropoff": (DropoffEnv, "src/training/logs/checkpoints/ppo_s4_final.zip"),
    "s5": (ChainedCycleEnv, "src/training/logs/checkpoints/ppo_s5_final.zip"),
    "chained_cycle": (ChainedCycleEnv, "src/training/logs/checkpoints/ppo_s5_final.zip"),
}


def main() -> None:
    parser = argparse.ArgumentParser(description="View trained RL agent navigating in Godot.")
    parser.add_argument("--stage", type=str, default="s1", choices=list(STAGE_MAP.keys()), help="Stage to view")
    parser.add_argument("--model", type=str, default="", help="Path to PPO model .zip (defaults to stage final checkpoint)")
    parser.add_argument("--port", type=int, default=11000, help="TCP port for Godot bridge")
    parser.add_argument("--fps", type=float, default=300.0, help="Simulation playback rate (actions per second)")
    parser.add_argument("--connect", action="store_true", help="Connect to already-running Godot Editor instance (F6) instead of spawning a new window")
    parser.add_argument("--episodes", type=int, default=30, help="Number of episodes to run (0 for infinite)")
    parser.add_argument("--difficulty", type=float, default=0, help="Curriculum difficulty (0.0 to 1.0)")

    args = parser.parse_args()

    stage_key = args.stage.lower()
    env_cls, default_model_path = STAGE_MAP[stage_key]
    model_path = args.model if args.model else default_model_path

    if not os.path.isfile(model_path):
        # Check if s1 checkpoint exists as fallback
        s1_fallback = "src/training/logs/checkpoints/ppo_s1_final.zip"
        if os.path.isfile(s1_fallback):
            print(f"Warning: Model '{model_path}' not found, falling back to '{s1_fallback}'")
            model_path = s1_fallback
        else:
            print(f"Error: Model file '{model_path}' does not exist.")
            print("Please train the stage first or specify a valid --model path.")
            sys.exit(1)

    print(f"===========================================================")
    print(f"  Stage:       {stage_key.upper()}")
    print(f"  Model:       {model_path}")
    print(f"  Mode:        {'Connect to open Godot Editor (F6)' if args.connect else 'Spawn new Visual Godot Window'}")
    print(f"  Pacing:      {args.fps} actions/sec (~{1000/args.fps:.0f} ms/step)")
    print(f"  Port:        {args.port}")
    print(f"===========================================================\n")

    if args.connect:
        print(">> Connecting to Godot on 127.0.0.1:%d..." % args.port)
        print(">> Make sure you pressed F6 in Godot to run the scene first!")
    else:
        print(">> Launching Godot in visual window...")

    env = env_cls(
        port=args.port,
        ticks_per_step=4,
        headless=False,
        autostart=not args.connect,
    )

    print(f"Loading trained policy from {model_path}...")
    model = PPO.load(model_path, device="cpu")

    step_delay = 1.0 / max(1.0, args.fps)
    episode_idx = 0

    try:
        while True:
            episode_idx += 1
            if args.episodes > 0 and episode_idx > args.episodes:
                print(f"\nCompleted {args.episodes} demonstration episodes.")
                break

            obs, info = env.reset(options={"difficulty": args.difficulty})
            ep_reward = 0.0
            step = 0
            t_start = time.time()

            print(f"\n--- Episode {episode_idx} Started ---")

            while True:
                step += 1
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, info = env.step(action)
                ep_reward += float(reward)

                dist = info.get("distance_to_box", 0.0)
                v_lin = float(action[0])
                v_ang = float(action[1])
                trig = float(action[2]) if len(action) > 2 else 0.0

                # Live terminal telemetry
                act_str = f"v={v_lin:+.2f}, w={v_ang:+.2f}"
                if len(action) > 2:
                    act_str += f", trig={trig:+.2f}"
                sys.stdout.write(
                    f"\rStep: {step:3d} | Dist to Target: {dist:5.2f}m | Action: [{act_str}] | Ep Reward: {ep_reward:+6.2f}"
                )
                sys.stdout.flush()

                # Real-time pacing for human observation
                time.sleep(step_delay)

                if terminated or truncated:
                    elapsed = time.time() - t_start
                    goal = info.get("goal_reached", False) or info.get("is_picked", False) or info.get("is_placed", False)
                    col = info.get("wall_collided", False)

                    if goal:
                        status_str = "✔ GOAL REACHED!"
                    elif col:
                        status_str = "💥 WALL COLLISION"
                    elif truncated:
                        status_str = "⏱ TIMEOUT"
                    else:
                        status_str = "🏁 EPISODE ENDED"

                    print(f"\n{status_str} (Steps: {step}, Time: {elapsed:.1f}s, Total Reward: {ep_reward:+.2f}, Final Dist: {dist:.2f}m)")

                    # Pause briefly on episode end so user can appreciate the outcome
                    time.sleep(1.0)
                    break

    except KeyboardInterrupt:
        print("\n\nExiting viewer...")
    finally:
        env.close()
        print("Viewer closed.")


if __name__ == "__main__":
    main()
