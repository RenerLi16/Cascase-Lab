class_name GameManager
extends RefCounted

signal changed
signal confidential_recorded(record: Dictionary)
var confidential_records: Array = []
var support_provider: SupportProvider = MockSupportProvider.new()
var support_session_id := "local-" + Crypto.new().generate_random_bytes(16).hex_encode()
var frozen_support_context: Dictionary = {}
var intervention_identity: Dictionary = {}

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
const DISCUSSION_SECONDS := 120
# Export schema 5: narrative dispatches retired (no public_intel, no PUBLIC_INTEL_SHOWN events).
const EXPORT_SCHEMA := 5
var discussion_deadline_ms := 0
var _support_clock: Callable
var private_player := 0
var private_surveys: Dictionary = {}
var dev_mode := false
var dev_used := false
static var _generation := 0
var run_token := 0
enum RunPurpose { NORMAL, DEV_SANDBOX }
var _run_purpose := RunPurpose.NORMAL
var run_purpose: RunPurpose:
	get: return _run_purpose
var condition_locked := false

func is_sandbox() -> bool:
	return _run_purpose == RunPurpose.DEV_SANDBOX

func begin_sandbox_actions() -> bool:
	if not is_sandbox() or phase != Phase.OBSERVE: return false
	_set_phase(Phase.ACTIONS)
	return true

func invalidate() -> void:
	_generation += 1
	run_token = _generation

var pending_action: GameAction
var pending_resolution: Dictionary = {}
var resolution_applied := false
var last_summary: Dictionary = {}
var latest_observation: Dictionary = {}

func _init(data: ScenarioData = null, condition: InterventionType = InterventionType.NONE, clock: Callable = Callable(), purpose: RunPurpose = RunPurpose.NORMAL) -> void:
	_run_purpose = purpose
	scenario = data if data != null else ScenarioData.load_default()
	_intervention_type = condition if condition in InterventionType.values() else InterventionType.NONE
	_support_clock = clock if clock.is_valid() else func(): return Time.get_ticks_msec()
	reset(false)

func reset(emit_change: bool = true) -> void:
	invalidate()
	state = GameState.new(scenario)
	logger = EventLogger.new()
	action_manager = ActionManager.new(state,logger)
	phase = Phase.OBSERVE
	private_player = 0
	private_surveys.clear()
	dev_mode = false
	dev_used = is_sandbox()
	support_message = {}
	frozen_support_context = {}
	intervention_identity = {}
	confidential_records.clear()
	support_shown = false
	support_deadline_ms = 0
	discussion_deadline_ms = 0
	pending_action = null
	pending_resolution = {}
	resolution_applied = false
	last_summary = {}
	latest_observation = {}
	logger.record(0,"MISSION_STARTED",scenario.scenario_id,null,null,{"schema_version":EXPORT_SCHEMA,"run_purpose":"dev" if is_sandbox() else "normal","research_eligible":false,"surveys_skipped":is_sandbox(),"dev_used":dev_used,"condition":condition_name(),"support_version":SupportLibrary.VERSION,"context_version":SupportContext.VERSION})
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
	return not is_sandbox() and not condition_locked and phase == Phase.OBSERVE and state.round == 1 and private_surveys.is_empty() and state.actions.is_empty()

func configure_condition(condition: int) -> bool:
	if not can_configure_condition() or not condition in InterventionType.values(): return false
	_intervention_type = condition as InterventionType
	reset()
	return true

func start_private() -> void:
	if is_sandbox() or phase != Phase.OBSERVE: return
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
	if belief.confidence < 1 or belief.confidence > 5 or belief.reason.is_empty() or not PlayerBelief.REASONS.has(belief.reason): return false
	# Snapshot prevents later form changes from mutating a submitted measurement.
	var response := belief.to_dictionary()
	private_surveys[state.round].append(response)
	_confidential("private", {"type":"PRIVATE_RESPONSE","round":state.round,"slot":"P%d" % (private_player+1),"response":response.duplicate(true)})
	# A receipt contains neither the answer nor a participant identifier.
	logger.record(state.round,"PRIVATE_SURVEY_SUBMITTED")
	private_player += 1
	if private_player < 3:
		_set_phase(Phase.PRIVATE_GATE)
	else:
		discussion_deadline_ms = int(_support_clock.call()) + DISCUSSION_SECONDS * 1000
		_prepare_support()
		_set_phase(Phase.DISCUSSION)
	return true

func discussion_seconds_remaining() -> int:
	return maxi(0,ceili(float(discussion_deadline_ms-int(_support_clock.call()))/1000.0))

func tick_discussion() -> void:
	if phase == Phase.DISCUSSION and discussion_seconds_remaining() == 0: begin_support()

func begin_support() -> bool:
	if is_sandbox() or phase != Phase.DISCUSSION or discussion_seconds_remaining() > 0: return false
	support_shown = false
	support_deadline_ms = 0
	_set_phase(Phase.INTERVENTION)
	return true

func _confidential(channel: String, payload: Dictionary) -> void:
	var record := {"channel":channel,"payload":payload.duplicate(true)}
	confidential_records.append(record)
	confidential_recorded.emit(record)

