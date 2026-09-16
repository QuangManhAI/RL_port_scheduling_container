#!/usr/bin/env python3
"""View and evaluate trained Multi-Agent RL policy (2 AMRs, 4 Boxes) in Godot 3D."""

from __future__ import annotations

import argparse
import glob
import os
import sys
import time

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    from stable_baselines3 import PPO
except ImportError as e:
    print(f"Error importing stable_baselines3: {e}")
    sys.exit(1)

from src.envs.multi_agent_gym_env import MultiAgentGymEnv


def main() -> None:
    parser = argparse.ArgumentParser(description="View trained MARL policy in Godot 3D.")
    parser.add_argument("--model", type=str, default="", help="Path to trained PPO .zip model")
    parser.add_argument("--fps", type=float, default=30.0, help="Visual playback pacing rate (default: 30 FPS)")
    parser.add_argument("--port", type=int, default=11090, help="TCP port for Godot bridge")
    parser.add_argument("--episodes", type=int, default=5, help="Number of episodes to demonstrate")

    args = parser.parse_args()

    # Find latest checkpoint if not specified
    model_path = args.model
    if not model_path:
        checkpoints = sorted(glob.glob("src/training/logs/checkpoints/marl/*.zip"))
        if checkpoints:
            model_path = checkpoints[-1]
            print(f">> Automatically selected latest checkpoint: {model_path}")
        else:
            print("Error: No MARL checkpoints found in src/training/logs/checkpoints/marl/")
            sys.exit(1)

    print("=" * 65)
    print("   MARL DEMO / EVALUATION: 2 AMRs & 4 BOXES")
    print(f"   Model:   {model_path}")
    print(f"   Pacing:  {args.fps} FPS")
    print(f"   Port:    {args.port}")
    print("=" * 65 + "\n")

    env = MultiAgentGymEnv(
        port=args.port,
        ticks_per_step=4,
        headless=False,
        autostart=True,
        fps=args.fps,
    )

    print(f"Loading trained policy from {model_path}...")
    model = PPO.load(model_path, device="cpu")

    try:
        for ep in range(1, args.episodes + 1):
            obs, info = env.reset()
            ep_reward = 0.0
            step = 0
            t_start = time.time()

            print(f"\n--- Episode {ep}/{args.episodes} Started ---")

            while True:
                step += 1
                action, _states = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, info = env.step(action)
                ep_reward += reward

                if step % 50 == 0 or terminated or truncated:
                    deliv = info.get("delivered_count", 0)
                    col = info.get("robot_collisions", 0)
                    print(f"Step {step:4d} | Delivered: {deliv}/4 | Collisions: {col:2d} | Reward: {ep_reward:+.1f}")

                if terminated or truncated:
                    all_deliv = info.get("all_delivered", False)
                    mark = "✔ ALL 4 DELIVERED!" if all_deliv else f"Finished ({info.get('delivered_count', 0)}/4)"
                    dt = time.time() - t_start
                    print(f"🏁 Episode {ep} {mark} (Steps: {step}, Time: {dt:.1f}s, Total Reward: {ep_reward:+.1f})")
                    break

        print(f"\nCompleted {args.episodes} demonstration episodes.")
    finally:
        env.close()


if __name__ == "__main__":
    main()
