# Walkthrough: Smart Warehouse AMR Fleet 3D Digital Twin (Godot 4)

- **Document Type**: Engineering Walkthrough & Delivery Record
- **Component**: [`godot/`](../godot), [`src/utils/warehouse_bridge.py`](../src/utils/warehouse_bridge.py), [`docs/phases/03_GODOT_3D_DIGITAL_TWIN.md`](phases/03_GODOT_3D_DIGITAL_TWIN.md)
- **Authoritative Charter**: [`docs/PURPOSE.md`](PURPOSE.md) & [`DREAM.txt`](../DREAM.txt)
- **Status**: Completed & Verified

---

## 1. What Was Accomplished

The 3D environment in Godot has been completely rebuilt to physically and functionally match the **Smart Warehouse Multi-Agent AMR/AGV Fleet Coordination Platform (RAMemory)** defined in [`docs/PURPOSE.md`](PURPOSE.md):

### 1.1 Complete Retirement of Legacy Port Assets
- All maritime assets (ships, berths, quay cranes, ocean water planes, container yard slots) were completely removed from `godot/` and replaced with automated warehouse fulfillment assets.

### 1.2 Warehouse Infrastructure & Procedural Storage Grid
- **Warehouse Building & Floor ([`scenes/environment/warehouse_floor.tscn`](../godot/scenes/environment/warehouse_floor.tscn))**: High-ceiling logistics facility with polished concrete slab, walls, yellow bidirectional travel aisles, green pedestrian safety paths, and a crosshatched 4-way conflict intersection.
- **Procedural Aisle Generator ([`scripts/environment/procedural_warehouse.gd`](../godot/scripts/environment/procedural_warehouse.gd))**: Generates storage aisles and spawns mobile shelf pods at designated inventory coordinates.
- **4-Tier Mobile Shelf Pods ([`scenes/environment/shelf_pod.tscn`](../godot/scenes/environment/shelf_pod.tscn))**: Heavy-duty storage racks with under-chassis clearance and colorful SKU inventory bins (blue, yellow, green, red). Can be elevated and moved by AMRs.
- **Goods-to-Person Pick Stations ([`scenes/environment/pick_station.tscn`](../godot/scenes/environment/pick_station.tscn))**: Order fulfillment workstations with conveyor rollers, packing desks, and operator monitors.
- **Automated Floor Charging Docks ([`scenes/environment/charging_station.tscn`](../godot/scenes/environment/charging_station.tscn))**: Floor contact charging pads.

### 1.3 Autonomous Lifter AMRs ([`scenes/entities/amr_robot.tscn`](../godot/scenes/entities/amr_robot.tscn))
- Sleek low-profile chassis with motorized elevating turntable for lifting shelf pods.
- **360° Multi-Color State LED Ring**:
  - 🟢 **Green**: Cruising normally along aisles.
  - 🟡 **Yellow**: **Yielding at intersection** (demonstrating MARL Anti-Deadlock priority negotiation).
  - 🔴 **Red**: OR Safety Guardrail Obstacle Detection.
  - 🔵 **Blue**: Docking beneath pod / raising turntable.
  - ⚡ **Cyan**: Charging on floor dock.
- Floating 3D billboard tag displaying Robot ID (`AMR-01`..`04`), live battery gauge, and current task.

### 1.4 Warehouse Camera Rig & Real-Time Dashboard
- **RTS Camera Rig ([`scripts/ui/camera_rig.gd`](../godot/scripts/ui/camera_rig.gd))**: Smooth WASD panning, mouse orbit/tilt, wheel zoom, and instant preset view switching (`1`: High-Angle Overview, `2`: Top-down 2D Traffic & Intersection Map, `3`: Pick Station close-up, `4`: Charging Dock close-up).
- **Warehouse KPI HUD ([`scenes/ui/hud.tscn`](../godot/scenes/ui/hud.tscn))**: Real-time KPI cards for **Pick Rate** (+22.5%), **Active Fleet** (4 AMRs), **Deadlock Count** (0 - 100% Anti-Deadlock), and **Deadheading Ratio** (13.8%), with interactive buttons: **Simulate 4-Way Conflict**, **Dispatch Order**, **Auto Fleet Run**, and **Reset Floor**.

### 1.5 Python VDA 5050 Telemetry Bridge ([`src/utils/warehouse_bridge.py`](../src/utils/warehouse_bridge.py))
- Zero-dependency WebSocket server on `ws://127.0.0.1:9090` broadcasting VDA 5050 messages, multi-agent fleet coordinates, and fulfillment events.
- Unit tests verified in [`tests/test_warehouse_bridge.py`](../tests/test_warehouse_bridge.py).

---

## 2. Verification & Run Instructions

```bash
# Terminal 1 (Optional): Start Python VDA 5050 Bridge
python src/utils/warehouse_bridge.py

# Terminal 2: Run Godot Digital Twin
godot --path godot/
```

### Interactive Test Scenarios in Godot:
1. **Anti-Deadlock Yielding Test**: Click **"Simulate 4-Way Conflict"**. Watch AMR-01 (West $\to$ East) and AMR-02 (North $\to$ South) approach the intersection simultaneously. Dynamic yielding activates: AMR-02 illuminates yellow, halts outside the hazard zone, yields right-of-way, and proceeds safely once the intersection is clear. **Zero deadlocks occur.**
2. **Goods-to-Person Dispatch Test**: Click **"Dispatch Order"**. Watch AMR-03 navigate down an aisle, slide beneath Shelf Pod #3, raise its turntable, transport the pod to Pick Station #1, and log order completion.
3. **Preset Camera Views**: Press keys **`1`**, **`2`**, **`3`**, **`4`** to switch between tactical overviews and close-up workstation cameras.
