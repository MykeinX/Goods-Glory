# World map sources

`generate_world_geography.py` produces the two presentation atlases used by
SpriteKit:

- `map_board_silhouette.json`: low-detail land polygons for the rounded board.
- `map_boundaries.json`: country-border lines at final render detail.

Both outputs are generated globally from the same Natural Earth 1:50m source.
The whole world therefore receives one detail budget; no region has a
hand-tuned or higher-resolution exception.

Pinned inputs:

- Natural Earth 50m land GeoJSON:
  `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_land.geojson`
- Natural Earth 50m admin-0 land boundary lines GeoJSON:
  `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_boundary_lines_land.geojson`

Processing rules:

- Antarctica is omitted.
- Small island confetti is removed globally by one footprint threshold.
- Land is simplified to roughly 900 vertices for the entire board.
- Country borders are simplified once offline; SpriteKit does not simplify them again.
- Coast rounding is a renderer concern and does not mutate geographic data.
- Cities and transport graphs are independent. Road traversal is land because
  the Domain road graph says so, not because presentation performs polygon
  collision against the silhouette.

Generate both resources:

```sh
python3 -B scripts/generate_world_geography.py
```

Refresh pinned source caches:

```sh
python3 -B scripts/generate_world_geography.py --refresh
```