func _prepare_support() -> void:
	support_message = {}
	support_shown = false
	support_deadline_ms = 0
	frozen_support_context = SupportContext.build(state,private_surveys.get(state.round,[]),scenario.exposure_progresses)
	intervention_identity = {"session":support_session_id,"scenario":scenario.scenario_id,"round":state.round}
	if intervention_type == InterventionType.NONE:
		support_message = SupportLibrary.generate(frozen_support_context,"NONE")
		return
	_confidential("audit", {"type":"AI_REQUESTED","identity":intervention_identity.duplicate(),"context_version":SupportContext.VERSION,"context":frozen_support_context.duplicate(true),"requested_utc":Time.get_datetime_string_from_system(true)+"Z"})
	var token := run_token
	var round_number := state.round
	support_provider.request(frozen_support_context.duplicate(true),condition_name(),intervention_identity.duplicate(),func(result: Dictionary): _receive_support(result,token,round_number))

func _receive_support(result: Dictionary, token: int, round_number: int) -> void:
	if token != run_token or round_number != state.round or support_shown: return
	if result.has("error") or not result.has("text"):
		var reason := str(result.get("error","invalid_response"))
		support_message = {"text":"提示: AI support unavailable / AI 支持暂不可用。\n说明: 本轮未提供 AI 建议，请依据现有公开信息判断。\n暂停: 阅读暂停仍然保留。此开发故障处理政策须经批准后方可用于研究。", "template_id":"failure.unavailable","version":"development-failure-1","provider":"unavailable","error":reason}
		_confidential("audit", {"type":"AI_FAILURE","identity":intervention_identity.duplicate(),"error":reason})
	else:
		support_message = result.duplicate(true)
	_confidential("audit", {"type":"AI_RESULT","identity":intervention_identity.duplicate(),"result":support_message.duplicate(true),"received_utc":Time.get_datetime_string_from_system(true)+"Z"})
	if phase == Phase.INTERVENTION: changed.emit()

func mark_support_shown() -> bool:
	if phase != Phase.INTERVENTION or support_shown or support_message.is_empty(): return false
	support_shown = true
	support_deadline_ms = int(_support_clock.call()) + SupportLibrary.PAUSE_SECONDS * 1000
	_confidential("audit", {"type":"AI_DISPLAYED" if intervention_type != InterventionType.NONE else "NEUTRAL_PAUSE_DISPLAYED","identity":intervention_identity.duplicate(),"displayed_text":support_message.text,"displayed_utc":Time.get_datetime_string_from_system(true)+"Z","elapsed_ms":Time.get_ticks_msec()-logger.started_ticks,"provider":support_message.get("provider","none")})
	# Categories only: never persist the support input payload or individual views here.
	logger.record(state.round,"SUPPORT_SHOWN","",null,null,{
		"condition":condition_name(),"scenario_id":scenario.scenario_id,"round":state.round,
		"allowed_inputs":SupportContext.CATEGORIES.duplicate(),"displayed_text":support_message.text,
		"template_id":support_message.template_id,"template_version":support_message.version,"context_version":SupportContext.VERSION})
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
		logger.record(state.round,"MISSION_COMPLETED","",null,null,{"survivors":state.shelters.size()-state.overrun_ids().size(),"supply_used":6-state.total_supply(),"dev_used":dev_used})
		_set_phase(Phase.RESULTS)
	else:
		state.round += 1
		_set_phase(Phase.OBSERVE)

func set_dev_mode(enabled: bool) -> void:
	if not is_sandbox() or phase in [Phase.DELIVERY,Phase.RESOLUTION,Phase.PRIVATE_GATE,Phase.PRIVATE_FORM,Phase.INTERVENTION]: return
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
		var responses: Array = SupportContext.build(state,private_surveys[round_number]).responses
		for response in responses: surveys.append({"round":round_number,"response":response})
	return surveys

func export_dictionary() -> Dictionary:
	return {"schema_version":EXPORT_SCHEMA,"context_version":SupportContext.VERSION,"run_purpose":"dev" if is_sandbox() else "normal","research_eligible":false,"eligibility_note":"Local development build; no approved research submission configured.","surveys_skipped":is_sandbox(),"scenario_version":scenario.scenario_id.get_slice("_v",1),"mode_settings":{"hidden_state_reveal":dev_mode,"support_enabled":not is_sandbox()},"scenario_id":scenario.scenario_id,"intervention":condition_name(),"support_version":SupportLibrary.VERSION,"dev_used":dev_used,
		"events":logger.to_array(),"private_surveys":anonymous_surveys(),"development_private_audit":confidential_records.duplicate(true),
		"observations":state.observations.duplicate(true),"final_state":state.to_dictionary(),
		"ground_truth":{"initial_exposure_ids":scenario.initial_exposure_ids(),"original_source":scenario.original_source,"initial_pressures":scenario.initial_pressures,"timeline":scenario.ground_truth_timeline}}

# Local debug exports are allowed. No research backend is configured in this build.
func research_submission() -> Dictionary:
	return {"ok":false,"error":"Development runs cannot be submitted as research." if is_sandbox() or dev_used else "No approved research submission configured."}
