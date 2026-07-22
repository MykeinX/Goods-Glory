#!/usr/bin/env python3
"""
Deterministic city supply/demand weights from city attributes + product catalog.

Produces city_markets.json with 10–15 supply and 10–15 demand entries per city.
Weights are relative selection weights for freight-flow derivation (and any
remaining offer generation while the old system is phased out).

Supply weights carry each city's real economic identity via CITY_INDUSTRIES
(curated, offline-only — no runtime city role/tag, per GDD K-009): Detroit leans
automotive, Houston petrochemical, Dhaka apparel. Demand stays population-led;
consumption is generic on purpose.
"""

from __future__ import annotations

import json
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"

# Curated supply-side multipliers per city: signature industries > 1, implausible
# ones < 1. Cities absent from a product default to 1.0. Values are deliberately
# coarse (0.4–3.5); precision here is fake — the goal is a recognizable profile.
CITY_INDUSTRIES: dict[str, dict[str, float]] = {
    # --- USA ---
    "us_new_york": {"apparel": 2.2, "pharmaceuticals": 2.0, "consumer_goods": 1.8, "paper_packaging": 1.4},
    "us_los_angeles": {"apparel": 2.5, "fresh_produce": 2.2, "consumer_electronics": 1.8, "beverages": 1.6, "refrigerated_goods": 1.5},
    "us_chicago": {"processed_food": 2.5, "industrial_machinery": 2.0, "paper_packaging": 1.8, "construction_materials": 1.4},
    "us_dallas": {"consumer_electronics": 2.2, "industrial_machinery": 1.8, "construction_materials": 1.5},
    "us_houston": {"industrial_chemicals": 3.0, "industrial_machinery": 2.2, "construction_materials": 1.6},
    "us_atlanta": {"beverages": 2.8, "paper_packaging": 2.2, "processed_food": 1.8, "refrigerated_goods": 1.5},
    "us_washington": {"pharmaceuticals": 1.5, "industrial_chemicals": 0.5, "industrial_machinery": 0.6, "automotive_parts": 0.5},
    "us_miami": {"fresh_produce": 2.5, "refrigerated_goods": 2.2, "beverages": 1.5, "industrial_machinery": 0.6},
    "us_phoenix": {"consumer_electronics": 2.5, "construction_materials": 1.8, "industrial_machinery": 1.4},
    "us_boston": {"pharmaceuticals": 3.0, "consumer_electronics": 2.0, "industrial_machinery": 1.4},
    "us_san_francisco": {"consumer_electronics": 3.0, "pharmaceuticals": 2.0, "beverages": 1.8},
    "us_detroit": {"automotive_parts": 3.5, "industrial_machinery": 2.0, "construction_materials": 1.3},
    "us_seattle": {"industrial_machinery": 2.5, "refrigerated_goods": 1.8, "beverages": 1.6, "consumer_electronics": 1.5},
    "us_minneapolis": {"processed_food": 2.8, "pharmaceuticals": 1.8, "paper_packaging": 1.6},
    "us_denver": {"beverages": 2.2, "processed_food": 1.8, "construction_materials": 1.5},
    "us_charlotte": {"furniture": 2.5, "apparel": 1.8, "construction_materials": 1.4, "industrial_machinery": 1.4},
    "us_st_louis": {"beverages": 2.5, "automotive_parts": 1.8, "industrial_chemicals": 1.8},
    "us_las_vegas": {"consumer_goods": 1.2, "automotive_parts": 0.4, "industrial_chemicals": 0.4, "industrial_machinery": 0.5, "apparel": 0.6, "fresh_produce": 0.7},
    "us_kansas_city": {"processed_food": 2.5, "automotive_parts": 2.0, "fresh_produce": 1.5},
    "us_nashville": {"automotive_parts": 2.2, "furniture": 1.6, "processed_food": 1.5},
    "us_salt_lake_city": {"industrial_machinery": 2.0, "construction_materials": 1.8, "industrial_chemicals": 1.6},
    "us_new_orleans": {"industrial_chemicals": 2.5, "refrigerated_goods": 1.8, "processed_food": 1.6},
    # --- Europe ---
    "eu_london": {"pharmaceuticals": 2.0, "consumer_goods": 1.8, "beverages": 1.5, "automotive_parts": 0.6},
    "eu_paris": {"apparel": 2.5, "pharmaceuticals": 2.0, "beverages": 1.8, "consumer_goods": 1.8},
    "eu_madrid": {"automotive_parts": 2.2, "processed_food": 1.8, "apparel": 1.5},
    "eu_barcelona": {"automotive_parts": 2.2, "industrial_chemicals": 1.8, "apparel": 1.8, "beverages": 1.4},
    "eu_lisbon": {"beverages": 2.0, "apparel": 1.8, "paper_packaging": 1.6, "fresh_produce": 1.4},
    "eu_rome": {"processed_food": 2.0, "fresh_produce": 1.8, "apparel": 1.5},
    "eu_milan": {"apparel": 3.0, "furniture": 2.5, "industrial_machinery": 1.8},
    "eu_berlin": {"pharmaceuticals": 2.2, "consumer_electronics": 1.8, "consumer_goods": 1.5},
    "eu_hamburg": {"industrial_machinery": 2.0, "refrigerated_goods": 1.8, "processed_food": 1.5, "paper_packaging": 1.4},
    "eu_munich": {"automotive_parts": 3.0, "industrial_machinery": 2.2, "beverages": 2.0},
    "eu_amsterdam": {"fresh_produce": 2.8, "beverages": 1.8, "refrigerated_goods": 1.6, "pharmaceuticals": 1.4},
    "eu_rotterdam": {"industrial_chemicals": 3.0, "construction_materials": 1.6, "refrigerated_goods": 1.5, "fresh_produce": 1.4},
    "eu_brussels": {"pharmaceuticals": 2.5, "processed_food": 2.0, "beverages": 1.8},
    "eu_vienna": {"industrial_machinery": 2.0, "pharmaceuticals": 1.8, "processed_food": 1.5},
    "eu_prague": {"automotive_parts": 2.8, "industrial_machinery": 1.8, "beverages": 1.8},
    "eu_warsaw": {"furniture": 2.5, "automotive_parts": 1.8, "processed_food": 1.6, "consumer_electronics": 1.5},
    "eu_budapest": {"automotive_parts": 2.5, "pharmaceuticals": 2.0, "consumer_electronics": 1.8},
    "eu_stockholm": {"paper_packaging": 2.5, "industrial_machinery": 2.2, "furniture": 2.0},
    "eu_copenhagen": {"pharmaceuticals": 3.0, "processed_food": 2.0, "beverages": 1.8},
    "eu_athens": {"fresh_produce": 2.0, "construction_materials": 1.8, "processed_food": 1.6},
    "eu_istanbul": {"apparel": 3.0, "furniture": 1.8, "automotive_parts": 1.8, "consumer_goods": 1.6},
    "eu_kyiv": {"processed_food": 2.5, "construction_materials": 1.8, "industrial_machinery": 1.6},
    "eu_moscow": {"industrial_machinery": 2.0, "industrial_chemicals": 1.8, "processed_food": 1.6},
    # --- Asia ---
    "as_ankara": {"construction_materials": 1.8, "industrial_machinery": 1.8, "processed_food": 1.5},
    "as_tehran": {"industrial_chemicals": 2.2, "fresh_produce": 1.8, "construction_materials": 1.6, "automotive_parts": 1.5},
    "as_dubai": {"consumer_goods": 2.2, "consumer_electronics": 2.0, "apparel": 1.5, "fresh_produce": 0.7},
    "as_riyadh": {"industrial_chemicals": 3.0, "construction_materials": 1.8, "fresh_produce": 0.5, "refrigerated_goods": 0.7},
    "as_karachi": {"apparel": 2.8, "processed_food": 1.6, "refrigerated_goods": 1.4},
    "as_lahore": {"apparel": 2.8, "consumer_goods": 1.6, "fresh_produce": 1.5},
    "as_delhi": {"apparel": 2.2, "automotive_parts": 2.2, "consumer_goods": 1.8},
    "as_mumbai": {"pharmaceuticals": 2.8, "apparel": 2.0, "industrial_chemicals": 1.8},
    "as_kolkata": {"paper_packaging": 2.2, "beverages": 1.8, "construction_materials": 1.6},
    "as_chennai": {"automotive_parts": 3.0, "consumer_electronics": 2.0, "apparel": 1.8},
    "as_dhaka": {"apparel": 3.5, "consumer_goods": 1.4},
    "as_yangon": {"apparel": 2.2, "processed_food": 1.8, "fresh_produce": 1.5},
    "as_bangkok": {"automotive_parts": 2.5, "consumer_electronics": 2.0, "processed_food": 1.8, "refrigerated_goods": 1.6},
    "as_hanoi": {"consumer_electronics": 2.8, "apparel": 2.0, "furniture": 1.6},
    "as_ho_chi_minh_city": {"apparel": 2.5, "furniture": 2.2, "consumer_electronics": 1.8, "refrigerated_goods": 1.6},
    "as_kuala_lumpur": {"consumer_electronics": 2.5, "industrial_chemicals": 1.8, "furniture": 1.6},
    "as_guangzhou": {"consumer_goods": 2.8, "apparel": 2.2, "consumer_electronics": 2.2, "furniture": 1.8},
    "as_shanghai": {"consumer_electronics": 2.5, "industrial_machinery": 2.2, "automotive_parts": 2.0, "industrial_chemicals": 1.6},
    "as_beijing": {"consumer_electronics": 2.2, "pharmaceuticals": 1.8, "industrial_machinery": 1.8},
    "as_chengdu": {"consumer_electronics": 2.5, "processed_food": 1.8, "pharmaceuticals": 1.5},
    "as_xian": {"industrial_machinery": 2.2, "consumer_electronics": 2.0},
    "as_seoul": {"consumer_electronics": 3.0, "automotive_parts": 2.2, "industrial_chemicals": 1.8},
    "as_almaty": {"processed_food": 2.0, "fresh_produce": 1.8, "construction_materials": 1.5, "pharmaceuticals": 0.5, "consumer_electronics": 0.5},
    "as_tashkent": {"apparel": 2.2, "fresh_produce": 1.8, "automotive_parts": 1.6},
    "as_novosibirsk": {"industrial_machinery": 2.0, "industrial_chemicals": 1.8, "construction_materials": 1.5, "apparel": 0.7},
    "as_yekaterinburg": {"industrial_machinery": 2.5, "construction_materials": 1.8, "industrial_chemicals": 1.6},
}

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
    # Demand rises with population; supply is identity-led with mild noise.
    if side == "demand":
        value *= 0.7 + pop_norm
        value *= 0.75 + 0.5 * stable_noise(city["id"], product_id, side)
    else:
        value *= CITY_INDUSTRIES.get(city["id"], {}).get(product_id, 1.0)
        value *= 0.9 + 0.2 * stable_noise(city["id"], product_id, "supply")
        value *= 0.85 + 0.3 * stable_noise(city["id"], product_id, side)
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

    # Identity table hygiene: no dangling city or product references.
    city_ids = {c["id"] for c in cities}
    for city_id, table in CITY_INDUSTRIES.items():
        assert city_id in city_ids, f"CITY_INDUSTRIES unknown city: {city_id}"
        for pid in table:
            assert pid in product_ids, f"CITY_INDUSTRIES unknown product: {city_id}/{pid}"

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
