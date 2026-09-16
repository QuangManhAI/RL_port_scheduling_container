#!/usr/bin/env python3
"""Buffer for recording and sampling terminal episode states for curriculum seeding."""

from __future__ import annotations

import json
import os
import random
from typing import Any, Dict, List, Optional, Tuple


def _to_json_safe(obj: Any) -> Any:
    if hasattr(obj, "tolist"):
        return obj.tolist()
    if hasattr(obj, "item"):
        return obj.item()
    if isinstance(obj, dict):
        return {k: _to_json_safe(v) for k, v in obj.items() if not k.startswith("_")}
    if isinstance(obj, (list, tuple)):
        return [_to_json_safe(v) for v in obj]
    return obj


class TerminalStateBuffer:
    """Manages disk-backed buffer of (x, z, yaw) terminal poses."""

    def __init__(self, log_dir: str = "src/training/logs/terminal_states") -> None:
        self.log_dir = log_dir
        os.makedirs(self.log_dir, exist_ok=True)

    def _get_stage_path(self, stage_name: str) -> str:
        return os.path.join(self.log_dir, f"{stage_name.lower()}_terminal_states.jsonl")

    def record_terminal_state(self, stage_name: str, pose: List[float], extra_info: Optional[Dict[str, Any]] = None) -> None:
        """Record a single terminal state."""
        if not pose or len(pose) < 3:
            return
        path = self._get_stage_path(stage_name)
        safe_pose = [float(p) for p in pose]
        safe_info = _to_json_safe(extra_info or {})
        entry = {
            "pose": safe_pose,
            "info": safe_info
        }
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")

    def load_states(self, stage_name: str) -> List[List[float]]:
        """Load all recorded poses for a stage."""
        path = self._get_stage_path(stage_name)
        if not os.path.isfile(path):
            return []
        poses = []
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    data = json.loads(line)
                    if "pose" in data:
                        poses.append(data["pose"])
        return poses

    def sample_pose(self, stage_name: str) -> Optional[List[float]]:
        """Sample a random pose from the stage's recorded buffer."""
        poses = self.load_states(stage_name)
        if not poses:
            return None
        return random.choice(poses)
