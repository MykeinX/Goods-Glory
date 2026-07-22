#!/usr/bin/env python3
"""
Advisory mirror of GameCatalog freight-flow derivation, for calibration only.

Canonical derivation lives in Swift (GameCatalog.deriveFlows); this script
re-implements the same formula so flow bands can be eyeballed and tuned without
building the app. If the two disagree, Swift wins — update this mirror.

Writes freight_flow_report.txt next to this script.
"""

from __future__ import annotations

import heapq
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"

# Mirror of code constants in GameCatalog (rules, not balance):
DESTINATIONS_PER_PRODUCT = 2
MAX_FLOWS_PER_CITY = 16
MIN_FLOWS_PER_CITY = 3


def city_distances(cities, nodes, roads):
    adjacency = defaultdict(list)
    for road in roads:
        adjacency[road["from"]].append((road["to"], road["distanceKm"]))
        adjacency[road["to"]].append((road["from"], road["distanceKm"]))
    city_by_node = {c["roadNodeID"]: c["id"] for c in cities}
    result = {}
    for city in cities:
        start = city["roadNodeID"]
        dist = {start: 0.0}
        heap = [(0.0, start)]
        reached = {}
        while heap:
            d, node = heapq.heappop(heap)
            if d > dist.get(node, float("inf")):
                continue
            if node in city_by_node:
                reached[city_by_node[node]] = d
            for neighbor, km in adjacency[node]:
                nd = d + km
                if nd < dist.get(neighbor, float("inf")):
                    dist[neighbor] = nd
                    heapq.heappush(heap, (nd, neighbor))
        result[city["id"]] = reached
    return result


def derive_flows(cities, markets_by_id, flow_config, distances):
    flows = []
    for origin in sorted(cities, key=lambda c: c["id"]):
        market = markets_by_id.get(origin["id"])
        if not market or not market["supply"]:
            continue
        reach = distances.get(origin["id"], {})
        budget = origin["population"] / 100_000 * flow_config["cityOutboundKgPerDayPer100k"]
        weight_sq_sum = sum(e["weight"] ** 2 for e in market["supply"])
        if weight_sq_sum <= 0:
            continue
        candidates = []
        for entry in market["supply"]:
            product_budget = budget * entry["weight"] ** 2 / weight_sq_sum
            scored = []
            for destination, km in reach.items():
                if destination == origin["id"]:
                    continue
                demand = next(
                    (d for d in markets_by_id[destination]["demand"]
                     if d["productID"] == entry["productID"]),
                    None,
                )
                if demand is None:
                    continue
                score = demand["weight"] / (1 + km / flow_config["distanceHalfWeightKm"])
                scored.append((destination, score))
            scored.sort(key=lambda x: (-x[1], x[0]))
            chosen = scored[:DESTINATIONS_PER_PRODUCT]
            score_sum = sum(s for _, s in chosen)
            if score_sum <= 0:
                continue
            for destination, score in chosen:
                rate = round(product_budget * score / score_sum)
                candidates.append({
                    "origin": origin["id"],
                    "product": entry["productID"],
                    "destination": destination,
                    "rate": rate,
                })
        candidates.sort(key=lambda f: (-f["rate"], f"{f['origin']}.{f['product']}.{f['destination']}"))
        kept = []
        for candidate in candidates[:MAX_FLOWS_PER_CITY]:
            if candidate["rate"] < 1:
                continue
            if len(kept) < MIN_FLOWS_PER_CITY or candidate["rate"] >= flow_config["minimumRatePerDayKg"]:
                kept.append(candidate)
        flows.extend(kept)
    return flows


def main() -> None:
    cities = json.loads((CATALOG / "cities.json").read_text())
    nodes = json.loads((CATALOG / "road_nodes.json").read_text())
    roads = json.loads((CATALOG / "roads.json").read_text())
    markets_by_id = {m["cityID"]: m for m in json.loads((CATALOG / "city_markets.json").read_text())}
    economy = json.loads((CATALOG / "economy.json").read_text())
    flow_config = economy["flows"]

    distances = city_distances(cities, nodes, roads)
    flows = derive_flows(cities, markets_by_id, flow_config, distances)

    lines = [f"{len(flows)} flows, config {flow_config}", ""]
    by_origin = defaultdict(list)
    for flow in flows:
        by_origin[flow["origin"]].append(flow)
    for city in sorted(cities, key=lambda c: c["id"]):
        outbound = by_origin.get(city["id"], [])
        total = sum(f["rate"] for f in outbound)
        budget = city["population"] / 100_000 * flow_config["cityOutboundKgPerDayPer100k"]
        lines.append(
            f"{city['id']}  pop {city['population']:,}  flows {len(outbound)}"
            f"  total {total / 1000:.1f} t/day  (budget {budget / 1000:.1f}, kept {total / budget:.0%})"
        )
        for flow in outbound[:5]:
            lines.append(f"    {flow['product']:24s} → {flow['destination']:22s} {flow['rate'] / 1000:5.1f} t/day")
        lines.append("")

    out = Path(__file__).resolve().parent / "freight_flow_report.txt"
    out.write_text("\n".join(lines))
    print(f"Wrote {len(flows)} flows → {out}")
    ratios = [
        sum(f["rate"] for f in by_origin.get(c["id"], []))
        / (c["population"] / 100_000 * flow_config["cityOutboundKgPerDayPer100k"])
        for c in cities
    ]
    print(f"kept-ratio min {min(ratios):.2f} max {max(ratios):.2f}")


if __name__ == "__main__":
    main()
