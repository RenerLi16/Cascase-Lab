class_name ScenarioData
extends RefCounted

var scenario_id: String
var scenario_title: String
var rounds: int
var node_positions: Dictionary
var world_size: Array
var road_bends: Dictionary
var shelter_names: Dictionary
var initial_pressures: Dictionary
var edges: Array
# Bridge-only closure (rule bridge-only-1): the sole authority for which edges can close.
# Rendering, action validation, survey targets and support context all read this list.
var bridges: Array
var supply_depots: Array
var supply_amounts: Dictionary
var exposure_progresses := true
var original_source: String
var ground_truth_timeline: Array

static var last_error := ""
const REGISTRY_PATH := "res://scenarios/registry.json"
const FIELDS := ["scenario_id", "scenario_title", "rounds", "node_positions", "world_size", "road_bends", "shelter_names", "initial_pressures", "edges", "bridges", "supply_depots", "supply_amounts", "exposure_progresses", "original_source", "ground_truth_timeline"]
# Retired narrative dispatches (context cascade-context-2). Older scenario files may still
# carry this field; it is explicitly ignored and never copied into active gameplay.
const DEPRECATED_FIELDS := ["public_intel"]

static func registry() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	return parsed if parsed is Dictionary else {}

static func load_default() -> ScenarioData:
	return load_by_id("riverside_01_v3")

static func load_by_id(id: String) -> ScenarioData:
	var matches: Array = []
	for entry in registry().get("scenarios", []):
		if entry.id == id: matches.append(entry)
	if matches.size() != 1:
		last_error = "Unknown or duplicated scenario ID: " + id
		return null
	var result := load_path(matches[0].path)
	if result != null and result.scenario_id != id:
		last_error = "Scenario ID does not match registry: " + id
		return null
	return result

static func load_path(path: String) -> ScenarioData:
	if not FileAccess.file_exists(path):
		last_error = "Scenario file is missing: " + path
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		last_error = "Scenario must contain a JSON object: " + path
		return null
	return from_dictionary(parsed)

