"""Domain models for the port simulation."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from typing import Optional, Tuple


class ContainerType(IntEnum):
    IMPORT = 0
    EXPORT = 1
    TRANSSHIPMENT = 2


YardLocation = Tuple[int, int, int, int]


@dataclass(frozen=True)
class Container:
    id: int
    type: ContainerType
    priority: int
    deadline: int
    weight: float = 1.0
    destination_ship_id: Optional[int] = None


@dataclass
class Ship:
    id: int
    arrival_time: int
    departure_time: int
    containers: list[Container] = field(default_factory=list)
    arrived: bool = False
    departed: bool = False
    unloaded_count: int = 0

    @property
    def unloading_complete(self) -> bool:
        return self.unloaded_count >= len(self.containers)

    def next_container(self) -> Optional[Container]:
        if self.unloaded_count >= len(self.containers):
            return None
        return self.containers[self.unloaded_count]

    def mark_unloaded(self) -> None:
        if self.unloaded_count < len(self.containers):
            self.unloaded_count += 1
