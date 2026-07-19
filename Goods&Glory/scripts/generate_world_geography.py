#!/usr/bin/env python3
"""Build bundled world land/inland-water silhouettes for the strategic map.

Downloads Natural Earth physical land + lakes and admin-0 land boundary lines
at 50m, drops Antarctica, splits antimeridian-crossing geometry,
simplifies to a strategic tolerance, and writes map_geography.json.

No cities or roads are produced.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import urllib.request
from pathlib import Path

# Natural Earth vector GeoJSON mirrors.
# 50m land + lakes, matching the boundary resolution.
#
# This used to be 110m, and it made map detail regionally uneven in a way that
# looked like a bug in our pipeline but was really the source data: 110m keeps
# smooth coastlines faithfully and deletes intricate ones. Measured over equal
# windows, the US mainland carried 849 land vertices and six lakes while the
# Turkish Aegean carried 21 vertices and no islands at all — the whole
# archipelago is simply absent at 110m. Borders were already 50m, so land was
# the odd one out.
LAND_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_land.geojson"
)
LAKES_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_lakes.geojson"
)
# 50m land boundaries: accurate enough for customs/borders without 10m weight.
BOUNDARIES_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_0_boundary_lines_land.geojson"
)

KM_PER_LATITUDE_DEGREE = 111.32
# Mid-latitude approximation is fine for strategic simplification.
KM_PER_LONGITUDE_DEGREE = 85.0
ANTARCTICA_MAX_LAT = -55.0
# Minimum footprint for a drawn landform or lake. Below this a shape is a
# speck at strategic zoom: invisible, but it still makes the map read like a
# navigation app instead of a game board. At 50m the source ships over a
# thousand land rings and most of them are exactly that.
#
# 8,000 km² keeps every landform a player would name — Britain, Ireland,
# Sicily, Sardinia, Corsica, Crete, Cyprus, Japan, Sri Lanka, the Great Lakes —
# and deletes the confetti. The Aegean goes from 35 shapes to 2.
MIN_LAND_BBOX_AREA = 0.95  # deg² ≈ 8,000 km² at mid latitudes
MIN_LAKE_BBOX_AREA = 0.95  # deg², same rule for inland water

# Coastline smoothing, deliberately far coarser than cartographic practice.
#
# The budget is anchored to the original 110m build, whose level of coastal
# detail was the one the team liked: ~4,000 land vertices for the world. The
# problem with 110m was never that it was coarse, it was that the coarseness
# was uneven — smooth coasts survived and intricate ones were deleted outright,
# so Turkey got 21 vertices where the US got 849. Taking the finer 50m source
# and flattening it hard reaches the same budget with the detail spread evenly.
#
# A bay narrower than ~35 km is not something a player acts on. Route arcs do
# not depend on the shoreline at all — they follow the road graph — so
# coarsening here cannot make a truck look lost.
SIMPLIFY_TOLERANCE_KM = 35.0
# Borders were two thirds of every vertex in the file at 2 km, which bought
# precision no one can see on a strategic map. A country still reads as itself
# at 20 km — the silhouette is intact, only surveyed wiggle is gone.
BOUNDARY_SIMPLIFY_TOLERANCE_KM = 20.0
MIN_RING_POINTS = 4  # closed ring with ≥3 unique vertices
MIN_BOUNDARY_POINTS = 2


def planar(point: tuple[float, float]) -> tuple[float, float]:
    return point[0] * KM_PER_LONGITUDE_DEGREE, point[1] * KM_PER_LATITUDE_DEGREE


def douglas_peucker(
    points: list[tuple[float, float]], tolerance_km: float
) -> list[tuple[float, float]]:
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
            fraction = max(
                0.0,
                min(1.0, ((px - first[0]) * dx + (py - first[1]) * dy) / denominator),
            )
            distance = math.hypot(
                px - (first[0] + fraction * dx),
                py - (first[1] + fraction * dy),
            )
        if distance > farthest:
            index, farthest = candidate_index, distance
    if farthest <= tolerance_km:
        return [points[0], points[-1]]
    return (
        douglas_peucker(points[: index + 1], tolerance_km)[:-1]
        + douglas_peucker(points[index:], tolerance_km)
    )


def ring_bounds(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    longitudes = [point[0] for point in points]
    latitudes = [point[1] for point in points]
    return min(longitudes), min(latitudes), max(longitudes), max(latitudes)


def bbox_area(points: list[tuple[float, float]]) -> float:
    min_lon, min_lat, max_lon, max_lat = ring_bounds(points)
    return max(0.0, max_lon - min_lon) * max(0.0, max_lat - min_lat)


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


def normalize_longitude(lon: float) -> float:
    while lon < -180.0:
        lon += 360.0
    while lon > 180.0:
        lon -= 360.0
    return lon


def split_ring_at_antimeridian(
    points: list[tuple[float, float]],
) -> list[list[tuple[float, float]]]:
    """Split only rings that actually jump across ±180°.

    Wide continents (e.g. Eurasia from -17° to +180°) must NOT be band-split —
    that destroys the Natural Earth dateline cut needed to stitch Chukotka.
    """
    if len(points) < 3:
        return []
    ring = list(points)
    if ring[0] != ring[-1]:
        ring = ring + [ring[0]]

    has_jump = any(
        abs(ring[index][0] - ring[index + 1][0]) > 180.0
        for index in range(len(ring) - 1)
    )
    if not has_jump:
        return [ring]

    unwrapped = unwrap_ring(ring)
    if unwrapped[0] != unwrapped[-1]:
        unwrapped = unwrapped + [unwrapped[0]]

    min_lon = min(lon for lon, _ in unwrapped)
    max_lon = max(lon for lon, _ in unwrapped)
    if max_lon - min_lon <= 180.0 and -180.0 <= min_lon and max_lon <= 180.0:
        return [[(normalize_longitude(lon), lat) for lon, lat in unwrapped]]

    bands: dict[int, list[tuple[float, float]]] = {}
    for lon, lat in unwrapped[:-1]:
        display = normalize_longitude(lon)
        band = int(math.floor((lon + 180.0) / 360.0))
        bands.setdefault(band, []).append((display, lat))

    rings: list[list[tuple[float, float]]] = []
    for band_points in bands.values():
        if len(band_points) < 3:
            continue
        closed = list(band_points)
        if closed[0] != closed[-1]:
            closed.append(closed[0])
        if bbox_area(closed) < 1e-4:
            continue
        rings.append(closed)

    if rings:
        return rings

    return [[(normalize_longitude(lon), lat) for lon, lat in unwrapped]]


def simplified_closed_ring(
    points: list[tuple[float, float]], tolerance_km: float
) -> list[tuple[float, float]] | None:
    if len(points) < 3:
        return None
    ring = list(points)
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return None
    simplified = douglas_peucker(ring, tolerance_km)
    if len(simplified) < 3:
        return None
    if simplified[0] != simplified[-1]:
        simplified.append(simplified[0])
    return simplified


def is_antarctica_ring(points: list[tuple[float, float]]) -> bool:
    _, min_lat, _, max_lat = ring_bounds(points)
    return max_lat <= ANTARCTICA_MAX_LAT


def iter_polygon_rings(geometry: dict) -> list[list[tuple[float, float]]]:
    """Return outer rings only as (lon, lat) lists (GeoJSON order)."""
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    rings: list[list[tuple[float, float]]] = []
    if kind == "Polygon":
        if coordinates:
            outer = coordinates[0]
            rings.append([(float(lon), float(lat)) for lon, lat, *_ in outer])
    elif kind == "MultiPolygon":
        for polygon in coordinates or []:
            if not polygon:
                continue
            outer = polygon[0]
            rings.append([(float(lon), float(lat)) for lon, lat, *_ in outer])
    return rings


def iter_polylines(geometry: dict) -> list[list[tuple[float, float]]]:
    """Return open polylines as (lon, lat) lists."""
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    lines: list[list[tuple[float, float]]] = []
    if kind == "LineString":
        if coordinates:
            lines.append([(float(lon), float(lat)) for lon, lat, *_ in coordinates])
    elif kind == "MultiLineString":
        for line in coordinates or []:
            if len(line) >= 2:
                lines.append([(float(lon), float(lat)) for lon, lat, *_ in line])
    return lines


def split_open_polyline_at_antimeridian(
    points: list[tuple[float, float]],
) -> list[list[tuple[float, float]]]:
    """Split a polyline wherever consecutive vertices jump across ±180°."""
    if len(points) < 2:
        return []
    segments: list[list[tuple[float, float]]] = []
    current: list[tuple[float, float]] = [points[0]]
    for point in points[1:]:
        prev = current[-1]
        if abs(point[0] - prev[0]) > 180.0:
            if len(current) >= 2:
                segments.append(current)
            current = [point]
        else:
            current.append(point)
    if len(current) >= 2:
        segments.append(current)
    return segments


def simplified_open_polyline(
    points: list[tuple[float, float]], tolerance_km: float
) -> list[tuple[float, float]] | None:
    if len(points) < 2:
        return None
    simplified = douglas_peucker(points, tolerance_km)
    if len(simplified) < 2:
        return None
    return simplified


def load_geojson(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        destination.write_bytes(response.read())


def ensure_sources(cache_dir: Path, refresh: bool) -> tuple[Path, Path, Path]:
    # Filenames must track the URLs. When these still said 110m after the
    # sources moved to 50m, an existing cache silently satisfied the download
    # check and the script kept rebuilding from the old, coarser data.
    land_path = cache_dir / "ne_50m_land.geojson"
    lakes_path = cache_dir / "ne_50m_lakes.geojson"
    boundaries_path = cache_dir / "ne_50m_admin_0_boundary_lines_land.geojson"
    if refresh or not land_path.exists():
        download(LAND_URL, land_path)
    if refresh or not lakes_path.exists():
        download(LAKES_URL, lakes_path)
    if refresh or not boundaries_path.exists():
        download(BOUNDARIES_URL, boundaries_path)
    return land_path, lakes_path, boundaries_path


def process_land(geojson: dict) -> list[list[tuple[float, float]]]:
    rings: list[list[tuple[float, float]]] = []
    for feature in geojson.get("features", []):
        geometry = feature.get("geometry") or {}
        for outer in iter_polygon_rings(geometry):
            if len(outer) < 3:
                continue
            if is_antarctica_ring(outer):
                continue
            for piece in split_ring_at_antimeridian(outer):
                if is_antarctica_ring(piece):
                    continue
                if len(_open_ring(piece)) < 3:
                    continue
                rings.append(piece if piece[0] == piece[-1] else piece + [piece[0]])
    # Stitch NE Asia dateline wraps before DP so ±180 cut vertices survive.
    rings = merge_dateline_wraps_into_land(rings)
    simplified_rings: list[list[tuple[float, float]]] = []
    for ring in rings:
        if bbox_area(ring) < MIN_LAND_BBOX_AREA:
            continue
        simplified = simplified_closed_ring(ring, SIMPLIFY_TOLERANCE_KM)
        if simplified is None or len(simplified) < MIN_RING_POINTS:
            continue
        if is_antarctica_ring(simplified):
            continue
        simplified_rings.append(simplified)
    simplified_rings.sort(key=bbox_area, reverse=True)
    return simplified_rings


def process_lakes(geojson: dict) -> list[list[tuple[float, float]]]:
    rings: list[list[tuple[float, float]]] = []
    for feature in geojson.get("features", []):
        geometry = feature.get("geometry") or {}
        props = feature.get("properties") or {}
        name = str(props.get("name") or props.get("NAME") or "").lower()
        for outer in iter_polygon_rings(geometry):
            if len(outer) < 3:
                continue
            if is_antarctica_ring(outer):
                continue
            if "antar" in name:
                continue
            if bbox_area(outer) < MIN_LAKE_BBOX_AREA:
                continue
            for piece in split_ring_at_antimeridian(outer):
                if bbox_area(piece) < MIN_LAKE_BBOX_AREA:
                    continue
                simplified = simplified_closed_ring(piece, SIMPLIFY_TOLERANCE_KM)
                if simplified is None or len(simplified) < MIN_RING_POINTS:
                    continue
                rings.append(simplified)
    rings.sort(key=bbox_area, reverse=True)
    return rings


def process_boundaries(geojson: dict) -> list[list[tuple[float, float]]]:
    """International land borders (open polylines), Antarctica omitted."""
    lines: list[list[tuple[float, float]]] = []
    for feature in geojson.get("features", []):
        props = feature.get("properties") or {}
        name = str(props.get("name") or props.get("NAME") or "").lower()
        if "antar" in name:
            continue
        geometry = feature.get("geometry") or {}
        for line in iter_polylines(geometry):
            if len(line) < 2:
                continue
            if is_antarctica_ring(line):
                continue
            for piece in split_open_polyline_at_antimeridian(line):
                if len(piece) < 2 or is_antarctica_ring(piece):
                    continue
                simplified = simplified_open_polyline(
                    piece, BOUNDARY_SIMPLIFY_TOLERANCE_KM
                )
                if simplified is None or len(simplified) < MIN_BOUNDARY_POINTS:
                    continue
                lines.append(simplified)
    lines.sort(key=lambda pts: -len(pts))
    return lines


def is_east_asia_dateline_wrap(points: list[tuple[float, float]]) -> bool:
    """True for Chukotka-style remnants that appear on the far-left after ±180 split.

    Those belong east of Asia. Alaska / Canada stay put (further east than ~-168°
    or lower latitude).
    """
    min_lon, min_lat, max_lon, max_lat = ring_bounds(points)
    if min_lat < 55.0:
        return False
    if max_lon > -168.0:
        return False
    return min_lon <= -170.0


def _open_ring(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    ring = list(points)
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    return ring


def _on_dateline(lon: float, eps: float = 0.05) -> bool:
    return abs(abs(lon) - 180.0) <= eps


def _find_dateline_cut(
    ring: list[tuple[float, float]],
) -> tuple[int, tuple[float, float], tuple[float, float]] | None:
    """Index i where ring[i]→ring[i+1] is the artificial ±180 cut (lat span)."""
    r = _open_ring(ring)
    n = len(r)
    if n < 3:
        return None
    best = None
    for i in range(n):
        a = r[i]
        b = r[(i + 1) % n]
        if not (_on_dateline(a[0]) and _on_dateline(b[0])):
            continue
        lat_span = abs(a[1] - b[1])
        if lat_span < 0.4:
            continue
        if best is None or lat_span > best[0]:
            best = (lat_span, i, a, b)
    if best is None:
        return None
    _, index, a, b = best
    return index, a, b


def _shift_lon_east(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Move western dateline remnant into lon > 180."""
    return [(lon + 360.0 if lon < 0.0 else lon, lat) for lon, lat in points]


