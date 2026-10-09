# Bridge-only closure and revised terrain (pack 1.1.0)

Date: 2026-10-08. Engine checks used Godot 4.7.1 (Linux arm64 build, llvmpipe software rendering under Xvfb). Nothing was deployed, committed or pushed, and no paid model calls were made.

## Rule change

**bridge-only-1:** only edges listed in a scenario's `bridges` array can be closed. Players see the action as **Close bridge**. The internal action ID stays `ISOLATE`, so existing logs, exports and the AI action vocabulary are unchanged. Ordinary roads can still be selected and inspected. Their bubble says "Only bridges can be closed." and offers no closure action.

Everything else is unchanged: the two-supply cost, one delivery to each end, source selection and reachability checks, closure only after both deliveries arrive, a permanent closure that blocks both outbreak spread and supply transit, and no reopening. The rule applies in every condition (No AI, Direct, Dissent), in normal and development runs, and in practice.

### One authoritative mapping

| Concern | Reads |
|---|---|
| Scenario data | `ScenarioData.bridges`: required, exact edge IDs (same convention as `road_bends`), validated by the loader |
| State | `EdgeState.bridge`, set from scenario data; copied and exported |
| Validation | `ActionManager.unavailable_reason` → `NOT A BRIDGE` before any stock check; `SupplyManager.delivery_options` is empty for ordinary roads. Invalid direct requests reserve nothing and log nothing. |
| Survey | `GameManager.survey_targets("ISOLATE")` lists bridges only; ordinary roads can still be named as the danger location |
| Visible bridge | `WoodlandArt.bridge_spans(data, paths)` places decks only on `data.bridges`. Geometry decides where the deck sits, never whether an edge is a bridge. |
| AI context | Each road carries `bridge`. Legal actions and the direct ranking consider bridges only; ordinary-road closure proposals are dropped. The backend validates the flag and recomputes legal actions. |

Tests assert in both directions that every closable edge has exactly one complete deck and that every deck belongs to a closable edge.

## Finalized bridge edges

| Scenario | ID | Bridges | Terrain |
|---|---|---|---|
| 1 Riverside | `riverside_01_v3` | E–F | Unchanged river; terrain raster verified pixel-identical |
| 2 Twin Districts: The Island Outpost | `twin_districts_02_v2` | C–D, D–E | A river forks around the island outpost D; one bridge per arm |
| 3 Lifeline | `lifeline_03_v2` | D–E, E–F, E–G | Dry rocky ravine (D–E, longest deck) with two eastern side gullies around E's promontory |
| 4 Crossfire | `crossfire_04_v2` | B–D, B–E, D–F, E–F | Dry gully west of D, a brook ending in a pool east of D, and a southern hollow no road enters |
| Practice | `practice_demo_v2` | C–E, D–F | Unchanged river; raster pixel-identical |

Topology, logical edge lengths, initial pressures, depots and supplies are unchanged. The terrain was fitted to the visual anchors and road centerlines in `assets/maps/layouts/*.json`, not to the logical coordinates.

## Terrain implementation

`WoodlandArt.terrain_definition()` now returns a list of features. Each feature has a mode (`column` for the legacy x-of-y river, or `path` for any polyline), a kind (`water` or `ravine`), a core width and a bank distance.

One geometry feeds the raster, banks, rim rubble, tree exclusion, bank stones, bridge spans, ravine abutments and water-only ripple animation.

Geometry checks:

- Towers and forecourts are on dry land.
- Ordinary roads stay more than 6 px from any bank.
- Each bridge crosses exactly one obstacle and meets dry ground at both ends.
- The barricade sits mid-deck.
- Decks stay on their road after zoom, pan and resize.

Riverside and practice keep their previous pixels because column mode reproduces the terrain version 2 renderer and its RNG sequence.

## Versioning

- Scenario pack `1.1.0`; IDs `_v2` (Riverside `_v3`)
- Export schema 6, which adds edge `bridge`, `closure_rule` and `bridges`
- Session schema 7 / `cascade-development-7`
- Context `cascade-context-3`
- `support-1.2.0`, with `direct.isolate` reworded to "Close Bridge %s" (49 words)
- Qwen prompt `cascade-zh-4`
- Practice `practice-2`

The backend still accepts schema 5 and 6 sessions as record-only legacy sessions that can never request an intervention. **The Render backend must be redeployed before any new web build is uploaded.** The currently deployed backend will reject context-3 requests.

## Gameplay checks (simulation, not human evidence)

Method: I wrote a Python mirror of the rules and checked it against all 8 existing engine fixtures with no mismatches. With it I ran exhaustive full-information searches, public-information policies and a seeded random baseline (3,000 trials). Three new representative bridge plans were added to `tests/scenario_validation_cases.json`, and the engine confirms them.

