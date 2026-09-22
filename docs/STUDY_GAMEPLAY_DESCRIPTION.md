# Cascade Lab: Outbreak — gameplay and AI intervention reference

Prepared 20 September 2026 from the current project. This is a factual reference for revising study materials, not a completed participant consent form. Researcher-only scenario spoilers are clearly marked below.

## 1. Status and recorded design decision

**Recorded decision: use a 120-second initial team discussion in every round and every condition.** The countdown starts after the third private judgment is submitted. At zero, the team moves to the intervention stage. The outbreak does not advance during this countdown.

The discussion timer is an agreed change, **not yet implemented**. The current build ends discussion when the team clicks **Finish initial discussion**.

The current support system is a deterministic, hand-built template library, version `support-1.0.0`. It does not call an LLM, learn from participants, or use reinforcement learning. The intended future version will use **GPT-5.4 mini through the OpenAI API** for the two AI conditions. That integration is also **not yet implemented**. The model would generate bounded, short messages from an approved input snapshot; it would not become a free-form chatbot or autonomous game player.

The existing 15-second decision pause, the three conditions, private forms, input filter, and support logging are implemented. This document preserves those rules while describing the agreed discussion timer and planned model integration explicitly as future behavior. Documentation work does not resume the paused game changes or build work.

## 2. What the game is

Cascade Lab: Outbreak is a cooperative strategy game for a team of **three people**, designed to study decisions under uncertainty and the effects of different forms of decision support. Players manage a fictional district during an outbreak. Their shared objective is to keep as many of its **eight shelters functioning as possible through three rounds**, while managing **six supply units for the entire session**.

The team sees a road network, public reports, visible losses, depot stock, and information obtained through its own actions. Some underlying shelter conditions remain hidden. A shelter can look operational while already being exposed. Reports can be incomplete or ambiguous, and information obtained earlier may no longer describe the current situation.

The team must decide where to investigate, where to place protection, whether to close a road, and when to preserve supplies. Roads carry both infection and supply deliveries, so a decision that restricts spread can also restrict future assistance. Players share the outcome; there is no implemented individual score, opposing player role, or separate personal resource pool.

The current interface supports three people taking turns on **one shared computer and display**. Private judgments use a pass-the-screen procedure. The game is an abstract, fictional outbreak simulation; its rules and AI text are not medical or emergency-management guidance.

The study comparison concerns the form of support: a direct recommendation, a reasoning challenge, or a neutral pause. The current game records pre-discussion judgments and subsequent team behavior. It does not, by itself, establish changes in trust or individual reasoning without appropriate additional study measures.

## 3. The district and resources

Only **one playable scenario** is currently implemented: **Riverside district**, scenario ID `riverside_01_v2`. Its three rounds are successive stages of that scenario, not three separate randomized scenarios.

| ID | Location | Role in the network |
| --- | --- | --- |
| A | North depot | Starts with three supply units; connects to B and D. |
| B | Old market | Connects to A, C, and E. |
| C | Civic clinic | Connects to B and E. |
| D | West school | Connects to A and E. |
| E | Tram interchange | Connects to B, C, D, and F; a central junction. |
| F | East gate | Connects E to G. |
| G | Riverside hall | Connects F to H. |
| H | South depot | Starts with three supply units; connects to G. |

The nine bidirectional roads are A–B, B–C, C–E, E–D, D–A, B–E, E–F, F–G, and G–H. The western side has alternate routes. E–F is the only connection between the western network and the eastern chain F–G–H.

The six supply units do **not** replenish each round. Unused supplies carry forward. A supply unit can only help a target if a usable route exists from its depot. Roads that have been isolated and shelters that are Overrun cannot carry deliveries. Consequently, a team may have stock remaining but be unable to reach a desired target. An Overrun depot cannot dispatch its remaining stock.

## 4. Hidden conditions and public evidence

Each shelter has one underlying pressure state:

| Pressure | Meaning | What the team normally knows |
| --- | --- | --- |
| 0 | Not exposed | Not automatically revealed merely because the shelter looks operational. |
| 1 | Exposed | May remain hidden; the shelter is still functioning but exposure will progress at resolution. |
| 2 | Overrun | Publicly visible and permanently unavailable as a functioning shelter or supply relay. |

