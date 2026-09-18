#!/usr/bin/env python3
"""Training Runner for Fleet-Level Multi-Agent PPO (Phase 08 - MAPPO).

Trains parameter-shared decentralized AMR policies using Centralized Training and
Decentralized Execution (CTDE) in the dual-rack narrow aisle environment.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import List

import numpy as np

from pathlib import Path
project_root = str(Path(__file__).resolve().parents[3])
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.envs.fleet.fleet_mappo_gym_env import FleetMappoGymEnv
from src.training.fleet.mappo_agent import MappoAgent, MultiAgentRolloutBuffer


def main() -> None:
    parser = argparse.ArgumentParser(description="Train Phase 08 Fleet MAPPO Coordination.")
    parser.add_argument("--steps", type=int, default=50000, help="Total environment steps to train (default: 50k)")
    parser.add_argument("--rollout-len", type=int, default=512, help="Rollout buffer horizon length (default: 512)")
    parser.add_argument("--port", type=int, default=11300, help="TCP port for Godot bridge (default: 11300)")
    parser.add_argument("--num-amrs", type=int, default=2, help="Fleet AMR count in training aisle (default: 2)")
    parser.add_argument("--headless", action="store_true", default=True, help="Run headless Godot without window")
    parser.add_argument("--visual", action="store_true", help="Open visual Godot window")
    parser.add_argument("--save-dir", type=str, default="src/training/logs/checkpoints/fleet", help="Checkpoint save directory")
    parser.add_argument("--lr-actor", type=float, default=3e-4, help="Actor learning rate")
    parser.add_argument("--lr-critic", type=float, default=1e-3, help="Critic learning rate")
    parser.add_argument("--device", type=str, default="auto", choices=["auto", "cuda", "cpu"])
    parser.add_argument("--checkpoint", type=str, default=None, help="Path to checkpoint to resume from")

    args = parser.parse_args()
    headless_mode = not args.visual

    os.makedirs(args.save_dir, exist_ok=True)
    logs_dir = os.path.join(project_root, "src", "training", "logs")
    metrics_dir = os.path.join(project_root, "experiments", "metrics")
    os.makedirs(logs_dir, exist_ok=True)
    os.makedirs(metrics_dir, exist_ok=True)

    log_file = os.path.join(logs_dir, "fleet_mappo_training.log")
    csv_file = os.path.join(metrics_dir, "fleet_mappo_metrics.csv")

    import logging
    logger = logging.getLogger("MAPPO")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    f_handler = logging.FileHandler(log_file, mode="a", encoding="utf-8")
    f_handler.setFormatter(logging.Formatter("[%(asctime)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
    s_handler = logging.StreamHandler(sys.stdout)
    s_handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(f_handler)
    logger.addHandler(s_handler)

    if not os.path.exists(csv_file) or os.path.getsize(csv_file) == 0:
        with open(csv_file, "w", encoding="utf-8") as f:
            f.write("timestamp,step,episode,team_reward,delivered,actor_loss,critic_loss,sps,elapsed_sec\n")

    import torch
    device_name = "cuda" if (args.device == "cuda" or (args.device == "auto" and torch.cuda.is_available())) else "cpu"

    logger.info("=" * 70)
    logger.info("   PHASE 08: FLEET-LEVEL MULTI-AGENT PPO (MAPPO) TRAINING")
    logger.info("   Architecture:   Decentralized Actor (37-D) + Centralized Critic (CTDE)")
    logger.info(f"   Fleet Size:     {args.num_amrs} AMRs | Dual 4-Tier Racks + Motorized Conveyor")
    logger.info(f"   Target Steps:   {args.steps:,} | Rollout Horizon: {args.rollout_len}")
    logger.info(f"   Mode:           {'Headless (Max Throughput)' if headless_mode else 'Visual Window Active'}")
    logger.info(f"   TCP Port:       {args.port} | Device: {device_name}")
    logger.info(f"   Log File:       {log_file}")
    logger.info(f"   Metrics CSV:    {csv_file}")
    logger.info("=" * 70 + "\n")


    env = FleetMappoGymEnv(
        port=args.port,
        num_agents=args.num_amrs,
        headless=headless_mode,
        autostart=True,
    )

    agent = MappoAgent(
        obs_dim=env.obs_dim,
        act_dim=env.act_dim,
        global_dim=20,
        lr_actor=args.lr_actor,
        lr_critic=args.lr_critic,
        device=device_name,
    )

    if args.checkpoint and os.path.exists(args.checkpoint):
        agent.load(args.checkpoint)
        print(f"✔ Successfully loaded checkpoint weights from: {args.checkpoint}")


    buffer = MultiAgentRolloutBuffer(
        buffer_size=args.rollout_len,
        num_agents=args.num_amrs,
        obs_dim=env.obs_dim,
        act_dim=env.act_dim,
        global_dim=20,
        device=device_name,
    )

    total_steps = 0
    episodes = 0
    t_start = time.time()

    obs, info = env.reset()
    global_state = np.array(info.get("global_state", np.zeros(20)), dtype=np.float32)
    if len(global_state) < 20:
        global_state = np.pad(global_state, (0, 20 - len(global_state)))
    elif len(global_state) > 20:
        global_state = global_state[:20]

    ep_team_reward = 0.0

    try:
        while total_steps < args.steps:
            # 1. Collect Rollout Horizon
            for step in range(args.rollout_len):
                actions, log_probs, value = agent.select_actions(obs, global_state)

                next_obs, rewards, terminated, truncated, next_info = env.step(actions)
                done = terminated or truncated

                next_global = np.array(next_info.get("global_state", np.zeros(20)), dtype=np.float32)
                if len(next_global) < 20:
                    next_global = np.pad(next_global, (0, 20 - len(next_global)))
                elif len(next_global) > 20:
                    next_global = next_global[:20]

                buffer.add(
                    obs=obs,
                    actions=actions,
                    log_probs=log_probs,
                    rewards=rewards,
                    dones=np.full((args.num_amrs,), float(done), dtype=np.float32),
                    global_state=global_state,
                    value=value,
                )

                ep_team_reward += float(rewards.mean())
                total_steps += 1
                obs = next_obs
                global_state = next_global

                if done:
                    episodes += 1
                    delivered = next_info.get("total_fleet_delivered", 0)
                    elapsed = time.time() - t_start
                    sps = int(total_steps / max(0.1, elapsed))
                    logger.info(
                        f"[MAPPO Ep {episodes:3d}] Steps: {total_steps:6d}/{args.steps} | "
                        f"Team Rew: {ep_team_reward:+6.2f} | Delivered: {delivered:2d}/6 | SPS: {sps}"
                    )
                    ep_team_reward = 0.0
                    obs, info = env.reset()
                    global_state = np.array(info.get("global_state", np.zeros(20)), dtype=np.float32)
                    if len(global_state) < 20:
                        global_state = np.pad(global_state, (0, 20 - len(global_state)))
                    elif len(global_state) > 20:
                        global_state = global_state[:20]

            # 2. Compute GAE and Update MAPPO Networks
            _, _, last_val = agent.select_actions(obs, global_state)
            advantages, returns = buffer.compute_returns_and_advantages(last_val, False)
            metrics = agent.train_step(buffer, advantages, returns)

            elapsed = time.time() - t_start
            sps = int(total_steps / max(0.1, elapsed))
            logger.info(
                f"  >> [Update @ {total_steps:6d}] "
                f"Actor Loss: {metrics['actor_loss']:+.4f} | "
                f"Critic Loss: {metrics['critic_loss']:.4f} | "
                f"SPS: {sps}"
            )

            # Write row to CSV
            try:
                with open(csv_file, "a", encoding="utf-8") as f:
                    timestamp_str = time.strftime("%Y-%m-%d %H:%M:%S")
                    f.write(f"{timestamp_str},{total_steps},{episodes},{ep_team_reward:.2f},{delivered if 'delivered' in locals() else 0},{metrics['actor_loss']:.4f},{metrics['critic_loss']:.4f},{sps},{elapsed:.1f}\n")
            except Exception:
                pass

            # Periodic Checkpoint
            if total_steps % max(args.rollout_len * 4, 2048) == 0:
                ckpt_path = os.path.join(args.save_dir, "mappo_fleet_latest.pt")
                agent.save(ckpt_path)
                logger.info(f"  [Checkpoint] Saved latest policy snapshot to: {ckpt_path}")

        final_ckpt = os.path.join(args.save_dir, "mappo_fleet_final.pt")
        agent.save(final_ckpt)
        logger.info(f"\n✔ MAPPO Training Completed successfully! Final model saved to: {final_ckpt}")


    finally:
        env.close()


if __name__ == "__main__":
    main()
