#!/usr/bin/env python3
"""
Human-readable audit of city_markets.json: per-city top supply/demand profile.

Run after generate_city_markets.py and eyeball the result: every city's top
supply entries should read like its real economic identity (Detroit →
automotive, Houston → petrochemicals, Dhaka → apparel). Writes
city_market_audit.txt next to this script.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Goods&Glory" / "Resources" / "Catalog"
TOP = 5


def main() -> None:
    cities = {c["id"]: c for c in json.loads((CATALOG / "cities.json").read_text())}
    markets = json.loads((CATALOG / "city_markets.json").read_text())

    lines: list[str] = []
    for market in sorted(markets, key=lambda m: m["cityID"]):
        city = cities[market["cityID"]]
        lines.append(f"{market['cityID']}  (pop {city['population']:,})")
        supply = ", ".join(f"{e['productID']}:{e['weight']}" for e in market["supply"][:TOP])
        demand = ", ".join(f"{e['productID']}:{e['weight']}" for e in market["demand"][:TOP])
        lines.append(f"  supply: {supply}")
        lines.append(f"  demand: {demand}")
        lines.append("")

    out = Path(__file__).resolve().parent / "city_market_audit.txt"
    out.write_text("\n".join(lines))
    print(f"Wrote audit for {len(markets)} cities → {out}")


if __name__ == "__main__":
    main()
