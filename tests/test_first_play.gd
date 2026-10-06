extends "res://tests/test_presentation.gd"

func run() -> void:
	capture_dir = OS.get_environment("CAPTURE_DIR") if OS.get_environment("CAPTURE_DIR") != "" else "/tmp/cascade-first-play/after"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var sync := root.get_node("StudySync")
	var saved_before: Array = sync.sessions.duplicate(true)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		for chinese in [false,true]:
			FirstPlayText.chinese = chinese
			var tag := "%d-%s" % [viewport_size.x,"zh" if chinese else "en"]
			app = load("res://scenes/Main.tscn").instantiate()
			root.add_child(app)
			await snapshot(tag+"-opening")
			await click("Play")
			check(app.session == null and app.mission_session == null,"Practice has no measured session")
			var practice: PracticeView = app.practice
			check(not ScenarioData.registry().development_default_order.has(practice.scenario.scenario_id),"Demo is outside research registry")
			check(practice.state.total_supply() == 6,"Practice starts fresh")
			await snapshot(tag+"-practice-start")
			check_layout(tag+"-practice-start")
			practice.select_shelter("E")
			await create_timer(0.65).timeout
			await snapshot(tag+"-practice-selected")
			practice.deliver("VERIFY","E")
			check(practice.state.total_supply() == 5,"Reservation visibly deducts supply")
			await create_timer(0.4).timeout
			await snapshot(tag+"-practice-delivery")
			await create_timer(1.8).timeout
			check(practice.step == 1 and practice.state.observations.size() == 1,"Delivery produces only purchased dated observation")
			practice.select_road("C-E")
			await snapshot(tag+"-practice-road")
			check_layout(tag+"-practice-road")
			await practice.deliver("ISOLATE","C-E")
			check(practice.state.total_supply() == 3 and practice.state.edges["C-E"].isolated,"Two deliveries close road through shared mechanics")
			check(not practice.actions.supply.stocked_reachability().has("E"),"Closure changes available supply routes")
			check(practice.step == 2 and sync.sessions == saved_before,"Practice stays outside saved research records")
			await snapshot(tag+"-practice-complete")
			check_layout(tag+"-practice-complete")
			practice.reset()
			check(practice.state.total_supply() == 6 and practice.state.actions.is_empty() and practice.state.observations.is_empty(),"Reset discards stock, actions and observations")
			check(not practice.state.edges["C-E"].isolated and practice.step == 0,"Replay reopens roads and resets instructions")
			# Reset while a delivery is pending cannot write into the new attempt.
			practice.deliver("VERIFY","C")
			practice.reset()
			await create_timer(2.2).timeout
			check(practice.state.total_supply() == 6 and practice.step == 0,"Stale practice animation cannot mutate reset")
			await practice.deliver("VERIFY","C")
			await practice.deliver("ISOLATE","C-E")
			await click("开始正式任务" if chinese else "Start measured session")
			check(app.practice == null and app.practice_completed_version == PracticeView.VERSION,"Completion version is separate from mission")
			check(app.session.state.total_supply() == 6 and app.session.state.round == 1,"Measured session starts with fresh stock and round")
			check(app.session.state.actions.is_empty() and app.session.state.observations.is_empty() and app.session.private_surveys.is_empty(),"No practice data enters measured session")
			check(app.mission_session.records.is_empty() and app.session.support_message.is_empty(),"Fresh mission records and AI response")
			check(not JSON.stringify(app.mission_session.export_dictionary()).contains("practice_demo"),"Measured export contains no demo record")
			for condition in 3:
				check(app.session.configure_condition(condition),"Assigned condition is available after common practice")
				check(app.session.state.total_supply() == 6,"Condition configuration retains fresh mission")
			app._show_main_menu()
			check(button_containing("重玩练习" if chinese else "Replay practice") != null,"Replay remains available")
			app.queue_free()
			await settle()
	FirstPlayText.chinese = false
	# Participant gate remains closed without explicit protocol approval.
	ProjectSettings.set_setting("cascade/development_access",false)
	ProjectSettings.set_setting("cascade/practice_approved",false)
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_practice()
	check(app.practice == null,"Practice off in participant configuration by default")
	ProjectSettings.set_setting("cascade/practice_approved",true)
	ProjectSettings.set_setting("cascade/require_access_code",true)
	sync.enabled = true
	sync.access_code = ""
	app._start_practice()
	check(app.practice == null,"Practice respects existing access gate")
	app._start_normal()
	check(app.session == null,"Measured entry still respects existing access gate")
	sync.enabled = false
	ProjectSettings.set_setting("cascade/require_access_code",false)
	ProjectSettings.set_setting("cascade/development_access",true)
	ProjectSettings.set_setting("cascade/practice_approved",false)
	# Width, hit testing, state styling, alignment, and public-only rendering.
	for entry in ScenarioData.registry().scenarios:
		app._start_dev(entry.id)
		await settle(8)
		for zoom_value in [1.0,2.6]:
			app.board.zoom = zoom_value
			app.board._refresh_geometry()
			check(app.board.road_core_width() >= 4 and app.board.road_core_width() <= 6,"Bounded thick road core")
			for id in app.session.state.edges:
				check(app.board.visual_road(id) == CityMapProfiles.road(app.session.scenario,id),"Road alignment unchanged: "+id)
				var path: PackedVector2Array = app.board.road_geometry[id]
				var mid: Vector2 = app.board._point_on_path(path,0.5)
				var tangent: Vector2 = (app.board._point_on_path(path,0.51)-mid).normalized()
				check(app.board.hit_test(mid+tangent.orthogonal()*4) == id,"Road visible width is selectable: "+id)
		for id in app.session.state.shelters:
			check(app.board.shelter_ink(id) == UIkit.SECONDARY,"Unknown ink is neutral")
		app.board.zoom = 1.0
		if DisplayServer.get_name() != "headless":
			var before := await public_pixels()
			for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1 - shelter.zombie_pressure
			var after := await public_pixels()
			check(before == after,"Hidden P0/P1 changes never alter map feedback")
		await snapshot(entry.id+"-overview")
	app.queue_free()
	await settle()
	print("FIRST PLAY TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
