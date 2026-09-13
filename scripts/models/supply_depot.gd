class_name SupplyDepot
extends RefCounted

var node: String
var supply_remaining: int
var capacity: int

func _init(node_id: String = "", amount: int = 0) -> void:
	node = node_id
	supply_remaining = amount
	capacity = amount

func to_dictionary() -> Dictionary:
	return {"node":node,"supply_remaining":supply_remaining,"capacity":capacity}
