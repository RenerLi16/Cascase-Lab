class_name GameManager
extends RefCounted

signal changed
enum Phase { MENU, BRIEFING, PRIVATE_GATE, PRIVATE_FORM, BELIEFS, DISCUSSION, INTERVENTION, ACTIONS, SUMMARY, DIAGNOSTIC, RESULTS }
enum InterventionType { NONE, DIRECT_RECOMMENDATION, CONSTRUCTIVE_DISSENT }

var scenario: ScenarioData
var state: GameState
var logger: EventLogger
var action_manager: ActionManager
var phase := Phase.MENU
var intervention_type := InterventionType.NONE
var initial_beliefs: Array[PlayerBelief] = []
var updated_beliefs: Array[PlayerBelief] = []
var private_player := 0
var collecting_update := false
var dev_mode := false
var dev_used := false
var draft: Array[GameAction] = []
var last_summary: Dictionary = {}
var notices: Array[String] = []
# Fixed display permutation keeps simulations deterministic and avoids player-number labels.
const ANONYMOUS_ORDER := [1, 2, 0]

func _init(data: ScenarioData = null) -> void:
	scenario = data if data != null else ScenarioData.load_default()
	reset(false)

func reset(emit_change: bool = true) -> void:
	state = GameState.new(scenario)
	logger = EventLogger.new()
	action_manager = ActionManager.new(state, logger)
	phase = Phase.MENU
	initial_beliefs.clear()
	updated_beliefs.clear()
	private_player = 0
	collecting_update = false
	dev_mode = false
	dev_used = false
	draft.clear()
	notices.clear()
	last_summary = {}
	logger.record(0, "SESSION_STARTED", scenario.scenario_id, null, null, {"schema_version":1,"intervention":"NONE"})
	if emit_change: changed.emit()

func start_briefing() -> void:
	if phase != Phase.MENU: return
	phase = Phase.BRIEFING
	changed.emit()

func start_private(update: bool = false) -> void:
	if (not update and phase != Phase.BRIEFING) or (update and phase != Phase.DIAGNOSTIC): return
	collecting_update = update
	private_player = 0
	phase = Phase.PRIVATE_GATE
	changed.emit()

func open_private_form() -> void:
	if phase != Phase.PRIVATE_GATE: return
	phase = Phase.PRIVATE_FORM
	changed.emit()

func submit_belief(belief: PlayerBelief) -> bool:
	if phase != Phase.PRIVATE_FORM: return false
	if not state.shelters.has(belief.suspected_source) or belief.confidence < 1 or belief.confidence > 5: return false
	if belief.predicted_next != "None":
		if not state.shelters.has(belief.predicted_next) or state.shelters[belief.predicted_next].is_overrun: return false
	if not collecting_update and not GameAction.TYPES.has(belief.preferred_action): return false
	if collecting_update:
		belief.preferred_action = ""
		updated_beliefs.append(belief)
	else: initial_beliefs.append(belief)
	logger.record(state.round, "BELIEF_UPDATED" if collecting_update else "PRIVATE_BELIEF_SUBMITTED",
		"participant_%d" % ANONYMOUS_ORDER.find(private_player), null, belief.to_dictionary())
	private_player += 1
	phase = Phase.BELIEFS if private_player == 3 else Phase.PRIVATE_GATE
	changed.emit()
	return true

func begin_discussion() -> void:
	if phase != Phase.BELIEFS: return
	if collecting_update: state.round = 2
	# Reserved boundary for a future experiment condition. NONE never chooses an action.
	phase = Phase.INTERVENTION
	logger.record(state.round, "INTERVENTION_SKIPPED", "", null, null, {"condition":"NONE"})
	phase = Phase.DISCUSSION
	changed.emit()

func proceed_to_actions() -> void:
	if phase != Phase.DISCUSSION: return
	phase = Phase.ACTIONS
	notices.clear()
	changed.emit()

func return_to_discussion() -> void:
	if phase != Phase.ACTIONS: return
	phase = Phase.DISCUSSION
	changed.emit()

func queue_action(kind: String, target: String, depot: String) -> Dictionary:
	if phase != Phase.ACTIONS: return {"ok":false,"error":"Actions are only available during the action phase."}
	var action := GameAction.new(kind, target, depot, state.round)
	var next := draft.duplicate()
	next.append(action)
	var result := action_manager.project_plan(next)
	if not result.ok: return result
	draft.append(action)
	logger.record(state.round, "ACTION_SELECTED", target, null, null, action.to_dictionary())
	changed.emit()
	return {"ok":true}

func clear_draft() -> void:
	if phase != Phase.ACTIONS: return
	logger.record(state.round, "PLAN_CLEARED", "", draft.size(), 0)
	draft.clear()
	changed.emit()

func confirm_actions() -> Dictionary:
	if phase != Phase.ACTIONS or draft.is_empty(): return {"ok":false,"error":"No actions queued."}
	var result := action_manager.commit_plan(draft)
	if not result.ok: return result
	notices = result.messages
	draft.clear()
	changed.emit()
	return result

func projected_state() -> GameState:
	var result := action_manager.project_plan(draft)
	return result.state if result.ok else state.copy()

