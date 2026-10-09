class_name EdgeState
extends RefCounted

var id: String
var from: String
var to: String
var isolated := false
# Copied from ScenarioData.bridges. Only bridge edges can be closed (internal action ISOLATE).
var bridge := false
# `from` and `to` are stable endpoint names, not directions. Roads are undirected.
var length := 1.0

func _init(source: String = "", destination: String = "") -> void:
	from = source
	to = destination
	id = "%s-%s" % [source, destination]

func to_dictionary() -> Dictionary:
	return {"id":id,"endpoints":[from,to],"isolated":isolated,"bridge":bridge,"length":length}

func other_endpoint(node: String) -> String:
	return to if node == from else (from if node == to else "")
