# Instructor Dev Mode web export verification — 2026-10-09

## Result and export selection

The existing menu already contained Dev Mode, the masked password dialog, the session-only gate, and the four-scenario offline sandbox. No duplicate controls or alternate sandbox were added. The release helper defaults to **Web Participant**, which intentionally hides Dev Mode; the expected instructor release folder was absent at inspection. The instructor and participant releases were rebuilt separately from the current source.

| Audience | Exact preset | Exported files | Upload archive |
| --- | --- | --- | --- |
| Instructor/demo, with password-gated sandbox | **Web Instructor** (`instructor`) | `build/itch-instructor/` | `build/cascade-lab-itch-instructor.zip` |
| Research-participant, without developer access | **Web Participant** (`participant`) | `build/itch/` | `build/cascade-lab-itch.zip` |

Use the instructor archive above for the requested demo. Older files in `build/itch-upload/` were left untouched. Each new archive has `index.html` at its root and a `build-info.json` identifying the audience, preset, sandbox availability, and hashes of the exported files. Both ZIP integrity and contained-file hashes were verified.

The release helper overrides the preset's direct-editor output location. Direct Godot export of **Web Instructor** uses `build/instructor/index.html`; the release helper used here writes the actual deliverable to **`build/itch-instructor/index.html`** and sets the existing HTTPS backend origin for regular Play.

Reproduce the instructor release:

```sh
python3 tools/build_web_release.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --backend-url https://cascade-lab-backend.onrender.com \
  --preset "Web Instructor"
```

Use `--preset "Web Participant"` for the separate restricted release. The default remains participant. The project-wide development setting and participant feature restrictions were not relaxed.

## Changes in this task

- Added release audience/preset metadata and exported-file hashes to prevent confusing the participant upload with the instructor upload.
- Added a second local-only safeguard in `StudySync.attach`: it rejects sandbox attachment and retains the local mock provider, even if a future UI caller accidentally tries to attach a sandbox to saving.
- Extended the existing menu tests to exercise that boundary for all four scenarios.
- Preserved the existing menu layout, animations, password digest, dialog, scenario picker, game rules, resources, and inspector.

The gate remains a client-side convenience, not authentication. Unlocking only affects the sandbox in application memory. It grants no backend administration, participant-record access, or provider credentials. No password was added to UI hints, errors, logs, URLs, documentation, or build metadata.

## Actual release-build browser checks

Tested the unmodified release files above in local Chrome using Playwright, with software WebGL. All external requests were intercepted and aborted before reaching the network. The source project was not instrumented for these browser checks. Screenshots were reviewed visually; OCR assisted navigation and inspection.

| Check | Result |
| --- | --- |
| Dev Mode visible directly below Play | Passed at 1440×900 and in 960×600 / 720×450 iframes |
| English and Simplified Chinese menu/dialog | Passed; text and buttons fit, and the dialog stays above the decorative network |
| Masked field | Passed; entered text rendered as masking characters |
| Invalid password and case-changed password | Stayed in dialog; clear incorrect-password message; picker did not open |
| Enter | Submitted incorrect and correct entries as expected |
| Cancel and Escape | Returned to menu without unlocking |
| Unlock button | Correct entry opened the picker in the Chinese iframe dialog |
| Session-only unlock | Returning from scenarios retained access; reloading the page required the password again |
| Four choices | Riverside, Twin Districts, Lifeline, and Crossfire all opened successfully |
| Sandbox research bypass | Each scenario started at Observe with six supplies, then Begin actions immediately entered Select actions; no study code, forms, discussion countdown, or AI pause |
| Optional hidden state / inspector | Started off; explicit confirmation enabled it; inspector opened |
| Sandbox return paths | Returned to scenario picker and main menu through the existing controls |
| Regular Play after sandbox | Entered practice without a password; completed practice and entered a fresh normal mission with 6/6 supplies, public-only board, private-proposal flow, and no dev label |
| Regular Play while Dev Mode locked | Fresh instructor load entered practice directly without a password |
| Normal-session isolation | Browser outbox contained only the normal public-demo session, with no sandbox mission records |
| Participant export | No Dev Mode button; Play entered the normal mission without a password |
| Sandbox/menu network activity | Zero outbound requests and zero browser console/page errors before normal Play |

The normal Play checks intentionally produced blocked attempts to the existing anonymous-session endpoint. No remote sessions were created, records uploaded, or model calls made. Browser contexts were disposable and closed after verification. The network summary is in `build/dev-web-verification/network-results.json` and contains no session credentials or password.

The four-card picker scrolls at ordinary iframe sizes. `scenario-picker-all-four.png` uses a taller viewport to show all four cards in one screenshot; the 960×600 iframe picker was also exercised.

## Screenshots

- [English menu](../build/dev-web-verification/menu-en.png)
- [Password dialog](../build/dev-web-verification/password-dialog.png)
- [Masked entry](../build/dev-web-verification/masked-password.png)
- [Incorrect password](../build/dev-web-verification/incorrect-password.png)
- [Unlocked picker — all four scenarios](../build/dev-web-verification/scenario-picker-all-four.png)
- [960×600 iframe — English](../build/dev-web-verification/iframe960-menu-en.png)
- [960×600 iframe — Chinese](../build/dev-web-verification/iframe960-menu-zh.png)
- [960×600 iframe — Chinese dialog](../build/dev-web-verification/iframe960-dialog-zh.png)
- [720×450 iframe — Chinese](../build/dev-web-verification/iframe720-menu-zh.png)
- [Refresh relocked](../build/dev-web-verification/refresh-relocked.png)
- [Regular Play after sandbox](../build/dev-web-verification/regular-play-clean.png)
- [Participant menu](../build/dev-web-verification/participant-menu.png)

Additional scenario, practice, and inspector screenshots are in `build/dev-web-verification/`.

## Automated checks

Godot 4.7.1:

- `tests/test_title_menu.gd`: **948 checks, 0 failures**, with `--headless --fixed-fps 60 -- --offline-tests`. The password was supplied through the existing `CASCADE_DEV_PASSWORD` environment input, not embedded in the test.
- `tests/test_missions.gd`: **665 checks, 0 failures**, including sandbox progression, resources, support rejection, normal-mode separation, and submission rejection.
- `git diff --check`: passed.
- Both release ZIPs: integrity and all manifest hashes passed.

The first uncapped headless menu run failed one spring-settling timing assertion because the test waits a fixed number of frames. Re-running with a fixed 60 Hz simulation timestep passed all checks; the animation code was unchanged. Headless Godot also emitted a macOS certificate-store warning, and temporary export imports could not save global editor preferences; both exports completed successfully and the resulting browser builds loaded without script errors.

Limitations: tested locally in Chrome and local iframe hosts, not on the live itch.io page, Firefox, Safari, or physical touch devices. No deployment, commit, push, cloud setting change, or paid model call was performed.
