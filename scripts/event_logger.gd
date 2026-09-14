class_name EventLogger
extends RefCounted

var events: Array[GameEvent] = []
var capture_timing := true
var started_ticks := Time.get_ticks_msec()

func record(round_number: int, kind: String, target: String = "", old_value: Variant = null, new_value: Variant = null, metadata: Dictionary = {}) -> void:
	var event := GameEvent.new()
	event.order = events.size() + 1
	event.elapsed_ms = Time.get_ticks_msec() - started_ticks if capture_timing else 0
	event.timestamp_utc = Time.get_datetime_string_from_system(true) + "Z" if capture_timing else ""
	event.round = round_number
	event.type = kind
	event.target = target
	event.old_value = old_value
	event.new_value = new_value
	event.metadata = metadata.duplicate(true)
	events.append(event)

func to_array() -> Array:
	var output: Array = []
	for event in events:
		output.append(event.to_dictionary())
	return output
