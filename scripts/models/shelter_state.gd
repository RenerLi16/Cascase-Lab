class_name ShelterState
extends RefCounted

var id: String
var display_name: String
var zombie_pressure: int
var is_overrun: bool:
	get: return zombie_pressure == 2
var is_monitored := false
var verified_history: Array = []
var shielded_this_round := false
# Monitoring starts a baseline internally, but only changes are reported publicly.
var monitor_known_pressure := -1

func _init(node_id: String = "", label: String = "", pressure: int = 0) -> void:
	id = node_id
	display_name = label
	zombie_pressure = clampi(pressure, 0, 2)

func to_dictionary() -> Dictionary:
	return {"id":id,"display_name":display_name,"zombie_pressure":zombie_pressure,
		"is_overrun":is_overrun,"is_monitored":is_monitored,"verified_history":verified_history.duplicate(true),
		"shielded_this_round":shielded_this_round,"monitor_known_pressure":monitor_known_pressure}
