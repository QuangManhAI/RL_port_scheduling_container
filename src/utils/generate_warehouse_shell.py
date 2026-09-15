#!/usr/bin/env python3
"""
generate_warehouse_shell.py
Generates godot/scenes/environment/warehouse_shell.tscn conforming strictly to
docs/phases/05_WAREHOUSE_VISUAL_REALISM_ENVIRONMENT.md.
Creates complete building shell, tilt-up concrete walls, steel bar joist trusses,
skylights, two-story control mezzanine, exterior truck yard with semi-trucks,
PBR zone dressing, safety markings, and cutaway compatibility.
"""

import os

class Vector3:
    def __init__(self, x, y, z):
        self.x = x
        self.y = y
        self.z = z

def build_warehouse_shell_tscn(out_path: str):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    content = []
    content.append('[gd_scene load_steps=65 format=3 uid="uid://dmx3whshell005"]')
    content.append('')
    content.append('[ext_resource type="Script" path="res://scripts/environment/warehouse_shell.gd" id="1_shell"]')
    content.append('')

    # --- MATERIALS ---
    # 1. Polished Concrete Floor Slab (with subtle sheen)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_FloorConcrete"]')
    content.append('albedo_color = Color(0.82, 0.83, 0.86, 1.0)')
    content.append('roughness = 0.32')
    content.append('metallic = 0.05')
    content.append('specular_mode = 1')
    content.append('')

    # 2. Tilt-up Concrete Wall Panels
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_WallConcrete"]')
    content.append('albedo_color = Color(0.78, 0.80, 0.82, 1.0)')
    content.append('roughness = 0.85')
    content.append('metallic = 0.0')
    content.append('')

    # 3. Baseboard Rubber Trim
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_WallTrim"]')
    content.append('albedo_color = Color(0.18, 0.20, 0.22, 1.0)')
    content.append('roughness = 0.7')
    content.append('')

    # 4. Steel Bar Joist Roof Trusses & Structure
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_SteelTruss"]')
    content.append('albedo_color = Color(0.85, 0.87, 0.90, 1.0)')
    content.append('metallic = 0.75')
    content.append('roughness = 0.35')
    content.append('')

    # 5. Skylight Panels (Diffuse Daylight Glow)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_Skylight"]')
    content.append('albedo_color = Color(0.92, 0.96, 1.0, 0.95)')
    content.append('emission_enabled = true')
    content.append('emission = Color(0.95, 0.98, 1.0, 1.0)')
    content.append('emission_energy_multiplier = 1.4')
    content.append('roughness = 0.1')
    content.append('')

    # 6. Clerestory Window Glass
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_Clerestory"]')
    content.append('albedo_color = Color(0.75, 0.88, 0.98, 0.75)')
    content.append('transparency = 1')
    content.append('roughness = 0.15')
    content.append('metallic = 0.2')
    content.append('')

    # 7. Roll-up Sectional Dock Doors (Industrial Slats)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_DockDoor"]')
    content.append('albedo_color = Color(0.55, 0.58, 0.62, 1.0)')
    content.append('metallic = 0.85')
    content.append('roughness = 0.3')
    content.append('')

    # 8. Dock Leveler Plate (Diamond Tread Steel)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_DockLeveler"]')
    content.append('albedo_color = Color(0.35, 0.38, 0.42, 1.0)')
    content.append('metallic = 0.9')
    content.append('roughness = 0.4')
    content.append('')

    # 9. Safety Yellow Bumper / Guardrails / Bollards
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_SafetyYellow"]')
    content.append('albedo_color = Color(0.95, 0.75, 0.05, 1.0)')
    content.append('roughness = 0.4')
    content.append('metallic = 0.1')
    content.append('')

    # 10. Hazard Black & Yellow Stripes
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_HazardStripes"]')
    content.append('albedo_color = Color(0.90, 0.55, 0.05, 1.0)')
    content.append('roughness = 0.45')
    content.append('')

    # 11. Green Pedestrian Safety Walkway
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_WalkwayGreen"]')
    content.append('albedo_color = Color(0.12, 0.58, 0.36, 1.0)')
    content.append('roughness = 0.5')
    content.append('')

    # 12. Mezzanine Tempered Tinted Glass
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_MezzanineGlass"]')
    content.append('albedo_color = Color(0.2, 0.45, 0.55, 0.65)')
    content.append('transparency = 1')
    content.append('roughness = 0.08')
    content.append('metallic = 0.3')
    content.append('')

    # 13. Mezzanine Office Walls (Clean Interior Drywall)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_OfficeWall"]')
    content.append('albedo_color = Color(0.88, 0.90, 0.92, 1.0)')
    content.append('roughness = 0.7')
    content.append('')

    # 14. Computer Monitor Screen (Glowing Data Display)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_ScreenGlow"]')
    content.append('albedo_color = Color(0.05, 0.25, 0.4, 1.0)')
    content.append('emission_enabled = true')
    content.append('emission = Color(0.1, 0.8, 1.0, 1.0)')
    content.append('emission_energy_multiplier = 2.5')
    content.append('')

    # 15. Exterior Asphalt Yard
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_Asphalt"]')
    content.append('albedo_color = Color(0.18, 0.19, 0.22, 1.0)')
    content.append('roughness = 0.92')
    content.append('metallic = 0.0')
    content.append('')

    # 16. Semi-Truck Cab & Trailer Body
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_TruckWhite"]')
    content.append('albedo_color = Color(0.92, 0.92, 0.94, 1.0)')
    content.append('roughness = 0.3')
    content.append('metallic = 0.25')
    content.append('')

    content.append('[sub_resource type="StandardMaterial3D" id="Mat_TruckBlue"]')
    content.append('albedo_color = Color(0.08, 0.32, 0.75, 1.0)')
    content.append('roughness = 0.3')
    content.append('metallic = 0.35')
    content.append('')

    # 17. Wooden Euro-Pallet
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_PalletWood"]')
    content.append('albedo_color = Color(0.68, 0.52, 0.35, 1.0)')
    content.append('roughness = 0.85')
    content.append('metallic = 0.0')
    content.append('')

    # 18. Corrugated Shipping Carton
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_CartonCardboard"]')
    content.append('albedo_color = Color(0.72, 0.56, 0.38, 1.0)')
    content.append('roughness = 0.88')
    content.append('')

    # 19. Fire Sprinkler Pipe (Red)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_SprinklerRed"]')
    content.append('albedo_color = Color(0.85, 0.12, 0.12, 1.0)')
    content.append('roughness = 0.35')
    content.append('metallic = 0.5')
    content.append('')

    # 20. Galvanized HVAC Duct
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_HVACGalvanized"]')
    content.append('albedo_color = Color(0.70, 0.73, 0.76, 1.0)')
    content.append('metallic = 0.8')
    content.append('roughness = 0.35')
    content.append('')

    # 21. Emergency Exit Sign (Glowing Green)
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_ExitSign"]')
    content.append('albedo_color = Color(0.05, 0.5, 0.15, 1.0)')
    content.append('emission_enabled = true')
    content.append('emission = Color(0.15, 0.95, 0.35, 1.0)')
    content.append('emission_energy_multiplier = 2.0')
    content.append('')

    # 22. Powered Roller Conveyor Frame & Rollers
    content.append('[sub_resource type="StandardMaterial3D" id="Mat_ConveyorFrame"]')
    content.append('albedo_color = Color(0.12, 0.35, 0.65, 1.0)')
    content.append('metallic = 0.6')
    content.append('roughness = 0.4')
    content.append('')

    content.append('[sub_resource type="StandardMaterial3D" id="Mat_ConveyorRoller"]')
    content.append('albedo_color = Color(0.75, 0.78, 0.82, 1.0)')
    content.append('metallic = 0.85')
    content.append('roughness = 0.25')
    content.append('')

    # --- MESHES ---
    content.append('[sub_resource type="BoxMesh" id="Mesh_FloorSlab"]')
    content.append('material = SubResource("Mat_FloorConcrete")')
    content.append('size = Vector3(140, 1, 100)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_WallLong"]')
    content.append('material = SubResource("Mat_WallConcrete")')
    content.append('size = Vector3(140, 16, 1)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_WallShort"]')
    content.append('material = SubResource("Mat_WallConcrete")')
    content.append('size = Vector3(1, 16, 100)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_WallBaseboard"]')
    content.append('material = SubResource("Mat_WallTrim")')
    content.append('size = Vector3(140, 0.35, 1.05)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_WallBaseboardShort"]')
    content.append('material = SubResource("Mat_WallTrim")')
    content.append('size = Vector3(1.05, 0.35, 100)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_ClerestoryStrip"]')
    content.append('material = SubResource("Mat_Clerestory")')
    content.append('size = Vector3(1, 1.8, 92)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_DockDoorPanel"]')
    content.append('material = SubResource("Mat_DockDoor")')
    content.append('size = Vector3(3.6, 4.5, 0.15)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_DockBumper"]')
    content.append('material = SubResource("Mat_HazardStripes")')
    content.append('size = Vector3(0.35, 1.2, 0.35)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_DockLeveler"]')
    content.append('material = SubResource("Mat_DockLeveler")')
    content.append('size = Vector3(2.4, 0.1, 2.8)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_RoofTrussChords"]')
    content.append('material = SubResource("Mat_SteelTruss")')
    content.append('size = Vector3(0.6, 1.4, 100)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_SkylightPane"]')
    content.append('material = SubResource("Mat_Skylight")')
    content.append('size = Vector3(6.0, 0.08, 12.0)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_RoofDeckPanel"]')
    content.append('material = SubResource("Mat_SteelTruss")')
    content.append('size = Vector3(140, 0.25, 100)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_LaneYellowX"]')
    content.append('material = SubResource("Mat_SafetyYellow")')
    content.append('size = Vector3(120, 0.02, 0.45)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_LaneYellowZ"]')
    content.append('material = SubResource("Mat_SafetyYellow")')
    content.append('size = Vector3(0.45, 0.02, 80)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_HazardIntersect"]')
    content.append('material = SubResource("Mat_HazardStripes")')
    content.append('size = Vector3(14, 0.02, 14)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_WalkwayGreen"]')
    content.append('material = SubResource("Mat_WalkwayGreen")')
    content.append('size = Vector3(120, 0.02, 2.2)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_AsphaltApron"]')
    content.append('material = SubResource("Mat_Asphalt")')
    content.append('size = Vector3(110, 0.8, 38)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_TrailerBody"]')
    content.append('material = SubResource("Mat_TruckWhite")')
    content.append('size = Vector3(3.0, 4.2, 14.5)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_TruckCab"]')
    content.append('material = SubResource("Mat_TruckBlue")')
    content.append('size = Vector3(2.8, 3.8, 6.2)')
    content.append('')

    content.append('[sub_resource type="CylinderMesh" id="Mesh_Bollard"]')
    content.append('material = SubResource("Mat_SafetyYellow")')
    content.append('top_radius = 0.12')
    content.append('bottom_radius = 0.12')
    content.append('height = 1.1')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_EuroPallet"]')
    content.append('material = SubResource("Mat_PalletWood")')
    content.append('size = Vector3(1.2, 0.16, 0.8)')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_CartonBox"]')
    content.append('material = SubResource("Mat_CartonCardboard")')
    content.append('size = Vector3(0.6, 0.45, 0.4)')
    content.append('')

    content.append('[sub_resource type="CylinderMesh" id="Mesh_SprinklerPipe"]')
    content.append('material = SubResource("Mat_SprinklerRed")')
    content.append('top_radius = 0.04')
    content.append('bottom_radius = 0.04')
    content.append('height = 138.0')
    content.append('')

    content.append('[sub_resource type="BoxMesh" id="Mesh_HVACDuct"]')
    content.append('material = SubResource("Mat_HVACGalvanized")')
    content.append('size = Vector3(138.0, 0.8, 1.2)')
    content.append('')

    # --- COLLISION SHAPES ---
    content.append('[sub_resource type="BoxShape3D" id="Col_Floor"]')
    content.append('size = Vector3(140, 1, 100)')
    content.append('')

    content.append('[sub_resource type="BoxShape3D" id="Col_WallLong"]')
    content.append('size = Vector3(140, 16, 1)')
    content.append('')

    content.append('[sub_resource type="BoxShape3D" id="Col_WallShort"]')
    content.append('size = Vector3(1, 16, 100)')
    content.append('')

    content.append('[sub_resource type="BoxShape3D" id="Col_Mezzanine"]')
    content.append('size = Vector3(26, 0.4, 22)')
    content.append('')

    content.append('[sub_resource type="BoxShape3D" id="Col_Yard"]')
    content.append('size = Vector3(110, 0.8, 38)')
    content.append('')

    # --- SCENE TREE ROOT ---
    content.append('[node name="WarehouseShell" type="Node3D"]')
    content.append('script = ExtResource("1_shell")')
    content.append('')

    # 1. Collision Group (StaticBody3D on Layer 1)
    content.append('[node name="WarehouseCollision" type="StaticBody3D" parent="."]')
    content.append('collision_layer = 1')
    content.append('collision_mask = 0')
    content.append('')
    content.append('[node name="ColFloor" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)')
    content.append('shape = SubResource("Col_Floor")')
    content.append('')
    content.append('[node name="ColWallNorth" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 8, -50)')
    content.append('shape = SubResource("Col_WallLong")')
    content.append('')
    content.append('[node name="ColWallSouth" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 8, 50)')
    content.append('shape = SubResource("Col_WallLong")')
    content.append('')
    content.append('[node name="ColWallWest" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -70, 8, 0)')
    content.append('shape = SubResource("Col_WallShort")')
    content.append('')
    content.append('[node name="ColWallEast" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 70, 8, 0)')
    content.append('shape = SubResource("Col_WallShort")')
    content.append('')
    content.append('[node name="ColMezzanine" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 48, 4.5, -35)')
    content.append('shape = SubResource("Col_Mezzanine")')
    content.append('')
    content.append('[node name="ColYard" type="CollisionShape3D" parent="WarehouseCollision"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.4, -69)')
    content.append('shape = SubResource("Col_Yard")')
    content.append('')

    # 2. Structure
    content.append('[node name="Structure" type="Node3D" parent="."]')
    content.append('')
    content.append('[node name="ConcreteSlab" type="MeshInstance3D" parent="Structure"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)')
    content.append('mesh = SubResource("Mesh_FloorSlab")')
    content.append('')

    # Perimeter Walls
    content.append('[node name="PerimeterWalls" type="Node3D" parent="Structure"]')
    content.append('')
    content.append('[node name="WallNorth" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 8, -50)')
    content.append('mesh = SubResource("Mesh_WallLong")')
    content.append('')
    content.append('[node name="BaseboardNorth" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.175, -49.5)')
    content.append('mesh = SubResource("Mesh_WallBaseboard")')
    content.append('')
    content.append('[node name="WallSouth" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 8, 50)')
    content.append('mesh = SubResource("Mesh_WallLong")')
    content.append('')
    content.append('[node name="BaseboardSouth" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.175, 49.5)')
    content.append('mesh = SubResource("Mesh_WallBaseboard")')
    content.append('')
    content.append('[node name="WallWest" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -70, 8, 0)')
    content.append('mesh = SubResource("Mesh_WallShort")')
    content.append('')
    content.append('[node name="ClerestoryWest" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -69.4, 13.5, 0)')
    content.append('mesh = SubResource("Mesh_ClerestoryStrip")')
    content.append('')
    content.append('[node name="WallEast" type="MeshInstance3D" parent="Structure/PerimeterWalls"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 70, 8, 0)')
    content.append('mesh = SubResource("Mesh_WallShort")')
    content.append('')
    content.append('[node name="ClerestoryEast" type="MeshInstance3D" parent="Structure/PerimeterWalls/WallEast"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.6, 5.5, 0)')
    content.append('mesh = SubResource("Mesh_ClerestoryStrip")')
    content.append('')

    # Dock Doors on North Wall (Receiving)
    content.append('[node name="DockDoorsNorth" type="Node3D" parent="Structure"]')
    dock_x_coords = [-30.0, -10.0, 10.0, 30.0]
    for i, x in enumerate(dock_x_coords):
        content.append(f'[node name="DoorNorth_{i+1}" type="MeshInstance3D" parent="Structure/DockDoorsNorth"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 2.25, -49.4)')
        content.append('mesh = SubResource("Mesh_DockDoorPanel")')
        content.append('')
        content.append(f'[node name="LevelerNorth_{i+1}" type="MeshInstance3D" parent="Structure/DockDoorsNorth"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0.05, -48.4)')
        content.append('mesh = SubResource("Mesh_DockLeveler")')
        content.append('')
        content.append(f'[node name="BumperNorthL_{i+1}" type="MeshInstance3D" parent="Structure/DockDoorsNorth"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x - 2.1}, 0.6, -49.6)')
        content.append('mesh = SubResource("Mesh_DockBumper")')
        content.append('')
        content.append(f'[node name="BumperNorthR_{i+1}" type="MeshInstance3D" parent="Structure/DockDoorsNorth"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x + 2.1}, 0.6, -49.6)')
        content.append('mesh = SubResource("Mesh_DockBumper")')
        content.append('')

    # Dock Doors on South Wall (Shipping)
    content.append('[node name="DockDoorsSouth" type="Node3D" parent="Structure"]')
    for i, x in enumerate(dock_x_coords):
        content.append(f'[node name="DoorSouth_{i+1}" type="MeshInstance3D" parent="Structure/DockDoorsSouth"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 2.25, 49.4)')
        content.append('mesh = SubResource("Mesh_DockDoorPanel")')
        content.append('')
        content.append(f'[node name="LevelerSouth_{i+1}" type="MeshInstance3D" parent="Structure/DockDoorsSouth"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0.05, 48.4)')
        content.append('mesh = SubResource("Mesh_DockLeveler")')
        content.append('')

    # Roof & Trusses
    content.append('[node name="Roof" type="Node3D" parent="Structure"]')
    content.append('')
    content.append('[node name="RoofDeck" type="MeshInstance3D" parent="Structure/Roof"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 16.1, 0)')
    content.append('mesh = SubResource("Mesh_RoofDeckPanel")')
    content.append('')

    truss_x_coords = [-55.0, -40.0, -25.0, -10.0, 5.0, 20.0, 35.0, 50.0]
    for i, x in enumerate(truss_x_coords):
        content.append(f'[node name="Truss_{i+1}" type="MeshInstance3D" parent="Structure/Roof"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 15.3, 0)')
        content.append('mesh = SubResource("Mesh_RoofTrussChords")')
        content.append('')

    # Skylights Grid
    content.append('[node name="Skylights" type="Node3D" parent="Structure"]')
    skylight_x = [-32.0, -16.0, 0.0, 16.0, 32.0]
    skylight_z = [-22.0, 0.0, 22.0]
    sky_idx = 1
    for sx in skylight_x:
        for sz in skylight_z:
            content.append(f'[node name="Sky_{sky_idx}" type="MeshInstance3D" parent="Structure/Skylights"]')
            content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {sx}, 16.15, {sz})')
            content.append('mesh = SubResource("Mesh_SkylightPane")')
            content.append('')
            sky_idx += 1

    # Ceiling Dressing (Sprinklers, HVAC)
    content.append('[node name="CeilingDressing" type="Node3D" parent="Structure"]')
    content.append('')
    content.append('[node name="SprinklerMain1" type="MeshInstance3D" parent="Structure/CeilingDressing"]')
    content.append('transform = Transform3D(-4.37114e-08, 0, 1, 0, 1, 0, -1, 0, -4.37114e-08, 0, 14.5, -16)')
    content.append('mesh = SubResource("Mesh_SprinklerPipe")')
    content.append('')
    content.append('[node name="SprinklerMain2" type="MeshInstance3D" parent="Structure/CeilingDressing"]')
    content.append('transform = Transform3D(-4.37114e-08, 0, 1, 0, 1, 0, -1, 0, -4.37114e-08, 0, 14.5, 16)')
    content.append('mesh = SubResource("Mesh_SprinklerPipe")')
    content.append('')
    content.append('[node name="HVACMain" type="MeshInstance3D" parent="Structure/CeilingDressing"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 14.2, 0)')
    content.append('mesh = SubResource("Mesh_HVACDuct")')
    content.append('')

    # 3. Floor Markings & Safety Zones
    content.append('[node name="FloorMarkings" type="Node3D" parent="."]')
    content.append('')
    content.append('[node name="MainAisleX" type="MeshInstance3D" parent="FloorMarkings"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.01, 0)')
    content.append('mesh = SubResource("Mesh_LaneYellowX")')
    content.append('')
    content.append('[node name="MainAisleZ" type="MeshInstance3D" parent="FloorMarkings"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.01, 0)')
    content.append('mesh = SubResource("Mesh_LaneYellowZ")')
    content.append('')
    content.append('[node name="HazardIntersection" type="MeshInstance3D" parent="FloorMarkings"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.015, 0)')
    content.append('mesh = SubResource("Mesh_HazardIntersect")')
    content.append('')
    content.append('[node name="SafetyWalkwayGreen" type="MeshInstance3D" parent="FloorMarkings"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.012, 38)')
    content.append('mesh = SubResource("Mesh_WalkwayGreen")')
    content.append('')

    # 4. Two-Story Office & Control Mezzanine
    content.append('[node name="Mezzanine" type="Node3D" parent="."]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 48, 0, -35)')
    content.append('')
    # Ground Floor Utility/Breakroom
    content.append('[node name="GroundFloorBlock" type="MeshInstance3D" parent="Mezzanine"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.25, 0)')
    content.append('mesh = SubResource("Mesh_WallLong")')
    content.append('')
    # Elevated Mezzanine Deck
    content.append('[node name="MezzanineFloor" type="MeshInstance3D" parent="Mezzanine"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 4.5, 0)')
    content.append('mesh = SubResource("Mesh_DockLeveler")')
    content.append('')
    # Upper Control Room Glass Front
    content.append('[node name="ControlRoomGlass" type="MeshInstance3D" parent="Mezzanine"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10.0, 6.2, 0)')
    content.append('mesh = SubResource("Mesh_ClerestoryStrip")')
    content.append('')
    # Control Screens
    content.append('[node name="Screen1" type="MeshInstance3D" parent="Mezzanine"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -8.5, 5.5, -4)')
    content.append('mesh = SubResource("Mesh_DockBumper")')
    content.append('')
    content.append('[node name="Screen2" type="MeshInstance3D" parent="Mezzanine"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -8.5, 5.5, 4)')
    content.append('mesh = SubResource("Mesh_DockBumper")')
    content.append('')
    # Exit sign
    content.append('[node name="ExitSign" type="MeshInstance3D" parent="Mezzanine"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -10.0, 7.5, 0)')
    content.append('mesh = SubResource("Mesh_DockBumper")')
    content.append('')

    # 5. Exterior Truck Yard
    content.append('[node name="Yard" type="Node3D" parent="."]')
    content.append('')
    content.append('[node name="AsphaltApron" type="MeshInstance3D" parent="Yard"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.4, -69)')
    content.append('mesh = SubResource("Mesh_AsphaltApron")')
    content.append('')

    # Semi-Truck 1 at Dock 1 (-30m)
    content.append('[node name="Truck1_Trailer" type="MeshInstance3D" parent="Yard"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -30, 2.1, -58.5)')
    content.append('mesh = SubResource("Mesh_TrailerBody")')
    content.append('')
    content.append('[node name="Truck1_Cab" type="MeshInstance3D" parent="Yard"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -30, 1.9, -68.8)')
    content.append('mesh = SubResource("Mesh_TruckCab")')
    content.append('')

    # Semi-Truck 2 at Dock 3 (+10m)
    content.append('[node name="Truck2_Trailer" type="MeshInstance3D" parent="Yard"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 10, 2.1, -58.5)')
    content.append('mesh = SubResource("Mesh_TrailerBody")')
    content.append('')
    content.append('[node name="Truck2_Cab" type="MeshInstance3D" parent="Yard"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 10, 1.9, -68.8)')
    content.append('mesh = SubResource("Mesh_TruckCab")')
    content.append('')

    # 6. Zone-by-Zone Dressing Props
    content.append('[node name="ZoneDressing" type="Node3D" parent="."]')
    content.append('')

    # Receiving Staging Props (Bollards, Pallet Stacks, Forklift)
    content.append('[node name="ReceivingDressing" type="Node3D" parent="ZoneDressing"]')
    bollard_x = [-32.5, -27.5, -12.5, -7.5, 7.5, 12.5, 27.5, 32.5]
    for i, bx in enumerate(bollard_x):
        content.append(f'[node name="BollardRec_{i+1}" type="MeshInstance3D" parent="ZoneDressing/ReceivingDressing"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {bx}, 0.55, -46.5)')
        content.append('mesh = SubResource("Mesh_Bollard")')
        content.append('')

    # Pallet stacks in Receiving
    pallet_positions = [
        Vector3(-22.0, 0.08, -44.0),
        Vector3(-22.0, 0.24, -44.0),
        Vector3(-22.0, 0.40, -44.0),
        Vector3(-18.0, 0.08, -44.0),
        Vector3(-18.0, 0.24, -44.0),
        Vector3(22.0, 0.08, -44.0),
        Vector3(22.0, 0.24, -44.0),
        Vector3(26.0, 0.08, -44.0)
    ]
    for i, pos in enumerate(pallet_positions):
        content.append(f'[node name="Pallet_{i+1}" type="MeshInstance3D" parent="ZoneDressing/ReceivingDressing"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos.x}, {pos.y}, {pos.z})')
        content.append('mesh = SubResource("Mesh_EuroPallet")')
        content.append('')

    # Pick & Pack Dressing Props
    content.append('[node name="PickPackDressing" type="Node3D" parent="ZoneDressing"]')
    content.append('')
    # Powered Conveyor Frame
    content.append('[node name="PackConveyor" type="MeshInstance3D" parent="ZoneDressing/PickPackDressing"]')
    content.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.65, 33)')
    content.append('mesh = SubResource("Mesh_DockDoorPanel")')
    content.append('')

    # Shipping Carton Stacks
    carton_positions = [
        Vector3(-6.0, 0.22, 32.0),
        Vector3(-6.0, 0.67, 32.0),
        Vector3(-5.2, 0.22, 32.0),
        Vector3(6.0, 0.22, 32.0),
        Vector3(6.0, 0.67, 32.0)
    ]
    for i, pos in enumerate(carton_positions):
        content.append(f'[node name="Carton_{i+1}" type="MeshInstance3D" parent="ZoneDressing/PickPackDressing"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos.x}, {pos.y}, {pos.z})')
        content.append('mesh = SubResource("Mesh_CartonBox")')
        content.append('')

    # Safety Props: Fire Extinguishers on Perimeter Columns
    content.append('[node name="SafetyEquipment" type="Node3D" parent="ZoneDressing"]')
    content.append('')
    extinguisher_x = [-69.2, -69.2, 69.2, 69.2]
    extinguisher_z = [-25.0, 25.0, -25.0, 25.0]
    for i, (ex, ez) in enumerate(zip(extinguisher_x, extinguisher_z)):
        content.append(f'[node name="FireExt_{i+1}" type="MeshInstance3D" parent="ZoneDressing/SafetyEquipment"]')
        content.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {ex}, 1.6, {ez})')
        content.append('mesh = SubResource("Mesh_DockBumper")')
        content.append('')

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(content) + "\n")
    print(f"✔ Successfully generated {out_path}")

if __name__ == "__main__":
    out_file = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../godot/scenes/environment/warehouse_shell.tscn"))
    build_warehouse_shell_tscn(out_file)
