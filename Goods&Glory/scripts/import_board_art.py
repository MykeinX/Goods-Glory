#!/usr/bin/env python3
"""Import Mini Metro–style board art into map_board_silhouette.json.

Unlike aggressive polygon approximation (which collapses continents into
triangles), this keeps a high-detail contour then snaps every coast edge to
the eight board directions (horizontal, vertical, 45°). SpriteKit only rounds
corners with a small fixed radius at render time.

Usage:
  python3 -B scripts/import_board_art.py
  python3 -B scripts/import_board_art.py --source path/to/board.png
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
from pathlib import Path

import cv2
import numpy as np

# Linear fit from artwork land bbox → geographic extents. City coordinates in
# cities.json are authored in this same board space (not raw WGS84). Re-tune
# only if framing changes.
LON0, LON1 = -170.0, 190.0
LAT0, LAT1 = 80.0, -55.0

# Light Douglas–Peucker fraction of perimeter for continents. Aggressive
# values (~0.01+) produce the triangle disaster; stay well below that.
CONTOUR_EPS_FRAC = 0.00035
# Small islands get a stronger simplify so they read as soft chips.
SMALL_AREA_PX = 3_500
SMALL_CONTOUR_EPS_FRAC = 0.004
MIN_OUTER_AREA = 120
MIN_HOLE_AREA = 120

OCTI_GUARD_PX = 6.0
OCTI_GUARD_SMALL_PX = 9.0
OCTI_MIN_EDGE_PX = 1.5
OCTI_MIN_EDGE_SMALL_PX = 3.0
SMALL_MAX_VERTS = 14


def extract_land(img: np.ndarray) -> np.ndarray:
    b, g, r = cv2.split(img)
    white = ((r > 220) & (g > 220) & (b > 220)).astype(np.uint8)
    num, labels, stats, _ = cv2.connectedComponentsWithStats(white, 8)
    border = np.zeros_like(white)
    border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = 1
    frame = {
        int(labels[y, x])
        for y, x in zip(*np.where(border.astype(bool) & white.astype(bool)))
    }
    land = np.zeros(white.shape, np.uint8)
    for lab in range(1, num):
        if lab in frame or stats[lab, cv2.CC_STAT_AREA] < 40:
            continue
        land[labels == lab] = 255
    land = cv2.morphologyEx(land, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    return land


def land_bbox(land: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(land > 0)
    return int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())


def px_to_geo(pt, box: tuple[int, int, int, int]) -> tuple[float, float]:
    x0, x1, y0, y1 = box
    x, y = float(pt[0]), float(pt[1])
    lon = LON0 + (x - x0) / (x1 - x0) * (LON1 - LON0)
    lat = LAT0 - (y - y0) / (y1 - y0) * (LAT0 - LAT1)
    return round(lat, 4), round(lon, 4)


def open_ring(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(points) >= 2 and points[0] == points[-1]:
        return points[:-1]
    return list(points)


def octilinear_ring(
    points: list[tuple[float, float]],
    *,
    guard_px: float = OCTI_GUARD_PX,
    min_edge_px: float = OCTI_MIN_EDGE_PX,
) -> list[tuple[float, float]] | None:
    """Snap a closed ring to the eight directions in pixel space."""
    ring = open_ring([(float(x), float(y)) for x, y in points])
    if len(ring) < 3:
        return None

    step = math.pi / 4
    runs: list[dict] = []
    for index in range(len(ring)):
        start = ring[index]
        end = ring[(index + 1) % len(ring)]
        length = math.hypot(end[0] - start[0], end[1] - start[1])
        if length < 1e-9:
            continue
        direction = round(math.atan2(end[1] - start[1], end[0] - start[0]) / step) * step
        midpoint = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
        if runs and math.isclose(runs[-1]["direction"], direction, abs_tol=1e-9):
            previous = runs[-1]
            total = previous["length"] + length
            previous["anchor"] = (
                (previous["anchor"][0] * previous["length"] + midpoint[0] * length) / total,
                (previous["anchor"][1] * previous["length"] + midpoint[1] * length) / total,
            )
            previous["length"] = total
            previous["corner"] = end
        else:
            runs.append({
                "direction": direction,
                "anchor": midpoint,
                "length": length,
                "corner": end,
            })
    if len(runs) >= 2 and math.isclose(runs[0]["direction"], runs[-1]["direction"], abs_tol=1e-9):
        first, last = runs[0], runs.pop()
        total = first["length"] + last["length"]
        first["anchor"] = (
            (first["anchor"][0] * first["length"] + last["anchor"][0] * last["length"]) / total,
            (first["anchor"][1] * first["length"] + last["anchor"][1] * last["length"]) / total,
        )
        first["length"] = total
    if len(runs) < 3:
        return None

    result: list[tuple[float, float]] = []
    for index, run in enumerate(runs):
        following = runs[(index + 1) % len(runs)]
        corner = run["corner"]
        di = (math.cos(run["direction"]), math.sin(run["direction"]))
        dj = (math.cos(following["direction"]), math.sin(following["direction"]))
        determinant = di[0] * dj[1] - di[1] * dj[0]
        if abs(determinant) < 0.3:
            result.append(corner)
            continue
        ai, aj = run["anchor"], following["anchor"]
        t = ((aj[0] - ai[0]) * dj[1] - (aj[1] - ai[1]) * dj[0]) / determinant
        candidate = (ai[0] + di[0] * t, ai[1] + di[1] * t)
        if math.hypot(candidate[0] - corner[0], candidate[1] - corner[1]) > guard_px:
            result.append(corner)
        else:
            result.append(candidate)

    spike_cos = math.cos(math.radians(35.0))
    changed = True
    while changed and len(result) > 3:
        changed = False
        for index in range(len(result)):
            previous = result[index - 1]
            current = result[index]
            following = result[(index + 1) % len(result)]
            into = (current[0] - previous[0], current[1] - previous[1])
            out = (following[0] - current[0], following[1] - current[1])
            lengths = math.hypot(*into) * math.hypot(*out)
            if lengths < 1e-12:
                continue
            cosine = -(into[0] * out[0] + into[1] * out[1]) / lengths
            if cosine > spike_cos:
                del result[index]
                changed = True
                break

    cleaned: list[tuple[float, float]] = []
    for point in result:
        if cleaned and math.hypot(
            point[0] - cleaned[-1][0], point[1] - cleaned[-1][1]
        ) < min_edge_px:
            cleaned[-1] = (
                (cleaned[-1][0] + point[0]) / 2,
                (cleaned[-1][1] + point[1]) / 2,
            )
        else:
            cleaned.append(point)
    if len(cleaned) >= 2 and math.hypot(
        cleaned[0][0] - cleaned[-1][0], cleaned[0][1] - cleaned[-1][1]
    ) < min_edge_px:
        cleaned.pop()
    if len(cleaned) < 3:
        return None
    return cleaned


def approx_contour(cnt, area: float) -> np.ndarray:
    peri = cv2.arcLength(cnt, True)
    small = area < SMALL_AREA_PX
    eps_frac = SMALL_CONTOUR_EPS_FRAC if small else CONTOUR_EPS_FRAC
    ceiling = peri * (0.04 if small else 0.004)
    epsilon = min(max(1.2, eps_frac * peri), ceiling)
    return cv2.approxPolyDP(cnt, epsilon, True).reshape(-1, 2)


def reduce_small_ring(ring: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(ring) <= SMALL_MAX_VERTS:
        return ring
    points = list(ring)
    while len(points) > SMALL_MAX_VERTS:
        best_i = None
        best_len = float("inf")
        for index in range(len(points)):
            previous = points[index - 1]
            current = points[index]
            following = points[(index + 1) % len(points)]
            edge = (
                math.hypot(current[0] - previous[0], current[1] - previous[1])
                + math.hypot(following[0] - current[0], following[1] - current[1])
            )
            if edge < best_len:
                best_len = edge
                best_i = index
        if best_i is None or len(points) <= 4:
            break
        del points[best_i]
    return points


def calm_small_islands(land: np.ndarray) -> np.ndarray:
    """Close AA gaps on small components. Never OPEN — that deletes thin islands."""
    num, labels, stats, _ = cv2.connectedComponentsWithStats(land, 8)
    out = land.copy()
    kernel = np.ones((3, 3), np.uint8)
    for lab in range(1, num):
        area = stats[lab, cv2.CC_STAT_AREA]
        if area < 40:
            out[labels == lab] = 0
            continue
        if area >= SMALL_AREA_PX:
            continue
        mask = (labels == lab).astype(np.uint8) * 255
        calmed = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        out[labels == lab] = 0
        out[calmed > 0] = 255
    return out


def trace_masses(land: np.ndarray) -> list[dict]:
    contours, hierarchy = cv2.findContours(
        land, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE
    )
    if not contours or hierarchy is None:
        return []
    hier = hierarchy[0]
    masses: list[dict] = []
    i = 0
    while i != -1 and i < len(contours):
        if hier[i][3] != -1:
            i += 1
            continue
        area = cv2.contourArea(contours[i])
        if area < MIN_OUTER_AREA:
            nxt = hier[i][0]
            i = nxt if nxt != -1 else len(contours)
            continue
        small = area < SMALL_AREA_PX
        outer_pts = approx_contour(contours[i], area)
        outer = octilinear_ring(
            [(float(x), float(y)) for x, y in outer_pts],
            guard_px=OCTI_GUARD_SMALL_PX if small else OCTI_GUARD_PX,
            min_edge_px=OCTI_MIN_EDGE_SMALL_PX if small else OCTI_MIN_EDGE_PX,
        )
        if outer is None or len(outer) < 3:
            nxt = hier[i][0]
            i = nxt if nxt != -1 else len(contours)
            continue
        if small:
            outer = reduce_small_ring(outer)
        holes = []
        if not small:
            child = hier[i][2]
            while child != -1:
                if cv2.contourArea(contours[child]) >= MIN_HOLE_AREA:
                    hole_pts = approx_contour(contours[child], area)
                    hole = octilinear_ring(
                        [(float(x), float(y)) for x, y in hole_pts]
                    )
                    if hole is not None and len(hole) >= 3:
                        holes.append(hole)
                child = hier[child][0]
        masses.append({"outer": outer, "holes": holes, "area": area})
        nxt = hier[i][0]
        i = nxt if nxt != -1 else len(contours)
    masses.sort(key=lambda m: -m["area"])
    return masses


def ring_to_points(ring, box) -> list[dict]:
    points = [
        {"latitude": lat, "longitude": lon}
        for lat, lon in (px_to_geo(p, box) for p in ring)
    ]
    if points and points[0] != points[-1]:
        points.append(dict(points[0]))
    return points


def write_json(path: Path, value) -> None:
    text = json.dumps(value, indent=2, ensure_ascii=False)
    text = re.sub(
        r"\{\s*\"latitude\":\s*(-?[\d.]+),\s*\"longitude\":\s*(-?[\d.]+)\s*\}",
        r'{ "latitude": \1, "longitude": \2 }',
        text,
    )
    path.write_text(text + "\n", encoding="utf-8")


def main() -> None:
    scripts = Path(__file__).resolve().parent
    catalog = scripts.parent / "Goods&Glory" / "Resources" / "Catalog"
    default_source = scripts / "assets" / "board_art_reference.png"

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=default_source)
    parser.add_argument(
        "--output",
        type=Path,
        default=catalog / "map_board_silhouette.json",
    )
    parser.add_argument(
        "--seed-from",
        type=Path,
        default=None,
        help="Copy this PNG onto --source before importing",
    )
    args = parser.parse_args()

    if args.seed_from is not None:
        args.source.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.seed_from, args.source)

    if not args.source.exists():
        raise SystemExit(
            f"Missing board art at {args.source}. Pass --seed-from or --source."
        )

    img = cv2.imread(str(args.source), cv2.IMREAD_COLOR)
    if img is None:
        raise SystemExit(f"Could not read {args.source}")

    land = calm_small_islands(extract_land(img))
    box = land_bbox(land)
    masses = trace_masses(land)

    land_masses = []
    index = 1
    for mass in masses:
        land_masses.append({
            "id": f"board_land_{index:03d}",
            "points": ring_to_points(mass["outer"], box),
        })
        index += 1
        for hole in mass["holes"]:
            land_masses.append({
                "id": f"board_hole_{index:03d}",
                # OpenCV already winds holes opposite their outer contour.
                # px_to_geo flips the Y axis for both, so preserving that order
                # keeps the non-zero CGPath fill rule cutting the hole out.
                "points": ring_to_points(hole, box),
            })
            index += 1

    points = sum(len(item["points"]) for item in land_masses)
    board = {
        "version": 5,
        "source": (
            f"Authored Mini Metro board art ({args.source.name}); "
            "high-detail contour + octilinear edge snap; Antarctica omitted"
        ),
        "landMasses": land_masses,
    }
    write_json(args.output, board)
    print(
        f"Wrote {args.output}\n"
        f"  landMasses={len(land_masses)} ({points} points)\n"
        f"  size={args.output.stat().st_size / 1024.0:.1f} KB"
    )


if __name__ == "__main__":
    main()
