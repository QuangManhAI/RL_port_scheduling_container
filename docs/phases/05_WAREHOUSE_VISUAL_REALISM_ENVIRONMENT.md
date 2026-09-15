# 05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md — Warehouse Shell & Cinematic Environment Upgrade Specification

- **Motivation/Background**: `PHASE-03` delivered a functional procedural warehouse (racking, lanes, AMRs) and `PHASE-04` locked the simulation mechanics (mobile manipulator kinematics, physics, RL contracts). Both currently render against a bare/"kind of med" grey-box shell — flat floor, no building envelope, no zone dressing. To communicate the platform credibly (pitch decks, pilot demos, operator training), the environment needs a realistic building shell and zone layout in the style of a professional 3PL/warehouse infographic (reference: Interlake Mecalux–style isometric cutaway layout chart), rendered at real-time quality in Godot 4.
- **Purpose**: Give the build agent a concrete, buildable description of the warehouse *shell* (building, roof, dock, mezzanine), *zone layout* (receiving → storage → picking → shipping), *materials/lighting*, and *camera presets* needed to move the digital twin from grey-box to a realistic, readable facility — without touching the already-locked simulation mechanics in `PHASE-04`.
- **Overview Pipeline**: `PHASE-03`'s procedural racking generator and `PHASE-04`'s grid/reservation graph remain the ground truth for *where* things are; this phase only adds the *building shell*, *static zone dressing*, *materials*, *lighting*, and *camera rigs* around that existing topology in `godot/scenes/environment/`.
- **Detailed Plan**: §1 Scope & Objective; §2 Reference Layout & Zone Map (§2.1 Concrete Zone Dimensions, §2.2 Yard + Cutaway Camera Composition); §3 Building Shell & Structure; §4 Materials, Lighting & Post-Processing; §5 Zone-by-Zone Dressing; §6 Camera Presets; §7 Scene Node Map (implementation contract); §8 Acceptance Criteria.
- **References**: [`03_GODOT_3D_DIGITAL_TWIN.md`](./03_GODOT_3D_DIGITAL_TWIN.md), [`04_WAREHOUSE_SIMULATION_ENVIRONMENT.md`](./04_WAREHOUSE_SIMULATION_ENVIRONMENT.md), [`PURPOSE.md`](./PURPOSE.md).
- **Created**: 2026-09-15
- **Last Updated**: 2026-09-15

---

## Metadata

- **Phase ID**: `PHASE-05`
- **Phase Name**: `Warehouse Shell, Zone Dressing & Cinematic Camera Upgrade`
- **Status**: Proposed
- **Target Directories**: [`godot/scenes/environment/`](../../godot/scenes/environment), [`godot/scripts/environment/`](../../godot/scripts/environment)

---

## 1. Scope & Objective

Current state (per `PHASE-03`/`PHASE-04`): a flat ground plane, procedural racking aisles, AMRs, pick stations, charging docks — functionally complete but visually a grey-box test level (no walls, no roof, no daylight, no zone identity).

Target state: a single rectangular **big-box distribution center** shell, seen either as a cutaway isometric "chart" (matching the reference layout-plan aesthetic) or walked/flown through in first/third person, with clearly legible zones the way a real 3PL facility reads from above: **Receiving → Reserve Storage → Pick Modules → Pack/Consolidation → Shipping**, plus an **office mezzanine** overlooking the floor.

This phase does **not** change grid spacing, reservation logic, AMR kinematics, or inventory contracts from `PHASE-04` — it only wraps that existing simulation in a believable building.

---

## 2. Reference Layout & Zone Map

The reference image is a stylized isometric "cutaway" infographic (roof and near-side wall removed, far walls and floor visible, labeled functional zones) — the standard way logistics vendors (Mecalux/Interlake, and similar) visualize a distribution center. Reproduce the *structure and zone logic*, not any vendor's branding, colors, or exact geometry.

Zone strip, front-to-back along the long axis of the building:

```
[ YARD/TRUCKS ] → [ RECEIVING DOCK ] → [ INBOUND STAGING ] → [ RESERVE STORAGE RACKING (bulk of floor) ]
                                                                        │
                                                        [ PICK MODULES / GOODS-TO-PERSON STATIONS ]
                                                                        │
                                                    [ PACK / CONSOLIDATION ] → [ OUTBOUND STAGING ] → [ SHIPPING DOCK ] → [ YARD ]

[ OFFICE / CONTROL ROOM MEZZANINE ] — elevated, glass-fronted, overlooking the floor near Receiving
[ CHARGING DOCK ] — side alcove, off the main traffic lanes
```

