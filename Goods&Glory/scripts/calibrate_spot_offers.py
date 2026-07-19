#!/usr/bin/env python3
"""Spot-offer calibration against bundled catalog JSON (freight model).

Mirrors SimulationEngine freight payout: rate × km × fillFactor × urgency.
"""

from __future__ import annotations

import heapq
import json
import statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"
OUT = Path(__file__).resolve().parent / "goodsglory_offer_calibration.txt"


def load(name: str):
    return json.loads((CATALOG / name).read_text())


def build_graph(roads):
    adj = defaultdict(list)
    for road in roads:
        d = float(road["distanceKm"])
        adj[road["from"]].append((road["to"], d))
        adj[road["to"]].append((road["from"], d))
    return adj


def shortest_km(adj, origin_node: str, dest_node: str) -> float | None:
    if origin_node == dest_node:
        return 0.0
    dist = {origin_node: 0.0}
    pq = [(0.0, origin_node)]
    seen = set()
    while pq:
        d, u = heapq.heappop(pq)
        if u in seen:
            continue
        seen.add(u)
        if u == dest_node:
            return d
        for v, w in adj[u]:
            nd = d + w
            if nd < dist.get(v, float("inf")):
                dist[v] = nd
                heapq.heappush(pq, (nd, v))
    return None


def travel_minutes(distance_km: float, speed_kmh: float) -> int:
    return max(1, int(round(distance_km / speed_kmh * 60)))


def task_cost(total_km: float, task_minutes: int, cpk: float, dph: float) -> int:
    return int(round(total_km * cpk + task_minutes / 60.0 * dph))


def freight_payout(road_km: float, util: float, vehicle, eco, multiplier: float = 1.0) -> int:
    fill = eco["fillFloor"] + (1.0 - eco["fillFloor"]) * max(0.0, min(1.0, util))
    return max(1, int(round(vehicle["freightRatePerKm"] * road_km * fill * multiplier)))


def stats(label: str, values: list[float]) -> str:
    if not values:
        return f"{label}: (empty)"
    s = sorted(values)
    n = len(s)

    def pct(p):
        return s[min(n - 1, max(0, int((n - 1) * p)))]

    return (
        f"{label}: n={n} min={s[0]:.1f} p25={pct(0.25):.1f} med={statistics.median(s):.1f} "
        f"p75={pct(0.75):.1f} max={s[-1]:.1f} mean={sum(s)/n:.1f}"
    )


def short(cid: str) -> str:
    return cid.removeprefix("us_")


def main() -> None:
    cities = load("cities.json")
    roads = load("roads.json")
    vehicles = load("vehicle_types.json")
    eco = load("economy.json")
    van = next(v for v in vehicles if v["id"] == "cargo_van")
    adj = build_graph(roads)
    by_id = {c["id"]: c for c in cities}
    starters = [c for c in cities if c.get("isStarterCity")]

    lines: list[str] = []
    lines.append("=== SPOT OFFER CALIBRATION (freight model) ===")
    lines.append(
        f"cities={len(cities)} starters={len(starters)} "
        f"fillFloor={eco['fillFloor']} vanRate={van['freightRatePerKm']}/km "
        f"fixed/day={van['fixedCostPerDay']}"
    )

    utils = [0.5, 0.75, 1.0]
    tiers = {t["id"]: t["multiplier"] for t in eco["urgencyTiers"]}

    samples = []
    for origin in starters:
        for dest in cities:
            if dest["id"] == origin["id"]:
                continue
            road = shortest_km(adj, origin["roadNodeID"], dest["roadNodeID"])
            if road is None or road > 2500:
                continue
            for util in utils:
                for tier_id, mult in tiers.items():
                    pay = freight_payout(road, util, van, eco, mult)
                    mins = (
                        eco["loadingMinutes"]
                        + travel_minutes(road, van["speedKmh"])
                        + eco["unloadingMinutes"]
                    )
                    cost = task_cost(road, mins, van["costPerKm"], van["driverCostPerHour"])
                    samples.append(
                        {
                            "origin": origin["id"],
                            "dest": dest["id"],
                            "road": road,
                            "util": util,
                            "tier": tier_id,
                            "payout": pay,
                            "profit": pay - cost,
                            "rate": pay / road,
                        }
                    )

    lines.append("")
    lines.append("--- A. Van direct (no deadhead) profits ---")
    for util in utils:
        subset = [s for s in samples if s["util"] == util and s["tier"] == "normal"]
        lines.append(stats(f"util={util:.2f} normal profit $", [float(s["profit"]) for s in subset]))
        lines.append(stats(f"util={util:.2f} normal $/km", [s["rate"] for s in subset]))

    lines.append("")
    lines.append("--- B. Starter HQ short lanes (road < 800 km, util=0.75 normal) ---")
    for hq in sorted(starters, key=lambda c: c["id"]):
        lanes = [
            s
            for s in samples
            if s["origin"] == hq["id"] and s["util"] == 0.75 and s["tier"] == "normal" and s["road"] < 800
        ]
        if not lanes:
            lines.append(f"{short(hq['id'])}: no short lanes")
            continue
        med = statistics.median(s["profit"] for s in lanes)
        lines.append(
            f"{short(hq['id'])}: short lanes n={len(lanes)} medProfit=${med:.0f} "
            f"road[{min(s['road'] for s in lanes):.0f}–{max(s['road'] for s in lanes):.0f}]"
        )

    # Second-van affordability sketch: ~2 profitable jobs/day for 14 days
    lines.append("")
    lines.append("--- C. Second-vehicle sketch (Chicago, util=0.75 normal, no deadhead) ---")
    chi = next(c for c in starters if c["id"] == "us_chicago")
    chi_lanes = [
        s
        for s in samples
        if s["origin"] == chi["id"] and s["util"] == 0.75 and s["tier"] == "normal"
    ]
    med_profit = statistics.median(s["profit"] for s in chi_lanes)
    daily_fixed = van["fixedCostPerDay"]
    net_per_job = med_profit
    jobs_per_day = 2
    two_week = 14 * (jobs_per_day * net_per_job - daily_fixed)
    lines.append(f"median job profit ${med_profit:.0f}, fixed/day ${daily_fixed}")
    lines.append(f"~{jobs_per_day} jobs/day × 14d net ≈ ${two_week:.0f} (van price ${van['purchasePrice']})")

    text = "\n".join(lines) + "\n"
    OUT.write_text(text)
    print(text)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
