# Codebase Audit Report: RAMemory Smart Warehouse Platform & Digital Twin

**Audit Date**: September 15, 2026  
**Audited Repository**: `RL_port_scheduling_container` (Smart Warehouse Multi-Agent AMR Coordination Platform)  
**Engine**: Godot Engine 4.7.2 Forward+ (Vulkan 1.4, RTX 4060)  
**Backend**: Python 3.12 (Zero-dependency asyncio VDA 5050 WebSocket server)  

---

## 1. Executive Summary

This codebase implements the **RAMemory Smart Warehouse Multi-Agent AMR/AGV Fleet Coordination Platform** (Goods-to-Person fulfillment, under-chassis lifter AMRs, mobile shelf pods, VDA 5050 communication protocol, and MARL dynamic intersection routing with OR safety guardrails).

The system architecture cleanly decouples:
1. **Fleet Orchestration & Backend Protocol**: Python WebSocket server running on `ws://127.0.0.1:9090` sending VDA 5050 state snapshots and receiving dispatch manifests.
2. **3D Interactive Digital Twin Client**: Godot 4 Forward+ environment rendering the facility grid, racking aisles, multi-tier SKU shelf pods, pick stations, inbound docks, and AMR lifters.
3. **2D Zoned Minimap & Radar**: Real-time 2D radar HUD element tracking AMR coordinates, directional headings, and zoned storage partitions.

---

## 2. Component Audits & Resolutions

### 2.1 Window Mode & Fullscreen Behavior (Audit & Fix)
* **Observed Issue**: Pressing `F11` (or clicking Fullscreen) briefly transitioned to windowed mode, but immediately snapped back to fullscreen.
* **Root Cause Analysis**:
  1. **SceneTree `Window` vs. `DisplayServer` Desynchronization**: In Godot 4, the root viewport is a `Window` node (`get_window()`). When using low-level `DisplayServer.window_set_mode()`, Godot's internal `Window` node maintained `Window.MODE_FULLSCREEN`. On the subsequent frame, the root viewport detected a discrepancy and commanded the DisplayServer back to fullscreen.
  2. **OS Focus Key Bouncing**: On Windows, toggling between fullscreen and windowed alters window styles, firing `WM_ACTIVATE` / `WM_SETFOCUS`. If the physical key was held for more than 1 frame during the OS transition, a second `InputEventKey(pressed=true)` was generated on the newly focused window, immediately inverting the toggle.
  3. **Button Focus Capture**: Clicking the HUD toggle button retained keyboard focus (`focus_mode = FOCUS_ALL`), causing subsequent keyboard interactions to inadvertently trigger button activations.
* **Resolution Implemented**:
  * Switched window mode management to `get_window().mode = Window.MODE_WINDOWED` and `get_window().mode = Window.MODE_FULLSCREEN`.
  * Added a 400 ms hardware timestamp debounce guard (`Time.get_ticks_msec()`).
  * Consumed key events immediately via `get_viewport().set_input_as_handled()`.
  * Applied explicit window dimensioning ($1600 \times 900$ or 85% screen bounds) and dynamic centering upon entering windowed mode.
  * Set `focus_mode = 0` (`FOCUS_NONE`) on all HUD window controls.

### 2.2 In-Game Logging & Auto-Copy to Clipboard
* **Requirement**: Enable double-clicking the simulation mission log box to automatically copy all logs to the system clipboard.
* **Implementation Details**:
  * Attached `gui_input` event handlers to both `LogBox` (`RichTextLabel`) and `LogPanel` (`Panel`).
  * Configured `mouse_filter = 0` (`MOUSE_FILTER_STOP`) and added visual tooltips: `💡 Double-click to copy all logs to clipboard`.
  * On `double_click`, the system extracts parsed text via `log_box.get_parsed_text()` (with fallback to an in-memory `_raw_log_lines` array with BBCode stripped via regex).
  * Invokes `DisplayServer.clipboard_set(full_text)` to transfer raw logs directly into the OS clipboard.
  * Emits an instant visual confirmation log: `[color=lime]📋 Logs copied to clipboard (N entries)![/color]`.

### 2.3 Upstream Synchronization Status
* Synced with upstream commit `cafd55a` (`QuangManhAI/RL_port_scheduling_container`):
  * Integrated `RadarMap` 2D real-time warehouse radar.
  * Integrated Inbound Receiving (`PO-101`..`PO-103`) and Outbound Picking (`SO-501`..`SO-503`) manifest queues.
  * Multi-tiered shelf pods with category-coded SKU tote boxes.
  * Integrated graceful WebSocket client disconnect handling on Windows (`ConnectionResetError` suppression).

---

## 3. Recommended Next Iterations

1. **Kinematics Refinement**: Replace linear position interpolation with realistic differential-drive rotational alignment (turn-in-place before forward transit).
2. **Elevating Turntable Animation**: Add vertical piston stroke animation when lifters dock under shelf pods.
3. **Continuous Order Dispatching**: Expand the automated order engine to dynamically restock empty shelf cells.
