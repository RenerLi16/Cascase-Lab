# Medieval UI refinement review

The eight original tower designs and wood/brass controls are retained. Towers now stand on the existing visual network anchors instead of legacy building rectangles. The simulation and scenario files are unchanged.

## Presentation changes

- `WoodlandArt.metadata()` defines each sprite’s ground pivot and lamp origin. The tower rectangle, camera focus, hit target, selection brackets, lights and labels derive from this mapping. Public arrival positions now use the same ground anchor as courier route endpoints.
- Removed decorative driveways. Existing road centerlines, routing and lengths are unchanged. Short terminal portions of connected roads are drawn over the foreground of each entrance to make their mouths visible.
- A single lightweight Compatibility-renderer shader relights the original forest texture, preserving tree and ground surfaces. Cool ambient colors give way to warm soft illumination around tower bases. Maximum blending controls overlapping pools. The lamp artwork and local glow share individual sprite anchors.
- The shader receives only visual positions and public beacon on/off values. P0/P1, supplies and experimental condition are absent from its inputs. Overrun switches off the corresponding lamp; loss of supply does not. Reduced motion retains static illumination.
- Forest density varies, clearings preserve roads and towers, and all network roads remain drawn from actual edge geometry.
- Labels are packed near their towers and avoid complete road corridors, other towers, UI bounds and each other. Leader lines are used only for a substantial remaining gap. Inspection prioritizes the selected label and hides detached labels belonging to towers behind the interface.
- Top HUD padding and the bottom instruction surface are smaller. The map remains full viewport. The end-round arrow, actions, survey controls and original animation durations are preserved.

## Review artifacts

Open [the local before/after gallery](../build/medieval-refinement/index.html). It includes:

- Clean before/after 1440×900 overviews of all four scenarios.
- Clean 1200×800 overviews and inspection comparisons.
- All eight tower inspection captures for each scenario at both sizes (additional test captures include an explicit offline-test notice).
- English and Simplified Chinese practice overviews and inspection at both sizes.
- Overrun/no-supply lighting fixtures and a short selection/courier animation video.
- Development overlay captures. Cyan identifies sprite/click bounds; magenta and white coincide at network anchors and ground pivots/light origins; green marks road endpoints; yellow marks lamp origins. `debug_anchors` defaults to false and is enabled only by capture tests.

Inspected the four clean scenario overviews, smaller scenario views, selected tower inspection views, English/Chinese practice, public-state fixtures and the anchor overlay visually, in addition to automated checks.

## Verification

| Check | Result |
| --- | --- |
| Native medieval visual/integration suite | 27,314 checks, zero failures; includes exact rendered P0/P1 comparisons for four scenarios at both sizes |
| Additional geometry/full-status/selected-label assertions | 27,442 checks, zero failures in headless run |
| Native practice inspection, both languages and sizes, every node | 464 checks, zero failures |
| Native controls, rendered public light mask, supply loss, delivery timer | 104 checks, zero failures; final long delivery measured 2,060 ms against the existing 1.5 s transit + 0.55 s arrival |
| Rules | 507 checks, zero failures |
| Production scenario fixtures | 263 checks, zero failures |
| Support conditions | 2,004 checks, zero failures |
| UI | 197 checks, zero failures |
| First play | 855 checks, zero failures |
| Practice isolation | 10 checks, zero failures |
| Presentation, including all experimental conditions | 6,286 checks, zero failures |
| Diff whitespace / gallery file links | Passed |

The first concurrent native control run narrowly failed the existing wall-clock duration threshold. Delivery code was unchanged. Settling pending control redraws before measurement produced a passing isolated final run; original transit, arrival, spread and intervention timings remain untouched.

The offline Web export was exercised in the in-app browser at 1440×900 and 1200×800. Tower selection, inspection, a real VERIFY delivery, Overview, drag and wheel zoom worked. The delivery recorded exactly one action and reduced supply from six to five. Sampled steady views ran at 60 fps, 4.2–7.2 ms process time and approximately 45–50 MiB static engine memory. No browser console warnings or errors were captured.

## Limits and scope

Browser performance measurements apply to this Apple M4 Mac and its in-app browser, not to untested phones or low-end GPUs. Lighting is decorative surface shading, with no shadow engine or gameplay radius. Full backend/database suites were not rerun because no backend, provider, logging, access-code, scenario or domain logic changed. All runs used offline fixtures; nothing was deployed, committed, pushed or sent to a paid model provider.
