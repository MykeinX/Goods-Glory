#!/usr/bin/env python3
"""Octilinear board lattice used to bake road geometry.

Every road vertex lands on one shared lattice, so parallel trunks stay truly
parallel and every segment is horizontal, vertical or exactly 45 degrees on
screen. The lattice is square in PROJECTED space, not in degrees: MapProjection
stretches latitude by VERTICAL_BOARD_SCALE, so a degree lattice would render
diagonals at the wrong angle.

Water cells are impassable, which is what makes "no road across the sea" a
structural property instead of a scoring heuristic. Roads that must cross water
(the Channel) opt in explicitly and pay a punitive per-km cost, so the search
picks the narrowest gap.
"""

from __future__ import annotations

import heapq
import json
import math
from pathlib import Path

import cv2
import numpy as np

# Must match Presentation/Map/MapProjection.swift.
EARTH_RADIUS_KM = 6_378.137
VERTICAL_BOARD_SCALE = 1.364
DEGREE_KM = EARTH_RADIUS_KM * math.pi / 180

# Lattice pitch in projected km. 45 km keeps anchor snapping under ~30 km while
# still reading as a deliberate grid at the zoom the map is normally used at.
STEP_KM = 45.0
# Cost of one 45-degree turn, in km of straight running. High on purpose: the
# search buys long clean runs rather than staircases along a diagonal coast.
TURN_KM = 220.0
# What makes a line wobble is a staircase — short runs back to back — not a
# single short run. A lone jog is how any metro map corrects a one-cell offset
# and reads as deliberate. So the charge lands only where a short run follows
# another short run, and each adjacent pair is billed once.
#
# Charging every short run instead, as this once did, made the unavoidable jog
# ruinous: Berlin and Warsaw sit one lattice row apart, and the 540 km levied
# on that single diagonal cell bought a 225 km plunge south and back, which
# cost 440 km and therefore "won". The cure was worse than the wobble.
MINIMUM_RUN_CELLS = 4
SHORT_RUN_KM = 180.0
# Cap on how far one expansion may run. Long enough to cross a continent leg.
MAXIMUM_RUN_CELLS = 48
# A city that shares a row, column or diagonal with a neighbour lets the
# corridor pass without a bend. This is a tie-breaker, not an objective: kept
# below one cell so it can only choose between near-equally close cells, never
# buy a straighter line with a city in the wrong place. At 0.55 it could, and
# it did — Miami left Florida to line up with Atlanta.
ALIGNMENT_BONUS_KM = 0.30 * STEP_KM
# How far inland a tie is allowed to pull a pin, on the same reasoning.
INLAND_BIAS = 0.12
# Hard cap on how far a city may move from its authored coordinate. A coastal
# pin may need most of a cell to reach land; nothing legitimately needs more.
# Exceeding it is a data problem — an anchor at sea, or an island the board
# dropped — and is reported rather than silently absorbed.
MAXIMUM_SNAP_KM = 1.35 * STEP_KM
# Roads drift inland instead of tracing the coastline pixel by pixel.
COAST_MARGIN_KM = STEP_KM * 2.6
COAST_PENALTY = 2.6
# Multiplier applied to water cells for roads that declared a crossing.
CROSSING_WATER_COST = 6.0
# What a cell costs once another road already runs through it. This is what
# makes the network read as a metro map instead of a bundle of unrelated
# strokes: a later road would rather share a trunk for a stretch than draw its
# own line a cell away from one. Low enough to be worth a detour, high enough
# that a road will not cross a continent to find company. Sharing saturates
# around here: below 0.28 the network shares no more track, it only starts
# buying extra bends to reach it.
BUNDLE_DISCOUNT = 0.28
# How much longer bundling may make a road, as a multiple of the same road
# routed alone. Without a ceiling the discount is not a preference but a
# compulsion: at 0.28 a shared cell is 72% off, so a road will dive 225 km off
# its line to reach a trunk and climb back. Berlin and Warsaw sit one lattice
# row apart and were being joined by a five-cell plunge south.
#
# Measured against the road's own solo path, not against the straight line:
# Chicago–Detroit is legitimately 1.46x straight because it rounds the Great
# Lakes, and a ceiling on straightness would have banned the geography instead
# of the detour. Bundling should win ties, never arguments.
MAXIMUM_DETOUR = 1.12

