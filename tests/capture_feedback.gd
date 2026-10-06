extends "res://tests/test_presentation.gd"

func run() -> void:
	capture_dir = "/tmp/cascade-first-play/after"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		app._start_dev("riverside_01_v2")
		await snapshot("roads-overview-%d" % viewport_size.x)
		app._select_shelter("E")
		await create_timer(0.65).timeout
		await snapshot("roads-closeup-%d" % viewport_size.x)
		app._clear_selection()
		await create_timer(0.65).timeout
		app.session.begin_sandbox_actions()
		await dispatch("MONITOR","E",["A"])
		await dispatch("ISOLATE","A-B",["A","A"])
		app.session.begin_resolution()
		await create_timer(1.7).timeout
		await snapshot("recap-%d" % viewport_size.x)
		check_layout("public-recap")
		app.session.next_round()
		app.session.begin_sandbox_actions()
		await dispatch("SHIELD","F",["H"])
		# Only public sources, roads and installed shields drive transmission visuals.
		var movements: Array = app.session.preview_resolution().movements
		app.board.animation_paths.clear()
		for movement in movements: app.board.animation_paths.append(app.board.world_path_for_nodes([movement.from,movement.to]))
		app.board.animation_kind = "outbreak"
		app.board.animation_progress = 0.85
		await snapshot("blocked-%d" % viewport_size.x)
		if DisplayServer.get_name() != "headless":
			var before := await public_pixels()
			app.session.state.shelters.F.zombie_pressure = 1
			check(movements == app.session.preview_resolution().movements,"Public transmission paths independent of concealed target pressure")
			check(before == await public_pixels(),"Blocked animation independent of concealed target pressure")
			app.session.state.shelters.F.zombie_pressure = 0
		var preview: Dictionary = app.session.preview_resolution()
		for calculation in preview.calculations:
			if calculation.target == "F": check(calculation.incoming > 0 and calculation.new == calculation.old,"Public blocked response matches an actual blocked incoming transmission")
		app.board.animation_kind = ""
		app.session.begin_resolution()
		await create_timer(1.7).timeout
		await snapshot("overrun-%d" % viewport_size.x)
		app.queue_free()
		await settle()
	print("PUBLIC FEEDBACK TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