| Scenario | Best possible, old any-road rule | Best possible, bridge rule | Best plan with ≥1 closure | Reactive shields only (public info) |
|---|---|---|---|---|
| Riverside | 7/8 (no closure) | 7/8 (no closure) | 7/8 | 7/8 |
| Twin Districts | 7/8 (no closure) | 7/8 (no closure) | 7/8, 1 more supply spent | 7/8 |
| Lifeline | 7/8 (no closure) | 7/8 (no closure) | 7/8 (E–F local) | 7/8 |
| Crossfire | 6/8 (no closure) | 6/8 (no closure) | 5/8 (any single bridge) | 6/8 |

- **No scenario becomes impossible.** The best achievable result is identical under the old and new rules in all four maps.
- **No dominant closure sequence.**
  - Twin Districts: closing C–D, D–E or both ties with no closure on survivors (7/8) but costs supply, so no single bridge disconnects everything.
  - Lifeline: shows the intended trade-off. Closing D–E in round 1 is broad containment that also cuts both depots off from the east and leaves 4/8. Closing the local bridge E–F leaves 7/8. Closing E–G in round 1 leaves 5/8.
  - Crossfire: any one closure caps the result at 5/8, below the 6/8 achievable without closures.
- **Timing has consequences.** Closures next to the initially exposed shelter must happen in round 1, before it is visible, because an Overrun end blocks delivery. Lifeline's D–E and E–G can be closed later at 7/8, but only after protection has been bought.
- **Non-closure actions stay central.** Shields carry every optimal plan.
- **Random legal play** averages, new vs old rule: Riverside 3.34 vs 3.60, Twin 5.50 vs 5.29, Lifeline 4.24 vs 4.42, Crossfire 2.08 vs 2.32.

### Unresolved balance concerns

1. **Closure is never strictly needed.** In all four maps, under both the old and the new rule, every full-information optimum uses zero closures. A simple public-information policy reaches it: wait in round 1, shield functioning neighbours of visible Overrun shelters in round 2, and shield shelters with two Overrun neighbours in round 3. A closure costs 2 and must be made before the source is visible; a shield costs 1 and can react afterwards. This comes from the existing action economy and 3-round horizon, not from the bridge assignments. No bridge-only reassignment fixes it, because even "any road closable" gives the same optimum. The smallest levers would be mechanic changes (for example shield cost or duration, or closure next to an Overrun end), which were out of scope and need a researcher decision.
2. Choices are still meaningful under uncertainty: players do not see the source in round 1, and closure decisions trade guaranteed protection against supply access. Whether real teams disagree, over-close or under-close is an empirical question. **No participant testing has been done; nothing here shows balance or disagreement in human play.**

## Research materials still to update

- The body of `docs/STUDY_GAMEPLAY_DESCRIPTION.md` (now flagged at the top), plus consent and instruction sheets, facilitator scripts and codebooks: rename "Isolate" to Close bridge, limit survey closure targets to bridges, update the AI example "Isolate Road E-F" and the reference paths.
- Screenshots in `docs/screenshots/` and earlier review documents still show the old geography.
- The Twin Districts subtitle changed from "The Bridge" to "The Island Outpost". Lifeline and Crossfire keep their titles; their blurbs were updated.
- The Qwen prompt change is code-reviewed only. No live call was made.

## Verification

All headless suites pass: rules 507, fixtures 367, support 2,004, missions 665, async support 18, and **new `tests/test_bridges.gd` 848**.

`test_bridges.gd` covers:

- ordinary-road rejection in UI, direct dispatch and `reserve` with no spending
- valid closure
- insufficient supplies
- unreachable ends
- cancellation and duplicate confirmation
- survey targets
- every condition and run purpose
- AI context and legal actions
- geometry and alignment
- English/Chinese practice

A mutation check that removed the rule produced 210 failures.

All windowed suites pass:

| Suite | Checks |
|---|---:|
| UI | 198 |
| Session UI | 168 |
| Practice isolation | 10 |
| Medieval controls | 104 |
| First play | 859 |
| Redesign | 1,444 |
| City art | 5,440 |
| Medieval | 27,586 |
| UI improvements | 25,399 |
| Presentation | 6,078 |

`test_mission_ui` has 56 failures in "Artwork building registration rendered" and "Results footer is below map". The committed HEAD fails identically (2,518 checks, 56 failures), so they predate this change.

The backend unittest suite passes with `GODOT_BIN`, including the real Godot client tests: 52 tests, 11 PostgreSQL tests skipped without a database. A new `backend/tests/test_bridge_rule.py` covers the backend side of the rule.

One test-helper change: `tests/test_ui.gd` now waits 230 ms of wall-clock time between repeated clicks on the same depot. Under software rendering, a scene timer could fire early in real time and trip the picker's 160 ms debounce.

Screenshots (git-ignored) are in `build/bridge-review/`: overview, bridge and road bubbles, open and closed close-ups, and closed overview for each map at 1440×900 and 1200×800.
