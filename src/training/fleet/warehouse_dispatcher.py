#!/usr/bin/env python3
"""Deterministic Warehouse Management System (WMS) Order Dispatcher for Phase 08 Fleet.

Handles task allocation: assigns pick orders (rack, tier, slot) to available AMRs
based on distance and tray capacity, keeping task assignment decoupled from MAPPO spatial navigation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Tuple
import numpy as np


class BoxStatus(Enum):
    STORED = "STORED"
    ASSIGNED = "ASSIGNED"
    CARRIED = "CARRIED"
    DELIVERED = "DELIVERED"


@dataclass
class ToteOrder:
    box_id: int
    rack_name: str          # "North" or "South"
    tier: int               # 1 to 4
    slot: str               # "L" or "R"
    world_pos: Tuple[float, float, float]
    status: BoxStatus = BoxStatus.STORED
    assigned_amr_id: Optional[int] = None


class WarehouseDispatcher:
    """Scripted WMS Dispatcher managing 16 physical tote boxes across dual racks."""

    def __init__(self) -> None:
        self.orders: Dict[int, ToteOrder] = {}
        self.delivered_count: int = 0
        self._init_warehouse_inventory()

    def _init_warehouse_inventory(self) -> None:
        """Initialize all 16 ToteBoxes across North Rack and South Rack."""
        self.orders.clear()
        self.delivered_count = 0

        # Tier heights matching 07_RACK_TRAINING_SPEC.md
        tier_y = {1: 0.56, 2: 1.11, 3: 1.67, 4: 2.23}
        slot_x = {"L": -0.36, "R": 0.36}

        # 8 Boxes on North Rack (Z = -3.4m)
        box_idx = 0
        for tier in range(1, 5):
            for slot in ["L", "R"]:
                # Facing south (+Z): Left is +0.36 in world, Right is -0.36
                wx = slot_x[slot] if slot == "R" else -slot_x[slot]
                self.orders[box_idx] = ToteOrder(
                    box_id=box_idx,
                    rack_name="North",
                    tier=tier,
                    slot=slot,
                    world_pos=(wx, tier_y[tier], -3.4),
                )
                box_idx += 1

        # 8 Boxes on South Rack (Z = +3.4m)
        for tier in range(1, 5):
            for slot in ["L", "R"]:
                wx = slot_x[slot]
                self.orders[box_idx] = ToteOrder(
                    box_id=box_idx,
                    rack_name="South",
                    tier=tier,
                    slot=slot,
                    world_pos=(wx, tier_y[tier], 3.4),
                )
                box_idx += 1

    def reset(self) -> None:
        """Reset all box inventory to STORED state."""
        self._init_warehouse_inventory()

    def request_task_for_amr(
        self,
        amr_id: int,
        amr_pos: Tuple[float, float],
        stowed_count: int,
        conveyor_pos: Tuple[float, float] = (5.5, 0.0),
    ) -> Dict[str, Any]:
        """Assign next optimal sub-goal for an AMR based on current state and capacity.
        
        Args:
            amr_id: Unique robot index.
            amr_pos: (x, z) coordinates of AMR.
            stowed_count: Number of boxes currently in robot's cargo tray.
            conveyor_pos: (x, z) coordinates of conveyor dock.
            
        Returns:
            Dictionary with task details and target sub-goal coordinate.
        """
        # If tray is full (2/2), robot must proceed directly to conveyor dock
        if stowed_count >= 2:
            return {
                "action_type": "DELIVER_TO_CONVEYOR",
                "target_pos": (conveyor_pos[0], 0.77, conveyor_pos[1]),
                "box_id": -1,
            }

        # Check for unassigned stored boxes
        available_orders = [o for o in self.orders.values() if o.status == BoxStatus.STORED]

        if not available_orders:
            # If no more stored boxes, deliver whatever is stowed or park
            if stowed_count > 0:
                return {
                    "action_type": "DELIVER_TO_CONVEYOR",
                    "target_pos": (conveyor_pos[0], 0.77, conveyor_pos[1]),
                    "box_id": -1,
                }
            return {
                "action_type": "IDLE_PARK",
                "target_pos": (amr_pos[0], 0.02, amr_pos[1]),
                "box_id": -1,
            }

        # Select closest available box to AMR
        best_order: Optional[ToteOrder] = None
        min_dist = float("inf")

        for order in available_orders:
            dx = order.world_pos[0] - amr_pos[0]
            dz = order.world_pos[2] - amr_pos[1]
            dist = (dx**2 + dz**2)**0.5

            if dist < min_dist:
                min_dist = dist
                best_order = order

        if best_order:
            best_order.status = BoxStatus.ASSIGNED
            best_order.assigned_amr_id = amr_id
            return {
                "action_type": "PICK_FROM_RACK",
                "box_id": best_order.box_id,
                "rack": best_order.rack_name,
                "tier": best_order.tier,
                "slot": best_order.slot,
                "target_pos": best_order.world_pos,
            }

        return {
            "action_type": "IDLE_PARK",
            "target_pos": (amr_pos[0], 0.02, amr_pos[1]),
            "box_id": -1,
        }

    def mark_box_picked(self, box_id: int, amr_id: int) -> None:
        """Mark box as gripped or stowed by an AMR."""
        if box_id in self.orders:
            self.orders[box_id].status = BoxStatus.CARRIED
            self.orders[box_id].assigned_amr_id = amr_id

    def mark_box_delivered(self, box_id: int) -> None:
        """Mark box as placed onto conveyor belt."""
        if box_id in self.orders:
            self.orders[box_id].status = BoxStatus.DELIVERED
            self.orders[box_id].assigned_amr_id = None
            self.delivered_count += 1

    def get_remaining_box_count(self) -> int:
        """Count boxes still needing delivery."""
        return sum(1 for o in self.orders.values() if o.status != BoxStatus.DELIVERED)
