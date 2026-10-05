extends SceneTree

var checks := 0
var failures := 0
var now := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func resolve(game: GameManager) -> void:
	check(game.begin_resolution(),"Begin once")
	check(not game.begin_resolution(),"No double resolution")
	check(game.apply_resolution(game.run_token),"Apply once")
	check(not game.apply_resolution(game.run_token),"No double application")
	check(game.finish_resolution(game.run_token),"Finish once")
	game.next_round()

func normal_actions(game: GameManager) -> void:
	game._support_clock = func(): return now
	check(not game.begin_sandbox_actions(),"Normal mode rejects survey bypass")
	check(not game.begin_resolution(),"Normal observe rejects resolution")
	game.start_private()
	for player in 3:
		game.open_private_form()
		check(game.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access")),"Required response")
	check(not game.begin_support(),"Cannot skip 120 seconds")
	now += 119999
	check(not game.begin_support(),"Cannot skip final millisecond")
	now += 1
	check(game.begin_support(),"Discussion completes")
	check(not game.proceed_to_actions(),"Unseen support cannot continue")
	game.mark_support_shown()
	now += 14999
	check(not game.proceed_to_actions(),"Reading gate enforced")
	now += 1
	check(game.proceed_to_actions(),"Actions unlocked")

func _initialize() -> void:
	var registry := ScenarioData.registry()
	check(registry.scenarios.size() == 4,"Four explicit registry entries")
	var ids: Array = []
	var exposures := [["E"],["D"],["F"],["B","F"]]
	for index in registry.scenarios.size():
		var entry: Dictionary = registry.scenarios[index]
		check(not ids.has(entry.id),"Unique registry ID")
		ids.append(entry.id)
		var scenario := ScenarioData.load_by_id(entry.id)
		check(scenario != null,"Loads by registered ID")
		check(scenario.initial_exposure_ids() == exposures[index],"Expected exposures")
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
		for key in ScenarioData.FIELDS:
			check(scenario.get(key) == source[key],"Exact imported field " + key)
		var sandbox := GameManager.new(scenario,GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
		sandbox.set_dev_mode(true)
		sandbox.set_dev_mode(false)
		sandbox.reset()
		check(sandbox.is_sandbox() and sandbox.dev_used and not sandbox.dev_mode,"Purpose survives reset; reveal defaults off")
		for round_number in 3:
			check(not sandbox.logger.to_array().any(func(e): return e.type == "PUBLIC_INTEL_SHOWN"),"Sandbox rounds publish no narrative report")
			sandbox.start_private()
			check(sandbox.phase == GameManager.Phase.OBSERVE,"Sandbox cannot start forms")
			check(sandbox.begin_sandbox_actions(),"Sandbox begins actions")
			check(not sandbox.begin_support(),"Sandbox disables support")
			resolve(sandbox)
		var record := sandbox.export_dictionary()
		check(record.run_purpose == "dev" and record.dev_used and record.surveys_skipped and not record.research_eligible,"All dev flags in export")
		check(record.private_surveys.is_empty() and sandbox.private_surveys.is_empty(),"No fabricated responses")
		check(sandbox.support_message.is_empty() and not sandbox.support_shown,"No generated support")
		check(not sandbox.research_submission().ok,"Submission boundary rejects dev")
		check(record.ground_truth.initial_exposure_ids == exposures[index],"Canonical debug source list")
		for event in record.events:
			check(event.type not in ["SUPPORT_SHOWN","PRIVATE_SURVEY_SUBMITTED"],"No research interactions recorded")
	check(ScenarioData.load_by_id("missing") == null and not ScenarioData.last_error.is_empty(),"Unknown ID returns useful error")
	check(ScenarioData.load_path("res://scenarios/missing.json") == null and not ScenarioData.last_error.is_empty(),"Missing path returns useful error")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry.scenarios[0].path))
	for mutation in ["pressure","duplicate","disconnected","coordinate","depot","rounds","missing"]:
		var bad := raw.duplicate(true)
		match mutation:
			"pressure": bad.initial_pressures.A = 2
			"duplicate": bad.edges.append(["B","A"])
			"disconnected": bad.edges = [["A","B"]]
			"coordinate": bad.node_positions.A = [9999,4]
			"depot": bad.supply_depots = ["A","A"]
			"rounds": bad.rounds = 2
			"missing": bad.erase("shelter_names")
		check(ScenarioData.from_dictionary(bad) == null and not ScenarioData.last_error.is_empty(),"Reject malformed " + mutation)
	# Older scenario files may still carry retired dispatches; the loader ignores them explicitly.
	var legacy := raw.duplicate(true)
	legacy.public_intel = [{"round":1,"time":"LEGACY_TIME_CANARY","text":"LEGACY_DISPATCH_CANARY"}]
	var legacy_scenario := ScenarioData.from_dictionary(legacy)
	check(legacy_scenario != null and legacy_scenario.get("public_intel") == null,"Deprecated report field is ignored, never loaded")
	var legacy_game := GameManager.new(legacy_scenario,GameManager.InterventionType.DIRECT_RECOMMENDATION,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	for round_number in 3:
		legacy_game.begin_sandbox_actions()
		resolve(legacy_game)
	check(legacy_game.phase == GameManager.Phase.RESULTS and not JSON.stringify(legacy_game.export_dictionary()).contains("CANARY"),"Legacy dispatch text never enters play, events, or export")
	var batch := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.CONSTRUCTIVE_DISSENT)
	var session_id := batch.session_id
	for index in 4:
		var game := batch.current
		check(game.state.round == 1 and game.state.total_supply() == 6 and game.state.observations.is_empty(),"Fresh mission state")
		check(game.intervention_type == GameManager.InterventionType.CONSTRUCTIVE_DISSENT,"Fixed session condition")
		if index > 0: check(not game.configure_condition(0),"No condition switch between missions")
		for round_number in 3:
			normal_actions(game)
			resolve(game)
		check(batch.capture_result(),"Capture complete mission")
		check(batch.records.size() == index+1,"Exactly one record per mission")
		check(batch.capture_result() and batch.records.size() == index+1,"Capture is idempotent")
		if index < 3: check(batch.advance(),"Advance to next mission")
	check(batch.is_complete() and not batch.advance(),"Four missions complete session")
	var exported := batch.export_dictionary()
	check(exported.session_id == session_id and exported.missions.size() == 4,"Stable session with four records")
	check(not exported.research_eligible and exported.order_source == "development_default_not_randomized","Default is explicitly unapproved")
	for index in 4:
		check(exported.missions[index].scenario_id == ids[index] and exported.missions[index].private_surveys.size() == 9,"Separate scenario survey records")
	var reverse := ids.duplicate()
	reverse.reverse()
	var configured := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE,reverse)
	check(configured.order == reverse and configured.order_source == "configured","Configured order honored")
	var invalid := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE,[ids[0]])
	check(invalid.current == null and not invalid.error.is_empty(),"Reject incomplete normal order")
	var abandoned := MissionSession.new()
	check(not abandoned.capture_result() and not abandoned.advance() and abandoned.records.is_empty(),"Abandoned mission cannot be appended as complete")
	var old := GameManager.new(null,GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	old.begin_sandbox_actions()
	check(old.dispatch_action("VERIFY","A",["A"]).ok,"Dispatch test delivery")
	var token := old.run_token
	var fresh := GameManager.new(null,GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	fresh.begin_sandbox_actions()
	fresh.dispatch_action("VERIFY","A",["A"])
	check(token != fresh.run_token and not fresh.complete_delivery(token),"Tokens cannot collide across managers")
	old.reset()
	check(not old.complete_delivery(token),"Restart rejects old delivery")
	check(fresh.complete_delivery(fresh.run_token) and not fresh.complete_delivery(fresh.run_token),"Delivery cannot apply twice")
	# Crossfire additive pressure and shields retain the original physics.
	var cross := GameManager.new(ScenarioData.load_by_id(ids[3]),GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	cross.begin_sandbox_actions()
	resolve(cross)
	var calculations: Array = cross.preview_resolution().calculations
	for calculation in calculations:
		if calculation.target in ["D","E"]: check(calculation.incoming == 2 and calculation.new == 2,"Two fronts overwhelm junctions")
	cross.state.shelters.D.shielded_this_round = true
	cross.state.shelters.E.shielded_this_round = true
	cross.state.shelters.E.zombie_pressure = 1
	for calculation in cross.preview_resolution().calculations:
		if calculation.target == "D": check(calculation.new == 0,"Shield blocks both inputs")
		if calculation.target == "E": check(calculation.new == 2,"Shield cannot stop existing exposure")
	print("MISSION TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
