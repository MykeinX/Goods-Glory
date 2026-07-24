#!/usr/bin/env python3
"""Build map_board_silhouette.json: the flat-icon game board silhouette.

The board is drawn the way the reference art is drawn, not the way an atlas
is drawn. Natural Earth land is rasterized onto a coarse square grid in
projected board space, then the cell outline is traced back into polygons and
staircase steps are cut into 45-degree diagonals. The result is the long
straight edges, clean diagonals and uniform visual rhythm of a designed
sticker map — SpriteKit only rounds the corners with one small fixed radius.

Hand-authored sea lanes keep narrow straits (Dover, Gibraltar, Oresund,
Bosphorus...) open where the grid would seal them, and every catalog city's
cell is pinned to land so no port ever drowns in the stylization.

Country borders are not produced: the board is a game, not an atlas.

Usage: python3 -B scripts/generate_world_geography.py
"""

from __future__ import annotations

import argparse
import json
import math
import re
import urllib.request
from pathlib import Path

# Natural Earth 50m land GeoJSON mirror. 50m keeps small-but-visible islands
# (Britain's neighbours, the Aegean, Japan) that 110m simply deletes.
LAND_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_land.geojson"
)

# Must match MapProjection.verticalBoardScale.
BOARD_VERTICAL_SCALE = 1.274

# Grid cell in board units (longitude degrees; latitude is pre-scaled by
# BOARD_VERTICAL_SCALE, so a one-cell diagonal renders at exactly 45 degrees
# in game). 1.25 divides 180, keeping the antimeridian cut on the grid.
CELL = 1.25

# Antarctica is not part of the game board.
ANTARCTICA_MAX_LAT = -55.0

# Grid domain. Longitude extends past +180 for the stitched NE-Asia dateline
# wraps; latitude spans the drawn world with a two-cell water margin.
LON_MIN, LON_MAX = -180.0, 200.0
LAT_MIN, LAT_MAX = -58.0, 84.0

# Island policy: only continental land, city-bearing land and the authored
# keep-list below survive. Small Pacific, Caribbean and coastal islands are
# visual noise on a game board, not geography the player trades across.
CONTINENT_MIN_CELLS = 30
KEEP_ISLAND_SEEDS: dict[str, tuple[float, float]] = {
    "greenland": (72.0, -40.0),
    "ireland": (53.3, -8.0),
    "great_britain": (53.0, -1.5),
    "japan_honshu": (36.5, 138.0),
    "japan_hokkaido": (43.2, 142.8),
    "japan_kyushu": (32.8, 131.0),
    "sumatra": (-0.6, 101.5),
    "java": (-7.3, 110.0),
    "borneo": (0.5, 114.0),
    "sulawesi": (-2.0, 120.5),
    "new_guinea": (-5.5, 141.0),
    "madagascar": (-19.5, 46.5),
    "new_zealand_north": (-38.5, 175.5),
    "new_zealand_south": (-43.8, 171.0),
}
# Water pockets below the lake threshold are noise; the big angular inland
# seas (Black Sea, Caspian) stay as readable holes in the land.
MAX_LAKE_CELLS = 15

# Coast calm-down. One-cell bays are filled and prongs this short are shaved,
# so the traced coast is long straight runs instead of grid noise — the bold,
# quiet edges of the reference art. Trimming more eats thin peninsulas
# (Baja, Italy, Japan) that the reference keeps.
PRONG_TRIM_PASSES = 2

