class_name SupportContext
extends RefCounted

# Sole adapter between the simulation and support. Never serialize GameState wholesale.
const CATEGORIES := ["public_shelter_status_and_dated_observations", "public_roads",
	"depot_supplies", "previous_team_actions", "published_reports", "current_round",
	"remaining_budget", "anonymous_structured_responses"]

static func build(state: GameState, published_reports: Array, responses: Array) -> Dictionary:
	var result := {"round":state.round, "remaining_budget":state.total_supply(),
		"shelters":{}, "roads":{}, "depots":{}, "previous_actions":[], "public_reports":[], "responses":[]}
	for id in state.shelters:
		var shelter: ShelterState = state.shelters[id]
		var history: Array = []
		for record in shelter.verified_history:
			if int(record.round) <= state.round:
				history.append({"round":int(record.round), "pressure":int(record.pressure)})
		result.shelters[id] = {"overrun":shelter.is_overrun,
			"known_pressure":2 if shelter.is_overrun else shelter.monitor_known_pressure,
			"verified_history":history, "monitored":shelter.is_monitored, "shielded":shelter.shielded_this_round}
	for id in state.edges:
		var edge: EdgeState = state.edges[id]
		result.roads[id] = {"endpoints":[edge.from,edge.to], "closed":edge.isolated}
	for id in state.depots: result.depots[id] = state.depots[id].supply_remaining
	for action: GameAction in state.actions:
		if action.round > state.round or not action.completed: continue
		result.previous_actions.append({"type":action.type, "target":action.target,
			"round":action.round, "cost":action.cost, "depots":action.endpoint_depots.duplicate()})
	for report in published_reports:
		if int(report.round) <= state.round:
			result.public_reports.append({"round":int(report.round), "time":str(report.time), "text":str(report.text)})
	# Whitelist fields, enums and map IDs; never include respondent IDs or free text.
	for response in responses:
		var danger := str(response.get("danger_location",""))
		var action := str(response.get("preferred_action",""))
		var target := str(response.get("action_target",""))
		var reason := str(response.get("reason",""))
		if not state.shelters.has(danger) and not state.edges.has(danger): continue
		if not PlayerBelief.ACTIONS.has(action): continue
		if action == "WAIT":
			if target != "NONE": continue
		elif action == "ISOLATE":
			if not state.edges.has(target): continue
		elif not state.shelters.has(target): continue
		result.responses.append({"danger_location":danger, "preferred_action":action,
			"action_target":target, "confidence":clampi(int(response.get("confidence",1)),1,5),
			"reason":reason if PlayerBelief.REASONS.has(reason) else ""})
	# Stable order carries no relationship to handoff order or participant identity.
	result.responses.sort_custom(func(a: Dictionary,b: Dictionary): return JSON.stringify(a) < JSON.stringify(b))
	return result
