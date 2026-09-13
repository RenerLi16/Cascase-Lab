class_name NetworkManager
extends RefCounted

var state: GameState

func _init(current_state: GameState) -> void:
	state = current_state

# Supply is undirected; pressure resolution deliberately uses directed edges instead.
func get_supply_path(depot: String, shelter: String, excluded_edge: String = "") -> Array[String]:
	if not state.depots.has(depot) or not state.shelters.has(shelter):
		return []
	if state.shelters[depot].is_overrun or state.shelters[shelter].is_overrun:
		return []
	var queue: Array[String] = [depot]
	var previous := {depot:""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == shelter:
			var path: Array[String] = []
			while current != "":
				path.push_front(current)
				current = previous[current]
			return path
		for edge: EdgeState in state.edges.values():
			if edge.isolated or edge.id == excluded_edge:
				continue
			var neighbor := ""
			if edge.from == current: neighbor = edge.to
			elif edge.to == current: neighbor = edge.from
			if neighbor != "" and not previous.has(neighbor) and not state.shelters[neighbor].is_overrun:
				previous[neighbor] = current
				queue.append(neighbor)
	return []

func can_supply_reach(depot: String, shelter: String) -> bool:
	return not get_supply_path(depot, shelter).is_empty()

func get_reachable_shelters(depot: String, excluded_edge: String = "") -> Array[String]:
	var output: Array[String] = []
	for id in state.shelters:
		if not get_supply_path(depot, id, excluded_edge).is_empty(): output.append(id)
	return output

func preview_isolation(edge_id: String) -> Dictionary:
	var loss := {}
	if not state.edges.has(edge_id): return loss
	for depot in state.depots:
		var before := get_reachable_shelters(depot)
		var after := get_reachable_shelters(depot, edge_id)
		var disconnected: Array[String] = []
		for id in before:
			if not after.has(id): disconnected.append(id)
		loss[depot] = disconnected
	return loss
