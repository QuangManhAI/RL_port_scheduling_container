# 03_GODOT_3D_DIGITAL_TWIN.md — Godot 4 3D Digital Twin & Simulation Phase Specification

- **Motivation/Background**: Real-time 3D observability and autonomous simulation of container port scheduling and AGV fleet routing are required to validate reinforcement learning models and deliver the digital twin promised in the strategic charter.
- **Purpose**: Provide the technical phase specification for the Godot 4 3D environment, procedural yard generation, kinematic crane/vehicle controllers, and the Python WebSocket telemetry bridge.
- **Overview Pipeline**: Implements the approved plan in [`plan_godot_3d_env.md`](../../plan_godot_3d_env.md) and bridges [`src/port_sim/`](../src/port_sim) with [`godot/`](../../godot).
- **Detailed Plan**: §1 Scope & Acceptance Criteria; §2 Input & Output Protocol Contracts; §3 Scene Hierarchy & Component Architecture; §4 Kinematics & Procedural Logic; §5 Verification & Run Instructions.
- **References**: [`docs/PURPOSE.md`](../PURPOSE.md), [`plan_godot_3d_env.md`](../../plan_godot_3d_env.md), [`agents/rules/MD_CONVENTION.md`](../../agents/rules/MD_CONVENTION.md).
- **Created**: 2026-09-14T22:38:00+07:00
- **Last Updated**: 2026-09-14T22:38:00+07:00

---

## Metadata

- **Phase ID**: `PHASE-03`
- **Phase Name**: `Godot 4 3D Digital Twin & Telemetry Bridge`
- **Status**: Completed
- **Target Directories**: [`godot/`](../../godot), [`src/utils/godot_bridge.py`](../src/utils/godot_bridge.py)

---

## 1. Scope & Objective

### Background
Container yard logistics require fine-grained spatial coordination of quay cranes, yard cranes (RTGs), and transport vehicles (AGVs/AMRs). While [`src/port_sim`](../src/port_sim) implements the discrete mathematical state transitions and rewards, human researchers and industrial stakeholders require a full-fidelity 3D Digital Twin environment to visualize congestion points, rehandling maneuvers, and vessel turnaround times.

### Goals & Acceptance Criteria
- [x] Full Godot 4 project skeleton initialized under [`godot/`](../../godot) with zero Python repository contamination.
- [x] Procedural yard generator ([`godot/scripts/environment/procedural_yard.gd`](../../godot/scripts/environment/procedural_yard.gd)) automatically constructing blocks, bays, stacks, and tiers matching [`src/port_sim/config.py`](../src/port_sim/config.py).
- [x] Standardized 20ft ISO container entity ([`godot/scenes/entities/container.tscn`](../../godot/scenes/entities/container.tscn)) with dynamic PBR materials color-coded by type (Import = Blue, Export = Green, Transshipment = Amber).
- [x] 3D Infrastructure: Berth dock, water plane with custom wave shader, moored container vessel, STS quay crane, and AGV platform.
- [x] RTS Simulation Camera Rig supporting WASD panning, mouse orbit/tilt, wheel zoom, and isometric/top-down preset angles (`1`, `2`, `3`).
- [x] Industrial HUD overlay displaying real-time KPIs (Step, Sim Time, Accumulated Reward) and simulation controls (Step, Auto-Run, Reset).
- [x] Zero-dependency Python WebSocket server ([`src/utils/godot_bridge.py`](../src/utils/godot_bridge.py)) streaming live telemetry to Godot over `ws://127.0.0.1:9090`.

---

## 2. Input & Output Contracts

### Telemetry Stream Schema (`Python -> Godot`)
Broadcast over WebSocket port `9090`:
```json
{
  "step": 42,
  "sim_time": 42.0,
  "reward": 10.0,
  "accum_reward": 320.0,
  "yard_grid": [
    [
      [
        [{"id": 101, "type": 0}, {"id": 102, "type": 1}, null],
        [null, null, null]
      ]
    ]
  ],
  "event": "Step 42: Action 14 -> Reward +10.00",
  "active_ships": 1,
  "pending_containers": 12
}
```

### Command Protocol (`Godot -> Python`)
Sent from Godot client to Python bridge:
```json
{"command": "step"}
{"command": "reset"}
{"command": "auto_run", "enabled": true}
```

---

## 3. Scene Hierarchy & Directory Map

```text
godot/
├── project.godot                          # Godot 4.3 configuration
├── icon.svg                               # Application icon
├── scenes/
│   ├── main.tscn                          # Master integrated scene
│   ├── environment/
│   │   ├── water.tscn                     # PBR wave water surface
│   │   ├── berth.tscn                     # Concrete apron & crane tracks
│   │   └── yard_grid.tscn                 # Procedural yard container grid
│   ├── entities/
│   │   ├── container.tscn                 # 20ft ISO container with PBR material
│   │   ├── quay_crane.tscn                # STS Gantry crane
│   │   ├── agv.tscn                       # Autonomous mobile platform
│   │   └── ship.tscn                      # Moored cargo vessel
│   └── ui/
│       ├── camera_controller.tscn         # RTS camera rig
│       └── hud.tscn                       # KPI dashboard & controls
└── scripts/
    ├── main.gd                            # Master controller
    ├── bridge/
    │   └── sim_client.gd                  # WebSocket client
    ├── environment/
    │   ├── procedural_yard.gd             # Procedural slot generation
    │   └── water_shader.gdshader          # Vertex wave shader
    ├── entities/
    │   ├── container.gd                   # PBR material & animations
    │   ├── quay_crane.gd                  # 3-axis crane kinematics
    │   ├── agv_agent.gd                   # Vehicle navigation
    │   └── ship.gd                        # Vessel cargo state
    └── ui/
        ├── camera_rig.gd                  # Orbit / pan / zoom
        └── hud.gd                         # Telemetry & event log
```

---

## 4. Execution & Verification

### Running the Python Bridge
```bash
python src/utils/godot_bridge.py --scenario default
```

### Launching the 3D Digital Twin
Open [`godot/project.godot`](../../godot/project.godot) in the Godot 4 Editor or run via command line:
```bash
godot --path godot/
```