This keeps `PHASE-04`'s existing aisle/rack/pick-station graph intact; it just gives each existing element a *place* inside a real building envelope instead of floating on an infinite plane.

### 2.1 Concrete Zone Dimensions

Ties the qualitative zone strip above to the existing `140 m × 100 m` footprint (`PHASE-04` §4.5, Layer 1). Origin `(0, 0)` at the Receiving-end corner of the building, long axis = X (0–140 m), short axis = Z (0–100 m). These are starting proportions for the build agent, not hard constraints — adjust to whatever the procedural generator's actual aisle count needs, but keep Storage as the dominant share of floor area (it should read as clearly the largest zone from the Chart/Cutaway camera).

| Zone | X range (long axis) | Approx. share | Notes |
| :--- | :--- | :--- | :--- |
| Yard / truck apron | −25 m to 0 m (outside building) | — | Exterior, not part of the 140×100 m interior footprint |
| Receiving dock | 0 m – 15 m | ~11% | Full Z width (0–100 m); dock doors on the X=0 wall |
| Reserve storage (racking) | 15 m – 90 m | ~54% | Bulk of the floor; this is where `PHASE-03`'s procedural aisles live |
| Pick modules / G2P + Pack | 90 m – 120 m | ~21% | Includes the Charging dock as a side alcove off Z ≈ 80–100 m, not inline with pick traffic |
| Shipping dock | 120 m – 140 m | ~14% | Full Z width; dock doors on the X=140 wall |
| Office/mezzanine | X ≈ 5–25 m, Z ≈ 80–100 m | — | Corner insert overlapping the Receiving zone, elevated ~4–5 m |

### 2.2 Yard + Cutaway Camera Composition

Concrete framing reference for the Chart/Cutaway camera preset (§6.1), matching the reference layout-chart aesthetic:

