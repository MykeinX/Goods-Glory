#!/usr/bin/env python3
"""Build the bundled contiguous-US strategic map from pinned source files.

The game intentionally keeps a strategic level of detail: ~22 geographically
spaced major metro hubs, principal Interstate corridors, and their real
junction topology. Divided carriageways and sub-kilometre detail are collapsed
before JSON is written.

Expected files below --source-dir:
  primaryroads/tl_2025_us_primaryroads.{shp,dbf}
  gazetteer/2025_Gaz_place_national.txt
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import struct
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path


KM_PER_LATITUDE_DEGREE = 111.32
KM_PER_LONGITUDE_DEGREE = 88.2  # Contiguous-US midpoint; topology only.
CONTIGUOUS_BOUNDS = (-125.0, 24.0, -66.0, 50.0)

# TIGER occasionally stores an urban Interstate segment under its well-known
# freeway name instead of the route number. Only aliases needed to keep a
# numbered strategic corridor continuous are included.
FREEWAY_ALIASES = {
    "Santa Monica Fwy": "I-10",
    "San Bernardino Fwy": "I-10",
    "W San Bernadino Fwy": "I-10",
    "E San Bernadino Fwy": "I-10",
    "Katy Fwy": "I-10",
    "East Fwy": "I-10",
    "Gulf Fwy": "I-45",
    "Gulf Fwy N": "I-45",
    "Gulf Fwy S": "I-45",
    "North Fwy": "I-45",
    "Galveston Cswy": "I-45",
    "Southwest Fwy": "I-69",
    "Eastex Fwy": "I-69",
    "Southern Tier Expy": "I-86",
}


@dataclass(frozen=True)
class CitySpec:
    slug: str
    name: str
    state: str
    place_name: str
    population: int
    cost_index: int
    traffic_index: int
    starter: bool = False
    coordinate_override: tuple[float, float] | None = None


# Population: Census 2025 metro estimates. Cost: BEA 2023 metro RPP x10.
# Traffic: FHWA FY2026 Q1 peak Travel Time Index x1000.
#
# Access flags (static gameplay metadata, not full mode graphs):
#   rail — Class I freight railroad with local yards / intermodal in the metro.
#   air  — Significant dedicated freighter or express-hub cargo role
#          (ACI-NA / FAA all-cargo class metros).
#   sea  — Commercial deep-draft coastal/estuarine or Great Lakes port.
#          Inland river barge hubs alone are false.
CITY_ACCESS: dict[str, tuple[bool, bool, bool]] = {
    # slug: (rail, air, sea)
    "new_york": (True, True, True),
    "los_angeles": (True, True, True),
    "chicago": (True, True, True),  # Great Lakes commercial port
    "dallas": (True, True, False),
    "houston": (True, True, True),
    "atlanta": (True, True, False),
    "washington": (True, True, False),
    "miami": (True, True, True),
    "phoenix": (True, True, False),
    "boston": (True, True, True),
    "san_francisco": (True, True, True),
    "detroit": (True, True, True),  # Great Lakes
    "seattle": (True, True, True),
    "minneapolis": (True, True, False),  # river barge, not deep-sea
    "denver": (True, True, False),
    "charlotte": (True, True, False),
    "st_louis": (True, False, False),  # major rail; limited air cargo; river only
    "las_vegas": (False, False, False),  # UP through-line, no freight hub / no port
    "kansas_city": (True, False, False),
    "nashville": (True, False, False),
    "salt_lake_city": (True, False, False),
    "new_orleans": (True, False, True),
}

CITY_SPECS = [
    # Sparse national skeleton (~22): famous metros only, one hub per region cluster.
    CitySpec("new_york", "New York", "NY", "New York city", 20_112_448, 1125, 1340, coordinate_override=(-74.0060, 40.7128)),
    CitySpec("los_angeles", "Los Angeles", "CA", "Los Angeles city", 12_844_441, 1155, 1590, True, coordinate_override=(-118.2437, 34.0522)),
    CitySpec("chicago", "Chicago", "IL", "Chicago city", 9_434_123, 1026, 1300, True),
    CitySpec("dallas", "Dallas", "TX", "Dallas city", 8_477_157, 1033, 1320),
    CitySpec("houston", "Houston", "TX", "Houston city", 7_904_627, 1002, 1340, True),
    CitySpec("atlanta", "Atlanta", "GA", "Atlanta city", 6_482_182, 1009, 1310, True),
    CitySpec("washington", "Washington", "DC", "Washington city", 6_465_724, 1086, 1330),
    CitySpec("miami", "Miami", "FL", "Miami city", 6_391_072, 1118, 1380, True),
    CitySpec("phoenix", "Phoenix", "AZ", "Phoenix city", 5_228_938, 1055, 1190, True),
    CitySpec("boston", "Boston", "MA", "Boston city", 5_034_221, 1116, 1270, True),
    CitySpec("san_francisco", "San Francisco", "CA", "San Francisco city", 4_630_041, 1182, 1350, coordinate_override=(-122.4194, 37.7749)),
    CitySpec("detroit", "Detroit", "MI", "Detroit city", 4_390_913, 980, 1130),
    CitySpec("seattle", "Seattle", "WA", "Seattle city", 4_161_883, 1130, 1360, True),
    CitySpec("minneapolis", "Minneapolis", "MN", "Minneapolis city", 3_790_295, 1045, 1210),
    CitySpec("denver", "Denver", "CO", "Denver city", 3_092_037, 1055, 1280, True),
    CitySpec("charlotte", "Charlotte", "NC", "Charlotte city", 2_938_830, 970, 1230),
    CitySpec("st_louis", "St. Louis", "MO", "St. Louis city", 2_814_421, 963, 1020),
    CitySpec("las_vegas", "Las Vegas", "NV", "Las Vegas city", 2_407_226, 974, 1220, coordinate_override=(-115.1398, 36.1699)),
    CitySpec("kansas_city", "Kansas City", "MO", "Kansas City city", 2_270_682, 933, 1100),
    CitySpec("nashville", "Nashville", "TN", "Nashville-Davidson metropolitan government (balance)", 2_197_416, 974, 1220),
    CitySpec("salt_lake_city", "Salt Lake City", "UT", "Salt Lake City city", 1_308_377, 964, 1160),
    CitySpec("new_orleans", "New Orleans", "LA", "New Orleans city", 970_849, 911, 1170),
]


@dataclass
class Feature:
    highway: str
    route_key: str
    geometry: list[tuple[float, float]]  # longitude, latitude


@dataclass
class Event:
    feature: int
    segment: int
    fraction: float
    point: tuple[float, float]


@dataclass
class Edge:
    start: int
    end: int
    highway: str
    geometry: list[tuple[float, float]]


class UnionFind:
    def __init__(self, size: int):
        self.parent = list(range(size))

    def find(self, value: int) -> int:
        while self.parent[value] != value:
            self.parent[value] = self.parent[self.parent[value]]
            value = self.parent[value]
        return value

    def union(self, left: int, right: int) -> None:
        left = self.find(left)
        right = self.find(right)
        if left != right:
            self.parent[right] = left


def planar(point: tuple[float, float]) -> tuple[float, float]:
    return point[0] * KM_PER_LONGITUDE_DEGREE, point[1] * KM_PER_LATITUDE_DEGREE


def planar_distance(left: tuple[float, float], right: tuple[float, float]) -> float:
    lx, ly = planar(left)
    rx, ry = planar(right)
    return math.hypot(rx - lx, ry - ly)


def geographic_distance(left: tuple[float, float], right: tuple[float, float]) -> float:
    lon1, lat1 = map(math.radians, left)
    lon2, lat2 = map(math.radians, right)
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    value = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(max(0.0, min(1.0, value))))


def geometry_distance(points: list[tuple[float, float]]) -> float:
    return sum(geographic_distance(a, b) for a, b in zip(points, points[1:]))


def interpolate(left: tuple[float, float], right: tuple[float, float], fraction: float) -> tuple[float, float]:
    return (
        left[0] + (right[0] - left[0]) * fraction,
        left[1] + (right[1] - left[1]) * fraction,
    )


def closest_point_on_segment(
    point: tuple[float, float],
    start: tuple[float, float],
    end: tuple[float, float],
) -> tuple[float, tuple[float, float], float]:
    px, py = planar(point)
    ax, ay = planar(start)
    bx, by = planar(end)
    dx, dy = bx - ax, by - ay
    denominator = dx * dx + dy * dy
    fraction = 0.0 if denominator == 0 else ((px - ax) * dx + (py - ay) * dy) / denominator
    fraction = max(0.0, min(1.0, fraction))
    closest = interpolate(start, end, fraction)
    return planar_distance(point, closest), closest, fraction


def segment_intersection(
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
    d: tuple[float, float],
) -> tuple[float, float, tuple[float, float]] | None:
    ax, ay = planar(a)
    bx, by = planar(b)
    cx, cy = planar(c)
    dx, dy = planar(d)
    rx, ry = bx - ax, by - ay
    sx, sy = dx - cx, dy - cy
    denominator = rx * sy - ry * sx
    if abs(denominator) < 1e-9:
        return None
    qx, qy = cx - ax, cy - ay
    first = (qx * sy - qy * sx) / denominator
    second = (qx * ry - qy * rx) / denominator
    tolerance = 1e-8
    if -tolerance <= first <= 1 + tolerance and -tolerance <= second <= 1 + tolerance:
        first = max(0.0, min(1.0, first))
        second = max(0.0, min(1.0, second))
        return first, second, interpolate(a, b, first)
    return None


def douglas_peucker(points: list[tuple[float, float]], tolerance_km: float) -> list[tuple[float, float]]:
    if len(points) <= 2:
        return points
    first = planar(points[0])
    last = planar(points[-1])
    dx, dy = last[0] - first[0], last[1] - first[1]
    denominator = dx * dx + dy * dy
    index = 0
    farthest = -1.0
    for candidate_index, candidate in enumerate(points[1:-1], 1):
        px, py = planar(candidate)
        if denominator == 0:
            distance = math.hypot(px - first[0], py - first[1])
        else:
            fraction = max(0.0, min(1.0, ((px - first[0]) * dx + (py - first[1]) * dy) / denominator))
            distance = math.hypot(px - (first[0] + fraction * dx), py - (first[1] + fraction * dy))
        if distance > farthest:
            index, farthest = candidate_index, distance
    if farthest <= tolerance_km:
        return [points[0], points[-1]]
    return douglas_peucker(points[: index + 1], tolerance_km)[:-1] + douglas_peucker(points[index:], tolerance_km)


def read_dbf(path: Path) -> list[dict[str, str]]:
    with path.open("rb") as handle:
        header = handle.read(32)
        record_count, header_length, record_length = struct.unpack_from("<IHH", header, 4)
        fields: list[tuple[str, int]] = []
        while handle.tell() < header_length - 1:
            descriptor = handle.read(32)
            name = descriptor[:11].split(b"\0", 1)[0].decode("ascii")
            fields.append((name, descriptor[16]))
        handle.read(1)
        result = []
        for _ in range(record_count):
            record = handle.read(record_length)
            offset = 1
            values = {}
            for name, length in fields:
                values[name] = record[offset : offset + length].decode("latin-1").strip()
                offset += length
            result.append(values)
        return result


def read_polyline_shapefile(path: Path) -> list[list[list[tuple[float, float]]]]:
    records: list[list[list[tuple[float, float]]]] = []
    with path.open("rb") as handle:
        handle.read(100)
        while header := handle.read(8):
            _, content_words = struct.unpack(">2i", header)
            content = handle.read(content_words * 2)
            shape_type = struct.unpack_from("<i", content, 0)[0]
            if shape_type == 0:
                records.append([])
                continue
            if shape_type != 3:
                raise ValueError(f"Expected PolyLine shapefile, found shape type {shape_type}")
            part_count, point_count = struct.unpack_from("<2i", content, 36)
            starts = list(struct.unpack_from(f"<{part_count}i", content, 44))
            values = struct.unpack_from(f"<{point_count * 2}d", content, 44 + part_count * 4)
            points = list(zip(values[::2], values[1::2]))
            starts.append(point_count)
            records.append([points[starts[i] : starts[i + 1]] for i in range(part_count)])
    return records


def normalized_interstate(name: str) -> str | None:
    normalized = name.strip()
    if re.search(r"\b(?:Bus|Hov|Express|Spr)\b", normalized, re.IGNORECASE):
        return None
    match = re.match(r"(?:[NSEW]\s+)?I-\s*(\d{1,3})(?:\s*([A-Z]))?", normalized)
    if not match:
        return None
    number = int(match.group(1))
    strategic_auxiliaries = {215, 264, 275, 279, 280, 376, 680, 880}
    if number > 99 and number not in strategic_auxiliaries:
        return None
    return f"I-{number}{match.group(2) or ''}"


def is_contiguous(points: list[tuple[float, float]]) -> bool:
    min_lon, min_lat, max_lon, max_lat = CONTIGUOUS_BOUNDS
    return any(min_lon <= lon <= max_lon and min_lat <= lat <= max_lat for lon, lat in points)


def load_features(source_dir: Path) -> list[Feature]:
    base = source_dir / "primaryroads" / "tl_2025_us_primaryroads"
    rows = read_dbf(base.with_suffix(".dbf"))
    shapes = read_polyline_shapefile(base.with_suffix(".shp"))
    if len(rows) != len(shapes):
        raise ValueError("Primary-road SHP and DBF record counts differ")

    candidates: list[Feature] = []
    for row, parts in zip(rows, shapes):
        highway = normalized_interstate(row["FULLNAME"]) if row["RTTYP"] == "I" else None
        if highway is None and row["RTTYP"] == "M":
            highway = FREEWAY_ALIASES.get(row["FULLNAME"])
        if highway is None:
            continue
        route_key = highway
        for points in parts:
            if len(points) >= 2 and is_contiguous(points):
                candidates.append(Feature(highway, route_key, points))

    # TIGER represents most divided highways as two carriageways. Features with
    # the same designation and near-identical endpoints are one strategic road.
    union = UnionFind(len(candidates))
    by_highway: dict[str, list[int]] = defaultdict(list)
    for index, feature in enumerate(candidates):
        by_highway[feature.route_key].append(index)
    for indices in by_highway.values():
        for offset, left_index in enumerate(indices):
            left = candidates[left_index].geometry
            for right_index in indices[offset + 1 :]:
                right = candidates[right_index].geometry
                direct = max(planar_distance(left[0], right[0]), planar_distance(left[-1], right[-1]))
                reverse = max(planar_distance(left[0], right[-1]), planar_distance(left[-1], right[0]))
                if min(direct, reverse) <= 1.0:
                    union.union(left_index, right_index)

    groups: dict[int, list[int]] = defaultdict(list)
    for index in range(len(candidates)):
        groups[union.find(index)].append(index)
    representatives = []
    for indices in groups.values():
        chosen = max(indices, key=lambda index: geometry_distance(candidates[index].geometry))
        feature = candidates[chosen]
        simplified = douglas_peucker(feature.geometry, tolerance_km=0.35)
        representatives.append(Feature(feature.highway, feature.route_key, simplified))
    representatives.sort(key=lambda feature: (feature.route_key, feature.geometry[0], feature.geometry[-1]))
    return representatives


def build_segment_index(features: list[Feature], cell_size_km: float = 30.0):
    segments = []
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for feature_index, feature in enumerate(features):
        for segment_index, (start, end) in enumerate(zip(feature.geometry, feature.geometry[1:])):
            ax, ay = planar(start)
            bx, by = planar(end)
            segment_id = len(segments)
            segments.append((feature_index, segment_index, start, end))
            for x in range(math.floor(min(ax, bx) / cell_size_km), math.floor(max(ax, bx) / cell_size_km) + 1):
                for y in range(math.floor(min(ay, by) / cell_size_km), math.floor(max(ay, by) / cell_size_km) + 1):
                    grid[(x, y)].append(segment_id)
    return segments, grid


def find_events(features: list[Feature]) -> list[Event]:
    events = []
    for feature_index, feature in enumerate(features):
        events.append(Event(feature_index, 0, 0.0, feature.geometry[0]))
        events.append(Event(feature_index, len(feature.geometry) - 2, 1.0, feature.geometry[-1]))

    segments, grid = build_segment_index(features)
    compared: set[tuple[int, int]] = set()
    for bucket in grid.values():
        for offset, left_id in enumerate(bucket):
            for right_id in bucket[offset + 1 :]:
                pair = (min(left_id, right_id), max(left_id, right_id))
                if pair in compared:
                    continue
                compared.add(pair)
                left_feature, left_segment, a, b = segments[left_id]
                right_feature, right_segment, c, d = segments[right_id]
                if left_feature == right_feature:
                    continue
                intersection = segment_intersection(a, b, c, d)
                if intersection is None:
                    continue
                left_fraction, right_fraction, point = intersection
                events.append(Event(left_feature, left_segment, left_fraction, point))
                events.append(Event(right_feature, right_segment, right_fraction, point))

    # Join a route that terminates just beside another Interstate centreline.
    for feature_index, feature in enumerate(features):
        for segment_index, fraction, endpoint in (
            (0, 0.0, feature.geometry[0]),
            (len(feature.geometry) - 2, 1.0, feature.geometry[-1]),
        ):
            px, py = planar(endpoint)
            cell = (math.floor(px / 30.0), math.floor(py / 30.0))
            best = None
            for x in range(cell[0] - 1, cell[0] + 2):
                for y in range(cell[1] - 1, cell[1] + 2):
                    for segment_id in grid.get((x, y), []):
                        other_feature, other_segment, start, end = segments[segment_id]
                        if other_feature == feature_index:
                            continue
                        distance, point, other_fraction = closest_point_on_segment(endpoint, start, end)
                        if distance <= 1.0 and (best is None or distance < best[0]):
                            best = (distance, other_feature, other_segment, other_fraction, point)
            if best is not None:
                _, other_feature, other_segment, other_fraction, point = best
                events.append(Event(feature_index, segment_index, fraction, endpoint))
                events.append(Event(other_feature, other_segment, other_fraction, point))
    return events


def cluster_events(events: list[Event], radius_km: float = 1.0):
    union = UnionFind(len(events))
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for index, event in enumerate(events):
        x, y = planar(event.point)
        cell = (math.floor(x / radius_km), math.floor(y / radius_km))
        for nearby_x in range(cell[0] - 1, cell[0] + 2):
            for nearby_y in range(cell[1] - 1, cell[1] + 2):
                for other in grid.get((nearby_x, nearby_y), []):
                    if planar_distance(event.point, events[other].point) <= radius_km:
                        union.union(index, other)
        grid[cell].append(index)

    members: dict[int, list[int]] = defaultdict(list)
    for index in range(len(events)):
        members[union.find(index)].append(index)
    roots = sorted(members, key=lambda root: (
        sum(events[i].point[1] for i in members[root]) / len(members[root]),
        sum(events[i].point[0] for i in members[root]) / len(members[root]),
    ))
    root_to_node = {root: node for node, root in enumerate(roots)}
    coordinates = {}
    for root, node in root_to_node.items():
        coordinates[node] = (
            sum(events[i].point[0] for i in members[root]) / len(members[root]),
            sum(events[i].point[1] for i in members[root]) / len(members[root]),
        )
    event_nodes = {index: root_to_node[union.find(index)] for index in range(len(events))}
    return coordinates, event_nodes


def geometry_between(feature: Feature, first: Event, second: Event) -> list[tuple[float, float]]:
    result = [first.point]
    for index in range(first.segment + 1, second.segment + 1):
        result.append(feature.geometry[index])
    result.append(second.point)
    deduplicated = [result[0]]
    for point in result[1:]:
        if planar_distance(point, deduplicated[-1]) > 0.001:
            deduplicated.append(point)
    return deduplicated


def construct_edges(features: list[Feature], events: list[Event]):
    coordinates, event_nodes = cluster_events(events)
    by_feature: dict[int, list[tuple[int, Event]]] = defaultdict(list)
    for index, event in enumerate(events):
        by_feature[event.feature].append((index, event))

    edges = []
    for feature_index, feature in enumerate(features):
        ordered = sorted(
            by_feature[feature_index],
            key=lambda pair: (pair[1].segment + pair[1].fraction, pair[0]),
        )
        canonical = []
        for index, event in ordered:
            node = event_nodes[index]
            position = event.segment + event.fraction
            if canonical and (node == canonical[-1][2] or abs(position - canonical[-1][3]) < 1e-8):
                continue
            canonical.append((index, event, node, position))
        for left, right in zip(canonical, canonical[1:]):
            _, first, start_node, _ = left
            _, second, end_node, _ = right
            if start_node == end_node:
                continue
            geometry = geometry_between(feature, first, second)
            geometry[0] = coordinates[start_node]
            geometry[-1] = coordinates[end_node]
            if geometry_distance(geometry) > 0.05:
                edges.append(Edge(start_node, end_node, feature.highway, geometry))
    return coordinates, merge_parallel_edges(edges)


def highway_sort_key(value: str):
    match = re.match(r"I-(\d+)(.*)", value)
    return (int(match.group(1)), match.group(2)) if match else (9999, value)


def merge_parallel_edges(edges: list[Edge]) -> list[Edge]:
    groups: dict[tuple[int, int], list[Edge]] = defaultdict(list)
    for edge in edges:
        groups[tuple(sorted((edge.start, edge.end)))].append(edge)
    result = []
    for key, candidates in groups.items():
        chosen = min(candidates, key=lambda edge: geometry_distance(edge.geometry))
        labels = sorted(
            {label for edge in candidates for label in edge.highway.split(" / ")},
            key=highway_sort_key,
        )
        geometry = chosen.geometry if chosen.start == key[0] else list(reversed(chosen.geometry))
        result.append(Edge(key[0], key[1], " / ".join(labels), geometry))
    return result


def largest_component(edges: list[Edge]) -> set[int]:
    adjacency: dict[int, set[int]] = defaultdict(set)
    for edge in edges:
        adjacency[edge.start].add(edge.end)
        adjacency[edge.end].add(edge.start)
    best: set[int] = set()
    remaining = set(adjacency)
    while remaining:
        origin = min(remaining)
        component = {origin}
        queue = deque([origin])
        while queue:
            node = queue.popleft()
            for neighbor in adjacency[node]:
                if neighbor not in component:
                    component.add(neighbor)
                    queue.append(neighbor)
        remaining -= component
        if len(component) > len(best):
            best = component
    return best


def oriented(edge: Edge, node: int) -> tuple[list[tuple[float, float]], int]:
    if edge.start == node:
        return edge.geometry, edge.end
    return list(reversed(edge.geometry)), edge.start


def collapse_degree_two(edges: list[Edge]) -> list[Edge]:
    adjacency: dict[int, list[int]] = defaultdict(list)
    for index, edge in enumerate(edges):
        adjacency[edge.start].append(index)
        adjacency[edge.end].append(index)
    anchors = {
        node for node, edge_ids in adjacency.items()
        if len(edge_ids) != 2 or edges[edge_ids[0]].highway != edges[edge_ids[1]].highway
    }
    visited: set[int] = set()
    result = []
    for start in sorted(anchors):
        for first_edge_id in sorted(adjacency[start]):
            if first_edge_id in visited:
                continue
            highway = edges[first_edge_id].highway
            geometry, current = oriented(edges[first_edge_id], start)
            visited.add(first_edge_id)
            while current not in anchors:
                next_ids = [edge_id for edge_id in adjacency[current] if edge_id not in visited]
                if not next_ids:
                    break
                next_edge_id = min(next_ids)
                if edges[next_edge_id].highway != highway:
                    break
                addition, next_node = oriented(edges[next_edge_id], current)
                geometry.extend(addition[1:])
                visited.add(next_edge_id)
                current = next_node
            if start != current:
                result.append(Edge(start, current, highway, geometry))
    for edge_id, edge in enumerate(edges):
        if edge_id not in visited:
            result.append(edge)
    return merge_parallel_edges(result)


def load_city_coordinates(source_dir: Path) -> dict[str, tuple[float, float]]:
    path = source_dir / "gazetteer" / "2025_Gaz_place_national.txt"
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="|"))
    coordinates = {}
    for city in CITY_SPECS:
        matches = [row for row in rows if row["USPS"] == city.state and row["NAME"] == city.place_name]
        if len(matches) != 1:
            raise ValueError(f"Expected one Gazetteer row for {city.name}, found {len(matches)}")
        row = matches[0]
        coordinates[city.slug] = city.coordinate_override or (
            float(row["INTPTLONG"]),
            float(row["INTPTLAT"]),
        )
    return coordinates


def nearest_edge(point: tuple[float, float], edges: list[Edge]):
    best = None
    for edge_index, edge in enumerate(edges):
        for segment_index, (start, end) in enumerate(zip(edge.geometry, edge.geometry[1:])):
            distance, closest, fraction = closest_point_on_segment(point, start, end)
            candidate = (distance, edge_index, segment_index, fraction, closest)
            if best is None or candidate < best:
                best = candidate
    if best is None:
        raise ValueError("Cannot attach city to an empty road graph")
    return best


def attach_cities(
    coordinates: dict[int, tuple[float, float]],
    edges: list[Edge],
    city_coordinates: dict[str, tuple[float, float]],
):
    city_nodes = {}
    next_node = max(coordinates, default=-1) + 1
    for city in CITY_SPECS:
        point = city_coordinates[city.slug]
        distance, edge_index, segment_index, fraction, attachment = nearest_edge(point, edges)
        edge = edges.pop(edge_index)
        if planar_distance(attachment, coordinates[edge.start]) <= 0.25:
            attachment_node = edge.start
            edges.append(edge)
        elif planar_distance(attachment, coordinates[edge.end]) <= 0.25:
            attachment_node = edge.end
            edges.append(edge)
        else:
            attachment_node = next_node
            next_node += 1
            coordinates[attachment_node] = attachment
            first_geometry = edge.geometry[: segment_index + 1] + [attachment]
            second_geometry = [attachment] + edge.geometry[segment_index + 1 :]
            first_geometry[0] = coordinates[edge.start]
            second_geometry[-1] = coordinates[edge.end]
            edges.append(Edge(edge.start, attachment_node, edge.highway, first_geometry))
            edges.append(Edge(attachment_node, edge.end, edge.highway, second_geometry))

        city_node = next_node
        next_node += 1
        coordinates[city_node] = point
        city_nodes[city.slug] = city_node
        connector_geometry = [point, coordinates[attachment_node]]
        if distance < 0.05:
            # Preserve a positive canonical edge without visually moving the city.
            lon, lat = coordinates[attachment_node]
            connector_geometry = [point, (lon + 0.0005, lat), coordinates[attachment_node]]
        edges.append(Edge(city_node, attachment_node, "City access", connector_geometry))
    return city_nodes, edges


def rounded_coordinate(point: tuple[float, float]) -> dict[str, float]:
    return {"latitude": round(point[1], 6), "longitude": round(point[0], 6)}


def serialize_catalog(
    coordinates: dict[int, tuple[float, float]],
    edges: list[Edge],
    city_nodes: dict[str, int],
    city_coordinates: dict[str, tuple[float, float]],
):
    city_node_values = set(city_nodes.values())
    junction_values = sorted(
        (node for node in coordinates if node not in city_node_values),
        key=lambda node: (coordinates[node][1], coordinates[node][0]),
    )
    node_ids = {node: f"us_junction_{index:04d}" for index, node in enumerate(junction_values, 1)}
    for slug, node in city_nodes.items():
        node_ids[node] = f"us_city_{slug}"

    cities = []
    nodes = []
    for city in CITY_SPECS:
        lon, lat = city_coordinates[city.slug]
        city_id = f"us_{city.slug}"
        node_id = node_ids[city_nodes[city.slug]]
        rail, air, sea = CITY_ACCESS[city.slug]
        cities.append({
            "id": city_id,
            "name": city.name,
            "country": "USA",
            "latitude": round(lat, 6),
            "longitude": round(lon, 6),
            "roadNodeID": node_id,
            "population": city.population,
            "hasRailFreightAccess": rail,
            "hasAirCargoAccess": air,
            "hasSeaPortAccess": sea,
            "costIndex": city.cost_index,
            "trafficDelayIndex": city.traffic_index,
            "isStarterCity": city.starter,
        })
        nodes.append({
            "id": node_id,
            "coordinate": rounded_coordinate(coordinates[city_nodes[city.slug]]),
            "kind": "city",
            "cityID": city_id,
        })
    for node in junction_values:
        nodes.append({
            "id": node_ids[node],
            "coordinate": rounded_coordinate(coordinates[node]),
            "kind": "junction",
            "cityID": None,
        })

    canonical_edges = []
    for edge in edges:
        start_node = edge.start
        end_node = edge.end
        start_id = node_ids[start_node]
        end_id = node_ids[end_node]
        geometry = edge.geometry
        if start_id > end_id:
            start_node, end_node = end_node, start_node
            start_id, end_id = end_id, start_id
            geometry = list(reversed(geometry))
        geometry[0] = coordinates[start_node]
        geometry[-1] = coordinates[end_node]
        canonical_edges.append((edge.highway, start_id, end_id, geometry))
    canonical_edges.sort(key=lambda item: (highway_sort_key(item[0].split(" / ")[0]), item[1], item[2]))
    roads = []
    for index, (highway, start_id, end_id, geometry) in enumerate(canonical_edges, 1):
        roads.append({
            "id": f"us_road_{index:05d}",
            "from": start_id,
            "to": end_id,
            "distanceKm": round(max(0.001, geometry_distance(geometry)), 3),
        })
    markets = [{"cityID": f"us_{city.slug}", "supply": [], "demand": []} for city in CITY_SPECS]
    return cities, nodes, roads, markets


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()

    features = load_features(arguments.source_dir)
    events = find_events(features)
    coordinates, edges = construct_edges(features, events)
    component = largest_component(edges)
    coordinates = {node: point for node, point in coordinates.items() if node in component}
    edges = [edge for edge in edges if edge.start in component and edge.end in component]
    edges = collapse_degree_two(edges)

    city_coordinates = load_city_coordinates(arguments.source_dir)
    city_nodes, edges = attach_cities(coordinates, edges, city_coordinates)
    connector_distances = [
        geometry_distance(edge.geometry)
        for edge in edges
        if edge.highway == "City access"
    ]
    used_nodes = {node for edge in edges for node in (edge.start, edge.end)} | set(city_nodes.values())
    coordinates = {node: point for node, point in coordinates.items() if node in used_nodes}
    cities, nodes, roads, markets = serialize_catalog(coordinates, edges, city_nodes, city_coordinates)

    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    write_json(arguments.output_dir / "cities.json", cities)
    write_json(arguments.output_dir / "city_markets.json", markets)
    # road_nodes.json / roads.json are no longer written here: the shipped
    # network is the authored trade-corridor graph from
    # generate_trade_network.py. The TIGER graph would overwrite it.
    _ = (nodes, roads)

    print(
        f"Generated {len(cities)} cities, {len(nodes)} road nodes and {len(roads)} road edges "
        f"from {len(features)} Interstate centreline features. "
        f"Longest city access: {max(connector_distances):.1f} km."
    )


if __name__ == "__main__":
    main()
