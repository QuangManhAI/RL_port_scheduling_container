"""3D container yard storage and retrieval logic."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, Optional

import numpy as np

from port_sim.models import Container, YardLocation


@dataclass(frozen=True)
class PlacementResult:
    valid: bool
    location: Optional[YardLocation] = None
    reason: str = ""


@dataclass(frozen=True)
class RetrievalResult:
    found: bool
    container: Optional[Container] = None
    rehandles: int = 0
    reason: str = ""


class Yard:
    """Stores containers in a block/bay/stack/tier grid."""

    def __init__(self, blocks: int, bays: int, stacks: int, tiers: int) -> None:
        self.blocks = blocks
        self.bays = bays
        self.stacks = stacks
        self.tiers = tiers
        self._grid: np.ndarray = np.zeros((blocks, bays, stacks, tiers), dtype=np.int64)
        self._containers: Dict[int, Container] = {}
        self._locations: Dict[int, YardLocation] = {}

    @property
    def grid(self) -> np.ndarray:
        return self._grid.copy()

    @property
    def container_count(self) -> int:
        return len(self._containers)

    def reset(self) -> None:
        self._grid.fill(0)
        self._containers.clear()
        self._locations.clear()

    def is_valid_stack(self, block: int, bay: int, stack: int) -> bool:
        return 0 <= block < self.blocks and 0 <= bay < self.bays and 0 <= stack < self.stacks

    def stack_height(self, block: int, bay: int, stack: int) -> int:
        if not self.is_valid_stack(block, bay, stack):
            return self.tiers
        return int(np.count_nonzero(self._grid[block, bay, stack, :]))

    def can_place(self, block: int, bay: int, stack: int) -> bool:
        return self.is_valid_stack(block, bay, stack) and self.stack_height(block, bay, stack) < self.tiers

    def place(self, container: Container, block: int, bay: int, stack: int) -> PlacementResult:
        if container.id in self._containers:
            return PlacementResult(False, reason="container already placed")
        if not self.is_valid_stack(block, bay, stack):
            return PlacementResult(False, reason="stack coordinates out of bounds")
        height = self.stack_height(block, bay, stack)
        if height >= self.tiers:
            return PlacementResult(False, reason="stack full")

        location = (block, bay, stack, height)
        self._grid[location] = container.id
        self._containers[container.id] = container
        self._locations[container.id] = location
        return PlacementResult(True, location=location)

    def retrieve(self, container_id: int) -> RetrievalResult:
        location = self._locations.get(container_id)
        if location is None:
            return RetrievalResult(False, reason="container not in yard")

        block, bay, stack, tier = location
        rehandles = 0
        for upper_tier in range(self.tiers - 1, tier, -1):
            upper_id = int(self._grid[block, bay, stack, upper_tier])
            if upper_id == 0:
                continue
            upper_container = self._containers.pop(upper_id)
            self._locations.pop(upper_id)
            self._grid[block, bay, stack, upper_tier] = 0
            rehandles += 1
            self._relocate_blocking_container(upper_container, forbidden=(block, bay, stack))

        removed = self._containers.pop(container_id)
        self._locations.pop(container_id)
        self._grid[block, bay, stack, tier] = 0
        self._compact_stack(block, bay, stack)
        return RetrievalResult(True, container=removed, rehandles=rehandles)

    def due_containers(self, time: int) -> Iterable[Container]:
        return sorted(
            (container for container in self._containers.values() if container.deadline <= time),
            key=lambda item: (item.deadline, item.priority),
        )

    def overdue_count(self, time: int) -> int:
        return sum(1 for container in self._containers.values() if container.deadline < time)

    def location_of(self, container_id: int) -> Optional[YardLocation]:
        return self._locations.get(container_id)

    def get_container(self, container_id: int) -> Optional[Container]:
        """Return the stored container by ID, or ``None`` if not present."""
        return self._containers.get(container_id)

    def _relocate_blocking_container(self, container: Container, forbidden: tuple[int, int, int]) -> None:
        best: Optional[tuple[int, int, int]] = None
        best_height = self.tiers + 1
        for block in range(self.blocks):
            for bay in range(self.bays):
                for stack in range(self.stacks):
                    candidate = (block, bay, stack)
                    if candidate == forbidden or not self.can_place(block, bay, stack):
                        continue
                    height = self.stack_height(block, bay, stack)
                    if height < best_height:
                        best = candidate
                        best_height = height
        if best is None:
            raise RuntimeError("no free yard slot available for rehandling")
        self.place(container, *best)

    def _compact_stack(self, block: int, bay: int, stack: int) -> None:
        ids = [int(item) for item in self._grid[block, bay, stack, :] if int(item) != 0]
        self._grid[block, bay, stack, :] = 0
        for tier, container_id in enumerate(ids):
            self._grid[block, bay, stack, tier] = container_id
            self._locations[container_id] = (block, bay, stack, tier)
