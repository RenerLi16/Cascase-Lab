# CASCADE LAB: OUTBREAK

Cascade Lab is a deterministic cooperative zombie strategy game for three people sharing one computer. The map is the main interface: inspect a small city district, discuss danger, spend a fixed supply budget, and watch the outbreak develop over three rounds.

The project uses Godot 4.7.1, GDScript, built-in Controls, and procedural drawing. There are no external art assets, plugins, online services, AI interventions, or backend dependencies.

## Run it

1. Open `project.godot` in Godot 4.7+.
2. Press F6 with `scenes/Main.tscn` open, or press F5.
3. Start in `OBSERVE`, then pass the screen for each `PRIVATE JUDGMENT`.

The Compatibility renderer and 1440 × 900 viewport are configured. The layout remains usable in a smaller laptop window, and the map can be zoomed or panned.

## Play loop

Every round is intentionally distinct:

```text
OBSERVE → PRIVATE JUDGMENT → TEAM DISCUSSION → ACTIONS
        → SUPPLY DELIVERY → OUTBREAK RESOLUTION → NEXT ROUND
```

The current phase and `ROUND n / 3` are always in the sidebar. The map stays visible while the sidebar shows the selected shelter or road, fixed supply balances, and scheduled public intelligence. The Help button opens the compact rules.

At scenario start, exactly one shelter is secretly `Pressure 1`; the other seven are `Pressure 0`, and there are no Overrun shelters. Pressure 0 and 1 are hidden in normal play. When an exposed shelter reaches 2 it becomes publicly Overrun and stays that way. Each Overrun shelter spreads to every active neighboring road at resolution. Roads are bidirectional for both supply and zombies.

There are two depots with three supply each. Supply never regenerates and never heals pressure. A delivery follows the current shortest route through functioning shelters and active roads. A shelter that is Overrun cannot receive or relay a delivery. `ISOLATE` delivers one unit to each endpoint; the two endpoint units may come from the same depot or different depots. A road closes only after both deliveries arrive.

The action meanings are:

| Action | Cost | Result |
| --- | ---: | --- |
| `VERIFY` | 1 | Delivers a precise, dated pressure snapshot immediately on arrival. |
| `MONITOR` | 1 | Delivers permanent monitoring; later pressure changes create a concise alert. Installation does not reveal a baseline. |
| `SHIELD` | 1 | Blocks incoming infection for the upcoming resolution, then expires. It does not cure an existing exposure or stop outgoing spread. |
| `ISOLATE` | 2 | Delivers to both endpoints, warns about supply-route losses, then permanently closes the road in both directions. |

The city-surveillance system publishes one concise, predefined report at the start of each round. Reports are shared, incomplete observations; they never state exact pressure. Verify and Monitor are the precise player-gathered information.

Private surveys measure the current decision model: immediate danger (shelter or road), next action (`VERIFY`, `MONITOR`, `SHIELD`, `ISOLATE`, or `WAIT / SAVE SUPPLY`), action target, confidence 1–5, and a structured reason. Forms start blank and the handoff clears the previous form. Responses are kept out of normal gameplay; they are in Dev Mode and the research export.

## Scenario

`scenarios/scenario_01.json` is a hand-authored Riverside district map. It has a four-way central hub at E, a west loop through A–B–E–D, an east branch through F–G–H, and the E–F crossing that can split the city. A and H are the supply depots. Positions are irregular and include curved road bends, district labels, building silhouettes, a river, and a faded planning-grid treatment. Decorative geometry has no gameplay effect.

The initial hidden exposure is E. The three public reports describe ambiguous radio calls, a replayed recording and a patrol photo. Good play can identify the hub, preserve a depot route, and isolate or shield the dangerous crossing. The deterministic rule suite also compares informed play with a seeded random legal-action baseline.

## Dev Mode and export

Dev Mode is explicitly labeled and asks before showing hidden pressure (`P0`, `P1`, `P2`) and the hidden source. The Inspector exposes supply paths, road state, private survey records, next-resolution calculations, and the internal event stream. Enabling Dev Mode permanently sets `dev_used` in the session export. Dev Mode is disabled during private handoffs and delivery/resolution animations.

Results stay simple for normal players: survivors, supply used, roads closed, and shelters lost. Research details remain in the local event logger and can be exported as structured JSON from the results screen or Dev Inspector. Native builds open a save dialog; Web builds request a browser download. Event records include ordered types, round, elapsed milliseconds, UTC timestamp, target, before/after values, and metadata. Logged events include surveys, public intelligence, action selection, shortest delivery paths, supply spent and delivered, Verify/Monitor observations, shields, isolation, pressure changes, Overrun transitions, damage, phase transitions, and completion.

## Project layout

