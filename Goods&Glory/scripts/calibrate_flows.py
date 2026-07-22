#!/usr/bin/env python3
"""
Lane economics: does serving a flow actually pay?

Mirrors SimulationEngine's pricing so a balance change can be checked in a
second instead of a play session. Swift is canonical; if the two disagree,
update this mirror.

The question it answers is the one a player asks on turn one: I bought a truck
and put it on a lane — am I making money, and how much better does it get if I
fill the return leg?

Writes flow_calibration.txt next to this script.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"
MINUTES_PER_DAY = 24 * 60


def load(name):
    return json.loads((CATALOG / f"{name}.json").read_text())


def travel_minutes(km, speed):
    return max(1, round(km / speed * 60))


def task_cost(km, minutes, v):
    return round(km * v["costPerKm"] + minutes / 60 * v["driverCostPerHour"])


def haul_cost(km, v, load_min, unload_min):
    minutes = load_min + travel_minutes(km, v["speedKmh"]) + unload_min
    running = task_cost(km, minutes, v)
    ownership = v["fixedCostPerDay"] * minutes / MINUTES_PER_DAY
    return round(running + ownership), minutes


def payout(km, v, econ, utilisation, lane_price=1.0, presence=1.0, competition=1.0):
    load_min = econ["loadingMinutes"]
    unload_min = econ["unloadingMinutes"]
    loaded, _ = haul_cost(km, v, load_min, unload_min)
    return_minutes = travel_minutes(km, v["speedKmh"])
    empty_return = task_cost(km, return_minutes, v)
    lane_cost = loaded + empty_return * econ["emptyReturnSharePercent"] / 100
    billable = max(econ["fillFloor"], utilisation)
    margin = econ["spotMarginPercent"] / 100 * lane_price * presence * competition
    return round(lane_cost * billable * (1 + margin))


def lap(km, v, econ, utilisation, backhaul_utilisation=0.0):
    """One out-and-back lap: revenue, cost and the standing cost of its hours."""
    load_min, unload_min = econ["loadingMinutes"], econ["unloadingMinutes"]
    one_way = travel_minutes(km, v["speedKmh"])
    lap_minutes = 2 * (one_way + load_min + unload_min)

    revenue = payout(km, v, econ, utilisation)
    if backhaul_utilisation > 0:
        revenue += payout(km, v, econ, backhaul_utilisation)

    running = 2 * task_cost(km, one_way + load_min + unload_min, v)
    standing = v["fixedCostPerDay"] * lap_minutes / MINUTES_PER_DAY
    return revenue, running, round(standing), lap_minutes


def main() -> None:
    econ = load("economy")
    vehicles = {v["id"]: v for v in load("vehicle_types")}
    lines: list[str] = []

    lines.append("=== LANE ECONOMICS ===")
    lines.append(
        f"spotMargin {econ['spotMarginPercent']}%  fillFloor {econ['fillFloor']}  "
        f"emptyReturnShare {econ['emptyReturnSharePercent']}%"
    )
    lines.append("")
    lines.append("lap = out loaded + back empty, unless a backhaul is noted")
    lines.append(f"{'vehicle':11s} {'km':>5s} {'fill':>5s} {'revenue':>9s} {'running':>9s} "
                 f"{'standing':>9s} {'NET/lap':>9s} {'NET/day':>9s}")

    for vid in ["cargo_van", "box_truck", "semi_truck"]:
        v = vehicles[vid]
        for km in (250, 500, 860):
            for fill in (0.5, 1.0):
                revenue, running, standing, minutes = lap(km, v, econ, fill)
                net = revenue - running - standing
                per_day = round(net * MINUTES_PER_DAY / minutes)
                lines.append(
                    f"{vid:11s} {km:5d} {fill:5.0%} {revenue:9d} {-running:9d} "
                    f"{-standing:9d} {net:9d} {per_day:9d}"
                )
        lines.append("")

    lines.append("=== THE REWARD FOR A BALANCED LANE (860 km, full both ways) ===")
    for vid in ["cargo_van", "box_truck", "semi_truck"]:
        v = vehicles[vid]
        one_way_rev, running, standing, minutes = lap(860, v, econ, 1.0)
        both_rev, running_b, standing_b, minutes_b = lap(860, v, econ, 1.0, backhaul_utilisation=1.0)
        empty_net = one_way_rev - running - standing
        both_net = both_rev - running_b - standing_b
        lines.append(
            f"{vid:11s} empty return {empty_net:+7d}/lap → with backhaul {both_net:+7d}/lap "
            f"({both_net - empty_net:+d})"
        )

    lines.append("")
    lines.append("=== FIRST HOUR: can the opening vehicle pay for itself? ===")
    for vid in ["cargo_van", "box_truck"]:
        v = vehicles[vid]
        _, _, _, minutes = lap(500, v, econ, 1.0)
        revenue, running, standing, _ = lap(500, v, econ, 1.0)
        net_day = (revenue - running - standing) * MINUTES_PER_DAY / minutes
        payback = v["purchasePrice"] / net_day if net_day > 0 else float("inf")
        lines.append(
            f"{vid:11s} price ${v['purchasePrice']:,} · net ${net_day:,.0f}/day · "
            + (f"pays for itself in {payback:.0f} days" if net_day > 0 else "NEVER PAYS BACK")
        )

    out = Path(__file__).resolve().parent / "flow_calibration.txt"
    out.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
