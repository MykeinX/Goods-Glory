#!/usr/bin/env python3
"""Import authored board art into map_board_silhouette.json.

Follows the source silhouette closely: light contour simplification only.
Does not force octilinear (H/V/45°) edges — those made coasts harsher than the
art. SpriteKit rounds corners with a fixed radius at render time.

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

# Contour fidelity. Keep well below the old "triangle disaster" (~0.01+).
CONTOUR_EPS_FRAC = 0.00022
SMALL_AREA_PX = 3_500
SMALL_CONTOUR_EPS_FRAC = 0.0025
MIN_OUTER_AREA = 80
MIN_HOLE_AREA = 80
# Collapse near-collinear runs without inventing new angles.
COLLINEAR_COS = math.cos(math.radians(2.5))
MIN_EDGE_PX = 1.25
SMALL_MAX_VERTS = 28


def extract_land(img: np.ndarray) -> np.ndarray:
    """Land is near-white; water is saturated blue. Soft AA edges bias to land."""
    b, g, r = cv2.split(img.astype(np.float32))
    gray = (r + g + b) / 3.0
    # Prefer luminance over a hard RGB gate so soft coast AA stays with land.
    land = ((gray > 198) & ((r + g) > (b + 55))).astype(np.uint8) * 255
    num, labels, stats, _ = cv2.connectedComponentsWithStats(land, 8)
    border = np.zeros_like(land)
    border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = 1
    frame = {
        int(labels[y, x])
        for y, x in zip(*np.where((border > 0) & (land > 0)))
    }
    cleaned = np.zeros_like(land)
    for lab in range(1, num):
        if lab in frame or stats[lab, cv2.CC_STAT_AREA] < 30:
            continue
        cleaned[labels == lab] = 255
    # Tiny close fills 1px AA notches without bloating continents.
    cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_CLOSE, np.ones((2, 2), np.uint8))
    return cleaned


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


def merge_collinear(
    points: list[tuple[float, float]],
    *,
    min_edge_px: float = MIN_EDGE_PX,
) -> list[tuple[float, float]]:
    """Drop vertices that barely bend the coast; keep authored angles intact."""
    ring = open_ring(points)
    if len(ring) < 3:
        return ring

    changed = True
    while changed and len(ring) > 3:
        changed = False
        for index in range(len(ring)):
            previous = ring[index - 1]
            current = ring[index]
            following = ring[(index + 1) % len(ring)]
            into = (current[0] - previous[0], current[1] - previous[1])
            out = (following[0] - current[0], following[1] - current[1])
            len_in = math.hypot(*into)
            len_out = math.hypot(*out)
            if len_in < min_edge_px or len_out < min_edge_px:
                del ring[index]
                changed = True
                break
            cosine = (into[0] * out[0] + into[1] * out[1]) / (len_in * len_out)
            if cosine >= COLLINEAR_COS:
                del ring[index]
                changed = True
                break
    return ring


def approx_contour(cnt, area: float) -> list[tuple[float, float]]:
    peri = cv2.arcLength(cnt, True)
    small = area < SMALL_AREA_PX
    eps_frac = SMALL_CONTOUR_EPS_FRAC if small else CONTOUR_EPS_FRAC
    ceiling = peri * (0.03 if small else 0.0028)
    epsilon = min(max(0.8, eps_frac * peri), ceiling)
    approx = cv2.approxPolyDP(cnt, epsilon, True).reshape(-1, 2)
    ring = [(float(x), float(y)) for x, y in approx]
    return merge_collinear(ring, min_edge_px=2.0 if small else MIN_EDGE_PX)


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
        if area < 30:
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
        outer = approx_contour(contours[i], area)
        if len(outer) < 3:
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
                    hole = approx_contour(contours[child], area)
                    if len(hole) >= 3:
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
        "version": 7,
        "source": (
            f"Authored board art ({args.source.name}); "
            "contour-faithful import (no octilinear snap); Antarctica omitted"
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
