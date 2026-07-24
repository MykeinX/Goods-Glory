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
# A run shorter than this many cells reads as a wobble rather than a bend, so
# the search pays for every cell it falls short. Both numbers are in cells/km.
MINIMUM_RUN_CELLS = 4
SHORT_RUN_KM = 180.0
# Cap on how far one expansion may run. Long enough to cross a continent leg.
MAXIMUM_RUN_CELLS = 48
# A city that shares a row, column or diagonal with a neighbour lets the
# corridor pass without a bend. Keep this mild so authored geography wins.
ALIGNMENT_BONUS_KM = 0.55 * STEP_KM
# Roads drift inland instead of tracing the coastline pixel by pixel.
COAST_MARGIN_KM = STEP_KM * 2.6
COAST_PENALTY = 2.6
# Multiplier applied to water cells for roads that declared a crossing.
CROSSING_WATER_COST = 6.0

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
        span = max(4, int(400 / self.step_km) + 2)
        best: tuple[float, float, tuple[int, int]] | None = None
        for row_delta in range(-span, span + 1):
            for column_delta in range(-span, span + 1):
                cell = (row + row_delta, column + column_delta)
                if not self._inside(cell) or not self.is_land[cell]:
                    continue
                if cell in taken:
                    continue
                distance = math.dist(self.point(cell), target)
                # A tie between two equally close cells goes to the one further
                # from the coast, which keeps pins off one-pixel headlands.
                inland = min(float(self.inland_km[cell]), 2.5 * self.step_km)
                score = distance - 0.30 * inland
                score -= ALIGNMENT_BONUS_KM * self._alignment(cell, aligned_with)
                if best is None or score < best[0]:
                    best = (score, distance, cell)
        if best is None:
            raise ValueError(f"no free land cell near ({latitude}, {longitude})")
        return best[2], best[1]

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
    ) -> list[tuple[int, int]] | None:
        """Cheapest octilinear lattice path, penalising turns and coastlines."""
        if not (self._inside(start) and self._inside(goal)):
            return None

        def passable(cell: tuple[int, int]) -> bool:
            return self._inside(cell) and (self.is_land[cell] or may_cross_water)

        def cell_cost(cell: tuple[int, int]) -> float:
            if not self.is_land[cell]:
                return CROSSING_WATER_COST
            shallow = max(0.0, 1.0 - float(self.inland_km[cell]) / COAST_MARGIN_KM)
            return 1.0 + COAST_PENALTY * shallow * shallow

        def heuristic(cell: tuple[int, int]) -> float:
            rows = abs(cell[0] - goal[0])
            columns = abs(cell[1] - goal[1])
            return (max(rows, columns) + (math.sqrt(2) - 1) * min(rows, columns)) * self.step_km

        if not passable(start) or not passable(goal):
            return None

        # Expansion is by whole straight runs rather than single cells, so a
        # segment is a deliberate stretch of line instead of one stair step.
        queue = [(heuristic(start), 0.0, start, -1)]
        best = {(start, -1): 0.0}
        previous: dict[tuple[tuple[int, int], int], tuple[tuple[int, int], int]] = {}
        while queue:
            _, cost, cell, heading = heapq.heappop(queue)
            if cost > best.get((cell, heading), math.inf) + 1e-9:
                continue
            if cell == goal:
                return self._unwind(previous, cell, heading)
            for direction, (row_delta, column_delta) in enumerate(DIRECTIONS):
                turns = 0
                if heading >= 0:
                    turns = min((direction - heading) % 8, (heading - direction) % 8)
                    # A hairpin is never a readable metro line.
                    if turns >= 3:
                        continue
                span = self.step_km * (math.sqrt(2) if row_delta and column_delta else 1.0)
                run = cost + TURN_KM * turns
                current = cell
                for length in range(1, MAXIMUM_RUN_CELLS + 1):
                    following = (current[0] + row_delta, current[1] + column_delta)
                    if not passable(following):
                        break
                    run += span * 0.5 * (cell_cost(current) + cell_cost(following))
                    current = following
                    # Only the run that lands here pays the short-run charge;
                    # a longer continuation of the same run is charged less.
                    total = run + SHORT_RUN_KM * max(0, MINIMUM_RUN_CELLS - length)
                    key = (current, direction)
                    if total < best.get(key, math.inf) - 1e-9:
                        best[key] = total
                        previous[key] = (cell, heading)
                        heapq.heappush(
                            queue, (total + heuristic(current), total, current, direction)
                        )
        return None

    def _unwind(self, previous, cell, heading) -> list[tuple[int, int]]:
        """Rebuild the cell-by-cell path from the run-based search tree."""
        corners_reversed = [cell]
        key = (cell, heading)
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