# Seas the grid or the coast calm-down would seal shut: narrow straits and
# the diagonal one-cell seas whose staircase cells look like dead-end bays.
# Cells near these polylines are forced to water; catalog cities are
# re-pinned to land afterwards, so Istanbul survives the Bosphorus carve.
SEA_LANES: dict[str, list[tuple[float, float]]] = {
    "english_channel": [(49.5, -3.0), (50.3, -1.0), (50.7, 1.2), (51.6, 2.6)],
    "irish_sea": [(51.8, -5.8), (53.3, -5.0), (54.8, -5.6), (55.9, -7.0)],
    "gibraltar": [(35.9, -6.5), (36.0, -5.2), (36.3, -3.5)],
    "oresund": [(57.8, 10.6), (56.5, 11.8), (55.6, 12.7), (54.6, 13.6)],
    "adriatic": [(45.0, 13.2), (43.6, 14.8), (42.0, 16.8), (40.5, 18.4)],
    "sicily_strait": [(37.6, 10.6), (37.2, 11.8), (36.6, 13.0)],
    # No Bosphorus lane on purpose: Thrace stays visibly connected to
    # Anatolia and the Black Sea reads as an enclosed angular inland sea,
    # clearly separate from the Aegean and the Mediterranean.
    "red_sea": [
        (13.5, 42.8), (16.5, 41.0), (20.0, 38.5), (24.0, 35.5), (27.5, 34.0),
    ],
    "bab_el_mandeb": [(11.8, 44.0), (12.7, 43.2), (13.8, 42.5)],
    "persian_gulf": [(24.5, 52.5), (26.0, 54.0), (26.5, 56.4), (25.9, 57.4)],
    "malacca": [(6.0, 97.5), (4.0, 99.5), (2.2, 101.8), (1.2, 103.9)],
    "gulf_of_california": [
        (23.0, -108.5), (26.0, -110.5), (29.5, -113.0), (31.0, -114.3),
    ],
}
SEA_LANE_RADIUS_CELLS = 0.75

# The land dual of the sea lanes: peninsulas thinner than a grid cell never
# rasterize (their cell centers fall in the sea), yet the board is
# unrecognizable without them. Cells near these polylines are forced to land
# before cleanup.
LAND_ANCHORS: dict[str, list[tuple[float, float]]] = {
    "italy_boot": [
        (43.8, 11.0), (42.5, 13.0), (41.5, 14.5), (40.5, 16.0),
        (39.0, 16.5), (38.2, 15.6),
    ],
    "greece": [(40.0, 21.5), (39.0, 21.8), (38.0, 22.5), (37.2, 22.3)],
    "baja_california": [
        (31.5, -116.2), (29.0, -114.3), (26.5, -112.0), (24.5, -110.5),
    ],
}
LAND_ANCHOR_RADIUS_CELLS = 0.6


def board_x(lon: float) -> float:
    return lon


def board_y(lat: float) -> float:
    return lat * BOARD_VERTICAL_SCALE


GRID_X0 = LON_MIN
GRID_Y0 = math.floor(board_y(LAT_MIN) / CELL) * CELL
GRID_NX = int(round((LON_MAX - LON_MIN) / CELL))
GRID_NY = int(math.ceil((board_y(LAT_MAX) - GRID_Y0) / CELL))


def cell_center(ix: int, iy: int) -> tuple[float, float]:
    return GRID_X0 + (ix + 0.5) * CELL, GRID_Y0 + (iy + 0.5) * CELL


# MARK: - Source geometry


