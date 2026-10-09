# Landscape recomposition review

Local review completed 2026-10-09. Godot 4.7.1 Compatibility renderer on macOS.

## Result and review artifacts

Open [the before-and-after gallery](../build/landscape/index.html), or serve that directory locally. The gallery switches between 1440×900 and 1200×800, and includes original/final overviews and a paired close-up of **every** designated crossing. Expand each map for source selection, route confirmation, closed gates, all eight tower inspection positions and all four pan corners. Screenshots are local, git-ignored review artifacts; they are not a game export.

The [composition plan](LANDSCAPE_COMPOSITION.md) records the initial land, drainage and graph arrangements. The finished landscapes were inspected from rendered screenshots and refined after the geometry checks—not accepted on geometry checks alone.

- **Riverside:** retains its original anchors, road centerlines and north–south river. The existing E–F crossing remains the reference. Added outer scenery prevents the camera exposing the old texture boundary.
- **Twin Districts:** an unequal pair of continuous channels splits upstream and reunites downstream around a sizeable island. D sits in its raised central clearing. C–D crosses the narrower west arm; D–E crosses the stronger east channel. Western roads skirt a wooded hollow, while the eastern settlement follows an oblique ridge. The two settlements no longer mirror each other.
- **Lifeline:** a continuous dry valley descends south, with two uphill tributary gullies eroding the sides of E’s plateau. D–E crosses the main valley; E–F and E–G cross its northern and southern tributaries. The gullies narrow into rocky scree before the eastern ridge road. A small connected gully extends into the southern scenery. No black incision terminates with a blunt rounded cap.
- **Crossfire:** B occupies a western upland spur above a connected ravine; D and E occupy the central ridge. An irregular eastern lake basin drains north through the D–F and E–F crossings. B–D and B–E cross the western ravine. The ordinary A–C–E–G–H–F route passes around the valley head and lake on continuous land. The disconnected southern hollow was removed.

There are no unresolved graph/geography conflicts. No ordinary edge received a decorative bridge, and the designated bridge lists are unchanged.

## Geometry, timing and privacy

`ScenarioData.road_length()` computes logical distance from scenario coordinates and bends; `GameState` stores it in `EdgeState.length`, and Dijkstra uses that length. Those files and all scenario data are unchanged.

There was a separate timing dependency: `NetworkView.play_deliveries()` previously measured the rendered route to calculate its timer. Layout schema 2 therefore retains each original rendered edge length as `delivery_length`. The timer sums those frozen lengths while couriers follow the new centerlines. Both routing costs and pre-change delivery durations remain unchanged; the animation, arrival and closure delays retain their original formulas and constants.

The visual layouts remain the sole source of node anchors and road centerlines. Tower footprints, click targets, camera inspection, labels, lights, bridge spans, gates, route previews and courier paths all derive from that mapping. The older illustrated-building metadata in the layouts remains inactive historical data, as before.

The same terrain definitions now drive filled water surfaces, shorelines, ravine depth, tapered widths, forest exclusion, bank distance and complete bank-to-bank bridge spans. Paths join other channels, the lake, tapered rocky heads, or continue beyond the full painted extent. Scenery padding grows from 320 to 800 world units, with a matching shader offset. Camera clamping keeps the full viewport inside that extent, including source-selection pans. Riverside’s central scenery stream is retained.

Lighting still accepts only public beacon on/off flags. New terrain accepts public geometry and deterministic scenery seeds. Hidden P0/P1 changes produce identical public pixels in every final map at both sizes.

Map annotations reserve space below the toolbar, above the unchanged source picker, and around public bridge notices. Longer searches allow crowded inspection labels to move with their existing leader lines. No menu, gate, access-code Paste, source-picker, AI, survey, research logger, backend or infrastructure implementation was changed.

## Validation

| Suite | Checks | Failures |
| --- | ---: | ---: |
| Original/current behavior comparison | 4,354 | 0 |
| Landscape geography | 2,637 | 0 |
| Rendered labels, source routes and closed notices | 9,120 | 0 |
| Final rendered capture and public-pixel privacy | 40 | 0 |
| Rules | 507 | 0 |
| Scenario action fixtures | 367 | 0 |
| Support conditions and privacy | 2,004 | 0 |
| Bridge eligibility, geometry and actions | 848 | 0 |
| Medieval mapping, interaction and delivery animation | 43,436 | 0 |
| Existing terrain, source selection and Paste suite | 43,115 | 0 |

The behavior baseline covers 4,320 depot/target routing situations: every combination of designated closed bridges, with no overrun node or each single overrun node. It compares exact paths, logical costs, bridge flags and delivery durations. Thirteen three-round action replays across all four scenarios compare outcomes and research events, excluding wall-clock timestamp fields. The initial baseline was captured before edits; it was reproduced exactly in an isolated copy of the original Git HEAD, and the two Riverside replay cases were added from that original copy.

Geometry checks sample every ordinary road and designated crossing, verify dry tower footprints and bridge abutments, reject false road intersections, verify connected/tapered terrain endpoints, and cover every viewport corner at six zoom levels in both ordinary and source-selection modes. Rendered inspection additionally covers all four maps at both resolutions, every bridge, every tower, route previews and real bridge closure after delivery.

Visual iteration corrected a bend splitting B–D’s deck, a southern label covering the lake, overly flat elevation shading, a label touching the toolbar, source-status clipping, and a tower label overlapping a CLOSED notice.

Chinese public tower names are **test-only translated display-name fixtures**, clearly marked in the gallery; production tower names and ordinary status text remain English as in the existing game. The source picker’s Chinese text is the actual existing UI. Both were rendered and checked at both resolutions.

## Limits and diagnostics

This is native desktop validation, not a new browser export or production-host test. No deployment, commit, push, rebalance or infrastructure change was made.

The full existing title-menu suite was attempted headless but not completed: its password tests require `CASCADE_DEV_PASSWORD`, which was not supplied. It also reported a frame-sensitive decorative-node settling failure in the headless run. That suite is not counted as passing; menu and password-gate source files are byte-for-byte unchanged.

The existing UI-improvements suite emits a freed-lambda diagnostic during its stale-source test despite zero assertion failures. The same diagnostic was reproduced on the untouched original Git HEAD. Restricted headless runs also emit the macOS system-certificate diagnostic; all work used `--offline-tests`. The dedicated rendered landscape captures and label checks are checked separately for script errors.

## Reproduce

Run the following with the local Godot executable and `--path . --log-file /tmp/<name>.log --script <script> -- --offline-tests`:

- `tests/test_landscape_behavior.gd`
- `tests/test_landscape_geography.gd`
- `tests/test_landscape_labels.gd` (windowed)
- `tests/capture_landscapes.gd` (windowed; default phase is `after`)

Then run `python3 tools/build_landscape_gallery.py` to regenerate the local gallery and verify every linked capture. The checked-in behavior baseline is an original-state fixture; do not regenerate it from the recomposed layouts. Historical `tools/build_map_layouts.py` targets the old illustrated-building artwork, not the live medieval tower renderer.
