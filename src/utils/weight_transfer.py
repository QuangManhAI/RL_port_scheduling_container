#!/usr/bin/env python3
"""Utility for transferring pre-trained 13-dim PPO weights into extended 16-dim Rack models."""

from __future__ import annotations

import os
from typing import Optional

import torch
from stable_baselines3 import PPO


def warm_start_rack_policy(
    target_model: PPO,
    source_checkpoint_path: str,
    base_dim: int = 13,
) -> PPO:
    """Transfers weights from a 13-dim checkpoint into a 16-dim PPO policy.

    The first `base_dim` input columns, all hidden layers, and action/value heads
    are copied directly from the source policy. The newly appended input features
    (indices `base_dim:` e.g. tier, slot, rack face alignment) are initialized
    with small near-zero weights so the policy initially behaves identically to the
    trained foundation policy.

    Args:
        target_model: An initialized 16-dim PPO model.
        source_checkpoint_path: Path to the 13-dim source .zip checkpoint (e.g. ppo_s1_final.zip).
        base_dim: Number of base features to copy (default: 13).

    Returns:
        The target_model with transferred weights.
    """
    if not os.path.isfile(source_checkpoint_path):
        raise FileNotFoundError(f"Source checkpoint not found: {source_checkpoint_path}")

    source_model = PPO.load(source_checkpoint_path, device="cpu")

    with torch.no_grad():
        old_w_pi = source_model.policy.mlp_extractor.policy_net[0].weight
        old_b_pi = source_model.policy.mlp_extractor.policy_net[0].bias
        target_w_pi = target_model.policy.mlp_extractor.policy_net[0].weight

        if old_w_pi.shape == target_w_pi.shape:
            # Direct same-shape weight copy (e.g. 16-D -> 16-D)
            target_model.policy.mlp_extractor.policy_net[0].weight.copy_(old_w_pi)
            target_model.policy.mlp_extractor.policy_net[0].bias.copy_(old_b_pi)
            target_model.policy.mlp_extractor.value_net[0].weight.copy_(
                source_model.policy.mlp_extractor.value_net[0].weight
            )
            target_model.policy.mlp_extractor.value_net[0].bias.copy_(
                source_model.policy.mlp_extractor.value_net[0].bias
            )
        else:
            # Dimension surgery (e.g. 13->16, 16->32): copy overlapping base features and init new features near zero
            copy_dim = min(old_w_pi.shape[1], target_w_pi.shape[1], base_dim)
            target_model.policy.mlp_extractor.policy_net[0].weight[:, :copy_dim] = old_w_pi[:, :copy_dim]
            target_model.policy.mlp_extractor.policy_net[0].bias.copy_(old_b_pi)
            target_model.policy.mlp_extractor.policy_net[0].weight[:, copy_dim:].normal_(mean=0.0, std=0.01)

            old_w_vf = source_model.policy.mlp_extractor.value_net[0].weight
            old_b_vf = source_model.policy.mlp_extractor.value_net[0].bias
            target_model.policy.mlp_extractor.value_net[0].weight[:, :copy_dim] = old_w_vf[:, :copy_dim]
            target_model.policy.mlp_extractor.value_net[0].bias.copy_(old_b_vf)
            target_model.policy.mlp_extractor.value_net[0].weight[:, copy_dim:].normal_(mean=0.0, std=0.01)

        # 3. Policy Network - Hidden Layer (Layer 2)
        target_model.policy.mlp_extractor.policy_net[2].weight.copy_(
            source_model.policy.mlp_extractor.policy_net[2].weight
        )
        target_model.policy.mlp_extractor.policy_net[2].bias.copy_(
            source_model.policy.mlp_extractor.policy_net[2].bias
        )

        # 4. Value Network - Hidden Layer (Layer 2)
        target_model.policy.mlp_extractor.value_net[2].weight.copy_(
            source_model.policy.mlp_extractor.value_net[2].weight
        )
        target_model.policy.mlp_extractor.value_net[2].bias.copy_(
            source_model.policy.mlp_extractor.value_net[2].bias
        )

        # 5. Output Heads (Action Net & Value Net)
        target_model.policy.action_net.weight.copy_(source_model.policy.action_net.weight)
        target_model.policy.action_net.bias.copy_(source_model.policy.action_net.bias)

        target_model.policy.value_net.weight.copy_(source_model.policy.value_net.weight)
        target_model.policy.value_net.bias.copy_(source_model.policy.value_net.bias)

    print(f"✔ Transferred pre-trained foundation weights from '{source_checkpoint_path}' into 16-D Rack Policy!")
    return target_model
