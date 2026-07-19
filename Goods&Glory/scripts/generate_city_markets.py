#!/usr/bin/env python3
"""
Deterministic city supply/demand weights from city attributes + product catalog.

Produces city_markets.json with 10–15 supply and 10–15 demand entries per city.
Weights are relative selection weights for spot/contract generation.
"""

from __future__ import annotations

import json
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"

# Product affinities: positive → stronger supply bias for matching city traits.
PRODUCT_TRAITS = {
    "consumer_goods": {"pop": 1.2, "default": 1.0},
    "processed_food": {"pop": 1.0, "default": 1.0},
    "fresh_produce": {"pop": 0.8, "sea": 0.4, "default": 0.9},
    "beverages": {"pop": 1.0, "default": 0.9},
    "construction_materials": {"pop": 0.7, "rail": 0.5, "default": 0.8},
    "consumer_electronics": {"pop": 1.1, "air": 0.6, "default": 0.7},
    "automotive_parts": {"rail": 0.5, "pop": 0.8, "default": 0.8},
    "pharmaceuticals": {"air": 0.7, "pop": 0.9, "default": 0.6},
    "apparel": {"pop": 1.1, "sea": 0.3, "default": 0.8},
    "paper_packaging": {"pop": 0.9, "default": 0.9},
    "industrial_chemicals": {"sea": 0.6, "rail": 0.5, "default": 0.6},
    "furniture": {"pop": 0.9, "default": 0.8},
    "industrial_machinery": {"rail": 0.7, "default": 0.6},
    "refrigerated_goods": {"sea": 0.5, "pop": 0.9, "air": 0.3, "default": 0.7},
}


def stable_noise(city_id: str, product_id: str, salt: str) -> float:
    h = hashlib.sha256(f"{city_id}|{product_id}|{salt}".encode()).hexdigest()
    return int(h[:8], 16) / 0xFFFFFFFF


def score(city: dict, product_id: str, side: str) -> float:
    traits = PRODUCT_TRAITS[product_id]
    pop_norm = city["population"] / 20_000_000
    value = traits.get("default", 1.0)
    value += traits.get("pop", 0) * pop_norm
    if city.get("hasSeaPortAccess"):
        value += traits.get("sea", 0)
    if city.get("hasRailFreightAccess"):
        value += traits.get("rail", 0)
    if city.get("hasAirCargoAccess"):
        value += traits.get("air", 0)
    # Demand rises with population; supply leans on access + noise.
    if side == "demand":
        value *= 0.7 + pop_norm
    else:
        value *= 0.85 + 0.4 * stable_noise(city["id"], product_id, "supply")
    value *= 0.75 + 0.5 * stable_noise(city["id"], product_id, side)
    return max(0.05, value)


def pick_side(city: dict, product_ids: list[str], side: str, count: int) -> list[dict]:
    ranked = sorted(
        ((pid, score(city, pid, side)) for pid in product_ids),
        key=lambda x: (-x[1], x[0]),
    )[:count]
    # Convert scores to integer weights 1..100, sorted weight desc then id.
    max_score = ranked[0][1]
    entries = []
    for pid, sc in ranked:
        weight = max(1, min(100, int(round(sc / max_score * 90 + 10))))
        entries.append({"productID": pid, "weight": weight})
    entries.sort(key=lambda e: (-e["weight"], e["productID"]))
    return entries


def main() -> None:
    cities = json.loads((CATALOG / "cities.json").read_text())
    products = json.loads((CATALOG / "products.json").read_text())
    product_ids = [p["id"] for p in products]
    assert 10 <= len(product_ids) <= 20

    markets = []
    for city in cities:
        # 12 entries each — within 10–15 and under the 20-entry catalog cap.
        supply_n = 12
        demand_n = 12
        markets.append(
            {
                "cityID": city["id"],
                "supply": pick_side(city, product_ids, "supply", supply_n),
                "demand": pick_side(city, product_ids, "demand", demand_n),
            }
        )
    markets.sort(key=lambda m: m["cityID"])
    out = CATALOG / "city_markets.json"
    out.write_text(json.dumps(markets, indent=2) + "\n")
    print(f"Wrote {len(markets)} markets → {out}")


if __name__ == "__main__":
    main()
