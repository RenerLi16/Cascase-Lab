extends "res://tests/test_city_art.gd"

# Visual regression + domain integration. All fixtures use the offline test
# outbox; captures go to a new directory, never the historical screenshot set.
func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://build/medieval-review")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	UIkit.reduced_motion = true
	var unique: Dictionary = {}
	for variant in 8:
		var pixels := WoodlandArt.tower(variant,false,true,0,false).get_image().get_data()
		unique[hash(pixels)] = true
		check(pixels != WoodlandArt.tower(variant,true,true,0,false).get_image().get_data(),"Inspection adds real pixel detail")
	check(unique.size() == 8,"Eight distinct tower designs")
	var glow := WoodlandArt.light_texture().get_image()
	check(glow.get_pixel(64,64).a > glow.get_pixel(85,64).a and glow.get_pixel(85,64).a > glow.get_pixel(110,64).a and glow.get_pixel(127,64).a == 0,"Local light falls gradually to zero")
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		for entry in ScenarioData.registry().scenarios:
			app._start_dev(entry.id)
			app.session.set_dev_mode(false)
			app.session.begin_sandbox_actions()
			await settle(6)
			var tag := str(viewport_size.x)+"-"+str(entry.id)
			geometry_checks()
			check_layout(tag)
			for rect: Rect2 in app.board.title_rects.values():
				check(rect.position.y >= 178,"Name remains below floating header")
				check(not app.board._annotation_hides_road(rect),"Names leave roads readable")
			await snapshot(tag+"-overview")
			if DisplayServer.get_name() != "headless":
				var before := await public_pixels()
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
				check(before == await public_pixels(),"Every public pixel ignores hidden exposure")
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
			for id in ["A","C","G"]:
				app._select_shelter(id)
				await settle()
				var tower: Rect2 = app.board.tower_screen_rect(id)
				check(tower.end.x < app.inspector.global_position.x,"Inspection panel leaves tower visible")
				check(app.board.zoom == 2.0,"Reduced-motion inspection is immediate")
				check_layout(tag+"-"+id)
				if entry.id == "riverside_01_v2": await snapshot(tag+"-tower-"+id)
			app._clear_selection()
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			for i in 40: app.board._gui_input(wheel)
			check(app.board.zoom <= 1.4,"Wheel is bounded in overview")
			app.board.camera_center = Vector2(90000,-90000)
			app.board._update_camera()
			check(app.board.camera_center.x <= app.session.scenario.world_size[0]+70,"Pan remains bounded")
			app.board.center_map(false)
			# Actual delivery and isolation still use the existing route and action manager.
			var target := "H" if entry.id == "riverside_01_v2" else "G"
			var assignment: Array[String] = ["A"]
			var result: Dictionary = app.session.dispatch_action("VERIFY",target,assignment)
			check(result.ok,"Actual routed delivery accepted")
			await create_timer(0.3).timeout
			check(app.board.animation_paths[0] == app.board.world_path_for_nodes(app.session.pending_action.deliveries[0].path),"Courier follows authoritative route")
			await wait_delivery()
			var edge := "E-F" if entry.id == "riverside_01_v2" else "D-E"
			await map_click(edge,true)
			await click("ISOLATE")
			await click("Confirm delivery")
			check(not app.session.state.edges[edge].isolated,"Road stays open until arrival")
			await wait_delivery()
			check(app.session.state.edges[edge].isolated,"Closure completes after delivery")
			app._clear_selection()
			await snapshot(tag+"-closed")
		app.queue_free()
		await settle()
	# Capture the real practice controller in both language modes.
	for chinese in [false,true]:
		FirstPlayText.chinese = chinese
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		app._begin_play()
		await snapshot("1200-practice-"+("zh" if chinese else "en"))
		check_layout("practice")
		app.practice.select_shelter("E")
		await snapshot("1200-practice-inspection-"+("zh" if chinese else "en"))
		check_layout("practice inspection")
		app.queue_free()
		await settle()
	FirstPlayText.chinese = false
	if DisplayServer.get_name() != "headless": await record_demo()
	print("MEDIEVAL TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func record_demo() -> void:
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_dev("riverside_01_v2")
	app.session.set_dev_mode(false)
	app.session.begin_sandbox_actions()
	UIkit.reduced_motion = false
	await settle(8)
	DirAccess.make_dir_recursive_absolute(capture_dir+"/frames")
	for frame in 64:
		if frame == 8: app._select_shelter("C")
		if frame == 25:
			app._clear_selection()
			app.board.center_map(false)
			var assignment: Array[String] = ["A"]
			app.session.dispatch_action("VERIFY","H",assignment)
		if frame == 52:
			app._select_shelter("G")
		await create_timer(0.1).timeout
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(capture_dir+"/frames/%03d.png" % frame)
	app.queue_free()
	await settle()
