class_name PlayerBelief
extends RefCounted

# Retained model boundary; schema v2 measures a current decision, never a source guess.
const ACTIONS := ["VERIFY", "MONITOR", "SHIELD", "ISOLATE", "WAIT"]
const REASONS := ["", "visible outbreak", "suspected hidden exposure", "protect important route", "protect supply access", "gather more information", "prevent cascade", "other / uncertain"]
var danger_location: String
var preferred_action: String
var action_target: String
var confidence: int
var reason: String

func _init(danger: String = "", action: String = "", target: String = "", certainty: int = 0, rationale: String = "") -> void:
	danger_location = danger
	preferred_action = action
	action_target = target
	confidence = certainty
	reason = rationale

func to_dictionary() -> Dictionary:
	return {"danger_location":danger_location,"preferred_action":preferred_action,
		"action_target":action_target,"confidence":confidence,"reason":reason}