def _exterior_path_from_cut(
    ring: list[tuple[float, float]], cut_index: int
) -> list[tuple[float, float]]:
    """Vertices from cut end → around exterior → cut start (inclusive)."""
    r = _open_ring(ring)
    n = len(r)
    start = (cut_index + 1) % n
    end = cut_index
    path = [r[start]]
    j = (start + 1) % n
    while j != end:
        path.append(r[j])
        j = (j + 1) % n
    path.append(r[end])
    return path


def try_stitch_wrap_into_host(
    host: list[tuple[float, float]],
    wrap: list[tuple[float, float]],
) -> list[tuple[float, float]] | None:
    """Replace host's ±180 cut with wrap's eastern coastline (lon shifted +360)."""
    host_cut = _find_dateline_cut(host)
    wrap_cut = _find_dateline_cut(wrap)
    if host_cut is None or wrap_cut is None:
        return None
    host_i, host_a, host_b = host_cut
    wrap_i, wrap_a, wrap_b = wrap_cut

    # Host cut host_a→host_b should match wrap cut endpoints (same latitudes).
    host_lats = sorted((host_a[1], host_b[1]))
    wrap_lats = sorted((wrap_a[1], wrap_b[1]))
    if abs(host_lats[0] - wrap_lats[0]) > 0.15 or abs(host_lats[1] - wrap_lats[1]) > 0.15:
        return None

    exterior = _exterior_path_from_cut(wrap, wrap_i)
    # exterior starts at wrap_b and ends at wrap_a (cut direction wrap_a→wrap_b).
    # Host wants path host_a→host_b. Align orientation.
    exterior_shifted = _shift_lon_east(exterior)

    def lat_key(point: tuple[float, float]) -> float:
        return point[1]

    start_lat, end_lat = host_a[1], host_b[1]
    if abs(exterior_shifted[0][1] - start_lat) > abs(exterior_shifted[-1][1] - start_lat):
        exterior_shifted = list(reversed(exterior_shifted))
    # Snap endpoints exactly onto the host cut vertices.
    exterior_shifted[0] = (max(exterior_shifted[0][0], 180.0), start_lat)
    exterior_shifted[-1] = (max(exterior_shifted[-1][0], 180.0), end_lat)
    # Prefer host cut longitudes (typically +180).
    exterior_shifted[0] = (host_a[0] if host_a[0] >= 180.0 else 180.0, start_lat)
    exterior_shifted[-1] = (host_b[0] if host_b[0] >= 180.0 else 180.0, end_lat)

    host_open = _open_ring(host)
    n = len(host_open)
    # host_open[host_i]=host_a, host_open[host_i+1]=host_b
    mid = exterior_shifted[1:-1]
    merged = (
        host_open[: host_i + 1]
        + mid
        + host_open[host_i + 1 :]
    )
    if merged[0] != merged[-1]:
        merged.append(merged[0])
    return merged


