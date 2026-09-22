# Dark interface validation — September 2026

- Rule suite: **485 checks, 0 failures**.
- Support suite: **1,994 checks, 0 failures**.
- Updated gameplay UI suite: **184 checks, 0 failures**.
- Full three-round presentation suite: **5,842 checks, 0 failures**.
- Windowed redesign suite: **1,416 checks, 0 failures**, including all twelve support templates, every building close-up, survey retention, actual form bounds, and countdown expiry at 1440 × 900 and 1200 × 800.
- Browser export loaded locally; building selection, information panel, private handoff, and survey rendering were inspected. No browser console warnings or errors were reported during the smoke test.
- The browser archive was checked for integrity and for index.html / index.pck at the ZIP root.

Current screenshots and implementation notes: [Dark UI redesign](DARK_UI_REDESIGN.md). Older validation below describes the preceding release.

---

# Refactor validation record

Tested on September 14, 2026 with Godot 4.7.1 stable, macOS, Apple M4, and the Compatibility renderer.

The refactored project passes:

- 485 deterministic mechanics checks in `tests/test_rules.gd`.
- 142 real scene/UI checks in `tests/test_ui.gd`.
- 1,994 controlled-support checks in `tests/test_support.gd`.
- Godot editor/import startup with no project parser errors.

The suites exercise the one-hidden-exposure start, no initial Overrun, hidden pressure, bidirectional roads, irregular map topology, loops and chokepoints, shortest supply paths, two-endpoint isolation, split depot funding, fixed supplies, delivery and resolution phases, private survey handoffs, structured public intelligence, Verify-on-arrival, Monitor alerts, Shield expiry, map pan/zoom/center, Dev Mode, restart, and structured JSON logging.

The strategy suite reports an informed 7/8 survival result, 3/8 with no containment, and a seeded random legal-action baseline averaging 3.62/8 over 200 trials. Randomness exists only in this test baseline; gameplay and the scenario are deterministic.

The UI test also verifies that normal play has no Beliefs, Reports, or Log tabs; private fields begin blank; survey responses remain internal; delivery animation locks the phase; isolation sends one unit to each endpoint; and the first hidden exposure becomes Overrun during gameplay. The support suite checks hidden-state independence, anonymous inputs, all template word limits, executable recommendations, non-prescriptive dissent, and a shared timed pause. Windowed support runs capture `/tmp/cascade-support-0.png` through `/tmp/cascade-support-2.png`.

The native project starts successfully. All three support cards were visually inspected in windowed runs. Matching single-threaded Web templates are installed. The updated Web release exported successfully to `build/support-web/`, and its initial game screen loaded correctly in the in-app browser through a local HTTP server. This browser smoke check does not claim a full three-round browser playthrough. The upload archive is `build/cascade-lab-support.zip`; replace the existing itch.io upload to update the hosted game.
