extends "res://tests/test_ui.gd"

func run() -> void:
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_normal()
	app.session.configure_condition(GameManager.InterventionType.DIRECT_RECOMMENDATION)
	var id: String = app.mission_session.session_id
	for mission in 4:
		app.session._support_clock = func(): return support_time
		check(app.session.intervention_type == GameManager.InterventionType.DIRECT_RECOMMENDATION,"Assigned condition retained in UI mission")
		for round_number in 3:
			await click("Choose your")
			for player in 3:
				app.session.open_private_form()
				check(app.session.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access")),"Normal UI records actual structured answer")
			support_time += 120000
			await settle(8)
			check(app.session.phase == GameManager.Phase.INTERVENTION,"Normal UI shows intervention")
			check(not dispatch_ui_visible(),"No dispatch beside the intervention: mission %d round %d" % [mission+1,round_number+1])
			support_time += 15000
			await settle()
			await click("Proceed to actions")
			# Production resolution; skip visual time only in this automated UI navigation test.
			app.session.begin_resolution()
			app.session.apply_resolution(app.session.run_token)
			app.session.finish_resolution(app.session.run_token)
			await click("Results" if round_number == 2 else "Next round")
			check(not dispatch_ui_visible() and button_containing("Earlier") == null,"No dispatch history: mission %d round %d" % [mission+1,round_number+1])
		check(app.mission_session.records.size() == mission+1,"Results capture exactly one complete mission")
		app._select_shelter("A")
		await settle()
		if mission < 3: await click("Continue to next mission")
		else: check(button_containing("Continue to next mission") == null,"Final mission has no extra continuation")
		check(app.mission_session.session_id == id,"UI preserves session identity")
	var exported: Dictionary = app.mission_session.export_dictionary()
	check(exported.completed and exported.missions.size() == 4,"UI full session export complete")
	for mission in exported.missions:
		check(mission.private_surveys.size() == 9,"Every mission retains nine responses")
	app.queue_free()
	await settle()
	print("SESSION UI TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
