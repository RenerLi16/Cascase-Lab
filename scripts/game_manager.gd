class_name GameManager
extends RefCounted

signal changed
enum Phase { OBSERVE, PRIVATE_GATE, PRIVATE_FORM, DISCUSSION, INTERVENTION, ACTIONS, DELIVERY, RESOLUTION, ROUND_COMPLETE, RESULTS }
enum InterventionType { NONE, DIRECT_RECOMMENDATION, CONSTRUCTIVE_DISSENT }

var scenario: ScenarioData
var state: GameState
var logger: EventLogger
var action_manager: ActionManager
var phase := Phase.OBSERVE
var _intervention_type := InterventionType.NONE
var intervention_type: InterventionType:
	get: return _intervention_type
var support_message: Dictionary = {}
var support_shown := false
var support_deadline_ms := 0
var _support_clock: Callable
var private_player := 0
var private_surveys: Dictionary = {}
var public_intel: Array = []
var dev_mode := false
var dev_used := false
var run_token := 0
var pending_action: GameAction
var pending_resolution: Dictionary = {}
var resolution_applied := false
var last_summary: Dictionary = {}
var latest_observation: Dictionary = {}

func _init(data: ScenarioData = null, condition: InterventionType = InterventionType.NONE, clock: Callable = Callable()) -> void:
	scenario = data if data != null else ScenarioData.load_default()
	_intervention_type = condition if condition in InterventionType.values() else InterventionType.NONE
	_support_clock = clock if clock.is_valid() else func(): return Time.get_ticks_msec()
	reset(false)

func reset(emit_change: bool = true) -> void:
	run_token += 1
	state = GameState.new(scenario)
	logger = EventLogger.new()
	action_manager = ActionManager.new(state,logger)
	phase = Phase.OBSERVE
	private_player = 0
	private_surveys.clear()
	public_intel.clear()
	dev_mode = false
	dev_used = false
	support_message = {}
	support_shown = false
	support_deadline_ms = 0
	pending_action = null
	pending_resolution = {}
	resolution_applied = false
	last_summary = {}
	latest_observation = {}
	logger.record(0,"SESSION_STARTED",scenario.scenario_id,null,null,{"schema_version":3,"condition":condition_name(),"support_version":SupportLibrary.VERSION})
	_publish_intel()
	logger.record(state.round,"PHASE_STARTED","OBSERVE")
	if emit_change: changed.emit()

func _set_phase(next: Phase) -> void:
	logger.record(state.round,"PHASE_ENDED",Phase.keys()[phase])
	phase = next
	logger.record(state.round,"PHASE_STARTED",Phase.keys()[phase])
	changed.emit()

func phase_label() -> String:
	if phase in [Phase.PRIVATE_GATE,Phase.PRIVATE_FORM]: return "PRIVATE JUDGMENT"
	if phase == Phase.INTERVENTION: return "DECISION PAUSE"
	return Phase.keys()[phase].replace("_"," ")

func condition_name() -> String:
	return InterventionType.keys()[_intervention_type]

func can_configure_condition() -> bool:
	return phase == Phase.OBSERVE and state.round == 1 and private_surveys.is_empty() and state.actions.is_empty()

func configure_condition(condition: int) -> bool:
	if not can_configure_condition() or not condition in InterventionType.values(): return false
	_intervention_type = condition as InterventionType
	reset()
	return true

func _publish_intel() -> void:
	for report in scenario.public_intel:
		if int(report.round) == state.round:
			public_intel.append(report.duplicate(true))
			logger.record(state.round,"PUBLIC_INTEL_SHOWN","city_surveillance",null,null,report)

func start_private() -> void:
	if phase != Phase.OBSERVE: return
	private_player = 0
	private_surveys[state.round] = []
	_set_phase(Phase.PRIVATE_GATE)

func open_private_form() -> void:
	if phase == Phase.PRIVATE_GATE: _set_phase(Phase.PRIVATE_FORM)

func survey_targets(kind: String) -> Array:
	if kind == "WAIT": return ["NONE"]
	return state.edges.keys() if kind == "ISOLATE" else state.shelters.keys()

