# Contiguous-US research sources

Shipped cities live in `cities.json`. Markets and the sparse metro-style road
backbone are produced by `generate_city_markets.py` and
`generate_trade_network.py`. City placement and the road graph will be
re-authored against the board art in a later pass.

Pinned Census / FHWA inputs useful for future US expansion research:

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

Regional catalog IDs stay country-namespaced (`us_...`). Future regions merge
into the same runtime JSON contract; SpriteKit and the simulation consume the
canonical road graph without region-specific rules.
