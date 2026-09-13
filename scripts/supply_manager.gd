class_name SupplyManager
extends RefCounted

var state: GameState
var network: NetworkManager

func _init(current_state: GameState) -> void:
	state = current_state
	network = NetworkManager.new(state)

func eligible_depots(target: String, cost: int, road: bool = false) -> Array[String]:
	var output: Array[String] = []
	for id in state.depots:
		if state.depots[id].supply_remaining < cost: continue
		if road:
			if not state.edges.has(target): continue
			var edge: EdgeState = state.edges[target]
			# A crew closes a road from either reachable, non-Overrun endpoint.
			if network.can_supply_reach(id, edge.from) or network.can_supply_reach(id, edge.to):
				output.append(id)
		elif network.can_supply_reach(id, target): output.append(id)
	return output

func stocked_reachability() -> Array[String]:
	var output: Array[String] = []
	for id in state.shelters:
		if not eligible_depots(id, 1).is_empty(): output.append(id)
	return output