def merge_dateline_wraps_into_land(
    rings: list[list[tuple[float, float]]],
) -> list[list[tuple[float, float]]]:
    """Stitch NE Asia dateline remnants into the Eurasian ring (no seam)."""
    wraps = [r for r in rings if is_east_asia_dateline_wrap(r)]
    others = [r for r in rings if not is_east_asia_dateline_wrap(r)]
    if not wraps:
        return rings

    # Primary host: largest ring that reaches the dateline from the west/Asia side.
    host_index = None
    host_area = -1.0
    for index, ring in enumerate(others):
        min_lon, min_lat, max_lon, max_lat = ring_bounds(ring)
        if max_lon < 179.5 or max_lat < 60.0:
            continue
        area = bbox_area(ring)
        if area > host_area:
            host_area = area
            host_index = index

    consumed: set[int] = set()
    if host_index is not None:
        host = others[host_index]
        for wrap_index, wrap in enumerate(wraps):
            stitched = try_stitch_wrap_into_host(host, wrap)
            if stitched is None:
                continue
            host = stitched
            consumed.add(wrap_index)
        others[host_index] = host

    # Leftover wraps: try eastern island halves (e.g. Wrangel), else shift only.
    for wrap_index, wrap in enumerate(wraps):
        if wrap_index in consumed:
            continue
        merged = False
        for index, ring in enumerate(others):
            min_lon, min_lat, max_lon, max_lat = ring_bounds(ring)
            if max_lon < 178.0 or min_lon < 100.0 or min_lat < 55.0:
                continue
            stitched = try_stitch_wrap_into_host(ring, wrap)
            if stitched is None:
                continue
            others[index] = stitched
            merged = True
            break
        if not merged:
            others.append(_shift_lon_east(wrap))

    others.sort(key=bbox_area, reverse=True)
    return others