def load_geojson(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        destination.write_bytes(response.read())


def ensure_source(cache_dir: Path, refresh: bool) -> Path:
    land_path = cache_dir / "ne_50m_land.geojson"
    if refresh or not land_path.exists():
        download(LAND_URL, land_path)
    return land_path


def iter_polygons(geometry: dict) -> list[list[list[tuple[float, float]]]]:
    """All polygons as ring lists (outer first, then holes), (lon, lat)."""
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    polygons: list[list[list[tuple[float, float]]]] = []
    if kind == "Polygon" and coordinates:
        polygons.append([
            [(float(lon), float(lat)) for lon, lat, *_ in ring]
            for ring in coordinates
        ])
    elif kind == "MultiPolygon":
        for polygon in coordinates or []:
            if polygon:
                polygons.append([
                    [(float(lon), float(lat)) for lon, lat, *_ in ring]
                    for ring in polygon
                ])
    return polygons


def is_antarctica_ring(points: list[tuple[float, float]]) -> bool:
    return max(lat for _, lat in points) <= ANTARCTICA_MAX_LAT


def unwrap_ring(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Make successive longitudes continuous (no ±180 jumps)."""
    if not points:
        return points
    result = [points[0]]
    for lon, lat in points[1:]:
        prev = result[-1][0]
        while lon - prev > 180.0:
            lon -= 360.0
        while lon - prev < -180.0:
            lon += 360.0
        result.append((lon, lat))
    return result


def positioned_ring(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Place a ring in the [-180, 200] board domain.

    Rings live in [-180, 180]. The NE-Asia remnants that Natural Earth cuts
    at the dateline (Chukotka) belong visually east of Siberia, so rings that
    sit hard against the far-left edge at high latitude shift east by 360.
    """
    ring = unwrap_ring(points)
    min_lon = min(lon for lon, _ in ring)
    max_lon = max(lon for lon, _ in ring)
    min_lat = min(lat for _, lat in ring)
    if max_lon <= -168.0 and min_lon <= -170.0 and min_lat >= 55.0:
        return [(lon + 360.0, lat) for lon, lat in ring]
    return ring


# MARK: - Rasterization


def fill_polygon(
    rings: list[list[tuple[float, float]]],
    land: list[list[bool]],
) -> None:
    """Even-odd scanline fill of one polygon (outer + holes) into the grid."""
    board_rings = [
        [(board_x(lon), board_y(lat)) for lon, lat in ring]
        for ring in rings
        if len(ring) >= 3
    ]
    if not board_rings:
        return
    y_low = min(y for ring in board_rings for _, y in ring)
    y_high = max(y for ring in board_rings for _, y in ring)
    iy_low = max(0, int((y_low - GRID_Y0) / CELL - 1))
    iy_high = min(GRID_NY - 1, int((y_high - GRID_Y0) / CELL + 1))

    for iy in range(iy_low, iy_high + 1):
        yc = GRID_Y0 + (iy + 0.5) * CELL
        crossings: list[float] = []
        for ring in board_rings:
            for index in range(len(ring)):
                x0, y0 = ring[index]
                x1, y1 = ring[(index + 1) % len(ring)]
                if (y0 <= yc < y1) or (y1 <= yc < y0):
                    crossings.append(x0 + (yc - y0) * (x1 - x0) / (y1 - y0))
        crossings.sort()
        for pair in range(0, len(crossings) - 1, 2):
            start, end = crossings[pair], crossings[pair + 1]
            ix_start = max(0, math.ceil((start - GRID_X0) / CELL - 0.5))
            ix_end = min(GRID_NX - 1, math.floor((end - GRID_X0) / CELL - 0.5))
            for ix in range(ix_start, ix_end + 1):
                land[iy][ix] = True


def smooth_grid(land: list[list[bool]]) -> None:
    """Coast calm-down that can never seal a through-channel.

    Dead-end notches (water with three cardinal land neighbours) are filled
    and pimples/needle tips (land with at most one cardinal land neighbour)
    are shaved. A navigable one-cell strait has land on only two sides, so
    seas and straits survive; only grid noise goes.
    """
    def count(ix: int, iy: int, offsets) -> int:
        return sum(
            1 for dx, dy in offsets
            if 0 <= iy + dy < GRID_NY and 0 <= ix + dx < GRID_NX
            and land[iy + dy][ix + dx]
        )

    cardinal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    ring8 = cardinal + [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    for _ in range(PRONG_TRIM_PASSES):
        notches = [
            (ix, iy)
            for iy in range(1, GRID_NY - 1)
            for ix in range(1, GRID_NX - 1)
            if not land[iy][ix] and count(ix, iy, cardinal) >= 3
        ]
        for ix, iy in notches:
            land[iy][ix] = True
        # The prong test uses all eight neighbours: diagonal one-cell land
        # chains (Italy, Greece, Baja) have no cardinal neighbours at all and
        # would evaporate under a four-neighbour rule.
        prongs = [
            (ix, iy)
            for iy in range(GRID_NY)
            for ix in range(GRID_NX)
            if land[iy][ix] and count(ix, iy, ring8) <= 1
        ]
        for ix, iy in prongs:
            land[iy][ix] = False


def paint_lanes(
    land: list[list[bool]],
    lanes: dict[str, list[tuple[float, float]]],
    radius_cells: float,
    value: bool,
) -> None:
    radius = radius_cells * CELL
    for lane in lanes.values():
        board = [(board_x(lon), board_y(lat)) for lat, lon in lane]
        for (x0, y0), (x1, y1) in zip(board, board[1:]):
            length = math.hypot(x1 - x0, y1 - y0)
            steps = max(1, int(length / (CELL / 2)))
            for step in range(steps + 1):
                t = step / steps
                px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                ix_center = int((px - GRID_X0) / CELL)
                iy_center = int((py - GRID_Y0) / CELL)
                reach = int(radius / CELL) + 1
                for iy in range(iy_center - reach, iy_center + reach + 1):
                    for ix in range(ix_center - reach, ix_center + reach + 1):
                        if not (0 <= iy < GRID_NY and 0 <= ix < GRID_NX):
                            continue
                        cx, cy = cell_center(ix, iy)
                        if math.hypot(cx - px, cy - py) <= radius:
                            land[iy][ix] = value


def pin_cities(land: list[list[bool]], cities: list[dict]) -> None:
    for city in cities:
        ix = int((board_x(city["longitude"]) - GRID_X0) / CELL)
        iy = int((board_y(city["latitude"]) - GRID_Y0) / CELL)
        if 0 <= iy < GRID_NY and 0 <= ix < GRID_NX:
            land[iy][ix] = True


def cleanup_components(land: list[list[bool]], cities: list[dict]) -> None:
    """Apply the island policy and fill lake noise.

    Land survives if it is continental (big), carries a catalog city, or is
    on the authored keep-list; everything else is confetti and goes.
    """
    protected_cells = set()
    for city in cities:
        ix = int((board_x(city["longitude"]) - GRID_X0) / CELL)
        iy = int((board_y(city["latitude"]) - GRID_Y0) / CELL)
        protected_cells.add((ix, iy))
    for lat, lon in KEEP_ISLAND_SEEDS.values():
        ix = int((board_x(lon) - GRID_X0) / CELL)
        iy = int((board_y(lat) - GRID_Y0) / CELL)
        protected_cells.add((ix, iy))

    def component(seed, value, visited):
        # Land connects across diagonals (thin peninsulas like Calabria are
        # diagonal cell chains); water does not, or it would leak through
        # those same chains.
        if value:
            offsets = (
                (1, 0), (-1, 0), (0, 1), (0, -1),
                (1, 1), (1, -1), (-1, 1), (-1, -1),
            )
        else:
            offsets = ((1, 0), (-1, 0), (0, 1), (0, -1))
        stack = [seed]
        cells = []
        visited.add(seed)
        while stack:
            ix, iy = stack.pop()
            cells.append((ix, iy))
            for dx, dy in offsets:
                nx, ny = ix + dx, iy + dy
                if not (0 <= ny < GRID_NY and 0 <= nx < GRID_NX):
                    continue
                if (nx, ny) in visited or land[ny][nx] != value:
                    continue
                visited.add((nx, ny))
                stack.append((nx, ny))
        return cells

    visited: set[tuple[int, int]] = set()
    for iy in range(GRID_NY):
        for ix in range(GRID_NX):
            if land[iy][ix] and (ix, iy) not in visited:
                cells = component((ix, iy), True, visited)
                keep = (
                    len(cells) >= CONTINENT_MIN_CELLS
                    or bool(set(cells) & protected_cells)
                )
                if not keep:
                    for cx, cy in cells:
                        land[cy][cx] = False

    visited = set()
    border_touching = False
    for iy in range(GRID_NY):
        for ix in range(GRID_NX):
            if not land[iy][ix] and (ix, iy) not in visited:
                cells = component((ix, iy), False, visited)
                border_touching = any(
                    cx in (0, GRID_NX - 1) or cy in (0, GRID_NY - 1)
                    for cx, cy in cells
                )
                if not border_touching and len(cells) <= MAX_LAKE_CELLS:
                    for cx, cy in cells:
                        land[cy][cx] = True


# MARK: - Contour tracing


def trace_outlines(land: list[list[bool]]) -> list[list[tuple[int, int]]]:
    """Trace directed cell-edge loops around every land region.

    Edges keep land on their left, so outer coasts wind one way and lake
    shores the other; the even-odd fill of the renderer shows both correctly.
    At checkerboard vertices the sharpest left turn is taken, so diagonally
    touching land (thin peninsulas are diagonal cell chains) stays one
    continuous outline instead of a chain of separate diamonds.
    """
    def is_land(ix: int, iy: int) -> bool:
        return 0 <= iy < GRID_NY and 0 <= ix < GRID_NX and land[iy][ix]

    # Directed boundary edges: (vertex from) -> (vertex to), land on left.
    edges: dict[tuple[int, int], list[tuple[int, int]]] = {}

    def add(a: tuple[int, int], b: tuple[int, int]) -> None:
        edges.setdefault(a, []).append(b)

    for iy in range(GRID_NY):
        for ix in range(GRID_NX):
            if not land[iy][ix]:
                continue
            if not is_land(ix, iy - 1):
                add((ix, iy), (ix + 1, iy))
            if not is_land(ix + 1, iy):
                add((ix + 1, iy), (ix + 1, iy + 1))
            if not is_land(ix, iy + 1):
                add((ix + 1, iy + 1), (ix, iy + 1))
            if not is_land(ix - 1, iy):
                add((ix, iy + 1), (ix, iy))

    loops: list[list[tuple[int, int]]] = []
    while edges:
        start = min(edges)
        loop = [start]
        current = start
        incoming = (0, 0)
        while True:
            candidates = edges.get(current)
            if not candidates:
                break
            if len(candidates) == 1 or incoming == (0, 0):
                chosen = candidates[0]
            else:
                # Sharpest left turn relative to the incoming direction.
                def turn(candidate: tuple[int, int]) -> float:
                    dx, dy = candidate[0] - current[0], candidate[1] - current[1]
                    cross = incoming[0] * dy - incoming[1] * dx
                    dot = incoming[0] * dx + incoming[1] * dy
                    return math.atan2(cross, dot)
                chosen = max(candidates, key=turn)
            candidates.remove(chosen)
            if not candidates:
                del edges[current]
            incoming = (chosen[0] - current[0], chosen[1] - current[1])
            current = chosen
            if current == start:
                break
            loop.append(current)
        if len(loop) >= 4:
            loops.append(loop)
    return loops


def cut_staircases(loop: list[tuple[int, int]]) -> list[tuple[float, float]]:
    """Turn unit staircase steps into 45-degree diagonals, then merge runs."""
    points: list[tuple[float, float]] = [(float(x), float(y)) for x, y in loop]

    changed = True
    passes = 0
    while changed and passes < 12 and len(points) > 4:
        changed = False
        passes += 1
        index = 0
        while index < len(points) and len(points) > 4:
            previous = points[index - 1]
            current = points[index]
            following = points[(index + 1) % len(points)]
            into = (current[0] - previous[0], current[1] - previous[1])
            out = (following[0] - current[0], following[1] - current[1])
            unit_in = max(abs(into[0]), abs(into[1])) <= 1.01
            unit_out = max(abs(out[0]), abs(out[1])) <= 1.01
            perpendicular = abs(into[0] * out[0] + into[1] * out[1]) < 0.01
            if unit_in and unit_out and perpendicular:
                del points[index]
                changed = True
                index += 1  # skip the next corner: cut alternately
            else:
                index += 1

    # Merge collinear runs.
    merged: list[tuple[float, float]] = []
    for point in points:
        while len(merged) >= 2:
            a, b = merged[-2], merged[-1]
            cross = (b[0] - a[0]) * (point[1] - b[1]) - (b[1] - a[1]) * (point[0] - b[0])
            dot = (b[0] - a[0]) * (point[0] - b[0]) + (b[1] - a[1]) * (point[1] - b[1])
            if abs(cross) < 1e-9 and dot > 0:
                merged.pop()
            else:
                break
        merged.append(point)
    if len(merged) >= 3:
        a, b, c = merged[-2], merged[-1], merged[0]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        dot = (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])
        if abs(cross) < 1e-9 and dot > 0:
            merged.pop()
    return merged


# MARK: - Assembly


def build_board(land_path: Path, cities: list[dict]) -> dict:
    land = [[False] * GRID_NX for _ in range(GRID_NY)]
    for feature in load_geojson(land_path).get("features", []):
        geometry = feature.get("geometry") or {}
        for polygon in iter_polygons(geometry):
            outer = polygon[0]
            if len(outer) < 3 or is_antarctica_ring(outer):
                continue
            positioned = [positioned_ring(ring) for ring in polygon]
            fill_polygon(positioned, land)

    smooth_grid(land)
    paint_lanes(land, SEA_LANES, SEA_LANE_RADIUS_CELLS, False)
    paint_lanes(land, LAND_ANCHORS, LAND_ANCHOR_RADIUS_CELLS, True)
    pin_cities(land, cities)
    cleanup_components(land, cities)

    land_masses = []
    for loop in trace_outlines(land):
        outline = cut_staircases(loop)
        if len(outline) < 3:
            continue
        points = []
        for gx, gy in outline:
            lon = GRID_X0 + gx * CELL
            lat = (GRID_Y0 + gy * CELL) / BOARD_VERTICAL_SCALE
            points.append({
                "latitude": round(lat, 6),
                "longitude": round(lon, 6),
            })
        land_masses.append(points)
    land_masses.sort(key=len, reverse=True)

    return {
        "version": 3,
        "source": (
            "Natural Earth 50m land "
            "(https://www.naturalearthdata.com/); rasterized onto a "
            f"{CELL}-degree board grid, staircase steps cut to 45-degree "
            "diagonals; authored sea lanes keep narrow straits open; "
            "catalog cities pinned to land; Antarctica omitted"
        ),
        "landMasses": [
            {"id": f"board_land_{index:03d}", "points": points}
            for index, points in enumerate(land_masses, start=1)
        ],
    }


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, indent=2, ensure_ascii=False)
    text = re.sub(
        r"\{\s*\"latitude\":\s*(-?[\d.]+),\s*\"longitude\":\s*(-?[\d.]+)\s*\}",
        r'{ "latitude": \1, "longitude": \2 }',
        text,
    )
    path.write_text(text + "\n", encoding="utf-8")


def main() -> None:
    repo_scripts = Path(__file__).resolve().parent
    catalog_dir = repo_scripts.parent / "Goods&Glory" / "Resources" / "Catalog"

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=repo_scripts / ".cache" / "natural_earth",
        help="Directory for downloaded Natural Earth GeoJSON files",
    )
    parser.add_argument(
        "--board-output",
        type=Path,
        default=catalog_dir / "map_board_silhouette.json",
        help="Destination map_board_silhouette.json path",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Re-download Natural Earth sources even if cached",
    )
    arguments = parser.parse_args()

    cities = json.loads((catalog_dir / "cities.json").read_text(encoding="utf-8"))
    land_path = ensure_source(arguments.cache_dir, arguments.refresh)
    board = build_board(land_path, cities)
    write_json(arguments.board_output, board)

    land_points = sum(len(item["points"]) for item in board["landMasses"])
    print(
        f"Wrote {arguments.board_output}\n"
        f"  landMasses={len(board['landMasses'])} ({land_points} points)\n"
        f"  size={arguments.board_output.stat().st_size / 1024.0:.1f} KB"
    )


if __name__ == "__main__":
    main()
