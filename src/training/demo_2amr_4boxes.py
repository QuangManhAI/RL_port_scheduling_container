#!/usr/bin/env python3
"""Live Demonstration: 2 AMRs dynamically picking and delivering 4 Boxes using S5 Policy."""

from __future__ import annotations

import argparse
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
    parser = argparse.ArgumentParser(description="2 AMRs picking 4 Boxes with S5 policy.")
    parser.add_argument("--s5-model", type=str, default="src/training/logs/checkpoints/ppo_s5_final.zip", help="Path to S5 checkpoint")
    parser.add_argument("--fps", type=float, default=20.0, help="Visual playback FPS (default: 20)")
    parser.add_argument("--port", type=int, default=11099, help="TCP port for Godot bridge")
    parser.add_argument("--episodes", type=int, default=3, help="Number of episodes to run")

    args = parser.parse_args()

    if not os.path.isfile(args.s5_model):
        print(f"Error: S5 model checkpoint not found at: {args.s5_model}")
        sys.exit(1)

    print("=" * 65)
    print("   2 AMRs COOPERATIVE PICK & DROP (4 BOXES)")
    print(f"   Shared Brain: {args.s5_model}")
    print(f"   Visual Pacing: {args.fps} FPS")
    print(f"   Port:          {args.port}")
    print("=" * 65 + "\n")

    print(f">> Loading trained S5 policy from {args.s5_model}...")
    s5_policy = PPO.load(args.s5_model, device="cpu")
    print("✔ S5 Policy successfully loaded!\n")

    print(">> Launching Godot 3D Window...")
    env = MultiAgentGymEnv(
        port=args.port,
        ticks_per_step=4,
        headless=False,
        autostart=True,
        fps=args.fps,
    )

    try:
        for ep in range(1, args.episodes + 1):
            obs, info = env.reset()
            step = 0
            t_start = time.time()

            print(f"\n" + "-" * 55)
            print(f"--- EPISODE {ep}/{args.episodes} STARTED ---")
            print(f"Arena: 4 Boxes placed. Both AMRs launching towards their targets...")
            print("-" * 55)

            prev_deliv = 0

            while True:
                step += 1

                # Extract 13-dim S5 observation for AMR 1 and AMR 2
                obs_1 = obs[0:13]
                obs_2 = obs[13:26]

                # Run inference for each robot through the shared S5 brain
                act_1, _ = s5_policy.predict(obs_1, deterministic=True)
                act_2, _ = s5_policy.predict(obs_2, deterministic=True)

                # Fuse into 6-dim joint action
                joint_action = np.concatenate([act_1, act_2]).astype(np.float32)

                obs, reward, terminated, truncated, info = env.step(joint_action)

                deliv = info.get("delivered_count", 0)
                if deliv > prev_deliv:
                    print(f"  ⭐ [Step {step:3d}] Delivery Event! Box Delivered! (Total: {deliv}/4)")
                    prev_deliv = deliv

                if step % 25 == 0:
                    c1 = "CARRYING" if obs[9] > 0.5 else "SEEKING"
                    c2 = "CARRYING" if obs[22] > 0.5 else "SEEKING"
                    print(f"  Step {step:3d} | AMR-1: {c1} | AMR-2: {c2} | Delivered: {deliv}/4")

                if terminated or truncated:
                    dt = time.time() - t_start
                    if info.get("all_delivered", False):
                        print(f"\n🎉 SUCCESS! ALL 4 BOXES DELIVERED IN {step} STEPS (~{dt:.1f}s)!")
                    else:
                        print(f"\nEpisode finished ({deliv}/4 delivered) in {step} steps.")
                    break

            time.sleep(1.0)

    finally:
        env.close()
        print("\n>> Demonstration complete. Godot closed cleanly.")


if __name__ == "__main__":
    main()
