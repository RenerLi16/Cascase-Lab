# Refactor validation record

Tested on September 13, 2026 with Godot 4.7.1 stable, macOS, Apple M4, and the Compatibility renderer.

The refactored project passes:

- 455 deterministic mechanics checks in `tests/test_rules.gd`.
- 135 real scene/UI checks in `tests/test_ui.gd`.
- Godot editor/import startup with no project parser errors.

The suites exercise the one-hidden-exposure start, no initial Overrun, hidden pressure, bidirectional roads, irregular map topology, loops and chokepoints, shortest supply paths, two-endpoint isolation, split depot funding, fixed supplies, delivery and resolution phases, private survey handoffs, structured public intelligence, Verify-on-arrival, Monitor alerts, Shield expiry, map pan/zoom/center, Dev Mode, restart, and structured JSON logging.

The strategy suite reports an informed 7/8 survival result, 3/8 with no containment, and a seeded random legal-action baseline averaging 3.62/8 over 200 trials. Randomness exists only in this test baseline; gameplay and the scenario are deterministic.

The UI test also verifies that normal play has no Beliefs, Reports, or Log tabs; private fields begin blank; survey responses remain internal; delivery animation locks the phase; isolation sends one unit to each endpoint; and the first hidden exposure becomes Overrun during gameplay. It can run headless or with a window. Windowed runs can capture screenshots under `/tmp/cascade-lab-qa`.

The native project starts successfully. Web export templates are not installed on the development machine, so the Web preset is prepared but an HTML/WASM/PCK browser build has not been compiled or deployed. Follow the Web/itch.io procedure in the README and perform a browser smoke test before publishing.
