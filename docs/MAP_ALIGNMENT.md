# City map alignment — implemented 3 October 2026

All four maps now share a presentation layout for streets, road clicks, previews,
closures and vehicle movement. The previous profiles routed every edge through
building centers and access drives. Concatenating those edges made a vehicle
enter an intermediate shelter and retrace its driveway. Riverside also had
roof-center endpoints and shared road trunks outside real junctions.

The replacement separates each shelter's open network anchor from its building,
entrance, selection footprint and label anchor. Edges terminate at network
anchors. Multi-edge routes concatenate those paths once at the shared anchor;
there is no intermediate driveway animation. Shield endpoint detection now uses
the same network anchors.

## Editable sources and artwork

- `assets/maps/layouts/{riverside,twin_districts,lifeline,crossfire}.json` is the
  authoritative visual layout, in the existing 1000 × 700 world coordinate space.
  It includes centerlines, widths, reserved corridors, junction radii, closure
  fractions, landmark footprints, entrances, selection areas and label anchors.
- `assets/maps/*.png` contains the regenerated terrain/building layer. Original
  illustrations remain under `output/imagegen/`.
- `output/map-alignment/` retains accepted terrain layers, final layout guides,
  transparent editable SVG street layers and `PROMPTS.md`.
- `tools/build_map_layouts.py` validates the graph and footprint clearance and
  regenerates the guides/SVG layers from the JSON. It requires Pillow and does
  not modify scenario files or terrain images.
- `scripts/ui/city_map_profiles.gd` loads the layouts. `network_view.gd` draws
  asphalt, curbs and open junctions directly from them, then draws interaction
  overlays on those same paths. The terrain and all coordinates share one
  world-to-screen transform. Actual raster dimensions are **1499 × 1049**, not
  the previously assumed 1500 × 1050.

The geometry guides were authored first from the scenario node positions.
Built-in imagegen edited the city artwork around reserved empty road corridors.
Outputs were inspected rather than assumed accurate: rejected Crossfire passes
were replaced, and final anchors were refined within the resulting open plazas.
Simulation node positions, edges, logical edge lengths, depot stock, pressures,
costs, phases, scoring, routing, and the eight playthrough fixtures were not
changed. The refinements affect presentation only.

Landmark names and public status stay together near their building, avoid road
corridors, and use leader lines where needed. Offscreen landmarks do not leave
floating captions in a close view. Vehicles and barriers scale with the roadway.
Road details use a compact panel positioned away from the selected midpoint.

## Verification

`tests/test_city_art.gd`: **134,808 checks, zero failures**, run in the real
windowed game. All four maps were exercised at **1440 × 900** and **1200 × 800**:

- Exact edge coverage, correct endpoints and registered image dimensions.
- Separate building selection and network anchors; camera transform round trips.
- Forward/reverse centerlines and every possible two-edge transit through each
  junction; no duplicate joins or intermediate roof visits.
- No nonincident playable-edge intersections; road-width clearance from every
  registered landmark footprint; correct branch and closure-position hit tests.
- Names leave road branches visible; public pixels unchanged by hidden-pressure
  changes.
- Actual VERIFY deliveries from depot A across multiple edges, using production
  delivery plans and completing normally. Moving vehicles captured at overview
  and close zoom.
- Actual ISOLATE actions, their supply deliveries, previews and completed road
  closures. Barriers captured at overview and close zoom.

The combined terrain/street layers were visually reviewed at overview and close
zoom. Background views without operational overlays were also captured and
reviewed. Twin Districts has only its D-E canal crossing; Lifeline keeps its
single D-E district connection and visible F-G; Crossfire preserves both central
triangles and all five E branches, with its transfer building beside the plaza.
Riverside no longer shares accidental trunks or routes through building roofs.

Gameplay regression suites remain in place. Final suite results are recorded in
`output/map-alignment/verification.txt`. All eight scenario fixtures pass
(263 fixture assertions). Web exports include the new JSON layout resources.

Browser verification is **partial**: the local web export loaded and rendered
its main menu in the in-app browser. The attempted Dev Mode click was rejected
by automatic approval review because the review service hit a usage limit.
Interactive browser deliveries/closures were therefore not verified; native
windowed gameplay verification completed. This was a review-service failure,
not an observed game failure.

## Before/after evidence

`docs/screenshots/map-alignment/before/` contains all four original maps at both
viewport sizes, with overview and fixed close camera states. `after/` contains
matching views plus unobstructed backgrounds, selections, previews, moving
vehicles and completed closures. The close comparison uses world camera center
(500,350), zoom 2.6; overview uses the world center, zoom 1. Riverside's old special
crop was replaced by the common full-world framing.

- [Riverside comparison](screenshots/map-alignment/riverside_01_v2-comparison.png)
- [Twin Districts comparison](screenshots/map-alignment/twin_districts_02_v1-comparison.png)
- [Lifeline comparison](screenshots/map-alignment/lifeline_03_v1-comparison.png)
- [Crossfire comparison](screenshots/map-alignment/crossfire_04_v1-comparison.png)

No commit, push or deployment was made. Unrelated working-tree changes were
preserved. Raster artwork is still illustrative: automated geometry checks cover
registered footprints and road topology; visual inspection supplies the check
against decorative buildings and terrain.
