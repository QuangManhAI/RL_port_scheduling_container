"""Ship schedule management."""

from __future__ import annotations

from copy import deepcopy
from typing import Optional

from port_sim.models import Container, Ship


class ShipScheduler:
    def __init__(self, ships: tuple[Ship, ...]) -> None:
        self._initial_ships = tuple(deepcopy(ships))
        self.ships: list[Ship] = []
        self.reset()

    def reset(self) -> None:
        self.ships = list(deepcopy(self._initial_ships))

    def update_arrivals(self, time: int) -> None:
        for ship in self.ships:
            if not ship.arrived and ship.arrival_time <= time:
                ship.arrived = True

    def active_ships(self, time: int) -> list[Ship]:
        return [
            ship
            for ship in self.ships
            if ship.arrived and not ship.departed and ship.departure_time >= time
        ]

    def next_container(self, time: int) -> Optional[tuple[Ship, Container]]:
        candidates = []
        for ship in self.active_ships(time):
            container = ship.next_container()
            if container is not None:
                candidates.append((ship.departure_time, ship.id, ship, container))
        if not candidates:
            return None
        _, _, ship, container = sorted(candidates, key=lambda item: (item[0], item[1]))[0]
        return ship, container

    def mark_loaded_to_yard(self, ship_id: int) -> bool:
        ship = self.ship_by_id(ship_id)
        if ship is None:
            return False
        before = ship.unloading_complete
        ship.mark_unloaded()
        return not before and ship.unloading_complete

    def mark_departures(self, time: int) -> None:
        for ship in self.ships:
            if ship.arrived and not ship.departed and ship.departure_time < time:
                ship.departed = True

    def all_complete(self) -> bool:
        return all(ship.unloading_complete for ship in self.ships)

    def ship_by_id(self, ship_id: int) -> Optional[Ship]:
        for ship in self.ships:
            if ship.id == ship_id:
                return ship
        return None

    def snapshot(self, time: int, limit: int = 5) -> list[list[int]]:
        rows = []
        for ship in sorted(self.ships, key=lambda item: (item.arrival_time, item.id))[:limit]:
            rows.append(
                [
                    ship.id,
                    ship.arrival_time,
                    ship.departure_time,
                    int(ship.arrived),
                    int(ship.departed),
                    len(ship.containers) - ship.unloaded_count,
                    max(0, ship.departure_time - time),
                ]
            )
        while len(rows) < limit:
            rows.append([0, 0, 0, 0, 0, 0, 0])
        return rows
