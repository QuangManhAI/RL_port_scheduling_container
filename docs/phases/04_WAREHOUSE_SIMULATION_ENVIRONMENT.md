# 04_WAREHOUSE_SIMULATION_ENVIRONMENT.md — Smart Warehouse Simulation Environment Technical Specification

- **Motivation/Background**: Current simulation prototypes rely on predetermined tweens, mock conflict buttons, and visual approximations ("vibe code"). To validate the throughput (+15–25%), zero-deadlock, and deadheading reduction targets codified in `docs/PURPOSE.md`, the platform requires a physically grounded, mathematically deterministic warehouse simulation environment.
- **Purpose**: Specify the complete architectural blueprint, spatial topology, kinematic models, traffic conflict mechanics, fulfillment lifecycle, and I/O contracts for the core warehouse simulation environment.
- **Overview Pipeline**: Bridges high-level WES/Fleet dispatching with low-level Godot 3D visualization and Python VDA 5050 protocol handling.
- **Detailed Plan**: §1 Scope & Objective; §2 Input & Output Contracts; §3 Execution Pipeline; §4 Technical Specification & Mechanics (Topology, Kinematics, Traffic & Anti-Deadlock, Fulfillment Cycle); §5 Associated Links.
- **References**: `docs/PURPOSE.md`, `docs/DREAM/DREAM.md`, `agents/templates/PHASE_DOC_TEMPLATE.md`, `agents/rules/FOLDER_STRUCTURE.md`.
- **Created**: 2026-09-15T07:57:00+07:00
- **Last Updated**: 2026-09-15T07:57:00+07:00

---

## Metadata

- **Phase ID**: `PHASE-04`
- **Phase Name**: `Smart Warehouse Deterministic Simulation Environment & Core Mechanics Engine`
- **Status**: In Progress
- **Target Modules**: [`src/warehouse/`](../../src/warehouse), [`godot/scripts/`](../../godot/scripts), [`src/utils/warehouse_bridge.py`](../../src/utils/warehouse_bridge.py)

---

## 1. Scope & Objective

### Background
Modern Goods-to-Person (G2P) automated fulfillment warehouses operate hundreds of autonomous mobile robots (AMRs) navigating beneath mobile shelf pods. Moving beyond illustrative frontend animations requires a rigorous discrete-event or continuous-time physics engine that enforces spatial occupancy, acceleration/rotation kinematic limits, battery discharge rates, and multi-agent reservation tables.

### Goals & Acceptance Criteria
- [ ] **Directed Warehouse Topology Graph**: Mathematical grid representation where storage bays, travel lanes, 4-way intersections, pick stations, and inbound receiving docks are modeled as discrete vertices $V$ and directed edges $E$.
- [ ] **Rigorous AMR Kinematics**:
  - Distinct rotational velocity ($\omega \approx 180^\circ/\text{s}$) vs. translational linear velocity ($v_{\max} \approx 1.5\,\text{m/s}$).
  - Payload mass speed penalties ($v_{\text{loaded}} = 0.75 \times v_{\text{unloaded}}$).
  - Explicit under-chassis docking and elevating turntable lift stroke ($t_{\text{lift}} = 2.5\,\text{s}$).
- [ ] **Deterministic Anti-Deadlock Mechanics**:
  - Time-Space Reservation Table preventing simultaneous vertex and edge occupancy.
  - 4-Way intersection conflict zones requiring dynamic reservation or token yielding.
- [ ] **End-to-End Fulfillment Lifecycle**:
  - Inbound Receiving: Freight arrival at Dock $\to$ AMR dispatch $\to$ pod retrieval $\to$ dock stow $\to$ storage return.
  - Outbound Picking: Order line $\to$ SKU pod identification $\to$ AMR pod lift $\to$ pick station transit $\to$ worker pick duration $\to$ pod storage return.
  - Autonomous Opportunity Charging: AMR routes to charging pad when battery $< 20\%$.
- [ ] **Execution Modes**:
  - **Headless Fast-Time Stepper**: High-throughput discrete simulation for benchmarking and policy training ($>1,000$ steps/sec).
  - **Real-Time Digital Twin Sync**: Real-time tick loop broadcasting telemetry over VDA 5050 WebSocket to Godot 4.

### Non-Goals (Out of Scope)
- Deformable box physics or item-level robotic arm grasp dynamics (tote picking is modeled as a stochastic dwell time $t_{\text{pick}} \sim \mathcal{N}(\mu, \sigma)$).
- Microscopic electrical motor circuit simulations (battery drain is modeled via kinematic work equations).

---

## 2. Input & Output Contracts