A public Overrun marker is strong evidence of a loss. The absence of that marker does not distinguish pressure 0 from pressure 1. A green supply-access indicator describes delivery access, not a guarantee of safety.

Public evidence includes reports already released, known road closures, visible Overrun shelters, depot balances, completed actions, dated verification results, and public monitoring observations. A verification is a snapshot of the moment it was obtained. Installing a monitor does not immediately reveal a shelter's baseline pressure.

The outbreak advances only when the team ends the action phase and resolves the round. It does not spread because participants spend longer reading, completing forms, discussing, or watching a supply delivery.

## 5. Available actions

| Action | Cost | Target and effect | Limitation |
| --- | --- | --- | --- |
| **Verify** | 1 supply | Deliver to a functioning shelter and reveal its exact pressure at arrival. | Does not protect or cure it. The result is dated, not a permanent live reading. |
| **Monitor** | 1 supply | Install a persistent monitor at a functioning shelter; later pressure changes produce public alerts. | No immediate baseline reading, no protection, and no cure. There must be a later change for a new alert. |
| **Shield** | 1 supply | Protect a functioning shelter against incoming infection during the upcoming resolution. | Expires after that resolution. Does not reverse exposure or stop its internal progression. |
| **Isolate** | 2 supplies | Deliver one unit to each endpoint of an open road; close it permanently after both deliveries arrive. | Stops supply traffic as well as infection. Both endpoints must still function and be reachable. |
| **Wait / save supply** | 0 | End the round without further spending. | The outbreak still resolves. Waiting is a private proposal option; final waiting uses End round. |

For isolation, one depot may fund both endpoints if it has enough stock and routes; alternatively, the depots can split the deliveries. The preview shows supply access that would be lost. A road cannot be isolated after either endpoint becomes Overrun, because the required delivery cannot be completed.

Before dispatch, the game checks action eligibility, stock, and routes. Supplies are deducted at dispatch; the effect happens after delivery. Other actions and round resolution are blocked during delivery. The game then returns to the action phase.

**There is no one-action-per-round limit.** The team can take several actions sequentially, use a new verification result to choose another action, conserve supplies, or stop when no useful legal action remains. Its constraints are stock, access, action eligibility, and the three-round horizon. An installed monitor cannot be installed again, and an active shield cannot be stacked. Verification can be purchased again.

## 6. The complete round loop

### Before play: setup

The facilitator selects **No AI**, **Direct-Recommendation AI**, or **Constructive-Dissent AI** in Session setup before the first private judgment. The current build defaults to No AI. The chosen condition stays fixed across all three rounds. Assignment is currently manual; random assignment is not implemented.

The facilitator explains the controls, hidden information, actions, shared objective, and private handoff procedure. Any practice session, consent procedure, or researcher questionnaire is separate from the implemented game and needs its own protocol. Dev Mode should remain off during ordinary participant play because it reveals hidden game information. Its use flags the session record.

### Step 1: observe the public situation

At the start of each round, a new scheduled public report appears. Players examine the map, depot stock, closures, losses, and any observations from earlier rounds. Round 1 starts a new situation; rounds 2 and 3 retain the consequences of earlier actions and resolutions.

The formal timed discussion has not begun. Instructions should ask players to record their initial judgments independently before group deliberation; the software cannot prevent people from speaking during observation or handoff.

### Step 2: three private judgments

Players complete a structured form one at a time. A handoff screen identifies whose turn it is and asks the others to look away. Each new form starts blank. Earlier answers are not displayed to the next participant or placed on a normal comparison screen.

Each form records:

1. **Most immediate danger:** a shelter or road.
2. **Proposed action:** Verify, Monitor, Shield, Isolate, or Wait.
3. **Action target:** the relevant shelter or road; Wait has no target.
4. **Confidence:** 1–5, with 1 low and 5 high.
5. **Main reason:** an optional category: visible outbreak; suspected hidden exposure; protect important route; protect supply access; gather more information; prevent cascade; or other/uncertain.

