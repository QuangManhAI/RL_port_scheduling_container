#!/usr/bin/env python3
"""Chained Skill Sequencer Orchestrator for Phase 06 Stage S5.

Composes the graduated modular skill policies:
  - S1: Navigate-to-Item (ppo_s1_final.zip)
  - S2: Pick-Up (ppo_s2_final.zip)
  - S3: Navigate-while-Carrying (ppo_s3_final.zip)
  - S4: Drop-Off (ppo_s4_final.zip)

Executes the full pick-and-place cycle end-to-end in the 18x18m arena.
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
    1: "NAV_TO_ITEM (S1)",
    2: "PICK_UP (S2)",
    3: "NAV_CARRYING (S3)",
    4: "DROP_OFF (S4)",
    5: "CYCLE_COMPLETE",
}


class ChainedSkillSequencer:
    """Orchestrates checkpoint swapping across sub-stages of the full cycle."""

    def __init__(
        self,
        checkpoint_dir: str = "src/training/logs/checkpoints",
        device: str = "cpu",
    ) -> None:
        self.device = device
        print("=== Loading Graduated Skill Checkpoints for S5 Sequencer ===")

        s1_path = os.path.join(checkpoint_dir, "ppo_s1_final.zip")
        s2_path = os.path.join(checkpoint_dir, "ppo_s2_final.zip")
        s3_path = os.path.join(checkpoint_dir, "ppo_s3_final.zip")
        s4_path = os.path.join(checkpoint_dir, "ppo_s4_final.zip")

        print(f"Loading S1: {s1_path}")
        self.model_s1 = PPO.load(s1_path, device=device)
        print(f"Loading S2: {s2_path}")
        self.model_s2 = PPO.load(s2_path, device=device)
        print(f"Loading S3: {s3_path}")
        self.model_s3 = PPO.load(s3_path, device=device)
        print(f"Loading S4: {s4_path}")
        self.model_s4 = PPO.load(s4_path, device=device)
        print("✔ All four skill policies successfully loaded into sequencer memory!\n")

    def predict_action(self, obs: np.ndarray, sub_stage: int, deterministic: bool = True) -> np.ndarray:
        """Selects active policy based on state-machine sub-stage."""
        if sub_stage == 1:
            action, _ = self.model_s1.predict(obs, deterministic=deterministic)
        elif sub_stage == 2:
            action, _ = self.model_s2.predict(obs, deterministic=deterministic)
        elif sub_stage == 3:
            action, _ = self.model_s3.predict(obs, deterministic=deterministic)
        elif sub_stage == 4:
            action, _ = self.model_s4.predict(obs, deterministic=deterministic)
        else:
            action = np.zeros(3, dtype=np.float32)
        return action


def run_evaluation(
    episodes: int = 10,
    port: int = 11011,
    device: str = "cpu",
    verbose: bool = True,
) -> Tuple[float, List[Dict]]:
    """Runs orchestrated evaluation over multiple full cycles."""
    sequencer = ChainedSkillSequencer(device=device)
    env = ChainedCycleEnv(port=port, ticks_per_step=4, headless=True, autostart=True)

    episode_results: List[Dict] = []
    successes = 0

    print(f"=== Starting Stage 5 Chained Full-Cycle Evaluation ({episodes} episodes) ===")

    for ep in range(episodes):
        obs, info = env.reset()
        sub_stage = info.get("sub_stage", 1)
        sub_stage_steps: Dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0}
        total_steps = 0
        total_reward = 0.0
        prev_sub_stage = sub_stage

        ep_start_time = time.time()
        if verbose:
            print(f"\n--- Episode {ep + 1}/{episodes} ---")

        while True:
            action = sequencer.predict_action(obs, sub_stage, deterministic=True)
            obs, rew, term, trunc, info = env.step(action)
            total_steps += 1
            total_reward += rew

            new_sub_stage = info.get("sub_stage", 1)
            if new_sub_stage in sub_stage_steps:
                sub_stage_steps[new_sub_stage] += 1

            if new_sub_stage != prev_sub_stage:
                if verbose:
                    prev_name = STAGE_NAMES.get(prev_sub_stage, str(prev_sub_stage))
                    new_name = STAGE_NAMES.get(new_sub_stage, str(new_sub_stage))
                    print(f"  [Step {total_steps:3d}] Transition: {prev_name} -> {new_name} (took {sub_stage_steps.get(prev_sub_stage, 0)} steps)")
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
                    f"S1: {sub_stage_steps[1]}s, S2: {sub_stage_steps[2]}s, S3: {sub_stage_steps[3]}s, S4: {sub_stage_steps[4]}s | "
                    f"Reward: {total_reward:+.1f} | Time: {ep_duration:.1f}s"
                )
                break

    env.close()

    success_rate = successes / max(1, episodes)
    print("\n" + "=" * 60)
    print("STAGE 5 CHAINED FULL-CYCLE SUMMARY:")
    print(f"Overall Full-Cycle Success Rate: {success_rate:.1%} ({successes}/{episodes})")
    avg_steps = np.mean([r["total_steps"] for r in episode_results])
    print(f"Average Total Episode Steps: {avg_steps:.1f} steps")
    for s_idx in [1, 2, 3, 4]:
        s_steps = [r["sub_stage_steps"].get(s_idx, 0) for r in episode_results]
        print(f"  - {STAGE_NAMES[s_idx]}: avg {np.mean(s_steps):.1f} steps")
    print("=" * 60)

    return success_rate, episode_results


def main() -> None:
    parser = argparse.ArgumentParser(description="Chained full-cycle skill sequencer.")
    parser.add_argument("--episodes", type=int, default=10, help="Number of test episodes")
    parser.add_argument("--port", type=int, default=11011, help="TCP port for Godot bridge")
    parser.add_argument("--device", type=str, default="cpu", choices=["auto", "cuda", "cpu"])
    parser.add_argument("--quiet", action="store_true", help="Quiet mode")

    args = parser.parse_args()
    run_evaluation(
        episodes=args.episodes,
        port=args.port,
        device=args.device,
        verbose=not args.quiet,
    )


if __name__ == "__main__":
    main()
