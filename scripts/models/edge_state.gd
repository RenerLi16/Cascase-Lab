class_name EdgeState
extends RefCounted

var id: String
var from: String
var to: String
var isolated := false

func _init(source: String = "", destination: String = "") -> void:
	from = source
	to = destination
	id = "%s-%s" % [source, destination]

func to_dictionary() -> Dictionary:
	return {"id":id,"from":from,"to":to,"isolated":isolated}
