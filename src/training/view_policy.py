#!/usr/bin/env python3
"""Interactive visual policy viewer for Godot 4 skill stages.

Supports:
1. Standalone Visual Window (default): Spawns Godot in windowed mode and runs policy in real-time.
2. Connect to Godot Editor (--connect): Connects to a scene you launched manually via F6 in Godot.
3. Native In-Engine AI (--native): Spawns Godot running native decoupled in-engine neural inference.
4. Stage R4 Multi-Box & Manifest Transport: Supports --manifest, --delivery-count, --full-tray, --multi-box, and --sequencer.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import Any, Dict, List, Optional

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    from stable_baselines3 import PPO
except ImportError:
    print("Error: stable-baselines3 not installed. Please activate .venv.")
    sys.exit(1)

from src.envs.chained_cycle_env import ChainedCycleEnv
from src.envs.dropoff_env import DropoffEnv
from src.envs.navigate_carrying_env import NavigateCarryingEnv
from src.envs.navigate_to_item_env import NavigateToItemEnv
from src.envs.pickup_env import PickupEnv
from src.envs.rack_docking_gym_env import RackDockingGymEnv
from src.envs.rack_targeting_gym_env import RackTargetingGymEnv
from src.envs.rack_pick_gym_env import RackPickGymEnv
from src.envs.rack_cycle_gym_env import RackCycleGymEnv
from src.training.rack_cycle_sequencer import RackCycleSequencer, SUB_STAGE_NAMES
from src.utils.config_loader import get_clock_config

STAGE_MAP = {
    "s1": (NavigateToItemEnv, "src/training/logs/checkpoints/ppo_s1_final.zip"),
    "navigate_to_item": (NavigateToItemEnv, "src/training/logs/checkpoints/ppo_s1_final.zip"),
    "s2": (PickupEnv, "src/training/logs/checkpoints/ppo_s2_final.zip"),
    "pickup": (PickupEnv, "src/training/logs/checkpoints/ppo_s2_final.zip"),
    "s3": (NavigateCarryingEnv, "src/training/logs/checkpoints/ppo_s3_final.zip"),
    "navigate_carrying": (NavigateCarryingEnv, "src/training/logs/checkpoints/ppo_s3_final.zip"),
    "s4": (DropoffEnv, "src/training/logs/checkpoints/ppo_s4_final.zip"),
    "dropoff": (DropoffEnv, "src/training/logs/checkpoints/ppo_s4_final.zip"),
    "s5": (ChainedCycleEnv, "src/training/logs/checkpoints/ppo_s5_final.zip"),
    "chained_cycle": (ChainedCycleEnv, "src/training/logs/checkpoints/ppo_s5_final.zip"),
    "r1": (RackDockingGymEnv, "src/training/logs/checkpoints/ppo_r1_final.zip"),
    "rack_docking": (RackDockingGymEnv, "src/training/logs/checkpoints/ppo_r1_final.zip"),
    "r2": (RackTargetingGymEnv, "src/training/logs/checkpoints/ppo_r2_final.zip"),
    "rack_targeting": (RackTargetingGymEnv, "src/training/logs/checkpoints/ppo_r2_final.zip"),
    "r3": (RackPickGymEnv, "src/training/logs/checkpoints/ppo_r3_final.zip"),
    "rack_pick": (RackPickGymEnv, "src/training/logs/checkpoints/ppo_r3_final.zip"),
    "r4": (RackCycleGymEnv, "src/training/logs/checkpoints/ppo_r4_final.zip"),
    "rack_cycle": (RackCycleGymEnv, "src/training/logs/checkpoints/ppo_r4_final.zip"),
}


def main() -> None:
    clock_cfg = get_clock_config()
    def_physics_fps = int(clock_cfg.get("physics_fps"))
    def_action_fps = float(clock_cfg.get("action_fps"))

    parser = argparse.ArgumentParser(description="View trained RL agent navigating in Godot.")
    parser.add_argument("--stage", type=str, default="r4", choices=list(STAGE_MAP.keys()), help="Stage to view (default: r4)")
    parser.add_argument("--model", type=str, default="", help="Path to PPO model .zip (defaults to stage final checkpoint)")
    parser.add_argument("--port", type=int, default=11000, help="TCP port for Godot bridge")
    parser.add_argument("--physics-fps", type=int, default=def_physics_fps, help=f"Simulation physics clock rate in Hz (default: {def_physics_fps})")
    parser.add_argument("--action-fps", type=float, default=def_action_fps, help=f"Action decision clock rate in Hz (default: {def_action_fps})")
    parser.add_argument("--native", action="store_true", help="Run 100%% native in-engine AI (zero Python TCP overhead, dual-clock decoupled)")
    parser.add_argument("--connect", action="store_true", help="Connect to already-running Godot Editor instance (F6) instead of spawning a new window")
    parser.add_argument("--episodes", type=int, default=10, help="Number of episodes to run (0 for infinite)")
    parser.add_argument("--difficulty", type=float, default=0.5, help="Curriculum difficulty (0.0 to 1.0)")

    # Extended Stage R4 Transport Options
    parser.add_argument("--manifest", type=str, default="", help="Comma-separated box indices to deliver for R4 (e.g., '0,2,5')")
    parser.add_argument("--delivery-count", type=int, default=0, help="Number of random boxes to deliver in R4 manifest (0 uses default)")
    parser.add_argument("--multi-box", action="store_true", help="Enable multi-box delivery manifest for Stage R4")
    parser.add_argument("--full-tray", action="store_true", help="Pre-stow 2 boxes in CargoTray for immediate transit")
    parser.add_argument("--sequencer", action="store_true", help="Force modular RackCycleSequencer orchestration for Stage R4")
    parser.add_argument("--dispatch-strategy", type=str, default="auto", choices=["auto", "batch", "immediate"], help="Dispatch strategy for R4 tray fill vs delivery decision (auto: cost-benefit evaluation, batch: fill tray, immediate: single box)")

    args = parser.parse_args()

    stage_key = args.stage.lower()
    env_cls, default_model_path = STAGE_MAP[stage_key]
    model_path = args.model if args.model else default_model_path
    action_hz = args.action_fps

    if args.native:
        from src.envs.godot_env_bridge import find_godot_binary
        import subprocess
        godot_bin = find_godot_binary()
        proj_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        godot_proj = os.path.join(proj_root, "godot")
        if stage_key in ("r4", "rack_cycle"):
            scene = "res://scenes/training/training_rack_cycle.tscn"
        elif stage_key in ("r3", "rack_pick"):
            scene = "res://scenes/training/training_rack_pick.tscn"
        elif stage_key in ("r2", "rack_targeting"):
            scene = "res://scenes/training/training_rack_targeting.tscn"
        elif "r" in stage_key:
            scene = "res://scenes/training/training_rack_docking.tscn"
        else:
            scene = "res://scenes/training/multi_agent_arena.tscn"

        print("===========================================================")
        print("  MODE: Native Dual-Clock In-Engine AI")
        print(f"  Simulation Speed (Physics):  {args.physics_fps} Hz")
        print(f"  Action Decision Clock:       {int(action_hz)} Hz")
        print("  Render Clock:                Monitor Refresh Rate (Decoupled)")
        print(f"  Scene:                       {scene}")
        print("===========================================================\n")
        cmd = [
            godot_bin,
            "--path",
            godot_proj,
            scene,
            "--native-ai",
            f"--physics_hz={args.physics_fps}",
            f"--action_hz={int(action_hz)}",
            "--fixed-fps",
            str(args.physics_fps),
            "--max-fps",
            "0",
            "--disable-vsync",
        ]
        subprocess.run(cmd)
        return

    is_r4 = stage_key in ("r4", "rack_cycle")
    use_sequencer = False
    sequencer: Optional[RackCycleSequencer] = None
    model: Optional[PPO] = None

    if is_r4:
        user_specified_model = bool(args.model and os.path.isfile(args.model))
        if user_specified_model and not args.sequencer:
            print(f">> Loading User-Specified PPO Model: {args.model}")
            model = PPO.load(args.model, device="cpu")
        else:
            use_sequencer = True
            sequencer = RackCycleSequencer(r4_policy_path=None)
            print(">> Stage R4 Modular Sequencer Active (Reliable Multi-Box Chained Skills)")
    else:
        if not os.path.isfile(model_path):
            s1_fallback = "src/training/logs/checkpoints/ppo_s1_final.zip"
            if os.path.isfile(s1_fallback):
                print(f"Warning: Model '{model_path}' not found, falling back to '{s1_fallback}'")
                model_path = s1_fallback
            else:
                print(f"Error: Model file '{model_path}' does not exist.")
                sys.exit(1)
        model = PPO.load(model_path, device="cpu")

    print(f"===========================================================")
    print(f"  Stage:                       {stage_key.upper()}")
    print(f"  Policy Engine:               {'Modular RackCycleSequencer' if use_sequencer else model_path}")
    print(f"  Mode:                        {'Connect to open Godot Editor (F6)' if args.connect else 'Spawn new Visual Godot Window'}")
    print(f"  Simulation Clock (Physics):  {args.physics_fps} Hz")
    print(f"  Action Decision Clock:       {action_hz:.1f} Hz")
    print(f"  Dispatch Strategy:           {args.dispatch_strategy.upper()}")
    print(f"  Port:                        {args.port}")
    print(f"===========================================================\n")

    if args.connect:
        print(f">> Connecting to Godot on 127.0.0.1:{args.port}...")
        print(">> Make sure you pressed F6 in Godot to run the scene first!")
    else:
        print(">> Launching Godot in visual window...")

    env = env_cls(
        port=args.port,
        ticks_per_step=4,
        physics_hz=args.physics_fps,
        action_hz=int(action_hz),
        headless=False,
        autostart=not args.connect,
    )

    # Build reset options
    reset_options: Dict[str, Any] = {"difficulty": args.difficulty, "dispatch_strategy": args.dispatch_strategy}
    if args.manifest:
        reset_options["manifest"] = [int(x.strip()) for x in args.manifest.split(",") if x.strip().isdigit()]
    if args.delivery_count > 0:
        reset_options["delivery_count"] = args.delivery_count
    if args.full_tray:
        reset_options["full_tray"] = True
    if args.multi_box:
        reset_options["multi_box"] = True

    step_interval = 1.0 / max(1.0, action_hz)
    episode_idx = 0

    try:
        while True:
            episode_idx += 1
            if args.episodes > 0 and episode_idx > args.episodes:
                print(f"\nCompleted {args.episodes} demonstration episodes.")
                break

            obs, info = env.reset(options=reset_options)
            ep_reward = 0.0
            step = 0
            t_start = time.time()

            man_init = info.get("delivery_manifest", [])
            man_str = f" | Manifest: {man_init}" if man_init else ""
            print(f"\n--- Episode {episode_idx} Started{man_str} ---")

            while True:
                step += 1
                if use_sequencer and sequencer is not None:
                    action = sequencer.predict_action(obs, info, deterministic=True)
                else:
                    assert model is not None
                    action, _ = model.predict(obs, deterministic=True)

                obs, reward, terminated, truncated, info = env.step(action)
                ep_reward += float(reward)

                dist = float(info.get("distance_to_box", info.get("dist_to_target", info.get("dist_to_subgoal", 0.0))))
                v_lin = float(action[0])
                v_ang = float(action[1])
                trig = float(action[2]) if len(action) > 2 else 0.0
                act_str = f"v={v_lin:+.2f}, w={v_ang:+.2f}"
                if len(action) > 2:
                    act_str += f", trig={trig:+.2f}"

                # Real-time dashboard telemetry
                sub_stage_id = int(info.get("current_sub_stage", 0))
                phase_name = SUB_STAGE_NAMES.get(sub_stage_id, "")
                if is_r4 and phase_name:
                    placed = int(info.get("total_placed_boxes", 0))
                    rem = int(info.get("delivery_manifest_remaining", 0))
                    line = f"\rStep: {step:4d} | Phase: {phase_name:<17} | Placed: {placed} (Rem: {rem}) | Dist: {dist:4.2f}m | Action: [{act_str}] | Ep Reward: {ep_reward:+6.2f}"
                else:
                    line = f"\rStep: {step:4d} | Dist to Target: {dist:5.2f}m | Action: [{act_str}] | Ep Reward: {ep_reward:+6.2f}"

                sys.stdout.write(line)
                sys.stdout.flush()

                # Real-time pacing for visual display (60 Hz action clock)
                time.sleep(step_interval)

                if terminated or truncated:
                    elapsed = time.time() - t_start
                    cycle_ok = bool(
                        info.get("cycle_success", False)
                        or (info.get("all_boxes_transported", False) and info.get("is_manifest_empty", True))
                    )
                    placed_total = int(info.get("total_placed_boxes", 0))
                    goal = cycle_ok if is_r4 else (
                        info.get("goal_reached", False)
                        or (info.get("is_picked", False) and stage_key in ["r2", "r3"])
                        or info.get("is_placed", False)
                        or info.get("docking_success", False)
                    )
                    if truncated and not cycle_ok:
                        goal = False

                    col = bool(info.get("wall_collided", False))
                    dropped = bool(info.get("box_dropped", False))
                    toppled = bool(info.get("rack_toppled", False))

                    if goal:
                        if is_r4:
                            status_str = f"✔ ALL {placed_total} BOXES DELIVERED SUCCESSFULLY!"
                        else:
                            status_str = "✔ GOAL REACHED!"
                    elif dropped:
                        status_str = "❌ BOX DROPPED / GLITCHED"
                    elif toppled:
                        status_str = "⚠️ RACK TOPPLED"
                    elif col:
                        status_str = "💥 WALL COLLISION"
                    elif truncated:
                        status_str = f"⏱ TIMEOUT (Placed: {placed_total})"
                    else:
                        status_str = "🏁 EPISODE ENDED"

                    print(f"\n{status_str} (Steps: {step}, Time: {elapsed:.1f}s, Total Reward: {ep_reward:+.2f}, Final Dist: {dist:.2f}m)")

                    # Pause briefly between episodes
                    time.sleep(1.2)
                    break

    except KeyboardInterrupt:
        print("\n\nExiting viewer...")
    finally:
        env.close()
        print("Viewer closed.")


if __name__ == "__main__":
    main()
