#!/usr/bin/env python3
"""Stage R2 Test & Evaluation Script with Comprehensive Collision Verification."""

from __future__ import annotations

import os
import sys
import numpy as np

# Add project root to sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from stable_baselines3 import PPO
from src.envs.rack_targeting_gym_env import RackTargetingGymEnv
from src.envs.godot_env_bridge import find_godot_binary


def test_r2_targeting_and_collision():
    print("=" * 68)
    print("  STAGE R2 RE-TEST & COMPREHENSIVE COLLISION INTEGRITY SUITE")
    print("=" * 68)

    # 1. Verify Godot executable exists
    godot_bin = find_godot_binary()
    assert os.path.isfile(godot_bin), f"Godot binary not found: {godot_bin}"
    print(f"✔ Godot Binary: {godot_bin}")

    # 2. Check trained Stage R2 checkpoint
    model_path = "src/training/logs/checkpoints/ppo_r2_final.zip"
    assert os.path.isfile(model_path), f"Checkpoint not found: {model_path}"
    print(f"✔ Stage R2 Model Checkpoint: {model_path}")

    # 3. Load PPO Model
    model = PPO.load(model_path, device="cpu")
    print("✔ PPO Model Loaded Successfully.")

    # 4. Instantiate Gym Environment on isolated test port
    test_port = 11195
    env = RackTargetingGymEnv(
        port=test_port,
        headless=True,
        autostart=True,
    )
    print(f"✔ Environment Connected on TCP Port {test_port} (200Hz sim, 60Hz action).")

    num_episodes = 20
    ik_successes = []
    dock_successes = []
    topple_events = []
    step_counts = []

    try:
        for ep in range(num_episodes):
            obs, info = env.reset(seed=1000 + ep)
            done = False
            ep_steps = 0
            ep_reward = 0.0

            while not done and ep_steps < 300:
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, info = env.step(action)
                ep_reward += reward
                ep_steps += 1
                done = terminated or truncated

            ik_succ = bool(info.get("ik_success", False))
            dock_succ = bool(info.get("docking_success", False))
            toppled = bool(info.get("rack_toppled", False))

            ik_successes.append(ik_succ)
            dock_successes.append(dock_succ)
            topple_events.append(toppled)
            step_counts.append(ep_steps)

            target_tier = info.get("target_tier", "?")
            ik_dist = info.get("ik_dist", 0.0)
            status_str = "SUCCESS" if ik_succ else "FAIL"
            print(
                f"  Episode {ep + 1:2d}/{num_episodes} | "
                f"Tier: {target_tier} | "
                f"Steps: {ep_steps:3d} | "
                f"IK Dist: {ik_dist:.2f}m | "
                f"IK Success: {str(ik_succ):5s} | "
                f"Toppled: {str(toppled):5s} | "
                f"[{status_str}]"
            )

        ik_rate = float(np.mean(ik_successes)) * 100.0
        dock_rate = float(np.mean(dock_successes)) * 100.0
        topple_rate = float(np.mean(topple_events)) * 100.0
        avg_steps = float(np.mean(step_counts))

        print("-" * 68)
        print("  STAGE R2 EVALUATION SUMMARY:")
        print(f"  Arm IK Reachability:  {ik_rate:5.1f}% (Target: >= 90.0%)")
        print(f"  Docking Success Rate: {dock_rate:5.1f}% (Target: >= 90.0%)")
        print(f"  Rack Topple Rate:     {topple_rate:5.1f}% (Target: <= 5.0%)")
        print(f"  Average Steps/Ep:     {avg_steps:5.1f} steps")
        print("-" * 68)

        assert ik_rate >= 90.0, f"Arm IK reachability {ik_rate:.1f}% below 90.0% target"
        assert dock_rate >= 90.0, f"Docking success rate {dock_rate:.1f}% below 90.0% target"
        assert topple_rate <= 5.0, f"Topple rate {topple_rate:.1f}% exceeds 5.0% threshold"

        print("✔ ALL STAGE R2 RE-TEST CRITERIA SATISFIED WITH 100% PASS!")
        print("=" * 68)

    finally:
        env.close()


if __name__ == "__main__":
    test_r2_targeting_and_collision()