def shift_dateline_wraps_east(
    geometries: list[list[tuple[float, float]]],
) -> list[list[tuple[float, float]]]:
    """Shift (don't stitch) — used for open border polylines."""
    shifted: list[list[tuple[float, float]]] = []
    for points in geometries:
        if is_east_asia_dateline_wrap(points):
            shifted.append(_shift_lon_east(points))
        else:
            shifted.append(points)
    return shifted


def rounded_coordinate(point: tuple[float, float]) -> dict[str, float]:
    return {"latitude": round(point[1], 6), "longitude": round(point[0], 6)}


def build_geography(
    land_path: Path, lakes_path: Path, boundaries_path: Path
) -> dict:
    land_rings = process_land(load_geojson(land_path))
    lake_rings = process_lakes(load_geojson(lakes_path))
    boundary_lines = shift_dateline_wraps_east(
        process_boundaries(load_geojson(boundaries_path))
    )
    return {
        "version": 3,
        "source": (
            "Natural Earth 50m land + lakes + admin-0 land boundary lines "
            "(https://www.naturalearthdata.com/); Antarctica omitted; "
            "NE Asia dateline wraps stitched into Eurasia (lon>180); "
            f"land simplify ~{SIMPLIFY_TOLERANCE_KM:.0f} km, "
            f"borders ~{BOUNDARY_SIMPLIFY_TOLERANCE_KM:.0f} km"
        ),
        "landMasses": [
            {
                "id": f"world_land_{index:03d}",
                "points": [rounded_coordinate(point) for point in ring],
            }
            for index, ring in enumerate(land_rings, 1)
        ],
        "waterBodies": [
            {
                "id": f"world_lake_{index:03d}",
                "points": [rounded_coordinate(point) for point in ring],
            }
            for index, ring in enumerate(lake_rings, 1)
        ],
        "boundaries": [
            {
                "id": f"world_border_{index:04d}",
                "points": [rounded_coordinate(point) for point in line],
            }
            for index, line in enumerate(boundary_lines, 1)
        ],
    }


