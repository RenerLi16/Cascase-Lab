# Main menu and password-gated Dev Mode (2026-10-08)

Status: implemented locally, **not committed, pushed or deployed**. No cloud or backend settings were changed.

## What changed

- **Title screen** (`scripts/ui/title_screen.gd`): a very large pixel title "CASCADE LAB" with the smaller "OUTBREAK" subtitle, two short orientation lines (English / Simplified Chinese), a prominent **Play** button, and a smaller **Dev Mode** button directly below it. Language and motion toggles sit in the top-right corner. No enclosing panel or cards.
- **Decorative network** (`scripts/ui/menu_network.gd`): plain circles and lines drawn with Godot's own `_draw`/`_gui_input`, placed around the outside of the screen from a fixed random seed. Nodes drift around their homes, enlarge and light their links on hover, pop on click, and can be dragged; on release they spring back. It is unrelated to any scenario, hidden state, solution, AI output or study condition, and nothing it does is logged, uploaded or sent to a model.
- **Play** enters the existing introduction/practice/normal flow directly, without a code or intermediate setup screen. Repeated clicks are handled once. *Replay practice* appears on the title after practice. Pending-save status and *Export pending recovery JSON* remain in the quiet footer. See [Public Play](PUBLIC_PLAY.md) for backend authorization and data-policy defaults.
- **Dev Mode** opens a password dialog in web and instructor builds (masked field, Unlock / Cancel, Enter submits, Escape cancels, focus kept inside, short "Incorrect password." message). On success it opens the existing developer level picker.
- Title font: **Silkscreen** Bold/Regular (SIL OFL 1.1, bundled in `assets/fonts/` with `Silkscreen-OFL.txt`; the export filter already ships `*OFL.txt`). Imported without antialiasing and sized in multiples of 8 so pixels stay square. All other text keeps Barlow with the Noto Sans SC fallback. No global theme change, so game screens are unaffected.

## Keeping the interface clear

Protected areas are read every frame (and again at draw time) from the real global rects of the title column, Play, Dev Mode, replay practice, the corner toggles, the footer, the password dialog and any error modal, each grown by 20–48 px. Nodes are pushed out with room for their largest hover/spring size; a line that would cross any protected area is not drawn; anything that cannot be placed clear is skipped that frame. Layout containers ignore the mouse, so the network only receives input where there is no control, and a drag that ends over Play cannot press it (Godot routes the release to the network).

Small windows get fewer nodes first (density follows the physical free area); text grows slightly in logical units when the window is scaled below 80 % so it stays readable. The title breaks onto two lines only if one line would not fit.

Reduced motion (browser `prefers-reduced-motion`, or the corner toggle) keeps a static network with hover and focus feedback but no drift, spring or fade. The network pauses while a dialog or modal is open and is freed when the game starts.

## Dev Mode access and separation

`scripts/ui/dev_gate.gd`:

| Build | Dev Mode button | Password |
| --- | --- | --- |
| Editor / native development (`development_access=true`) | yes | no (existing offline behaviour) |
| Web dev export (`Web` preset) | yes | yes |
| **Web Instructor** preset (`instructor` feature) | yes | yes |
| **Web Participant** preset (`participant` feature) | never | — |

- The password is case-sensitive. Only a salted SHA-256 digest is in the source; the plain text is not in the repository, the export, the UI, URLs, logs or errors. To change it, replace `DIGEST` with `sha256("cascade-dev-gate-v1:" + new_password)`.
- The unlock lives in memory only (`DevGate.unlocked`). Refresh or restart locks it; *Lock Dev Mode* on the level picker locks it explicitly. Returning from a dev run keeps it.
- **This is a convenience gate, not authentication.** Anyone with the web files can inspect or bypass it. It unlocks only the local sandbox: no backend administration, participant records, other sessions' exports or AI requests.
- Sandbox runs are no longer attached to automatic saving (previously they were uploaded as synthetic sessions) and use the local mock support provider. Dev exports no longer include other sessions' pending upload records.
- Sandbox play is unchanged otherwise: any of the four scenarios, no surveys, discussion timers or AI pauses, the same rules/supplies/deliveries, the optional hidden-state inspector, and the "Dev mode — not research data" label.

Build the instructor web upload with:

```sh
python3 tools/build_web_release.py --godot <Godot> --backend-url https://<backend> --preset "Web Instructor"
```

It writes `build/itch-instructor/` and `build/cascade-lab-itch-instructor.zip`. The participant build (`--preset "Web Participant"`, default) is unchanged and never offers Dev Mode.

## Historical validation before public Play (Godot 4.7.1, Linux x86_64, Xvfb + Chromium/SwiftShader)

- New `tests/test_title_menu.gd`: 1,076 checks, 0 failures — 1440×900, 1200×800 (native and scaled), 960×600 and 720×450 embeds in English and Chinese; per-frame "nothing over the interface" checks while idle, hovering, dragging across Play, resizing mid-drag, switching language and stage; reduced motion; keyboard focus; access-code setup (manual, paste, invalid, Escape, explicit Start); password dialog (wrong/case-changed, Enter, Escape, Tab/Shift+Tab containment, correct); all four sandbox scenarios with no saving attachment, mock provider and clean export; normal play after sandbox inherits nothing; lock/relock; participant configuration.
- Existing suites: rules 507/0, UI 198/0, UI improvements 25,493/0, first play 863/0, practice isolation 10/0, medieval 27,578/0, session UI 168/0. Mission UI keeps its 56 pre-existing failures (identical to HEAD). `test_access_code_recovery` needs its backend harness and was not run.
- Exported web builds driven in headless Chromium (Playwright): dev, instructor (1200×800) and participant (960×600 iframe) builds; load, hover, drag over Play, wrong/correct password with Enter, Escape, refresh relock, all four scenarios and return to the picker, Play into practice, Paste with clipboard permission, reduced motion frame-identical, touch drag and tap. Request logging showed **no backend or model requests** from the title, setup step, Dev Mode, sandbox or practice.

## Limitations

- Browser checks used software WebGL and pixel/coordinate probes, not real devices; Safari, Firefox and physical touch devices were not tried, and the itch.io page itself was not tested.
- The Chinese strings for the new title/setup/dialog copy were written here and should be checked by a native speaker.
- Pending outbox records from earlier normal sessions still retry in the background as before (existing recovery behaviour); the title screen itself creates nothing.
