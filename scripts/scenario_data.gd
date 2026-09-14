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
var supply_depots: Array
var supply_amounts: Dictionary
var public_intel: Array
var exposure_progresses := true
var original_source: String
var ground_truth_timeline: Array

static func load_default() -> ScenarioData:
	return from_dictionary(JSON.parse_string(FileAccess.get_file_as_string("res://scenarios/scenario_01.json")))

static func from_dictionary(data: Dictionary) -> ScenarioData:
	var scenario := ScenarioData.new()
	for key in data:
		scenario.set(key, data[key])
	assert(scenario.initial_pressures.size() == 8, "A mission needs eight shelters.")
	assert(scenario.rounds == 3, "MVP missions last three rounds.")
	assert(scenario.public_intel.size() == scenario.rounds, "Publish one scheduled report each round.")
	assert(scenario.initial_pressures.values().count(1.0) == 1 or scenario.initial_pressures.values().count(1) == 1, "Start with exactly one exposure.")
	assert(not scenario.initial_pressures.values().has(2), "No initial Overrun shelters.")
	return scenario

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
