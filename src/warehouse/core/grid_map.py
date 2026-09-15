"""Discrete topological grid map and spatial routing graph for warehouse simulation."""

from __future__ import annotations
import math
import heapq
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple, Set, Any


class NodeType(str, Enum):
    """Semantic category of warehouse floor vertices."""
    LANE = "LANE"                    # High-speed bidirectional travel lane
    AISLE = "AISLE"                  # Narrow racking access aisle
    INTERSECTION = "INTERSECTION"    # 4-way conflict intersection zone
    STORAGE_BAY = "STORAGE_BAY"      # Docking point alongside a storage rack
    PICK_STATION = "PICK_STATION"    # Outbound Goods-to-Person pick/pack station
    INBOUND_DOCK = "INBOUND_DOCK"    # Inbound freight receiving dock
    CHARGING_PAD = "CHARGING_PAD"    # Automated opportunity charging pad


@dataclass
class GridNode:
    """Individual topological vertex on the warehouse coordinate grid."""
    node_id: str
    x: float                         # World X coordinate (meters)
    z: float                         # World Z coordinate (meters)
    grid_x: int                      # Integer grid column
    grid_z: int                      # Integer grid row
    node_type: NodeType = NodeType.LANE
    zone: Optional[str] = None       # "Zone A", "Zone B", "Zone C", "Zone D", or None
    metadata: Dict[str, Any] = field(default_factory=dict)
    neighbors: Set[str] = field(default_factory=set)

    @property
    def pos(self) -> Tuple[float, float]:
        """Returns 2D tuple (x, z)."""
        return (self.x, self.z)


