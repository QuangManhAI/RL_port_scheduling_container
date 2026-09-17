#!/usr/bin/env python3
"""True MAPPO (Multi-Agent PPO) with Centralized Training and Decentralized Execution (CTDE).

- Actor: Decentralized MLP policy with parameter sharing (Ego + k-NN + 16-ray LiDAR: 37 -> 2)
- Critic: Centralized Value network (Global state -> 1)
- Supports GAE-Lambda, clipped surrogate objective, entropy regularization, and PyTorch checkpoints.
"""

from __future__ import annotations

import os
from typing import Dict, List, Optional, Tuple

import numpy as np
import torch
import torch.nn as nn
from torch.distributions import Normal


class DecentralizedActor(nn.Module):
    """Parameter-shared actor policy taking ego-centric 37-D observation."""

    def __init__(self, obs_dim: int = 37, act_dim: int = 2, hidden_dim: int = 128) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(obs_dim, hidden_dim),
            nn.LayerNorm(hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.LayerNorm(hidden_dim),
            nn.Tanh(),
        )
        self.mean_head = nn.Linear(hidden_dim, act_dim)
        self.log_std = nn.Parameter(torch.zeros(act_dim) - 0.5)

    def forward(self, obs: torch.Tensor) -> Normal:
        features = self.net(obs)
        mean = torch.tanh(self.mean_head(features))
        std = torch.exp(self.log_std.clamp(-2.0, 0.5))
        return Normal(mean, std)

    def get_action(
        self,
        obs: torch.Tensor,
        deterministic: bool = False,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        dist = self.forward(obs)
        if deterministic:
            action = dist.mean
        else:
            action = dist.rsample()
        action = torch.clamp(action, -1.0, 1.0)
        log_prob = dist.log_prob(action).sum(dim=-1)
        return action, log_prob

    def evaluate_actions(
        self,
        obs: torch.Tensor,
        actions: torch.Tensor,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        dist = self.forward(obs)
        log_prob = dist.log_prob(actions).sum(dim=-1)
        entropy = dist.entropy().sum(dim=-1)
        return log_prob, entropy


class CentralizedCritic(nn.Module):
    """Centralized value function taking global warehouse state."""

    def __init__(self, global_dim: int = 20, hidden_dim: int = 256) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(global_dim, hidden_dim),
            nn.LayerNorm(hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.LayerNorm(hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1),
        )

    def forward(self, global_state: torch.Tensor) -> torch.Tensor:
        return self.net(global_state).squeeze(-1)


class MultiAgentRolloutBuffer:
    """Stores multi-agent transitions for centralized GAE advantage estimation."""

    def __init__(
        self,
        buffer_size: int,
        num_agents: int,
        obs_dim: int = 37,
        act_dim: int = 2,
        global_dim: int = 20,
        gamma: float = 0.99,
        gae_lambda: float = 0.95,
        device: str = "cpu",
    ) -> None:
        self.buffer_size = buffer_size
        self.num_agents = num_agents
        self.obs_dim = obs_dim
        self.act_dim = act_dim
        self.global_dim = global_dim
        self.gamma = gamma
        self.gae_lambda = gae_lambda
        self.device = torch.device(device)

        self.obs = np.zeros((buffer_size, num_agents, obs_dim), dtype=np.float32)
        self.actions = np.zeros((buffer_size, num_agents, act_dim), dtype=np.float32)
        self.log_probs = np.zeros((buffer_size, num_agents), dtype=np.float32)
        self.rewards = np.zeros((buffer_size, num_agents), dtype=np.float32)
        self.dones = np.zeros((buffer_size, num_agents), dtype=np.float32)
        self.global_states = np.zeros((buffer_size, global_dim), dtype=np.float32)
        self.values = np.zeros(buffer_size, dtype=np.float32)

        self.step: int = 0
        self.full: bool = False

    def add(
        self,
        obs: np.ndarray,
        actions: np.ndarray,
        log_probs: np.ndarray,
        rewards: np.ndarray,
        dones: np.ndarray,
        global_state: np.ndarray,
        value: float,
    ) -> None:
        self.obs[self.step] = obs
        self.actions[self.step] = actions
        self.log_probs[self.step] = log_probs
        self.rewards[self.step] = rewards
        self.dones[self.step] = dones
        self.global_states[self.step] = global_state
        self.values[self.step] = value

        self.step += 1
        if self.step >= self.buffer_size:
            self.full = True
            self.step = 0

    def compute_returns_and_advantages(
        self,
        last_value: float,
        last_done: bool,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Compute Generalized Advantage Estimation across multi-agent rollouts."""
        advantages = np.zeros(self.buffer_size, dtype=np.float32)
        last_gae = 0.0

        for t in reversed(range(self.buffer_size)):
            if t == self.buffer_size - 1:
                next_val = last_value
                next_non_terminal = 1.0 - float(last_done)
            else:
                next_val = self.values[t + 1]
                next_non_terminal = 1.0 - float(self.dones[t].all())

            # Mean team reward across agents for centralized value evaluation
            mean_r = self.rewards[t].mean()
            delta = mean_r + (self.gamma * next_val * next_non_terminal) - self.values[t]
            last_gae = delta + (self.gamma * self.gae_lambda * next_non_terminal * last_gae)
            advantages[t] = last_gae

        returns = advantages + self.values
        return advantages, returns


class MappoAgent:
    """True MAPPO Trainer with Centralized Training and Decentralized Execution (CTDE)."""

    def __init__(
        self,
        obs_dim: int = 37,
        act_dim: int = 2,
        global_dim: int = 20,
        lr_actor: float = 3e-4,
        lr_critic: float = 1e-3,
        clip_ratio: float = 0.2,
        entropy_coef: float = 0.01,
        value_loss_coef: float = 0.5,
        max_grad_norm: float = 0.5,
        device: str = "cpu",
    ) -> None:
        self.device = torch.device(device)
        self.clip_ratio = clip_ratio
        self.entropy_coef = entropy_coef
        self.value_loss_coef = value_loss_coef
        self.max_grad_norm = max_grad_norm

        self.actor = DecentralizedActor(obs_dim, act_dim).to(self.device)
        self.critic = CentralizedCritic(global_dim).to(self.device)

        self.optimizer_actor = torch.optim.Adam(self.actor.parameters(), lr=lr_actor, eps=1e-5)
        self.optimizer_critic = torch.optim.Adam(self.critic.parameters(), lr=lr_critic, eps=1e-5)

    def select_actions(
        self,
        fleet_obs: np.ndarray,
        global_state: np.ndarray,
        deterministic: bool = False,
    ) -> Tuple[np.ndarray, np.ndarray, float]:
        """Generate decentralized actions for all AMRs and evaluate centralized value.
        
        Args:
            fleet_obs: Array of shape (N_agents, 37).
            global_state: Array of shape (global_dim,).
        
        Returns:
            actions: (N_agents, 2)
            log_probs: (N_agents,)
            value: float
        """
        self.actor.eval()
        self.critic.eval()

        with torch.no_grad():
            obs_t = torch.as_tensor(fleet_obs, dtype=torch.float32, device=self.device)
            g_state_t = torch.as_tensor(global_state, dtype=torch.float32, device=self.device)

            actions_t, log_probs_t = self.actor.get_action(obs_t, deterministic=deterministic)
            value_t = self.critic(g_state_t.unsqueeze(0))

        return (
            actions_t.cpu().numpy(),
            log_probs_t.cpu().numpy(),
            float(value_t.item()),
        )

    def train_step(
        self,
        buffer: MultiAgentRolloutBuffer,
        advantages: np.ndarray,
        returns: np.ndarray,
        num_epochs: int = 5,
        batch_size: int = 64,
    ) -> Dict[str, float]:
        """Perform PPO mini-batch gradient descent updates."""
        self.actor.train()
        self.critic.train()

        # Flatten multi-agent observations for parameter-shared actor
        N = buffer.num_agents
        T = buffer.buffer_size
        total_samples = T * N

        flat_obs = buffer.obs.reshape(total_samples, buffer.obs_dim)
        flat_act = buffer.actions.reshape(total_samples, buffer.act_dim)
        flat_log_p = buffer.log_probs.reshape(total_samples)

        # Broadcast centralized advantages to each agent
        adv_norm = (advantages - advantages.mean()) / (advantages.std() + 1e-8)
        flat_adv = np.repeat(adv_norm, N)

        # Tensor conversion
        obs_t = torch.as_tensor(flat_obs, dtype=torch.float32, device=self.device)
        act_t = torch.as_tensor(flat_act, dtype=torch.float32, device=self.device)
        old_log_p_t = torch.as_tensor(flat_log_p, dtype=torch.float32, device=self.device)
        adv_t = torch.as_tensor(flat_adv, dtype=torch.float32, device=self.device)

        g_state_t = torch.as_tensor(buffer.global_states, dtype=torch.float32, device=self.device)
        ret_t = torch.as_tensor(returns, dtype=torch.float32, device=self.device)

        actor_losses: List[float] = []
        critic_losses: List[float] = []

        # 1. Update Actor
        for _ in range(num_epochs):
            indices = np.random.permutation(total_samples)
            for start_idx in range(0, total_samples, batch_size):
                b_idx = indices[start_idx : start_idx + batch_size]

                log_prob, entropy = self.actor.evaluate_actions(obs_t[b_idx], act_t[b_idx])
                ratio = torch.exp(log_prob - old_log_p_t[b_idx])

                surr1 = ratio * adv_t[b_idx]
                surr2 = torch.clamp(ratio, 1.0 - self.clip_ratio, 1.0 + self.clip_ratio) * adv_t[b_idx]
                actor_loss = -torch.min(surr1, surr2).mean() - (self.entropy_coef * entropy.mean())

                self.optimizer_actor.zero_grad()
                actor_loss.backward()
                nn.utils.clip_grad_norm_(self.actor.parameters(), self.max_grad_norm)
                self.optimizer_actor.step()
                actor_losses.append(float(actor_loss.item()))

        # 2. Update Critic
        for _ in range(num_epochs):
            g_indices = np.random.permutation(T)
            for start_idx in range(0, T, batch_size // N):
                b_idx = g_indices[start_idx : start_idx + (batch_size // N)]

                v_pred = self.critic(g_state_t[b_idx])
                critic_loss = nn.functional.mse_loss(v_pred, ret_t[b_idx])

                self.optimizer_critic.zero_grad()
                critic_loss.backward()
                nn.utils.clip_grad_norm_(self.critic.parameters(), self.max_grad_norm)
                self.optimizer_critic.step()
                critic_losses.append(float(critic_loss.item()))

        return {
            "actor_loss": float(np.mean(actor_losses)),
            "critic_loss": float(np.mean(critic_losses)),
        }

    def save(self, checkpoint_path: str) -> None:
        os.makedirs(os.path.dirname(os.path.abspath(checkpoint_path)), exist_ok=True)
        torch.save(
            {
                "actor_state_dict": self.actor.state_dict(),
                "critic_state_dict": self.critic.state_dict(),
                "optimizer_actor": self.optimizer_actor.state_dict(),
                "optimizer_critic": self.optimizer_critic.state_dict(),
            },
            checkpoint_path,
        )
        print(f"✔ MAPPO Checkpoint saved to: {checkpoint_path}")

    def load(self, checkpoint_path: str) -> None:
        if not os.path.isfile(checkpoint_path):
            raise FileNotFoundError(f"Checkpoint not found at: {checkpoint_path}")
        ckpt = torch.load(checkpoint_path, map_location=self.device)
        self.actor.load_state_dict(ckpt["actor_state_dict"])
        self.critic.load_state_dict(ckpt["critic_state_dict"])
        print(f"✔ MAPPO Checkpoint successfully loaded from: {checkpoint_path}")
