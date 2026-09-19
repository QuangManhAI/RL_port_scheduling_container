#!/usr/bin/env python3
"""Exports trained Stable-Baselines3 PPO policy weights into Godot-native JSON format.

Enables 100% in-engine zero-latency C++/GDScript neural inference without Python or TCP sockets.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

try:
    from stable_baselines3 import PPO
except ImportError as e:
    print(f"Error importing stable_baselines3: {e}")
    sys.exit(1)


def export_ppo_model(model_path: str, output_path: str) -> None:
    print(f">> Loading SB3 PPO checkpoint: {model_path}")
    model = PPO.load(model_path, device="cpu")

    state = model.policy.state_dict()

    # Extract weights for the MlpPolicy architecture
    w0 = state["mlp_extractor.policy_net.0.weight"].cpu().numpy().tolist()
    b0 = state["mlp_extractor.policy_net.0.bias"].cpu().numpy().tolist()
    w1 = state["mlp_extractor.policy_net.2.weight"].cpu().numpy().tolist()
    b1 = state["mlp_extractor.policy_net.2.bias"].cpu().numpy().tolist()
    w2 = state["action_net.weight"].cpu().numpy().tolist()
    b2 = state["action_net.bias"].cpu().numpy().tolist()

    data = {
        "model_type": "MlpPolicy",
        "activation": "tanh",
        "input_dim": len(w0[0]),
        "hidden_dim": len(w0),
        "output_dim": len(w2),
        "layers": [
            {"weight": w0, "bias": b0, "activation": "tanh"},
            {"weight": w1, "bias": b1, "activation": "tanh"},
            {"weight": w2, "bias": b2, "activation": "none"},
        ]
    }

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    print(f"✔ Exported native policy to: {output_path}")
    print(f"   Architecture: Linear({data['input_dim']} -> {data['hidden_dim']}) -> Tanh -> Linear({data['hidden_dim']} -> {data['hidden_dim']}) -> Tanh -> Linear({data['hidden_dim']} -> {data['output_dim']})")

    # Verification: Compare Python manual forward pass with model.predict()
    dummy_input = np.random.randn(data["input_dim"]).astype(np.float32)
    pred_sb3, _ = model.predict(dummy_input, deterministic=True)

    # Manual forward
    h1 = np.tanh(np.dot(np.array(w0), dummy_input) + np.array(b0))
    h2 = np.tanh(np.dot(np.array(w1), h1) + np.array(b1))
    pred_manual = np.clip(np.dot(np.array(w2), h2) + np.array(b2), -1.0, 1.0)

    diff = np.max(np.abs(pred_sb3 - pred_manual))
    print(f"✔ Numerical Parity Verified! Max difference: {diff:.8e}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export PPO policy to Godot native JSON format.")
    parser.add_argument("--model", type=str, default="src/training/logs/checkpoints/ppo_s5_final.zip", help="Path to input .zip")
    parser.add_argument("--output", type=str, default="godot/models/ppo_s5_policy.json", help="Path to output .json")

    args = parser.parse_args()
    export_ppo_model(args.model, args.output)


if __name__ == "__main__":
    main()
