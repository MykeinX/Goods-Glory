#!/usr/bin/env python3
"""Build bundled world land/inland-water silhouettes for the strategic map.

Downloads Natural Earth physical land + lakes (110m) and admin-0 land boundary
lines (50m) GeoJSON, drops Antarctica, splits antimeridian-crossing geometry,
simplifies to a strategic tolerance, and writes map_geography.json.

No cities or roads are produced.
"""

from __future__ import annotations

import argparse
import json
import math
import urllib.request
from pathlib import Path

# Natural Earth vector GeoJSON mirrors.
LAND_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_110m_land.geojson"
)
LAKES_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_110m_lakes.geojson"
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
# Drop tiny lake blobs; keep Great Lakes, Caspian, Baikal-scale features.
MIN_LAKE_BBOX_AREA = 0.35  # deg²
SIMPLIFY_TOLERANCE_KM = 6.0
# Tighter than land silhouettes so border shapes stay close to reality.
BOUNDARY_SIMPLIFY_TOLERANCE_KM = 2.0
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
    """Split an unwrapped ring into closed rings in [-180, 180]."""
    if len(points) < 3:
        return []
    unwrapped = unwrap_ring(points)
    if unwrapped[0] != unwrapped[-1]:
        unwrapped = unwrapped + [unwrapped[0]]

    min_lon = min(lon for lon, _ in unwrapped)
    max_lon = max(lon for lon, _ in unwrapped)
    if max_lon - min_lon <= 180.0 and -180.0 <= min_lon and max_lon <= 180.0:
        return [[(normalize_longitude(lon), lat) for lon, lat in unwrapped]]

    # Group vertices by 360° band, then normalize each piece into [-180, 180].
    # Natural Earth 110m rarely needs this; Russia/Fiji-style spans are covered.
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
    land_path = cache_dir / "ne_110m_land.geojson"
    lakes_path = cache_dir / "ne_110m_lakes.geojson"
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
                simplified = simplified_closed_ring(piece, SIMPLIFY_TOLERANCE_KM)
                if simplified is None or len(simplified) < MIN_RING_POINTS:
                    continue
                if is_antarctica_ring(simplified):
                    continue
                rings.append(simplified)
    rings.sort(key=bbox_area, reverse=True)
    return rings


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

    Those belong east of Asia: shift them by +360° so Siberia completes on the
    right. Alaska / Canada stay put (further east than ~-168° or lower latitude).
    """
    min_lon, min_lat, max_lon, max_lat = ring_bounds(points)
    if min_lat < 55.0:
        return False
    if max_lon > -168.0:
        return False
    # Dateline pocket: touches -180 or sits in the Russian Far East wrap band.
    return min_lon <= -170.0


def shift_dateline_wraps_east(
    geometries: list[list[tuple[float, float]]],
) -> list[list[tuple[float, float]]]:
    shifted: list[list[tuple[float, float]]] = []
    for points in geometries:
        if is_east_asia_dateline_wrap(points):
            shifted.append([(lon + 360.0, lat) for lon, lat in points])
        else:
            shifted.append(points)
    return shifted


def rounded_coordinate(point: tuple[float, float]) -> dict[str, float]:
    return {"latitude": round(point[1], 6), "longitude": round(point[0], 6)}


def build_geography(
    land_path: Path, lakes_path: Path, boundaries_path: Path
) -> dict:
    land_rings = shift_dateline_wraps_east(process_land(load_geojson(land_path)))
    lake_rings = process_lakes(load_geojson(lakes_path))
    boundary_lines = shift_dateline_wraps_east(
        process_boundaries(load_geojson(boundaries_path))
    )
    return {
        "version": 2,
        "source": (
            "Natural Earth 110m land + lakes, 50m admin-0 land boundary lines "
            "(https://www.naturalearthdata.com/); Antarctica omitted; "
            "NE Asia dateline wrap shifted east (+360°); "
            "land simplify ~6 km, borders ~2 km"
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
        "rivers": [],
        "boundaries": [
            {
                "id": f"world_border_{index:04d}",
                "points": [rounded_coordinate(point) for point in line],
            }
            for index, line in enumerate(boundary_lines, 1)
        ],
    }


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


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
