# CASCADE LAB: OUTBREAK

Cascade Lab is a deterministic cooperative zombie strategy game for three people sharing one computer. The map is the main interface: inspect a small city district, discuss danger, spend a fixed supply budget, and watch the outbreak develop over three rounds.

The project uses Godot 4.7.1, GDScript, built-in Controls, and an illustrated city with drawn gameplay overlays. Bundled assets include the existing generated Riverside artwork and IBM Plex Sans / Plex Mono fonts (SIL Open Font License, see `assets/fonts/OFL.txt`). Experimental support uses a deterministic template library; there are no plugins, online services, model APIs, or backend dependencies.

## Run it

1. Open `project.godot` in Godot 4.7+.
2. Press F6 with `scenes/Main.tscn` open, or press F5.
3. Before play, the facilitator can open **Menu → Session setup** and select No AI, Direct-Recommendation AI, or Constructive-Dissent AI. The default is No AI.
4. Start in `OBSERVE`, then pass the screen for each `PRIVATE JUDGMENT`.

The Compatibility renderer and 1440 × 900 viewport are configured. The desktop layout is checked at 1440 × 900 and 1200 × 800. Click a named building frame for an animated close-up; use Overview or Escape to return. Roads open action bubbles without zooming.

## Play loop

Every round is intentionally distinct:

```text
OBSERVE → PRIVATE JUDGMENT → INITIAL DISCUSSION → DECISION PAUSE → ACTIONS
        → SUPPLY DELIVERY → OUTBREAK RESOLUTION → NEXT ROUND
```

The map and current decision lead the screen. The top header shows the phase and round, the right panel shows the selected building, and the bottom strip carries field dispatches. Supply balances appear on the two depots. **Menu → Field guide** opens the rules and map key. Private handoffs replace the board with an opaque screen; the blank private form restores only the public map as a reference.

The presentation uses a dark operations console, the illustrated Riverside city, green named building frames, amber road bubbles, and red confirmed losses. Building details open at the right, with decisions beneath a divider. The phase is centered above the map; timed phases have a red countdown. Private forms slide down into a bottom drawer for map inspection and retain unfinished answers. Earlier dispatches remain available below the map. See [the redesign report](docs/DARK_UI_REDESIGN.md) for details and previews.

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

Private surveys measure the current decision model: immediate danger (shelter or road), next action (`VERIFY`, `MONITOR`, `SHIELD`, `ISOLATE`, or `WAIT / SAVE SUPPLY`), action target, confidence 1–5, and a structured reason. Forms start blank and the handoff clears the previous form. Responses are kept out of normal gameplay. Dev Inspector and the research export contain anonymous records sorted within each round, with no participant identifiers or submission-order linkage. Survey event entries record submission receipts without answers.

## Controlled support conditions

The condition locks when the first private judgment begins. Restart retains the assigned condition; Session setup is available again before the new run starts. The condition is not randomized or inferred from team performance. No condition selector is shown during an active run.

A two-minute discussion timer starts after the third private response. Expiry, or **Finish initial discussion**, opens a **Decision pause** in the same sidebar position for every condition. Both support modes produce one 35–60 word message with three equally emphasized sections. No AI displays a neutral message of the same length range. All use a 15-second minimum pause measured from first display; **Proceed to actions** then unlocks. The team can take longer. No action is preselected or executed, and no message is regenerated during that round. Dev controls cannot interrupt this phase.

- **Direct-Recommendation AI:** Recommendation / Why / Check. It offers an executable action and target, or an explicit district-wide wait if no funded action is reachable or all structured proposals favor waiting. The fixed ranking considers visible Overrun neighbors, public topology, and anonymous proposed actions/targets. It avoids claiming shields cure known exposure.
- **Constructive-Dissent AI:** Decision check / Discuss / Evidence to seek. It distinguishes different decisions, different reasoning categories, and uncertainty in confidence. Agreement triggers a shared-assumption question. It never identifies respondents, reports vote counts, assigns majority/minority labels, or prescribes a final action.
- **No AI:** Pause / Time / Continue. It describes the scheduled interval without suggesting a tactic or introducing a decision check.

`SupportContext` is the only simulation-to-support adapter. Its whitelist contains public Overrun/monitor status, dated Verify observations, road topology/closures, depot supplies, previous team actions, already-published reports, current round, remaining budget, and anonymous structured responses. Unrevealed P0/P1 remain unknown; a historical Verify result is never silently upgraded to current pressure. No names, raw explanations, live discussion, source, hidden pressure, future reports, or ground-truth timeline enter the generator, even in Dev Mode.

`SupportLibrary` version **support-1.0.0** is a pure local template/ranking function. It has no file, network, random, clock, scenario, or simulator access. Both modes receive the same projection. Reports and prior actions are available in that projection; this version does not interpret report prose with a language model. Templates and deterministic selection rules must receive a new version if wording or ranking changes.

The `SUPPORT_SHOWN` event stores condition, scenario ID, round, permitted input categories, exact displayed text, template ID/version, and display time (UTC plus elapsed milliseconds). It intentionally does not store the input payload or any individual response. Replay of the displayed message uses the stored text; regenerating from inputs requires the same permitted snapshot and library version. Existing anonymous survey records and detailed simulation logs remain separate research data and are never fed wholesale into support. The export schema is now **3**.

