# Light paper-board redesign — October 2026

Presentation-only redesign of Cascade Lab: Outbreak as a light, tactile city board.
Gameplay, experimental conditions, surveys, AI behaviour and text, data collection,
saving, and research timing are unchanged. Nothing was committed, pushed, or deployed.

Screenshots: [`docs/screenshots/light-board/`](screenshots/light-board/) —
`compare-menu.png`, `compare-board.png`, `compare-private-form.png`,
`compare-ai-panel.png`, `compare-ai-panel-zh.png`, `compare-scenarios.png`
(all four missions plus practice), and `before/` and `after/` sets.

## What changed

### Location pieces sit on the junctions
Each location is now a single board piece drawn **exactly on its network anchor**,
where its roads meet. The separate building frame and its spur are gone, so a node
reads as one object at a glance:

- Shelters are small house tiles; depots are square crate tiles with plank lines
  (shape, not only colour, separates them). The location ID is on the piece.
- Name plate and status chips sit beside the piece, placed clear of roads and other
  pieces, with a short leader line only when they had to move.
- Status chips (sentence case): `? Unobserved` (neutral grey; never looks safe),
  `Overrun` (brick, plus a cross badge and red piece), `Monitor: n`, `Monitor`
  (installed, no reading yet; plus a badge), `Shield` (plus a badge), `n supply`,
  `No supply route` (ochre).
- Selection: blue ring and a 160 ms pop. Hover: lighter ring. Keyboard focus: dashed
  ring. Route-loss preview: dashed ochre ring.
- Click/hover areas are the visible piece and its label; roads are selectable
  everywhere else along their visible stroke.

Node positions, road centerlines, topology, logical lengths, routing, and supply
access are unchanged. `world_building()` and the layout JSON footprints are kept for
registration and clearance checks; the camera now centres on the piece (anchor).

### Paper palette (`scripts/ui/ui_kit.gd`)
| Token | Value | Use | Contrast |
| --- | --- | --- | --- |
| BG | #F4F0E6 | page / table | — |
| PANEL | #FFFCF5 | sheets, cards, piece faces | — |
| TEXT | #292A26 | primary text | 12.7 on BG, 14.1 on PANEL |
| SECONDARY | #55574F | secondary labels | 6.5 on BG, 6.1 on SUNKEN |
| LINE / LINE_STRONG | #CCC5B7 / #8F887B | rules / control outlines | outline 3.1 on BG |
| ACTION | #315F78 | primary keys, selection, focus | 6.7 with paper text |
| WARNING | #855A00 | privacy label, route loss, no supply route | 5.3 on BG, 5.0 on tint |
| DANGER | #A23B2E | Overrun, closed roads | 5.8 on BG, 6.4 paper-on-brick |
| PROTECT | #3E6B48 | shield, monitor | 6.0 |
| ROAD | #57584F | open playable road core | 4.5–5.6 on all terrain tones |

Contrast ratios were computed (WCAG formula) against the actual surfaces. Disabled
text is 4.1 on its face. Decorative streets are deliberately 1.1 against land.
Typography, sizes, and locally bundled fonts are unchanged.

Removed dark-theme leftovers: dark clear colour, boot-splash and PWA background,
Godot's light-on-dark arrow/switch/radio icons (replaced by drawn charcoal icons),
hardcoded colours in custom drawing, popups, tooltips, map labels, and the modal
scrim. All reading surfaces stay opaque.

### Simplified city artwork
`tools/build_board_terrain.py` renders a flat terrain layer per map from the
authoritative layouts: pale land, a quiet street grid lighter than the land, a few
lots with simple building masses and small parks, and (Riverside, Twin Districts)
the river traced from the archived illustration and smoothed. Every playable
corridor and node area is left clear; no playable roads, IDs, names, or status are
baked in. Output sizes match each layout's registered `image_size`, so no
coordinate changed. The practice map gets the same terrain (`assets/maps/practice.png`).

The previous illustrations are archived unchanged in
`output/illustrated-city-v1/` (also identical to `output/map-alignment/*-terrain.png`
and in git history). Restore one by copying it back to `assets/maps/<name>.png`.

### Bold roads
Pale casing (core + 6 px) under a charcoal core of 7–10 px (previously 4–6 px),
drawn in two passes so junctions stay clean. Open = solid charcoal; selected = blue
with a pale-blue casing and a midpoint ring; no supply route = dotted; closed = red
dashes plus a barricade piece and `Closed` chip; supply preview = blue with direction
ticks. Hit radius follows the casing.

