extends "res://tests/test_rules.gd"

func _run() -> void:
	for initial in [0,1]:
		var game := fresh()
		game.phase = GameManager.Phase.ACTIONS
		game.state.shelters.E.zombie_pressure = initial
		var shelter: ShelterState = game.state.shelters.E
		var before := SupportContext.build(game.state,[])
		check(before.shelters.E.known_pressure == -1,"Unobserved pressure remains hidden")
		check(game.dispatch_action("MONITOR","E",["H"]).ok,"Monitor delivery starts")
		check(not shelter.is_monitored and shelter.monitor_known_pressure == -1,"No monitor reading in transit")
		check(SupportContext.build(game.state,[]).shelters.E == before.shelters.E,"Both AI roles receive no reading in transit")
		check(game.state.observations.is_empty(),"No premature observation")
		check(game.complete_delivery(game.run_token),"Delivery completes")
		check(shelter.monitor_known_pressure == initial,"Arrival reveals pressure %d" % initial)
		check(shelter.zombie_pressure == initial and not shelter.shielded_this_round,"Monitor does not cure or protect")
		check(game.latest_observation.kind == "initial" and game.latest_observation.pressure == initial,"Initial reading is a Monitor observation")
		check(SupportContext.build(game.state,[]).shelters.E.known_pressure == initial,"Permitted AI context receives public reading")
		var stock := game.state.total_supply()
		check(not game.dispatch_action("MONITOR","E",["A"]).ok and game.state.total_supply() == stock,"Duplicate rejected without spending")
		check(not game.complete_delivery(game.run_token) and game.state.observations.size() == 1,"Duplicate completion cannot spend or record again")
		game.begin_resolution()
		game.apply_resolution(game.run_token)
		check(shelter.is_monitored,"Monitor persists")
		check(shelter.monitor_known_pressure == (0 if initial == 0 else 2),"Unchanged reading retained; changed reading updated")
		check(game.last_summary.monitor_observations.size() == (1 if initial == 0 else 2),"Round summary includes initial and changed observations")
		if initial == 1:
			check(game.state.monitor_alerts.size() == 1,"Later change alerts preserved")
			check(PresentationText.known_status(shelter) == "OVERRUN","Overrun dominates reading")
		var exported := game.export_dictionary()
		check(exported.monitor_rule == "monitor-current-1" and exported.observation_format == "observations-2","Records version mechanics and observations")
	var game := fresh()
	game.phase = GameManager.Phase.ACTIONS
	game.dispatch_action("MONITOR","E",["H"])
	game.state.shelters.E.zombie_pressure = 0 # Synthetic state change during transit.
	game.complete_delivery(game.run_token)
	check(game.state.shelters.E.monitor_known_pressure == 0,"Reading samples actual delivery-time state")
	check(act(game,"VERIFY","B",["A"]),"Verify still available")
	game.state.shelters.B.zombie_pressure = 1
	var context := SupportContext.build(game.state,[])
	check(context.shelters.B.known_pressure == -1 and context.shelters.B.verified_history[0].pressure == 0,"Verify remains dated; hidden changes do not become public")
	check(PresentationText.observation_text(game.state.observations[-1]).contains("dated snapshot"),"Verify explicitly dated")
	print("MONITOR CURRENT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
