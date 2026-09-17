#!/usr/bin/env python3
"""Unit tests for Phase 08 Scripted Warehouse Dispatcher (WMS)."""

import os
import sys
import pytest

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.training.fleet.warehouse_dispatcher import WarehouseDispatcher, BoxStatus


def test_dispatcher_inventory_initialization():
    dispatcher = WarehouseDispatcher()
    assert len(dispatcher.orders) == 16, "Must initialize 16 total tote boxes"

    north_boxes = [o for o in dispatcher.orders.values() if o.rack_name == "North"]
    south_boxes = [o for o in dispatcher.orders.values() if o.rack_name == "South"]

    assert len(north_boxes) == 8, "North rack must have 8 boxes"
    assert len(south_boxes) == 8, "South rack must have 8 boxes"

    # Verify 4 tiers present
    tiers_present = {o.tier for o in dispatcher.orders.values()}
    assert tiers_present == {1, 2, 3, 4}, "All 4 vertical tiers must be populated"


def test_dispatcher_order_assignment():
    dispatcher = WarehouseDispatcher()

    # AMR 1 at (-3.0, -1.0) requests task with empty tray
    task_amr1 = dispatcher.request_task_for_amr(amr_id=0, amr_pos=(-3.0, -1.0), stowed_count=0)
    assert task_amr1["action_type"] == "PICK_FROM_RACK"
    assert task_amr1["box_id"] >= 0

    assigned_order = dispatcher.orders[task_amr1["box_id"]]
    assert assigned_order.status == BoxStatus.ASSIGNED
    assert assigned_order.assigned_amr_id == 0

    # AMR 2 requests task with full tray (2/2) -> must be routed to conveyor dock
    task_amr2 = dispatcher.request_task_for_amr(amr_id=1, amr_pos=(0.0, 0.0), stowed_count=2)
    assert task_amr2["action_type"] == "DELIVER_TO_CONVEYOR"


def test_dispatcher_delivery_tracking():
    dispatcher = WarehouseDispatcher()
    task = dispatcher.request_task_for_amr(amr_id=0, amr_pos=(-2.0, -2.0), stowed_count=0)
    box_id = task["box_id"]

    dispatcher.mark_box_picked(box_id, amr_id=0)
    assert dispatcher.orders[box_id].status == BoxStatus.CARRIED

    dispatcher.mark_box_delivered(box_id)
    assert dispatcher.orders[box_id].status == BoxStatus.DELIVERED
    assert dispatcher.delivered_count == 1
    assert dispatcher.get_remaining_box_count() == 15
