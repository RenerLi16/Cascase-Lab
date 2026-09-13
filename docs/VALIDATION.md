# MVP validation record

Tested on September 13, 2026 using Godot **4.7.1.stable.official.a13da4feb**, macOS, Apple M4, and the Compatibility renderer.

## Automated checks

- **187 rule checks: passed.** Covers deterministic scenario setup, reverse supply transportation, directed infection, Overrun routing obstruction, per-depot isolation previews, resource deduction, stale/invalid requests, atomic confirmation, exact dated verification, persistent monitors, stacked infection, shield blocking and expiry, permanent isolation, permanent Overrun states, all mandatory phases, repeatable JSON exports, and restart.
- **227 UI integration checks: passed.** Loads `scenes/Main.tscn` and exercises real screen controls and map hit testing. Covers six private forms with blank defaults, six privacy handoffs, both anonymous comparisons, discussion/actions, all four action types, paying-depot selection, multiple confirmed batches, isolation's second warning, cancellation, clearing plans, disabled action reasons, mandatory diagnostic evidence, all three summaries, results, JSON save-dialog completion, development mode, and restart.
- Final test logs contain no script errors. The native project starts successfully.

## Complete logical/UI playthrough

| Round | Confirmed actions | New Overrun | Supplies afterward |
| --- | --- | --- | --- |
| 1 | Verify B from H; Monitor E and Shield E from A; Isolate D–G from H | None | A 1, H 0 |
| 2 | Shield E from A | None | A 0, H 0 |
| 3 | None | E; monitor reports 1 → 2 | A 0, H 0 |

Final result: **6/8 surviving**, Overrun **D and E**, **0 supply**. B's Round 1 verification remains a dated Pressure 1 record. The result includes both belief sets, two source-belief changes in the test fixture, the ground-truth timeline, and complete event data. The native save dialog's callback wrote and roundtripped the resulting structured JSON.

## Strategy comparison

- Isolating both outgoing roads from D before Round 1: **7/8 survive**, two supplies remain.
- Shielding E and G every round: **7/8 survive**, zero supplies remain.
- No containment: **1/8 survives**.
- Test-only random legal-action baseline: **2.42/8 average**, 200 trials with fixed seed 73019. This is a repeatable baseline rather than a human-performance claim.

## Visual and input checks

Rendered screenshots were captured for the menu, briefing, privacy gate, initial and updated private forms, belief comparisons, actions, isolation preview, plan confirmation, diagnostic evidence, summary, results, and dev mode. Inspected full-size and smaller-laptop renders, including 1440 × 900 and 1100 × 720. Fixed an automatic first-answer selection issue in Godot's OptionButton and a font-rendering configuration that degraded bold text. Moved immediate action results to the top of the Plan tab and cleared map captions from vertical arrows.

The running native app was also opened and its briefing/rules controls checked using actual mouse input, including fullscreen. It was left open for play.

## Remaining platform verification

The Web preset explicitly includes the scenario JSON and disables threads/extensions. **Matching Godot Web export templates are absent on this machine. No HTML/WASM/PCK build was produced, no browser playthrough was performed, and nothing was deployed.** Follow the README's future deployment procedure to validate an exported build and its download behavior in Chrome before publishing.

This record concerns the local MVP, not networked play, experiment-grade anonymity, or backend persistence; those are outside the requested implementation.
