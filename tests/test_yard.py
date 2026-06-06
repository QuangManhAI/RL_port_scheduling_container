from port_sim.models import Container, ContainerType
from port_sim.yard import Yard


def container(container_id: int, deadline: int = 10) -> Container:
    return Container(
        id=container_id,
        type=ContainerType.IMPORT,
        priority=1,
        deadline=deadline,
    )


def test_place_uses_lowest_available_tier() -> None:
    yard = Yard(blocks=1, bays=1, stacks=1, tiers=3)

    first = yard.place(container(1), 0, 0, 0)
    second = yard.place(container(2), 0, 0, 0)

    assert first.valid
    assert first.location == (0, 0, 0, 0)
    assert second.valid
    assert second.location == (0, 0, 0, 1)


def test_full_stack_rejects_placement() -> None:
    yard = Yard(blocks=1, bays=1, stacks=1, tiers=1)

    assert yard.place(container(1), 0, 0, 0).valid
    result = yard.place(container(2), 0, 0, 0)

    assert not result.valid
    assert result.reason == "stack full"


def test_retrieve_blocked_container_counts_and_relocates_rehandles() -> None:
    yard = Yard(blocks=1, bays=1, stacks=2, tiers=3)
    yard.place(container(1), 0, 0, 0)
    yard.place(container(2), 0, 0, 0)

    result = yard.retrieve(1)

    assert result.found
    assert result.rehandles == 1
    assert yard.location_of(1) is None
    assert yard.location_of(2) == (0, 0, 1, 0)


def test_due_containers_are_ordered_by_deadline_then_priority() -> None:
    yard = Yard(blocks=1, bays=1, stacks=3, tiers=1)
    yard.place(Container(1, ContainerType.IMPORT, priority=5, deadline=4), 0, 0, 0)
    yard.place(Container(2, ContainerType.IMPORT, priority=1, deadline=4), 0, 0, 1)
    yard.place(Container(3, ContainerType.IMPORT, priority=1, deadline=3), 0, 0, 2)

    due_ids = [item.id for item in yard.due_containers(4)]

    assert due_ids == [3, 2, 1]