func resolve_zombie_spread() -> Dictionary:
	var incoming := {}
	var sources := state.overrun_ids()
	var newly: Array[String] = []
	var changes: Array = []
	var protected: Array[String] = []
	state.spread_calculations.clear()
	for id in state.shelters: incoming[id] = 0
	# Snapshot sources once: newly Overrun shelters first transmit NEXT round.
	for edge: EdgeState in state.edges.values():
		if not edge.isolated and sources.has(edge.from): incoming[edge.to] += 1
	for id in state.shelters:
		var shelter: ShelterState = state.shelters[id]
		var old := shelter.zombie_pressure
		var amount: int = 0 if shelter.shielded_this_round else incoming[id]
		if shelter.shielded_this_round: protected.append(id)
		shelter.zombie_pressure = mini(2, old + amount)
		state.spread_calculations.append({"target":id,"old":old,"incoming":incoming[id],"shielded":shelter.shielded_this_round,"new":shelter.zombie_pressure})
		if old != shelter.zombie_pressure:
			changes.append({"target":id,"old":old,"new":shelter.zombie_pressure})
			logger.record(state.round, "PRESSURE_CHANGED", id, old, shelter.zombie_pressure, {"incoming":incoming[id]})
			if shelter.is_overrun:
				newly.append(id)
				logger.record(state.round, "SHELTER_OVERRUN", id, false, true)
		if shelter.shielded_this_round:
			logger.record(state.round, "SHIELD_EXPIRED", id, true, false)
			shelter.shielded_this_round = false
	var alerts := resolve_monitor_alerts(changes)
	return {"round":state.round,"newly_overrun":newly,"shielded":protected,"monitor_alerts":alerts,
		"survivors":8 - state.overrun_ids().size(),"supply_remaining":state.total_supply()}

func resolve_monitor_alerts(changes: Array) -> Array[String]:
	var alerts: Array[String] = []
	for change in changes:
		var shelter: ShelterState = state.shelters[change.target]
		if not shelter.is_monitored: continue
		shelter.monitor_known_pressure = change.new
		var message := "Round %d · Monitor Alert: %s changed from Pressure %d → %d." % [state.round, change.target, change.old, change.new]
		alerts.append(message)
		state.monitor_alerts.append(message)
		state.investigation_log.append(message)
		logger.record(state.round, "MONITOR_ALERT", change.target, change.old, change.new)
	return alerts

func resolve_round() -> bool:
	if phase != Phase.ACTIONS or not draft.is_empty(): return false
	last_summary = resolve_zombie_spread()
	state.round_summaries.append(last_summary.duplicate(true))
	logger.record(state.round, "ROUND_COMPLETED", "", null, null, last_summary)
	phase = Phase.SUMMARY
	notices.clear()
	changed.emit()
	return true

func continue_after_summary() -> void:
	if phase != Phase.SUMMARY: return
	if state.round == scenario.rounds:
		phase = Phase.RESULTS
		logger.record(state.round, "SESSION_COMPLETED", "", null, null, {"surviving":8-state.overrun_ids().size(),"supply_remaining":state.total_supply(),"dev_used":dev_used})
	elif state.round == int(scenario.diagnostic_evidence.after_round):
		phase = Phase.DIAGNOSTIC
		logger.record(state.round, "DIAGNOSTIC_EVIDENCE_SHOWN", scenario.scenario_id, null, null, scenario.diagnostic_evidence)
	else:
		state.round += 1
		phase = Phase.DISCUSSION
	changed.emit()

func set_dev_mode(enabled: bool) -> void:
	dev_mode = enabled
	dev_used = dev_used or enabled
	logger.record(state.round, "DEV_MODE_CHANGED", "", not enabled, enabled)
	changed.emit()

func belief_change_count() -> int:
	var count := 0
	for index in mini(initial_beliefs.size(), updated_beliefs.size()):
		if initial_beliefs[index].suspected_source != updated_beliefs[index].suspected_source: count += 1
	return count

func export_dictionary() -> Dictionary:
	var initial: Array = []
	var updated: Array = []
	var verifications: Array = []
	for id in state.shelters:
		for record: Dictionary in state.shelters[id].verified_history:
			verifications.append({"target":id,"round":record.round,"pressure":record.pressure})
	for index in ANONYMOUS_ORDER:
		if index < initial_beliefs.size(): initial.append(initial_beliefs[index].to_dictionary())
		if index < updated_beliefs.size(): updated.append(updated_beliefs[index].to_dictionary())
	return {"schema_version":1,"scenario_id":scenario.scenario_id,"intervention":"NONE","dev_used":dev_used,
		"events":logger.to_array(),"initial_beliefs":initial,"post_evidence_beliefs":updated,
		"source_belief_changes":belief_change_count(),"final_state":state.to_dictionary(),
		"verification_results":verifications,"investigation_log":state.investigation_log,"monitor_alerts":state.monitor_alerts,
		"ground_truth":{"original_source":scenario.original_source,"initial_pressures":scenario.initial_pressures,"timeline":scenario.ground_truth_timeline}}
