# Headstock art — designer guide

Each instrument's headstock is described by a small JSON file in this folder
plus (optionally) an SVG silhouette in the asset catalog. **No code changes** are
needed to add or restyle a head.

The tuning **pegs are drawn live by the app** (they change color as you tune and
are tappable), so the artwork is the **silhouette only** — the pegs are placed on
top using the coordinates in the JSON.

## To add / restyle a head

1. **Draw the silhouette** in any vector tool (Figma, Illustrator, Sketch…).
   - Just the head outline/body. Do **not** draw the tuning pegs.
   - Use a canvas whose width ÷ height equals the `aspectRatio` you'll set below
     (the standard guitar uses `0.66` — taller than wide).
   - Export as **SVG**.

2. **Import the SVG** into `Assets.xcassets`:
   - Drag it in, then in the Attributes inspector set **"Preserve Vector Data"**
     and **Scales: Single Scale** so it stays crisp at any size.
   - Note the asset name you gave it (e.g. `headstock-guitar`).

3. **Write the JSON** (this folder), named after the instrument, e.g.
   `guitar.json`:

   ```json
   {
     "artAsset": "headstock-guitar",   // asset name from step 2, or null for the
                                        // built-in procedural shape
     "aspectRatio": 0.66,              // width ÷ height of your canvas
     "pegs": [                          // one entry per string, LOW → HIGH
       { "x": 0.24, "y": 0.67 },        // string 0 (low E): bottom-left
       { "x": 0.24, "y": 0.46 },        // string 1 (A):     mid-left
       { "x": 0.24, "y": 0.25 },        // string 2 (D):     top-left
       { "x": 0.76, "y": 0.25 },        // string 3 (G):     top-right
       { "x": 0.76, "y": 0.46 },        // string 4 (B):     mid-right
       { "x": 0.76, "y": 0.67 }         // string 5 (high E): bottom-right
     ]
   }
   ```

   - `x` / `y` are **normalized** to the head's box: `0,0` = top-left, `1,1` =
     bottom-right. Read them off your design (peg-center ÷ canvas size) so each
     dot lands exactly on its tuner post in the art.
   - Peg order is **string order, low to high** — the same order the tuner uses.

That's it. `artAsset: null` (as in the shipped `guitar.json`) uses the built-in
procedural head, so the tuner works before any SVG is made.
