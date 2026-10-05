# Four-mission menu and development sandbox

Implemented 2 October 2026 from the supplied `cascade_lab_scenario_pack_v1` reference maps and implementation prompt.

## Play

Run `project.godot` in Godot 4.7.1. The app opens on the main menu. **Play** starts a normal session of four independent three-round missions. Before the first private judgment, a facilitator can use **Menu → Session setup** to assign the condition. It remains fixed through all four missions. Each mission resets stock and game state; results offer **Continue to next mission**. The final mission shows session completion.

The existing structured judgment fields remain, with a required main-reason selection. All three private responses precede a full 120-second discussion and the existing 15-second support reading gate. Normal play cannot use the sandbox skip or hidden-state reveal. No new post-decision questionnaires, model provider, or external calls were added.

`cascade/scenario_order` in Project Settings accepts each registered ID exactly once. An empty value explicitly records `development_default_not_randomized` and uses Riverside, Twin Districts, Lifeline, Crossfire. This fallback is a demo order, not a randomized or approved study assignment.

## Dev Mode

**Dev Mode**, directly below Play, opens the four-district picker. Select **Start** for a fresh single mission, then **Begin actions** after each public report. Private forms, discussion, support generation, and reading timers are skipped. Supplies, action costs, deliveries, pressure progression, and scoring remain unchanged.

**Menu → Reveal hidden state** is optional and starts off. The sandbox always shows **DEV MODE — NOT RESEARCH DATA**, even when reveal is off. Results provide Replay, Choose another scenario, Main menu, and a DEV-labelled local JSON export. The results inspector and picker scroll when necessary, including when navigating by keyboard.

Leaving an unfinished mission requires confirmation. Completed mission records remain in the current normal session until it is discarded; export before leaving if they are needed. Exports and session state are local/in-memory. This task adds no persistence backend or transmission.

## Files and implementation

- `scenarios/registry.json`: explicit ID/path/title/description registry included in exports.
- `scenarios/scenario_02.json` through `scenario_04.json`: byte-for-byte copies of the supplied maps. `scenario_01.json` and Riverside artwork are unchanged.
- `scripts/scenario_data.gd`: ID/path loading with useful errors, graph/geometry/report/stock validation, and canonical initial exposure lists. Crossfire declares B and F without changing spread rules.
- `scripts/mission_session.gd`: session ID, fixed condition, configured order, completed records, and guarded mission advancement.
- `scripts/game_manager.gd`: immutable public run purpose, sandbox-only action transition, enforced discussion gate, unique process-wide callback generations, and marked exports.
- `scripts/ui/main.gd`: main menu, level picker, normal-session continuation, sandbox navigation, and accessible results controls.
- `scripts/ui/network_view.gd`: Riverside-specific artwork profile and illustrated map profiles for the three new districts. Hit targets, camera focus, route previews, couriers, and closures share the registered artwork geometry. Simulation coordinates and road lengths remain unchanged.
- `scripts/ui/presentation_text.gd`: debug output lists all initial exposures.

Schema 4 session exports contain separate completed `missions`, an optional `in_progress` record, order/source, session identity, and per-mission indices. Every sandbox export and mission includes `run_purpose: dev`, `research_eligible: false`, `surveys_skipped: true`, and `dev_used: true`. Survey collections remain empty. Revealing, restarting, or changing a dev level cannot make the record eligible. `research_submission()` rejects sandbox records at the domain boundary; normal records also remain ineligible because this project has no approved submission configuration or backend.

## Build outputs and participant configuration

- Demo: `build/scenario-pack-web/index.html`, packaged as `build/cascade-lab-scenario-pack-web.zip`.
- Participant configuration: `build/participant/index.html`, packaged as `build/cascade-lab-participant-web.zip`.

Both web exports use the existing single-threaded Godot Web target. Serve each directory over HTTP to play; opening the HTML directly from disk is not sufficient.

The **Web Participant** preset adds the `participant` feature, which disables the development entry even when `cascade/development_access` is true. Setting that project flag false also disables the entry in native builds. This is interface configuration, not hidden-state security or approval to recruit participants. Dev-data exclusion remains enforced independently. Client assets still contain scenario ground truth, as before.

## Validation actually run

Godot 4.7.1:

| Suite | Checks | Failures |
| --- | ---: | ---: |
| Rules and existing Riverside strategy | 510 | 0 |
| Support filtering, templates, and timing | 2,003 | 0 |
| Existing UI workflow, adapted to menu and sandbox | 192 | 0 |
| Supplied eight scenario playthrough fixtures through production loader | 263 | 0 |
| Registry, malformed input, mission sessions, sandbox flags, physics, stale tokens | 660 | 0 |
| Four-mission normal UI session with fixed condition and distinct records | 144 | 0 |
| Existing presentation suite, headless layout checks | 5,818 | 0 |
| Existing redesign suite, headless layout checks | 1,416 | 0 |
| Windowed menu, all four sandbox playthroughs, geometry, screenshots, map switches | 2,364 | 0 |

Windowed checks cover 1440×900 and 1200×800, all four boards, focused inspection, results, and identical public pixels under different unrevealed pressure values. Screenshot inspection caught and corrected a results/footer overlap at the smaller size. Pending delivery, resolution, and support-display callbacks were tested against scenario switching. Source byte comparisons confirm all new JSONs match the pack and Riverside is untouched.

Both Web exports completed. In-browser runtime verification was unavailable: the in-app browser failed to attach and no Chrome connection was available. Native tests ran successfully. Sandboxed headless Godot emitted macOS certificate-store and editor-settings-save warnings; these did not prevent the tests or exports. No deployment, upload, commit, or push was performed.

To rerun a suite, use `Godot --headless --log-file /tmp/cascade-tests.log --path . --script res://tests/test_missions.gd` (substitute the relevant test). Run `test_mission_ui.gd` without `--headless` for screenshots. The screenshot directory is `/private/tmp/cascade-mission-ui`.

The scenarios remain engineering prototypes. Software tests do not establish equal difficulty, valid counterevidence, ethics approval, or participant readiness. The original deterministic-information and scenario-balance limitations remain.

## City artwork integration — 2 October 2026

The three light overhead city illustrations from **Create light-themed city view** are now included in `assets/maps/twin_districts.png`, `lifeline.png`, and `crossfire.png`. These are unchanged copies of the supplied PNGs. Riverside retains its previous artwork and presentation.

`scripts/ui/city_map_profiles.gd` registers eight building frames and every scenario road to each illustration, including driveway approaches and road junctions. The registration is exclusively visual: scenario JSONs, supply routing costs, pressures, and game rules are unchanged. The existing green surveillance frames, building names, public status tags, selection, camera focus, couriers, and road-closure markers are drawn on the artwork. Labels are arranged to avoid one another at overview sizes; hidden pressure never influences their placement.

Validation: the windowed `tests/test_city_art.gd` passed 1,160 checks with zero failures. It checks both 1440×900 and 1200×800, all three images, label separation, building and road hit targets, reverse delivery paths, camera focus, isolation previews and delivered closures, and unchanged public pixels when unrevealed pressures change. The existing UI regression and eight production playthrough fixtures also pass. Both web archives were rebuilt with the artwork. In-browser verification remains unavailable as recorded above.

## Road/artwork alignment correction — 3 October 2026

The original city-art registration described above has been superseded by the
shared world-space layouts and regenerated terrain in [MAP_ALIGNMENT.md](MAP_ALIGNMENT.md).
All four maps now use open junction endpoints, separate landmark selection,
deterministic streets and continuous multi-edge vehicle routes. See that report
for sources, before/after screenshots, regression results and the browser-test
limitation.
