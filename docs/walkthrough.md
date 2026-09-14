# Walkthrough: Godot 4 3D Digital Twin & Simulation Environment

- **Document Type**: Engineering Walkthrough & Delivery Record
- **Component**: [`godot/`](../godot), [`src/utils/godot_bridge.py`](../src/utils/godot_bridge.py), [`docs/phases/03_GODOT_3D_DIGITAL_TWIN.md`](phases/03_GODOT_3D_DIGITAL_TWIN.md)
- **Status**: Completed & Verified
- **Created**: 2026-09-14T22:40:00+07:00
- **Last Updated**: 2026-09-14T22:47:00+07:00

---

## 1. What Was Accomplished

Following approval of the implementation plan, the entire **Godot 4 3D Digital Twin & Simulation Environment** has been scaffolded and implemented to match the strategic charter in [`docs/PURPOSE.md`](PURPOSE.md).

### 1.1 Complete Godot 4 Project Setup ([`godot/`](../godot))
- **Configuration:** [`godot/project.godot`](../godot/project.godot) configured for Godot 4.3 with Forward+ rendering, MSAA 3D anti-aliasing, screen-space ambient occlusion, and resizable 1920x1080 viewport.
- **Icon:** Vector icon [`godot/icon.svg`](../godot/icon.svg) depicting a digital container and port cranes.

### 1.2 3D Port Environment & Procedural Yard
- **Procedural Yard Generation:** [`godot/scripts/environment/procedural_yard.gd`](../godot/scripts/environment/procedural_yard.gd) dynamically generates concrete pads, stack boundaries, and container slots matching [`src/port_sim/config.py`](../src/port_sim/config.py) dimensions (`num_blocks`, `bays_per_block`, `stacks_per_bay`, `max_tiers`).
- **Water Shader:** [`godot/scripts/environment/water_shader.gdshader`](../godot/scripts/environment/water_shader.gdshader) with vertex wave displacement, depth-based color gradients, and specular reflections.
- **Berth & Quay Apron:** [`godot/scenes/environment/berth.tscn`](../godot/scenes/environment/berth.tscn) with concrete docks, crane rail tracks, and water safety curb.

### 1.3 Kinematic Entities & Dynamic Container Materials
- **ISO Containers:** [`godot/scripts/entities/container.gd`](../godot/scripts/entities/container.gd) and [`godot/scenes/entities/container.tscn`](../godot/scenes/entities/container.tscn) with PBR materials color-coded by type:
  - **Import**: Marine Blue (`#0077b6`)
  - **Export**: Emerald Green (`#2a9d8f`)
  - **Transshipment**: Sunset Amber (`#f4a261`)
  - Smooth tweened lifting/positioning and emission highlight pulsing.
- **Quay Crane (STS):** [`godot/scripts/entities/quay_crane.gd`](../godot/scripts/entities/quay_crane.gd) and [`godot/scenes/entities/quay_crane.tscn`](../godot/scenes/entities/quay_crane.tscn) featuring 3-axis motion (gantry X, trolley Z, spreader hoist Y).
- **AGV Transport Robot:** [`godot/scripts/entities/agv_agent.gd`](../godot/scripts/entities/agv_agent.gd) and [`godot/scenes/entities/agv.tscn`](../godot/scenes/entities/agv.tscn) with lockable deck bed for container transit.
- **Container Ship:** [`godot/scripts/entities/ship.gd`](../godot/scripts/entities/ship.gd) and [`godot/scenes/entities/ship.tscn`](../godot/scenes/entities/ship.tscn) docked along the berth.

### 1.4 Camera Rig & Interactive Digital Twin HUD
- **RTS Camera Controls:** [`godot/scripts/ui/camera_rig.gd`](../godot/scripts/ui/camera_rig.gd):
  - `WASD` / Arrow keys smooth horizontal panning.
  - Right Mouse Button / Middle Mouse Button orbit and pitch tilt.
  - Mouse wheel zoom with distance clamping.
  - Instant preset keys: `1` (Isometric), `2` (Top-down 2D), `3` (Quay close-up).
