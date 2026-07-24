# Contiguous-US map sources

`generate_us_map.py` produces the US city roster (`cities.json`) and market
profiles (`city_markets.json`) from the pinned sources below. The routing
graph (`road_nodes.json` + `roads.json`) is **not** generated from TIGER
anymore: the shipped network is the authored world trade-corridor graph from
`generate_trade_network.py`, which covers all continents with a sparse,
metro-style line set. Runtime derives its shared schematic corridors from
that graph.

Pinned inputs:

- US Census TIGER/Line 2025 Primary Roads:
  `https://www2.census.gov/geo/tiger/TIGER2025/PRIMARYROADS/tl_2025_us_primaryroads.zip`
- US Census 2025 Places Gazetteer:
  `https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/2025_Gaz_place_national.zip`
- US Census 2025 metropolitan population estimates:
  `https://www2.census.gov/programs-surveys/popest/tables/2020-2025/metro/totals/cbsa-met-est2025-pop.xlsx`
- BEA 2023 metropolitan Regional Price Parities:
  `https://www.bea.gov/sites/default/files/2024-12/rpp1224.pdf`
- FHWA FY2026 Q1 Urban Congestion Report:
  `https://ops.fhwa.dot.gov/perf_measurement/ucr/reports/fy2026_q1.pdf`

The 22 hubs are a sparse national skeleton of well-known major metros rather
than a dense top-N ranking: nearby secondary cities are omitted so each region
has one clear hub, leaving room for future world cities on the same map.

The first road slice contains one- and two-digit Interstate routes plus the
few auxiliary Interstate corridors needed by selected metro areas. Route names
are build-time matching data only and are not stored in `RoadDefinition` or the
runtime JSON. Known TIGER freeway-name aliases are joined to avoid artificial
gaps. Genuine current Interstate termini and unfinished corridors remain
genuine termini.

Generate the catalog after extracting the source archives into one directory:

```sh
python3 -B scripts/generate_us_map.py \
  --source-dir /path/to/us_sources \
  --output-dir 'Goods&Glory/Resources/Catalog'
```

Every regional catalog ID is country-namespaced (`us_...`). Future regions can
be generated independently and merged into the same runtime JSON contract;
SpriteKit and the simulation continue to consume the canonical road graph
without region-specific rules.
