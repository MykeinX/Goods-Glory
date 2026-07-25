#!/usr/bin/env python3
"""Build the stylised game board from real coastline data.

This replaces importing a drawing. The old pipeline traced a 1024x576
decorative world map and then tried to fit that art back onto the globe; the
fit was good to about 1.5 degrees RMS and 3.8 degrees at worst, which put
Miami 495 km inland and left Houston and New York off the land mask entirely.
Port cities are the ones a logistics game cares about, and they were the ones
the art destroyed.

So geography comes from Natural Earth now, and the flat-icon look is produced
here instead of being traced. One source feeds both the drawn silhouette and
the land mask `map_grid.BoardGrid` rasterises, so the coast a road is forbidden
to cross is by construction the coast the player sees.

Output coordinates are real WGS84. Cities are authored in WGS84 too, so there
is no registration step left to drift.

Usage: python3 -B scripts/build_board.py [--preview]
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

import cv2
import numpy as np

# Board window. Longitudes run past +-180 so the Pacific rim stays whole
# instead of being sliced down the dateline; MapProjection expects that.
BOARD_MIN_LON, BOARD_MAX_LON = -185.0, 200.0
BOARD_MIN_LAT, BOARD_MAX_LAT = -60.0, 88.0

# Must match MapProjection.swift and map_grid.py.
VERTICAL_BOARD_SCALE = 1.364

# Raster pitch in degrees of longitude. Finer than any feature we intend to
# keep, so the stylising below is what sets the look, not the sampling.
# Sixteen puts a pixel at about 7 km, which is what lets a carved strait be a
# channel several pixels wide rather than a seam that simplification eats.
PIXELS_PER_DEGREE = 16.0

# --- Straits ---------------------------------------------------------------
# Closing each land mass separately keeps every strait the raster can actually
# see, which is most of them: Dover is 34 km and survives untouched. But
# Gibraltar is 14 km and the Bosphorus is 700 m — narrower than a pixel at any
# resolution this board can afford, so they arrive already fused in the source
# raster and no amount of care in the morphology recovers them.
#
# They are therefore authored. That is not a workaround: at board scale a 700 m
# channel has to be drawn far wider than life to exist at all, which is a
# cartographic decision, not a rendering one. It is also gameplay data — these
# are the channels sea routes will run through.
#
# Each is carved at least one lattice cell wide so it blocks a road as well as
# reading as water. Where a real fixed link crosses one, the road declares
# itself in WATER_CROSSINGS, exactly as London–Paris already does.
STRAIT_WIDTH_KM = 52.0
STRAITS: dict[str, list[tuple[float, float]]] = {
    # (latitude, longitude) along the channel's centre line.
    "gibraltar": [(35.95, -5.55), (35.90, -5.35)],
    "bosphorus": [(41.35, 29.15), (40.95, 28.90), (40.65, 27.30), (40.20, 26.20)],
    "suez": [(31.25, 32.35), (29.95, 32.55), (27.80, 34.05)],
    "panama": [(9.35, -79.95), (8.90, -79.55)],
    "malacca": [(5.60, 98.20), (2.90, 101.20), (1.20, 103.60)],
}

# --- Stylising -------------------------------------------------------------
# The look is "flat icon world map": bays and straits narrower than a strait
# worth sailing are filled, spits and islets smaller than a landmark are
# dropped, and what survives is drawn with few vertices. Corner rounding is
# the renderer's job (GameMapScene+Terrain), so no rounding happens here.

# Closing fills inlets and channels thinner than this. Big enough to swallow
# fjords and river mouths, small enough to keep the Gulf, the Red Sea and the
# Channel as water.
CLOSE_KM = 85.0
# Opening removes headlands and isthmuses thinner than this. Kept well below
# CLOSE_KM so Florida, Italy, Baja and Denmark survive as recognisable shapes.
OPEN_KM = 52.0
# Land smaller than this is not a place the player can route through.
MIN_ISLAND_KM2 = 110_000.0
# Inland water smaller than this reads as a blemish, not a lake.
MIN_HOLE_KM2 = 60_000.0
# How far the board will stretch its coast to take in an authored city. Beyond
# this the anchor itself is wrong, and saying so beats quietly growing a cape.
CITY_HOLD_LIMIT_KM = 320.0
# Each pass grows the coast by this much around a city the rings left out. A
# patch has to outlast simplification to change the outline, so it starts near
# SIMPLIFY_KM rather than at the few km the raster says are missing.
CITY_HOLD_STEP_KM = 55.0
# An outer ring smaller than this is land inside an inland sea, not a continent
# that should punch through one. Sized well above any held city patch.
HOLE_ISLAND_MAX_PX = 40_000.0
# Solid land kept right under a held city. Must exceed SIMPLIFY_KM or the patch
# is thinned away by the very pass it exists to survive — at 26 km Rome and
# Miami were re-patched five times and still ended up at sea.
CITY_HOLD_CORE_KM = 88.0
# Contour simplification, as an absolute distance the outline may stray from
# the true coast. Absolute on purpose: a tolerance scaled to each ring's own
# perimeter is enormous for a continent and tiny for an island, which cut
# North America in half while tracing Ireland's every cove.
SIMPLIFY_KM = 70.0
# Islands carry proportionally more shape in fewer km, so they are allowed a
# finer tolerance without costing many vertices.
SMALL_RING_KM2 = 900_000.0
SMALL_SIMPLIFY_KM = 42.0
# Collapse vertices that add no shape.
COLLINEAR_DEGREES = 4.0
MIN_EDGE_KM = 55.0

# --- Octilinear regularisation ---------------------------------------------
# The reference art is not merely simplified, it is regularised: every coast
# runs horizontal, vertical or at exactly 45 degrees, and the turns between
# those runs are rounded. That is the same grammar the road lattice uses, which
# is why the two read as one board. Simplification alone leaves coasts at
# arbitrary angles that fight the roads crossing them.
#
# Corner rounding is deliberately NOT done here: GameMapScene+Terrain strokes
# these rings with a fixed-radius round, so baking curves in would round twice
# and cost vertices for no gain.
OCTILINEAR = True
# Only an edge already this close to one of the eight directions passes through
# untouched; everything else is split into two octilinear runs. Kept tight on
# purpose — a generous tolerance here leaves oblique coasts in place, which is
# exactly the look this step exists to remove.
OCTILINEAR_SNAP_DEGREES = 3.0
# Runs shorter than this are absorbed into their neighbour instead of becoming
# a visible stair step. This is what keeps the result blocky rather than jagged.
OCTILINEAR_MIN_RUN_KM = 105.0
# ...but only when the corner that replaces the step stays this close to where
# the coast actually ran. Two runs meeting at a shallow angle can otherwise
# meet hundreds of km out to sea, which is how a bulge like Brazil turns into
# one long diagonal.
OCTILINEAR_MAX_DRIFT_KM = 105.0
# A vertex whose two edges double back on each other is a needle: a cape a few
# cells wide and many long. Rounding cannot soften one — there is no room
# between its sides — so it is cut off at the base instead. Measured as the
# turn away from straight-on, so 180° is a perfect spike.
SPIKE_TURN_DEGREES = 128.0
SPIKE_MAX_ARM_KM = 240.0

DEGREE_KM = 6_378.137 * math.pi / 180


def _kilometres_to_pixels(km: float) -> float:
    return km / DEGREE_KM * PIXELS_PER_DEGREE


class BoardRaster:
    """Land mask in board-projected space, where a pixel is square on screen."""

    def __init__(self) -> None:
        self.width = int(round((BOARD_MAX_LON - BOARD_MIN_LON) * PIXELS_PER_DEGREE))
        self.min_y = BOARD_MIN_LAT * VERTICAL_BOARD_SCALE
        self.max_y = BOARD_MAX_LAT * VERTICAL_BOARD_SCALE
        self.height = int(round((self.max_y - self.min_y) * PIXELS_PER_DEGREE))
        self.mask = np.zeros((self.height, self.width), np.uint8)

    def pixels(self, ring: list[tuple[float, float]], lon_shift: float) -> np.ndarray:
        return np.array(
            [
                (
                    (longitude + lon_shift - BOARD_MIN_LON) * PIXELS_PER_DEGREE,
                    (self.max_y - latitude * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE,
                )
                for longitude, latitude in ring
            ],
            np.int32,
        )

    def coordinate(self, x: float, y: float) -> tuple[float, float]:
        longitude = x / PIXELS_PER_DEGREE + BOARD_MIN_LON
        latitude = (self.max_y - y / PIXELS_PER_DEGREE) / VERTICAL_BOARD_SCALE
        return (round(latitude, 4), round(longitude, 4))

    def draw(self, rings: list[list[tuple[float, float]]], value: int) -> None:
        # Every ring is drawn at three longitudes so shapes meeting the
        # dateline arrive whole from either side and the board window can run
        # past +-180 without a seam.
        for shift in (-360.0, 0.0, 360.0):
            polygons = [self.pixels(ring, shift) for ring in rings]
            polygons = [p for p in polygons if len(p) >= 3]
            if polygons:
                cv2.fillPoly(self.mask, polygons, value)

    def pixel_km2(self) -> float:
        return (DEGREE_KM / PIXELS_PER_DEGREE) ** 2 / VERTICAL_BOARD_SCALE


def rings_of(geometry: dict) -> list[list[list[tuple[float, float]]]]:
    """GeoJSON geometry as a list of polygons, each [outer, *holes]."""
    kind = geometry["type"]
    if kind == "Polygon":
        return [geometry["coordinates"]]
    if kind == "MultiPolygon":
        return list(geometry["coordinates"])
    return []


def load_rings(path: Path) -> list[list[list[tuple[float, float]]]]:
    data = json.loads(path.read_text())
    polygons: list[list[list[tuple[float, float]]]] = []
    for feature in data["features"]:
        geometry = feature.get("geometry")
        if geometry:
            polygons.extend(rings_of(geometry))
    return polygons


def build_mask(assets: Path) -> BoardRaster:
    """Land only. Lakes are punched later, after closing cannot refill them."""
    board = BoardRaster()
    for polygon in load_rings(assets / "ne_50m_land.geojson"):
        board.draw([polygon[0]], 255)
        for hole in polygon[1:]:
            board.draw([hole], 0)
    return board


def punch_lakes(mask: np.ndarray, board: BoardRaster, assets: Path) -> np.ndarray:
    """Inland water big enough to be a barrier, not a blemish.

    Punched after closing so a lake is never filled in and then traced as land;
    an inland sea has to be water to the router as well as to the eye.
    """
    minimum = MIN_HOLE_KM2 / board.pixel_km2()
    lakes = BoardRaster()
    for polygon in load_rings(assets / "ne_50m_lakes.geojson"):
        probe = BoardRaster()
        probe.draw([polygon[0]], 255)
        if int(probe.mask.sum()) / 255 >= minimum:
            lakes.draw([polygon[0]], 255)
    result = mask.copy()
    result[lakes.mask > 0] = 0
    return result


def ellipse(km: float) -> np.ndarray:
    size = max(3, int(round(_kilometres_to_pixels(km))) | 1)
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))


def close_per_component(mask: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    """Close each land mass on its own, so no strait is ever bridged.

    Closing the whole map at once fills any water narrower than the kernel —
    including the Dover Strait, which fused Britain to France and quietly
    deleted the Channel fixed link the game is built around. Closing a land
    mass in isolation can only fill its own bays: the water beyond a strait
    belongs to a different land mass and is simply open sea from here.

    Straits therefore survive by construction, with no list to maintain.
    """
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        (mask > 0).astype(np.uint8), 8
    )
    pad = max(kernel.shape) + 2
    result = np.zeros_like(mask)
    for label in range(1, count):
        x = stats[label, cv2.CC_STAT_LEFT]
        y = stats[label, cv2.CC_STAT_TOP]
        width = stats[label, cv2.CC_STAT_WIDTH]
        height = stats[label, cv2.CC_STAT_HEIGHT]
        x0, y0 = max(0, x - pad), max(0, y - pad)
        x1 = min(mask.shape[1], x + width + pad)
        y1 = min(mask.shape[0], y + height + pad)
        window = (labels[y0:y1, x0:x1] == label).astype(np.uint8) * 255
        closed = cv2.morphologyEx(window, cv2.MORPH_CLOSE, kernel)
        np.maximum(result[y0:y1, x0:x1], closed, out=result[y0:y1, x0:x1])
    return result


def carve_straits(mask: np.ndarray, board: BoardRaster) -> np.ndarray:
    """Open the authored channels, after morphology can no longer close them."""
    result = mask.copy()
    width = max(3, int(round(_kilometres_to_pixels(STRAIT_WIDTH_KM))))
    for centre_line in STRAITS.values():
        points = np.array(
            [
                (
                    (longitude - BOARD_MIN_LON) * PIXELS_PER_DEGREE,
                    (board.max_y - latitude * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE,
                )
                for latitude, longitude in centre_line
            ],
            np.int32,
        )
        cv2.polylines(result, [points], False, 0, width, cv2.LINE_8)
    return result


def stylise(board: BoardRaster, assets: Path) -> np.ndarray:
    """Fill the narrow water, drop the small land, keep the readable shape."""
    mask = close_per_component(board.mask, ellipse(CLOSE_KM))
    mask = punch_lakes(mask, board, assets)
    # Opening only ever removes pixels, so it cannot undo the separation above.
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, ellipse(OPEN_KM))
    # Carved last, so nothing downstream can fill a channel back in.
    mask = carve_straits(mask, board)

    pixel_km2 = board.pixel_km2()
    mask = drop_components(mask, 255, MIN_ISLAND_KM2 / pixel_km2)
    mask = drop_components(mask, 0, MIN_HOLE_KM2 / pixel_km2)
    return mask


def drop_components(mask: np.ndarray, value: int, minimum_pixels: float) -> np.ndarray:
    """Erase blobs of `value` smaller than the threshold, keeping the frame."""
    target = (mask == value).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(target, 8)
    result = mask.copy()
    # The ocean touches the border and must never be filled in as a "small
    # hole", however the window happens to be cropped.
    border = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    for label in range(1, count):
        if label in border:
            continue
        if stats[label, cv2.CC_STAT_AREA] < minimum_pixels:
            result[labels == label] = 0 if value else 255
    return result


def simplify(ring: np.ndarray, area_km2: float, board: BoardRaster) -> list:
    tolerance = SIMPLIFY_KM if area_km2 >= SMALL_RING_KM2 else SMALL_SIMPLIFY_KM
    points = cv2.approxPolyDP(
        ring, _kilometres_to_pixels(tolerance), True
    ).reshape(-1, 2).astype(float)
    outline = collapse(points, board)
    if OCTILINEAR and len(outline) >= 3:
        outline = regularise(outline)
    return outline


# The eight board directions, as (dx, dy) in raster pixels.
DIRECTIONS_8 = [
    (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
]


def regularise(points: list) -> list:
    """Redraw a ring so every edge is horizontal, vertical or exactly 45°.

    Each edge is replaced by at most two octilinear runs that meet its own
    endpoints, so the outline still passes through the vertices simplification
    chose and cannot drift off the coast. Runs are then merged and short steps
    absorbed, which is what turns a staircase into the few long strokes the
    reference art is made of.
    """
    runs = _decompose_ring(points)
    runs = _merge_collinear(runs)
    runs = _absorb_short_runs(
        runs,
        _kilometres_to_pixels(OCTILINEAR_MIN_RUN_KM),
        _kilometres_to_pixels(OCTILINEAR_MAX_DRIFT_KM),
    )
    clipped = _clip_spikes(runs)
    if len(clipped) != len(runs):
        # Cutting a needle joins its neighbours at whatever angle they had, so
        # the ring has to be put back on the eight directions afterwards.
        clipped = _merge_collinear(_decompose_ring(clipped))
    return clipped if len(clipped) >= 3 else points


def _clip_spikes(points: list) -> list:
    """Cut needles off at the base so corner rounding has something to round.

    A fixed-radius round can only soften a corner that has room on both sides.
    Where a cape doubles back on itself the two sides are the same few pixels
    apart, so the round collapses and the coast keeps a hard point.
    """
    maximum_arm = _kilometres_to_pixels(SPIKE_MAX_ARM_KM)
    limit = math.cos(math.radians(180 - SPIKE_TURN_DEGREES))
    working = list(points)
    for _ in range(len(points)):
        count = len(working)
        if count <= 4:
            break
        cut: int | None = None
        for index in range(count):
            before = working[(index - 1) % count]
            corner = working[index]
            after = working[(index + 1) % count]
            incoming = (corner[0] - before[0], corner[1] - before[1])
            outgoing = (after[0] - corner[0], after[1] - corner[1])
            first = math.hypot(*incoming)
            second = math.hypot(*outgoing)
            if first < 1e-9 or second < 1e-9:
                cut = index
                break
            if min(first, second) > maximum_arm:
                continue
            # Cosine of the turn away from carrying straight on.
            turn = (incoming[0] * outgoing[0] + incoming[1] * outgoing[1]) / (first * second)
            if turn < -limit:
                cut = index
                break
        if cut is None:
            break
        working.pop(cut)
    return _merge_collinear(working)


def _decompose_ring(points: list) -> list:
    """Every edge as an axis run plus a 45° run, endpoints preserved."""
    snap = math.radians(OCTILINEAR_SNAP_DEGREES)
    result: list[tuple[float, float]] = [tuple(points[0])]
    count = len(points)
    for index in range(count):
        target = tuple(points[(index + 1) % count])
        start = result[-1]
        dx, dy = target[0] - start[0], target[1] - start[1]
        if abs(dx) < 1e-9 and abs(dy) < 1e-9:
            continue

        # An edge already close to one of the eight directions is taken as
        # that direction outright; only genuinely oblique edges are split.
        angle = math.atan2(dy, dx)
        nearest = round(angle / (math.pi / 4)) % 8
        if abs(_angle_difference(angle, nearest * math.pi / 4)) <= snap:
            _push(result, target)
            continue

        step_x = (dx > 0) - (dx < 0)
        step_y = (dy > 0) - (dy < 0)
        if abs(dx) >= abs(dy):
            corner = (start[0] + step_x * (abs(dx) - abs(dy)), start[1])
        else:
            corner = (start[0], start[1] + step_y * (abs(dy) - abs(dx)))
        _push(result, corner)
        _push(result, target)

    if len(result) > 1 and math.dist(result[0], result[-1]) < 1e-9:
        result.pop()
    return result


def _push(result: list, point: tuple[float, float]) -> None:
    if math.dist(point, result[-1]) > 1e-9:
        result.append(point)


def _angle_difference(first: float, second: float) -> float:
    return (first - second + math.pi) % (2 * math.pi) - math.pi


def _direction(start, end) -> tuple[int, int]:
    dx = float(end[0]) - float(start[0])
    dy = float(end[1]) - float(start[1])
    return (int(dx > 1e-9) - int(dx < -1e-9), int(dy > 1e-9) - int(dy < -1e-9))


def _merge_collinear(points: list) -> list:
    count = len(points)
    if count < 3:
        return points
    result = []
    for index in range(count):
        previous = points[(index - 1) % count]
        current = points[index]
        following = points[(index + 1) % count]
        if _direction(previous, current) != _direction(current, following):
            result.append(current)
    return result or points


def _absorb_short_runs(points: list, minimum: float, maximum_drift: float) -> list:
    """Replace a short run by the meeting point of the runs either side.

    Both neighbours keep their direction, so the ring stays octilinear; it
    simply loses a step that read as a wobble rather than a corner. A step is
    only absorbed when the corner replacing it stays within `maximum_drift` of
    the coast it stood on — otherwise the step is real shape, not a wobble,
    and gets left alone.
    """
    working = list(points)
    blocked: set[tuple[float, float]] = set()
    for _ in range(len(points)):
        count = len(working)
        if count <= 4:
            break
        candidates = [
            (math.dist(working[index], working[(index + 1) % count]), index)
            for index in range(count)
            if working[index] not in blocked
        ]
        if not candidates:
            break
        length, shortest = min(candidates)
        if length >= minimum:
            break

        start = working[shortest]
        end = working[(shortest + 1) % count]
        before = working[(shortest - 1) % count]
        after = working[(shortest + 2) % count]
        meeting = _intersect(before, start, end, after)
        if (
            meeting is None
            or math.dist(meeting, start) > maximum_drift
            or math.dist(meeting, end) > maximum_drift
        ):
            # Parallel, or the corner would land far out to sea. Keep the step:
            # at this length it is carrying real shape.
            blocked.add(start)
            continue
        working[shortest] = meeting
        working.pop((shortest + 1) % count)
    return _merge_collinear(working)


def _intersect(a1, a2, b1, b2):
    """Where line a1->a2 meets line b1->b2, or None if they are parallel."""
    ax, ay = a2[0] - a1[0], a2[1] - a1[1]
    bx, by = b2[0] - b1[0], b2[1] - b1[1]
    cross = ax * by - ay * bx
    if abs(cross) < 1e-9:
        return None
    t = ((b1[0] - a1[0]) * by - (b1[1] - a1[1]) * bx) / cross
    return (a1[0] + ax * t, a1[1] + ay * t)


def collapse(points: np.ndarray, board: BoardRaster) -> list:
    """Drop vertices that neither turn the outline nor lengthen it."""
    minimum_edge = _kilometres_to_pixels(MIN_EDGE_KM)
    cosine = math.cos(math.radians(COLLINEAR_DEGREES))
    result = [(float(points[0][0]), float(points[0][1]))]
    for raw in points[1:]:
        point = (float(raw[0]), float(raw[1]))
        if math.dist(point, result[-1]) < minimum_edge and len(result) > 3:
            continue
        while len(result) >= 2:
            before, corner = result[-2], result[-1]
            first = (corner[0] - before[0], corner[1] - before[1])
            second = (point[0] - corner[0], point[1] - corner[1])
            first_length = math.hypot(*first)
            second_length = math.hypot(*second)
            if first_length < 1e-6 or second_length < 1e-6:
                result.pop()
                continue
            dot = (first[0] * second[0] + first[1] * second[1]) / (
                first_length * second_length
            )
            if dot < cosine:
                break
            result.pop()
        result.append(tuple(point))
    return result


def trace(mask: np.ndarray, board: BoardRaster) -> list[dict]:
    """Outer coastlines and the inland water inside them, largest first."""
    contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    if hierarchy is None:
        return []
    hierarchy = hierarchy[0]
    pixel_km2 = board.pixel_km2()

    outers: list[tuple[float, int]] = []
    holes: list[tuple[float, int]] = []
    for index, contour in enumerate(contours):
        area = cv2.contourArea(contour) * pixel_km2
        if hierarchy[index][3] < 0:
            if area >= MIN_ISLAND_KM2:
                outers.append((area, index))
        elif area >= MIN_HOLE_KM2:
            holes.append((area, index))

    masses: list[dict] = []
    for order, (area, index) in enumerate(sorted(outers, reverse=True), start=1):
        masses.append({
            "id": f"board_land_{order:03d}",
            "points": [
                {"latitude": lat, "longitude": lon}
                for lat, lon in (
                    board.coordinate(x, y)
                    for x, y in simplify(contours[index], area, board)
                )
            ],
        })
    for order, (area, index) in enumerate(sorted(holes, reverse=True), start=1):
        masses.append({
            "id": f"board_hole_{order:03d}",
            "points": [
                {"latitude": lat, "longitude": lon}
                for lat, lon in (
                    board.coordinate(x, y)
                    for x, y in simplify(contours[index], area, board)
                )
            ],
        })
    return [mass for mass in masses if len(mass["points"]) >= 3]


def traced_mask(masses: list[dict], board: BoardRaster) -> np.ndarray:
    """The traced rings rasterised back, exactly as the renderer fills them.

    Testing rings one at a time cannot answer this: a point inside the
    Mediterranean hole is also inside the Eurasia ring that contains it, and
    land painted back into that hole is a third ring inside both. Filling them
    in order — land, then holes, then land again — is the only reading that
    matches what the player sees.
    """
    result = np.zeros_like(board.mask)
    for wants_hole in (False, True):
        for mass in masses:
            if mass["id"].startswith("board_hole") != wants_hole:
                continue
            ring = np.array(
                [
                    (
                        (p["longitude"] - BOARD_MIN_LON) * PIXELS_PER_DEGREE,
                        (board.max_y - p["latitude"] * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE,
                    )
                    for p in mass["points"]
                ],
                np.int32,
            )
            if len(ring) >= 3:
                cv2.fillPoly(result, [ring], 0 if wants_hole else 255)
    # Land the holes swallowed, put back: an island inside an inland sea is
    # land, and that is how a city held inside one survives.
    for mass in masses:
        if mass["id"].startswith("board_hole"):
            continue
        ring = np.array(
            [
                (
                    (p["longitude"] - BOARD_MIN_LON) * PIXELS_PER_DEGREE,
                    (board.max_y - p["latitude"] * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE,
                )
                for p in mass["points"]
            ],
            np.int32,
        )
        if len(ring) >= 3 and cv2.contourArea(ring) < HOLE_ISLAND_MAX_PX:
            cv2.fillPoly(result, [ring], 255)
    return result


def trace_holding_cities(
    mask: np.ndarray, board: BoardRaster, anchors: Path, raw: np.ndarray
) -> tuple[list[dict], list[tuple[float, str]]]:
    """Trace the board, and grow it wherever an authored city fell outside.

    Checked against the **traced rings**, not the raster they came from. That
    distinction is the whole point: simplifying to 70 km and regularising with
    up to 105 km of drift cuts corners off a diagonal coast, so a city can sit
    comfortably on land in the mask and still be at sea in the polygon that
    ships. Sydney, Brisbane and Miami all did.

    So the rule is structural: **the board must contain the cities it is built
    for.** Where a ring excludes one, land is painted around it and the board is
    retraced until the ring takes it back in — which also puts the coast back
    roughly where it really runs. Carved straits are never painted over; a city
    on a strait belongs on its shore.
    """
    cities = json.loads(anchors.read_text())["cities"]
    protected = carve_straits(np.full_like(mask, 255), board) == 0
    held: list[tuple[float, str]] = []
    grown: dict[str, float] = {}

    for attempt in range(6):
        masses = trace(mask, board)
        drawn = traced_mask(masses, board)
        missing = []
        for name, anchor in sorted(cities.items()):
            x = int(round((anchor["longitude"] - BOARD_MIN_LON) * PIXELS_PER_DEGREE))
            y = int(round(
                (board.max_y - anchor["latitude"] * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE
            ))
            if not (0 <= x < board.width and 0 <= y < board.height):
                raise SystemExit(f"city {name} is outside the board window")
            if drawn[y, x] == 0:
                missing.append((name, anchor))
        if not missing:
            held = sorted(((km, name) for name, km in grown.items()), reverse=True)
            return masses, held

        # How far each stranded city is from the land that was actually drawn.
        # Measuring the gap beats guessing at it: a fixed step converged for
        # nineteen cities and oscillated for a hundred and seventy, because
        # patching one city retraces the coast its neighbours sit on.
        gap = cv2.distanceTransform((drawn == 0).astype(np.uint8), cv2.DIST_L2, 5)

        for name, anchor in missing:
            x = int(round((anchor["longitude"] - BOARD_MIN_LON) * PIXELS_PER_DEGREE))
            y = int(round(
                (board.max_y - anchor["latitude"] * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE
            ))
            if not (0 <= x < board.width and 0 <= y < board.height):
                raise SystemExit(f"city {name} is outside the board window")
            if protected[y, x]:
                continue
            # Reach the drawn coast, plus enough margin to outlast the next
            # simplification pass. Never shrinks: a patch that was needed once
            # stays, so the loop cannot oscillate.
            needed = float(gap[y, x]) * DEGREE_KM / PIXELS_PER_DEGREE + CITY_HOLD_STEP_KM
            reach_km = max(needed, grown.get(name, 0) + CITY_HOLD_STEP_KM * 0.5)
            if reach_km > CITY_HOLD_LIMIT_KM:
                raise SystemExit(
                    f"city {name} sits more than {CITY_HOLD_LIMIT_KM:.0f} km "
                    f"outside the drawn coast. Stylising moves a diagonal coast "
                    f"by up to about 175 km (SIMPLIFY_KM + OCTILINEAR_MAX_DRIFT_KM), "
                    f"and this one falls beyond that. Either move its anchor "
                    f"inland onto the coast the board actually draws, or drop it "
                    f"and use a different city in the same region."
                )
            # Restore the *real* coast around the city rather than bulging a
            # disc out of the stylised one. Australia's east coast is nearly
            # 200 km west of Brisbane after regularising, and a 200 km circle
            # bolted onto it would read as a blister; the true coastline reads
            # as coastline. The small core disc guarantees the pin itself.
            window = np.zeros_like(mask)
            cv2.circle(window, (x, y), int(_kilometres_to_pixels(reach_km)), 255, -1)
            patch = cv2.bitwise_and(window, raw)
            cv2.circle(patch, (x, y), int(_kilometres_to_pixels(CITY_HOLD_CORE_KM)), 255, -1)
            patch[protected] = 0
            np.maximum(mask, patch, out=mask)
            grown[name] = reach_km

    raise SystemExit(
        "these cities never landed on the drawn board: "
        + ", ".join(f"{name} (grew {grown.get(name, 0):.0f} km)" for name, _ in missing)
        + ". Move their anchors onto the coast the board draws, or replace them "
        "with nearby cities that sit on it."
    )


def verify_straits(mask: np.ndarray, board: BoardRaster) -> None:
    """Every declared channel must still be open, and must still separate land.

    Retuning CLOSE_KM or OPEN_KM is exactly the kind of change that would quietly
    weld one shut again, and the symptom — a road strolling from Spain into
    Morocco — would surface far from its cause.
    """
    count, labels = cv2.connectedComponents((mask == 0).astype(np.uint8), 8)
    _ = count
    for name, centre_line in STRAITS.items():
        for latitude, longitude in centre_line:
            x = int(round((longitude - BOARD_MIN_LON) * PIXELS_PER_DEGREE))
            y = int(round((board.max_y - latitude * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE))
            if not (0 <= x < board.width and 0 <= y < board.height):
                raise SystemExit(f"strait {name}: point ({latitude}, {longitude}) is off the board")
            if mask[y, x] != 0:
                raise SystemExit(
                    f"strait {name}: ({latitude}, {longitude}) closed back up as land. "
                    f"Widen STRAIT_WIDTH_KM or check CLOSE_KM / OPEN_KM."
                )
            if labels[y, x] == 0:
                raise SystemExit(f"strait {name}: carved water is not connected to the sea")


def write_json(path: Path, value) -> None:
    text = json.dumps(value, indent=2, ensure_ascii=False)
    text = re.sub(
        r"\{\s*\"latitude\":\s*(-?[\d.]+),\s*\"longitude\":\s*(-?[\d.]+)\s*\}",
        r'{ "latitude": \1, "longitude": \2 }',
        text,
    )
    path.write_text(text + "\n", encoding="utf-8")


def preview(mask: np.ndarray, masses: list[dict], board: BoardRaster, path: Path) -> None:
    image = np.full((board.height, board.width, 3), (196, 132, 74), np.uint8)
    image[mask > 0] = (232, 238, 240)
    for mass in masses:
        ring = np.array(
            [
                (
                    (p["longitude"] - BOARD_MIN_LON) * PIXELS_PER_DEGREE,
                    (board.max_y - p["latitude"] * VERTICAL_BOARD_SCALE) * PIXELS_PER_DEGREE,
                )
                for p in mass["points"]
            ],
            np.int32,
        )
        colour = (60, 60, 220) if mass["id"].startswith("board_hole") else (40, 160, 40)
        cv2.polylines(image, [ring], True, colour, 2)
    cv2.imwrite(str(path), image)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true", help="write a PNG check")
    arguments = parser.parse_args()

    scripts = Path(__file__).resolve().parent
    catalog = scripts.parent / "Goods&Glory" / "Resources" / "Catalog"

    board = build_mask(scripts / "assets")
    mask = stylise(board, scripts / "assets")
    masses, held = trace_holding_cities(
        mask, board, scripts / "city_anchors.json", board.mask
    )
    verify_straits(mask, board)

    write_json(catalog / "map_board_silhouette.json", {
        "version": 8,
        "source": (
            "Natural Earth 1:50m land and lakes, stylised by build_board.py; "
            "real WGS84; Antarctica outside the board window"
        ),
        "landMasses": masses,
    })

    if arguments.preview:
        preview(mask, masses, board, scripts / ".cache" / "board_preview.png")

    lands = [m for m in masses if not m["id"].startswith("board_hole")]
    holes = [m for m in masses if m["id"].startswith("board_hole")]
    points = sum(len(m["points"]) for m in masses)
    print(
        f"Wrote {len(lands)} land masses and {len(holes)} inland waters\n"
        f"  raster    {board.height}x{board.width} @ {PIXELS_PER_DEGREE:.0f} px/deg\n"
        f"  vertices  {points} total, max {max(len(m['points']) for m in masses)}\n"
        f"  land      {(mask > 0).mean():.1%} of the board window\n"
        f"  held      {len(held)} cities the coast was pulled out to reach"
        + (f", worst {held[0][0]:.0f} km ({held[0][1]})" if held else "")
    )


if __name__ == "__main__":
    main()
