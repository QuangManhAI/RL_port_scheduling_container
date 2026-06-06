"""Abstract crane resources and task queues."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Optional


class CraneKind(IntEnum):
    QUAY = 0
    YARD = 1


@dataclass
class CraneTask:
    kind: CraneKind
    container_id: int
    duration: int
    description: str


@dataclass
class Crane:
    id: int
    kind: CraneKind
    remaining_time: int = 0
    task: Optional[CraneTask] = None

    @property
    def available(self) -> bool:
        return self.task is None

    def assign(self, task: CraneTask) -> bool:
        if not self.available:
            return False
        self.task = task
        self.remaining_time = max(1, task.duration)
        return True

    def tick(self) -> Optional[CraneTask]:
        if self.task is None:
            return None
        self.remaining_time -= 1
        if self.remaining_time > 0:
            return None
        completed = self.task
        self.task = None
        self.remaining_time = 0
        return completed


class CranePool:
    def __init__(self, quay_cranes: int, yard_cranes: int) -> None:
        self.cranes = [
            Crane(id=i, kind=CraneKind.QUAY) for i in range(quay_cranes)
        ] + [
            Crane(id=quay_cranes + i, kind=CraneKind.YARD) for i in range(yard_cranes)
        ]

    def reset(self) -> None:
        for crane in self.cranes:
            crane.task = None
            crane.remaining_time = 0

    def assign_first_available(self, task: CraneTask) -> bool:
        for crane in self.cranes:
            if crane.kind == task.kind and crane.assign(task):
                return True
        return False

    def tick(self) -> list[CraneTask]:
        completed = []
        for crane in self.cranes:
            task = crane.tick()
            if task is not None:
                completed.append(task)
        return completed

    def availability_vector(self) -> list[int]:
        return [1 if crane.available else 0 for crane in self.cranes]

    def idle_count(self, kind: CraneKind) -> int:
        return sum(1 for crane in self.cranes if crane.kind == kind and crane.available)
