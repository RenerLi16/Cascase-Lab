# Controlled support — support-1.0.0

This is a reproducible experimental manipulation implemented with local templates, not a conversational model. No credentials, API calls, participant names, microphones, chat boxes, or external knowledge are used.

## Assignment and delivery

Before the first private judgment, the facilitator selects one of the three conditions in **Session setup**. No AI is the default. Assignment is fixed across all three rounds and retained on restart. A fresh run can be reassigned in setup. This is a local facilitator tool; participants are not authenticated, and restart is not a protected researcher operation.

The initial discussion ends only when the team clicks **Finish initial discussion**. The shared `INTERVENTION` phase is presented as **DECISION PAUSE**. A single immutable message is generated for that round. `mark_support_shown()` records first display and starts the monotonic 15-second gate; generation time does not count. Early or duplicate continuation, actions, and resolution are rejected by GameManager, not just disabled buttons. The same card, label sizes, color, countdown, and continuation button serve all conditions. There is no automatic action, preselected recommendation, chat, refresh, or second prompt. Map rerenders do not regenerate the text, reset its deadline, or duplicate the display event. Participants may spend longer than the minimum interval.

## Data boundary

The trusted `SupportContext.build()` adapter creates a new dictionary containing:

| Field | Allowed representation |
| --- | --- |
| shelters | Public Overrun state, public Monitor reading or unknown, dated Verify history, installed monitor/shield markers |
| roads | Public endpoints and closures |
| depots | Visible remaining supplies |
| previous_actions | Completed team action type, target, round, cost, and paying depots |
| public_reports | Already-published report round, fictional time, and text |
| round / remaining_budget | Current round and total remaining supply |
| responses | Validated danger location, proposed action, applicable target, confidence, and enumerated reason only |

It never copies current hidden P0/P1, the source, planned resolution, ground truth, future scenario reports, private IDs, names, or raw text fields. Anonymous response records are sorted so changing player order cannot change output. Verify snapshots stay historical, even if hidden pressure changes later. Monitor installation alone exposes no pressure. Dev Mode does not expand this boundary.

`SupportLibrary.generate()` receives only that dictionary and the condition string. It neither receives nor looks up a scenario ID. It cannot reach a GameManager, GameState, ScenarioData, logger, filesystem, network, clock, or random generator. The scenario ID is attached separately by the logger for audit.

## Deterministic selection

Every message is 35–60 whitespace-separated words including section labels. Road IDs such as E-F count as one word. Tests validate every template, including zero-supply and wait cases.

Direct support independently computes legal supply actions from public road connectivity and depot balances. Isolation requires two reachable endpoints and sufficient combined stock, matching live action rules. A fixed ranking considers anonymous proposal matches, danger-target matches, visible connections, and visibly Overrun neighbors. Shield messages only apply to a functioning neighbor of visible Overrun and are excluded for publicly known exposure. Monitor and isolation suggestions require a corresponding structured proposal. Verify is the baseline legal information action. Stable map-ID/action ordering breaks ties; confidence never identifies a favored respondent. Unanimous waiting and no-funded-route states have distinct explicit wait templates. This policy is a bounded suggestion heuristic, not an optimizer or hidden outbreak solver.

Dissent selects one branch: no executable funded action; differing danger/action/target patterns; differing reasoning categories; low or divergent confidence; otherwise shared agreement. It asks one focused question, suggests an evidence comparison, and never produces an action/target prescription. It reports neither vote counts nor respondent labels. Report prose is passed as public data but is not interpreted or interpolated by a language model in this version.

No AI uses the same dictionary and renderer but shows only neutral scheduling text. It receives the same minimum exposure interval, not a reasoning intervention.

## Logging and anonymity

Schema 3 uses the actual assigned condition. Each round emits exactly one `SUPPORT_SHOWN` event after the card becomes visible. Metadata fields are `condition`, `scenario_id`, `round`, `allowed_inputs` (category labels only), `displayed_text`, `template_id`, and `template_version`. The event envelope holds UTC `timestamp_utc` and monotonic `elapsed_ms`. No support payload, structured responses, identity, or model reasoning is copied into this event.

The original private surveys remain in memory to supply the intervention. Separate research export records are anonymized and sorted within rounds. Submission events have neither answer values nor participant identifiers, preventing a direct join from the chronological handoff receipts back to an answer. Dev Inspector uses the same anonymous representation. The ordinary player interface has no response-comparison screen. Small-group answers can still be recognized through what people voluntarily say; this is not a guarantee of statistical anonymization against outside knowledge.

Exact display replay uses the stored text. Independent regeneration requires the same permitted snapshot and the versioned library; the support log intentionally does not retain a raw snapshot. Retain old library versions when changing wording or selection rules. Simulation research logs still contain hidden game data for research, but are never used as generator inputs.

## Validation

`tests/test_support.gd` checks hidden pressure/source/future-report canaries, removal of private/free-text fields, unchanged output under player reordering, dated evidence, every template's length and structure, executable recommendations across 48 varied public states, agreement and disagreement branches, all conditions through three rounds, display-time logging, repeat prevention, the exact 15-second boundary, restart, export, and shared real-scene rendering. Tests inject a clock; production uses `Time.get_ticks_msec()`.

For manual review, run a new session in each condition, complete the three private forms, finish initial discussion, and inspect the decision card. Confirm that **Proceed to actions** stays disabled for 15 seconds, the card does not select an action, and export contains the matching `SUPPORT_SHOWN` text and condition for each round.
