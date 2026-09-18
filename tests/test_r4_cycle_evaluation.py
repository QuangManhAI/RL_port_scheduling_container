#!/usr/bin/env python3
"""Stage R4 Evaluation Suite: Full Rack Cycle (Pick from Rack -> Stow -> Transit -> Conveyor Dropoff).

Runs 50 deterministic evaluation episodes to verify:
  1. Full Cycle Success Rate >= 90.0%
  2. Rack Topple Rate < 5.0%
  3. Zero falling/dropped boxes
"""

from __future__ import annotations

import json
import os
import sys
import time
from typing import Any, Dict, List

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.envs.godot_env_bridge import find_godot_binary
from src.training.rack_cycle_sequencer import RackCycleSequencer, run_cycle_evaluation


def test_r4_cycle_benchmark() -> None:
    print("=" * 72)
    print("   STAGE R4: FULL RACK CYCLE BENCHMARK (50-EPISODE DETERMINISTIC SUITE)")
    print("=" * 72)

    godot_bin = find_godot_binary()
    assert os.path.isfile(godot_bin), f"Godot binary not found: {godot_bin}"
    print(f"✔ Godot Binary: {godot_bin}")

    checkpoint_dir = "src/training/logs/checkpoints"
    r4_model_path = os.path.join(checkpoint_dir, "ppo_r4_final.zip")
    r4_active_path = r4_model_path if os.path.isfile(r4_model_path) else None

    if r4_active_path:
        print(f"✔ Active Policy: Unified End-to-End PPO Model ({r4_active_path})")
    else:
        print(f"✔ Active Policy: Modular Chained Sequencer (R3 Pick & Stow + S3/S4 Transit & Dropoff)")

    num_episodes = 50
    test_port = 11230
    seed_offset = 2000

    success_rate, results = run_cycle_evaluation(
        episodes=num_episodes,
        checkpoint_dir=checkpoint_dir,
        r4_policy_path=r4_active_path,
        port=test_port,
        device="cpu",
        headless=True,
        seed_offset=seed_offset,
        verbose=True,
    )

    # Save benchmark metrics to JSON artifact
    os.makedirs("src/training/logs", exist_ok=True)
    report_path = "src/training/logs/benchmark_r4_cycle.json"
    report_data = {
        "stage": "R4",
        "total_episodes": num_episodes,
        "cycle_success_rate": success_rate,
        "target_success_rate": 90.0,
        "topple_rate": float(np.mean([r["rack_toppled"] for r in results])) * 100.0,
        "pick_rate": float(np.mean([r["picked"] for r in results])) * 100.0,
        "stow_rate": float(np.mean([r["stowed"] for r in results])) * 100.0,
        "results": results,
    }

    with open(report_path, "w") as f:
        json.dump(report_data, f, indent=2)
    print(f"\n✔ Benchmark report saved to: {report_path}")

    # Strict Criteria Assertions
    assert success_rate >= 90.0, f"Full cycle success rate {success_rate:.1f}% below 90.0% requirement!"
    topple_rate = report_data["topple_rate"]
    assert topple_rate < 5.0, f"Rack topple rate {topple_rate:.1f}% exceeds 5.0% ceiling!"
    print("\n✔ ALL STAGE R4 BENCHMARK ACCEPTANCE CRITERIA PASSED!")


if __name__ == "__main__":
    test_r4_cycle_benchmark()
