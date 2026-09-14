# 03_GODOT_3D_DIGITAL_TWIN.md — Smart Warehouse AMR Fleet Digital Twin Phase Specification

- **Motivation/Background**: Autonomous mobile robot (AMR) fleets face severe scaling bottlenecks (intersection deadlocks, vendor lock-in) beyond 20–30 units. A 3D digital twin is required to validate MARL anti-deadlock routing, Goods-to-Person fulfillment, and VDA 5050 compliance.
- **Purpose**: Technical phase specification for the Godot 4 3D Smart Warehouse environment, procedural storage racking, lifter AMRs, and the VDA 5050 WebSocket telemetry bridge.
- **Overview Pipeline**: Implements the approved plan in [`plan_warehouse_godot_3d_env.md`](../../plan_warehouse_godot_3d_env.md) and provides the digital twin anchor for [`docs/PURPOSE.md`](../PURPOSE.md).
- **Detailed Plan**: §1 Scope & Acceptance Criteria; §2 VDA 5050 I/O Protocol; §3 Scene Hierarchy; §4 Kinematics & Yielding Logic; §5 Verification.
- **References**: [`docs/PURPOSE.md`](../PURPOSE.md), [`DREAM.txt`](../../DREAM.txt), [`plan_warehouse_godot_3d_env.md`](../../plan_warehouse_godot_3d_env.md).
- **Created**: 2026-09-14T23:10:00+07:00
- **Last Updated**: 2026-09-14T23:14:00+07:00

---

## Metadata

- **Phase ID**: `PHASE-03`
- **Phase Name**: `Smart Warehouse AMR Fleet 3D Digital Twin & VDA 5050 Bridge`
- **Status**: Completed
- **Target Directories**: [`godot/`](../../godot), [`src/utils/warehouse_bridge.py`](../src/utils/warehouse_bridge.py)

---

## 1. Scope & Objective

### Background
As codified in [`docs/PURPOSE.md`](../PURPOSE.md) and [`DREAM.txt`](../../DREAM.txt), the RAMemory platform develops a centralized "air traffic control" brain for multi-agent autonomous mobile robots (AGVs/AMRs) operating in automated fulfillment centers. This digital twin simulates the physical warehouse topology, 4-way intersection conflicts, and under-chassis pod transport.

### Goals & Acceptance Criteria
- [x] Full Godot 4 project skeleton initialized under [`godot/`](../../godot) with zero Python repository coupling.
- [x] High-detail warehouse floor with bidirectional lanes, green pedestrian walkways, and crosshatched 4-way intersection conflict zones.
- [x] Procedural racking generator ([`procedural_warehouse.gd`](../../godot/scripts/environment/procedural_warehouse.gd)) constructing storage aisles and spawning mobile shelf pods.
- [x] 4-Tier mobile shelf pods ([`shelf_pod.tscn`](../../godot/scenes/environment/shelf_pod.tscn)) with clearance for AMR entry and dynamic lifting.
- [x] Autonomous Lifter AMR ([`amr_robot.tscn`](../../godot/scenes/entities/amr_robot.tscn)) with elevating turntable, 3D billboard status tag, and 360° LED ring indicating real-time states (Green = Cruising, Yellow = Yielding at Intersection, Red = Safety Stop, Blue = Lifting, Cyan = Charging).
- [x] Goods-to-Person pick stations and automated floor contact charging docks.
- [x] Warehouse KPI HUD displaying Pick Rate (+15-25%), Active Fleet count, Deadlock Count (0), and Deadheading distance ratio.
- [x] Zero-dependency Python VDA 5050 WebSocket bridge server ([`src/utils/warehouse_bridge.py`](../src/utils/warehouse_bridge.py)).

---

## 2. VDA 5050 Telemetry Stream Schema

Broadcast over WebSocket port `9090`:
```json
{
  "vda5050_topic": "vda5050/v2/warehouse/state",
  "step": 42,
  "pick_rate_boost": 22.5,
  "deadlocks": 0,
  "deadheading_ratio": 13.8,
  "active_fleet_count": 4,
  "event": "VDA 5050 Order #43 Dispatched: AMR-03 -> Pod #3 -> Pick Station #1",
  "fleet": {
    "AMR-01": {"state": "CRUISING", "battery": 96.0, "x": -25.0, "z": 0.0},
    "AMR-02": {"state": "YIELDING", "battery": 94.0, "x": 0.0, "z": -8.0},
    "AMR-03": {"state": "TRANSPORTING", "battery": 98.0, "x": 18.0, "z": -10.0},
    "AMR-04": {"state": "CHARGING", "battery": 72.0, "x": -20.0, "z": -28.0}
  }
}
```

---

## 3. Verification & Run Instructions

```bash
# Terminal 1: Run Python VDA 5050 Bridge
python src/utils/warehouse_bridge.py

# Terminal 2: Run Godot Digital Twin
godot --path godot/
```