- **Left of frame**: the Yard, rendered as a dashed/implied boundary (asphalt + parking stripes) with 2–3 static truck-and-trailer meshes staged nose-in toward the dock wall, plus a short access arrow implied by truck orientation rather than a literal UI arrow.
- **Center-left, tallest visual weight**: the building envelope itself as a single cutaway shell (roof + near wall removed for this camera only, per §6.1) with the Receiving zone as the first interior slice the eye hits.
- **Center, widest band**: Storage racking — deliberately the widest zone in the frame (per §2.1's ~54% share) so the eye reads it as the dominant function of the building, with aisle rows visible as repeated vertical racking lines receding into depth.
- **Right-center**: Pick & Pack as a narrower band, visually distinct from Storage (different fixture density — conveyor, pack tables, human-scale props vs. tall racking).
- **Far right**: Shipping, mirroring Receiving's proportions, with an implied outbound arrow (truck orientation again, not a UI element) exiting the frame.
- **Top-right corner, floating above the zone strip**: the glass-fronted Mezzanine, catching the skylight daylight from §3/§4 and giving the shot a clear "operator's-eye" focal point.
- **Overhead band the full width of the shot**: the skylight/roof-truss line — this is what visually unifies the cutaway (every zone sits under the same daylight source) and is the detail most worth getting right per §4's lighting notes.

This composition is the target for the "hero" screenshot/demo shot referenced in §6.1 — it should read correctly as a still image, not just as a live camera angle.

---

## 3. Building Shell & Structure

- **Footprint**: rectangular hall, long axis matching the existing `140 × 100 m` floor from `PHASE-04` §4.5 (Layer 1). Roughly a 3:2 aspect ratio reads as a realistic big-box DC rather than a square box.
- **Perimeter walls**: tilt-up concrete panel look — light grey/off-white PBR concrete texture with visible panel seams every ~9 m, a painted expansion joint line, and a dark rubber-base strip at floor level. Punch a row of high clerestory windows near the roofline on the long walls for daylight.
- **Roof structure**: exposed steel truss/joist roof (not a flat ceiling) — primary bar joists spanning the short axis, painted white/light grey, with visible bolted connections. Add **skylight panels** in a regular grid (roughly every 3rd–4th bay) that let a soft daylight shaft down onto the racking — this is the single biggest "realism" lever for a warehouse interior.
- **Floor**: polished/sealed concrete with a slight sheen (not matte grey), subtle mottling/stain variation, and painted **safety line markings**: yellow lane borders for AMR travel lanes, red/yellow hazard hatching at intersections (ties directly into `PHASE-03`'s crosshatched conflict zones — just re-skin them as painted floor decals rather than flat color), and painted pedestrian walkways in green (already specified in `PHASE-03` §Goals).
- **Dock wall**: one short end wall is the **dock wall** — a row of dock doors (roll-up sectional doors, ~3 m wide) each with a dock leveler plate and yellow/black bumper pads, matching the Receiving/Shipping zones. Use 4–6 doors: split between Receiving (inbound trucks) and Shipping (outbound trucks), with a painted line on the exterior yard distinguishing the two.
- **Office/control mezzanine**: a two-story insert in one corner near Receiving — ground floor is enclosed (break room/lockers, implied, can be a closed box), upper floor is a glass-fronted control room with a railed catwalk, reachable by a steel staircase. This is where the KPI HUD narratively "lives" and gives a natural elevated camera position (see §6).
- **Cable/pipe dressing on ceiling**: sprinkler piping (red, running the length of each aisle under the joists), a few HVAC ducts, and conduit racks — low-poly, tiled/instanced, not hero assets.

---

## 4. Materials, Lighting & Post-Processing

Godot 4 specifics, to be applied via a single `WorldEnvironment` + a small shared material library so the change is centralized and doesn't touch per-object scripts from `PHASE-03`/`PHASE-04`:

- **Lighting model**: SDFGI (`Environment.sdfgi_enabled = true`) or baked `LightmapGI` for the static shell (walls, roof, floor, racks) — either gives believable bounce light under the skylights instead of the flat/unlit grey-box look. Keep AMRs and totes dynamic (unbaked) since they move.
- **Key light**: a single `DirectionalLight3D` standing in for sun through the skylights/clerestory, warm-white (~3800–4200K), moderate intensity, soft shadows (`shadow_blur` > 0) so shadows read as diffuse skylight rather than hard sun.
- **Fill lighting**: high-bay LED fixtures as small `OmniLight3D`/`SpotLight3D` instances along each aisle centerline (cool-white ~5000K), low intensity — mainly for the aisle-guide light-strip effect already planned in `PHASE-03`, now motivated as real fixtures rather than emissive decals.
- **Materials (PBR, `StandardMaterial3D`)**:
  - Concrete floor: albedo light warm-grey, subtle normal map for surface texture, low roughness for a faint sheen, no metallic.
  - Racking steel: dark blue/orange industrial paint (common real-world rack colors — orange uprights, blue beams, or safety-yellow — pick one consistent scheme), moderate metallic + roughness, slight edge wear via a vertex-color or triplanar dirt mask.
  - Concrete wall panels: matte, very low sheen, subtle panel-seam normal detail.
  - Dock doors: brushed aluminum/steel slats, higher metallic.
- **Post-processing** (`WorldEnvironment` glow/SSAO/SSR):
  - SSAO on, modest intensity — this alone fixes most of the "flat grey-box" feel by grounding racks and equipment.
  - Very light glow/bloom, restricted to actual light sources (LED strips, exit signs, AMR LED rings) so the fleet-state colors from `PHASE-03` (green/yellow/red/blue/cyan) read as glowing indicators, not flat colors.
  - Optional thin volumetric fog (`FogVolume`, low density) to catch the skylight shafts — big visual payoff for a warehouse interior, cheap to render, easy to disable for the tactical overview camera if it hurts readability.
- **Exterior**: a simple skybox/environment texture (overcast daylight) visible through the clerestory windows and open dock doors, plus a flat asphalt yard plane with painted truck-parking stripes outside the dock wall, so the cutaway view has *something* believable beyond the walls.

---

## 5. Zone-by-Zone Dressing

Static, non-simulated props only — none of this touches `PHASE-04`'s physics layers (`Environment_Static`, `Racks_Dynamic`, `AMR_Fleet`, `Tote_Boxes`). Treat everything below as visual set-dressing parented under the existing `Floor`/`StaticBody3D`.

| Zone | Dressing |
| :--- | :--- |
| **Yard** | Painted parking stripes, 2–3 static semi-truck-and-trailer meshes backed up to dock doors, a fence line, exterior wall-pack lights. |
| **Receiving dock** | Dock levelers, yellow bollards, a stack of empty pallets, a static forklift, inbound PO signage board near the mezzanine stair. |
| **Reserve storage (racking)** | Already covered by `PHASE-03`'s procedural generator — add aisle-end signage placards (zone/aisle letter-number, matches the `(Zone, Rack, Tier, Slot)` WMS index from `PHASE-04` §1.5) and floor-level rack-protection corner guards. |
| **Pick modules / G2P stations** | Roller conveyor segment feeding into pack, a small operator podium/screen prop, floor-marked queueing lane for AMRs. |
| **Charging dock** | Side alcove off the main lanes (per `PHASE-03` Goals), floor-mounted charging pads already specified, add cable management trays and a small "Charging Zone" overhead sign. |
| **Pack / consolidation** | Packing tables, a shrink-wrap stand, stacked shipping cartons. |
| **Shipping dock** | Mirrors Receiving: dock levelers, outbound staging pallets marked with destination placards, a second static forklift. |
| **Office/mezzanine** | Desks/monitor props visible through the glass front (implies the KPI HUD operator), railed catwalk, stairs, an exit sign over the door. |
| **General/safety** | Fire extinguisher stations at aisle ends, a first-aid station near the office, exit signs over every dock/personnel door, a few ceiling-mounted security camera props overlooking intersections (nice narrative tie-in to the anti-deadlock monitoring theme). |

All of the above should be simple/low-poly instanced meshes (this is a real-time digital twin, not an offline render) — the realism budget should go to lighting/materials/floor decals first, hero-prop detail second.

---

## 6. Camera Presets

Extends `PHASE-04` §1.6 (RTS overview presets `1`–`4` + follow-cam) with shell-aware framing:

1. **Chart/Cutaway overview** (§6.1, new, matches the reference image) — a fixed high isometric angle from one open corner, roof and near wall hidden (`VisibilityBoundary`/culled at that camera only), so the whole zone strip reads left-to-right in one shot per the composition in §2.2. This is the "hero" screenshot/demo shot.
2. **Mezzanine operator view** (§6.2) — camera pinned at the glass-front control room, looking down the main aisle — a natural "watching the KPI HUD" shot.
3. **Tactical RTS presets `1`–`4`** (§6.3) — unchanged from `PHASE-04`, now simply have real walls/roof/skylights to render instead of void.
4. **Follow-cam** (§6.4) — unchanged; benefits automatically from the new lighting/materials.

---

## 7. Scene Node Map (implementation contract)

Additive under the existing `godot/scenes/environment/` tree — does not rename or move `PHASE-03` nodes:

```
WarehouseShell (new, Node3D)
├── Structure
│   ├── PerimeterWalls (MeshInstance3D + StaticBody3D, tilt-up panels)
│   ├── RoofTrusses (instanced MeshInstance3D)
│   ├── Skylights (MeshInstance3D, emissive-lit from above)
│   ├── ClerestoryWindows
│   └── DockWall (RollupDoors[4-6], DockLevelers)
├── Mezzanine
│   ├── GroundFloorShell
│   ├── ControlRoom (glass front, railed catwalk)
│   └── Staircase
├── Yard
│   ├── AsphaltPlane
│   ├── TruckTrailers[2-3]
│   └── FenceLine
├── ZoneDressing
│   ├── Receiving / InboundStaging
│   ├── PickPack
│   ├── ShippingStaging
│   └── SafetyProps (extinguishers, signs, cameras)
└── Lighting
    ├── SunDirectionalLight3D
    ├── HighBayFixtures (instanced Omni/SpotLight3D along aisle centerlines)
    └── WorldEnvironment (SDFGI/Lightmap, SSAO, glow, thin FogVolume)
```

Existing `PHASE-03` nodes (`procedural_warehouse.gd`, `shelf_pod.tscn`, `amr_robot.tscn`, pick stations, charging docks) and `PHASE-04` physics layers plug into this shell unchanged — `WarehouseShell` is purely a container the procedural generator's floor origin sits inside.

---

## 8. Acceptance Criteria

- [ ] From the Chart/Cutaway camera preset, an observer can identify Receiving, Storage, Picking, Packing, and Shipping without a legend, the way the reference layout-plan image reads at a glance.
- [ ] Skylights + SDFGI/baked GI visibly change aisle lighting versus the current flat grey-box (soft daylight shafts, not uniform ambient).
- [ ] Existing `PHASE-03` fleet LED states (Green/Yellow/Red/Blue/Cyan) and `PHASE-04` arm/tray mechanics render unchanged — this phase is additive only.
- [ ] Frame rate budget: shell + dressing adds ≤ target headroom on the existing edge-deployment constraint (`PURPOSE.md` §6, ≤ 8 GB RAM target hardware) — use instancing/LOD for repeated props (racks, trusses, fixtures), no per-object unique high-poly meshes.
- [ ] Full environment reset (`PHASE-04` §4.5, `R` key) is unaffected — shell/dressing is static and never resets.