# Board bounds in projected km, fixed so the lattice never shifts between runs.
_BOARD_MIN_LON, _BOARD_MAX_LON = -185.0, 200.0
_BOARD_MIN_LAT, _BOARD_MAX_LAT = -60.0, 88.0
# Land raster resolution. Finer than the lattice so coastlines stay honest.
_RASTER_KM = 15.0

# (row delta, column delta) for the eight metro directions.
DIRECTIONS = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]


def project(latitude: float, longitude: float) -> tuple[float, float]:
    return (DEGREE_KM * longitude, DEGREE_KM * latitude * VERTICAL_BOARD_SCALE)


def unproject(x: float, y: float) -> tuple[float, float]:
    return (y / (DEGREE_KM * VERTICAL_BOARD_SCALE), x / DEGREE_KM)


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    radius = 6371.0
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * radius * math.asin(math.sqrt(h))


class BoardGrid:
    """Land mask plus the shared octilinear lattice over the authored board."""

    def __init__(self, silhouette_path: Path, step_km: float = STEP_KM) -> None:
        self.step_km = step_km
        self.min_x, self.max_x = (
            project(0, _BOARD_MIN_LON)[0],
            project(0, _BOARD_MAX_LON)[0],
        )
        self.min_y, self.max_y = (
            project(_BOARD_MIN_LAT, 0)[1],
            project(_BOARD_MAX_LAT, 0)[1],
        )
        self._build_raster(json.loads(silhouette_path.read_text()))
        self._build_lattice()

    # -- construction ----------------------------------------------------

    def _build_raster(self, board: dict) -> None:
        width = int((self.max_x - self.min_x) / _RASTER_KM)
        height = int((self.max_y - self.min_y) / _RASTER_KM)
        mask = np.zeros((height, width), np.uint8)
        for mass in board["landMasses"]:
            ring = np.array(
                [self._raster_pixel(project(p["latitude"], p["longitude"]))
                 for p in mass["points"]],
                np.int32,
            )
            # Holes are inland water and must be punched back out; treating
            # them as land is what let corridors run across an inland sea.
            cv2.fillPoly(mask, [ring], 0 if mass["id"].startswith("board_hole") else 255)
        self._raster = mask
        self._raster_size = (height, width)
        self._inland_km = cv2.distanceTransform(mask, cv2.DIST_L2, 5) * _RASTER_KM

    def _raster_pixel(self, point: tuple[float, float]) -> tuple[int, int]:
        return (
            int(round((point[0] - self.min_x) / _RASTER_KM)),
            int(round((self.max_y - point[1]) / _RASTER_KM)),
        )

    def _build_lattice(self) -> None:
        self.columns = int((self.max_x - self.min_x) / self.step_km) + 1
        self.rows = int((self.max_y - self.min_y) / self.step_km) + 1
        height, width = self._raster_size
        xs = self.min_x + np.arange(self.columns) * self.step_km
        ys = self.min_y + np.arange(self.rows) * self.step_km
        cols = np.clip(np.round((xs - self.min_x) / _RASTER_KM).astype(int), 0, width - 1)
        rows = np.clip(np.round((self.max_y - ys) / _RASTER_KM).astype(int), 0, height - 1)
        self.is_land = self._raster[np.ix_(rows, cols)] > 0
        self.inland_km = self._inland_km[np.ix_(rows, cols)]
        # Which land mass each cell belongs to, in lattice terms. A search
        # between two disconnected masses can never succeed, and without this
        # it discovers that by exhausting a continent — minutes of silence
        # instead of an error naming the city that is stranded.
        _, self._components = cv2.connectedComponents(
            self.is_land.astype(np.uint8), 8
        )

    # -- lattice access --------------------------------------------------

    def point(self, cell: tuple[int, int]) -> tuple[float, float]:
        row, column = cell
        return (self.min_x + column * self.step_km, self.min_y + row * self.step_km)

    def coordinate(self, cell: tuple[int, int]) -> tuple[float, float]:
        """Lattice cell as (latitude, longitude), rounded for stable JSON."""
        latitude, longitude = unproject(*self.point(cell))
        return (round(latitude, 4), round(longitude, 4))

    def snap(
        self,
        latitude: float,
        longitude: float,
        taken: set[tuple[int, int]],
        aligned_with: list[tuple[int, int]] | None = None,
    ) -> tuple[tuple[int, int], float]:
        """Nearest free land cell, biased inland and towards neighbour alignment.

        Alignment is what keeps a trunk straight: if a city shares a row,
        column or diagonal with the cities it connects to, the corridor runs
        without a bend. Snapping on distance alone leaves endpoints a cell or
        two off the line, which the map shows as a wobble.
        """
        target = project(latitude, longitude)
        column = int(round((target[0] - self.min_x) / self.step_km))
        row = int(round((target[1] - self.min_y) / self.step_km))

        # The radius grows only if the cap found nothing, so the common case
        # stays inside MAXIMUM_SNAP_KM and a genuinely stranded anchor still
        # resolves — loudly, through the returned distance.
        limit = MAXIMUM_SNAP_KM
        while True:
            span = int(limit / self.step_km) + 1
            best: tuple[float, float, tuple[int, int]] | None = None
            for row_delta in range(-span, span + 1):
                for column_delta in range(-span, span + 1):
                    cell = (row + row_delta, column + column_delta)
                    if not self._inside(cell) or not self.is_land[cell]:
                        continue
                    if cell in taken:
                        continue
                    distance = math.dist(self.point(cell), target)
                    if distance > limit:
                        continue
                    # Among cells that are near-equally close, prefer the one
                    # further from the coast and the one that lines up with a
                    # neighbour. Both bonuses are capped below one cell, so
                    # neither can outvote being in the right place.
                    inland = min(float(self.inland_km[cell]), 2.5 * self.step_km)
                    score = distance - INLAND_BIAS * inland
                    score -= ALIGNMENT_BONUS_KM * self._alignment(cell, aligned_with)
                    if best is None or score < best[0]:
                        best = (score, distance, cell)
            if best is not None:
                return best[2], best[1]
            if limit > 20 * self.step_km:
                raise ValueError(f"no free land cell near ({latitude}, {longitude})")
            limit *= 2

    @staticmethod
    def _alignment(cell: tuple[int, int], others: list[tuple[int, int]] | None) -> int:
        if not others:
            return 0
        count = 0
        for other in others:
            rows = abs(cell[0] - other[0])
            columns = abs(cell[1] - other[1])
            if rows == 0 or columns == 0 or rows == columns:
                count += 1
        return count

    def _inside(self, cell: tuple[int, int]) -> bool:
        return 0 <= cell[0] < self.rows and 0 <= cell[1] < self.columns

    # -- search ----------------------------------------------------------

    def path(
        self,
        start: tuple[int, int],
        goal: tuple[int, int],
        *,
        may_cross_water: bool = False,
        bundled: set[tuple[int, int]] | None = None,
        budget: float | None = None,
    ) -> list[tuple[int, int]] | None:
        """Cheapest octilinear lattice path, penalising turns and coastlines.

        `bundled` holds the cells roads baked earlier already occupy. They are
        discounted, so this road shares their trunk where that is close to its
        own way instead of running a parallel line beside it.

        `budget` caps the plain, undiscounted km the path may cover. Callers
        pass the length of this road routed alone times `MAXIMUM_DETOUR`, which
        is what keeps bundling from dragging a road off its line.
        """
        if not (self._inside(start) and self._inside(goal)):
            return None

        def passable(cell: tuple[int, int]) -> bool:
            return self._inside(cell) and (self.is_land[cell] or may_cross_water)

        def cell_cost(cell: tuple[int, int]) -> float:
            if not self.is_land[cell]:
                return CROSSING_WATER_COST
            if bundled and cell in bundled:
                return BUNDLE_DISCOUNT
            shallow = max(0.0, 1.0 - float(self.inland_km[cell]) / COAST_MARGIN_KM)
            return 1.0 + COAST_PENALTY * shallow * shallow

        # The estimate assumes plain land, so a route that could have ridden
        # discounted cells is mildly over-estimated and the search may settle a
        # few percent above the true cheapest path. That is the right trade:
        # scaling the estimate down to stay strictly admissible makes it weak
        # enough to explode the frontier, and this cost buys looks, not length.
        def heuristic(cell: tuple[int, int]) -> float:
            rows = abs(cell[0] - goal[0])
            columns = abs(cell[1] - goal[1])
            return (max(rows, columns) + (math.sqrt(2) - 1) * min(rows, columns)) * self.step_km

        if not passable(start) or not passable(goal):
            return None
        if not may_cross_water and self._components[start] != self._components[goal]:
            return None

        ceiling = math.inf if budget is None else budget

        # Expansion is by whole straight runs rather than single cells, so a
        # segment is a deliberate stretch of line instead of one stair step.
        # State carries whether the run that arrived was itself short, which is
        # what lets the staircase charge above see a pair rather than a step.
        queue = [(heuristic(start), 0.0, 0.0, start, -1, False)]
        best = {(start, -1, False): 0.0}
        Key = tuple[tuple[int, int], int, bool]
        previous: dict[Key, Key] = {}
        while queue:
            _, cost, travelled, cell, heading, was_short = heapq.heappop(queue)
            if cost > best.get((cell, heading, was_short), math.inf) + 1e-9:
                continue
            if cell == goal:
                return self._unwind(previous, cell, heading, was_short)
            for direction, (row_delta, column_delta) in enumerate(DIRECTIONS):
                turns = 0
                if heading >= 0:
                    turns = min((direction - heading) % 8, (heading - direction) % 8)
                    # A hairpin is never a readable metro line.
                    if turns >= 3:
                        continue
                span = self.step_km * (math.sqrt(2) if row_delta and column_delta else 1.0)
                run = cost + TURN_KM * turns
                distance = travelled
                current = cell
                for length in range(1, MAXIMUM_RUN_CELLS + 1):
                    following = (current[0] + row_delta, current[1] + column_delta)
                    if not passable(following):
                        break
                    run += span * 0.5 * (cell_cost(current) + cell_cost(following))
                    distance += span
                    current = following
                    # Optimistic: even running straight at the goal from here,
                    # this path would already be too long to be worth drawing.
                    if distance + heuristic(current) > ceiling:
                        break
                    short = length < MINIMUM_RUN_CELLS
                    penalty = (
                        SHORT_RUN_KM * (MINIMUM_RUN_CELLS - length)
                        if short and was_short
                        else 0.0
                    )
                    total = run + penalty
                    key = (current, direction, short)
                    if total < best.get(key, math.inf) - 1e-9:
                        best[key] = total
                        previous[key] = (cell, heading, was_short)
                        heapq.heappush(
                            queue,
                            (
                                total + heuristic(current),
                                total,
                                distance,
                                current,
                                direction,
                                short,
                            ),
                        )
        return None

    def _unwind(self, previous, cell, heading, was_short) -> list[tuple[int, int]]:
        """Rebuild the cell-by-cell path from the run-based search tree."""
        corners_reversed = [cell]
        key = (cell, heading, was_short)
        while key in previous:
            key = previous[key]
            corners_reversed.append(key[0])
        cells: list[tuple[int, int]] = []
        for start, end in zip(corners_reversed[::-1], corners_reversed[-2::-1]):
            rows = end[0] - start[0]
            columns = end[1] - start[1]
            steps = max(abs(rows), abs(columns))
            row_delta = (rows > 0) - (rows < 0)
            column_delta = (columns > 0) - (columns < 0)
            if not cells:
                cells.append(start)
            for index in range(1, steps + 1):
                cells.append((start[0] + row_delta * index, start[1] + column_delta * index))
        return cells or [cell]

    # -- reporting -------------------------------------------------------

    def straight_km(self, start: tuple[int, int], goal: tuple[int, int]) -> float:
        """Shortest octilinear run between two cells, ignoring terrain."""
        rows = abs(start[0] - goal[0])
        columns = abs(start[1] - goal[1])
        return (max(rows, columns) + (math.sqrt(2) - 1) * min(rows, columns)) * self.step_km

    def length_km(self, cells: list[tuple[int, int]]) -> float:
        """Plain drawn length of a lattice path, with no cost weighting."""
        total = 0.0
        for first, second in zip(cells, cells[1:]):
            diagonal = first[0] != second[0] and first[1] != second[1]
            total += self.step_km * (math.sqrt(2) if diagonal else 1.0)
        return total

    def water_km(self, cells: list[tuple[int, int]]) -> float:
        total = 0.0
        for first, second in zip(cells, cells[1:]):
            if self.is_land[first] and self.is_land[second]:
                continue
            diagonal = first[0] != second[0] and first[1] != second[1]
            total += self.step_km * (math.sqrt(2) if diagonal else 1.0)
        return total


def corners(cells: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Collapse collinear lattice steps down to the bends worth drawing."""
    if len(cells) < 3:
        return list(cells)
    result = [cells[0]]
    for index in range(1, len(cells) - 1):
        before, cell, after = cells[index - 1], cells[index], cells[index + 1]
        entering = (cell[0] - before[0], cell[1] - before[1])
        leaving = (after[0] - cell[0], after[1] - cell[1])
        if entering != leaving:
            result.append(cell)
    result.append(cells[-1])
    return result