See [the support implementation notes](docs/AI_SUPPORT.md) for selection, privacy, timing, and validation details.

## Scenario

`scenarios/scenario_01.json` is a hand-authored Riverside district map. It has a four-way central hub at E, a west loop through A–B–E–D, an east branch through F–G–H, and the E–F crossing that can split the city. A and H are the supply depots. Positions are irregular and include curved road bends, district labels, building silhouettes, a river, and a faded planning-grid treatment. Decorative geometry has no gameplay effect.

The initial hidden exposure is E. The three public reports describe ambiguous radio calls, a replayed recording and a patrol photo. Good play can identify the hub, preserve a depot route, and isolate or shield the dangerous crossing. The deterministic rule suite also compares informed play with a seeded random legal-action baseline.

## Dev Mode and export

Dev Mode is explicitly labeled and asks before showing hidden pressure (`P0`, `P1`, `P2`) and the hidden source. The Inspector exposes supply paths, road state, anonymous survey records, next-resolution calculations, and the internal event stream. Enabling Dev Mode permanently sets `dev_used` in the session export. Dev Mode controls are disabled during private handoffs, decision pauses, and delivery/resolution animations. Its hidden simulation view is separate from the support input whitelist.

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
  support_context.gd    explicit public/anonymous input whitelist
  support_library.gd    versioned deterministic support templates/ranking
  scenario_data.gd      scenario loader
  models/               ShelterState, EdgeState, SupplyDepot,
                        PlayerBelief, GameAction, GameEvent
  ui/main.gd            map/sidebar/phase interface and dialogs
  ui/network_view.gd   illustrated map, building focus and animations
  ui/ui_kit.gd          palette and reusable controls
  ui/presentation_text.gd rules and Dev Inspector text
tests/test_rules.gd    deterministic mechanics and research checks
tests/test_ui.gd       real scene integration checks
tests/test_support.gd  support privacy, reproducibility, legality and timing checks
tests/test_presentation.gd  six full sessions, layout and public-pixel privacy checks
```

The root scene intentionally stays small; the screen is composed from native Controls, with an opaque private handoff between respondents. Domain state and managers are `RefCounted` objects and do not depend on the scene tree, keeping a later networked client/server split practical.

## Validation

The project has been tested with Godot 4.7.1 on macOS using the Compatibility renderer:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_rules.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_ui.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_support.gd
```

The current suites pass **485 mechanics checks**, **142 UI integration checks**, **1,994 support checks**, and **4,920 windowed presentation checks**. They cover gameplay, export, anonymity, hidden-state independence, deterministic output, template word limits, recommendation eligibility, condition locking, equal exposure timing, and desktop layout.

The suites can run headless or with a window. The windowed support suite writes `/tmp/cascade-support-0.png` through `/tmp/cascade-support-2.png` for visual inspection. Gameplay tests use real delivery/resolution animation time; support timing uses an injected monotonic clock to exercise the full 15-second boundary without sleeping.

Run the presentation suite with `/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_presentation.gd`. It captures all conditions at 1440 × 900 and 1200 × 800 in `/private/tmp/cascade-presentation/`, including a pixel comparison confirming that unrevealed pressure changes do not alter the public screen. Run it with a window for image checks. In a restricted environment, use a writable `--log-file` path if Godot cannot open its default user log.

## Future multiplayer architecture

The current MVP is Phase 1: one local device and one authoritative local `GameManager`. A future Phase 2 can ship the same deterministic client as a Godot Web build on itch.io. Phase 3 can add room-code multiplayer:

```text
Player 1 ─┐
Player 2 ─┼─→ authoritative server ─→ filtered shared GameState
Player 3 ─┘
```

The server should own hidden pressure, scenario ground truth, resource counts, action validation, shortest-path delivery, outbreak resolution, experiment condition, private survey storage, and logging. Clients should receive only a public projection: visible Overrun state, roads, supplies, shields, monitors, scheduled public intelligence, and observations permitted to that participant. Hidden pressure and the full scenario should eventually leave the client. Use authenticated room and participant IDs, idempotent commands, ordered round barriers, reconnect handling, and WSS/WebRTC or WebSocket transport as appropriate.

The support boundary is `PRIVATE SURVEY → DISCUSSION → INTERVENTION → ACTION`. A future authoritative server should own condition assignment and deliver only the same permitted projection to the support generator. The current facilitator selector is local session configuration, not an authentication or study-assignment service.

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
10. Test Chrome and another browser: map input, building focus, road bubbles, survey drawer, all actions, private handoffs, all three reports, delivery/resolution animation, JSON download, restart, and fullscreen.

Matching Web export templates are installed on this machine. Re-export after source changes and replace the itch.io upload to update the hosted game. Desktop suites do not replace a browser smoke test.

The current dark-theme release is `build/dark-web/`. Upload **`build/cascade-lab-dark.zip`**, replacing the older archive on itch.io. Its `index.html` and companion files are at the ZIP root. Older root-level ZIPs are separate snapshots and do not receive source updates.

For current browser limitations, see the [Godot Web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).
