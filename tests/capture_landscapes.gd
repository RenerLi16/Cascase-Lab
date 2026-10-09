extends "res://tests/test_landscape_labels.gd"

func run() -> void:
	var phase := OS.get_environment("LANDSCAPE_PHASE")
	if phase == "": phase = "after"
	capture_dir = ProjectSettings.globalize_path("res://build/landscape/"+phase)
	DirAccess.make_dir_recursive_absolute(capture_dir)
	UIkit.reduced_motion = true
	for viewport in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport
		root.size = viewport
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		for entry in ScenarioData.registry().scenarios:
			app._start_dev(entry.id)
			app.session.set_dev_mode(false)
			await settle(6)
			var tag: String = str(viewport.x)+"-"+entry.id
			await snapshot(tag+"-overview-en")
			for edge in app.session.scenario.bridges:
				var board: NetworkView = app.board
				var at := board._point_on_path(board.visual_road(edge),board.closure_fraction(edge))
				board._move_camera(at,2.5,false)
				await snapshot(tag+"-bridge-"+edge)
			if phase == "after":
				for id in app.session.scenario.node_positions:
					app._select_shelter(id)
					await snapshot(tag+"-inspection-"+id)
				app._clear_selection()
				for corner in [Vector2(-1000,-1000),Vector2(2000,-1000),Vector2(2000,1700),Vector2(-1000,1700)]:
					app.board._move_camera(corner,1.6,false)
					await snapshot(tag+"-pan-"+str(corner.x)+"-"+str(corner.y))
				app.board.center_map(false)
				var before := await public_pixels()
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
				check(before == await public_pixels(),"Hidden pressures do not alter public pixels: "+tag)
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
				app.session.begin_sandbox_actions()
				app._request_action("ISOLATE",app.session.scenario.bridges[0])
				await snapshot(tag+"-sources")
				await select_delivery_sources()
				await snapshot(tag+"-routes")
				await click("Confirm delivery")
				await wait_delivery()
				app._clear_selection()
				app.board.center_map(false)
				await snapshot(tag+"-closed")
				var edge: String = app.session.scenario.bridges[0]
				app.board._move_camera(app.board._point_on_path(app.board.visual_road(edge),app.board.closure_fraction(edge)),2.5,false)
				await snapshot(tag+"-closed-close")
			app.board.center_map(false)
			FirstPlayText.chinese = true
			app._start_dev(entry.id)
			app.session.set_dev_mode(false)
			for id in app.session.state.shelters:
				app.session.state.shelters[id].display_name = CHINESE_NAMES[entry.id][id.unicode_at(0)-65]
			app.board.annotation_key = ""
			await snapshot(tag+"-overview-zh-fixture")
			FirstPlayText.chinese = false
		app.queue_free()
		await settle()
	print("LANDSCAPE CAPTURE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
