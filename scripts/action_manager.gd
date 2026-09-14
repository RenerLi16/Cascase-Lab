class_name ActionManager
extends RefCounted

var state: GameState
var logger: EventLogger
var supply: SupplyManager
var in_transit: GameAction

func _init(current_state: GameState, event_logger: EventLogger) -> void:
	state = current_state
	logger = event_logger
	supply = SupplyManager.new(state)

func unavailable_reason(kind: String, target: String) -> String:
	if in_transit != null: return "DELIVERY IN PROGRESS"
	if not GameAction.TYPES.has(kind): return "UNKNOWN ACTION"
	if kind == "ISOLATE":
		if not state.edges.has(target): return "SELECT A ROAD"
		var edge: EdgeState = state.edges[target]
		if edge.isolated: return "ROAD CLOSED"
		if state.shelters[edge.from].is_overrun or state.shelters[edge.to].is_overrun: return "ENDPOINT OVERRUN"
	else:
		if not state.shelters.has(target): return "SELECT A SHELTER"
		var shelter: ShelterState = state.shelters[target]
		if shelter.is_overrun: return "OVERRUN"
		if kind == "MONITOR" and shelter.is_monitored: return "MONITOR ACTIVE"
		if kind == "SHIELD" and shelter.shielded_this_round: return "SHIELD ACTIVE"
	if supply.delivery_options(kind,target).is_empty():
		return "NO SUPPLY" if state.total_supply() < (2 if kind == "ISOLATE" else 1) else "NO SUPPLY ROUTE"
	return ""

func can_verify(target: String) -> bool:
	return unavailable_reason("VERIFY",target).is_empty()

func can_isolate(target: String) -> bool:
	return unavailable_reason("ISOLATE",target).is_empty()

func preview_isolation(target: String) -> Dictionary:
	return supply.network.preview_isolation(target)

func reserve(request: GameAction) -> Dictionary:
	var reason := unavailable_reason(request.type,request.target)
	if reason != "": return {"ok":false,"error":reason}
	if request.round != state.round: return {"ok":false,"error":"WRONG ROUND"}
	var assignments := request.endpoint_depots
	if not supply.delivery_options(request.type,request.target).has(assignments):
		return {"ok":false,"error":"NO SUPPLY ROUTE"}
	# Validate both endpoint deliveries and total stock before deducting either unit.
	var action := GameAction.new(request.type,request.target,"",state.round)
	action.endpoint_depots.assign(assignments)
	action.depot_used = "+".join(assignments)
	action.deliveries = supply.delivery_plan(action.type,action.target,assignments)
	logger.record(state.round,"ACTION_SELECTED",action.target,null,null,action.to_dictionary())
	for delivery in action.deliveries:
		var depot: SupplyDepot = state.depots[delivery.depot]
		var before := depot.supply_remaining
		depot.supply_remaining -= 1
		logger.record(state.round,"SUPPLY_SPENT",depot.node,before,depot.supply_remaining,{"action":action.type,"target":action.target})
		logger.record(state.round,"SUPPLY_DELIVERY_STARTED",delivery.target,null,null,delivery)
	in_transit = action
	return {"ok":true,"action":action}

func complete_delivery(action: GameAction) -> Dictionary:
	if action != in_transit or action.completed: return {"ok":false,"error":"NO PENDING DELIVERY"}
	for delivery in action.deliveries: logger.record(state.round,"SUPPLY_DELIVERED",delivery.target,null,null,delivery)
	var observation: Dictionary = {}
	if action.type == "ISOLATE":
		var loss := preview_isolation(action.target)
		state.edges[action.target].isolated = true
		logger.record(state.round,"EDGE_ISOLATED",action.target,false,true,{"supply_impact":loss})
	else:
		var shelter: ShelterState = state.shelters[action.target]
		match action.type:
			"VERIFY":
				var record := {"round":state.round,"pressure":shelter.zombie_pressure}
				shelter.verified_history.append(record)
				observation = {"type":"VERIFY","target":shelter.id,"round":state.round,"pressure":shelter.zombie_pressure}
				state.observations.append(observation)
				state.investigation_log.append("R%d · %s verified: Pressure %d" % [state.round,shelter.id,shelter.zombie_pressure])
				logger.record(state.round,"VERIFY_RESULT",shelter.id,null,shelter.zombie_pressure)
			"MONITOR":
				shelter.is_monitored = true
				logger.record(state.round,"MONITOR_INSTALLED",shelter.id,false,true)
			"SHIELD":
				shelter.shielded_this_round = true
				logger.record(state.round,"SHIELD_APPLIED",shelter.id,false,true)
	action.completed = true
	state.actions.append(action)
	logger.record(state.round,"ACTION_COMPLETED",action.target,null,null,action.to_dictionary())
	in_transit = null
	return {"ok":true,"observation":observation}
