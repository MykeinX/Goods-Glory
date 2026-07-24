#!/usr/bin/env python3
"""Build the authored world trade network (road_nodes.json + roads.json).

The map is a logistics tycoon board, not a navigation atlas. Instead of a
dense graph collapsed from surveyed road data, the network is authored as a
small set of named trade corridors — Interstates, the Rhine–Danube axis, the
Silk Road, the Trans-Siberian — expressed as ordered stop lists over the 71
catalog cities plus a handful of steering junctions. Junctions exist for two
reasons only: a corridor genuinely branches there (Calais, Belgrade, Lanzhou)
or the line must be steered around water or mountains (Lyon, Zahedan).

Consecutive stops become single edges. SpriteKit turns each edge chain into
one clean octilinear "metro" leg at render time (MapCorridorCache), so this
file stays purely topological: nodes, edges, distances.

- distanceKm = great-circle distance x ROAD_FACTOR, matching the convention
  the Eurasian network already used. Domain travel time, costs and offer
  weighting all read this number.
- Continents are separate components (America / Europe / Asia): road networks
  do not cross between continents, so there is no Bosphorus or Atlantic edge.

Output replaces the generated TIGER graph from generate_us_map.py; that
script remains the source for cities.json and city_markets.json only.

Usage: python3 -B scripts/generate_trade_network.py
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

# Detours around terrain that the straight board line ignores.
ROAD_FACTOR = 1.15

# Steering junctions: id suffix -> (latitude, longitude).
AMERICA_JUNCTIONS = {
    "el_paso": (31.79, -106.42),
    "san_antonio": (29.42, -98.49),
    "billings": (45.79, -108.50),
    "cleveland": (41.50, -81.69),
    "little_rock": (34.74, -92.29),
}

EURASIA_JUNCTIONS = {
    "calais": (50.95, 1.85),
    "lyon": (45.76, 4.84),
    "hannover": (52.37, 9.73),
    "malmo": (55.60, 13.00),
    "jonkoping": (57.78, 14.16),
    "innsbruck": (47.27, 11.40),
    "stuttgart": (48.78, 9.18),
    "belgrade": (44.79, 20.45),
    "sofia": (42.70, 23.32),
    "skopje": (41.99, 21.43),
    "bucharest": (44.43, 26.10),
    "minsk": (53.90, 27.56),
    "tabriz": (38.08, 46.29),
    "adana": (37.00, 35.32),
    "amman": (31.95, 35.93),
    "kuwait": (29.38, 47.99),
    "mashhad": (36.30, 59.61),
    "zahedan": (29.50, 60.86),
    "urumqi": (43.83, 87.62),
    "lanzhou": (36.06, 103.83),
    "ulaanbaatar": (47.92, 106.92),
    "shenyang": (41.80, 123.43),
    "kunming": (25.04, 102.72),
    "phnom_penh": (11.56, 104.92),
    "bangalore": (12.97, 77.59),
}

# Corridors as ordered stop lists. Entries are city IDs (as in cities.json)
# or "jct:<suffix>" steering junctions. Consecutive pairs become edges;
# corridors sharing a pair share the edge.
AMERICA_CORRIDORS = {
    # I-5 Pacific coast
    "pacific_coast": ["us_seattle", "us_san_francisco", "us_los_angeles"],
    # I-10 sunbelt
    "sunbelt": [
        "us_los_angeles", "us_phoenix", "jct:el_paso", "jct:san_antonio",
        "us_houston", "us_new_orleans",
    ],
    # I-15 desert
    "mojave": ["us_los_angeles", "us_las_vegas", "us_salt_lake_city"],
    # I-80 / I-70 central transcontinental
    "central_transcon": [
        "us_san_francisco", "us_salt_lake_city", "us_denver",
        "us_kansas_city", "us_st_louis",
    ],
    # I-90 / I-94 northern tier
    "northern_tier": [
        "us_seattle", "jct:billings", "us_minneapolis", "us_chicago",
    ],
    # I-35 heartland spine
    "heartland": [
        "us_minneapolis", "us_kansas_city", "us_dallas", "jct:san_antonio",
    ],
    # I-45
    "texas_triangle": ["us_dallas", "us_houston"],
    # I-20
    "i20_west": ["jct:el_paso", "us_dallas"],
    # I-30 / I-40 mid-south
    "mid_south": ["us_dallas", "jct:little_rock", "us_nashville"],
    # I-80 / I-90 Great Lakes to the Atlantic
    "great_lakes_east": [
        "us_chicago", "us_detroit", "jct:cleveland", "us_new_york",
    ],
    # I-95 northeast corridor
    "northeast": ["us_boston", "us_new_york", "us_washington"],
    # I-85 Piedmont
    "piedmont": ["us_washington", "us_charlotte", "us_atlanta"],
    # I-24 / I-57 / I-55 Dixie corridor
    "dixie": ["us_atlanta", "us_nashville", "us_st_louis", "us_chicago"],
    # I-75 southeast
    "southeast": ["us_atlanta", "us_miami"],
    # I-59 / I-20 gulf link
    "gulf_link": ["us_new_orleans", "us_atlanta"],
}

EURASIA_CORRIDORS = {
    # Iberia
    "iberia": ["eu_lisbon", "eu_madrid", "eu_barcelona"],
    "madrid_paris": ["eu_madrid", "eu_paris"],
    # Rhone axis: Mediterranean trade steered inland around the gulf of Genoa
    "rhone_axis": ["eu_barcelona", "jct:lyon", "eu_milan"],
    "paris_lyon": ["eu_paris", "jct:lyon"],
    # Channel tunnel trunk shared by both branches
    "channel": ["eu_london", "jct:calais", "eu_paris"],
    "channel_north": ["jct:calais", "eu_brussels"],
    # Benelux and the North Sea range
    "north_sea_range": [
        "eu_paris", "eu_brussels", "eu_rotterdam", "eu_amsterdam", "eu_hamburg",
    ],
    # A2: Dutch ports into Berlin
    "a2_hannover": ["eu_rotterdam", "jct:hannover", "eu_berlin"],
    "hamburg_berlin": ["eu_hamburg", "eu_berlin"],
    # Oresund bridge and the Scandinavian spine
    "nordic": [
        "eu_hamburg", "eu_copenhagen", "jct:malmo", "jct:jonkoping",
        "eu_stockholm",
    ],
    "oder": ["eu_berlin", "eu_warsaw"],
    "bohemia": ["eu_berlin", "eu_prague", "eu_vienna"],
    # Paris–Munich via Stuttgart
    "swabia": ["eu_paris", "jct:stuttgart", "eu_munich"],
    "salzburg_link": ["eu_munich", "eu_vienna"],
    # Brenner pass
    "brenner": ["eu_munich", "jct:innsbruck", "eu_milan"],
    "italy": ["eu_milan", "eu_rome"],
    "danube": ["eu_vienna", "eu_budapest"],
    # Pan-European corridor X and its Athens branch
    "corridor_x": [
        "eu_budapest", "jct:belgrade", "jct:sofia", "eu_istanbul",
    ],
    "athens_branch": ["jct:belgrade", "jct:skopje", "eu_athens"],
    # Corridor IV through Romania
    "corridor_iv": ["eu_budapest", "jct:bucharest", "eu_istanbul"],
    "east_west": ["eu_warsaw", "jct:minsk", "eu_moscow"],
    "e40": ["eu_warsaw", "eu_kyiv"],
    "kyiv_moscow": ["eu_kyiv", "eu_moscow"],
    "e85": ["eu_kyiv", "jct:bucharest"],
    # No Bosphorus crossing: continents are separate road networks by design
    # (see Continent in CatalogDefinitions) — Europe↔Asia freight waits for
    # sea/air modes.
    # Anatolia into Persia
    "anatolia_iran": ["as_ankara", "jct:tabriz", "as_tehran"],
    # Levant route down to the Gulf
    "levant": ["as_ankara", "jct:adana", "jct:amman", "as_riyadh"],
    "gulf_coast": ["as_riyadh", "as_dubai"],
    "gulf_north": ["as_riyadh", "jct:kuwait", "as_tehran"],
    # Khorasan leg of the Silk Road
    "khorasan": ["as_tehran", "jct:mashhad", "as_tashkent"],
    "silk_road": [
        "as_tashkent", "as_almaty", "jct:urumqi", "jct:lanzhou", "as_xian",
    ],
    "hexi_south": ["jct:lanzhou", "as_chengdu"],
    # Baluchistan land route to the subcontinent
    "baluchistan": ["as_tehran", "jct:zahedan", "as_karachi"],
    # Trans-Siberian starts at the Urals: Moscow is Europe and continents do
    # not share a road network.
    "trans_siberian": ["as_yekaterinburg", "as_novosibirsk"],
    "turk_sib": ["as_novosibirsk", "as_almaty"],
    "trans_mongolian": ["as_novosibirsk", "jct:ulaanbaatar", "as_beijing"],
    "china_north": ["as_xian", "as_beijing"],
    "jinghu": ["as_beijing", "as_shanghai"],
    "china_coast": ["as_shanghai", "as_guangzhou"],
    "china_west": ["as_xian", "as_chengdu"],
    # Kunming hub: into Vietnam and down the old Burma Road
    "yunnan": ["as_chengdu", "jct:kunming", "as_hanoi"],
    "burma_road": ["jct:kunming", "as_yangon"],
    "korea": ["as_beijing", "jct:shenyang", "as_seoul"],
    "nanning_link": ["as_guangzhou", "as_hanoi"],
    "vietnam_coast": ["as_hanoi", "as_ho_chi_minh_city"],
    "indochina": ["as_ho_chi_minh_city", "jct:phnom_penh", "as_bangkok"],
    "malay": ["as_bangkok", "as_kuala_lumpur"],
    "thai_burma": ["as_bangkok", "as_yangon"],
    # Subcontinent: N-5, Grand Trunk Road and the coastal diagonals
    "n5": ["as_karachi", "as_lahore"],
    "grand_trunk_west": ["as_lahore", "as_delhi"],
    "grand_trunk_east": ["as_delhi", "as_kolkata"],
    "delhi_mumbai": ["as_delhi", "as_mumbai"],
    "deccan": ["as_mumbai", "jct:bangalore", "as_chennai"],
    "coromandel": ["as_kolkata", "as_chennai"],
    "bengal": ["as_kolkata", "as_dhaka"],
    "dhaka_yangon": ["as_dhaka", "as_yangon"],
}


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    radius = 6371.0
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * radius * math.asin(math.sqrt(h))


def build_region(
    prefix: str,
    junctions: dict[str, tuple[float, float]],
    corridors: dict[str, list[str]],
    cities: dict[str, dict],
) -> tuple[list[dict], list[dict]]:
    def node_id(stop: str) -> str:
        if stop.startswith("jct:"):
            return f"{prefix}_jct_{stop[4:]}"
        return cities[stop]["roadNodeID"]

    def coordinate(stop: str) -> tuple[float, float]:
        if stop.startswith("jct:"):
            return junctions[stop[4:]]
        city = cities[stop]
        return (city["latitude"], city["longitude"])

    nodes: list[dict] = []
    for stop_city in sorted(
        {stop for stops in corridors.values() for stop in stops
         if not stop.startswith("jct:")}
    ):
        city = cities[stop_city]
        nodes.append({
            "id": city["roadNodeID"],
            "coordinate": {
                "latitude": city["latitude"],
                "longitude": city["longitude"],
            },
            "kind": "city",
            "cityID": stop_city,
        })
    for suffix in sorted(junctions):
        latitude, longitude = junctions[suffix]
        nodes.append({
            "id": f"{prefix}_jct_{suffix}",
            "coordinate": {"latitude": latitude, "longitude": longitude},
            "kind": "junction",
            "cityID": None,
        })

    edges: list[dict] = []
    seen: set[frozenset[str]] = set()
    for corridor_name in sorted(corridors):
        stops = corridors[corridor_name]
        for first, second in zip(stops, stops[1:]):
            key = frozenset((node_id(first), node_id(second)))
            if key in seen:
                continue
            seen.add(key)
            distance = haversine_km(coordinate(first), coordinate(second))
            edges.append({
                "id": f"{prefix}_road_{len(edges) + 1:05d}",
                "from": node_id(first),
                "to": node_id(second),
                "distanceKm": round(distance * ROAD_FACTOR, 2),
            })
    return nodes, edges


def validate(
    nodes: list[dict],
    edges: list[dict],
    cities: dict[str, dict],
) -> None:
    node_ids = {node["id"] for node in nodes}
    assert len(node_ids) == len(nodes), "duplicate node id"
    for edge in edges:
        assert edge["from"] in node_ids and edge["to"] in node_ids, edge["id"]
        assert edge["distanceKm"] > 0, edge["id"]

    missing = {
        city["roadNodeID"] for city in cities.values()
    } - node_ids
    assert not missing, f"cities without a network node: {sorted(missing)}"

    # Connectivity: every component must contain a city (catalog validation)
    # and each continent must be exactly one component of its own.
    adjacency: dict[str, set[str]] = {node["id"]: set() for node in nodes}
    for edge in edges:
        adjacency[edge["from"]].add(edge["to"])
        adjacency[edge["to"]].add(edge["from"])
    unvisited = set(node_ids)
    components: list[set[str]] = []
    while unvisited:
        seed = unvisited.pop()
        component = {seed}
        frontier = [seed]
        while frontier:
            for neighbor in adjacency[frontier.pop()]:
                if neighbor not in component:
                    component.add(neighbor)
                    frontier.append(neighbor)
        unvisited -= component
        components.append(component)
    city_nodes = {node["id"] for node in nodes if node["kind"] == "city"}
    continent_by_city_node = {
        city["roadNodeID"]: city["continent"] for city in cities.values()
    }
    assert len(components) == 3, f"expected 3 components, got {len(components)}"
    for component in components:
        continents = {
            continent_by_city_node[node_id]
            for node_id in component & city_nodes
        }
        assert len(continents) == 1, f"component spans continents: {continents}"

    isolated = [node_id for node_id, others in adjacency.items() if not others]
    assert not isolated, f"isolated nodes: {isolated}"


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

    america_nodes, america_edges = build_region(
        "am", AMERICA_JUNCTIONS, AMERICA_CORRIDORS, cities
    )
    eurasia_nodes, eurasia_edges = build_region(
        "ea", EURASIA_JUNCTIONS, EURASIA_CORRIDORS, cities
    )
    nodes = america_nodes + eurasia_nodes
    edges = america_edges + eurasia_edges
    validate(nodes, edges, cities)

    write_json(catalog_dir / "road_nodes.json", nodes)
    write_json(catalog_dir / "roads.json", edges)

    junction_count = sum(1 for node in nodes if node["kind"] == "junction")
    print(
        f"Wrote {len(nodes)} nodes ({junction_count} junctions) "
        f"and {len(edges)} edges\n"
        f"  america: {len(america_nodes)} nodes / {len(america_edges)} edges\n"
        f"  eurasia: {len(eurasia_nodes)} nodes / {len(eurasia_edges)} edges"
    )


if __name__ == "__main__":
    main()