def write_json(path: Path, value: dict) -> None:
    """Indented JSON, except that each coordinate stays on one line.

    Fully indented, one coordinate spans four lines, so a regenerated world is
    a ~90,000 line diff nobody can review. Collapsing just the innermost
    `{latitude, longitude}` objects cuts that by three quarters and loses
    nothing: the file is still ordinary, readable JSON and the Swift decoder
    never sees the difference.
    """
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
    default_output = (
        repo_scripts.parent / "Goods&Glory" / "Resources" / "Catalog" / "map_geography.json"
    )
    default_cache = repo_scripts / ".cache" / "natural_earth"

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=default_cache,
        help="Directory for downloaded Natural Earth GeoJSON files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=default_output,
        help="Destination map_geography.json path",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Re-download Natural Earth sources even if cached",
    )
    arguments = parser.parse_args()

    land_path, lakes_path, boundaries_path = ensure_sources(
        arguments.cache_dir, arguments.refresh
    )
    geography = build_geography(land_path, lakes_path, boundaries_path)
    write_json(arguments.output, geography)

    land_points = sum(len(item["points"]) for item in geography["landMasses"])
    lake_points = sum(len(item["points"]) for item in geography["waterBodies"])
    border_points = sum(len(item["points"]) for item in geography["boundaries"])
    size_kb = arguments.output.stat().st_size / 1024.0
    print(
        f"Wrote {arguments.output}\n"
        f"  landMasses={len(geography['landMasses'])} ({land_points} points)\n"
        f"  waterBodies={len(geography['waterBodies'])} ({lake_points} points)\n"
        f"  boundaries={len(geography['boundaries'])} ({border_points} points)\n"
        f"  size={size_kb:.1f} KB"
    )


if __name__ == "__main__":
    main()