```text
project.godot
export_presets.cfg
scenes/Main.tscn
scenarios/scenario_01.json
scripts/
  game_manager.gd       phases, surveys, intel, delivery/resolution flow
  game_state.gd         shelters, roads, depots and observations
  network_manager.gd    bidirectional shortest-path routing
  supply_manager.gd     delivery eligibility and endpoint assignments
  action_manager.gd     validation, reservations and action effects
  event_logger.gd       UI-independent research events
  scenario_data.gd      scenario loader
  models/               ShelterState, EdgeState, SupplyDepot,
                        PlayerBelief, GameAction, GameEvent
  ui/main.gd            map/sidebar/phase interface and dialogs
  ui/network_view.gd   city-map drawing, pan/zoom and animations
  ui/ui_kit.gd          palette and reusable controls
  ui/presentation_text.gd rules and Dev Inspector text
tests/test_rules.gd    deterministic mechanics and research checks
tests/test_ui.gd       real scene integration checks
```

The root scene intentionally stays small; the screen is composed from native Controls so the map remains present through the main play loop. Domain state and managers are `RefCounted` objects and do not depend on the scene tree, keeping a later networked client/server split practical.

## Validation

The project has been tested with Godot 4.7.1 on macOS using the Compatibility renderer:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_rules.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_ui.gd
```

The current suites pass **455 mechanics checks** and **135 UI integration checks**. They cover the one-exposure start, hidden pressure, bidirectional roads, loops and chokepoints, both-depot routing, two-endpoint isolation, atomic reservations, fixed supply, real delivery/resolution phases, pan/zoom/center, blank private forms, survey privacy, public-intel boundaries, Verify arrival, Monitor alerts, Shield expiry, isolation, restart, Dev Mode and structured export.

The UI suite can run headless or with a window. With a window it writes temporary screenshots under `/tmp/cascade-lab-qa`; those are QA artifacts, not game dependencies. The test run uses real animation time so supply vehicles and outbreak markers have time to complete. The native game is also safe to open directly from the project manager.

## Future multiplayer architecture

The current MVP is Phase 1: one local device and one authoritative local `GameManager`. A future Phase 2 can ship the same deterministic client as a Godot Web build on itch.io. Phase 3 can add room-code multiplayer:

```text
Player 1 ─┐
Player 2 ─┼─→ authoritative server ─→ filtered shared GameState
Player 3 ─┘
```

The server should own hidden pressure, scenario ground truth, resource counts, action validation, shortest-path delivery, outbreak resolution, experiment condition, private survey storage, and logging. Clients should receive only a public projection: visible Overrun state, roads, supplies, shields, monitors, scheduled public intelligence, and observations permitted to that participant. Hidden pressure and the full scenario should eventually leave the client. Use authenticated room and participant IDs, idempotent commands, ordered round barriers, reconnect handling, and WSS/WebRTC or WebSocket transport as appropriate.

The future AI boundary remains `PRIVATE SURVEY → DISCUSSION → INTERVENTION → ACTION`. `InterventionType` already defines `NONE`, `DIRECT_RECOMMENDATION`, and `CONSTRUCTIVE_DISSENT`; the MVP always uses `NONE` and does not expose an AI choice to players.

## Future Web / itch.io deployment

Nothing is deployed by this project. `export_presets.cfg` contains a Web preset with Compatibility rendering, automatic canvas resizing, scenario JSON inclusion, extensions disabled, and thread support disabled. Godot 4 Web requires WebGL 2.0 and the Compatibility renderer. Single-threaded export is the preferred path for itch.io because it avoids cross-origin isolation headers. Browser download and fullscreen actions must originate from user input; this project triggers JSON download from its button and does not depend on browser filesystem persistence.

1. Install export templates matching the Godot version.
2. Open the project and choose Project → Export.
3. Select or recreate the Web preset. Keep thread and extension support off for this MVP.
4. Export to a clean folder with `index.html` at its root. Preserve the generated HTML, WASM, PCK and JavaScript filenames.
5. Test through a local HTTP server or Godot Web preview; do not open the HTML with `file://`.
6. ZIP the export contents, keeping `index.html` at the ZIP root.
7. Create an itch.io HTML/browser project and upload the ZIP.
8. Mark “This file will be played in the browser.”
9. Configure a responsive 1440 × 900 or laptop-sized embed and fullscreen.
10. Test Chrome and another browser: map input, zoom/pan, all actions, private handoffs, all three reports, delivery/resolution animation, JSON download, restart, and fullscreen.

The project has not produced a Web export on this machine because matching Web export templates are not installed. Desktop startup and the mechanics/UI suites passing do not replace a browser smoke test.

For current browser limitations, see the [Godot Web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).
