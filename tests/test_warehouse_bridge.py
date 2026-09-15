"""Unit tests for Smart Warehouse VDA 5050 WebSocket Bridge."""

import unittest
from src.utils.warehouse_bridge import WarehouseFleetOrchestrator


class TestWarehouseBridge(unittest.TestCase):
    """Test suite for VDA 5050 fleet orchestrator and state snapshots."""

    def test_warehouse_orchestrator_initialization(self) -> None:
        orchestrator = WarehouseFleetOrchestrator()
        snapshot = orchestrator.get_state_snapshot("Initial State")

        self.assertEqual(snapshot["vda5050_topic"], "vda5050/v2/warehouse/state")
        self.assertGreaterEqual(snapshot["pick_rate_boost"], 15.0)  # Must satisfy +15-25% target
        self.assertEqual(snapshot["deadlocks"], 0)                  # 0 deadlocks (100% Anti-Deadlock)
        self.assertLessEqual(snapshot["deadheading_ratio"], 20.0)   # Reduced deadheading
        self.assertEqual(snapshot["active_fleet_count"], 4)
        self.assertIn("AMR-01", snapshot["fleet"])
        self.assertIn("AMR-02", snapshot["fleet"])


if __name__ == "__main__":
    unittest.main()
