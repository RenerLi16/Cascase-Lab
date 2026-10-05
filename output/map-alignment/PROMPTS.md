# Map artwork editing record — 3 October 2026

Generated with the built-in imagegen tool. No external image API or CLI was used.
The original illustrations remain in `output/imagegen/`. Accepted terrain layers
are copied here and into `assets/maps/`. Final world geometry lives in
`assets/maps/layouts/*.json`; `tools/build_map_layouts.py` regenerates guides and
editable transparent SVG street layers from that geometry.

## Shared instructions

Edit the supplied layout guide into a detailed light city illustration. Existing
city artwork is a style reference. Preserve the guide's road topology, open
junctions, reserved corridors and separate landmark footprints. Use warm cream
paving, grey roofs with fine architectural detail, sage greenery, and a strictly
straight-down orthographic view. Keep corridors empty of roofs, trees and cars;
the application adds asphalt and curbs deterministically. No extra vehicle
streets or alternate district crossings. Decorative paths must be narrow tan
pedestrian paths. No labels or interface graphics.

The initial guide used the unchanged scenario node positions. Generated outputs
were visually inspected; small registration refinements moved visual anchors
within their open plazas and registered the resulting landmark roofs. These
refinements do not change simulation coordinates or route weights. Final guides
in this directory reflect those reviewed refinements, rather than the initial
input guide. The models did not reproduce exact requested dimensions: all final
terrain images are 1499 × 1049, explicitly recorded in the layout resources.

## Accepted Twin Districts edit

Edit IMAGE ONE, the geometric layout guide, into a richly detailed strictly
overhead city illustration. IMAGE TWO is STYLE ONLY; do not copy its composition.
Keep IMAGE ONE's exact positions, proportions and full 10:7 canvas. Turn each grey
rectangle into detailed roof architecture strictly inside that same rectangle,
remove letters. Keep all straight road corridors and junctions EXACTLY where
IMAGE ONE puts them: fill grey roads and white margins with empty cream paving,
completely clear of trees/buildings. Do not move, bend, add or remove corridors.
Fill remaining beige spaces with intricate city blocks, small grey roofs, warm
gardens and sage trees as detailed as image two. A top-left warehouse, B
bottom-left school, C market above western convergence, D small gatehouse BELOW
road on west bank, E gatehouse ABOVE road on east bank, F top-right clinic, G
bottom-right shelter, H far-right warehouse. One vertical canal at 52% width with
single horizontal bridge at exactly 50% height. Maintain guide junctions at
A(12%,28.57%), B(12%,71.43%), C(32%,50%), D(45%,50%), E(59%,50%),
F(76%,27.14%), G(76%,72.86%), H(91%,50%). No buildings on those junctions.
Warm light architectural watercolor linework, no perspective, no words, no UI.

Accepted output: `exec-92e4574d-072b-4979-8379-3f4332a52bce.png`.

## Accepted Lifeline edit

Use the shared guide-edit instructions. Landmarks: A north warehouse, B school
south of southwest junction, C warehouse south of southeast western junction,
D dispatch hall north of D junction, E service building north of E junction,
F clinic north of top eastern junction, G shelter south of bottom eastern
junction, H civic hall east of right junction. West quadrant, single D-E
connection, east diamond with vertical F-G. Guide junction percentages:
A(12,28.571), B(12,71.429), C(32,71.429), D(32,35.714), E(55,50),
F(74,22.857), G(74,77.143), H(91,50). No water. Open junctions beside buildings,
never through roofs. Preserve guide geometry over the style reference.

Accepted output: `exec-59f010c8-a046-47eb-a926-b4b67638827a.png`.

## Accepted Riverside edit

Use the shared guide-edit instructions. Landmarks: A warehouse at left, B covered
market above northern junction, C clinic east of C junction but west of river,
D school below southwest junction, E tram hall northeast of E junction,
F gatehouse BELOW F junction, G civic hall WEST of G junction, H depot below
southeast junction. River at 62% width in the guide, one E-F bridge only.
Guide junction percentages: A(12.5,34.286), B(33,19.286), C(50,32.857),
D(20.5,66.429), E(43,56.429), F(67.5,62.857), G(80.5,42.143), H(90.5,73.571).
Open junctions beside buildings, never through roofs.

Accepted output: `exec-74e77805-309f-4377-8cf4-647a30019519.png`.

## Accepted Crossfire construction and roof edit

The initial two-reference passes were rejected: one omitted the eastern branches.
A guide-only pass preserved all eleven roads, followed by this targeted roof edit:

Precise style edit of this image. Preserve EVERY road, empty paving corridor,
junction, building location and building footprint EXACTLY. Do not move anything.
Convert the architecture from medieval pitched-roof village into contemporary
city blocks: grey flat roofs with HVAC vents, solar panels, fine rooftop pipes,
cream concrete and restrained brick, modern urban gardens. Keep fine detailed
warm light strictly overhead architectural illustration, sage greenery. The
8 large dark grey roofs become modern landmarks inside exactly those existing
footprints: far left and far right are warehouse depots with loading bays; upper
left and upper right are arrival halls with glazed skylights; north center is
civic offices; south center transfer hall with skylight strips; lower left school
with small court; lower right garden shelter. Roof detail must stay within
current footprints. Remove medieval/castle aesthetic, avoid blue-black rooftops.
Keep all 11 clear roadway corridors identical in geometry and cream paving.
No extra roads or road furniture, no letters, no labels, no perspective. Modify
roofs ONLY, preserving all spatial arrangement.

Accepted output: `exec-b16e1e9e-1875-45cd-b4d9-2ced0911c133.png`.
