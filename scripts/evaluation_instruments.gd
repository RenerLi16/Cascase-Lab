class_name EvaluationInstruments
extends RefCounted

# Proposed instruments, not validated scales. Shared with backend validation and exports.
static var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/evaluation_instruments.json"))

static func questions(kind: String, ai_applicable: bool = false) -> Array:
	var result: Array = []
	for source in definitions[kind].questions:
		if source.get("ai_only",false) and not ai_applicable: continue
		var question: Dictionary = source.duplicate(true)
		if question.id == "influence" and not ai_applicable: question.options.erase("AI message")
		result.append(question)
	return result

static func valid(kind: String, answers: Dictionary, ai_applicable: bool = false) -> bool:
	var fields := questions(kind,ai_applicable)
	if answers.size() != fields.size(): return false
	for question in fields:
		var value = answers.get(question.id)
		if not value is String: return false
		if question.has("options"):
			if not question.options.has(value): return false
		elif value.strip_edges().is_empty() or value.length() > int(question.max_length): return false
	return true
