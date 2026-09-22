# Scenario 1 — city roads

Edited with the built-in imagegen tool from the original unlabelled city illustration. The original and surveillance versions remain unchanged. This is a standalone image, not an in-game integration.

## Scenario edge mapping

| Edge | Physical road connection |
| --- | --- |
| A–B | North depot to Old market |
| B–C | Old market to Civic clinic |
| C–E | Civic clinic to Tram interchange |
| E–D | Tram interchange to West school |
| D–A | West school to North depot |
| B–E | Old market to Tram interchange |
| E–F | Tram interchange over the bridge to East gate |
| F–G | East gate to Riverside hall |
| G–H | Riverside hall around the east side to South depot |

The final illustration was visually checked for these road connections. Landmark entrances and surrounding access areas act as nodes; road geometry is illustrative, not an exact pixel mapping to the game's node positions.

## Main edit prompt

Use case: precise-object-edit.
Edit the supplied light overhead Riverside city illustration. The user wants the PHYSICAL STREET NETWORK changed so every edge in their game scenario corresponds to one clear, visually traceable road. This is an urban illustration with real streets, not a graph overlay.

PRESERVE: exactly vertical 90-degree top-down orthographic perspective; the warm ivory, graphite-gray architectural illustration; pale blue-green river; detailed roofs, trees, sidewalks and vehicles; landscape crop; the eight recognizable landmark buildings and their approximate positions. Use the provided original unlabelled artwork, not the later green-box version. You MAY relocate or remove ordinary buildings immediately along the required road corridors to make a correct network. Keep all eight landmarks intact.

EIGHT LANDMARK NODES in the supplied image (names only explain placement; do not print labels):
A North depot = big warehouse with loading bays in upper-left (about 12% width, 30% height).
B Old market = glazed market hall and little market stalls above-left of center (30%,16%).
C Civic clinic = medical-cross rooftop campus above center, west of river (50%,32%).
D West school = U-shaped school around basketball courtyard in lower-left (21%,68%).
E Tram interchange = cluster of three long parallel tram platform roofs immediately west of bridge (47%,53%).
F East gate = small checkpoint complex immediately at east bridge landing (75%,62%).
G Riverside hall = formal civic building and forecourt in right-hand neighborhood (85%,43%).
H South depot = large warehouse and truck loading yard lower-right (90%,77%).

REBUILD THE MAIN ROAD NETWORK WITH EXACTLY THESE NINE CLEAR CONNECTIONS:
1. A—B: North depot to Old market. A distinct northeast-curving street through the northwest blocks, ending at the market's entrance junction.
2. B—C: Old market to Civic clinic. A separate east/southeast street around blocks north of the tram interchange.
3. C—E: Civic clinic to Tram interchange. A distinct southwest/downward road from the clinic entrance to the interchange hub, separate from the B—E route.
4. E—D: Tram interchange to West school. A clear southwest-curving road, ending at the school entrance.
5. D—A: West school to North depot. A clear street ascending through the left/west blocks, separate from the A—B route.
6. B—E: Old market DIRECTLY to Tram interchange. A clear southeast/downward street through the interior of the west loop. This is a vital third side of the B—C—E triangle and must not be omitted or merged with B—C or C—E.
7. E—F: Tram interchange to East gate. A clear eastward road over the existing SINGLE river bridge, ending at the checkpoint immediately after the east bridge landing. The bridge is the ONLY link between the banks.
8. F—G: East gate to Riverside hall. A clear northeast/upward-curving street from the checkpoint to the hall entrance and forecourt.
9. G—H: Riverside hall to South depot. A separate road curving toward the outer right side of the hall, then south/down to the depot entrance. It must NOT pass through or connect back to F.