static func validate(data: Dictionary) -> String:
	for field in FIELDS:
		if not data.has(field): return "Missing scenario field: " + field
	for field in ["node_positions", "road_bends", "shelter_names", "initial_pressures", "supply_amounts"]:
		if not data[field] is Dictionary: return field + " must be an object."
	for field in ["world_size", "edges", "bridges", "supply_depots", "ground_truth_timeline"]:
		if not data[field] is Array: return field + " must be an array."
	if not data.scenario_id is String or data.scenario_id.is_empty() or not data.scenario_title is String: return "Invalid scenario identity."
	if data.rounds != 3: return "A mission requires three rounds."
	if data.world_size.size() != 2: return "Invalid world size."
	for value in data.world_size:
		if not _number(value) or value <= 0: return "World dimensions must be positive."
	var nodes: Dictionary = data.initial_pressures
	if nodes.size() != 8 or data.node_positions.size() != 8 or data.shelter_names.size() != 8: return "A mission needs eight unique shelters."
	var exposed: Array = []
	var positions: Array = []
	for id in nodes:
		if not id is String or id.is_empty() or "-" in id: return "Invalid shelter ID."
		if not _number(nodes[id]) or (nodes[id] != 0 and nodes[id] != 1): return "Initial pressure must be 0 or 1."
		if nodes[id] == 1: exposed.append(id)
		if not data.node_positions.has(id) or not data.shelter_names.get(id) is String: return "Missing shelter metadata: " + id
		var point = data.node_positions[id]
		if not _point(point, data.world_size) or positions.has(point): return "Invalid or overlapping coordinate: " + id
		positions.append(point)
	exposed.sort()
	# Registered ground-truth declarations; never included in support inputs.
	var expected := {"riverside_01_v3": ["E"], "twin_districts_02_v2": ["D"], "lifeline_03_v2": ["F"], "crossfire_04_v2": ["B", "F"]}
	if expected.has(data.scenario_id) and exposed != expected[data.scenario_id]: return "Starting exposures do not match registered scenario."
	if exposed.is_empty(): return "At least one initial exposure is required."
	var seen := {}
	var adjacency := {}
	for id in nodes: adjacency[id] = []
	var edge_ids: Array = []
	for pair in data.edges:
		if not pair is Array or pair.size() != 2: return "Invalid road endpoints."
		if not nodes.has(pair[0]) or not nodes.has(pair[1]) or pair[0] == pair[1]: return "Road endpoints must be distinct shelters."
		var sorted_pair: Array = pair.duplicate()
		sorted_pair.sort()
		var key := str(sorted_pair[0]) + "-" + str(sorted_pair[1])
		if seen.has(key): return "Duplicated undirected road: " + key
		seen[key] = true
		edge_ids.append(str(pair[0]) + "-" + str(pair[1]))
		adjacency[pair[0]].append(pair[1])
		adjacency[pair[1]].append(pair[0])
	var reached: Array = [nodes.keys()[0]]
	var cursor := 0
	while cursor < reached.size():
		for neighbor in adjacency[reached[cursor]]:
			if not reached.has(neighbor): reached.append(neighbor)
		cursor += 1
	if reached.size() != 8: return "Starting graph must be connected."
	var bridge_ids: Array = []
	for id in data.bridges:
		# Exact edge IDs, as in road_bends; a bridge never names an absent or reversed road.
		if not id is String or not edge_ids.has(id) or bridge_ids.has(id): return "Invalid bridge ID: " + str(id)
		bridge_ids.append(id)
	for id in data.road_bends:
		if not edge_ids.has(id) or not data.road_bends[id] is Array: return "Invalid road bend ID."
		for point in data.road_bends[id]:
			if not _point(point, data.world_size): return "Invalid road bend coordinate."
	if data.supply_depots.size() != 2 or data.supply_depots[0] == data.supply_depots[1] or data.supply_amounts.size() != 2: return "Two distinct depots are required."
	var total := 0
	for id in data.supply_depots:
		if not nodes.has(id) or not data.supply_amounts.has(id): return "Invalid depot."
		var amount = data.supply_amounts[id]
		if not _number(amount) or amount < 0 or amount != int(amount): return "Invalid supply amount."
		total += int(amount)
	if total != 6: return "A mission requires six supplies."
	if not data.exposure_progresses is bool or not data.original_source is String: return "Invalid progression or source metadata."
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _point(value: Variant, bounds: Array) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and value[0] > 0 and value[0] < bounds[0] and value[1] > 0 and value[1] < bounds[1]

static func from_dictionary(data: Dictionary) -> ScenarioData:
	last_error = validate(data)
	if not last_error.is_empty(): return null
	var scenario := ScenarioData.new()
	# Only current fields are copied; DEPRECATED_FIELDS are deliberately dropped here.
	for key in FIELDS: scenario.set(key, data[key])
	return scenario

func initial_exposure_ids() -> Array[String]:
	var result: Array[String] = []
	for id in initial_pressures:
		if initial_pressures[id] == 1: result.append(id)
	result.sort()
	return result

func is_bridge(edge_id: String) -> bool:
	return bridges.has(edge_id)

func road_points(edge_id: String) -> PackedVector2Array:
	var endpoints := edge_id.split("-")
	var points := PackedVector2Array()
	var first: Array = node_positions[endpoints[0]]
	points.append(Vector2(first[0],first[1]))
	for point in road_bends.get(edge_id, []): points.append(Vector2(point[0],point[1]))
	var last: Array = node_positions[endpoints[1]]
	points.append(Vector2(last[0],last[1]))
	return points

func road_length(edge_id: String) -> float:
	var points := road_points(edge_id)
	var length := 0.0
	for index in points.size()-1: length += points[index].distance_to(points[index+1])
	return length
