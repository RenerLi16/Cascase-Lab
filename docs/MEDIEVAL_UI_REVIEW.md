# Medieval woodland UI review — 7 October 2026

Implemented against the approved `cascade-beacon-demo.html` composition. The game now uses a full-viewport woodland diorama, eight stable A–H tower designs, local amber beacon falloff, stone roads, route-aligned timber bridges, floating controls, a contextual inspector, and a brass-edged progression arrow. Original map images remain untouched in `assets/maps/`.

## Implementation

- `scripts/ui/woodland_art.gd`: deterministic, cached code-native pixel terrain and a coordinated 64 × 96 tower family. Inspection adds mortar, carved-stone highlights, door fittings and lantern lattice. The same ID always receives the same design, independent of pressure and AI condition.
- `scripts/ui/network_view.gd`: the existing visual route/entrance/junction geometry, selection and authoritative delivery paths remain in use. Tower silhouettes extend away from roads. Wider selectable roads, public state symbols, bounded drag/wheel/pinch camera handling, and brief inspection transitions share the existing renderer.
- Lighting uses two small cached alpha-gradient textures. There are no dynamic lights, shaders, new detection ranges, visibility rules or audio. `beacon_lit()` reads only the already-public Overrun state. P0 and hidden P1 render identically. A functioning shelter without supply remains lit.
- `scripts/ui/ui_kit.gd` and `progression_arrow.gd`: wood/aged-metal surfaces, restrained brass edges, stepped corners, material highlights, depressed pressed states and keyboard focus. The arrow remains a native Button with a polygon hit region, including its tip. Existing callbacks, labels, disabled rules and confirmation dialogs are unchanged.
- `scripts/ui/main.gd` and `practice_view.gd`: floating panels, common artwork and controls; opaque survey/AI reading surfaces; the original Barlow/Noto Sans SC fonts. Overview and Escape return from inspection. Reduced motion freezes decorative frames and removes camera/survey transitions while preserving delivery and experimental timing. Changing motion does not rebuild a draft form or restart delivery.
- `project.godot`: expand the canvas to remove aspect-ratio letterboxing.

No simulation, pathfinding, scenario/topology, AI-provider, private-response, access-control or storage implementation was changed. All three experimental conditions use the same presentation. No deployment, commit, push or cloud changes were made.

## Review artifacts

Open `build/medieval-review/index.html` for the gallery. It contains:

- Clean normal-session overviews of Riverside, Twin Districts, Lifeline and Crossfire.
- Close-ups of A, C and G, with contextual action controls.
- The 1200 × 800 captures, English/Simplified Chinese practice, public Monitor/Shield/Overrun states and functioning beacons without stocked supply access.
- Arrow hover, focus, pressed and disabled states; the original End round confirmation; private-form controls and a deliberately long bilingual AI message.
- `selection-delivery-beacons.mp4`: a silent recording from the actual Godot renderer, showing selection, real routed delivery and local beacon frames. The recording is an offline development fixture, explicitly labeled in the UI.

The screenshot gallery distinguishes normal participant views from synthetic stress-test and development fixtures. The long bilingual text is a test fixture, not a new research message.

## Validation results

| Suite | Checks | Result |
| --- | ---: | --- |
| Medieval visuals, all four scenarios × both sizes, route geometry, practice, exact public-pixel privacy | 69,978 | Passed |
| Motion/draft preservation, one-action delivery, arrow hit/focus/press/disable, public lighting, bilingual layout | 102 | Passed |
| Existing presentation: six full sessions, three conditions × both sizes | 6,144 | Passed |
| Existing UI integration | 197 | Passed |
| Existing layout/redesign | 1,468 | Passed |
| Existing first-play / English and Chinese practice | 871 | Passed |
| Existing full-session UI | 168 | Passed |
| Existing rules | 507 | Passed |
| Existing support/privacy/timing | 2,004 | Passed |
| Existing missions | 661 | Passed |
| Existing scenario fixtures | 263 | Passed |
| Existing practice/save isolation | 10 | Passed |
| Python backend suite | 46 tests | 35 passed; 11 environment-gated PostgreSQL tests skipped |

The backend suite includes real local HTTP tests for saving, access-code recovery and outbound AI context (14, 4 and 84 native client checks respectively). It used synthetic temporary databases. An initial standalone outbound-client invocation lacked its required local server fixture; the supported backend harness then passed. The initial sandbox also prevented loopback-server tests; rerunning with local-server permission passed.

Existing assertions changed only where the requested presentation changed: wheel zoom, 2.0× inspection with a floating-panel offset, and 7–13 px road widths. Public-pixel comparisons explicitly freeze decorative frames. Gameplay/privacy/backend assertions were not removed or weakened.

## Browser and native observations

Tested native Godot 4.7.1 GL Compatibility on Apple M4, plus its actual WebGL web export in the Codex browser. Inspected all four scenarios and Chinese practice in the browser; overview/inspection at 1440 × 900 and 1200 × 800, Escape, wheel zoom, drag panning, confirmation and delivery were exercised. No browser warning/error logs were reported in the final checks.

Observed steady browser performance was 60 fps, roughly 3.7–8.1 ms reported process time and about 44–46 MiB Godot static memory. The first cold-load reporting interval for other scenarios was 12–30 fps, recovering to 60 fps after initialization. These are spot observations on this machine, not a low-end-device benchmark. The offline debug export downloads approximately 60 MiB, largely the existing Godot runtime/fonts/assets; no external raster downloads were introduced.

## Remaining limits

- Physical touch-device pinch gestures and low-end mobile/Safari/Firefox hardware were not exercised. Pinch handling and its zoom limit were checked using Godot's magnify gesture event.
- The existing product localizes orientation/practice, not the research instruments. This work preserves that boundary; it verifies Chinese glyph rendering and long bilingual content without rewriting survey or AI text.
- Very long AI messages and accumulated observations scroll within opaque panels. No text is discarded.
- PostgreSQL integration tests require their external test configuration and remain skipped.
- The browser review export is deliberately offline and uses synthetic development state; it is not a participant deployment and cannot read the historical research outbox.

## Reproduce locally

Run the native scripts with the existing Godot executable and `-- --offline-tests`:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_medieval.gd -- --offline-tests
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_medieval_controls.gd -- --offline-tests
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/capture_medieval_participant.gd -- --offline-tests
python3 tools/build_medieval_preview.py
python3 -m http.server 8767 --bind 127.0.0.1 --directory build
```

The preview builder copies only project resources into an isolated temporary project, disables saving in that copy, and exports into `build/medieval-web/`. It does not change production connection settings or historical files.
