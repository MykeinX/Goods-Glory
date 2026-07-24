#!/usr/bin/env python3
"""Generate deterministic supply and demand weights for catalog cities.

The catalog ships a curated industry profile per city when one exists.
Future cities can be added without changing the algorithm: an absent profile
uses the shared population/access model until a recognizable local identity is
authored.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"

# Coarse supply-side multipliers. Precision would be fake; the goal is that a
# city's leading products feel recognizable while keeping the model data-driven.
CITY_INDUSTRIES: dict[str, dict[str, float]] = {
    "us_los_angeles": {
        "apparel": 2.5,
        "fresh_produce": 2.2,
        "consumer_electronics": 1.8,
        "beverages": 1.6,
        "refrigerated_goods": 1.5,
    },
    "us_dallas": {
        "consumer_electronics": 2.2,
        "industrial_machinery": 1.8,
        "construction_materials": 1.5,
    },
    "us_chicago": {
        "processed_food": 2.5,
        "industrial_machinery": 2.0,
        "paper_packaging": 1.8,
        "construction_materials": 1.4,
    },
    "us_atlanta": {
        "beverages": 2.8,
        "paper_packaging": 2.2,
        "processed_food": 1.8,
        "refrigerated_goods": 1.5,
    },
    "us_new_york": {
        "apparel": 2.2,
        "pharmaceuticals": 2.0,
        "consumer_goods": 1.8,
        "paper_packaging": 1.4,
    },
    "us_seattle": {
        "fresh_produce": 2.0,
        "consumer_electronics": 2.2,
        "paper_packaging": 1.6,
        "refrigerated_goods": 1.5,
    },
    "us_denver": {
        "construction_materials": 2.0,
        "industrial_machinery": 1.6,
        "beverages": 1.5,
    },
    "us_houston": {
        "industrial_chemicals": 2.8,
        "construction_materials": 1.8,
        "industrial_machinery": 1.6,
    },
    "us_miami": {
        "fresh_produce": 2.4,
        "refrigerated_goods": 2.2,
        "apparel": 1.6,
        "beverages": 1.5,
    },
    "us_detroit": {
        "automotive_parts": 3.0,
        "industrial_machinery": 2.0,
        "consumer_electronics": 1.4,
    },
    "eu_london": {
        "pharmaceuticals": 2.0,
        "consumer_goods": 1.8,
        "beverages": 1.5,
        "automotive_parts": 0.6,
    },
    "eu_paris": {
        "apparel": 2.5,
        "pharmaceuticals": 2.0,
        "beverages": 1.8,
        "consumer_goods": 1.8,
    },
    "eu_frankfurt": {
        "automotive_parts": 2.4,
        "pharmaceuticals": 2.2,
        "industrial_machinery": 2.0,
        "consumer_electronics": 1.6,
    },
    "eu_istanbul": {
        "apparel": 3.0,
        "furniture": 1.8,
        "automotive_parts": 1.8,
        "consumer_goods": 1.6,
    },
    "eu_madrid": {
        "fresh_produce": 2.2,
        "apparel": 1.8,
        "beverages": 1.8,
        "construction_materials": 1.4,
    },
    "eu_milan": {
        "apparel": 2.4,
        "furniture": 2.0,
        "automotive_parts": 1.8,
        "pharmaceuticals": 1.5,
    },
    "eu_berlin": {
        "industrial_machinery": 2.0,
        "consumer_electronics": 1.8,
        "paper_packaging": 1.6,
        "pharmaceuticals": 1.5,
    },
    "eu_warsaw": {
        "furniture": 2.2,
        "processed_food": 1.8,
        "construction_materials": 1.6,
        "automotive_parts": 1.5,
    },
    "eu_rome": {
        "apparel": 2.0,
        "beverages": 2.0,
        "fresh_produce": 1.8,
        "furniture": 1.5,
    },
}

# Positive affinity means that the city trait raises the product's weight.
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
    "refrigerated_goods": {
        "sea": 0.5,
        "pop": 0.9,
        "air": 0.3,
        "default": 0.7,
    },
}


def stable_noise(city_id: str, product_id: str, salt: str) -> float:
    digest = hashlib.sha256(
        f"{city_id}|{product_id}|{salt}".encode()
    ).hexdigest()
    return int(digest[:8], 16) / 0xFFFFFFFF


def score(city: dict, product_id: str, side: str) -> float:
    traits = PRODUCT_TRAITS[product_id]
    population = city["population"] / 20_000_000
    value = traits.get("default", 1.0)
    value += traits.get("pop", 0) * population
    if city.get("hasSeaPortAccess"):
        value += traits.get("sea", 0)
    if city.get("hasRailFreightAccess"):
        value += traits.get("rail", 0)
    if city.get("hasAirCargoAccess"):
        value += traits.get("air", 0)

    if side == "demand":
        value *= 0.7 + population
        value *= 0.75 + 0.5 * stable_noise(
            city["id"], product_id, side
        )
    else:
        value *= CITY_INDUSTRIES.get(
            city["id"], {}
        ).get(product_id, 1.0)
        value *= 0.9 + 0.2 * stable_noise(
            city["id"], product_id, "supply"
        )
        value *= 0.85 + 0.3 * stable_noise(
            city["id"], product_id, side
        )
    return max(0.05, value)


def pick_side(
    city: dict,
    product_ids: list[str],
    side: str,
    count: int,
) -> list[dict]:
    ranked = sorted(
        (
            (product_id, score(city, product_id, side))
            for product_id in product_ids
        ),
        key=lambda item: (-item[1], item[0]),
    )[:count]
    maximum = ranked[0][1]
    entries = [
        {
            "productID": product_id,
            "weight": max(
                1,
                min(100, int(round(value / maximum * 90 + 10))),
            ),
        }
        for product_id, value in ranked
    ]
    entries.sort(key=lambda entry: (-entry["weight"], entry["productID"]))
    return entries


def main() -> None:
    cities = json.loads((CATALOG / "cities.json").read_text())
    products = json.loads((CATALOG / "products.json").read_text())
    product_ids = [product["id"] for product in products]
    assert 10 <= len(product_ids) <= 20

    city_ids = {city["id"] for city in cities}
    product_id_set = set(product_ids)
    for city_id, table in CITY_INDUSTRIES.items():
        assert city_id in city_ids, f"unknown industry city: {city_id}"
        assert set(table) <= product_id_set, f"unknown product in {city_id}"

    markets = [
        {
            "cityID": city["id"],
            "supply": pick_side(city, product_ids, "supply", 12),
            "demand": pick_side(city, product_ids, "demand", 12),
        }
        for city in cities
    ]
    markets.sort(key=lambda market: market["cityID"])

    output = CATALOG / "city_markets.json"
    output.write_text(json.dumps(markets, indent=2) + "\n")
    print(f"Wrote {len(markets)} markets → {output}")


if __name__ == "__main__":
    main()
