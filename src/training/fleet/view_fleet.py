#!/usr/bin/env python3
"""Interactive Visual Policy Viewer for Phase 08 Fleet MAPPO Coordination.

Spawns a visual Godot window at 60 FPS action pacing and renders live multi-robot
telemetry across dual-rack aisle navigation and conveyor dock queuing.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import Optional

import numpy as np

from pathlib import Path
project_root = str(Path(__file__).resolve().parents[3])
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.envs.fleet.fleet_mappo_gym_env import FleetMappoGymEnv
from src.training.fleet.mappo_agent import MappoAgent

SUB_STAGE_NAMES = {
    0: "NAV_TO_RACK",
    1: "DOCK_AND_PICK",
    2: "TRAY_STOW",
    3: "NAV_TO_DOCK",
    4: "CONVEYOR_PLACE",
    5: "IDLE_WAIT",
}


def compute_fleet_navigation_action(obs_agent: np.ndarray, agent_idx: int) -> np.ndarray:
    """Proactive goal-directed navigation with mutual yielding and obstacle avoidance."""
    local_dx = float(obs_agent[6]) * 20.0
    local_dz = float(obs_agent[7]) * 20.0
    dist_to_goal = np.hypot(local_dx, local_dz)

    # Calculate desired angular rate to face sub-goal
    target_heading_err = np.arctan2(local_dx, -local_dz)
    w_cmd = float(np.clip(target_heading_err * 2.2, -1.0, 1.0))

    # Calculate linear velocity (throttle down when turning sharply)
    if abs(target_heading_err) < 0.45:
        v_cmd = 0.85 if dist_to_goal > 1.2 else 0.35
    elif abs(target_heading_err) < 0.9:
        v_cmd = 0.45
    else:
        v_cmd = 0.15

    # Mutual yielding using k-NN
    neighbor_dx = float(obs_agent[10]) * 6.0
    neighbor_dz = float(obs_agent[11]) * 6.0
    neighbor_dist = np.hypot(neighbor_dx, neighbor_dz)

    if 0.1 < neighbor_dist < 2.2:
        # Agent with higher index yields in narrow aisle
        if agent_idx > 0:
            v_cmd = 0.10
            w_cmd += 0.50

    return np.array([v_cmd, w_cmd], dtype=np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description="View Phase 08 Fleet MAPPO in Visual Window.")
    parser.add_argument("--checkpoint", type=str, default="src/training/logs/checkpoints/fleet/mappo_fleet_final.pt", help="Path to MAPPO checkpoint (.pt)")
    parser.add_argument("--port", type=int, default=11300, help="TCP port for Godot bridge (default: 11300)")
    parser.add_argument("--num-amrs", type=int, default=2, help="Number of AMRs to coordinate (default: 2)")
    parser.add_argument("--fps", type=float, default=60.0, help="Visual playback pacing rate in Hz (default: 60)")
    parser.add_argument("--episodes", type=int, default=5, help="Number of episodes to demonstrate (default: 5)")
    parser.add_argument("--connect", action="store_true", help="Connect to running Godot Editor (F6) instead of spawning")

    args = parser.parse_args()

    print("=" * 70)
    print("   PHASE 08: MULTI-AGENT FLEET COORDINATION VIEWER (MAPPO)")
    print(f"   Fleet:          {args.num_amrs} Phase 07 AMRs (Dual Trays + IK Grippers)")
    print(f"   Environment:    Dual 4-Tier Racks (16 Boxes) + Motorized Conveyor Table")
    print(f"   Visual Pacing:  {args.fps:.1f} FPS | Mode: {'Connect to Godot' if args.connect else 'Spawn New Window'}")
    print(f"   TCP Port:       {args.port}")
    print("=" * 70 + "\n")

    env = FleetMappoGymEnv(
        port=args.port,
        num_agents=args.num_amrs,
        headless=False,
        autostart=not args.connect,
        fps=args.fps,
    )

    has_checkpoint = os.path.isfile(args.checkpoint)
    agent = MappoAgent(
        obs_dim=env.obs_dim,
        act_dim=env.act_dim,
        global_dim=20,
        device="cpu",
    )

    if has_checkpoint:
        agent.load(args.checkpoint)
        print(f">> Loaded MAPPO Trained Policy: {args.checkpoint}\n")
    else:
        print(f">> Notice: Checkpoint '{args.checkpoint}' not found.")
        print(">> Running with Fleet Coordinated Navigator (Goal Seeking + Mutual Yielding).\n")

    try:
        for ep in range(1, args.episodes + 1):
            obs, info = env.reset()
            global_state = np.array(info.get("global_state", np.zeros(20)), dtype=np.float32)
            if len(global_state) < 20:
                global_state = np.pad(global_state, (0, 20 - len(global_state)))
            elif len(global_state) > 20:
                global_state = global_state[:20]

            step = 0
            ep_reward = 0.0
            print(f"\n--- Multi-Agent Fleet Episode {ep}/{args.episodes} Started ---")

            while True:
                step += 1
                if has_checkpoint:
                    actions, _, _ = agent.select_actions(obs, global_state, deterministic=True)
                else:
                    acts = [compute_fleet_navigation_action(obs[i], i) for i in range(args.num_amrs)]
                    actions = np.array(acts, dtype=np.float32)

                next_obs, rewards, terminated, truncated, next_info = env.step(actions)
                ep_reward += float(rewards.mean())
                obs = next_obs

                # Extract telemetry from agent_info
                ag_info_list = next_info.get("agent_info", [])
                st1 = SUB_STAGE_NAMES.get(ag_info_list[0].get("sub_stage", 0), "NAV") if len(ag_info_list) > 0 else "NAV"
                st2 = SUB_STAGE_NAMES.get(ag_info_list[1].get("sub_stage", 0), "NAV") if len(ag_info_list) > 1 else "NAV"
                sp1 = ag_info_list[0].get("speed", 0.0) if len(ag_info_list) > 0 else 0.0
                sp2 = ag_info_list[1].get("speed", 0.0) if len(ag_info_list) > 1 else 0.0
                deliv = next_info.get("total_fleet_delivered", 0)

                sys.stdout.write(
                    f"\rStep: {step:4d} | Delivered: {deliv:2d}/6 | "
                    f"AMR-1: [{st1:<13} spd={sp1:.2f}] | AMR-2: [{st2:<13} spd={sp2:.2f}] | "
                    f"Team Rew: {ep_reward:+6.2f}"
                )
                sys.stdout.flush()

                if terminated or truncated:
                    print(f"\n✔ Episode {ep} Finished! Delivered: {deliv}/6 Boxes | Steps: {step} | Total Reward: {ep_reward:+6.2f}")
                    break

    finally:
        env.close()


if __name__ == "__main__":
    main()
