# World geography sources

Strategic world land and inland-water silhouettes are generated offline by
`generate_world_geography.py`. Coastline detail is intentionally coarse
(Natural Earth 1:110m + ~6 km Douglas–Peucker) — enough to read continents,
not cove-level cartography. Fill/coast colors match the design mockup
(`#16283F` / `#2B4463` in `lojistik-oyunu-tasar-m-konsepti`); gameplay uses
continuous land masses rather than per-country political polygons.

Pinned inputs (downloaded into `scripts/.cache/natural_earth/` on first run):

- Natural Earth 110m land GeoJSON:
  `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_land.geojson`
- Natural Earth 110m lakes GeoJSON:
  `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_lakes.geojson`
- Natural Earth 50m admin-0 land boundary lines GeoJSON:
  `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_boundary_lines_land.geojson`

Processing notes:

- Antarctica is omitted (Mercator distortion; not used by gameplay).
- Antimeridian rings are split only when coordinates actually jump ±180°.
- NE Asia (Chukotka) remnants are stitched into the Eurasian land ring at
  lon>180 so Siberia completes continuously on the right (no seam).
- Country borders use 50m source + ~2 km simplify (closer to reality than land).
- Runtime draws all borders as one static `SKShapeNode` (no zoom rebuild).
- Cities and roads are unchanged; regenerate only geography:

```sh
python3 -B scripts/generate_world_geography.py
```

Optional:

```sh
python3 -B scripts/generate_world_geography.py --refresh
python3 -B scripts/generate_world_geography.py --output /path/to/map_geography.json
```
