# Terrain, source selection, and Paste review

Date: 2026-10-08. Godot 4.7.1 Compatibility renderer on macOS.

## Changes

- `WoodlandArt.terrain_definition()` supplies scenario-specific river curves, bank widths and scenery seeds. Riverside keeps its former river placement. Twin Districts and Lifeline have one central crossing; Crossfire has three crossings. Practice also has a river fitted between its existing towers. Towers, anchors, road centerlines, graph topology and logical edge lengths are unchanged.
- River rendering, animated ripples, tree exclusion, bank stones and bridge detection use that same definition. Bridges follow actual road segments and extend onto dry banks. Cache identity includes terrain configuration, building footprints and road geometry; scenery has no hidden-state inputs.
- `SupplySourcePicker` is shared by research, developer and practice modes. It highlights all eligible depots without preselection, retains destination markers, previews existing shortest routes and requires confirmation. Verify/Monitor/Shield choose one source; Isolate chooses each endpoint separately and filters the second choice against feasible combinations. Back, Cancel, source changes, no-source explanations and stale-selection recovery are included in English and Simplified Chinese.
- Selection never reserves supplies. Confirmation rechecks existing delivery eligibility before calling the original authoritative dispatch. A synchronous confirmation lock, click debounce and run-generation guards prevent duplicate/stale actions. Existing arrival timing, isolation effects and logged origins are retained.
- `AccessCodeEntry` adds themed Paste / 粘贴 controls. Only explicit activation reads the clipboard through Godot's JavaScriptBridge and the browser clipboard API. Outer whitespace is trimmed; case is preserved. Manual and pasted input share validation. Empty, multiline and oversized contents are handled without exposing text in logs.
- Editing only updates the field and Play availability. An explicit Play/Replay commits the access code, so pasted or partially typed codes cannot trigger pending credential retries. Clipboard denial/unavailability disables further API requests and leaves the field editable with the requested Ctrl+V / ⌘V fallback. Outstanding callbacks are cancelled when the entry leaves the scene.

## Verification

| Suite | Checks | Failures |
|---|---:|---:|
| New UI improvements, native rendered run | 25,245 | 0 |
| Rules | 507 | 0 |
| Scenario fixtures | 263 | 0 |
| Support | 2,004 | 0 |
| UI | 198 | 0 |
| First play | 855 | 0 |
| Practice isolation | 10 | 0 |
| Presentation | 6,076 | 0 |
| Redesign | 1,440 | 0 |

All four maps were checked at 1440×900 and 1200×800, at overview and each tower's inspection view, plus pan/zoom transforms. Tests verify dry full tower footprints, full bank-to-bank bridges, authoritative geometry and pixel-identical rendering after hidden pressure changes. Native final run has no script errors. `git diff --check` passes.

Source coverage includes one/multiple/zero eligible depots; non-depot rejection; source changes; Back/Cancel; repeated confirmation; same/different isolation sources; insufficient stock; live-stock changes; session changes; action origins, routes, costs and effects; delayed road closure; three experimental conditions; and bilingual practice. Existing tests now explicitly choose sources rather than assuming automatic assignment.

The isolated web export was exercised in Codex's Chromium-based in-app browser at 1200×800:

- Standalone Paste accepted a synthetic mixed-case code with surrounding whitespace; validation became valid while `session_started` and `code_submitted` remained false.
- A short synthetic code remained invalid. A 6,000-character clipboard payload was rejected without inserting it or enabling Play.
- A local cross-origin iframe (`127.0.0.1` parent, `localhost` child) with clipboard-read denied showed the fallback and disabled further Paste attempts.
- The same local iframe with clipboard-read/write allowed still reached the bounded fallback in this browser environment. Successful clipboard API reads inside that configuration are **not** claimed.
- Browser source selection displayed both depots with no default, previewed H → C while supplies stayed at six, and produced exactly one action with five supplies after confirmation. No warning/error console entries were observed for that flow; the sampled frame rate was 60 FPS.

The web harness contains only non-sensitive review metadata (length/validity/status and a comparison to a fixed synthetic fixture). It is generated in a temporary offline project, never reads the study outbox, and is not the production entry scene. Native tests also run with `--offline-tests`.

## Screenshots and local preview

- Gallery: `build/three-improvements/index.html`.
- All four clean participant overviews at both sizes: `overview-*.png` and `1200-overview-*.png`.
- Inspection captures: `1440-*-inspection-*.png` and `1200-*-inspection-*.png`.
- Source selection: `source-choose-*.png`, `source-confirm-*.png`, `isolate-*.png`, `source-none.png`, and `web-source-*.jpg`.
- Bilingual Paste and practice: `1200-paste-*.png`, `1200-practice-*.png`; actual standalone success and restricted-iframe captures: `web-paste-success.jpg`, `web-iframe-blocked.jpg`.
- Offline exported web preview: `build/three-web/index.html`; `embed-allowed.html` / `embed-blocked.html` are local test fixtures.

Reproduce the new native suite:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --log-file /tmp/cascade-ui-review.log --script tests/test_ui_improvements.gd -- --offline-tests
```

Rebuild the isolated web review:

```sh
PREVIEW_OUTPUT=build/three-web python3 tools/build_medieval_preview.py
```

## Limits

No actual itch.io/production embedding, Safari, Firefox, mobile browser, or insecure HTTP host was tested. Native validation covers editable fallback behavior; browser automated typing into Godot's IME field did not provide a reliable full-string result. Production hosting permissions remain unmodified. Screenshot/build outputs are intentionally git-ignored local artifacts.

No deployment, commit, push, infrastructure change, paid model call, research upload, backend edit, scenario-rule change, or survey/AI-timing change was performed.