The first four selections are required; the reason category is optional in the current implementation. There is no free-text explanation box, player-name field, or original-source guess question. Proposed actions express intentions and do not spend supplies or bind the team. They need not turn out to be executable when final actions are chosen.

Across a full session there are **nine forms: three per round and three per participant**. The AI-facing and exported answer records omit player identities and are sorted so their ordering does not preserve the pass-the-screen order. This does not prevent a teammate from recognizing a view someone voluntarily expresses aloud.

### Step 3: initial discussion — agreed 120 seconds

Immediately after the third form is submitted, the planned two-minute timer starts. The team discusses the situation, shares whatever reasoning it wishes to share, compares priorities, and forms a provisional plan. A visible countdown shows the remaining time. No support message has appeared yet, and final action controls remain unavailable.

At 120 seconds, the planned flow transitions to the intervention stage. This same duration applies to all three conditions. **The timer is not yet coded:** the current build uses the manual Finish initial discussion button.

The AI does not listen to this discussion. Its response patterns come from the forms submitted before discussion, so it cannot know whether participants subsequently resolved their disagreement or changed their minds.

### Step 4: one shared intervention message

The game prepares one permitted input snapshot and selects or generates one message for the assigned condition. The current build selects locally from templates. The planned GPT version will request a constrained message from a server, validate it, and show it in the same decision panel.

The shared phase is labeled **DECISION PAUSE**. The message appears in the panel beside the map, with the same placement, card styling, font emphasis, and three-part structure in all conditions. It is visible to all three participants at once.

The existing **15-second minimum reading pause starts when the message is actually displayed**. Generation or loading time does not count. During the pause, the team can read and discuss, but cannot dispatch an action or resolve the round. The continuation button remains disabled until the countdown ends.

Once the interval ends, **Proceed to actions** becomes available. The team may continue discussing before clicking it; the current pause is a minimum, not an automatic 15-second dismissal. Clicking continues to the final action phase. The AI never executes, preselects, or commits its recommendation.

There is **one message per round**, at most three per complete session. There is no chat, follow-up question, regeneration button, or message refresh after a new observation. The message reflects the information available at its original display point.

For the planned API version, the maximum generation wait, failure handling, and any matching wait in No AI remain to be specified. The 120-second discussion and 15-second reading interval alone do not settle network-latency equivalence.

### Step 5: final team decisions and deliveries

The team chooses whether and how to use the message. It may accept it, modify its plan, reject it, or choose another legal action. Players select a shelter or road, review an action and its cost, choose an available depot assignment, and confirm delivery.

After delivery, the action takes effect and the team may take another action. New information can influence subsequent choices, but does not produce another AI message. No extra fixed time limit for this final decision phase has been agreed or implemented.

### Step 6: resolve the round

The team selects End round and confirms resolution. Already-Overrun shelters transmit pressure along open roads; exposed shelters progress; shields block incoming pressure for this resolution; new Overrun shelters become public; monitors report changes; and shields expire. The game shows the public outcome and the number of shelters lost.

State changes are simultaneous. A shelter that becomes Overrun in this resolution begins spreading only at a later resolution, not immediately through the rest of the network in the same step.

### Step 7: next round or results

After rounds 1 and 2, the team advances to the next public report and repeats the private forms, discussion, intervention, actions, and resolution. Supplies, installed monitors, closures, observations, and losses carry forward.

After round 3, the results summarize surviving/functioning shelters and resource use. A functioning shelter means one not yet Overrun: a pressure-1 shelter still counts as functioning at the endpoint. This score does not establish that every surviving shelter is unexposed or would remain safe indefinitely.

The research session can be exported as JSON. Any final questionnaire, interview, or debrief is separate; no post-AI private judgment or trust questionnaire is currently built in. Restart creates a fresh run and clears the current in-memory session; export first if its record must be retained.

### Timing and counts

For a complete three-round session, the agreed timers account for **6 minutes of initial discussion plus at least 45 seconds of decision pauses**. **6 minutes 45 seconds is not the total session duration.** Observation, nine private forms, final deliberation, deliveries, resolution, instructions, API waiting, and any study measures add time. Total duration needs to be established by pilot sessions.

