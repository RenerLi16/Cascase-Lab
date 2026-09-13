class_name ScenarioData
extends RefCounted

var scenario_id: String
var scenario_title: String
var rounds: int
var node_positions: Dictionary
var shelter_names: Dictionary
var initial_pressures: Dictionary
var edges: Array
var supply_depots: Array
var supply_amounts: Dictionary
var public_evidence: Array
var diagnostic_evidence: Dictionary
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
	return scenario
