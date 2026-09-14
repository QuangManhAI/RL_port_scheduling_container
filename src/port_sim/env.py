"""Gymnasium-compatible reinforcement learning environment."""

from __future__ import annotations

from typing import Any, Optional

import numpy as np

try:
    import gymnasium as gym
    from gymnasium import spaces
except ModuleNotFoundError as exc:  # pragma: no cover - exercised by import users without deps.
    raise ModuleNotFoundError(
        "PortEnv requires gymnasium. Install with `python3 -m pip install .`."
    ) from exc

from port_sim.config import PortConfig, default_config
from port_sim.cranes import CraneKind, CranePool, CraneTask
from port_sim.models import Container, Ship
from port_sim.scheduler import ShipScheduler
from port_sim.yard import Yard


class PortEnv(gym.Env):
    """RL environment where actions choose yard stacks for incoming containers."""

    metadata = {"render_modes": ["ansi"], "render_fps": 1}

    def __init__(self, config: Optional[PortConfig] = None, render_mode: Optional[str] = None) -> None:
        super().__init__()
        self.config = config or default_config()
        self.render_mode = render_mode
        self.yard = Yard(self.config.blocks, self.config.bays, self.config.stacks, self.config.tiers)
        self.scheduler = ShipScheduler(self.config.schedule)
        self.cranes = CranePool(self.config.quay_cranes, self.config.yard_cranes)
        self.time = 0
        self.current_container: Optional[Container] = None
        self.current_ship: Optional[Ship] = None
        self.pending_containers: list[Container] = []
        self.completed_ship_ids: set[int] = set()
        self.last_reward_breakdown: dict[str, float] = {}

        # Normalization constants derived from the ship schedule so that
        # yard observation features are scaled to roughly [0, 1].
        all_containers = [c for ship in self.config.schedule for c in ship.containers]
        self.max_deadline = max((c.deadline for c in all_containers), default=1) or 1
        self.max_priority = max((c.priority for c in all_containers), default=1) or 1
        self.max_weight = max((c.weight for c in all_containers), default=1.0) or 1.0

        self.action_space = spaces.Discrete(self.config.action_count)
        self.observation_space = spaces.Dict(
            {
                "yard": spaces.Box(
                    low=0.0,
                    high=1.0,
                    shape=(self.config.blocks, self.config.bays, self.config.stacks, self.config.tiers, 4),
                    dtype=np.float32,
                ),
                "current_container": spaces.Box(low=0, high=1_000_000, shape=(5,), dtype=np.float32),
                "time": spaces.Box(low=0, high=self.config.max_time, shape=(1,), dtype=np.int64),
                "ship_queue": spaces.Box(low=0, high=1_000_000, shape=(5, 7), dtype=np.int64),
                "crane_status": spaces.MultiBinary(self.config.quay_cranes + self.config.yard_cranes),
                "pending_containers": spaces.Box(low=0, high=1_000_000, shape=(10, 5), dtype=np.float32),
            }
        )

    def reset(self, *, seed: Optional[int] = None, options: Optional[dict[str, Any]] = None) -> tuple[dict[str, np.ndarray], dict[str, Any]]:
        super().reset(seed=seed)
        self.time = 0
        self.yard.reset()
        self.scheduler.reset()
        self.cranes.reset()
        self.pending_containers = []
        self.completed_ship_ids = set()
        self.last_reward_breakdown = {}
        self.scheduler.update_arrivals(self.time)
        self._select_current_container()
        return self._observation(), self._info()

    def step(self, action: int) -> tuple[dict[str, np.ndarray], float, bool, bool, dict[str, Any]]:
        reward = 0.0
        breakdown = {
            "valid_placement": 0.0,
            "invalid_placement": 0.0,
            "ship_complete": 0.0,
            "rehandling": 0.0,
            "distance": 0.0,
            "crane_idle": 0.0,
            "delay": 0.0,
        }

        self.scheduler.update_arrivals(self.time)
        self._select_current_container()

        if self.current_container is None or self.current_ship is None:
            idle_penalty = self._idle_penalty(work_pending=False)
            reward += idle_penalty
            breakdown["crane_idle"] += idle_penalty
        else:
            block, bay, stack = self.decode_action(action)
            placement = self.yard.place(self.current_container, block, bay, stack)
            if placement.valid:
                reward += self.config.weight_valid_placement
                breakdown["valid_placement"] += self.config.weight_valid_placement
                distance_penalty = self.config.weight_distance_penalty * self._yard_distance(block, bay, stack)
                reward += distance_penalty
                breakdown["distance"] += distance_penalty
                self.cranes.assign_first_available(
                    CraneTask(
                        kind=CraneKind.QUAY,
                        container_id=self.current_container.id,
                        duration=self.config.quay_task_duration,
                        description="ship_to_yard",
                    )
                )
                complete = self.scheduler.mark_loaded_to_yard(self.current_ship.id)
                if complete and self.current_ship.id not in self.completed_ship_ids:
                    reward += self.config.weight_ship_complete
                    breakdown["ship_complete"] += self.config.weight_ship_complete
                    self.completed_ship_ids.add(self.current_ship.id)
                self.pending_containers.append(self.current_container)
                self.current_container = None
                self.current_ship = None
            else:
                reward += self.config.weight_invalid_placement
                breakdown["invalid_placement"] += self.config.weight_invalid_placement
                
                # Fallback: place in the first available valid stack to keep env state consistent
                fallback_placed = False
                for b in range(self.config.blocks):
                    for ba in range(self.config.bays):
                        for s in range(self.config.stacks):
                            if self.yard.can_place(b, ba, s):
                                self.yard.place(self.current_container, b, ba, s)
                                fallback_placed = True
                                break
                        if fallback_placed:
                            break
                    if fallback_placed:
                        break
                
                if fallback_placed:
                    self.pending_containers.append(self.current_container)
                    self.cranes.assign_first_available(
                        CraneTask(
                            kind=CraneKind.QUAY,
                            container_id=self.current_container.id,
                            duration=self.config.quay_task_duration,
                            description="ship_to_yard",
                        )
                    )
                    complete = self.scheduler.mark_loaded_to_yard(self.current_ship.id)
                    if complete and self.current_ship.id not in self.completed_ship_ids:
                        reward += self.config.weight_ship_complete
                        breakdown["ship_complete"] += self.config.weight_ship_complete
                        self.completed_ship_ids.add(self.current_ship.id)
                
                self.current_container = None
                self.current_ship = None

            idle_penalty = self._idle_penalty(work_pending=bool(self.current_container or self.pending_containers))
            reward += idle_penalty
            breakdown["crane_idle"] += idle_penalty

        completed_tasks = self.cranes.tick()
        for task in completed_tasks:
            if task.description == "yard_retrieve":
                continue

        retrieval_penalty = self._process_due_retrievals()
        reward += retrieval_penalty["reward"]
        breakdown["rehandling"] += retrieval_penalty["rehandling"]
        breakdown["delay"] += retrieval_penalty["delay"]

        self.time += 1
        self.scheduler.mark_departures(self.time)
        self.scheduler.update_arrivals(self.time)
        self._select_current_container()

        terminated = self.scheduler.all_complete() and self.yard.container_count == 0
        truncated = self.time >= self.config.max_time
        self.last_reward_breakdown = breakdown
        return self._observation(), reward, terminated, truncated, self._info()

    def decode_action(self, action: int) -> tuple[int, int, int]:
        if action < 0 or action >= self.config.action_count:
            raise ValueError(f"action must be in [0, {self.config.action_count - 1}], got {action}")
        stack = action % self.config.stacks
        bay = (action // self.config.stacks) % self.config.bays
        block = action // (self.config.bays * self.config.stacks)
        return block, bay, stack

    def encode_action(self, block: int, bay: int, stack: int) -> int:
        if not self.yard.is_valid_stack(block, bay, stack):
            raise ValueError("stack coordinates out of bounds")
        return block * self.config.bays * self.config.stacks + bay * self.config.stacks + stack

    def render(self) -> Optional[str]:
        if self.render_mode != "ansi":
            return None
        return (
            f"time={self.time}, current={self.current_container.id if self.current_container else None}, "
            f"yard_count={self.yard.container_count}\n{self.yard.grid}"
        )

    def _select_current_container(self) -> None:
        if self.current_container is not None:
            return
        next_item = self.scheduler.next_container(self.time)
        if next_item is None:
            return
        self.current_ship, self.current_container = next_item

    def _process_due_retrievals(self) -> dict[str, float]:
        reward = 0.0
        rehandling_component = 0.0
        delay_component = 0.0
        for container in list(self.yard.due_containers(self.time)):
            result = self.yard.retrieve(container.id)
            if not result.found:
                continue
            if container in self.pending_containers:
                self.pending_containers.remove(container)
            self.cranes.assign_first_available(
                CraneTask(
                    kind=CraneKind.YARD,
                    container_id=container.id,
                    duration=self.config.yard_task_duration,
                    description="yard_retrieve",
                )
            )
            rehandle_penalty = self.config.weight_rehandling_penalty * result.rehandles
            delay_penalty = self.config.weight_delay_penalty * max(0, self.time - container.deadline)
            reward += rehandle_penalty + delay_penalty
            rehandling_component += rehandle_penalty
            delay_component += delay_penalty
        return {"reward": reward, "rehandling": rehandling_component, "delay": delay_component}

    def _idle_penalty(self, work_pending: bool) -> float:
        if not work_pending:
            return 0.0
        return self.config.weight_idle_penalty * self.cranes.idle_count(CraneKind.QUAY)

    def _yard_distance(self, block: int, bay: int, stack: int) -> float:
        return float(block + bay + stack)

    def _observation(self) -> dict[str, np.ndarray]:
        return {
            "yard": self._yard_feature_grid(),
            "current_container": self._encode_container(self.current_container),
            "time": np.array([self.time], dtype=np.int64),
            "ship_queue": np.array(self.scheduler.snapshot(self.time), dtype=np.int64),
            "crane_status": np.array(self.cranes.availability_vector(), dtype=np.int8),
            "pending_containers": self._encode_pending(),
        }

    def _yard_feature_grid(self) -> np.ndarray:
        """Encode the yard as a feature grid.

        Each cell holds ``[type, norm_deadline, norm_priority, norm_weight]``
        with values in ``[0, 1]``.  Empty cells are all zeros.  Container type
        is shifted by one before normalising so that
        IMPORT -> 1/3, EXPORT -> 2/3, TRANSSHIPMENT -> 1.0,
        clearly separating occupied cells from empty ones (0).
        """
        shape = (self.config.blocks, self.config.bays, self.config.stacks, self.config.tiers, 4)
        features = np.zeros(shape, dtype=np.float32)
        id_grid = self.yard.grid
        for b in range(self.config.blocks):
            for ba in range(self.config.bays):
                for s in range(self.config.stacks):
                    for t in range(self.config.tiers):
                        cid = int(id_grid[b, ba, s, t])
                        if cid == 0:
                            continue
                        container = self.yard.get_container(cid)
                        if container is None:
                            continue
                        features[b, ba, s, t] = [
                            (float(container.type) + 1.0) / 3.0,
                            float(container.deadline) / self.max_deadline,
                            float(container.priority) / self.max_priority,
                            float(container.weight) / self.max_weight,
                        ]
        return features

    def _encode_container(self, container: Optional[Container]) -> np.ndarray:
        if container is None:
            return np.zeros(5, dtype=np.float32)
        return np.array(
            [
                float(container.id),
                float(int(container.type)),
                float(container.priority),
                float(container.deadline),
                float(container.weight),
            ],
            dtype=np.float32,
        )

    def _encode_pending(self, limit: int = 10) -> np.ndarray:
        rows = [self._encode_container(container) for container in self.pending_containers[:limit]]
        while len(rows) < limit:
            rows.append(np.zeros(5, dtype=np.float32))
        return np.vstack(rows).astype(np.float32)

    def _info(self) -> dict[str, Any]:
        return {
            "time": self.time,
            "current_container_id": self.current_container.id if self.current_container else None,
            "yard_container_count": self.yard.container_count,
            "reward_breakdown": self.last_reward_breakdown.copy(),
        }
