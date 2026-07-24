# World board art

The game board silhouette is **authored Mini Metro–style art**.

- Source: `scripts/assets/board_art_reference.png` (white land on soft blue sea)
- Importer: `python3 -B scripts/import_board_art.py`
- Output: `Resources/Catalog/map_board_silhouette.json`

The importer:

1. Separates near-white land from blue water (keeps soft AA with land)
2. Traces high-detail contours and inland-sea holes
3. Light Douglas–Peucker + collinear merge only — does **not** force H/V/45°
   snaps, so authored curves and uneven angles stay intact
4. Maps pixels to lat/lon for the board projection. City lat/lon in
   `cities.json` is authored in this same board space so pins sit on the art.

SpriteKit applies a fixed corner radius and a soft drop shadow at render time.
Country borders are not drawn.

Seed / refresh the reference PNG then re-import:

```sh
python3 -B scripts/import_board_art.py --seed-from /path/to/reference.png
```

## Road geometry

The silhouette is also the land mask for road layout, so **re-run the network
generator after every board re-import**:

```sh
python3 -B scripts/generate_trade_network.py
```

- Lattice + land-constrained A*: `scripts/map_grid.py`
- Outputs: `road_nodes.json` (one node per city), `roads.json`,
  `road_geometry.json`, and snapped `cities.json` coordinates

Every city snaps onto one shared octilinear lattice (45 km pitch, square in
projected space). Each road is then an A* path over that lattice with a turn
penalty, a short-run penalty and a coastline penalty, so segments are long,
horizontal / vertical / 45°, and inland. Water cells are impassable: "roads
never cross the sea" is structural, not a scoring heuristic. There are no
junction / steering nodes — the graph is city-to-city only.

Two knobs matter when the board changes:

- City lat/lon in `cities.json` is a neighbourhood hint; the lattice pulls each
  onto the nearest free land cell and towards alignment with the cities it
  connects to. A city one cell off its trunk is what turns a straight corridor
  into a visible wobble.
- `WATER_CROSSINGS` lists the roads allowed to leave land, with a km budget.
  London is an island on this board, so London–Paris is a declared fixed link.
  The generator fails rather than silently routing a road across water.

## City placement

`cities.json` coordinates are board-space, not raw WGS84. They are authored to
match recognizable board landmarks while keeping real relative order:

| City | Board landmark |
|---|---|
| Los Angeles | Pacific west coast |
| Seattle | Pacific NW, north of Los Angeles |
| New York | Atlantic east tip |
| Miami | SE peninsula tip |
| Chicago / Detroit | Great Lakes inlet |
| Dallas / Houston / Denver | interior Sun Belt / Rockies relative to LA–Chicago |
| London | SE of the UK island |
| Madrid | Iberian interior, west of Paris |
| Paris / Frankfurt / Berlin | central Europe north–south stack |
| Milan / Rome | Italian peninsula |
| Warsaw | east of Berlin, west of Istanbul |
| Istanbul | SW tip of the Black Sea hole (Anatolia / Bosphorus) |

After editing city hints, re-run `generate_trade_network.py` so pins snap onto
the shared lattice and road geometry is rebuilt.
