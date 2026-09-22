# Cascade Lab: Outbreak — Fixed Message Library

Version: `support-1.0.0`

This is the complete currently implemented template library. Wording is fixed and generated locally without a language model. `%s` is replaced only by a shelter ID or road ID. One message is selected after initial discussion in each round, before final action selection. All conditions use the same 15-second minimum pause.

Source of truth: `scripts/support_library.gd`. These templates are versioned in code; this document is a review copy, not a separate generator.

## Direct-Recommendation AI

### direct.verify

49 words, including section labels.

**Recommendation:** Verify Shelter %s next.

**Why:** A precise observation can test concerns about this location before more supplies are committed. Public reports and the map alone do not establish its current pressure.

**Check:** Confirm which stocked depot can reach it, and remember that the result is only a snapshot.

### direct.shield

45 words, including section labels.

**Recommendation:** Shield Shelter %s next.

**Why:** An open road connects this shelter to a visibly Overrun neighbor. Protection could block incoming infection while preserving the shelter as a supply route.

**Check:** Existing exposure is not cured by shielding; distinguish current observations from older verification results.

### direct.monitor

47 words, including section labels.

**Recommendation:** Monitor Shelter %s next.

**Why:** Structured proposals include monitoring this reachable location. Continuing observations could test assumptions about changing danger while the team manages its remaining supplies.

**Check:** Installation reveals no baseline and prevents no infection; consider whether later information will arrive in time to matter.

### direct.isolate

47 words, including section labels.

**Recommendation:** Isolate Road %s next.

**Why:** Structured proposals include closing this currently usable road. Both endpoints have funded delivery routes, and closure would block infection along this connection.

**Check:** Inspect the supply access lost on each side before committing both units; alternative roads may still carry infection.

### direct.wait_agreement

47 words, including section labels.

**Recommendation:** Wait; save supply across the district this round.

**Why:** The structured proposals agree on waiting. Retaining resources leaves them available later, although the public map and reports cannot establish every shelter's current condition.

**Check:** Consider whether delaying protection could make an important endpoint unreachable after resolution.

### direct.wait_unavailable

48 words, including section labels.

**Recommendation:** Wait; take no supply action across the district this round.

**Why:** No funded action has a usable delivery route under the current public road, shelter, and depot conditions. An action cannot be completed without reachable supplies.

**Check:** Review remaining depot stock and closures before ending the round.

## Constructive-Dissent AI

### dissent.different

48 words, including section labels.

**Decision check:** The anonymous responses suggest different priorities for the next decision; the public evidence may support more than one interpretation.

**Discuss:** Which observation would change how the team compares these priorities?

**Evidence to seek:** A comparison of existing observations, supply access, and the cost of delaying protection.

### dissent.assumptions

48 words, including section labels.

**Decision check:** Similar action proposals rest on different reasoning categories, so agreement about a next step may conceal different assumptions.

**Discuss:** Which assumption must hold for the proposed step to be useful?

**Evidence to seek:** The link between dated shelter observations, current road access, and the expected benefit.

### dissent.confidence

49 words, including section labels.

**Decision check:** The structured responses show uncertainty in confidence even where proposals align; confidence alone does not establish the condition of a shelter.

**Discuss:** What evidence would make the shared assumption more credible?

**Evidence to seek:** The age and precision of existing observations compared with the remaining supply options.

### dissent.agreement

51 words, including section labels.

**Decision check:** The structured proposals align, but a shared assumption can still overlook hidden exposure or a fragile supply route.

**Discuss:** What would have to be different for the current plan to lose its advantage?

**Evidence to seek:** A comparison of dated observations, route availability, and the cost of being wrong.

### dissent.unavailable

49 words, including section labels.

**Decision check:** The public map and remaining stock leave no funded action with a usable delivery route, limiting the team's immediate options.

**Discuss:** Which assumption about access or available resources shaped the current plan?

**Evidence to seek:** A comparison of depot balances, road closures, and visibly lost relay shelters.

## No AI

### none.pause

45 words, including section labels.

**Pause:** This is the scheduled interval between the team's initial discussion and final action selection.

**Time:** The same interval occurs in every round. The game remains paused while the countdown runs.

**Continue:** When the interval ends, the action controls become available after the team continues.

## Selection rules

### Direct recommendation

1. If no funded action has a usable route, use `direct.wait_unavailable`.
2. Otherwise, if all three structured proposals select WAIT, use `direct.wait_agreement`.
3. Otherwise, rank eligible action/target pairs using the public input projection:
   - Add 2 per matching suspected-danger target.
   - Add 3 per matching proposed action and target.
   - Verify: add 10 and 1 per open incident road.
   - Shield: require an openly connected, visibly Overrun neighbor. Exclude a target with public known pressure 1 or a latest dated Verify result of 1. Add 25 and 3 per visible Overrun neighbor.
   - Monitor / Isolate: require at least one matching proposal; add 12.
4. Pick the highest score. Ties retain the first candidate: sorted shelter IDs with VERIFY, MONITOR, SHIELD order, followed by sorted road IDs for ISOLATE.

Eligibility uses public closures, public Overrun state, depot stock and reachability, existing monitors/shields, and the two-endpoint funding requirement. Hidden exposure never enters selection.

### Constructive dissent (first matching branch)

1. No executable funded action → `dissent.unavailable`.
2. Different danger/action/target combinations → `dissent.different`.
3. Multiple nonblank reasoning categories → `dissent.assumptions`.
4. Otherwise, lowest confidence at most 2, or confidence range at least 2 → `dissent.confidence`.
5. Otherwise → `dissent.agreement`.

### No AI

Always `none.pause`.

## Reproducibility

The same permitted input projection and library version produce the same text. Each round retains its generated message. The session log records the shown text and template/version ID; it does not retain the raw support input snapshot. This library has 12 templates (6 direct, 5 dissent, 1 neutral). Changes to wording or selection rules require a new version.
