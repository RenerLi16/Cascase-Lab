class_name SupplyManager
extends RefCounted

var state: GameState
var network: NetworkManager

func _init(current_state: GameState) -> void:
	state = current_state
	network = NetworkManager.new(state)

func eligible_depots(target: String, cost: int = 1) -> Array[String]:
	var output: Array[String] = []
	for id in state.depots:
		if state.depots[id].supply_remaining >= cost and network.can_supply_reach(id,target):
			output.append(id)
	return output

# Each unit must arrive at its assigned endpoint before a road can close.
func delivery_options(kind: String, target: String) -> Array:
	var options: Array = []
	if kind == "ISOLATE":
		if not state.edges.has(target): return options
		var edge: EdgeState = state.edges[target]
		for first in eligible_depots(edge.from):
			for second in eligible_depots(edge.to):
				if first == second and state.depots[first].supply_remaining < 2: continue
				options.append([first,second])
	else:
		for depot in eligible_depots(target): options.append([depot])
	return options

func delivery_plan(kind: String, target: String, assignments: Array[String]) -> Array:
	var targets: Array = [target]
	if kind == "ISOLATE":
		var edge: EdgeState = state.edges[target]
		targets = [edge.from,edge.to]
	var output: Array = []
	for index in assignments.size():
		output.append({"depot":assignments[index],"target":targets[index],"units":1,
			"path":network.get_supply_path(assignments[index],targets[index])})
	return output

func stocked_reachability() -> Array[String]:
	var output: Array[String] = []
	for id in state.shelters:
		if not eligible_depots(id).is_empty(): output.append(id)
	return output
