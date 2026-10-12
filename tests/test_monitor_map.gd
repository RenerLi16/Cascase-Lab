extends "res://tests/test_landscape_labels.gd"

# Wait for two identical rendered frames before comparing different hidden states.
# Newly created fonts/controls can settle on different frames at startup.
func stable_pixels() -> PackedByteArray:
	var previous := await public_pixels()
	for attempt in 8:
		var current := await public_pixels()
		if previous == current: return current
		previous = current
	check(false,"Public view settles with reduced motion")
	return previous

func monitor_labels(tag: String) -> void:
	var board: NetworkView = app.board
	board._refresh_geometry()
	for id in board.title_rects:
		var title: Rect2 = board.title_rects[id]
		var block := Rect2(title.position,Vector2(title.size.x,NetworkView.NAME_BLOCK))
		check(not board._annotation_hides_road(block),tag+" complete pressure label avoids roads and bridges "+id)
		for other in board.positions:
			check(not block.intersects(board.tower_screen_rect(other)),tag+" label avoids tower "+other)
		for other in board.title_rects:
			if other != id:
				var rect: Rect2 = board.title_rects[other]
				check(not block.intersects(Rect2(rect.position,Vector2(rect.size.x,NetworkView.NAME_BLOCK))),tag+" neighboring labels do not overlap")

func run() -> void:
	UIkit.reduced_motion = true
	for viewport in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport
		root.size = viewport
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		for entry in ScenarioData.registry().scenarios:
			for chinese in [false,true]:
				FirstPlayText.chinese = chinese
				app._start_dev(entry.id)
				app.session.set_dev_mode(false)
				app.session.begin_sandbox_actions()
				if chinese:
					for id in app.session.state.shelters: app.session.state.shelters[id].display_name = CHINESE_NAMES[entry.id][id.unicode_at(0)-65]
				app._select_shelter("E")
				await settle(8)
				if DisplayServer.get_name() != "headless":
					var before := await stable_pixels()
					var before_image := root.get_texture().get_image()
					for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
					app._refresh_inspector()
					var after := await stable_pixels()
					check(before == after,"Hidden pressure cannot affect map, icons, labels or controls: "+entry.id+str(viewport)+str(chinese))
					if before != after:
						before_image.save_png("/tmp/privacy-before.png")
						root.get_texture().get_image().save_png("/tmp/privacy-after.png")
					for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
				for id in app.session.state.shelters:
					app.session.state.shelters[id].is_monitored = true
					app.session.state.shelters[id].monitor_known_pressure = app.session.state.shelters[id].zombie_pressure
				app.board.annotation_key = ""
				await settle(3)
				monitor_labels(str(viewport)+entry.id)
				app._clear_selection()
				await settle(3)
				monitor_labels(str(viewport)+entry.id+" overview")
		app.queue_free()
		await settle()
	FirstPlayText.chinese = false
	print("MONITOR MAP: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
