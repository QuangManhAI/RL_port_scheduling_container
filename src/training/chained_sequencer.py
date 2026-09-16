#!/usr/bin/env python3
"""Unified Full-Cycle Policy Evaluator for Phase 06 Stage S5.

Executes the complete pick-carry-place cycle in the 18x18m arena using
a SINGLE unified neural network checkpoint (ppo_s5_final.zip).
Zero model-swapping at runtime.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import Dict, List, Optional, Tuple

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    from stable_baselines3 import PPO
except ImportError as e:
    print(f"Error importing stable_baselines3: {e}")
    sys.exit(1)

from src.envs.chained_cycle_env import ChainedCycleEnv


STAGE_NAMES = {
    1: "APPROACH_AND_PICK",
    2: "CARRY_AND_DROPOFF",
    3: "CYCLE_COMPLETE",
}


class UnifiedFullCyclePolicy:
    """Evaluates the single unified neural network checkpoint for the full cycle."""

    def __init__(
        self,
        checkpoint_path: str = "src/training/logs/checkpoints/ppo_s5_final.zip",
        device: str = "cpu",
    ) -> None:
        self.device = device
        print("=== Loading Single Unified Checkpoint for S5 Full Cycle ===")
        print(f"Path: {checkpoint_path}")
        if not os.path.isfile(checkpoint_path):
            raise FileNotFoundError(f"Checkpoint not found at: {checkpoint_path}")
        self.model = PPO.load(checkpoint_path, device=device)
        print("✔ Single unified policy successfully loaded into memory!\n")

    def predict_action(self, obs: np.ndarray, deterministic: bool = True) -> np.ndarray:
        """Predicts action directly from single neural network policy."""
        action, _ = self.model.predict(obs, deterministic=deterministic)
        return action


def run_evaluation(
    episodes: int = 10,
    checkpoint: str = "src/training/logs/checkpoints/ppo_s5_final.zip",
    port: int = 11011,
    device: str = "cpu",
    headless: bool = True,
    connect: bool = False,
    fps: float = 20.0,
    verbose: bool = True,
) -> Tuple[float, List[Dict]]:
    """Runs evaluation of the single unified checkpoint over multiple full cycles."""
    policy = UnifiedFullCyclePolicy(checkpoint_path=checkpoint, device=device)

    if connect:
        print(f">> Connecting to Godot on 127.0.0.1:{port} (F6 running scene)...")
    elif not headless:
        print(f">> Launching Godot in visual window with {fps} FPS pacing...")

    env = ChainedCycleEnv(
        port=port,
        ticks_per_step=4,
        headless=headless,
        autostart=not connect,
    )

    episode_results: List[Dict] = []
    successes = 0
    step_delay = (1.0 / max(1.0, fps)) if not headless else 0.0

    print(f"=== Starting Stage 5 Single-Checkpoint Full-Cycle Evaluation ({episodes} episodes) ===")

    for ep in range(episodes):
        # Force full cycle start (difficulty=1.0)
        obs, info = env.reset(options={"difficulty": 1.0})
        sub_stage = info.get("sub_stage", 1)
        sub_stage_steps: Dict[int, int] = {1: 0, 2: 0}
        total_steps = 0
        total_reward = 0.0
        prev_sub_stage = sub_stage

        ep_start_time = time.time()
        if verbose:
            print(f"\n--- Episode {ep + 1}/{episodes} ---")

        while True:
            action = policy.predict_action(obs, deterministic=True)
            obs, rew, term, trunc, info = env.step(action)
            total_steps += 1
            total_reward += rew

            if step_delay > 0.0:
                time.sleep(step_delay)

            new_sub_stage = info.get("sub_stage", 1)
            if new_sub_stage in sub_stage_steps:
                sub_stage_steps[new_sub_stage] += 1

            if new_sub_stage != prev_sub_stage:
                if verbose:
                    prev_name = STAGE_NAMES.get(prev_sub_stage, str(prev_sub_stage))
                    new_name = STAGE_NAMES.get(new_sub_stage, str(new_sub_stage))
                    print(f"  [Step {total_steps:3d}] Phase Shift: {prev_name} -> {new_name} (took {sub_stage_steps.get(prev_sub_stage, 0)} steps)")
                prev_sub_stage = new_sub_stage
            sub_stage = new_sub_stage

            if term or trunc:
                cycle_success = info.get("cycle_success", False)
                wall_collided = info.get("wall_collided", False)
                ep_duration = time.time() - ep_start_time

                if cycle_success:
                    successes += 1
                    status = "✔ FULL CYCLE COMPLETE"
                elif wall_collided:
                    status = "❌ WALL COLLISION"
                else:
                    status = "⏱ TIMEOUT"

                result = {
                    "episode": ep + 1,
                    "success": cycle_success,
                    "status": status,
                    "total_steps": total_steps,
                    "sub_stage_steps": sub_stage_steps,
                    "reward": total_reward,
                    "duration_sec": ep_duration,
                }
                episode_results.append(result)

                print(
                    f"Ep {ep+1:02d}: {status} | Total Steps: {total_steps:3d} | "
                    f"Pick: {sub_stage_steps.get(1, 0)}s, Drop: {sub_stage_steps.get(2, 0)}s | "
                    f"Reward: {total_reward:+.1f} | Time: {ep_duration:.1f}s"
                )
                break

    env.close()

    success_rate = successes / max(1, episodes)
    print("\n" + "=" * 60)
    print("STAGE 5 UNIFIED SINGLE-CHECKPOINT SUMMARY:")
    print(f"Checkpoint: {checkpoint}")
    print(f"Overall Full-Cycle Success Rate: {success_rate:.1%} ({successes}/{episodes})")
    avg_steps = np.mean([r["total_steps"] for r in episode_results])
    print(f"Average Total Episode Steps: {avg_steps:.1f} steps (~{avg_steps/15.0:.2f}s simulated)")
    for s_idx in [1, 2]:
        s_steps = [r["sub_stage_steps"].get(s_idx, 0) for r in episode_results]
        print(f"  - {STAGE_NAMES[s_idx]}: avg {np.mean(s_steps):.1f} steps")
    print("=" * 60)

    return success_rate, episode_results


def main() -> None:
    parser = argparse.ArgumentParser(description="Unified single-checkpoint full-cycle evaluator.")
    parser.add_argument("--checkpoint", type=str, default="src/training/logs/checkpoints/ppo_s5_final.zip", help="Path to unified checkpoint")
    parser.add_argument("--episodes", type=int, default=10, help="Number of test episodes")
    parser.add_argument("--port", type=int, default=11011, help="TCP port for Godot bridge")
    parser.add_argument("--device", type=str, default="cpu", choices=["auto", "cuda", "cpu"])
    parser.add_argument("--render", action="store_true", help="Launch Godot in visual window for real-time viewing")
    parser.add_argument("--connect", action="store_true", help="Connect to running Godot Editor instance (F6)")
    parser.add_argument("--fps", type=float, default=20.0, help="Actions per second when rendering (default: 20)")
    parser.add_argument("--quiet", action="store_true", help="Quiet mode")

    args = parser.parse_args()
    headless = not (args.render or args.connect)
    run_evaluation(
        episodes=args.episodes,
        checkpoint=args.checkpoint,
        port=args.port,
        device=args.device,
        headless=headless,
        connect=args.connect,
        fps=args.fps,
        verbose=not args.quiet,
    )


if __name__ == "__main__":
    main()
