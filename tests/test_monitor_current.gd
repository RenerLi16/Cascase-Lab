extends "res://tests/test_rules.gd"

# Filename retained for existing test commands; current rule is monitor-next-round-1.
func _run() -> void:
	for sandbox in [false,true]:
		for expected in [0,1,2]:
			var game := GameManager.new(null,GameManager.InterventionType.NONE,func(): return support_time,GameManager.RunPurpose.DEV_SANDBOX if sandbox else GameManager.RunPurpose.NORMAL)
			game.logger.capture_timing = false
			for shelter: ShelterState in game.state.shelters.values(): shelter.zombie_pressure = 0
			if expected == 1: game.state.shelters.F.zombie_pressure = 2
			if expected == 2: game.state.shelters.E.zombie_pressure = 1
			if sandbox: game.begin_sandbox_actions()
			else: survey_round(game)
			var shelter: ShelterState = game.state.shelters.E
			var hidden := shelter.zombie_pressure
			var before := SupportContext.build(game.state,[])
			check(game.dispatch_action("MONITOR","E",["A"]).ok,"Monitor delivery starts")
			check(not shelter.is_monitored and shelter.monitor_known_pressure == -1,"No reading in transit")
			check(SupportContext.build(game.state,[]).shelters.E == before.shelters.E,"Transit exposes no extra AI information")
			check(game.complete_delivery(game.run_token),"Delivery completes")
			check(shelter.is_monitored and shelter.monitor_activation_round == 2,"Installation schedules next round")
			check(shelter.monitor_known_pressure == -1 and game.latest_observation.is_empty() and game.state.observations.is_empty(),"Installation reveals no pressure")
			check(shelter.zombie_pressure == hidden and not shelter.shielded_this_round,"Monitor neither cures nor protects")
			check(SupportContext.build(game.state,[]).shelters.E.known_pressure == -1,"Pending Monitor exposes no AI pressure")
			check(PresentationText.monitor_status(shelter,3).contains("pending"),"UI identifies pending installation")
			var copied := game.state.copy()
			check(copied.shelters.E.monitor_activation_round == 2 and copied.shelters.E.monitor_known_pressure == -1,"State copy retains pending activation")
			var stock := game.state.total_supply()
			check(not game.dispatch_action("MONITOR","E",["A"]).ok and game.state.total_supply() == stock,"Duplicate pending installation costs nothing")
			check(not game.complete_delivery(game.run_token) and game.state.observations.is_empty(),"Duplicate completion adds no reading")
			resolve(game)
			check(shelter.monitor_known_pressure == -1 and game.state.monitor_alerts.is_empty() and game.last_summary.monitor_observations.is_empty(),"Installation-round resolution gives no Monitor observation")
			check(shelter.zombie_pressure == expected,"First reading will sample resolved state")
			game.next_round()
			if not sandbox:
				check(game.state.round == 1 and shelter.monitor_known_pressure == -1,"Post-outcome forms precede activation")
				preload("res://tests/post_form_fixture.gd").finish(game)
			check(game.phase == GameManager.Phase.OBSERVE and game.state.round == 2,"Next playable round starts")
			check(shelter.monitor_known_pressure == expected,"First reading reflects current next-round pressure")
			check(game.state.observations.size() == 1 and game.state.observations[0].round == 2 and game.state.observations[0].kind == "initial","Activation records exactly one next-round observation")
			check(SupportContext.build(game.state,[]).shelters.E.known_pressure == expected,"Public AI context receives active reading")
			check(PresentationText.observation_text(game.state.observations[0]).contains("activated"),"Initial observation describes activation")
			game.next_round()
			check(game.state.observations.size() == 1,"Repeated advance cannot activate twice")
			if sandbox: game.begin_sandbox_actions()
			else: survey_round(game)
			resolve(game)
			check(shelter.monitor_known_pressure == (2 if expected == 1 else expected),"Active reading updates or persists")
			check(game.state.monitor_alerts.size() == (1 if expected == 1 else 0),"Only active changes produce alerts")
			check(game.last_summary.monitor_observations.size() == (2 if expected == 1 else 1),"Summary contains that round's initial reading and changes")
			var exported := game.export_dictionary()
			check(exported.schema_version == 9 and exported.monitor_rule == "monitor-next-round-1" and exported.observation_format == "observations-3","Export identifies new mechanics")
			check(exported.final_state.shelters.E.monitor_activation_round == 2,"Export retains activation round")
	# Final-round installation is legal, explicitly unhelpful, and never activates.
	var game := GameManager.new(null,GameManager.InterventionType.NONE,Callable(),GameManager.RunPurpose.DEV_SANDBOX)
	for shelter: ShelterState in game.state.shelters.values(): shelter.zombie_pressure = 0
	for _round in 2:
		game.begin_sandbox_actions()
		resolve(game)
		game.next_round()
	game.begin_sandbox_actions()
	check(act(game,"MONITOR","E",["H"]),"Final-round installation remains legal")
	check(PresentationText.monitor_status(game.state.shelters.E,3).contains("no round"),"Final-round pending label explains no future reading")
	check(act(game,"VERIFY","B",["A"]),"Verify gives immediate information even in final round")
	check(game.latest_observation.pressure == 0 and game.latest_observation.round == 3,"Verify still samples on arrival")
	game.state.shelters.B.zombie_pressure = 1
	var context := SupportContext.build(game.state,[])
	check(context.shelters.B.known_pressure == -1 and context.shelters.B.verified_history[0].pressure == 0,"Verify remains dated and does not reveal later hidden state")
	resolve(game)
	game.next_round()
	check(game.phase == GameManager.Phase.RESULTS and game.state.shelters.E.monitor_known_pressure == -1,"Results do not create an extra activation round")
	check(game.state.observations.filter(func(note): return note.type == "MONITOR").is_empty(),"Final-round Monitor never produces observations")
	print("MONITOR NEXT ROUND: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
