# Individual post-outcome forms

Normal play follows: initial individual judgments → 120-second discussion → AI/neutral reading pause (at least 15 seconds from display) → team actions and deliveries → outbreak resolution → round summary → three individual round evaluations → next round. After the final round's evaluations, three individual scenario reasoning forms precede scenario results, the next scenario, and final session completion. “End of each move” means a completed round, not a delivery or action. Four scenarios of three rounds produce **36 round evaluations and 12 scenario reasoning forms**, in addition to the unchanged 36 initial judgments.

Practice and Dev Sandbox never collect these forms. Gameplay rules, AI conditions, initial judgments, discussion timing, and reading timing are unchanged. No model calls or deployment are required to collect the forms.

## Proposed instruments

These questions and options are proposed wording, **not validated research scales**. The authoritative definitions, options, character limits, and versions are in `scripts/evaluation_instruments.json`, shared by the game, backend validation, and operator exports. Revise wording and bump the relevant instrument version together; coordinate contract changes with backend validation before releasing a new client.

Round evaluations are collected **after players see the outcome and round summary**. Their confidence is post-outcome confidence. The answers may reflect initial judgments, discussion, constraints, AI, and observed outcomes; they are not a clean measure of AI influence alone.

### Individual round evaluation (`round-evaluation-proposed-1`)

1. How much did you agree with the team’s final decisions this round?
   Options: Not at all / A little / Moderately / Very much / Completely.

2. How confident are you in the team’s final decisions this round?
   Options: Not at all confident / Slightly confident / Moderately confident / Very confident / Extremely confident.

3. Compared with your initial judgment, how much did your preferred plan change?
   Options: Not at all / A little / Moderately / A lot / Completely.

4. What most influenced your final judgment?
   Options: My initial judgment / Team discussion / Public map and observations / Supply and route constraints / AI message / Other.

5. Briefly explain what changed your mind, or why your view stayed the same.
   Required text; maximum 600 characters.

6. How useful was the AI message for your decision-making?
   Options: Not at all useful / Slightly useful / Moderately useful / Very useful / Extremely useful / Unable to judge.
   Only shown for a successfully displayed AI-provider message.

7. How much did you rely on the AI message when forming your final judgment?
   Options: Not at all / A little / Moderately / Very much / Completely.
   Only shown for a successfully displayed AI-provider message.

### Individual scenario reasoning (`scenario-reasoning-proposed-1`)

1. What was your overall strategy in this scenario?
   Required text; maximum 1000 characters.

2. Which decision mattered most, and why?
   Required text; maximum 1000 characters.

3. How did the road and bridge connections, supply access, or uncertainty affect your decisions?
   Required text; maximum 1000 characters.

4. What would you do differently if you played this scenario again, and why?
   Required text; maximum 1000 characters.

Every displayed field is required. Whitespace-only text is rejected; there is no arbitrary minimum length. “Nothing” and “Not sure” are accepted. The form limits typed or pasted text to its maximum and shows a character count.

“AI message” is removed from the influence options unless a nonempty successful Qwen message was actually displayed in that round. The two additional AI questions use the same condition. No AI, unavailable AI, development mock messages, and messages never displayed omit those questions entirely; omitted answers are absent, not zero. `ai_display.not_applicable_reason` records the reason. Assigned AI condition alone is insufficient. Eligibility is frozen when the reading card is marked displayed, and is retained separately for each round.

## Privacy and navigation

Each form has an opaque pass-the-screen gate and identifies its type, scenario, current player slot (P1/P2/P3), and round when relevant. Players start with blank fields. Submitted answers are not compared or shown to teammates. The current player's draft survives map inspection, drawer collapse, rerendering, export, and canceling the leave confirmation. Submission snapshots the answers, clears the draft, and removes the visible form before the next handoff. Leaving an unfinished mission still requires explicit confirmation and records interruption; a browser refresh does not resume gameplay or drafts.

`ROUND_EVALUATION_GATE`, `ROUND_EVALUATION_FORM`, `SCENARIO_REASONING_GATE`, and `SCENARIO_REASONING_FORM` are explicit phases. Submissions require the active form identity (session, scenario, round, type, slot, run generation) and valid answers. Repeated or stale callbacks cannot submit for another player. Next-round and results navigation cannot advance during these phases. Scenario capture and session completion also check required forms. Scenario completion events are emitted only after the last reasoning submission.

The new responses never enter `SupportContext` or Qwen requests, including future rounds. The existing initial-judgment input projection is unchanged. Ordinary gameplay logs contain only submission receipts and phase changes; free text is held only in confidential records and explicit private exports.

## Storage and compatibility

Local exports use schema **7**; new public sessions use schema **9 / cascade-public-9**. Support context remains `cascade-context-3`. Old protected schema-5/6/7 queues and public schema-8 queues retain their original identities, metadata, and record contracts. New tables are additive; existing initial judgments and saved records are not rewritten. Previous local JSON records remain readable as JSON and are not retroactively required to contain forms. The existing browser/native durable outbox remains version 1 because its envelope is unchanged.