- **Industrial HUD Overlay:** [`godot/scripts/ui/hud.gd`](../godot/scripts/ui/hud.gd) and [`godot/scenes/ui/hud.tscn`](../godot/scenes/ui/hud.tscn) displaying real-time KPI cards (Step, Sim Time, Accumulated Reward), connection status badge, live event log, and Step/Auto-Run/Reset controls.

### 1.5 Zero-Dependency WebSocket Telemetry Bridge
- **Python Telemetry Server:** [`src/utils/godot_bridge.py`](../src/utils/godot_bridge.py) implements a pure Python `asyncio` WebSocket server on `ws://127.0.0.1:9090` without requiring external libraries.
- **Godot Client:** [`godot/scripts/bridge/sim_client.gd`](../godot/scripts/bridge/sim_client.gd) connects to the Python bridge and automatically syncs the 4D container yard state and KPI counters.
- **Master Controller:** [`godot/scripts/main.gd`](../godot/scripts/main.gd) connects HUD signals to the network bridge and handles offline fallback mode when no backend is running.

---

## 2. Directory Structure of Deliverables

```text
godot/
├── project.godot                          # Godot 4.3 project configuration
├── icon.svg                               # Digital twin application icon
├── README.md                              # Dedicated Godot user manual
├── scenes/
│   ├── main.tscn                          # Integrated master world scene
│   ├── environment/
│   │   ├── water.tscn                     # PBR water surface plane
│   │   ├── berth.tscn                     # Concrete quay & rail tracks
│   │   └── yard_grid.tscn                 # Procedural yard container grid
│   ├── entities/
│   │   ├── container.tscn                 # ISO container with PBR material
│   │   ├── quay_crane.tscn                # STS Gantry crane
│   │   ├── agv.tscn                       # Autonomous mobile platform
│   │   └── ship.tscn                      # Moored container vessel
│   └── ui/
│       ├── camera_controller.tscn         # RTS camera rig
│       └── hud.tscn                       # Real-time KPI dashboard overlay
└── scripts/
    ├── main.gd                            # Master controller & state dispatcher
    ├── bridge/
    │   └── sim_client.gd                  # WebSocket client bridge
    ├── environment/
    │   ├── procedural_yard.gd             # Procedural slot generation & sync
    │   └── water_shader.gdshader          # Vertex wave shader
    ├── entities/
    │   ├── container.gd                   # Dynamic coloring & tween animations
    │   ├── quay_crane.gd                  # 3-axis crane kinematics
    │   ├── agv_agent.gd                   # Vehicle navigation & deck locking
    │   └── ship.gd                        # Vessel cargo status
    └── ui/
        ├── camera_rig.gd                  # Orbit / pan / zoom / presets
        └── hud.gd                         # Telemetry display & button events

src/utils/
└── godot_bridge.py                        # Python WebSocket telemetry server

docs/phases/
└── 03_GODOT_3D_DIGITAL_TWIN.md            # Formal phase technical specification

tests/
└── test_bridge.py                         # Telemetry serialization unit tests
```

---

## 3. How to Run

### Step 1: Start the Python Simulation Bridge Server
```bash
python src/utils/godot_bridge.py --scenario default
```
*Output:*
```text
[*] Godot Bridge WebSocket Server listening on ws://127.0.0.1:9090
```

### Step 2: Open the 3D Digital Twin in Godot
Open [`godot/project.godot`](../godot/project.godot) in Godot 4 (Standard Edition) and press **F5** (Play Project), or run:
```bash
godot --path godot/
```

*Expected Experience:*
- **Offline / Standalone:** Opens instantly with a populated demo yard, operational RTS camera controls (`WASD`, Right-Click Orbit, Scroll Zoom, Presets `1`/`2`/`3`), and interactive HUD buttons.
- **Online with Python Bridge:** HUD connection badge turns green (`● ONLINE`), and pressing "Step" or "Auto Run" advances the simulation, updates the 3D yard grid in real time, and logs events.
