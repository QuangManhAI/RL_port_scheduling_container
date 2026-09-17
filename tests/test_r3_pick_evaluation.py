#!/usr/bin/env python3
"""Stage R3 Evaluation Script: Rack Box Pick & Stow Verification."""

from __future__ import annotations

import os
import sys
import numpy as np

# Add project root to sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from stable_baselines3 import PPO
from src.envs.rack_pick_gym_env import RackPickGymEnv
from src.envs.godot_env_bridge import find_godot_binary


def test_r3_pick_and_stow():
    print("=" * 68)
    print("   STAGE R3: RACK BOX PICK & STOW EVALUATION SUITE")
    print("=" * 68)

    godot_bin = find_godot_binary()
    assert os.path.isfile(godot_bin), f"Godot binary not found: {godot_bin}"
    print(f"✔ Godot Binary: {godot_bin}")

    model_path = "src/training/logs/checkpoints/ppo_r3_final.zip"
    assert os.path.isfile(model_path), f"Checkpoint not found: {model_path}"
    print(f"✔ Stage R3 Model Checkpoint: {model_path}")

    model = PPO.load(model_path, device="cpu")
    print("✔ PPO Model Loaded Successfully.")

    test_port = 11210
    env = RackPickGymEnv(
        port=test_port,
        headless=True,
        autostart=True,
    )
    print(f"✔ Environment Connected on TCP Port {test_port} (200Hz sim, 60Hz action).")

    num_episodes = 20
    pick_successes = []
    stow_successes = []
    topple_events = []
    step_counts = []

    try:
        for ep in range(num_episodes):
            obs, info = env.reset(seed=1000 + ep)
            done = False
            ep_steps = 0
            ep_reward = 0.0

            while not done and ep_steps < 350:
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, info = env.step(action)
                ep_reward += reward
                ep_steps += 1
                done = terminated or truncated

            picked = bool(info.get("is_picked", False))
            stowed = bool(info.get("is_stowed", False))
            toppled = bool(info.get("rack_toppled", False))

            pick_successes.append(picked)
            stow_successes.append(stowed)
            topple_events.append(toppled)
            step_counts.append(ep_steps)

            target_tier = info.get("target_tier", "?")
            ik_dist = info.get("ik_dist", 0.0)
            trig_att = info.get("trigger_attempted", False)
            status_str = "SUCCESS" if stowed else ("PICKED" if picked else "FAIL")
            print(
                f"  Episode {ep + 1:2d}/{num_episodes} | "
                f"Tier: {target_tier} | "
                f"Steps: {ep_steps:3d} | "
                f"IK Dist: {ik_dist:.2f}m | "
                f"Triggered: {str(trig_att):5s} | "
                f"Picked: {str(picked):5s} | "
                f"Stowed: {str(stowed):5s} | "
                f"Toppled: {str(toppled):5s} | "
                f"[{status_str}]"
            )

        pick_rate = float(np.mean(pick_successes)) * 100.0
        stow_rate = float(np.mean(stow_successes)) * 100.0
        topple_rate = float(np.mean(topple_events)) * 100.0
        avg_steps = float(np.mean(step_counts))

        print("-" * 68)
        print("  STAGE R3 EVALUATION SUMMARY:")
        print(f"  Box Pick Success Rate: {pick_rate:5.1f}% (Target: >= 85.0%)")
        print(f"  Tray Stow Success Rate: {stow_rate:5.1f}% (Target: >= 85.0%)")
        print(f"  Rack Topple Rate:       {topple_rate:5.1f}% (Target: <= 5.0%)")
        print(f"  Average Steps/Ep:       {avg_steps:5.1f} steps")
        print("-" * 68)

        assert stow_rate >= 85.0, f"Stow rate {stow_rate:.1f}% below 85.0% target"
        assert topple_rate <= 5.0, f"Topple rate {topple_rate:.1f}% exceeds 5.0% threshold"

        print("✔ ALL STAGE R3 RE-TEST CRITERIA SATISFIED!")
        print("=" * 68)

    finally:
        env.close()


if __name__ == "__main__":
    test_r3_pick_and_stow()