## 7. What the AI receives and what it cannot access

Both AI conditions must receive the **same permitted categories and the same snapshot for an otherwise identical game situation**. The condition changes the response instruction, not access to evidence.

| Allowed input | Scope |
| --- | --- |
| Public shelter information | Overrun state, public monitor readings, dated verification history, installed monitors, and visible shields; unknown conditions remain unknown. |
| Roads | Public connections and known closures. |
| Supplies | Remaining stock at each depot and total remaining budget. |
| Team history | Completed team actions, targets, costs, round, and funding depots. |
| Reports | Reports already published in the current or previous rounds. |
| Round | Current round and the game rules needed to interpret the remaining horizon. |
| Anonymous structured responses | The current round's three danger selections, proposed actions and targets, confidence ratings, and optional reason categories. |

The model would also receive fixed game rules, its assigned condition instructions, and output restrictions. Publicly derived action eligibility can be calculated from the same roads, Overrun states, and stock. If supplied explicitly, the same derived information should be available to both modes.

Excluded information includes names; response-to-player mappings; free-written private explanations; audio, transcripts, or live conversation; actual hidden pressure 0/1; the original source; future reports or events; full internal simulation calculations; and the complete research export. The scenario identifier is recorded for audit, but the current generator does not receive it or look up the scenario's hidden definition.

The planned LLM should have no browsing, external retrieval, or game-control tools. Its instructions should require grounding in the supplied game facts. A pretrained language model still has prior learned knowledge; it is more accurate to describe these input and grounding restrictions than to promise that the model has literally no prior knowledge or can never make an unsupported statement.

Importantly, the forms are collected **before** the initial discussion. The model has no direct evidence of what was said during those two minutes, who persuaded whom, or the team's revised consensus.

## 8. The three experimental conditions

### Direct-Recommendation AI

The message proposes **one specific next action and target**, gives a short rationale, and identifies one uncertainty or risk. It is 35–60 words including labels, using this format:

> **Recommendation:** [specific action and target]
>
> **Why:** [one or two sentences grounded in allowed evidence]
>
> **Check:** [one uncertainty or risk to verify before committing]

The recommendation must be usable under the public action constraints. Waiting is an explicit recommendation where appropriate, including when no funded action can be executed. It must not present hidden information as known or imply that its choice is guaranteed to maximize the score. It must not identify individual respondents, report vote counts, or label people as a majority or minority.

This mode is intended to supply an actionable suggestion. Following that suggestion remains the team's decision. It does not prescribe all actions for the round or a complete three-round solution.

### Constructive-Dissent AI

The message identifies a disagreement, fragile shared assumption, missing evidence, or overlooked tradeoff. It asks **one focused discussion question** and names a useful comparison or information need. It is 35–60 words including labels:

> **Decision check:** [conflict, assumption, or uncertainty]
>
> **Discuss:** [one question to answer before committing]
>
> **Evidence to seek:** [useful verification, comparison, or tradeoff]

It must not select the final action, covertly endorse one participant's proposal, or say “choose X.” It can mention actions when framing a comparison, but cannot turn that comparison into an instruction to execute one. When the structured answers agree, it challenges a shared assumption rather than inventing disagreement. Confidence is a cue about uncertainty, not proof that a view is correct.

This mode is intended to make the team articulate and test its reasoning while preserving its own decision. Like direct support, it does not identify whose response prompted the message.

### No AI

The team receives neutral scheduling text in the same location and with the same visual weight and minimum 15-second gate. The current 45-word message is:

> **Pause:** This is the scheduled interval between the team's initial discussion and final action selection.
>
> **Time:** The same interval occurs in every round. The game remains paused while the countdown runs.
>
> **Continue:** When the interval ends, the action controls become available after the team continues.

It contains no recommendation, diagnosis of the team's reasoning, or evidence prompt. The planned No AI condition should continue to be local and should not send forms to an LLM merely to produce this neutral message. The private forms and normal research records still exist in this condition.

### Reproducibility and error handling

