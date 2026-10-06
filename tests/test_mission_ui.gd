extends "res://tests/test_presentation.gd"

func run() -> void:
	capture_dir = "/private/tmp/cascade-mission-ui"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		await settle(8)
		check(app.session == null,"Menu does not create active game")
		check(button_containing("Play") != null and button_containing("Dev Mode") != null,"Menu exposes Play and Dev Mode")
		check(button_containing("Dev Mode").global_position.y > button_containing("Play").get_global_rect().end.y,"Dev Mode directly below Play")
		await snapshot(str(viewport_size.x)+"-menu")
		check_layout("menu")
		await click("Dev Mode")
		check_layout("picker")
		await snapshot(str(viewport_size.x)+"-picker")
		for entry in ScenarioData.registry().scenarios:
			await click("Start · " + entry.title)
			await settle(8)
			check(app.session.is_sandbox() and not app.session.dev_mode,"Sandbox skips forms with reveal off")
			check(app.session.state.total_supply() == 6 and app.session.state.round == 1,"Fresh original stock and round")
			check_layout(entry.id+"-observe")
			check(not dispatch_ui_visible(),"No field dispatch panel: "+entry.id)
			await snapshot(str(viewport_size.x)+"-"+entry.id)
			for id in app.session.state.shelters:
				check(app.board.hit_test(app.board.positions[id]) == id,"Actual map position clickable: "+id)
				if entry.id != "riverside_01_v2":
					check(app.board.world_building(id) == CityMapProfiles.building(app.session.scenario,id),"Artwork building registration rendered")
			for id in app.session.state.edges:
				if entry.id != "riverside_01_v2": check(app.board.visual_road(id) == CityMapProfiles.road(app.session.scenario,id),"Artwork road registration rendered")
			if DisplayServer.get_name() != "headless":
				var before := await public_pixels()
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1 - shelter.zombie_pressure
				var after := await public_pixels()
				check(before == after,"Unrevealed pressures do not affect public map: "+entry.id)
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1 - shelter.zombie_pressure
			await click("Begin actions")
			var depot: String = app.session.scenario.supply_depots[0]
			await map_click(depot)
			await create_timer(0.65).timeout
			check_layout("focused-"+entry.id)
			await snapshot(str(viewport_size.x)+"-focus-"+entry.id)
			await dispatch("VERIFY",depot,[depot])
			app._clear_selection()
			await create_timer(0.65).timeout
			for round_number in 3:
				if round_number > 0: await click("Begin actions")
				await click("End round")
				await click("Resolve")
				await create_timer(1.7).timeout
				check(app.session.phase == GameManager.Phase.ROUND_COMPLETE,"Sandbox reaches next round without forms")
				await click("Results" if round_number == 2 else "Next round")
				check(not dispatch_ui_visible() and button_containing("Earlier") == null,"No dispatch or dispatch history after round %d: %s" % [round_number+1,entry.id])
			check(app.session.phase == GameManager.Phase.RESULTS,"Sandbox completes all three rounds")
			check(app.session.private_surveys.is_empty() and app.session.support_message.is_empty(),"No survey or AI artifacts")
			check_layout("results-"+entry.id)
			check(app.board.get_global_rect().end.y < app.footer.global_position.y,"Results footer is below map")
			await snapshot(str(viewport_size.x)+"-results-"+entry.id)
			app._select_shelter("A")
			await settle()
			check(button_containing("Replay") != null,"Results controls survive inspection")
			var record: Dictionary = app.mission_session.export_dictionary()
			check(record.run_purpose == "dev" and not record.research_eligible and record.missions.size() == 1,"Debug export stays separate")
			await click("Replay")
			await click("Restart scenario")
			check(app.session.is_sandbox() and app.session.state.total_supply() == 6,"Replay preserves dev purpose")
			await click("Menu")
			await click("Choose another scenario")
			await click("Leave mission")
		await click("Back")
		await click("Play")
		check(app.practice != null and app.session == null,"Play opens separate practice")
		app._start_normal()
		check(not app.session.is_sandbox() and button_containing("Begin actions") == null,"Normal Play exposes only survey route")
		check(not app.session.begin_sandbox_actions(),"Normal UI cannot bypass domain guard")
		app.queue_free()
		await settle()
	# Switch while asynchronous work is pending; a new manager must stay untouched.
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	for stage in ["delivery","resolution","support"]:
		app._start_dev("riverside_01_v2")
		app.session.begin_sandbox_actions()
		var funding: Array[String] = ["A"]
		if stage == "delivery": app.session.dispatch_action("VERIFY","A",funding)
		elif stage == "resolution": app.session.begin_resolution()
		else:
			app._start_normal()
			app.session._support_clock = func(): return support_time
			app.session.start_private()
			for player in 3:
				app.session.open_private_form()
				app.session.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access"))
			support_time += 120000
			app.session.begin_support()
		await settle(1)
		app._start_dev("crossfire_04_v1")
		await create_timer(2.0).timeout
		check(app.session.state.total_supply() == 6 and app.session.state.round == 1 and app.session.phase == GameManager.Phase.OBSERVE,"Stale "+stage+" callback cannot mutate new scenario")
		check(app.selected_shelter == "" and app.selected_edge == "" and app.session.support_message.is_empty(),"Switch clears selections and messages")
	app._show_main_menu()
	ProjectSettings.set_setting("cascade/development_access",false)
	app._show_main_menu()
	check(button_containing("Dev Mode") == null,"Participant configuration hides development entry")
	app._start_dev("riverside_01_v2")
	check(app.session == null,"Participant configuration disables dev entry point")
	ProjectSettings.set_setting("cascade/development_access",true)
	app.queue_free()
	await settle()
	print("MISSION UI TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
