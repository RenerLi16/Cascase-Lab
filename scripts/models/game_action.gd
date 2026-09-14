class_name GameAction
extends RefCounted

const TYPES := ["VERIFY", "MONITOR", "SHIELD", "ISOLATE"]
var type: String
var target: String
var cost: int
var depot_used: String
var endpoint_depots: Array[String] = []
var deliveries: Array = []
var round: int
var completed := false

func _init(kind: String = "", destination: String = "", depot: String = "", round_number: int = 1) -> void:
	type = kind
	target = destination
	cost = 2 if kind == "ISOLATE" else 1
	depot_used = depot
	round = round_number
	if depot != "": endpoint_depots.append(depot)

func to_dictionary() -> Dictionary:
	return {"type":type,"target":target,"cost":cost,"depot_used":depot_used,
		"endpoint_depots":endpoint_depots.duplicate(),"deliveries":deliveries.duplicate(true),
		"round":round,"completed":completed}