The existing library has 12 fixed templates: six direct, five dissent, and one neutral. It chooses a branch and fills permitted map targets using deterministic rules. Its full wording is in `docs/AI_MESSAGE_LIBRARY.md`.

For live GPT generation, the **formats and behavioral constraints can be locked, but every possible output sentence cannot be supplied in advance**. The model version, instruction version, schema, and generation settings should be fixed and recorded. Even fixed settings do not guarantee identical wording on every request; the actual displayed text is the reliable replay record.

Before display, the planned integration needs checks for the required fields, 35–60-word limit, permitted targets, legal recommendations, privacy restrictions, and the distinction between recommending and questioning. Such checks reduce errors but should not be described as guaranteeing perfect factual or behavioral compliance.

Timeouts, rejected outputs, retries, and any fallback to the existing library need a defined study policy and an explicit log entry. A hand-built fallback must not silently be counted as a successful GPT response. These are implementation requirements still to be completed, not current capabilities.

## 9. The situations participants encounter

The scenario's reports are scheduled and fixed. Their fictional timestamps are narrative labels, not the two-minute discussion timer or real waiting periods. The later board state varies with the team's earlier actions; the reports themselves do not adapt to those actions.

### Round 1 — competing reports and uncertain danger

At fictional time 09:30, the report reads:

> Distress calls mention Old Market, Tram Interchange and East Gate. All used the same radio relay; caller locations are unconfirmed.

The team starts with all eight shelters functioning and all six supply units available. Without purchased observations, apparent normal operation does not establish whether a shelter is exposed.

The report names B, E, and F, but does not establish that all three are infected, that three independent sources confirmed them, or that a caller was inside a named shelter. Players may focus on a named location, E's four connecting roads, the E–F connection, or preserving depot access. Their private judgments may therefore identify different dangers or propose different action types from the same public evidence.

The practical tension is whether to buy information, prepare future monitoring, spend resources on protection or closure before visible spread, or reserve stock. Early action may preserve options that disappear after a shelter is lost, but premature spending can consume resources before the danger is well understood.

### Round 2 — revised evidence and visible consequences

At fictional time 09:45, the next report reads:

> The Old Market call was a replayed recording. Archived camera footage shows movement near East Gate, but no entry into the shelter.

This weakens a simple reading of the first report without proving B or F safe. It separates a report's reliability from a shelter's actual current condition. Players also see the consequences of round 1 and any observations they obtained.

The team must reassess earlier assumptions, distinguish sightings on a road from exposure inside a shelter, and consider how lost relay shelters or road closures affect deliveries. Existing exposure cannot be cured by shielding, and an isolation option can disappear when an endpoint becomes Overrun.

Different teams can face different supply balances and routes at this point. Information gathering in round 1 may now help, but its cost leaves fewer units for intervention. Early closures may protect one connection while removing a route needed for assistance.

### Round 3 — limited horizon and remaining stock

At fictional time 10:00, the final report reads:

> A recovered patrol photo shows a group on West School’s service road. Its direction and destination are unclear.

The image report does not establish that D is exposed, safe, or the group's destination. The team must combine this uncertainty with its own observation history and the consequences of the first two resolutions.

There is only one resolution left. Information has value only if it can still affect a remaining decision. A monitor installed now provides no immediate baseline; an alert during the final resolution arrives after the final action phase. Verification can still support another action in the same round if stock and access permit. Saving stock now has no later round in which to spend it.

The team may be choosing among a few reachable targets, interpreting an old pressure reading, or discovering that an earlier closure or loss has made remaining stock unusable. The AI must respond to that actual public situation, not assume that all teams have reached the same board state.

## 10. Examples of the messages participants might see

The following are **illustrative authored examples**, not recorded outputs from GPT-5.4 mini and not a claim that these will appear in a particular round. Each AI example is 35–60 words. Its stated context must hold before it would be appropriate. They demonstrate the planned response behavior; the complete current fixed library is documented separately.

### A. Ambiguous opening report

Context: round 1; E is functioning and reachable; its four connections are public. The dissent example additionally assumes the forms actually name different danger locations.

**Direct example — 49 words**