CRITICAL GRAPH STRUCTURE: on the west bank, a four-sided loop A–B–E–D–A with a B–C–E triangle attached along B–E. E is the only four-way hub, connecting B,C,D,F. On the east bank, a single bent chain F–G–H. There is NO direct road F–H; remove the apparent shortcut between checkpoint and south depot, replacing that shortcut corridor with planted pedestrian space, closed courtyards or ordinary building blocks. No C–F road, no second river crossing, no extra main roads joining nodes. Every main-road junction belongs to one of the eight landmarks; do not create an extra intersection away from a landmark. Main routes may curve naturally but must not cross or share a trunk away from their landmark junctions. Have a clear road-access junction just outside each landmark's entrance, so streets meet at building forecourts, never through roofs. North depot and West school each connect two main roads; Old market connects three; clinic connects two; interchange connects four; East gate connects two; Riverside hall connects two; South depot ends the chain with one.

VISUAL READABILITY: Render all nine scenario roads in the SAME consistent real-street treatment: broad unobstructed medium-light slate-gray asphalt, approximately 24–30 pixels wide at this 1499px-wide image scale, clearly defined pale curbs and sidewalks, fine white dashed centerlines, small clean zebra crossings only at the landmark access junctions, occasional tiny cars. These are physical asphalt roads with curbs, NOT colored lines painted across buildings. Nine roads must be immediately distinguishable from local streets. Simplify and lighten incidental local alleys to slim warm-ivory pedestrian/access passages without centerlines; truncate their long through-routes into local courtyards so they do not compete with or bypass the scenario network. Keep the city dense, detailed, believable and inviting, not empty graph-paper. Preserve the overall light theme. Main roads should be easily followed by eye from one landmark to the next, continuous all the way, unobstructed by buildings or trees.

Do not add text, edge labels, node letters, nameplates, green tracking boxes, diagram lines, colored route overlays, legend, arrows, pins, UI, compass, watermark, or frame. The final output is the improved clean city illustration itself. Prioritize all nine correct connections and legibility.

## Final correction prompt

Make ONE precise local street correction to this supplied city illustration. Preserve the ENTIRE rest of the image exactly: all buildings, all nine intended roads, the river and bridge, roofs, trees, school, market, clinic, tram hub, overall image dimensions, overhead perspective, colors and drawing style.

CORRECTION: Remove the unwanted tenth road, the direct SOUTHWARD shortcut from the checkpoint at the EAST bridge landing to the South depot. This is the short curved asphalt segment BELOW the bridge on the right bank. In this 1500-by-1049 image its centerline goes approximately from (1101,681) through (1133,718), (1177,747) to (1214,781). Remove the entire 25–30px wide asphalt link, its curbs, lane dashes, crosswalks and its southern checkpoint carriageway. Replace ONLY this curved connector corridor with continuous landscaped pedestrian garden: trees, shrubs, warm ivory footpath, low planted beds and small paved courtyard areas matching the neighboring texture. Make a clearly visible UNBROKEN planting strip across the former car-road corridor so no vehicular road remains between bridge checkpoint and the depot below.

At the EAST bridge landing around (1090,667), keep the road that bends NORTH/NORTHEAST toward Riverside Hall (the large formal civic hall at x1250,y430). The bridge road should bend north as a simple two-way elbow toward the hall. There must be no fork toward the south and no road through the southern gate buildings. Keep the checkpoint structures beside the new planting where possible.

PRESERVE the separate intended Riverside Hall-to-South Depot road that curves around the RIGHT/EAST side of the hall: it leaves the hall around (1304,502), curves through (1371,592) and (1395,724), then runs west across the NORTH side of the South depot to its vehicle entrance around (1233,779). Preserve this entire outer route and the access lane beside the depot trucks down to (1255,929). At approximately (1223,781) it should simply turn toward the loading yard, no longer have any west/northwest branch back toward the bridge.

After the edit, the east bank's highlighted real streets form ONE single continuous bent chain: bridge → checkpoint → civic hall → around the far right/east → south warehouse. No short circuit from checkpoint directly down to warehouse. No road ring or triangle on the east bank.

Only remove that unwanted shortcut and clean up its junctions. Everything west of the river must be identical to the input. Do not add words, letters, labels, boxes, markers, color overlays or diagrams. Maintain the beautiful light urban architectural illustration.