func submit_belief(belief: PlayerBelief) -> bool:
	if phase != Phase.PRIVATE_FORM: return false
	if not state.shelters.has(belief.danger_location) and not state.edges.has(belief.danger_location): return false
	if not PlayerBelief.ACTIONS.has(belief.preferred_action): return false
	if not survey_targets(belief.preferred_action).has(belief.action_target): return false
	if belief.confidence < 1 or belief.confidence > 5 or not PlayerBelief.REASONS.has(belief.reason): return false
	# Snapshot prevents later form changes from mutating a submitted measurement.
	var response := belief.to_dictionary()
	private_surveys[state.round].append(response)
	# A receipt contains neither the answer nor a participant identifier.
	logger.record(state.round,"PRIVATE_SURVEY_SUBMITTED")
	private_player += 1
	if private_player < 3:
		_set_phase(Phase.PRIVATE_GATE)
	else:
		_set_phase(Phase.DISCUSSION)
	return true

func begin_support() -> bool:
	if phase != Phase.DISCUSSION: return false
	var context := SupportContext.build(state,public_intel,private_surveys.get(state.round,[]))
	support_message = SupportLibrary.generate(context,condition_name())
	support_shown = false
	support_deadline_ms = 0
	_set_phase(Phase.INTERVENTION)
	return true

func mark_support_shown() -> bool:
	if phase != Phase.INTERVENTION or support_shown: return false
	support_shown = true
	support_deadline_ms = int(_support_clock.call()) + SupportLibrary.PAUSE_SECONDS * 1000
	# Categories only: never persist the support input payload or individual views here.
	logger.record(state.round,"SUPPORT_SHOWN","",null,null,{
		"condition":condition_name(),"scenario_id":scenario.scenario_id,"round":state.round,
		"allowed_inputs":SupportContext.CATEGORIES.duplicate(),"displayed_text":support_message.text,
		"template_id":support_message.template_id,"template_version":support_message.version})
	return true

func support_seconds_remaining() -> int:
	if not support_shown: return SupportLibrary.PAUSE_SECONDS
	return maxi(0,ceili(float(support_deadline_ms - int(_support_clock.call())) / 1000.0))

func proceed_to_actions() -> bool:
	if phase != Phase.INTERVENTION or not support_shown or support_seconds_remaining() > 0: return false
	_set_phase(Phase.ACTIONS)
	return true

func dispatch_action(kind: String, target: String, depots: Array[String]) -> Dictionary:
	if phase != Phase.ACTIONS: return {"ok":false,"error":"NOT ACTION PHASE"}
	var request := GameAction.new(kind,target,"",state.round)
	request.endpoint_depots.assign(depots)
	var result := action_manager.reserve(request)
	if not result.ok: return result
	pending_action = result.action
	latest_observation = {}
	_set_phase(Phase.DELIVERY)
	return result

func complete_delivery(token: int) -> bool:
	if token != run_token or phase != Phase.DELIVERY: return false
	var result := action_manager.complete_delivery(pending_action)
	if not result.ok: return false
	latest_observation = result.observation
	pending_action = null
	_set_phase(Phase.ACTIONS)
	return true

# Pure hidden calculation: animation receives only the separately filtered public visuals.
func preview_resolution() -> Dictionary:
	var incoming := {}
	var movements: Array = []
	var calculations: Array = []
	var sources := state.overrun_ids()
	for id in state.shelters: incoming[id] = 0
	for edge: EdgeState in state.edges.values():
		if edge.isolated: continue
		for source: String in [edge.from,edge.to]:
			if not sources.has(source): continue
			var target := edge.other_endpoint(source)
			incoming[target] += 1
			if not state.shelters[target].is_overrun:
				movements.append({"road":edge.id,"from":source,"to":target})
	for id in state.shelters:
		var shelter: ShelterState = state.shelters[id]
		var old := shelter.zombie_pressure
		var incubation := 1 if old == 1 and scenario.exposure_progresses else 0
		var transmitted: int = 0 if shelter.shielded_this_round else incoming[id]
		calculations.append({"target":id,"old":old,"incoming":incoming[id],"incubation":incubation,
			"shielded":shelter.shielded_this_round,"new":mini(2,old+incubation+transmitted)})
	return {"calculations":calculations,"movements":movements}

func begin_resolution() -> bool:
	if phase != Phase.ACTIONS: return false
	pending_resolution = preview_resolution()
	resolution_applied = false
	latest_observation = {}
	logger.record(state.round,"RESOLUTION_PLANNED","",null,null,pending_resolution)
	_set_phase(Phase.RESOLUTION)
	return true