> **Recommendation:** Verify Shelter E next.
>
> **Why:** E connects four roads, so a current observation could inform several later decisions. The public report mentions multiple locations without confirming where the callers were.
>
> **Check:** Verification costs one supply and gives a snapshot; it neither prevents infection nor establishes the original source.

**Dissent example — 50 words**

> **Decision check:** The structured responses point to different danger locations, while the report does not confirm caller locations.
>
> **Discuss:** What evidence would distinguish a risky junction from the place where a distress call originated?
>
> **Evidence to seek:** Compare road connections, report uncertainty, and the value of a current shelter observation.

### B. A visibly Overrun neighbor

Context: E is visibly Overrun, E–B remains open, B is functioning and reachable, and no public observation establishes that B is already exposed. This can occur at the start of round 2. The recommendation is conditional on uncertainty, not a claim that the model knows B's hidden state.

**Direct example — 48 words**

> **Recommendation:** Shield Shelter B next.
>
> **Why:** B is connected by an open road to visibly Overrun Shelter E. If B is not already exposed, shielding can block incoming infection during this resolution.
>
> **Check:** Review any dated observations and confirm a funded delivery route; shielding cannot reverse existing exposure.

**Dissent example — 50 words**

> **Decision check:** A visibly Overrun neighbor establishes a route of danger, but it does not establish this shelter's current internal condition.
>
> **Discuss:** Does the proposed protection depend on the shelter still being unexposed?
>
> **Evidence to seek:** Compare the timing of existing observations with the different effects of shielding and verification.

### C. Closing the connection between the two sides

Context: before E becomes Overrun, with E–F open, both endpoints reachable, sufficient supplies, and structured proposals including isolation. This example is not legal after E is Overrun.

**Direct example — 49 words**

> **Recommendation:** Isolate Road E-F next.
>
> **Why:** The structured proposals include closing this connection between the two sides of the district. Both endpoints currently have funded delivery routes.
>
> **Check:** Closure costs two supplies and blocks supply movement as well as infection; inspect which shelters would lose access from each depot.

**Dissent example — 50 words**

> **Decision check:** Closing the connection could reduce one route of spread while also removing a route for future supplies.
>
> **Discuss:** Which consequence would matter more under the team's current assumptions?
>
> **Evidence to seek:** Compare supply access on both sides before and after closure, including the remaining stock at each depot.

### D. Agreement before the final resolution

Context: the structured proposals agree on verifying C; C remains reachable; enough stock and meaningful follow-up choices remain for its result to affect another decision. Agreement itself is not evidence that the assumption is true. If no useful follow-up is possible, this particular direct example would be inappropriate.

**Direct example — 48 words**

> **Recommendation:** Verify Shelter C next.
>
> **Why:** The structured proposals agree on checking C, but agreement does not establish its current pressure. A current observation could test the shared assumption before further supply is committed.
>
> **Check:** Confirm that the result could still change a decision before the final resolution.

**Dissent example — 51 words**

> **Decision check:** The structured proposals align, but a shared assumption can still overlook hidden exposure or a fragile supply route.
>
> **Discuss:** What would have to be different for the current plan to lose its advantage?
>
> **Evidence to seek:** A comparison of dated observations, route availability, and the cost of being wrong.

If no funded action remains, direct support should explicitly recommend waiting without fabricating an executable action. Dissent can examine how access or stock assumptions led to the constrained situation without pretending an alternative is available. Neither condition should invent private facts to make its message more dramatic.

## 11. Researcher-only appendix: hidden scenario structure and example outcomes

**Spoilers: this section is for the researcher/developer, not a pre-play participant disclaimer or an AI prompt.** Disclosing the source or outcome paths before play would change the uncertainty participants are supposed to experience.

The fixed initial source is **E, Tram interchange**, which starts at pressure 1. Every other shelter starts at pressure 0. The hidden timeline places the initial exposure at fictional time 09:22. No visible Overrun shelter exists at the start.

The resolution rules are deterministic:

