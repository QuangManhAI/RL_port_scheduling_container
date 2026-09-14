"""Unit tests for Godot 3D Digital Twin WebSocket Bridge."""

from src.utils.godot_bridge import PortEnvGodotBridge


def test_bridge_initialization() -> None:
    bridge = PortEnvGodotBridge(scenario="default")
    assert bridge.step_count == 0
    assert bridge.accum_reward == 0.0

    snapshot = bridge.get_state_snapshot("Init")
    assert snapshot["step"] == 0
    assert snapshot["sim_time"] == 0.0
    assert "yard_grid" in snapshot
    assert "active_ships" in snapshot

    # Check 4D yard grid dimensions: [blocks][bays][stacks][tiers]
    grid = snapshot["yard_grid"]
    assert len(grid) == bridge.env.yard.blocks
    assert len(grid[0]) == bridge.env.yard.bays
    assert len(grid[0][0]) == bridge.env.yard.stacks
    assert len(grid[0][0][0]) == bridge.env.yard.tiers


def test_bridge_step_and_reset() -> None:
    bridge = PortEnvGodotBridge(scenario="default")
    step_state = bridge.step_env()

    assert step_state["step"] == 1
    assert "reward" in step_state
    assert "accum_reward" in step_state

    # Verify reset
    reset_state = bridge.reset_env()
    assert reset_state["step"] == 0
    assert reset_state["accum_reward"] == 0.0
