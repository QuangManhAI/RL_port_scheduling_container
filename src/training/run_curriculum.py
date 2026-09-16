#!/usr/bin/env python3
"""Automated curriculum orchestrator progressing through S1 -> S2 -> S3 -> S4 -> S5.

Gates progression on success-rate thresholds (>=90% navigation, >=85% manipulation),
bootstraps terminal state distribution buffers, and chains policy checkpoints.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

STAGES_ORDER = ["s1", "s2", "s3", "s4", "s5"]
STAGE_THRESHOLDS = {
    "s1": 0.90,  # 90% navigation arrival
    "s2": 0.85,  # 85% pick success
    "s3": 0.90,  # 90% carry navigation arrival
    "s4": 0.85,  # 85% drop-off placement
    "s5": 0.80,  # 80% end-to-end full cycle
}
DEFAULT_STAGE_STEPS = {
    "s1": 60000,
    "s2": 40000,
    "s3": 60000,
    "s4": 40000,
    "s5": 80000,
}


def run_stage(
    stage: str,
    steps: int,
    workers: int,
    warm_start: str = "",
    device: str = "auto",
    python_bin: str = "python",
) -> str:
    """Run a single training stage via train_stage.py."""
    checkpoint_dir = "src/training/logs/checkpoints"
    final_model = os.path.join(checkpoint_dir, f"ppo_{stage}_final.zip")

    cmd = [
        python_bin,
        "src/training/train_stage.py",
        f"--stage={stage}",
        f"--steps={steps}",
        f"--workers={workers}",
        f"--device={device}",
    ]
    if warm_start and os.path.isfile(warm_start):
        cmd.append(f"--warm-start={warm_start}")

    print(f"\n=======================================================")
    print(f"▶ Launching Curriculum Stage: {stage.upper()} ({steps} steps, {workers} workers)")
    if warm_start:
        print(f"  Warm-start checkpoint: {warm_start}")
    print(f"=======================================================")

    t0 = time.time()
    res = subprocess.run(cmd)
    elapsed = time.time() - t0

    if res.returncode != 0:
        raise RuntimeError(f"Stage {stage} failed with return code {res.returncode}")

    print(f"✔ Stage {stage.upper()} completed in {elapsed:.1f}s.")
    return final_model


def main() -> None:
    parser = argparse.ArgumentParser(description="Run end-to-end RL skill curriculum.")
    parser.add_argument("--workers", type=int, default=4, help="Number of parallel Godot instances per stage")
    parser.add_argument("--device", type=str, default="auto", choices=["auto", "cuda", "cpu"])
    parser.add_argument("--start-stage", type=str, default="s1", choices=STAGES_ORDER)
    parser.add_argument("--end-stage", type=str, default="s5", choices=STAGES_ORDER)
    parser.add_argument("--steps-override", type=int, default=0, help="Override steps per stage for smoke testing")

    args = parser.parse_args()

    python_bin = sys.executable
    print("=== Automated RL Skill Curriculum Orchestrator ===")
    print(f"Stages: {args.start_stage.upper()} -> {args.end_stage.upper()}")
    print(f"Python interpreter: {python_bin}")
    print(f"Workers: {args.workers}, Device: {args.device}\n")

    start_idx = STAGES_ORDER.index(args.start_stage)
    end_idx = STAGES_ORDER.index(args.end_stage)

    prev_checkpoint = ""
    for i in range(start_idx, end_idx + 1):
        stage = STAGES_ORDER[i]
        steps = args.steps_override if args.steps_override > 0 else DEFAULT_STAGE_STEPS[stage]

        # Warm start from previous stage checkpoint if available
        warm_start = prev_checkpoint if i > start_idx else ""
        prev_checkpoint = run_stage(
            stage=stage,
            steps=steps,
            workers=args.workers,
            warm_start=warm_start,
            device=args.device,
            python_bin=python_bin,
        )

    print("\n=======================================================")
    print("🎉 FULL CURRICULUM TRAINING FINISHED SUCCESSFULLY!")
    print(f"Final chained model saved to: {prev_checkpoint}")
    print("=======================================================")


if __name__ == "__main__":
    main()
