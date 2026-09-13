class_name PresentationText
extends RefCounted

const RULES := "[b]MISSION[/b]\nAfter three spread phases, keep as many of eight shelters alive as possible. Exposed shelters still count as surviving.\n\n[b]PRESSURE[/b]\n0 Safe · 1 Exposed · 2 Overrun. Only Overrun is public. Overrun is permanent. At round end, shelters already Overrun each send +1 along every active outgoing arrow. Incoming pressure stacks; newly Overrun shelters transmit next round.\n\n[b]SUPPLY[/b]\nSix units for the entire mission, three at each depot. Supply moves BOTH ways on roads through non-Overrun shelters. Closed roads and Overrun shelters block supply. No action heals or removes pressure. Choose a paying depot; costs cannot be split.\n\n[b]FOUR ACTIONS[/b]\nVERIFY · 1 — reveal current pressure once. The dated record never updates.\nMONITOR · 1 — install permanently; report every later pressure change, without preventing it. Installation does not reveal a baseline.\nSHIELD · 1 — block all incoming pressure for one spread; then expire. Supply routes and outgoing pressure are unaffected.\nISOLATE · 2 — permanently close a road. A crew must reach either endpoint. Review access losses before confirming.\n\n[b]YOUR ROUND[/b]\nDiscuss together, queue any number of actions, review and confirm. Information actions apply first. Shields and road closures follow in queue order. You may confirm more actions after reading results. When ready, resolve spread. There is no per-round supply allowance.\n\n[b]SHARED EVIDENCE / PRIVATE JUDGMENTS[/b]\nEveryone gets the same reports. Pass the screen privately for each judgment, then discuss the anonymous comparison. New evidence after Round 1 prompts a second private judgment. No AI, timer, or automatic team decisions."

static func evidence(scenario: ScenarioData, include_diagnostic: bool = false) -> String:
	var output := "[color=#baf269]PUBLIC REPORTS · SHARED BY EVERYONE[/color]\n\n"
	for report in scenario.public_evidence:
		output += "[color=#63d8ca]%s[/color]  [b]%s[/b]\n%s\n\n" % [report.time, report.title, report.text]
	if include_diagnostic:
		output += "[color=#ffce78]RECOVERED AFTER ROUND 1[/color]\n[b]%s[/b]\n%s\n\n" % [scenario.diagnostic_evidence.title, scenario.diagnostic_evidence.text]
	return output

static func beliefs(session: GameManager, changes: bool = false) -> String:
	var output := ""
	for position in 3:
		var index: int = GameManager.ANONYMOUS_ORDER[position]
		if index >= session.initial_beliefs.size(): continue
		var belief: PlayerBelief = session.initial_beliefs[index]
		output += "[color=#baf269][b]Participant %s[/b][/color]\n" % ["A","B","C"][position]
		if changes and index < session.updated_beliefs.size():
			var updated: PlayerBelief = session.updated_beliefs[index]
			output += "Suspected source: [b]%s → %s[/b]\nNext at risk: %s → %s\nConfidence: %d → %d / 5\nInitial preference: %s\n\n" % [belief.suspected_source,updated.suspected_source,belief.predicted_next,updated.predicted_next,belief.confidence,updated.confidence,belief.preferred_action]
		else:
			output += "Suspected source: [b]%s[/b]\nNext at risk: %s\nPreferred action: %s\nConfidence: %d / 5\n\n" % [belief.suspected_source,belief.predicted_next,belief.preferred_action,belief.confidence]
	if changes: output += "[b]Source beliefs changed: %d / 3[/b]\n" % session.belief_change_count()
	return output

static func action_history(state: GameState) -> String:
	var output := ""
	for round_number in range(1, state.round+1):
		output += "[b]ROUND %d[/b]\n" % round_number
		var found := false
		for action in state.actions:
			if action.round != round_number: continue
			found = true
			output += "%s %s · %d supply from Depot %s\n" % [action.type,action.target,action.cost,action.depot_used]
		if not found: output += "No confirmed actions.\n"
		output += "\n"
	return output

static func investigation(state: GameState) -> String:
	if state.investigation_log.is_empty(): return "No investigation results yet.\n\nVerify records are dated snapshots. Monitor alerts record later changes."
	return "\n\n".join(state.investigation_log)

static func debug(session: GameManager) -> String:
	var output := "[color=#ffce78][b]DEV MODE · HIDDEN STATE EXPOSED[/b][/color]\nSource: %s\nSession flagged as a development run.\n\n" % session.scenario.original_source
	for id in session.state.shelters:
		var shelter: ShelterState = session.state.shelters[id]
		output += "%s: pressure %d · shield %s · monitor %s\n" % [id,shelter.zombie_pressure,shelter.shielded_this_round,shelter.is_monitored]
	var network := NetworkManager.new(session.state)
	for depot in session.state.depots:
		output += "\nDepot %s routes: %s\n" % [depot, ", ".join(network.get_reachable_shelters(depot))]
	output += "\n[b]ROADS[/b]\n"
	for edge: EdgeState in session.state.edges.values(): output += "%s → %s: %s\n" % [edge.from,edge.to,"CLOSED" if edge.isolated else "active"]
	output += "\n[b]LAST SPREAD CALCULATIONS[/b]\n"
	for calculation in session.state.spread_calculations:
		output += "%s: %d + %d incoming%s → %d\n" % [calculation.target,calculation.old,calculation.incoming," (shield blocks all)" if calculation.shielded else "",calculation.new]
	return output
