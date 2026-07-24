# World board art

The game board silhouette is **authored Mini Metro–style art**.

- Source: `scripts/assets/board_art_reference.png` (white land on soft blue sea)
- Importer: `python3 -B scripts/import_board_art.py`
- Output: `Resources/Catalog/map_board_silhouette.json`

The importer:

1. Thresholds white land (drops letterbox frame noise)
2. Traces high-detail contours and inland-sea holes
3. Snaps every coast edge to the eight board directions (H / V / 45°) and
   merges collinear runs — this is the Mini Metro look
4. Maps pixels to lat/lon for the board projection. City lat/lon in
   `cities.json` is authored in this same board space so pins sit on the art.

SpriteKit only applies a small fixed corner radius and a soft drop shadow at
render time. Country borders are not drawn.

Seed / refresh the reference PNG then re-import:

```sh
python3 -B scripts/import_board_art.py --seed-from /path/to/reference.png
```
