#!/usr/bin/env python3
"""Stage R4 Extended Delivery Benchmark: Manifest-Driven Multi-Box Transport.

Verifies:
  1. The robot receives a multi-box delivery manifest (e.g., [box_a, box_b, ...]).
  2. The robot executes round-trip cycles across the warehouse bay:
     - Bay -> Rack -> IK Dock & Pick -> Dynamic Stow -> Bay -> Conveyor -> Dynamic Unstow & Place
     - Auto-chains back to Rack for the next box in the manifest.
  3. The robot DOES NOT terminate after delivering just one box.
  4. The robot terminates ONLY when the delivery manifest is completely empty.
  5. Invariants: 0 dropped boxes, 0 topples, CargoTray rigidly attached at all times.
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


def run_extended_delivery_benchmark(
    episodes: int = 10,
    manifest_len: int = 2,
    port: int = 11245,
    device: str = "cpu",
    headless: bool = True,
    seed_offset: int = 4000,
    verbose: bool = True,
) -> Tuple[float, List[Dict[str, Any]]]:
    """Runs deterministic extended multi-box round-trip delivery benchmark."""
    sequencer = RackCycleSequencer(device=device)

    env = RackCycleGymEnv(
        port=port,
        ticks_per_step=4,
        headless=headless,
        autostart=True,
    )

    episode_results: List[Dict[str, Any]] = []
    manifest_successes = 0
    tray_detachment_events = 0
    topple_events = 0
    drop_events = 0

    print("=" * 76)
    print(f"   STAGE R4: EXTENDED DELIVERY BENCHMARK ({episodes} Episodes, {manifest_len} Boxes/Ep)")
    print(f"   Requirement: Deliver ALL boxes in manifest before terminating")
    print(f"   Base TCP Port: {port} | Headless: {headless}")
    print("=" * 76 + "\n")

    for ep in range(episodes):
        ep_seed = seed_offset + ep
        # Generate deterministic multi-box manifest for this episode
        rng = np.random.RandomState(ep_seed)
        boxes_manifest = rng.choice(8, size=manifest_len, replace=False).tolist()

        obs, info = env.reset(seed=ep_seed, options={"manifest": boxes_manifest, "difficulty": 0.5})

        sub_stage = int(info.get("current_sub_stage", 1))
        prev_sub_stage = sub_stage
        total_steps = 0
        total_reward = 0.0
        tray_ever_detached = False
        initial_manifest_size = len(boxes_manifest)

        if verbose:
            print(f"--- Episode {ep + 1}/{episodes} [Seed {ep_seed}] Manifest: {boxes_manifest} ({initial_manifest_size} boxes) ---")

        while True:
            # Rigid attachment invariant
            if not bool(info.get("cargo_tray_attached", True)):
                tray_ever_detached = True

            action = sequencer.predict_action(obs, info, deterministic=True)
            obs, rew, term, trunc, info = env.step(action)
            total_steps += 1
            total_reward += rew

            new_sub_stage = int(info.get("current_sub_stage", 1))
            if new_sub_stage != prev_sub_stage:
                if verbose:
                    p_name = SUB_STAGE_NAMES.get(prev_sub_stage, str(prev_sub_stage))
                    n_name = SUB_STAGE_NAMES.get(new_sub_stage, str(new_sub_stage))
                    rem = int(info.get("delivery_manifest_remaining", 0))
                    placed = int(info.get("total_placed_boxes", 0))
                    print(f"  [Step {total_steps:4d}] Phase: {p_name} -> {n_name} | Placed: {placed} | Remaining in Manifest: {rem}")
                prev_sub_stage = new_sub_stage

            if term or trunc:
                success = bool(info.get("cycle_success", False))
                placed_total = int(info.get("total_placed_boxes", 0))
                manifest_rem = int(info.get("delivery_manifest_remaining", -1))
                is_empty = bool(info.get("is_manifest_empty", False))
                toppled = bool(info.get("rack_toppled", False))
                dropped = bool(info.get("box_dropped", False))
                all_transported = bool(info.get("all_boxes_transported", False))

                if tray_ever_detached:
                    tray_detachment_events += 1
                if toppled:
                    topple_events += 1
                if dropped:
                    drop_events += 1

                # Episode is ONLY successful if manifest is completely empty and all boxes delivered
                is_complete_success = (
                    success
                    and is_empty
                    and manifest_rem == 0
                    and placed_total >= initial_manifest_size
                    and not tray_ever_detached
                    and not toppled
                    and not dropped
                )

                if is_complete_success:
                    manifest_successes += 1
                    status = f"✔ ALL {placed_total}/{initial_manifest_size} BOXES DELIVERED"
                elif trunc:
                    status = f"⏱ TIMEOUT (Placed {placed_total}/{initial_manifest_size})"
                elif toppled:
                    status = "❌ RACK TOPPLED"
                elif dropped:
                    status = "❌ BOX DROPPED"
                else:
                    status = f"❌ PREMATURE TERMINATION (Manifest remaining: {manifest_rem})"

                result = {
                    "episode": ep + 1,
                    "seed": ep_seed,
                    "manifest": boxes_manifest,
                    "placed_total": placed_total,
                    "manifest_rem": manifest_rem,
                    "is_manifest_empty": is_empty,
                    "cycle_success": success,
                    "all_transported": all_transported,
                    "tray_detached": tray_ever_detached,
                    "toppled": toppled,
                    "dropped": dropped,
                    "steps": total_steps,
                    "reward": total_reward,
                    "status": status,
                }
                episode_results.append(result)

                if verbose:
                    print(
                        f"Ep {ep + 1:02d}: {status} | Placed: {placed_total}/{initial_manifest_size} | "
                        f"Steps: {total_steps:4d} | Reward: {total_reward:+.1f}\n"
                    )
                break

    env.close()

    success_rate = (manifest_successes / max(1, episodes)) * 100.0
    print("=" * 76)
    print("   STAGE R4 EXTENDED DELIVERY BENCHMARK SUMMARY")
    print(f"   Total Episodes:               {episodes}")
    print(f"   Manifest Completion Rate:     {manifest_successes}/{episodes} ({success_rate:5.1f}%) [Target: 100.0%]")
    print(f"   Tray Detachment Incidents:    {tray_detachment_events}")
    print(f"   Rack Topple Events:           {topple_events}")
    print(f"   Dropped Box Events:           {drop_events}")
    print("=" * 76)

    return success_rate, episode_results


def test_r4_extended_delivery_manifest():
    """Pytest test case executing extended manifest delivery."""
    godot_bin = find_godot_binary()
    assert os.path.isfile(godot_bin), f"Godot binary not found: {godot_bin}"

    # Run 5 episodes with 2-box round trips
    success_rate, results = run_extended_delivery_benchmark(
        episodes=5,
        manifest_len=2,
        port=11250,
        headless=True,
        seed_offset=5000,
        verbose=True,
    )

    assert success_rate >= 80.0, f"Extended delivery success rate {success_rate:.1f}% below 80.0% target"
    for r in results:
        assert not r["tray_detached"], f"Ep {r['episode']}: CargoTray detached during transport!"
        assert not r["dropped"], f"Ep {r['episode']}: Box fell through floor!"
        assert not r["toppled"], f"Ep {r['episode']}: Rack toppled!"
        if r["cycle_success"]:
            assert r["is_manifest_empty"], f"Ep {r['episode']}: Terminated while manifest was not empty!"
            assert r["placed_total"] >= len(r["manifest"]), f"Ep {r['episode']}: Placed count < manifest count!"


if __name__ == "__main__":
    test_r4_extended_delivery_manifest()
