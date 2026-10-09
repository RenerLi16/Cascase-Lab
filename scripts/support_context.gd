class_name SupportContext
extends RefCounted

# Sole adapter between the simulation and support. Never serialize GameState wholesale.
# cascade-context-2: network, supplies, actions, dated Verify/Monitor observations and
# anonymous structured responses only. Narrative dispatches (v1 "public_reports") are retired;
# the backend rejects any request that still carries them.
# cascade-context-3: each road carries its public bridge flag; only bridges can be isolated.
const VERSION := "cascade-context-3"
const CATEGORIES := ["public_shelter_status_and_dated_observations", "public_roads",
	"depot_supplies", "previous_team_actions", "current_round",
	"remaining_budget", "anonymous_structured_responses", "public_rules_costs_and_display_names"]

static func build(state: GameState, responses: Array, exposure_progresses: bool = true) -> Dictionary:
	var result := {"round":state.round, "remaining_budget":state.total_supply(),
		"shelters":{}, "roads":{}, "depots":{}, "previous_actions":[], "responses":[]}
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
		result.roads[id] = {"endpoints":[edge.from,edge.to], "closed":edge.isolated, "bridge":edge.bridge}
	for id in state.depots: result.depots[id] = state.depots[id].supply_remaining
	for action: GameAction in state.actions:
		if action.round > state.round or not action.completed: continue
		result.previous_actions.append({"type":action.type, "target":action.target,
			"round":action.round, "cost":action.cost, "depots":action.endpoint_depots.duplicate()})
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
			if not state.edges.has(target) or not state.edges[target].bridge: continue
		elif not state.shelters.has(target): continue
		result.responses.append({"danger_location":danger, "preferred_action":action,
			"action_target":target, "confidence":clampi(int(response.get("confidence",1)),1,5),
			"reason":reason if PlayerBelief.REASONS.has(reason) else ""})
	# Stable order carries no relationship to handoff order or participant identity.
	result.responses.sort_custom(func(a: Dictionary,b: Dictionary): return JSON.stringify(a) < JSON.stringify(b))
	result.public_rules = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/public_support_rules.json"))
	result.public_rules.exposure_progresses = exposure_progresses
	result.display_names = {}
	for id in state.shelters: result.display_names[id] = state.shelters[id].display_name
	for id in state.edges: result.display_names[id] = ("Bridge " if state.edges[id].bridge else "Road ") + id
	result.legal_actions = SupportLibrary.legal_actions(result)
	result.legal_actions.append({"action":"WAIT","target":"NONE"})
	return result
