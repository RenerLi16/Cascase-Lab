class_name GameEvent
extends RefCounted

var order: int
var elapsed_ms: int
var timestamp_utc: String
var round: int
var type: String
var target: String
var old_value: Variant
var new_value: Variant
var metadata: Dictionary

func to_dictionary() -> Dictionary:
	return {"order":order,"elapsed_ms":elapsed_ms,"timestamp_utc":timestamp_utc,"round":round,"type":type,"target":target,
		"old_value":old_value,"new_value":new_value,"metadata":metadata.duplicate(true)}
