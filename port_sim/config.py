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

    # Reward weights
    weight_valid_placement: float = 10.0
    weight_invalid_placement: float = -20.0
    weight_ship_complete: float = 5.0
    weight_rehandling_penalty: float = -1.0
    weight_delay_penalty: float = -2.0
    weight_idle_penalty: float = -1.0
    weight_distance_penalty: float = -0.1

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


def medium_config() -> PortConfig:
    """480-slot yard (4×6×5×4), 42 containers, 7 ships, 3 QC + 2 YC."""
    I = ContainerType.IMPORT
    E = ContainerType.EXPORT
    T = ContainerType.TRANSSHIPMENT
    C = Container

    ships = (
        Ship(
            id=1,
            arrival_time=0,
            departure_time=30,
            containers=[
                C(101, I, priority=2, deadline=12, weight=8.5),
                C(102, I, priority=1, deadline=8, weight=12.0),
                C(103, I, priority=3, deadline=15, weight=6.5),
                C(104, T, priority=2, deadline=20, weight=9.0),
                C(105, I, priority=4, deadline=25, weight=7.0),
                C(106, I, priority=1, deadline=10, weight=15.5),
                C(107, E, priority=3, deadline=28, weight=11.0),
            ],
        ),
        Ship(
            id=2,
            arrival_time=5,
            departure_time=40,
            containers=[
                C(201, I, priority=2, deadline=15, weight=10.0),
                C(202, E, priority=3, deadline=35, weight=8.0),
                C(203, I, priority=1, deadline=12, weight=13.5),
                C(204, T, priority=4, deadline=30, weight=7.5),
                C(205, I, priority=2, deadline=18, weight=9.5),
                C(206, E, priority=1, deadline=22, weight=14.0),
            ],
        ),
        Ship(
            id=3,
            arrival_time=10,
            departure_time=50,
            containers=[
                C(301, I, priority=1, deadline=20, weight=11.0),
                C(302, I, priority=3, deadline=25, weight=8.5),
                C(303, I, priority=2, deadline=18, weight=16.0),
                C(304, T, priority=1, deadline=22, weight=6.0),
                C(305, I, priority=4, deadline=35, weight=9.0),
                C(306, I, priority=2, deadline=28, weight=12.5),
                C(307, E, priority=3, deadline=40, weight=7.5),
                C(308, I, priority=1, deadline=15, weight=20.0),
            ],
        ),
        Ship(
            id=4,
            arrival_time=20,
            departure_time=60,
            containers=[
                C(401, E, priority=2, deadline=45, weight=10.5),
                C(402, E, priority=1, deadline=38, weight=13.0),
                C(403, I, priority=3, deadline=30, weight=8.0),
                C(404, E, priority=5, deadline=55, weight=6.5),
                C(405, T, priority=2, deadline=40, weight=11.5),
            ],
        ),
        Ship(
            id=5,
            arrival_time=30,
            departure_time=70,
            containers=[
                C(501, I, priority=1, deadline=40, weight=14.0),
                C(502, T, priority=3, deadline=50, weight=7.0),
                C(503, I, priority=2, deadline=35, weight=9.5),
                C(504, E, priority=1, deadline=45, weight=18.0),
                C(505, I, priority=4, deadline=55, weight=8.0),
                C(506, I, priority=2, deadline=42, weight=10.0),
            ],
        ),
        Ship(
            id=6,
            arrival_time=40,
            departure_time=80,
            containers=[
                C(601, T, priority=1, deadline=50, weight=12.0),
                C(602, T, priority=3, deadline=55, weight=8.5),
                C(603, I, priority=2, deadline=48, weight=15.0),
                C(604, E, priority=1, deadline=60, weight=7.0),
                C(605, T, priority=4, deadline=65, weight=9.5),
            ],
        ),
        Ship(
            id=7,
            arrival_time=50,
            departure_time=90,
            containers=[
                C(701, I, priority=2, deadline=60, weight=11.0),
                C(702, E, priority=1, deadline=55, weight=13.5),
                C(703, I, priority=3, deadline=65, weight=8.0),
                C(704, T, priority=2, deadline=70, weight=10.5),
                C(705, I, priority=1, deadline=58, weight=16.5),
            ],
        ),
    )
    return PortConfig(
        blocks=4,
        bays=6,
        stacks=5,
        tiers=4,
        quay_cranes=3,
        yard_cranes=2,
        max_time=200,
        schedule=ships,
    )
