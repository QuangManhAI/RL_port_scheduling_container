#!/usr/bin/env python3
"""Stage 6 (S6) Multi-Agent Awareness PPO Training Runner.

Fine-tunes the S5 policy into S6 by:
1. Warm-starting all navigation, picking, and delivery weights from PPO S5.
2. Expanding the observation space from 13 to 17 dims (+4 teammate relative features).
3. Training with mutual collision penalties and speed incentives.
4. Exporting ppo_s6_policy.json directly for zero-latency native in-engine execution.
"""

from __future__ import annotations

import argparse
import os
import subprocess
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
except ImportError as e:
    print(f"Error importing RL packages: {e}")
    sys.exit(1)

from src.envs.marl_awareness_vec_env import MARLAwarenessVecEnv


class S6LiveCallback(BaseCallback):
    """Logs live S6 training metrics (deliveries, collisions, episode rewards)."""

    def __init__(self, verbose: int = 1) -> None:
        super().__init__(verbose)
        self.episode_count: int = 0
        self.ep_delivered: List[int] = []
        self.ep_collisions: List[int] = []
        self.ep_rewards: List[float] = []
        self._current_ep_reward: float = 0.0

    def _on_step(self) -> bool:
        rewards = self.locals.get("rewards", [0.0])
        dones = self.locals.get("dones", [False])
        infos = self.locals.get("infos", [{}])

        if len(rewards) > 0:
            self._current_ep_reward += float(rewards[0])

        if len(dones) > 0 and dones[0]:
            self.episode_count += 1
            info = infos[0] if len(infos) > 0 else {}
            deliv = int(info.get("delivered_count", 0))
            col = int(info.get("robot_collisions", 0))
            all_deliv = bool(info.get("all_delivered", False))

            self.ep_delivered.append(deliv)
            self.ep_collisions.append(col)
            self.ep_rewards.append(self._current_ep_reward)

            status_mark = "✔ ALL 8 DELIVERED!" if all_deliv else f"Delivered {deliv}/8"
            print(
                f"[S6 Ep {self.episode_count:03d} | Step {self.num_timesteps:6d}] "
                f"{status_mark:<22} | "
                f"Collisions: {col:2d} | "
                f"Reward: {self._current_ep_reward:+6.1f}"
            )
            self._current_ep_reward = 0.0

        return True