class WarehouseGridMap:
    """Directed graph representing warehouse floor topology, travel lanes, and workstations."""

    def __init__(self, cell_size: float = 1.2) -> None:
        self.cell_size: float = cell_size
        self.nodes: Dict[str, GridNode] = {}
        self._build_standard_facility()

    def add_node(
        self,
        node_id: str,
        x: float,
        z: float,
        grid_x: int,
        grid_z: int,
        node_type: NodeType = NodeType.LANE,
        zone: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> GridNode:
        """Registers a node in the graph."""
        node = GridNode(
            node_id=node_id,
            x=round(x, 2),
            z=round(z, 2),
            grid_x=grid_x,
            grid_z=grid_z,
            node_type=node_type,
            zone=zone,
            metadata=metadata or {},
        )
        self.nodes[node_id] = node
        return node

    def add_edge(self, from_id: str, to_id: str, bidirectional: bool = True) -> None:
        """Connects two nodes with a directed or bidirectional edge."""
        if from_id in self.nodes and to_id in self.nodes:
            self.nodes[from_id].neighbors.add(to_id)
            if bidirectional:
                self.nodes[to_id].neighbors.add(from_id)

    def get_node(self, node_id: str) -> Optional[GridNode]:
        """Retrieves a node by identifier."""
        return self.nodes.get(node_id)

    def get_closest_node(self, x: float, z: float) -> GridNode:
        """Finds the nearest graph node to given continuous coordinates."""
        best_node = None
        best_dist = float("inf")
        for node in self.nodes.values():
            dist = math.hypot(node.x - x, node.z - z)
            if dist < best_dist:
                best_dist = dist
                best_node = node
        assert best_node is not None, "Grid map contains no nodes"
        return best_node

    def distance(self, u_id: str, v_id: str) -> float:
        """Computes Euclidean distance between two nodes."""
        u = self.nodes[u_id]
        v = self.nodes[v_id]
        return math.hypot(u.x - v.x, u.z - v.z)

    def manhattan_distance(self, u_id: str, v_id: str) -> float:
        """Computes Manhattan distance between two nodes."""
        u = self.nodes[u_id]
        v = self.nodes[v_id]
        return abs(u.x - v.x) + abs(u.z - v.z)

    def get_nodes_by_type(self, node_type: NodeType) -> List[GridNode]:
        """Filters nodes by semantic type."""
        return [n for n in self.nodes.values() if n.node_type == node_type]

    def get_nodes_by_zone(self, zone: str) -> List[GridNode]:
        """Filters nodes belonging to a designated inventory zone."""
        return [n for n in self.nodes.values() if n.zone == zone]

    def find_path_astar(self, start_id: str, goal_id: str) -> List[str]:
        """Computes shortest topological path between two nodes using A* search."""
        if start_id not in self.nodes or goal_id not in self.nodes:
            return []
        if start_id == goal_id:
            return [start_id]

        open_set: List[Tuple[float, str]] = []
        heapq.heappush(open_set, (0.0, start_id))

        came_from: Dict[str, str] = {}
        g_score: Dict[str, float] = {node_id: float("inf") for node_id in self.nodes}
        g_score[start_id] = 0.0

        f_score: Dict[str, float] = {node_id: float("inf") for node_id in self.nodes}
        f_score[start_id] = self.distance(start_id, goal_id)

        visited: Set[str] = set()

        while open_set:
            _, current = heapq.heappop(open_set)
            if current == goal_id:
                path = [current]
                while current in came_from:
                    current = came_from[current]
                    path.append(current)
                path.reverse()
                return path

            visited.add(current)

            for neighbor_id in self.nodes[current].neighbors:
                if neighbor_id in visited:
                    continue

                tentative_g = g_score[current] + self.distance(current, neighbor_id)
                if tentative_g < g_score[neighbor_id]:
                    came_from[neighbor_id] = current
                    g_score[neighbor_id] = tentative_g
                    f = tentative_g + self.distance(neighbor_id, goal_id)
                    f_score[neighbor_id] = f
                    heapq.heappush(open_set, (f, neighbor_id))

        return []  # No path found

    def _build_standard_facility(self) -> None:
        """Constructs the standard RAMemory facility topology with 4 zones, docks, and stations."""
        # Key coordinate landmarks matching Godot 3D facility
        # North-South highway: X in [-28, 28], Z in [-32, 28]
        # Crossways: Z = -25 (Inbound crossway), Z = 0 (Central 4-Way crossway), Z = 22 (Pick crossway)
        
        # 1. Inbound Docks (North: Z = -30.0)
        in_dock_1 = self.add_node("INBOUND_DOCK_1", -10.0, -30.0, -8, -25, NodeType.INBOUND_DOCK, metadata={"dock_id": 1})
        in_dock_2 = self.add_node("INBOUND_DOCK_2", 10.0, -30.0, 8, -25, NodeType.INBOUND_DOCK, metadata={"dock_id": 2})

        # 2. Outbound Pick & Pack Stations (South: Z = 26.0)
        pick_stn_1 = self.add_node("PICK_STN_1", -10.0, 26.0, -8, 22, NodeType.PICK_STATION, metadata={"station_id": 1})
        pick_stn_2 = self.add_node("PICK_STN_2", 10.0, 26.0, 8, 22, NodeType.PICK_STATION, metadata={"station_id": 2})

        # 3. Charging Docks (West: X = -20.0, -15.0, Z = -28.0)
        charge_1 = self.add_node("CHARGING_1", -20.0, -28.0, -16, -23, NodeType.CHARGING_PAD, metadata={"dock_id": 1})
        charge_2 = self.add_node("CHARGING_2", -15.0, -28.0, -12, -23, NodeType.CHARGING_PAD, metadata={"dock_id": 2})

        # 4. Central 4-Way Intersection Core (X=0, Z=0)
        int_center = self.add_node("INT_CENTER", 0.0, 0.0, 0, 0, NodeType.INTERSECTION, metadata={"conflict_zone": "CORE_4WAY"})
        int_n = self.add_node("INT_N", 0.0, -6.0, 0, -5, NodeType.INTERSECTION, metadata={"stop_bar": "NORTH"})
        int_s = self.add_node("INT_S", 0.0, 6.0, 0, 5, NodeType.INTERSECTION, metadata={"stop_bar": "SOUTH"})
        int_w = self.add_node("INT_W", -6.0, 0.0, -5, 0, NodeType.INTERSECTION, metadata={"stop_bar": "WEST"})
        int_e = self.add_node("INT_E", 6.0, 0.0, 5, 0, NodeType.INTERSECTION, metadata={"stop_bar": "EAST"})

        self.add_edge("INT_N", "INT_CENTER")
        self.add_edge("INT_S", "INT_CENTER")
        self.add_edge("INT_W", "INT_CENTER")
        self.add_edge("INT_E", "INT_CENTER")

        # 5. Arterial Highway Spine
        spine_n = self.add_node("SPINE_N", 0.0, -20.0, 0, -16, NodeType.LANE)
        spine_s = self.add_node("SPINE_S", 0.0, 20.0, 0, 16, NodeType.LANE)
        spine_w = self.add_node("SPINE_W", -25.0, 0.0, -20, 0, NodeType.LANE)
        spine_e = self.add_node("SPINE_E", 25.0, 0.0, 20, 0, NodeType.LANE)

        self.add_edge("SPINE_N", "INT_N")
        self.add_edge("SPINE_S", "INT_S")
        self.add_edge("SPINE_W", "INT_W")
        self.add_edge("SPINE_E", "INT_E")

        # Connect Spine to Docks & Stations
        self.add_edge("SPINE_N", "INBOUND_DOCK_1")
        self.add_edge("SPINE_N", "INBOUND_DOCK_2")
        self.add_edge("SPINE_S", "PICK_STN_1")
        self.add_edge("SPINE_S", "PICK_STN_2")
        self.add_edge("INBOUND_DOCK_1", "CHARGING_1")
        self.add_edge("CHARGING_1", "CHARGING_2")

        # 6. Inventory Zones A, B, C, D Racking Aisles & Storage Bays
        zones_config = [
            {"zone": "Zone A", "center_x": -18.0, "category": "FMCG"},
            {"zone": "Zone B", "center_x": -6.0, "category": "TECH"},
            {"zone": "Zone C", "center_x": 6.0, "category": "PHARMA"},
            {"zone": "Zone D", "center_x": 18.0, "category": "BULKY"},
        ]

        for z_info in zones_config:
            zone_name = z_info["zone"]
            cx = z_info["center_x"]
            # Create north and south access nodes for each zone aisle
            aisle_n = self.add_node(f"AISLE_{zone_name}_N", cx, -18.0, int(cx / 1.2), -15, NodeType.AISLE, zone=zone_name)
            aisle_s = self.add_node(f"AISLE_{zone_name}_S", cx, 18.0, int(cx / 1.2), 15, NodeType.AISLE, zone=zone_name)
            
            # Connect aisle entry/exit to northern & southern highway arteries
            self.add_edge(aisle_n.node_id, "SPINE_N")
            self.add_edge(aisle_s.node_id, "SPINE_S")

            # Create 4 Storage Rack bays along this aisle
            for rack_idx in range(1, 5):
                rack_z = -12.0 + (rack_idx - 1) * 8.0
                bay_id = f"BAY_{zone_name}_R{rack_idx}"
                bay_node = self.add_node(
                    bay_id,
                    cx,
                    rack_z,
                    int(cx / 1.2),
                    int(rack_z / 1.2),
                    NodeType.STORAGE_BAY,
                    zone=zone_name,
                    metadata={"rack_id": rack_idx, "category": z_info["category"]},
                )
                # Link sequentially down the aisle
                self.add_edge(aisle_n.node_id, bay_id)
                self.add_edge(bay_id, aisle_s.node_id)
                if rack_idx > 1:
                    prev_bay = f"BAY_{zone_name}_R{rack_idx - 1}"
                    self.add_edge(prev_bay, bay_id)
