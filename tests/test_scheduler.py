from port_sim.config import default_config
from port_sim.scheduler import ShipScheduler


def test_scheduler_releases_ships_by_arrival_time() -> None:
    scheduler = ShipScheduler(default_config().schedule)

    scheduler.update_arrivals(0)
    active_at_zero = [ship.id for ship in scheduler.active_ships(0)]
    scheduler.update_arrivals(3)
    active_at_three = [ship.id for ship in scheduler.active_ships(3)]

    assert active_at_zero == [1]
    assert active_at_three == [1, 2]


def test_scheduler_selects_next_container_by_departure_urgency() -> None:
    scheduler = ShipScheduler(default_config().schedule)
    scheduler.update_arrivals(3)

    ship, container = scheduler.next_container(3)

    assert ship.id == 1
    assert container.id == 101


def test_mark_loaded_reports_completion_once() -> None:
    scheduler = ShipScheduler(default_config().schedule)

    assert scheduler.mark_loaded_to_yard(2) is False
    assert scheduler.mark_loaded_to_yard(2) is True
    assert scheduler.mark_loaded_to_yard(2) is False