def surgery_warm_start_from_s5(s6_model: PPO, s5_path: str, device: str = "cpu") -> None:
    """Copies all S5 weights into S6 policy & value nets and zero-initializes the 4 new teammate inputs."""
    print(f">> Loading S5 checkpoint for warm-start: {s5_path}")
    s5_model = PPO.load(s5_path, device=device)
    s5_sd = s5_model.policy.state_dict()

    with torch.no_grad():
        # 1. Policy net: layer 0 (weight: [64, 17], bias: [64])
        s6_model.policy.mlp_extractor.policy_net[0].weight[:, :13] = s5_sd["mlp_extractor.policy_net.0.weight"]
        s6_model.policy.mlp_extractor.policy_net[0].weight[:, 13:] = 0.0  # Zero out new teammate weights initially
        s6_model.policy.mlp_extractor.policy_net[0].bias.copy_(s5_sd["mlp_extractor.policy_net.0.bias"])

        # Policy net: layer 2 (weight: [64, 64], bias: [64])
        s6_model.policy.mlp_extractor.policy_net[2].weight.copy_(s5_sd["mlp_extractor.policy_net.2.weight"])
        s6_model.policy.mlp_extractor.policy_net[2].bias.copy_(s5_sd["mlp_extractor.policy_net.2.bias"])

        # Action net: (weight: [3, 64], bias: [3])
        s6_model.policy.action_net.weight.copy_(s5_sd["action_net.weight"])
        s6_model.policy.action_net.bias.copy_(s5_sd["action_net.bias"])

        # 2. Value net: layer 0 (weight: [64, 17], bias: [64])
        s6_model.policy.mlp_extractor.value_net[0].weight[:, :13] = s5_sd["mlp_extractor.value_net.0.weight"]
        s6_model.policy.mlp_extractor.value_net[0].weight[:, 13:] = 0.0
        s6_model.policy.mlp_extractor.value_net[0].bias.copy_(s5_sd["mlp_extractor.value_net.0.bias"])

        # Value net: layer 2 (weight: [64, 64], bias: [64])
        s6_model.policy.mlp_extractor.value_net[2].weight.copy_(s5_sd["mlp_extractor.value_net.2.weight"])
        s6_model.policy.mlp_extractor.value_net[2].bias.copy_(s5_sd["mlp_extractor.value_net.2.bias"])

        # Value net: (weight: [1, 64], bias: [1])
        s6_model.policy.value_net.weight.copy_(s5_sd["value_net.weight"])
        s6_model.policy.value_net.bias.copy_(s5_sd["value_net.bias"])

    print(">> Warm-start surgery completed successfully! (S6 starts with 100% of S5 capability)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Stage 6 (S6) Multi-Agent Awareness PPO Training Runner.")
    parser.add_argument("--steps", type=int, default=30000, help="Total training steps (timesteps)")
    parser.add_argument("--port", type=int, default=11060, help="TCP port for Godot bridge")
    parser.add_argument("--lr", type=float, default=1.5e-4, help="PPO fine-tuning learning rate")
    parser.add_argument("--batch-size", type=int, default=64, help="PPO minibatch size")
    parser.add_argument("--n-steps", type=int, default=512, help="PPO rollout steps per environment")
    parser.add_argument("--device", type=str, default="cpu", choices=["auto", "cuda", "cpu"])
    parser.add_argument(
        "--s5-checkpoint",
        type=str,
        default="experiments/checkpoints/ppo_s5_final.zip",
        help="Path to pre-trained S5 checkpoint",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="experiments/checkpoints",
        help="Directory to save S6 checkpoints",
    )
    parser.add_argument(
        "--resume-s6",
        action="store_true",
        help="Resume fine-tuning directly from existing experiments/checkpoints/ppo_s6_final.zip",
    )

    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    print("=" * 70)
    print("   STAGE 6 (S6) MULTI-AGENT AWARENESS PPO FINE-TUNING")
    print("   Target: 2 AMRs, 8 ToteBoxes, Mutual Collision Avoidance & Fast Pacing")
    print(f"   Warm-Start Source: {args.s5_checkpoint}")
    print(f"   Observation Space: 17 continuous dims (13 base + 4 teammate awareness)")
    print(f"   Action Space:      3 continuous dims (v_lin, v_ang, trigger)")
    print(f"   Total Timesteps:   {args.steps} (Rollouts per step: 2 agents parallel)")
    print(f"   Learning Rate:     {args.lr}")
    print("=" * 70 + "\n")

    # Fallback to secondary location if needed
    if not os.path.isfile(args.s5_checkpoint):
        alt_path = "src/training/logs/checkpoints/ppo_s5_final.zip"
        if os.path.isfile(alt_path):
            args.s5_checkpoint = alt_path

    # Instantiate Multi-Agent VecEnv
    print(f">> Launching Headless Godot on TCP port {args.port} with --s6 flag...")
    vec_env = MARLAwarenessVecEnv(
        port=args.port,
        ticks_per_step=4,
        headless=True,
        autostart=True,
    )

    s6_existing = os.path.join(args.output_dir, "ppo_s6_final.zip")
    if args.resume_s6 and os.path.isfile(s6_existing):
        print(f">> Resuming fine-tuning directly from: {s6_existing}")
        model = PPO.load(
            s6_existing,
            env=vec_env,
            learning_rate=args.lr,
            device=args.device,
        )
    else:
        # Instantiate PPO model with 17-dim observation space
        model = PPO(
            policy="MlpPolicy",
            env=vec_env,
            learning_rate=args.lr,
            n_steps=args.n_steps,
            batch_size=args.batch_size,
            n_epochs=10,
            gamma=0.99,
            gae_lambda=0.95,
            clip_range=0.2,
            ent_coef=0.005,
            verbose=0,
            device=args.device,
        )

        # Apply Warm-Start Surgery
        if os.path.isfile(args.s5_checkpoint):
            surgery_warm_start_from_s5(model, args.s5_checkpoint, device=args.device)
        else:
            print(f"Warning: S5 checkpoint not found at {args.s5_checkpoint}. Training from scratch!")

    live_cb = S6LiveCallback()
    save_cb = CheckpointCallback(
        save_freq=max(1024, args.steps // 5),
        save_path=args.output_dir,
        name_prefix="ppo_s6_checkpoint",
    )

    # Train
    start_time = time.time()
    print(f"\n>> Starting S6 fine-tuning for {args.steps} steps...")
    try:
        model.learn(total_timesteps=args.steps, callback=[live_cb, save_cb])
    except KeyboardInterrupt:
        print("\n>> Training interrupted by user.")
    finally:
        elapsed = time.time() - start_time
        final_zip = os.path.join(args.output_dir, "ppo_s6_final.zip")
        model.save(final_zip)
        print(f"\n>> Saved final S6 model to: {final_zip}")
        print(f">> Total Elapsed Time: {elapsed:.1f}s ({args.steps / max(1.0, elapsed):.1f} steps/s)")

        # Export to Godot JSON
        godot_json_out = "godot/models/ppo_s6_policy.json"
        print(f">> Exporting native policy to {godot_json_out}...")
        try:
            subprocess.run(
                [
                    sys.executable,
                    "src/utils/export_policy_to_godot.py",
                    "--model",
                    final_zip,
                    "--output",
                    godot_json_out,
                ],
                check=True,
            )
            print(f">> Successfully exported {godot_json_out}!")
        except Exception as e:
            print(f"Error exporting policy JSON: {e}")

        vec_env.close()
        print(">> Done.")


if __name__ == "__main__":
    main()