### Inputs
- **Facility Topology Configuration**: [`configs/warehouse_layout.yaml`](../../configs/) defining grid dimensions, racking aisle coordinates, dock positions, and one-way lane rules.
- **Order Manifest Stream**: Inbound purchase orders (PO) and outbound sales orders (SO) specifying SKU, quantity, priority, and target station.
- **Fleet Definition**: Robot physical parameters (wheelbase, max acceleration, battery capacity in Wh, lift mechanism timings).

### Outputs
- **Step Observation Tensor / State Dictionary**:
  - Agent states: Coordinates $(x, z)$, orientation $\theta$, linear velocity $v$, angular velocity $\omega$, battery level $\%$, carried pod ID, active task state.
  - Grid occupancy bitmap: Time-space reservation status across intersection vertices.
  - Station queues: Inbound dock backlog and outbound pick station pending totes.
- **Performance Telemetry**:
  - Instantaneous and cumulative pick rate (picks/hour).
  - Deadheading ratio ($\text{distance}_{\text{unloaded}} / \text{distance}_{\text{total}}$).
  - Deadlock counter and safety violation log (hard constraint: 0 collisions, 0 permanent deadlocks).

---

## 3. Execution Pipeline

```text
WMS Order Stream ──► Task Allocator & Pod Selector
                            │
                            ▼
               Time-Space Reservation & Router
                            │
                            ▼
          Kinematic Stepper & Collision Verification
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
    Headless Metric Logger      VDA 5050 WebSocket Bridge
                                          │
                                          ▼
                               Godot 4 3D Digital Twin
```

---

## 4. Technical Specification & Core Mechanics

### 4.1 Topology & Spatial Graph
The warehouse floor is discretized into a coordinate grid with cell dimension $d_{\text{cell}} = 1.2\,\text{m} \times 1.2\,\text{m}$ matching standard pod footprints:
- **Storage Cells (Pods)**: Grouped in double-deep or single-deep racking rows separated by narrow pick aisles.
- **Highway Lanes**: High-speed bidirectional travel perimeter and central arterial lanes.
- **Conflict Zones**: 4-way intersection vertices where perpendicular paths cross.
- **Docks & Workstations**:
  - North Edge ($z = -30\,\text{m}$): Inbound Receiving Docks.
  - South Edge ($z = +26\,\text{m}$): Outbound Goods-to-Person Pick Stations.
  - West Boundary: High-speed charging berths.

### 4.2 Kinematic Model
Each AMR is modeled as a differential-drive non-holonomic mobile base:
$$\begin{aligned}
\dot{x} &= v \cos(\theta) \\
\dot{z} &= v \sin(\theta) \\
\dot{\theta} &= \omega
\end{aligned}$$
- **Steering Rule**: AMRs rotate in-place to target lane heading before initiating forward acceleration.
- **Acceleration**: Trapezoidal velocity profile with $a_{\max} = 1.0\,\text{m/s}^2$ and deceleration $a_{\text{brake}} = 1.5\,\text{m/s}^2$.
- **Lift Mechanics**: When beneath a pod, the AMR activates its turntable lift ($t = 2.5\,\text{s}$), raising the pod by $0.15\,\text{m}$ before movement.

### 4.3 Traffic Control & Anti-Deadlock (OR Guardrail)
1. **Time-Space Vertex Reservation**: A robot must claim vertex $(x, z)$ for time window $[t_{\text{enter}}, t_{\text{exit}}]$ before moving.
2. **Intersection Protocol**:
   - If two AMRs approach an intersection simultaneously, the higher priority order proceeds while the yielding AMR slows and holds at the stop bar.
   - 360° LED status indicators display state transitions: Green (Cruising), Yellow (Yielding), Red (Safety Stop), Blue (Lifting/Lowering).

### 4.4 Inbound & Outbound Workflows
- **Inbound Cycle**: Inbound freight arrives $\to$ system allocates nearest optimal pod $\to$ AMR fetches pod to Inbound Dock $\to$ goods stowed ($10\,\text{s}$) $\to$ AMR returns pod to rack.
- **Outbound Cycle**: Customer order issued $\to$ AMR navigates to target pod $\to$ lifts pod $\to$ delivers to Pick Station $\to$ pick worker selects item ($8\,\text{s}$) $\to$ AMR returns pod to rack.

---

## 5. Associated Links

- Strategic Charter & KPIs: [`docs/PURPOSE.md`](../PURPOSE.md)
- Startup Concept: [`docs/DREAM/DREAM.md`](../DREAM/DREAM.md)
- Codebase Audit: [`docs/audit_codebase.md`](../audit_codebase.md)
- Godot Digital Twin: [`godot/scenes/main.tscn`](../../godot/scenes/main.tscn)
- Phase 3 Specification: [`docs/phases/03_GODOT_3D_DIGITAL_TWIN.md`](03_GODOT_3D_DIGITAL_TWIN.md)
