class_name PlayerBelief
extends RefCounted

var suspected_source: String
var predicted_next: String
var preferred_action: String
var confidence: int

func _init(source: String = "", next: String = "", action: String = "", certainty: int = 3) -> void:
	suspected_source = source
	predicted_next = next
	preferred_action = action
	confidence = certainty

func to_dictionary() -> Dictionary:
	return {"suspected_source":suspected_source,"predicted_next":predicted_next,
		"preferred_action":preferred_action,"confidence":confidence}
