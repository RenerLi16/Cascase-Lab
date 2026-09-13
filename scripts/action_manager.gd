class_name ActionManager
extends RefCounted

var state: GameState
var logger: EventLogger
var supply: SupplyManager

func _init(current_state: GameState, event_logger: EventLogger) -> void:
	state = current_state
	logger = event_logger
	supply = SupplyManager.new(state)

func unavailable_reason(kind: String, target: String, depot: String = "") -> String:
	if not GameAction.TYPES.has(kind): return "Unknown action."
	var road := kind == "ISOLATE"
	var cost := 2 if road else 1
	if road:
		if not state.edges.has(target): return "Select a road."
		if state.edges[target].isolated: return "This road is already permanently isolated."
	else:
		if not state.shelters.has(target): return "Select a shelter."
		var shelter: ShelterState = state.shelters[target]
		if shelter.is_overrun: return "Overrun shelters cannot receive or relay supplies."
		if kind == "MONITOR" and shelter.is_monitored: return "A permanent monitor is already installed."
		if kind == "SHIELD" and shelter.shielded_this_round: return "Already shielded for this spread phase."
	var eligible := supply.eligible_depots(target, cost, road)
	if eligible.is_empty():
		return "No depot with %d supply has an active route to %s." % [cost, "either road endpoint" if road else "Shelter " + target]
	if depot != "" and not eligible.has(depot):
		return "Depot %s cannot fund or reach this action." % depot
	return ""

func can_verify(target: String) -> bool:
	return unavailable_reason("VERIFY", target).is_empty()

func can_isolate(edge_id: String) -> bool:
	return unavailable_reason("ISOLATE", edge_id).is_empty()

func preview_isolation(edge_id: String) -> Dictionary:
	return supply.network.preview_isolation(edge_id)

func verify(target: String, depot: String) -> Dictionary:
	return execute(GameAction.new("VERIFY", target, depot, state.round))

func monitor(target: String, depot: String) -> Dictionary:
	return execute(GameAction.new("MONITOR", target, depot, state.round))

func shield(target: String, depot: String) -> Dictionary:
	return execute(GameAction.new("SHIELD", target, depot, state.round))

func isolate(edge_id: String, depot: String) -> Dictionary:
	return execute(GameAction.new("ISOLATE", edge_id, depot, state.round))

func execute(request: GameAction) -> Dictionary:
	var reason := unavailable_reason(request.type, request.target, request.depot_used)
	if not reason.is_empty(): return {"ok":false,"error":reason}
	if request.round != state.round: return {"ok":false,"error":"This action belongs to another round."}
	if request.depot_used.is_empty(): return {"ok":false,"error":"Choose the paying depot."}
	# Reconstruct instead of trusting client-supplied cost.
	var action := GameAction.new(request.type, request.target, request.depot_used, state.round)
	var depot: SupplyDepot = state.depots[action.depot_used]
	var old_supply := depot.supply_remaining
	depot.supply_remaining -= action.cost
	logger.record(state.round, "SUPPLY_SPENT", depot.node, old_supply, depot.supply_remaining, action.to_dictionary())
	state.actions.append(action)
	var message := ""
	if action.type == "ISOLATE":
		var losses := preview_isolation(action.target)
		state.edges[action.target].isolated = true
		message = "Road %s permanently isolated. Zombies and supplies cannot cross." % action.target
		logger.record(state.round, "EDGE_ISOLATED", action.target, false, true, {"disconnected":losses})
	else:
		var shelter: ShelterState = state.shelters[action.target]
		match action.type:
			"VERIFY":
				var result := {"round":state.round,"pressure":shelter.zombie_pressure}
				shelter.verified_history.append(result)
				message = "Round %d: %s was verified at Pressure %d." % [state.round, shelter.id, shelter.zombie_pressure]
				state.investigation_log.append(message)
				logger.record(state.round, "VERIFY_RESULT", shelter.id, null, shelter.zombie_pressure)
			"MONITOR":
				shelter.is_monitored = true
				message = "Round %d: Monitor installed at %s. Future changes will be reported." % [state.round, shelter.id]
				state.investigation_log.append(message)
				logger.record(state.round, "MONITOR_INSTALLED", shelter.id, false, true)
			"SHIELD":
				shelter.shielded_this_round = true
				message = "Shelter %s is shielded for the next spread only." % shelter.id
				logger.record(state.round, "SHIELD_APPLIED", shelter.id, false, true)
	return {"ok":true,"message":message}

static func ordered_plan(plan: Array[GameAction]) -> Array[GameAction]:
	var ordered: Array[GameAction] = []
	for action in plan:
		if action.type in ["VERIFY", "MONITOR"]: ordered.append(action)
	for action in plan:
		if action.type not in ["VERIFY", "MONITOR"]: ordered.append(action)
	return ordered

# A dry run makes confirmation atomic. Invalid plans never partially spend supplies.
func project_plan(plan: Array[GameAction]) -> Dictionary:
	var projected := state.copy()
	var simulator := ActionManager.new(projected, EventLogger.new())
	for action in ordered_plan(plan):
		var result := simulator.execute(action)
		if not result.ok: return {"ok":false,"error":result.error}
	return {"ok":true,"state":projected}

func commit_plan(plan: Array[GameAction]) -> Dictionary:
	var projection := project_plan(plan)
	if not projection.ok: return projection
	var messages: Array[String] = []
	for action in ordered_plan(plan):
		messages.append(execute(action).message)
	return {"ok":true,"messages":messages}
