class_name GameState
extends RefCounted

var shelters: Dictionary = {}
var edges: Dictionary = {}
var depots: Dictionary = {}
var round := 1
var actions: Array[GameAction] = []
var investigation_log: Array[String] = []
var monitor_alerts: Array[String] = []
var round_summaries: Array = []
var spread_calculations: Array = []

func _init(scenario: ScenarioData = null) -> void:
	if scenario == null:
		return
	for id in scenario.initial_pressures:
		shelters[id] = ShelterState.new(id, scenario.shelter_names[id], int(scenario.initial_pressures[id]))
	for connection in scenario.edges:
		var edge := EdgeState.new(connection[0], connection[1])
		edges[edge.id] = edge
	for id in scenario.supply_depots:
		depots[id] = SupplyDepot.new(id, int(scenario.supply_amounts[id]))

func copy() -> GameState:
	var other := GameState.new()
	other.round = round
	for id in shelters:
		var original: ShelterState = shelters[id]
		var shelter := ShelterState.new(id, original.display_name, original.zombie_pressure)
		shelter.is_monitored = original.is_monitored
		shelter.shielded_this_round = original.shielded_this_round
		shelter.verified_history = original.verified_history.duplicate(true)
		shelter.monitor_known_pressure = original.monitor_known_pressure
		other.shelters[id] = shelter
	for id in edges:
		var edge := EdgeState.new(edges[id].from, edges[id].to)
		edge.isolated = edges[id].isolated
		other.edges[id] = edge
	for id in depots:
		var depot := SupplyDepot.new(id, depots[id].capacity)
		depot.supply_remaining = depots[id].supply_remaining
		other.depots[id] = depot
	return other

func total_supply() -> int:
	var total := 0
	for depot in depots.values():
		total += depot.supply_remaining
	return total

func overrun_ids() -> Array[String]:
	var output: Array[String] = []
	for id in shelters:
		if shelters[id].is_overrun:
			output.append(id)
	return output

func to_dictionary() -> Dictionary:
	var output := {"round":round,"shelters":{},"edges":{},"depots":{},"actions":[],"round_summaries":round_summaries.duplicate(true)}
	for id in shelters: output.shelters[id] = shelters[id].to_dictionary()
	for id in edges: output.edges[id] = edges[id].to_dictionary()
	for id in depots: output.depots[id] = depots[id].to_dictionary()
	for action in actions: output.actions.append(action.to_dictionary())
	return output
