#!/usr/bin/env python3
"""Build the authored foundation road network and bake its map geometry.

The graph is a logistics board, not a navigation database. Cities connect
directly; there are no invisible junction nodes. Real freight corridors only
inspire which city pairs get an edge.

City positions are authored in scripts/city_anchors.json as real WGS84 and
used as-is: the board is built from the same real coastline (build_board.py),
so there is nothing to convert. cities.json carries only the snapped result:
it is an output of this script, never a place to author a coordinate. Editing
a pin there is lost on the next run.

Map geometry is baked here rather than synthesised at render time. Every city
snaps onto one shared octilinear lattice (scripts/map_grid.py), and each road's
drawn polyline is an A* path over that lattice through land only. That makes
"roads never cross the sea" a build-time guarantee, and SpriteKit simply
strokes what this script wrote.

The polylines go to road_geometry.json, not roads.json: they are presentation
data, and the simulation must keep routing on distanceKm alone.

America and Europe deliberately remain separate road components. Future cities
join by attaching to one or two nearby cities on the same landmass, not by
adding a direct edge to every other city.

Usage: python3 -B scripts/generate_trade_network.py
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from map_grid import MAXIMUM_DETOUR, BoardGrid, corners, haversine_km

# Adjacent cities follow corridor geography. This modest factor turns
# great-circle distance into a plausible strategic road distance without making
# the visual schematic responsible for simulation cost or travel time.
ROAD_FACTOR = 1.15
MAXIMUM_NODE_DEGREE = 4

REGION_CONTINENTS = {
    "us": "america",
    "eu": "europe",
}

# Consecutive cities become undirected roads. Shared pairs become one RoadID, so
# two player routes using the same trunk also share one rendered path segment.
# Keep each region sparse and cyclic — not a complete graph.
CORRIDORS = {
    "us": {
        # Pacific spine.
        "west_coast": [
            "us_seattle",
            "us_los_angeles",
        ],
        # Southern belt across the Sun Belt into Florida.
        "southern": [
            "us_los_angeles",
            "us_dallas",
            "us_atlanta",
            "us_miami",
        ],
        # Gulf port off the Texas hub.
        "gulf": [
            "us_dallas",
            "us_houston",
        ],
        # Rockies / plains bridge into the Midwest.
        "rockies": [
            "us_dallas",
            "us_denver",
            "us_chicago",
        ],
        # Great Lakes into the Northeast.
        "lakes": [
            "us_chicago",
            "us_detroit",
            "us_new_york",
        ],
        # Atlantic seaboard.
        "atlantic": [
            "us_atlanta",
            "us_new_york",
        ],
        # Relief edge so the US backbone is not a single tree.
        "midwest_southeast": [
            "us_chicago",
            "us_atlanta",
        ],
    },
    "eu": {
        # Channel fixed link — the only road allowed to leave land.
        "channel": [
            "eu_london",
            "eu_paris",
        ],
        "west_central": [
            "eu_paris",
            "eu_frankfurt",
        ],
        "iberia": [
            "eu_paris",
            "eu_madrid",
        ],
        "alpine": [
            "eu_paris",
            "eu_milan",
            "eu_rome",
        ],
        # Alps into the Rhine hub — without this, eastern Europe can only
        # reach Milan by backtracking through Paris.
        "alpine_central": [
            "eu_frankfurt",
            "eu_milan",
        ],
        "north": [
            "eu_frankfurt",
            "eu_berlin",
            "eu_warsaw",
        ],
        "east": [
            "eu_warsaw",
            "eu_istanbul",
        ],
        # Relief so Europe stays cyclic without a single choke point.
        "central_east": [
            "eu_frankfurt",
            "eu_istanbul",
        ],
    },
}

# Roads permitted to leave land, with the water budget each may spend. Every
# other road is land-only by construction. London sits on its own island on the
# authored board, so London–Paris is a real fixed link rather than a shortcut.
WATER_CROSSINGS = {
    "eu_road_city_london_to_city_paris": 420.0,
}


def apply_anchors(cities: dict[str, dict], anchors_path: Path) -> dict[str, dict]:
    """Seed every city with its authored WGS84 coordinate.

    Snapping then moves it to the nearest free land cell, and the final write
    replaces the seed with that cell. The authored intent survives in
    city_anchors.json, which is the whole point: a pin nudged in cities.json
    used to be the only record of where a city was meant to be, and the next
    run silently overwrote it.
    """
    anchors = json.loads(anchors_path.read_text())["cities"]
    missing = sorted(set(cities) - set(anchors))
    if missing:
        raise SystemExit(
            f"cities without an anchor: {missing}. Add their real WGS84 "
            f"coordinate to {anchors_path.name}."
        )
    unknown = sorted(set(anchors) - set(cities))
    assert not unknown, f"anchors for cities that do not exist: {unknown}"

    for city_id, anchor in anchors.items():
        cities[city_id]["latitude"] = anchor["latitude"]
        cities[city_id]["longitude"] = anchor["longitude"]
    return anchors


def node_id(city: dict) -> str:
    return city["roadNodeID"]


def edge_label(city_id: str) -> str:
    return f"city_{city_id.split('_', 1)[1]}"


def build_region(prefix: str, cities: dict[str, dict]) -> tuple[list[dict], list[dict]]:
    """Authored city stops and undirected roads, still at their pre-snap hints."""
    corridors = CORRIDORS[prefix]

    stops = {stop for corridor in corridors.values() for stop in corridor}
    nodes: list[dict] = []
    for city_id in sorted(stops):
        city = cities[city_id]
        assert city["continent"] == REGION_CONTINENTS[prefix], city_id
        nodes.append({
            "id": node_id(city),
            "coordinate": {
                "latitude": city["latitude"],
                "longitude": city["longitude"],
            },
            "kind": "city",
            "cityID": city_id,
        })

    roads: list[dict] = []
    seen: set[frozenset[str]] = set()
    for corridor_name in sorted(corridors):
        corridor = corridors[corridor_name]
        assert len(corridor) >= 2, corridor_name
        for first, second in zip(corridor, corridor[1:]):
            first_id = node_id(cities[first])
            second_id = node_id(cities[second])
            key = frozenset((first_id, second_id))
            if key in seen:
                continue
            seen.add(key)
            labels = sorted((edge_label(first), edge_label(second)))
            roads.append({
                "id": f"{prefix}_road_{labels[0]}_to_{labels[1]}",
                "from": first_id,
                "to": second_id,
            })
    roads.sort(key=lambda road: road["id"])
    return nodes, roads


def snap_nodes(
    grid: BoardGrid,
    nodes: list[dict],
    roads: list[dict],
) -> dict[str, tuple[int, int]]:
    """Move every city onto a free land cell of the shared lattice.

    Neighbour alignment keeps a trunk straight: if two connected cities can
    share a row, column or diagonal, the corridor runs without a wobble.
    """
    neighbours: dict[str, set[str]] = {node["id"]: set() for node in nodes}
    for road in roads:
        neighbours[road["from"]].add(road["to"])
        neighbours[road["to"]].add(road["from"])

    anchors: dict[str, tuple[int, int]] = {}
    taken: set[tuple[int, int]] = set()
    for node in sorted(nodes, key=lambda node: node["id"]):
        cell, moved_km = grid.snap(
            node["coordinate"]["latitude"],
            node["coordinate"]["longitude"],
            taken,
            aligned_with=[
                anchors[other]
                for other in sorted(neighbours[node["id"]])
                if other in anchors
            ],
        )
        anchors[node["id"]] = cell
        taken.add(cell)
        latitude, longitude = grid.coordinate(cell)
        node["coordinate"] = {"latitude": latitude, "longitude": longitude}
        node["snapKm"] = round(moved_km, 1)
    return anchors


def bake_geometry(
    grid: BoardGrid,
    nodes: list[dict],
    roads: list[dict],
    anchors: dict[str, tuple[int, int]],
) -> float:
    """Attach the drawn octilinear polyline and the routing distance to each road.

    Roads are baked longest first and each one leaves its cells behind for the
    next, which is what bundles the network. Baking them independently gave
    every road its own line: two corridors heading the same way ran a cell
    apart for hundreds of km, and a short road joining a long one met it at an
    angle instead of merging into it.

    The order is by span then id, so the result stays deterministic.

    Returns the share of drawn cells carrying more than one road — the number
    that says whether the network reads as a metro map or as loose strokes.
    """
    coordinates = {node["id"]: node["coordinate"] for node in nodes}
    bundled: set[tuple[int, int]] = set()
    usage: Counter[tuple[int, int]] = Counter()

    def span(road: dict) -> int:
        start, end = anchors[road["from"]], anchors[road["to"]]
        return max(abs(start[0] - end[0]), abs(start[1] - end[1]))

    for road in sorted(roads, key=lambda road: (-span(road), road["id"])):
        budget = WATER_CROSSINGS.get(road["id"])
        crosses = budget is not None

        start, goal = anchors[road["from"]], anchors[road["to"]]

        # Try the straight-line ceiling first. Most roads have open terrain and
        # clear it, which settles them in one search. The ceiling is stricter
        # than the real rule, so a path found here always satisfies it.
        cells = grid.path(
            start,
            goal,
            may_cross_water=crosses,
            bundled=bundled,
            budget=MAXIMUM_DETOUR * grid.straight_km(start, goal),
        )
        if cells is None:
            # Terrain forces a detour, so measure what this road costs alone
            # and hold the bundled attempt to that instead. A ceiling measured
            # against the straight line would outlaw honest detours like
            # Chicago–Detroit rounding the Great Lakes.
            solo = grid.path(start, goal, may_cross_water=crosses)
            if solo is None:
                raise SystemExit(
                    f"{road['id']}: no land path between its endpoints. Move a "
                    f"city, or declare the road in WATER_CROSSINGS."
                )
            cells = grid.path(
                start,
                goal,
                may_cross_water=crosses,
                bundled=bundled,
                budget=MAXIMUM_DETOUR * grid.length_km(solo),
            ) or solo
        water = grid.water_km(cells)
        if budget is None:
            assert water == 0, road["id"]
        elif water > budget:
            raise SystemExit(
                f"{road['id']}: crossing spends {water:.0f} km on water, "
                f"budget is {budget:.0f} km."
            )
        road["points"] = [
            {"latitude": latitude, "longitude": longitude}
            for latitude, longitude in (grid.coordinate(cell) for cell in corners(cells))
        ]
        start = coordinates[road["from"]]
        end = coordinates[road["to"]]
        road["distanceKm"] = round(
            haversine_km(
                (start["latitude"], start["longitude"]),
                (end["latitude"], end["longitude"]),
            ) * ROAD_FACTOR,
            2,
        )
        road["waterKm"] = water
        bundled.update(cells)
        usage.update(cells)

    shared = sum(1 for count in usage.values() if count > 1)
    return shared / max(1, len(usage))


def network_components(nodes: list[dict], roads: list[dict]) -> list[set[str]]:
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


def validate(nodes: list[dict], roads: list[dict], cities: dict[str, dict]) -> None:
    node_ids = {node["id"] for node in nodes}
    road_ids = {road["id"] for road in roads}
    assert len(node_ids) == len(nodes), "duplicate node id"
    assert len(road_ids) == len(roads), "duplicate road id"
    assert all(node["kind"] == "city" and node["cityID"] for node in nodes)

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
        continents = {cities[city_id]["continent"] for city_id in component_city_ids}
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


def validate_geometry(grid: BoardGrid, nodes: list[dict], roads: list[dict]) -> None:
    """The drawn contract: on-lattice, octilinear, and joined to its endpoints."""
    coordinates = {node["id"]: node["coordinate"] for node in nodes}
    pitch_lat = grid.step_km / (6_378.137 * 3.141592653589793 / 180 * 1.364)
    pitch_lon = grid.step_km / (6_378.137 * 3.141592653589793 / 180)
    for road in roads:
        points = road["points"]
        assert len(points) >= 2, road["id"]
        for name, expected in (("from", road["from"]), ("to", road["to"])):
            end = points[0] if name == "from" else points[-1]
            assert end == coordinates[expected], f"{road['id']} {name} detached"
        for first, second in zip(points, points[1:]):
            steps_lat = (second["latitude"] - first["latitude"]) / pitch_lat
            steps_lon = (second["longitude"] - first["longitude"]) / pitch_lon
            assert abs(steps_lat - round(steps_lat)) < 0.02, road["id"]
            assert abs(steps_lon - round(steps_lon)) < 0.02, road["id"]
            rows, columns = abs(round(steps_lat)), abs(round(steps_lon))
            assert rows or columns, f"{road['id']} has a zero-length segment"
            # Octilinear: a run is axis-aligned or an exact diagonal.
            assert rows == 0 or columns == 0 or rows == columns, (
                f"{road['id']} has an off-angle segment"
            )


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
    city_records = json.loads((catalog_dir / "cities.json").read_text())
    cities = {city["id"]: city for city in city_records}
    apply_anchors(cities, scripts_dir / "city_anchors.json")

    grid = BoardGrid(catalog_dir / "map_board_silhouette.json")

    nodes: list[dict] = []
    roads: list[dict] = []
    assert set(CORRIDORS) == set(REGION_CONTINENTS)
    for prefix in sorted(CORRIDORS):
        region_nodes, region_roads = build_region(prefix, cities)
        nodes.extend(region_nodes)
        roads.extend(region_roads)

    anchors = snap_nodes(grid, nodes, roads)
    shared_share = bake_geometry(grid, nodes, roads, anchors)

    # A city pin and its road node are the same lattice cell, so the pin sits
    # exactly where its roads meet instead of a short off-grid stub away.
    for node in nodes:
        city = cities[node["cityID"]]
        city["latitude"] = node["coordinate"]["latitude"]
        city["longitude"] = node["coordinate"]["longitude"]

    validate(nodes, roads, cities)
    validate_geometry(grid, nodes, roads)

    report = sorted(
        ((node.pop("snapKm"), node["id"]) for node in nodes), reverse=True
    )
    water = {road["id"]: road.pop("waterKm") for road in roads}

    write_json(catalog_dir / "cities.json", city_records)
    write_json(catalog_dir / "road_nodes.json", nodes)
    write_json(
        catalog_dir / "roads.json",
        [
            {
                "id": road["id"],
                "from": road["from"],
                "to": road["to"],
                "distanceKm": road["distanceKm"],
            }
            for road in roads
        ],
    )
    write_json(
        catalog_dir / "road_geometry.json",
        {
            "version": 1,
            "source": (
                f"Octilinear lattice at {grid.step_km:.0f} km, land-constrained "
                f"A* (generate_trade_network.py)"
            ),
            "roads": [
                {"id": road["id"], "points": road["points"]}
                for road in roads
            ],
        },
    )

    bends = [len(road["points"]) - 2 for road in roads]
    print(
        f"Wrote {len(nodes)} city nodes and {len(roads)} roads\n"
        f"  lattice   {grid.rows}x{grid.columns} @ {grid.step_km:.0f} km\n"
        f"  bends     avg {sum(bends)/len(bends):.2f}, max {max(bends)}\n"
        f"  bundled   {shared_share:.0%} of drawn cells shared\n"
        f"  snap      max {report[0][0]:.0f} km ({report[0][1]})\n"
        f"  crossings {[f'{k}: {v:.0f} km' for k, v in water.items() if v] or 'none'}"
    )


if __name__ == "__main__":
    main()
