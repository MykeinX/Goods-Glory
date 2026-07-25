# World board

The board silhouette is **generated from real coastline data and stylised in
code**. It is not a traced drawing.

- Source: `scripts/assets/ne_50m_land.geojson` and `ne_50m_lakes.geojson`
  (Natural Earth 1:50m, public domain)
- Builder: `python3 -B scripts/build_board.py [--preview]`
- Output: `Resources/Catalog/map_board_silhouette.json`, in **real WGS84**

`scripts/assets/board_art_reference.png` is kept as a **style** reference only.
It was once the geometric source, and that was the mistake this pipeline
exists to correct: a 1024x576 decorative map cannot be registered to the globe
better than a few hundred km, which put Miami 495 km inland at Jacksonville and
left Houston and New York off the land mask entirely. Port cities are the ones
a logistics game needs, and they were the ones the art destroyed.

The builder:

1. Rasterises land in board-projected space, each ring drawn at -360/0/+360 so
   the Pacific rim arrives whole instead of split down the dateline
2. **Closes each land mass on its own**, filling its bays without ever bridging
   a strait it can see — Dover is 34 km and survives untouched, with no list
   to maintain
3. Punches inland water above `MIN_HOLE_KM2`, after closing so a lake can never
   be filled in and then traced as land
4. Opens, to drop spits and islets thinner than a landmark
5. **Carves the authored `STRAITS`** (see below)
6. Simplifies with an **absolute** km tolerance, then **regularises to
   octilinear**: every coast runs H, V or exactly 45°, the same grammar the
   road lattice uses, which is what makes coast and road read as one board
7. Clips needles — capes whose two sides double back — because a fixed-radius
   round has no room to soften one and it stays a hard point

## Straits

Gibraltar is 14 km and the Bosphorus is 700 m: narrower than a pixel at any
raster this board can afford, so they arrive **already fused** in the source
and no care in the morphology recovers them. They are authored in `STRAITS`.

That is not a workaround. At board scale a 700 m channel has to be drawn far
wider than life to exist at all — a cartographic decision, the same one Mini
Metro makes. The scale is a deliberate lie; the behaviour is real:

- Each is carved at least one lattice cell wide, so it blocks a road as well as
  reading as water. A road that must cross one declares itself in
  `WATER_CROSSINGS`, exactly as London–Paris already does — a bridge *is* a
  declared water crossing.
- They are what will make sea routes work. Carving Gibraltar is why the
  Mediterranean is open water connected to the Atlantic rather than an enclosed
  hole, so a ship can reach it.

Adding one is a line in `STRAITS`: a centre line in real WGS84.

Corner rounding is not baked in — `GameMapScene+Terrain` strokes these rings
with a fixed iOS-style radius. Country borders are not drawn.

## Road geometry

The silhouette is also the land mask for road layout, so **re-run the network
generator after every board rebuild**:

```sh
python3 -B scripts/build_board.py && python3 -B scripts/generate_trade_network.py
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

- `MAXIMUM_SNAP_KM` caps how far a pin may leave its authored coordinate. The
  inland and alignment bonuses are tie-breakers held below one cell, so neither
  can buy a straighter line at the cost of putting a city in the wrong country.
  They used to be able to, and Miami left Florida to line up with Atlanta.
- `WATER_CROSSINGS` lists the roads allowed to leave land, with a km budget.
  Britain is an island, so London–Paris is a declared fixed link. The generator
  fails rather than silently routing a road across water.

## The board holds its cities

Stylising moves a coast: 70 km of simplification plus up to 105 km of octilinear
drift can cut a diagonal coastline well inland. A city can therefore sit on land
in the raster and still be at sea in the rings that ship — Rome and Miami both
did, and the check that missed it was looking at the raster.

So `trace_holding_cities` tests every anchor against the **traced rings**, and
where one falls outside it restores the real coastline around that city and
retraces, until the board contains the cities it was built for.

Where even that is not enough the build **stops and names the city**. It does
not quietly place it 200 km inland. The fix is a product decision, not a
geometry one: move the anchor onto the coast the board draws, or drop that city
and use another in the same region.

## City placement

`scripts/city_anchors.json` is the source of truth, in **real WGS84**. The board
is built from the same real coastline, so a real coordinate needs no correction
to land on the right coast — there is no registration step and no nudge field.

`cities.json` carries only the snapped lattice result and is an **output**.
Editing a coordinate there is lost on the next run.

To add a city: add its real latitude/longitude to `city_anchors.json`, attach it
to one or two nearby cities in `CORRIDORS`, and re-run the generator.
