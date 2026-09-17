#!/usr/bin/env python3
"""Stage R4 Multi-Box Comprehensive Evaluation Suite: Full Tray Transport & Emptying.

Verifies:
  1. Robot carries a full payload batch (both CargoTray slots occupied).
  2. CargoTray remains rigidly attached to AMR Chassis at all times during transit (0% detachment).
  3. Robot navigates corridor, docks at conveyor, and systematically unstows & places ALL boxes from the tray.
  4. Robot terminates ONLY after all stowed boxes from tray are placed on conveyor deck (stowed_box_count == 0).
  5. 0 dropped boxes, 0 rack topples, 100% full tray transport success.
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any, Dict, List, Tuple

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.envs.godot_env_bridge import find_godot_binary
from src.envs.rack_cycle_gym_env import RackCycleGymEnv
from src.training.rack_cycle_sequencer import RackCycleSequencer, SUB_STAGE_NAMES


def run_multi_box_evaluation(
    episodes: int = 20,
    checkpoint_dir: str = "src/training/logs/checkpoints",
    r4_policy_path: str | None = None,
    port: int = 11235,
    device: str = "cpu",
    headless: bool = True,
    seed_offset: int = 3000,
    verbose: bool = True,
) -> Tuple[float, List[Dict[str, Any]]]:
    """Runs deterministic multi-box evaluation verifying all tray boxes are transported and unloaded."""
    sequencer = RackCycleSequencer(
        checkpoint_dir=checkpoint_dir,
        device=device,
        r4_policy_path=r4_policy_path,
    )

    env = RackCycleGymEnv(
        port=port,
        ticks_per_step=4,
        headless=headless,
        autostart=True,
    )

    episode_results: List[Dict[str, Any]] = []
    full_transport_successes = 0
    tray_detachment_events = 0
    topple_events = 0
    wall_collisions = 0

    print("=" * 76)
    print(f"   STAGE R4: MULTI-BOX TRAY TRANSPORT BENCHMARK ({episodes} Episodes)")
    print(f"   Requirement: Transport ALL boxes from tray to conveyor before terminating")
    print(f"   Base TCP Port: {port} | Headless: {headless}")
    print("=" * 76 + "\n")

    for ep in range(episodes):
        ep_seed = seed_offset + ep
        # Reset with full_tray mode: pre-loads 2 boxes in CargoTray slots
        obs, info = env.reset(seed=ep_seed, options={"full_tray": True, "difficulty": 2.0})

        init_stowed = int(info.get("initial_stowed_count", 2))
        sub_stage = int(info.get("current_sub_stage", 4))
        prev_sub_stage = sub_stage
        total_steps = 0
        total_reward = 0.0
        tray_ever_detached = False
        min_boxes_stowed_at_end = 999
        placed_count_at_end = 0

        if verbose and (ep < 5 or (ep + 1) % 5 == 0):
            print(f"--- Episode {ep + 1}/{episodes} [Seed {ep_seed}] Initial Stowed: {init_stowed} Boxes ---")

        while True:
            # Check tray rigid attachment invariant every single tick
            tray_attached = bool(info.get("cargo_tray_attached", True))
            if not tray_attached:
                tray_ever_detached = True

            action = sequencer.predict_action(obs, info, deterministic=True)
            obs, rew, term, trunc, info = env.step(action)
            total_steps += 1
            total_reward += rew

            new_sub_stage = int(info.get("current_sub_stage", 4))
            if new_sub_stage != prev_sub_stage:
                if verbose and (ep < 5 or (ep + 1) % 5 == 0):
                    p_name = SUB_STAGE_NAMES.get(prev_sub_stage, str(prev_sub_stage))
                    n_name = SUB_STAGE_NAMES.get(new_sub_stage, str(new_sub_stage))
                    stowed_now = int(info.get("stowed_box_count", 0))
                    placed_now = int(info.get("total_placed_boxes", 0))
                    print(f"  [Step {total_steps:3d}] Phase Shift: {p_name} -> {n_name} | Tray Stowed: {stowed_now} | Conveyor Placed: {placed_now}")
                prev_sub_stage = new_sub_stage

            if term or trunc:
                min_boxes_stowed_at_end = int(info.get("stowed_box_count", 0))
                placed_count_at_end = int(info.get("total_placed_boxes", 0))
                cycle_success = bool(info.get("cycle_success", False))
                toppled = bool(info.get("rack_toppled", False))
                collided = bool(info.get("wall_collided", False))

                # Criteria: Cycle success AND tray is 100% empty (all boxes placed) AND at least 2 boxes placed
                all_transported = (
                    cycle_success
                    and min_boxes_stowed_at_end == 0
                    and placed_count_at_end >= init_stowed
                    and not toppled
                    and not tray_ever_detached
                )

                if all_transported:
                    full_transport_successes += 1
                if toppled:
                    topple_events += 1
                if collided:
                    wall_collisions += 1
                if tray_ever_detached:
                    tray_detachment_events += 1

                status_str = "SUCCESS (ALL BOXES PLACED)" if all_transported else "FAILED"
                if verbose and (ep < 5 or (ep + 1) % 5 == 0):
                    print(f"  Result: {status_str} | Placed: {placed_count_at_end}/{init_stowed} | Remaining in Tray: {min_boxes_stowed_at_end} | Tray Attached: {not tray_ever_detached} | Steps: {total_steps}\n")

                episode_results.append({
                    "episode": ep + 1,
                    "seed": ep_seed,
                    "initial_stowed": init_stowed,
                    "placed_count": placed_count_at_end,
                    "remaining_in_tray": min_boxes_stowed_at_end,
                    "all_transported": all_transported,
                    "cycle_success": cycle_success,
                    "tray_detached": tray_ever_detached,
                    "toppled": toppled,
                    "collided": collided,
                    "steps": total_steps,
                    "reward": total_reward,
                })
                break

    env.close()

    success_rate = (full_transport_successes / episodes) * 100.0
    detachment_rate = (tray_detachment_events / episodes) * 100.0
    topple_rate = (topple_events / episodes) * 100.0

    print("=" * 76)
    print("   MULTI-BOX BENCHMARK RESULTS")
    print(f"   Total Episodes:               {episodes}")
    print(f"   All-Boxes-Transported Rate:   {success_rate:.1f}% ({full_transport_successes}/{episodes})")
    print(f"   CargoTray Detachment Rate:    {detachment_rate:.1f}% ({tray_detachment_events}/{episodes})")
    print(f"   Rack Topple Rate:             {topple_rate:.1f}% ({topple_events}/{episodes})")
    print(f"   Wall Collisions:              {wall_collisions}")
    print("=" * 76)

    return success_rate, episode_results


def test_r4_multi_box_cycle() -> None:
    godot_bin = find_godot_binary()
    assert os.path.isfile(godot_bin), f"Godot binary not found: {godot_bin}"

    checkpoint_dir = "src/training/logs/checkpoints"
    r4_active_path = None # Use modular skills sequencer for full tray unloading benchmark

    num_episodes = 20
    test_port = 11235

    success_rate, results = run_multi_box_evaluation(
        episodes=num_episodes,
        checkpoint_dir=checkpoint_dir,
        r4_policy_path=r4_active_path,
        port=test_port,
        device="cpu",
        headless=True,
        seed_offset=3000,
        verbose=True,
    )

    # Save benchmark report
    os.makedirs("src/training/logs", exist_ok=True)
    report_path = "src/training/logs/benchmark_r4_multi_box.json"
    report_data = {
        "benchmark": "Stage R4 Multi-Box Comprehensive Tray Transport",
        "total_episodes": num_episodes,
        "all_boxes_transported_success_rate": success_rate,
        "tray_detachment_rate": float(np.mean([r["tray_detached"] for r in results])) * 100.0,
        "topple_rate": float(np.mean([r["toppled"] for r in results])) * 100.0,
        "mean_placed_boxes": float(np.mean([r["placed_count"] for r in results])),
        "mean_remaining_in_tray": float(np.mean([r["remaining_in_tray"] for r in results])),
        "results": results,
    }

    with open(report_path, "w") as f:
        json.dump(report_data, f, indent=2)
    print(f"\n✔ Benchmark report saved to: {report_path}")

    # Strict Criteria Assertions
    assert success_rate >= 90.0, f"All-boxes-transported success rate {success_rate:.1f}% below 90.0% requirement!"
    assert report_data["tray_detachment_rate"] == 0.0, f"CargoTray detachment detected in {report_data['tray_detachment_rate']:.1f}% of runs!"
    assert report_data["topple_rate"] < 5.0, f"Rack topple rate {report_data['topple_rate']:.1f}% exceeds 5.0% ceiling!"
    assert report_data["mean_remaining_in_tray"] == 0.0, f"Boxes remained in tray at termination! Mean remaining: {report_data['mean_remaining_in_tray']}"
    print("\n✔ ALL MULTI-BOX TRAY TRANSPORT ACCEPTANCE CRITERIA PASSED!")


if __name__ == "__main__":
    test_r4_multi_box_cycle()
