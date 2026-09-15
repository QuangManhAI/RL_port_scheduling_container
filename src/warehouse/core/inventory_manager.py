"""Discrete inventory management system tracking 4-tier rack slots and SKU tote boxes."""

from __future__ import annotations
from dataclasses import dataclass
from typing import Dict, List, Optional, Any


@dataclass
class SKUBox:
    """Individual small SKU tote box (the smallest unit of warehouse transport)."""
    box_id: str
    sku: str
    category: str
    color_hex: str
    weight_kg: float = 5.0
    order_id: Optional[str] = None


@dataclass
class RackSlot:
    """Discrete storage coordinate in warehouse racking."""
    slot_id: str                    # Format: "{Zone}_R{Rack}_T{Tier}_S{Slot}" (e.g. "Zone A_R1_T2_S1")
    zone: str                       # "Zone A", "Zone B", "Zone C", "Zone D"
    rack_id: int                    # 1 to 4
    tier: int                       # 1 to 4 (vertical shelf tier)
    slot_index: int                 # 1 to 4 (horizontal slot along tier)
    height_m: float                 # Physical height (meters) from floor
    side: str                       # "LEFT" or "RIGHT" relative to aisle
    is_occupied: bool = True
    box: Optional[SKUBox] = None


class InventoryManager:
    """Manages discrete inventory allocation, picking, and stowing across all zones and rack slots."""

    TIER_HEIGHTS: Dict[int, float] = {
        1: 0.5,
        2: 1.0,
        3: 1.5,
        4: 2.0,
    }

    ZONE_SPECS: Dict[str, Dict[str, Any]] = {
        "Zone A": {"category": "FMCG", "sku_default": "FMCG Beverage", "color": "#00e5ff"},
        "Zone B": {"category": "TECH", "sku_default": "Tech GPUs", "color": "#1aff70"},
        "Zone C": {"category": "PHARMA", "sku_default": "Pharma Vaccines", "color": "#be3fff"},
        "Zone D": {"category": "BULKY", "sku_default": "Heavy Machinery", "color": "#ffaa1a"},
    }

    def __init__(self, racks_per_zone: int = 4, tiers_per_rack: int = 4, slots_per_tier: int = 4) -> None:
        self.racks_per_zone: int = racks_per_zone
        self.tiers_per_rack: int = tiers_per_rack
        self.slots_per_tier: int = slots_per_tier
        self.slots: Dict[str, RackSlot] = {}
        self._initialize_warehouse_inventory()

    def _initialize_warehouse_inventory(self) -> None:
        """Populates all rack slots with initial category-coded SKU tote boxes."""
        box_counter = 1000
        for zone_name, spec in self.ZONE_SPECS.items():
            for r in range(1, self.racks_per_zone + 1):
                for t in range(1, self.tiers_per_rack + 1):
                    for s in range(1, self.slots_per_tier + 1):
                        slot_id = f"{zone_name}_R{r}_T{t}_S{s}"
                        box_id = f"BOX-{spec['category']}-{box_counter}"
                        box_counter += 1

                        box = SKUBox(
                            box_id=box_id,
                            sku=spec["sku_default"],
                            category=spec["category"],
                            color_hex=spec["color"],
                            weight_kg=6.0,
                        )

                        slot = RackSlot(
                            slot_id=slot_id,
                            zone=zone_name,
                            rack_id=r,
                            tier=t,
                            slot_index=s,
                            height_m=self.TIER_HEIGHTS.get(t, 1.0),
                            side="LEFT" if s <= 2 else "RIGHT",
                            is_occupied=True,
                            box=box,
                        )
                        self.slots[slot_id] = slot

    def get_slot(self, slot_id: str) -> Optional[RackSlot]:
        """Retrieves a rack slot by ID."""
        return self.slots.get(slot_id)

    def pick_box(self, slot_id: str) -> Optional[SKUBox]:
        """Removes a box from a rack slot (marks slot as EMPTY)."""
        slot = self.slots.get(slot_id)
        if not slot or not slot.is_occupied or slot.box is None:
            return None

        box = slot.box
        slot.box = None
        slot.is_occupied = False
        return box

    def stow_box(self, slot_id: str, box: SKUBox) -> bool:
        """Places a box into an available empty rack slot (marks slot as OCCUPIED)."""
        slot = self.slots.get(slot_id)
        if not slot or slot.is_occupied:
            return False

        slot.box = box
        slot.is_occupied = True
        return True

    def find_available_box(self, zone: str, sku: Optional[str] = None) -> Optional[RackSlot]:
        """Finds the first available occupied rack slot matching zone and/or SKU."""
        for slot in self.slots.values():
            if slot.is_occupied and slot.zone == zone and slot.box is not None:
                if sku is None or slot.box.sku == sku:
                    return slot
        return None

    def find_empty_slot(self, zone: str, preferred_tier: Optional[int] = None) -> Optional[RackSlot]:
        """Finds an empty rack slot in target zone for inbound stowage."""
        # Check preferred tier first if specified
        if preferred_tier is not None:
            for slot in self.slots.values():
                if not slot.is_occupied and slot.zone == zone and slot.tier == preferred_tier:
                    return slot

        # Otherwise any empty slot in zone
        for slot in self.slots.values():
            if not slot.is_occupied and slot.zone == zone:
                return slot
        return None

    def get_inventory_summary(self) -> Dict[str, Any]:
        """Generates real-time inventory statistics across all storage zones."""
        total = len(self.slots)
        occupied = sum(1 for s in self.slots.values() if s.is_occupied)
        empty = total - occupied

        zone_stats: Dict[str, Dict[str, int]] = {}
        for z in self.ZONE_SPECS:
            z_slots = [s for s in self.slots.values() if s.zone == z]
            z_occ = sum(1 for s in z_slots if s.is_occupied)
            zone_stats[z] = {
                "total": len(z_slots),
                "occupied": z_occ,
                "empty": len(z_slots) - z_occ,
            }

        return {
            "total_slots": total,
            "occupied_slots": occupied,
            "empty_slots": empty,
            "occupancy_rate_pct": round((occupied / total) * 100.0, 1) if total > 0 else 0.0,
            "zones": zone_stats,
        }
