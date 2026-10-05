class_name MissionSession
extends RefCounted

var session_id := Crypto.new().generate_random_bytes(16).hex_encode()
var order: Array = []
var order_source := "development_default_not_randomized"
var condition: GameManager.InterventionType
var purpose: GameManager.RunPurpose
var index := 0
var records: Array = []
var current: GameManager
var error := ""

func _init(mode: GameManager.RunPurpose = GameManager.RunPurpose.NORMAL, assigned: GameManager.InterventionType = GameManager.InterventionType.NONE, configured_order: Array = []) -> void:
	purpose = mode
	condition = assigned
	order = configured_order.duplicate()
	if order.is_empty():
		order = ScenarioData.registry().development_default_order.duplicate()
	else: order_source = "configured"
	if purpose == GameManager.RunPurpose.NORMAL:
		var registered: Array = ScenarioData.registry().development_default_order.duplicate()
		var sorted_order := order.duplicate()
		registered.sort()
		sorted_order.sort()
		if sorted_order != registered:
			error = "Normal sessions require each of the four registered missions exactly once."
			return
	elif order.size() != 1:
		error = "Dev Mode requires one selected scenario."
		return
	for id in order:
		if ScenarioData.load_by_id(id) == null:
			error = ScenarioData.last_error
			return
	_load_current()

func _load_current() -> void:
	current = GameManager.new(ScenarioData.load_by_id(order[index]),condition,Callable(),purpose)
	# Facilitator configuration is only allowed before the first mission starts.
	current.condition_locked = index > 0

func capture_result() -> bool:
	if current == null or current.phase != GameManager.Phase.RESULTS: return false
	if records.size() == index:
		condition = current.intervention_type
		var record := current.export_dictionary()
		record["session_id"] = session_id
		record["scenario_index"] = index
		record["completed"] = true
		record["scenario_order"] = order.duplicate()
		record["order_source"] = order_source
		records.append(record)
	return true

func advance() -> bool:
	if not capture_result() or index + 1 >= order.size(): return false
	current.invalidate()
	index += 1
	_load_current()
	return true

func is_complete() -> bool:
	return records.size() == order.size()

func export_dictionary() -> Dictionary:
	if current != null: capture_result()
	return {"schema_version":4,"session_id":session_id,"run_purpose":"dev" if purpose == GameManager.RunPurpose.DEV_SANDBOX else "normal", "research_eligible":false,"surveys_skipped":purpose == GameManager.RunPurpose.DEV_SANDBOX,"dev_used":purpose == GameManager.RunPurpose.DEV_SANDBOX,"scenario_order":order.duplicate(),"order_source":order_source,"condition":current.condition_name(),"completed":is_complete(),"missions":records.duplicate(true),"in_progress":current.export_dictionary() if current.phase != GameManager.Phase.RESULTS else {}}

func research_submission() -> Dictionary:
	return current.research_submission()