1. Each shelter already Overrun at the beginning of resolution sends one pressure unit to each neighboring shelter along an open road.
2. An exposed shelter that starts resolution at pressure 1 gains one unit from internal progression.
3. A shield blocks all incoming pressure for that resolution, but does not block internal progression.
4. Pressure is capped at 2. Several incoming sources can contribute in the same resolution.
5. All calculated changes are applied together. Newly Overrun shelters transmit in a subsequent round, not immediately in the same resolution.

Because E begins exposed and no action cures exposure, it becomes Overrun at the end of round 1 under the current rules. Shielding it cannot prevent this. Verifying it reveals its current pressure but does not establish by itself that it was the first source. Closing its roads can restrict later transmission but cannot restore E.

### Reference path 1: take no actions

| Resolution | Hidden/public outcome | Functioning shelters |
| --- | --- | --- |
| End of round 1 | E progresses from exposed to publicly Overrun. | 7/8 |
| End of round 2 | E transmits to B, C, D, and F, making them exposed. They have not yet become Overrun. | 7/8 |
| End of round 3 | B, C, D, and F become Overrun. A, G, and H remain functioning. | 3/8 |

The final losses do not immediately infect A, G, or H within that same resolution because newly Overrun shelters do not transmit until the next resolution, and the session ends after round 3.

### Reference path 2: isolate E–F in round 1, then take no other actions

If the team successfully closes E–F while both endpoints still function, that connection cannot transmit infection or carry supplies afterward. E is still lost at the end of round 1. Its western neighbors B, C, and D become exposed after round 2 and Overrun after round 3. A, F, G, and H remain functioning: **4/8**. This illustrates that one strategically important closure does not protect every neighboring shelter.

### Reference path 3: time protection for the first outward spread

One feasible reference sequence is to Verify E from H in round 1, then Shield B, C, and D from A and Shield F from H in round 2. These five actions cost five supplies in total. E is already Overrun, but all four neighbor shields block its incoming transmission in round 2. If no further action is taken, those neighbors become exposed in round 3 and still count as functioning at the endpoint: **7/8**, with one supply remaining.

This is a rules-based example, not an AI guarantee or a prescribed participant solution. It illustrates the endpoint score's distinction between functioning and unexposed. Under the current fixed initial exposure and lack of a cure, **8/8 is unattainable**. That fact should inform researcher interpretation of scores and any debrief, rather than be inadvertently exposed through model instructions or participant examples before play.

There is no randomized new source or new hidden outbreak scenario on each restart. Repeated play or prior knowledge can therefore change task difficulty substantially. If the study needs unfamiliar scenarios across sessions, additional scenarios and an assignment plan would need to be developed.

## 12. Data collection, privacy, and logging

### Information entered by participants

The game collects the nine structured judgments described above. The game form does not collect names, email addresses, demographic information, free-written explanations, voice, or discussion transcripts. These statements describe the game itself, not a researcher's separate consent forms, questionnaires, video calls, or recording equipment.

The private interface is procedural privacy on a shared device: it asks others to look away and does not display earlier answers. It cannot prevent shoulder-surfing or disclosure during conversation. Responses omit participant identifiers, but a three-person group's distinctive statements may still be recognizable to someone with outside knowledge. Avoid promising absolute anonymity.

### The support display log

Each displayed message creates one `SUPPORT_SHOWN` event containing:

- assigned condition;
- scenario ID;
- round;
- permitted input **category labels**, not a raw input snapshot;
- the exact displayed text;
- template ID and template version;
- UTC time shown and elapsed session time.

The current support event does not copy individual answers, player identities, or hidden simulation state. The future GPT integration should additionally identify the model version, instruction/configuration version, and generation or fallback status, with sufficient timing information to distinguish loading time from reading time. These additions are not yet implemented.

### The separate, broader research export

**The support display event is not the whole session record.** The current JSON export includes:

- anonymous structured private answers, grouped by round and sorted without player identifiers;
- public reports and observations;
- completed actions and targets;
- supply expenditures, depot assignments, delivery paths, and delivery events;
- road closures, installed monitors, shields, and their effects;
- phase transitions, timestamps, round outcomes, and final performance;
- Dev Mode usage;
- internal pressure changes and resolution calculations;
- the final internal state and scenario ground truth, including the original source and starting pressures.