### Tactile interaction
- `TactileButton` / `TactileBox`: keys rest on a thin base, lift 1 px on hover
  (120 ms), press 2 px down (70 ms), and settle on release (140 ms). One tween per
  key is replaced, never stacked; content margins move with the face while their sum
  is fixed, so size, position, and hit area never change.
- Pieces pop (160 ms) on selection. Barricades drop and settle onto the road inside
  the existing 0.22 s closure. Supply crates travel the route and land on the
  destination piece with a fading ring and `Delivered` chip — identical for every
  action type and condition.
- Camera moves shortened from 0.55 s to 0.5 s; survey drawer 0.3 s to 0.25 s.
- **Reduced motion**: browser `prefers-reduced-motion`, project setting
  `cascade/reduced_motion`, or the new **Reduce motion** toggle (main menu and
  session menu). Interface tweens become immediate; deliveries, outbreak, reveal,
  and closure keep their exact durations but show static routes and highlights.
- No sounds were added (no suitable licensed assets in the project).

### Other screens
Main menu gains a decorative row of blank pieces (no map data). Field guide map key
and map-controls text describe the new pieces. Sidebar tag reads `Shelter E` /
`Depot A` instead of `Building E`. Footer hint: "Select a location piece or a
road…". Discussion and decision-pause countdowns are charcoal rather than red.
Survey questions, scales, options, AI messages, and consent/privacy wording are
untouched.

## Verification
Run in Godot 4.7.1 (Linux, Compatibility renderer, windowed under Xvfb).

| Suite | Result |
| --- | --- |
| test_rules | 507 checks, 0 failures |
| test_ui | 197 / 0 (also passes with reduced motion forced on) |
| test_support | 2,004 / 0 |
| test_missions | 661 / 0 |
| test_mission_ui (windowed, hidden-pressure pixel checks) | 2,326 / 0 |
| test_session_ui | 168 / 0 |
| test_first_play (windowed) | 803 / 0 |
| test_practice_isolation | 10 / 0 |
| test_scenario_fixtures | 263 / 0 |
| test_async_support | 18 / 0 |
| test_redesign (windowed) | 1,372 / 0 |
| test_presentation (windowed, 3 conditions × 2 sizes) | 5,784 / 0 |
| test_reduced_motion (new; full presentation run) | 5,785 / 0 |
| test_city_art (windowed, all maps × 2 sizes) | 137,688 / 0 |
| backend Python suite incl. native client, access-code recovery, outbound context | 46 tests OK (11 skipped: PostgreSQL) |

Test edits (presentation assertions only): road-width bounds 4–6 → 7–10 px; piece ink
is charcoal instead of the old green; camera centres on the piece anchor; the
city-art branch check now samples 21 points per road and requires the junction piece
to take clicks where it covers the road end and the road everywhere else (previously
3 points). `test_city_art` accepts `CAPTURE_DIR` so verification runs don't rewrite
the archived alignment report images. `test_access_code_recovery`,
`test_backend_client`, and `test_outbound_context` must be run through their Python
wrappers (as before).

Visual QA: `tests/capture_ui_screens.gd` and the new `tests/capture_board_redesign.gd`
at 1440 × 900, 1200 × 800, and scaled 1366 × 768 / 1280 × 800; all four missions and
practice; English and Simplified Chinese; overview and close-up; hover, pressed,
disabled, selected, and keyboard-focus states; long survey options; long Chinese and
English AI messages; reduced-motion delivery. Hidden P0/P1 pixel-equality checks
still pass in every windowed suite.

### Not verified / known limits
- Not tested in a browser export (no Web export was built; nothing deployed).
  `prefers-reduced-motion` detection is web-only and unverified.
- Run on Linux, not the development Mac.
- At 1200 × 800, long Chinese AI messages still scroll inside the fixed note (unchanged).
- Terrain is a flat raster at the original resolution, so close-ups are slightly soft.

## For supervisor review before research use
1. **Node presentation**: pieces now sit on junctions with ID on the piece and name
   + status beside it. Same information, different layout and salience.
2. **Countdown colour** changed from red to charcoal (less urgency) in all conditions.
3. **Reduce motion toggle** is visible to participants on the main menu and session
   menu. It changes animation only, not timing or information.
4. **New artwork** for all maps, including a river trace and simplified buildings.
   Scenery is clearly non-playable but could still influence perceived geography.
5. Copy changes: field-guide map key and map-controls text, footer hint, sidebar tag.
6. The decorative menu pieces and the uniform delivery crate are the only new
   feedback graphics; none differ by action type or condition.
