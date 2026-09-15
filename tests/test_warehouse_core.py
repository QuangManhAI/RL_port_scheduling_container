"""Unit tests for WarehouseGridMap and InventoryManager core modules."""

import unittest
from src.warehouse.core.grid_map import WarehouseGridMap, NodeType
from src.warehouse.core.inventory_manager import InventoryManager, SKUBox


class TestWarehouseGridMap(unittest.TestCase):
    """Test suite for spatial topological graph and routing."""

    def setUp(self) -> None:
        self.grid = WarehouseGridMap(cell_size=1.2)

    def test_facility_landmarks_exist(self) -> None:
        """Verify essential workstations, docks, and intersections are registered."""
        self.assertIsNotNone(self.grid.get_node("INBOUND_DOCK_1"))
        self.assertIsNotNone(self.grid.get_node("INBOUND_DOCK_2"))
        self.assertIsNotNone(self.grid.get_node("PICK_STN_1"))
        self.assertIsNotNone(self.grid.get_node("PICK_STN_2"))
        self.assertIsNotNone(self.grid.get_node("CHARGING_1"))
        self.assertIsNotNone(self.grid.get_node("CHARGING_2"))
        self.assertIsNotNone(self.grid.get_node("INT_CENTER"))

    def test_intersection_connectivity(self) -> None:
        """Verify the central 4-way intersection has 4 approach branches."""
        center = self.grid.get_node("INT_CENTER")
        self.assertIsNotNone(center)
        self.assertEqual(center.node_type, NodeType.INTERSECTION)
        self.assertIn("INT_N", center.neighbors)
        self.assertIn("INT_S", center.neighbors)
        self.assertIn("INT_W", center.neighbors)
        self.assertIn("INT_E", center.neighbors)

    def test_astar_pathfinding(self) -> None:
        """Verify A* search finds a valid path between Inbound Dock and Pick Station."""
        path = self.grid.find_path_astar("INBOUND_DOCK_1", "PICK_STN_1")
        self.assertGreater(len(path), 0)
        self.assertEqual(path[0], "INBOUND_DOCK_1")
        self.assertEqual(path[-1], "PICK_STN_1")
        self.assertIn("INT_CENTER", path)

    def test_closest_node_query(self) -> None:
        """Verify spatial coordinate resolution to nearest node."""
        closest = self.grid.get_closest_node(-0.2, 0.1)
        self.assertEqual(closest.node_id, "INT_CENTER")


class TestInventoryManager(unittest.TestCase):
    """Test suite for discrete rack slots and SKU box management."""

    def setUp(self) -> None:
        self.inv = InventoryManager(racks_per_zone=4, tiers_per_rack=4, slots_per_tier=4)

    def test_inventory_capacity(self) -> None:
        """Verify 256 total slots across 4 zones."""
        # 4 zones * 4 racks * 4 tiers * 4 slots = 256 slots
        summary = self.inv.get_inventory_summary()
        self.assertEqual(summary["total_slots"], 256)
        self.assertEqual(summary["occupied_slots"], 256)
        self.assertEqual(summary["empty_slots"], 0)
        self.assertEqual(summary["occupancy_rate_pct"], 100.0)

    def test_pick_and_stow_lifecycle(self) -> None:
        """Verify box retrieval empties the slot and allows replenishment."""
        slot_id = "Zone A_R1_T2_S1"
        slot = self.inv.get_slot(slot_id)
        self.assertIsNotNone(slot)
        self.assertTrue(slot.is_occupied)

        # 1. Pick box
        picked_box = self.inv.pick_box(slot_id)
        self.assertIsNotNone(picked_box)
        self.assertEqual(picked_box.category, "FMCG")
        self.assertFalse(slot.is_occupied)
        self.assertIsNone(slot.box)

        # Verify summary reflects 1 empty slot
        summary = self.inv.get_inventory_summary()
        self.assertEqual(summary["empty_slots"], 1)

        # 2. Find empty slot in Zone A
        empty_slot = self.inv.find_empty_slot("Zone A", preferred_tier=2)
        self.assertIsNotNone(empty_slot)
        self.assertEqual(empty_slot.slot_id, slot_id)

        # 3. Stow new inbound box
        new_box = SKUBox(
            box_id="BOX-INBOUND-9999",
            sku="FMCG Beverage",
            category="FMCG",
            color_hex="#00e5ff",
            weight_kg=5.5,
        )
        stow_success = self.inv.stow_box(slot_id, new_box)
        self.assertTrue(stow_success)
        self.assertTrue(slot.is_occupied)
        self.assertEqual(slot.box.box_id, "BOX-INBOUND-9999")


if __name__ == "__main__":
    unittest.main()