Both new record types store:

| Field | Meaning |
| --- | --- |
| `type` | `ROUND_EVALUATION` or `SCENARIO_REASONING` |
| `session_id`, `scenario_id`, `scenario_index` | Session identity, scenario ID, zero-based order index |
| `slot` | Stable `P1`, `P2`, or `P3` slot |
| `condition` | Assigned intervention condition |
| `instrument_version` | Version of the proposed wording/options |
| `submitted_utc` | Client UTC submission timestamp |
| `timing` | `post_outcome_after_round_summary` or `post_outcome_after_final_round_evaluations` |
| `answers` | Question IDs mapped to selected option strings or written answers |

Round evaluations additionally store one-based `round` and `ai_display`: `status`, `provider`, `not_applicable_reason`, `message_id`, `message_version`, `template_id`, and `displayed_utc`. Statuses are `provider_displayed`, `no_ai_condition`, `development_mock`, `ai_unavailable`, and `not_displayed`. The provider intervention ID is retained when available; local display identity falls back to session/scenario/round. Scenario reasoning has no round answer field; its transport envelope uses final round 3.

Local mission exports have separate `round_evaluations` and `scenario_reasoning` arrays, alongside the existing initial judgments and confidential recovery audit. The two dedicated confidential upload channels and backend tables have the same names except the singular `round_evaluation` channel. SQLite and PostgreSQL use identical transactional storage logic. Event ID/sequence retries acknowledge the original record; a changed retry or a second event for the same session/scenario/round/slot conflicts without overwriting an answer. The client queues each record once, persists pending records, bounds batches by UTF-8 byte size, retries transport errors, and sends completion only after acknowledgments. A local persistence error remains visible and offers recovery export.

The operator CSV/Excel export adds separate `round_evaluations` and `scenario_reasoning` sheets with individual question columns, instrument/timing metadata, and AI-display metadata. CSV free text is escaped against spreadsheet formulas; Excel string cells retain text explicitly. Older databases without the new tables export empty form sheets. Every sheet retains server-owned `record_mode` and `research_eligible` classification. Local exports retain their existing classification too.

Public records and AI remain off by default. Form collection does not enable either permission. Public sessions with records disabled retain forms in local storage and explicit recovery exports; no form upload occurs. Such sessions send operational completion with `last_seq=0`, and the client enforces the form barrier. When remote records are enabled, the backend also refuses completed status until all 48 required records exist. Research eligibility remains false; no consent or research approval is implied by these forms.

## Verification

See `tests/test_evaluations.gd`, `tests/test_evaluation_ui.gd`, `tests/test_evaluation_sync.gd`, and `backend/tests/test_evaluations.py`. All fixtures are synthetic. The successful-provider case uses a local fixture or intercepted transport, never a paid call. The UI suite captures both supported sizes in `/private/tmp/cascade-evaluation-ui/` and exercises handoffs, blank forms, validation, maximum-length answers, map inspection, rerenders, navigation cancellation, scrolling, and conditional AI fields.

### Results from this implementation (2026-10-09)

- Four-scenario domain flow: **2,842 checks passed**, covering No AI, a synthetic successful provider message, failure, and development mock output. Each session produced 36 evaluations and 12 reasoning forms; original judgments and both timers remained required.
- Windowed form UI: **812 checks passed** at 1440×900 and 1200×800. Screenshots of both handoff types, blank forms, maximum-length text, and AI fields were visually inspected.
- Durable outbox/retry/completion checks: **34 passed**. The real Godot-to-localhost full-session test added **101 passing checks**, saved 36 initial judgments + 36 evaluations + 12 reasoning forms with maximum-length multilingual/emoji answers, and retried a deliberately lost form acknowledgment without duplication.
- Backend suite: **71 tests run, 60 passed and 11 PostgreSQL-specific tests skipped** because no test database URL was configured. SQLite persistence, native HTTP, provider-input exclusion with intercepted Qwen transport, legacy recovery, exports, and public-policy tests passed. PostgreSQL received the additive schema and shares the transaction implementation; it was not exercised against a live database.
- Regression suites passed: mechanics (567), missions (665), support (2,004), scenario fixtures (367), bridge rules (848), full normal-session UI (168), general UI (198), practice isolation (10), and local-only public saving (11).
- The broader existing `test_mission_ui.gd` still reports **56 unrelated artwork-registration/footer-layout assertion failures**. An isolated copy of unchanged HEAD reproduced the same 56 failures. The new forms suite and normal-session flow pass; this task does not alter map registration or the existing results-footer design.

No deployment or paid model call was made. Visual checks used local Godot windows, not a newly published/browser-hosted build.
