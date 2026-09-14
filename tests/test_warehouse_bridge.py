"""Unit tests for Smart Warehouse VDA 5050 WebSocket Bridge."""

from src.utils.warehouse_bridge import WarehouseFleetOrchestrator


def test_warehouse_orchestrator_initialization() -> None:
    orchestrator = WarehouseFleetOrchestrator()
    snapshot = orchestrator.get_state_snapshot("Initial State")

    assert snapshot["vda5050_topic"] == "vda5050/v2/warehouse/state"
    assert snapshot["pick_rate_boost"] >= 15.0  # Must satisfy +15-25% target
    assert snapshot["deadlocks"] == 0           # 0 deadlocks (100% Anti-Deadlock)
    assert snapshot["deadheading_ratio"] <= 20.0 # Reduced deadheading
    assert snapshot["active_fleet_count"] == 4
    assert "AMR-01" in snapshot["fleet"]
    assert "AMR-02" in snapshot["fleet"]
