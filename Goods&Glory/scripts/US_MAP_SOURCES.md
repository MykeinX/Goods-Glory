# Contiguous-US map sources

The bundled US slice is generated offline by `generate_us_map.py`. It is a
strategic game map, not a navigation database: divided carriageways and
sub-kilometre bends are collapsed, while real corridor shapes, junctions and
distances remain the canonical source for routing and SpriteKit rendering.

Pinned inputs:

- US Census TIGER/Line 2025 Primary Roads:
  `https://www2.census.gov/geo/tiger/TIGER2025/PRIMARYROADS/tl_2025_us_primaryroads.zip`
- US Census 2025 1:5m nation and state cartographic boundaries:
  `https://www2.census.gov/geo/tiger/GENZ2025/kml/cb_2025_us_nation_5m.zip`
  and
  `https://www2.census.gov/geo/tiger/GENZ2025/kml/cb_2025_us_state_5m.zip`
- US Census 2025 Places Gazetteer:
  `https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/2025_Gaz_place_national.zip`
- US Census 2025 metropolitan population estimates:
  `https://www2.census.gov/programs-surveys/popest/tables/2020-2025/metro/totals/cbsa-met-est2025-pop.xlsx`
- BEA 2023 metropolitan Regional Price Parities:
  `https://www.bea.gov/sites/default/files/2024-12/rpp1224.pdf`
- FHWA FY2026 Q1 Urban Congestion Report:
  `https://ops.fhwa.dot.gov/perf_measurement/ucr/reports/fy2026_q1.pdf`

The 40 hubs are deliberately geography-balanced rather than a strict top-40
ranking: a smaller city is omitted when it would overlap a nearby larger hub,
and a major hub in an otherwise empty region is preferred.

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
