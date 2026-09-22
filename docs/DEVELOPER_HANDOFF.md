# Cascade Lab: Outbreak — developer handoff

## Game description

Cascade Lab: Outbreak is a playable cooperative strategy and decision-making research game for three people sharing one computer. Players coordinate the containment of a zombie outbreak across eight connected shelters in the Riverside district. The objective is to keep as many shelters functioning as possible over three rounds while managing incomplete information and a fixed, shared supply budget. There is no real-time combat: players inspect the map, make private judgments, discuss evidence, and decide which interventions to fund.

The map is a bidirectional road network with two supply depots, each starting with three units. Exactly one shelter begins secretly exposed. Pressure progresses from 0 to 1 to 2; at 2, a shelter becomes publicly Overrun and remains lost. Normal players cannot directly distinguish unobserved pressure 0 from 1. Existing exposure progresses during resolution, and shelters already Overrun at the start of that resolution transmit along open roads. Newly Overrun shelters become sources on later resolutions. This creates a tension between gathering information and protecting routes before containment becomes impossible.

Each round starts with a scheduled, ambiguous public report. The three players then enter separate structured judgments: suspected danger, proposed action and target, confidence, and a reasoning category. After the initial team discussion, an experimental decision pause appears. The team then chooses actions, watches supply deliveries, and ends the round to resolve the outbreak. Multiple actions can be completed before resolution if resources and routes permit; the team can also save supplies. After round three, results summarize functioning shelters, losses, supplies used, and closed roads.

The four funded actions are:

| Action | Cost | Effect |
| --- | ---: | --- |
| Verify | 1 | Reveals an exact, dated pressure observation when delivery arrives. |
| Monitor | 1 | Permanently reports subsequent pressure changes; installation does not reveal the starting pressure. |
| Shield | 1 | Blocks incoming infection during the next resolution. Does not cure existing exposure or prevent outgoing spread. |
| Isolate | 2 | Delivers one unit to each road endpoint, then permanently closes the road to both infection and supplies. |

Deliveries follow available shortest routes through functioning shelters. Overrun shelters cannot receive or relay supplies. Isolation may draw its two units from different depots. Supplies never regenerate, so a useful closure can also cut off later interventions.

## Runtime and entry points

- Engine: Godot 4.7.1, GDScript, Compatibility renderer; base viewport 1440 × 900.
- Open `project.godot` and press F5. The entry scene is `scenes/Main.tscn`.
- UI uses native Controls and procedural map drawing. No backend, model API, or external service is required.
- Current multiplayer is local screen sharing/pass-and-play, not networked rooms.

## Code navigation

| File or directory | Responsibility |
| --- | --- |
| `scripts/game_manager.gd` | Authoritative round/phase flow, private forms, public reports, support timing, action dispatch, outbreak resolution, export assembly. Start here to trace gameplay. |
| `scripts/game_state.gd` | Mutable shelter, road, depot, and observation state. |
| `scripts/action_manager.gd` | Action validation, supply reservation, and effects applied after delivery. |
| `scripts/supply_manager.gd` | Reachability, depot funding, and isolation endpoint assignments. |
| `scripts/network_manager.gd` | Bidirectional road routing and shortest paths. |
| `scripts/models/` | Shelter, road, depot, belief, action, and event records. |
| `scripts/scenario_data.gd` | Loads scenario data and enforces MVP assumptions. |
| `scenarios/scenario_01.json` | Map geometry, roads, names, starting supplies, hidden initial state, and scheduled reports. Contains spoilers. |
| `scripts/ui/main.gd` | Main screen, sidebar, dialogs, private handoffs, condition selector, and phase-specific controls. |
| `scripts/ui/network_view.gd` | Illustrated map registration, building focus, selection, and visual animations. |
| `scripts/ui/ui_kit.gd` | Shared palette and reusable controls. |
| `scripts/ui/presentation_text.gd` | Help/rules and developer inspection text. |
| `scripts/support_context.gd` | Sole public/anonymous projection supplied to experimental support. |
| `scripts/support_library.gd` | Deterministic support templates and selection policy. |
| `scripts/event_logger.gd` | Timestamped research event recording. |

Domain managers are `RefCounted` objects, separate from scene-tree rendering. Phase transitions and legality should remain enforced in the domain layer, not solely through disabled UI buttons. Delivery/resolution callbacks use run tokens to reject stale callbacks after restart.

## Experimental support

Before private judgment begins, **Session setup** selects No AI, Direct Recommendation, or Constructive Dissent. Assignment stays fixed across the run and survives restart; setup becomes available again before a new run starts.

All conditions use the same sidebar card and minimum 15-second pause after initial discussion and before action selection. Both support modes generate exactly one 35–60-word message per round. Direct support provides an action, rationale, and uncertainty check. Dissent asks a focused reasoning question without selecting an action; agreement triggers a shared-assumption check. No AI displays a neutral pause message.

These are local templates, not live language-model agents. Version `support-1.0.0` uses deterministic rules and stable tie-breaking. Both modes receive the same public state and anonymous structured responses. Hidden pressure, future events, names, raw explanations, and live conversation must never cross `SupportContext`. Change the library version when changing template wording or selection rules. See `docs/AI_SUPPORT.md` for the full contract.

## Logging and development boundaries

Export schema 3 records the assigned condition and session events. Each `SUPPORT_SHOWN` event records scenario, round, input category labels, displayed text, template/version, and display timing; it does not retain the raw support snapshot. Separate research exports retain anonymous structured survey records and detailed simulation data. Do not feed those complete research logs into support.

Dev Mode can reveal hidden state and flags the session as `dev_used`; it is a debugging aid, not a participant feature. The local client contains scenario secrets, and the facilitator selector is not authenticated. Secure remote experiments would require server-owned hidden state, assignment, and validation. The scenario loader currently assumes eight shelters and three rounds; results also assume the initial six-unit supply budget.

## Validation and delivery

Run from the project root with Godot available as `godot`:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_rules.gd
godot --headless --path . --script res://tests/test_ui.gd
godot --headless --path . --script res://tests/test_support.gd
```

On the development Mac, the executable is `/Applications/Godot.app/Contents/MacOS/Godot`. Latest validation: 485 mechanics, 142 UI, 1,994 support, and 4,920 windowed presentation checks passed. Run `--path . --script res://tests/test_presentation.gd` with a window for the image-based checks. It completes three rounds in each condition at 1440 × 900 and 1200 × 800, checks equal support-note bounds, and compares public pixels under different unrevealed pressures. Details and browser validation are in `docs/VALIDATION.md`.

`export_presets.cfg` defines the single-threaded Web export. The latest prepared build is `build/operations-web/`, with upload archive `build/cascade-lab-operations.zip`. Keep `index.html` at the ZIP root and preserve its companion files. Re-export after code changes; uploading an older root-level ZIP will not include those changes. The repository does not automatically publish changes.

The current presentation has dark surfaces, green named frames on the illustrated city, animated building focus, a right information panel, anchored road bubbles, and a retractable private survey. Start with the tokens in `scripts/ui/ui_kit.gd`, phase composition in `scripts/ui/main.gd`, and drawing helpers in `scripts/ui/network_view.gd`. Handoff removes the board entirely; forms restore the public map; action explanations use tooltips; earlier dispatches are collapsed. The support note uses one renderer for all conditions. See `docs/DARK_UI_REDESIGN.md` for the current design report and screenshots.

For onboarding, read `README.md`, trace `game_manager.gd`, then open the UI or domain file for the behavior being changed. Run the relevant test suite before rebuilding the Web upload.
