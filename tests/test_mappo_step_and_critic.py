#!/usr/bin/env python3
"""Unit tests for Phase 08 PyTorch MAPPO Actor-Critic and CTDE Rollout Buffer."""

import os
import sys
import numpy as np
import pytest
import torch

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.training.fleet.mappo_agent import (
    DecentralizedActor,
    CentralizedCritic,
    MultiAgentRolloutBuffer,
    MappoAgent,
)


def test_decentralized_actor_forward():
    actor = DecentralizedActor(obs_dim=37, act_dim=2, hidden_dim=64)
    dummy_obs = torch.randn(4, 37) # Batch of 4 observations

    action, log_prob = actor.get_action(dummy_obs, deterministic=True)
    assert action.shape == (4, 2), "Actor action output must match (batch_size, 2)"
    assert log_prob.shape == (4,), "Actor log_prob output must match (batch_size,)"

    # Action limits [-1.0, 1.0]
    assert (action >= -1.0).all() and (action <= 1.0).all()


def test_centralized_critic_forward():
    critic = CentralizedCritic(global_dim=20, hidden_dim=64)
    dummy_g_state = torch.randn(4, 20)

    val = critic(dummy_g_state)
    assert val.shape == (4,), "Centralized critic output must be scalar per global state"


def test_mappo_agent_train_step():
    agent = MappoAgent(
        obs_dim=37,
        act_dim=2,
        global_dim=20,
        lr_actor=1e-3,
        lr_critic=1e-3,
        device="cpu",
    )

    buffer = MultiAgentRolloutBuffer(
        buffer_size=16,
        num_agents=2,
        obs_dim=37,
        act_dim=2,
        global_dim=20,
        device="cpu",
    )

    # Populate buffer with dummy transitions
    for _ in range(16):
        obs = np.random.randn(2, 37).astype(np.float32)
        actions = np.random.uniform(-1.0, 1.0, size=(2, 2)).astype(np.float32)
        log_probs = np.random.randn(2).astype(np.float32)
        rewards = np.array([0.5, 0.5], dtype=np.float32)
        dones = np.array([0.0, 0.0], dtype=np.float32)
        g_state = np.random.randn(20).astype(np.float32)
        val = 0.5

        buffer.add(obs, actions, log_probs, rewards, dones, g_state, val)

    advantages, returns = buffer.compute_returns_and_advantages(last_value=0.5, last_done=False)
    assert advantages.shape == (16,)
    assert returns.shape == (16,)

    metrics = agent.train_step(buffer, advantages, returns, num_epochs=2, batch_size=16)
    assert "actor_loss" in metrics
    assert "critic_loss" in metrics
    assert not np.isnan(metrics["actor_loss"])
    assert not np.isnan(metrics["critic_loss"])
