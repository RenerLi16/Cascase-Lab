class_name NetworkManager
extends RefCounted

var state: GameState

func _init(current_state: GameState) -> void:
	state = current_state

# Dijkstra over physical road lengths. Stable edge order breaks equal-length ties.
# Both supply and zombie movement use the same undirected road topology.
func get_supply_path(depot: String, shelter: String, excluded_edge: String = "") -> Array[String]:
	if not state.depots.has(depot) or not state.shelters.has(shelter): return []
	if state.shelters[depot].is_overrun or state.shelters[shelter].is_overrun: return []
	var distance := {depot:0.0}
	var previous := {depot:""}
	var visited: Array[String] = []
	while true:
		var current := ""
		var best := INF
		for id in state.shelters:
			if not visited.has(id) and distance.get(id,INF) < best:
				current = id
				best = distance[id]
		if current == "": return []
		if current == shelter:
			var path: Array[String] = []
			while current != "":
				path.push_front(current)
				current = previous[current]
			return path
		visited.append(current)
		for edge: EdgeState in state.edges.values():
			if edge.isolated or edge.id == excluded_edge: continue
			var neighbor := edge.other_endpoint(current)
			if neighbor == "" or state.shelters[neighbor].is_overrun: continue
			var candidate: float = best + edge.length
			if candidate < distance.get(neighbor,INF):
				distance[neighbor] = candidate
				previous[neighbor] = current
	return []

func road_between(first: String, second: String) -> String:
	for edge: EdgeState in state.edges.values():
		if edge.other_endpoint(first) == second: return edge.id
	return ""

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
