"""Small web UI for inspecting PortEnv simulations.

Run from the repository root:

    python3 examples/ui_server.py
"""

from __future__ import annotations

import argparse
import json
import random
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional

import numpy as np

from port_sim import Container, PortEnv, default_config


ROOT = Path(__file__).resolve().parent
UI_DIR = ROOT / "ui"


class SimulationSession:
    def __init__(self) -> None:
        self.env = PortEnv(default_config())
        self.obs, self.info = self.env.reset(seed=1)
        self.total_reward = 0.0
        self.last_reward = 0.0
        self.done = False
        self.last_action: Optional[int] = None
        self.cumulative_breakdown: dict[str, float] = {}
        self.event_log: list[str] = ["Simulation reset."]

    def reset(self, seed: int = 1) -> dict[str, Any]:
        self.obs, self.info = self.env.reset(seed=seed)
        self.total_reward = 0.0
        self.last_reward = 0.0
        self.done = False
        self.last_action = None
        self.cumulative_breakdown = {}
        self.event_log = [f"Simulation reset with seed={seed}."]
        return self.state()

    def step(self, action: Optional[int], mode: str) -> dict[str, Any]:
        if self.done:
            self.event_log.insert(0, "Step ignored because the episode is done. Reset to continue.")
            return self.state()

        selected_action = self._select_action(action, mode)
        before_container = self._container_payload(self.env.current_container)
        before_time = self.env.time
        self.obs, reward, terminated, truncated, self.info = self.env.step(selected_action)
        self.total_reward += reward
        self.last_reward = reward
        self.done = terminated or truncated
        self.last_action = selected_action
        for key, value in self.info.get("reward_breakdown", {}).items():
            self.cumulative_breakdown[key] = self.cumulative_breakdown.get(key, 0.0) + float(value)

        block, bay, stack = self.env.decode_action(selected_action)
        status = "terminated" if terminated else "truncated" if truncated else "running"
        container_text = (
            f"#{before_container['id']} {before_container['type']}"
            if before_container
            else "no container"
        )
        self.event_log.insert(
            0,
            (
                f"t={before_time} action={selected_action} ({block},{bay},{stack}) "
                f"{container_text} reward={reward:.2f} status={status}"
            ),
        )
        self.event_log = self.event_log[:80]
        return self.state()

    def state(self) -> dict[str, Any]:
        index = self._container_index()
        return {
            "time": self.env.time,
            "done": self.done,
            "totalReward": self.total_reward,
            "lastReward": self.last_reward,
            "lastAction": self.last_action,
            "config": {
                "blocks": self.env.config.blocks,
                "bays": self.env.config.bays,
                "stacks": self.env.config.stacks,
                "tiers": self.env.config.tiers,
                "actionCount": self.env.config.action_count,
                "maxTime": self.env.config.max_time,
            },
            "yard": self.env.yard.grid.tolist(),
            "currentContainer": self._container_payload(self.env.current_container),
            "pendingContainers": [self._container_payload(item) for item in self.env.pending_containers],
            "ships": [self._ship_payload(ship) for ship in self.env.scheduler.ships],
            "cranes": [self._crane_payload(crane) for crane in self.env.cranes.cranes],
            "rewardBreakdown": self.info.get("reward_breakdown", {}),
            "cumulativeRewardBreakdown": self.cumulative_breakdown,
            "containerIndex": {str(key): self._container_payload(value) for key, value in index.items()},
            "eventLog": self.event_log,
        }

    def _select_action(self, action: Optional[int], mode: str) -> int:
        if mode == "random":
            return random.randrange(self.env.action_space.n)
        if mode == "heuristic":
            return self._heuristic_action()
        if action is None:
            return 0
        if action < 0 or action >= self.env.action_space.n:
            return 0
        return action

    def _heuristic_action(self) -> int:
        if self.env.current_container is None:
            return 0
        yard = self.env.yard.grid
        index = self._container_index()
        scored = []
        for action in range(self.env.action_space.n):
            block, bay, stack = self.env.decode_action(action)
            height = int(np.count_nonzero(yard[block, bay, stack, :]))
            if height >= self.env.config.tiers:
                scored.append((-1_000.0, action))
                continue

            blocking_risk = 0
            for tier in range(height):
                below_id = int(yard[block, bay, stack, tier])
                below = index.get(below_id)
                if below and below.deadline < self.env.current_container.deadline:
                    blocking_risk += 1

            distance = block + bay + stack
            urgency_height_penalty = 3.0 if self.env.current_container.deadline <= self.env.time + 3 else -0.5
            score = 100.0 - (8.0 * blocking_risk) - (1.5 * height) - (0.2 * distance)
            score -= urgency_height_penalty * height
            scored.append((score, action))
        return max(scored, key=lambda item: item[0])[1]

    def _container_index(self) -> dict[int, Container]:
        containers = {}
        for ship in self.env.scheduler.ships:
            for container in ship.containers:
                containers[container.id] = container
        return containers

    def _container_payload(self, container: Optional[Container]) -> Optional[dict[str, Any]]:
        if container is None:
            return None
        return {
            "id": container.id,
            "type": container.type.name.lower(),
            "priority": container.priority,
            "deadline": container.deadline,
            "weight": container.weight,
            "destinationShipId": container.destination_ship_id,
        }

    def _ship_payload(self, ship: Any) -> dict[str, Any]:
        return {
            "id": ship.id,
            "arrivalTime": ship.arrival_time,
            "departureTime": ship.departure_time,
            "arrived": ship.arrived,
            "departed": ship.departed,
            "unloadedCount": ship.unloaded_count,
            "containerCount": len(ship.containers),
            "remaining": len(ship.containers) - ship.unloaded_count,
            "containers": [self._container_payload(c) for c in ship.containers],
        }

    def _crane_payload(self, crane: Any) -> dict[str, Any]:
        return {
            "id": crane.id,
            "kind": crane.kind.name.lower(),
            "available": crane.available,
            "remainingTime": crane.remaining_time,
            "task": None
            if crane.task is None
            else {
                "containerId": crane.task.container_id,
                "duration": crane.task.duration,
                "description": crane.task.description,
            },
        }


SESSION = SimulationSession()


class UiHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(UI_DIR), **kwargs)

    def do_GET(self) -> None:
        if self.path == "/api/state":
            self._send_json(SESSION.state())
            return
        if self.path == "/":
            self.path = "/index.html"
        super().do_GET()

    def do_POST(self) -> None:
        payload = self._read_json()
        if self.path == "/api/reset":
            seed = int(payload.get("seed", 1))
            self._send_json(SESSION.reset(seed=seed))
            return
        if self.path == "/api/step":
            action = payload.get("action")
            mode = str(payload.get("mode", "manual"))
            self._send_json(SESSION.step(action=action, mode=mode))
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def _send_json(self, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the PortEnv web UI.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8000, type=int)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), UiHandler)
    print(f"PortEnv UI running at http://{args.host}:{args.port}")
    print("Press Ctrl+C to stop.")
    server.serve_forever()


if __name__ == "__main__":
    main()