func apply_resolution(token: int) -> bool:
	if token != run_token or phase != Phase.RESOLUTION or resolution_applied: return false
	var newly: Array[String] = []
	var shields: Array[String] = []
	var alerts: Array = []
	var damage := 0
	state.spread_calculations = pending_resolution.calculations.duplicate(true)
	for calculation in state.spread_calculations:
		var shelter: ShelterState = state.shelters[calculation.target]
		shelter.zombie_pressure = calculation.new
		damage += calculation.new-calculation.old
		if calculation.old != calculation.new:
			logger.record(state.round,"PRESSURE_CHANGED",shelter.id,calculation.old,calculation.new,calculation)
			if shelter.is_overrun:
				newly.append(shelter.id)
				logger.record(state.round,"SHELTER_OVERRUN",shelter.id,false,true)
			if shelter.is_monitored:
				shelter.monitor_known_pressure = calculation.new
				var alert := {"type":"MONITOR","round":state.round,"target":shelter.id,"old":calculation.old,"new":calculation.new}
				alerts.append(alert)
				state.observations.append(alert)
				state.monitor_alerts.append("R%d · %s: %d → %d" % [state.round,shelter.id,calculation.old,calculation.new])
				logger.record(state.round,"MONITOR_ALERT",shelter.id,calculation.old,calculation.new)
		if shelter.shielded_this_round:
			shields.append(shelter.id)
			shelter.shielded_this_round = false
			logger.record(state.round,"SHIELD_EXPIRED",shelter.id,true,false)
	last_summary = {"round":state.round,"newly_overrun":newly,"shields":shields,"monitor_alerts":alerts,
		"survivors":state.shelters.size()-state.overrun_ids().size(),"supply_remaining":state.total_supply(),"damage":damage}
	state.round_summaries.append(last_summary.duplicate(true))
	logger.record(state.round,"DAMAGE_RESOLVED","",null,damage,{"newly_overrun":newly})
	resolution_applied = true
	changed.emit()
	return true

func finish_resolution(token: int) -> bool:
	if token != run_token or phase != Phase.RESOLUTION or not resolution_applied: return false
	logger.record(state.round,"ROUND_COMPLETED","",null,null,last_summary)
	_set_phase(Phase.ROUND_COMPLETE)
	return true

func next_round() -> void:
	if phase != Phase.ROUND_COMPLETE: return
	if state.round >= scenario.rounds:
		logger.record(state.round,"SESSION_COMPLETED","",null,null,{"survivors":state.shelters.size()-state.overrun_ids().size(),"supply_used":6-state.total_supply(),"dev_used":dev_used})
		_set_phase(Phase.RESULTS)
	else:
		state.round += 1
		_publish_intel()
		_set_phase(Phase.OBSERVE)

func set_dev_mode(enabled: bool) -> void:
	if phase in [Phase.DELIVERY,Phase.RESOLUTION,Phase.PRIVATE_GATE,Phase.PRIVATE_FORM,Phase.INTERVENTION]: return
	var previous := dev_mode
	dev_mode = enabled
	dev_used = dev_used or enabled
	logger.record(state.round,"DEV_MODE_CHANGED","",previous,enabled)
	changed.emit()

func closed_road_count() -> int:
	var count := 0
	for edge: EdgeState in state.edges.values():
		if edge.isolated: count += 1
	return count

func anonymous_surveys() -> Array:
	var surveys: Array = []
	for round_number in private_surveys:
		var responses: Array = SupportContext.build(state,[],private_surveys[round_number]).responses
		for response in responses: surveys.append({"round":round_number,"response":response})
	return surveys

func export_dictionary() -> Dictionary:
	return {"schema_version":3,"scenario_id":scenario.scenario_id,"intervention":condition_name(),"support_version":SupportLibrary.VERSION,"dev_used":dev_used,
		"events":logger.to_array(),"private_surveys":anonymous_surveys(),"public_intel":public_intel.duplicate(true),
		"observations":state.observations.duplicate(true),"final_state":state.to_dictionary(),
		"ground_truth":{"original_source":scenario.original_source,"initial_pressures":scenario.initial_pressures,"timeline":scenario.ground_truth_timeline}}
