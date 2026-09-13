class_name GameAction
extends RefCounted

const TYPES := ["VERIFY", "MONITOR", "SHIELD", "ISOLATE"]
var type: String
var target: String
var cost: int
var depot_used: String
var round: int

func _init(kind: String = "", destination: String = "", depot: String = "", round_number: int = 1) -> void:
	type = kind
	target = destination
	cost = 2 if kind == "ISOLATE" else 1
	depot_used = depot
	round = round_number

func to_dictionary() -> Dictionary:
	return {"type":type,"target":target,"cost":cost,"depot_used":depot_used,"round":round}