Hidden game data in this research export must remain outside the AI input path. Researchers can use it to understand what happened, but it is not evidence available to the team's support message.

The current game keeps session data in memory and provides a manual local/downloadable JSON export. It does not currently have an automatic research upload backend or a model API connection. An exported file persists wherever the researcher saves it; its retention and access policy is not defined by the game.

Therefore, the disclaimer must not say **“only the AI message and timestamp are stored”** or **“private choices are never recorded.”** Those statements would contradict the current research export. It can accurately distinguish private answers hidden from other players from anonymous answers retained for research.

This export is also broader than an interpretation of the earlier minimal-logging requirement that applies to the entire session, rather than just the support event. If the intended restriction is session-wide, the export must be reduced before data collection; changing the disclaimer alone would not implement that restriction.

### Planned external model processing

With the planned GPT integration, the approved public context and anonymous structured answers would pass through the game's server to OpenAI for message generation. This external processing must be described even if the local support event stores only category labels. The intended design needs no participant ChatGPT account; API credentials belong on the server, not in the downloadable game. Backend request logging, storage, and access controls still need to be established.

OpenAI states that API data is not used for model training by default unless the customer opts in. Its default abuse-monitoring logs may contain prompts and responses and may be retained for up to 30 days, with longer retention possible for legal or protective reasons. Additional storage depends on the endpoint and settings; disabling stored responses alone is not a guarantee of zero retention. Special retention controls require eligibility and approval. The study must describe its actual account and service configuration. [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data)

Hosting services and any future server may also have technical logs; this document does not establish their actual contents or retention. Do not infer that the whole deployed study collects no technical identifiers simply because the game form has no name field.

## 13. Points to settle before finalizing the participant disclaimer

The gameplay and approved intervention design can be described from this document. The following study-specific details are not established by the current project:

1. **Assignment:** how teams will be assigned, whether assignment is random, and what participants are told about the comparison.
2. **Duration:** the measured total session length, instructions, practice, breaks, questionnaires, and debrief.
3. **Data handling:** who receives exports, where they are stored, who can access them, retention/deletion periods, and how any consent roster relates to game records.
4. **External processing:** the actual API configuration, backend logs, hosting arrangements, and the policy for model request data.
5. **Additional recording:** whether researchers record audio, video, screens, observations, or interviews outside the game. The game does not itself record a conversation.
6. **Participation terms:** study contacts, eligibility, compensation if any, voluntary participation and withdrawal arrangements, and whether a withdrawn person's data can still be located after identifiers are removed.
7. **Model failures:** the permitted loading interval, retries, outage behavior, fallback rules, and how equivalent timing is maintained across conditions.
8. **Study measures:** whether post-intervention judgments, trust ratings, or individual decision-change measures will be added. They are not present in the current game.
9. **Participant experience:** explain that the task includes timed group discussion, incomplete or misleading fictional reports, resource limits, disagreement, and possibly unsuccessful containment. AI advice may be unhelpful or wrong, and the team retains control.

Do not describe approved-but-unimplemented features as already available in a participant-facing document for the current build. Do not include the researcher-only source and outcome paths in a pre-play disclaimer unless revealing them is an intentional part of the study.

## 14. Project sources checked

- `scenarios/scenario_01.json`: map, initial conditions, rounds, public reports, ground truth.
- `scripts/game_manager.gd`: phases, private submissions, support timing, resolution, export.
- `scripts/action_manager.gd`, `scripts/supply_manager.gd`, and `scripts/network_manager.gd`: action eligibility, stock, delivery access, closure effects.
- `scripts/models/player_belief.gd`: private form categories.
- `scripts/support_context.gd`: allowed input projection and anonymous sorting.
- `scripts/support_library.gd`: versioned templates and condition rules.
- `scripts/ui/main.gd`: shared intervention card, form, handoff, setup, controls, and export UI.
- `docs/AI_SUPPORT.md` and `docs/AI_MESSAGE_LIBRARY.md`: current support specification and full fixed wording.

This report adds documentation only. It does not implement the 120-second timer, connect GPT-5.4 mini, alter game behavior, or produce a new build.
