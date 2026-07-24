#!/usr/bin/env python3
"""Build the authored foundation road network.

The graph is a logistics board, not a navigation database. Real freight
corridors inspire a small number of reusable trunks and junctions; SpriteKit's
MapCorridorCache converts their projected guide points into shared horizontal,
vertical and 45-degree route geometry.

America and Europe deliberately remain separate road components. Future cities
join by splitting a nearby trunk edge or attaching to one or two existing hubs,
not by adding a direct edge to every other city.

Usage: python3 -B scripts/generate_trade_network.py
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

# Adjacent guide nodes follow real corridor geography. This modest factor turns
# great-circle distance into a plausible strategic road distance without making
# the visual schematic responsible for simulation cost or travel time.
ROAD_FACTOR = 1.15
MAXIMUM_NODE_DEGREE = 4

REGION_CONTINENTS = {
    "us": "america",
    "eu": "europe",
}

# Steering nodes sit on the authored board (same lat/lon space as cities).
# Interim placements until the road graph is carefully redesigned.
# Degree-two nodes shape a trunk; higher-degree nodes are reusable branches.
JUNCTIONS = {
    "us": {
        "phoenix": (30.2453, -126.4479),
        "albuquerque": (35.0, -119.0347),
        "denver": (36.3585, -113.7066),
        "kansas_city": (35.0, -100.0386),
        "cleveland": (39.0755, -74.7876),
        "nashville": (34.1509, -91.2355),
        "memphis": (28.3774, -97.4903),
        "charlotte": (32.6226, -74.7876),
    },
    "eu": {
        "calais": (38.566, 8.8417),
        "brussels": (37.0377, 16.4865),
        "lyon": (32.1132, 17.1815),
        "stuttgart": (37.3774, 19.7297),
        "munich": (34.3208, 25.0579),
        "vienna": (32.4528, 26.4479),
        "budapest": (30.5849, 27.6062),
        "belgrade": (29.566, 28.0695),
        "sofia": (26.3396, 30.8494),
    },
}

# Consecutive stops become undirected roads. Shared pairs become one RoadID, so
# two player routes using the same trunk also share one rendered path segment.
CORRIDORS = {
    "us": {
        # I-10 / I-40 / I-70 / I-80 strategic west-east spine.
        "transcontinental": [
            "us_los_angeles",
            "jct:phoenix",
            "jct:albuquerque",
            "jct:denver",
            "jct:kansas_city",
            "us_chicago",
            "jct:cleveland",
            "us_new_york",
        ],
        # Texas can enter either the western trunk or the Great Lakes trunk.
        "south_central": [
            "jct:albuquerque",
            "us_dallas",
            "jct:kansas_city",
        ],
        # I-30 / I-40 freight belt.
        "southern_freight": [
            "us_dallas",
            "jct:memphis",
            "us_atlanta",
        ],
        # I-65 / I-24 connection between Midwest and Southeast.
        "midwest_southeast": [
            "us_chicago",
            "jct:nashville",
            "us_atlanta",
        ],
        # Alternative Great Lakes approach keeps the graph from becoming a tree.
        "great_lakes_relief": [
            "jct:nashville",
            "jct:cleveland",
        ],
        # I-85 / I-95 Atlantic branch.
        "atlantic": [
            "us_atlanta",
            "jct:charlotte",
            "us_new_york",
        ],
    },
    "eu": {
        # Channel Tunnel trunk.
        "channel": [
            "eu_london",
            "jct:calais",
            "eu_paris",
        ],
        # Benelux freight approach to the Rhine.
        "channel_north": [
            "jct:calais",
            "jct:brussels",
            "eu_frankfurt",
        ],
        "west_central": [
            "eu_paris",
            "eu_frankfurt",
        ],
        # Rhone / Alpine alternative to the central trunk.
        "rhone_alpine": [
            "eu_paris",
            "jct:lyon",
            "jct:stuttgart",
            "jct:munich",
        ],
        "rhine_alpine": [
            "eu_frankfurt",
            "jct:munich",
        ],
        "danube_north": [
            "eu_frankfurt",
            "jct:vienna",
        ],
        "danube_south": [
            "jct:munich",
            "jct:vienna",
            "jct:budapest",
            "jct:belgrade",
        ],
        "danube_relief": [
            "jct:vienna",
            "jct:belgrade",
        ],
        "balkan": [
            "jct:belgrade",
            "jct:sofia",
            "eu_istanbul",
        ],
    },
}


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    radius = 6371.0
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2)
        * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * radius * math.asin(math.sqrt(h))


def build_region(
    prefix: str,
    cities: dict[str, dict],
) -> tuple[list[dict], list[dict]]:
    junctions = JUNCTIONS[prefix]
    corridors = CORRIDORS[prefix]

    def node_id(stop: str) -> str:
        if stop.startswith("jct:"):
            return f"{prefix}_jct_{stop[4:]}"
        return cities[stop]["roadNodeID"]

    def coordinate(stop: str) -> tuple[float, float]:
        if stop.startswith("jct:"):
            return junctions[stop[4:]]
        city = cities[stop]
        return (city["latitude"], city["longitude"])

    def edge_label(stop: str) -> str:
        if stop.startswith("jct:"):
            return f"jct_{stop[4:]}"
        return f"city_{stop.split('_', 1)[1]}"

    stops = {stop for corridor in corridors.values() for stop in corridor}
    city_stops = sorted(stop for stop in stops if not stop.startswith("jct:"))
    junction_stops = sorted(stop for stop in stops if stop.startswith("jct:"))

    nodes: list[dict] = []
    for city_id in city_stops:
        city = cities[city_id]
        assert city["continent"] == REGION_CONTINENTS[prefix], city_id
        nodes.append({
            "id": city["roadNodeID"],
            "coordinate": {
                "latitude": city["latitude"],
                "longitude": city["longitude"],
            },
            "kind": "city",
            "cityID": city_id,
        })
    for stop in junction_stops:
        suffix = stop[4:]
        latitude, longitude = junctions[suffix]
        nodes.append({
            "id": node_id(stop),
            "coordinate": {
                "latitude": latitude,
                "longitude": longitude,
            },
            "kind": "junction",
            "cityID": None,
        })

    roads: list[dict] = []
    seen: set[frozenset[str]] = set()
    for corridor_name in sorted(corridors):
        corridor = corridors[corridor_name]
        assert len(corridor) >= 2, corridor_name
        for first, second in zip(corridor, corridor[1:]):
            key = frozenset((node_id(first), node_id(second)))
            if key in seen:
                continue
            seen.add(key)
            labels = sorted((edge_label(first), edge_label(second)))
            roads.append({
                "id": f"{prefix}_road_{labels[0]}_to_{labels[1]}",
                "from": node_id(first),
                "to": node_id(second),
                "distanceKm": round(
                    haversine_km(coordinate(first), coordinate(second))
                    * ROAD_FACTOR,
                    2,
                ),
            })
    roads.sort(key=lambda road: road["id"])
    return nodes, roads


def network_components(
    nodes: list[dict],
    roads: list[dict],
) -> list[set[str]]:
    adjacency: dict[str, set[str]] = {node["id"]: set() for node in nodes}
    for road in roads:
        adjacency[road["from"]].add(road["to"])
        adjacency[road["to"]].add(road["from"])

    unvisited = set(adjacency)
    components: list[set[str]] = []
    while unvisited:
        seed = min(unvisited)
        component = {seed}
        pending = [seed]
        while pending:
            for neighbor in adjacency[pending.pop()]:
                if neighbor not in component:
                    component.add(neighbor)
                    pending.append(neighbor)
        unvisited -= component
        components.append(component)
    return components


def validate(
    nodes: list[dict],
    roads: list[dict],
    cities: dict[str, dict],
) -> None:
    node_ids = {node["id"] for node in nodes}
    road_ids = {road["id"] for road in roads}
    assert len(node_ids) == len(nodes), "duplicate node id"
    assert len(road_ids) == len(roads), "duplicate road id"

    adjacency: dict[str, set[str]] = {node_id: set() for node_id in node_ids}
    for road in roads:
        assert road["from"] in node_ids and road["to"] in node_ids, road["id"]
        assert road["from"] != road["to"], road["id"]
        assert road["distanceKm"] > 0, road["id"]
        adjacency[road["from"]].add(road["to"])
        adjacency[road["to"]].add(road["from"])

    missing = {city["roadNodeID"] for city in cities.values()} - node_ids
    assert not missing, f"cities without a network node: {sorted(missing)}"
    assert max(map(len, adjacency.values())) <= MAXIMUM_NODE_DEGREE

    node_by_id = {node["id"]: node for node in nodes}
    represented_continents = {city["continent"] for city in cities.values()}
    found_continents: set[str] = set()
    for component in network_components(nodes, roads):
        component_city_ids = {
            node_by_id[node_id]["cityID"]
            for node_id in component
            if node_by_id[node_id]["cityID"] is not None
        }
        assert component_city_ids, "road component has no city"
        continents = {
            cities[city_id]["continent"]
            for city_id in component_city_ids
        }
        assert len(continents) == 1, f"component spans continents: {continents}"
        continent = next(iter(continents))
        assert continent not in found_continents, f"split continent: {continent}"
        found_continents.add(continent)

        component_edges = sum(
            road["from"] in component and road["to"] in component
            for road in roads
        )
        cycle_rank = component_edges - len(component) + 1
        assert cycle_rank >= 1, f"{continent} backbone has no alternate route"

    assert found_continents == represented_continents


def write_json(path: Path, value) -> None:
    text = json.dumps(value, indent=2, ensure_ascii=False)
    text = re.sub(
        r"\{\s*\"latitude\":\s*(-?[\d.]+),\s*\"longitude\":\s*(-?[\d.]+)\s*\}",
        r'{ "latitude": \1, "longitude": \2 }',
        text,
    )
    path.write_text(text + "\n", encoding="utf-8")


def main() -> None:
    scripts_dir = Path(__file__).resolve().parent
    catalog_dir = scripts_dir.parent / "Goods&Glory" / "Resources" / "Catalog"
    cities = {
        city["id"]: city
        for city in json.loads((catalog_dir / "cities.json").read_text())
    }

    nodes: list[dict] = []
    roads: list[dict] = []
    assert set(CORRIDORS) == set(JUNCTIONS) == set(REGION_CONTINENTS)
    for prefix in sorted(CORRIDORS):
        region_nodes, region_roads = build_region(prefix, cities)
        nodes.extend(region_nodes)
        roads.extend(region_roads)

    validate(nodes, roads, cities)
    write_json(catalog_dir / "road_nodes.json", nodes)
    write_json(catalog_dir / "roads.json", roads)

    junction_count = sum(node["kind"] == "junction" for node in nodes)
    print(
        f"Wrote {len(nodes)} nodes ({junction_count} junctions) "
        f"and {len(roads)} roads"
    )


if __name__ == "__main__":
    main()
