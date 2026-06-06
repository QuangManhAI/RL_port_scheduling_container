"""Configuration helpers for the port simulation."""

from __future__ import annotations

from dataclasses import dataclass, field

from port_sim.models import Container, ContainerType, Ship


@dataclass(frozen=True)
class PortConfig:
    blocks: int = 2
    bays: int = 3
    stacks: int = 3
    tiers: int = 3
    quay_cranes: int = 2
    yard_cranes: int = 1
    quay_task_duration: int = 1
    yard_task_duration: int = 1
    max_time: int = 100
    schedule: tuple[Ship, ...] = field(default_factory=tuple)

    @property
    def action_count(self) -> int:
        return self.blocks * self.bays * self.stacks

    @property
    def yard_slots(self) -> int:
        return self.blocks * self.bays * self.stacks * self.tiers


def default_config() -> PortConfig:
    ships = (
        Ship(
            id=1,
            arrival_time=0,
            departure_time=12,
            containers=[
                Container(101, ContainerType.IMPORT, priority=1, deadline=5, weight=7.5),
                Container(102, ContainerType.IMPORT, priority=3, deadline=10, weight=9.0),
                Container(103, ContainerType.TRANSSHIPMENT, priority=2, deadline=8, weight=6.0),
            ],
        ),
        Ship(
            id=2,
            arrival_time=3,
            departure_time=18,
            containers=[
                Container(201, ContainerType.EXPORT, priority=4, deadline=16, weight=8.0),
                Container(202, ContainerType.IMPORT, priority=1, deadline=7, weight=5.5),
            ],
        ),
    )
    return PortConfig(schedule=ships)
