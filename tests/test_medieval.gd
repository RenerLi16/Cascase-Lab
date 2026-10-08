extends "res://tests/test_city_art.gd"

# Visual regression + domain integration. All fixtures use the offline test
# outbox; captures go to a new directory, never the historical screenshot set.
func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://build/medieval-refinement/after")
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
			check(app.board.title_rects.size() == 8,"Every overview tower has its public label")
			check_layout(tag)
			for rect: Rect2 in app.board.title_rects.values():
				check(rect.position.y >= 152,"Name remains below floating header")
				check(not app.board._annotation_hides_road(Rect2(rect.position,Vector2(rect.size.x,NetworkView.NAME_BLOCK))),"Name and status leave roads readable")
			await snapshot(tag+"-overview")
			app.board.debug_anchors = true
			app.board.queue_redraw()
			await snapshot(tag+"-anchors")
			app.board.debug_anchors = false
			app.board.queue_redraw()
			if DisplayServer.get_name() != "headless":
				var before := await public_pixels()
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
				check(before == await public_pixels(),"Every public pixel ignores hidden exposure")
				for shelter in app.session.state.shelters.values(): shelter.zombie_pressure = 1-shelter.zombie_pressure
			for id in app.session.scenario.node_positions:
				app._select_shelter(id)
				await settle()
				var tower: Rect2 = app.board.tower_screen_rect(id)
				check(tower.end.x < app.inspector.global_position.x,"Inspection panel leaves tower visible")
				check(app.board.zoom == 2.0,"Reduced-motion inspection is immediate")
				check_layout(tag+"-"+id)
				await snapshot(tag+"-tower-"+id)
				check(tower.position.y > 152 and tower.end.y < viewport_size.y-104,"Inspected tower clears top and bottom UI")
				geometry_checks()
				check(app.board.title_rects.has(id),"Selected tower retains its nearby public label")
				if app.board.title_rects.has(id):
					var plate: Rect2 = app.board.title_rects[id]
					check(plate.end.x < app.inspector.global_position.x,"Inspector leaves selected label visible")
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
	await check_practice()
	if DisplayServer.get_name() != "headless": await record_demo()
	print("MEDIEVAL TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check_practice() -> void:
	# Capture the real practice controller in both language modes.
	for practice_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = practice_size
		root.size = practice_size
		for chinese in [false,true]:
			FirstPlayText.chinese = chinese
			app = load("res://scenes/Main.tscn").instantiate()
			root.add_child(app)
			app._begin_play()
			await snapshot(str(practice_size.x)+"-practice-"+("zh" if chinese else "en"))
			check_layout("practice")
			var practice_board: NetworkView = app.practice.board
			practice_board.debug_anchors = true
			practice_board.queue_redraw()
			await snapshot(str(practice_size.x)+"-practice-anchors-"+("zh" if chinese else "en"))
			practice_board.debug_anchors = false
			for id in practice_board.scenario.node_positions:
				app.practice.select_shelter(id)
				await settle()
				var rect := practice_board.tower_screen_rect(id)
				check(practice_board.hit_test(rect.get_center()) == id,"Practice tower click maps to its node")
				check((practice_board.tower_world_rect(id).position+practice_board.sprite_metadata(id).ground).is_equal_approx(practice_board.network_anchor(id)),"Practice ground matches road anchor")
				check(practice_board.title_rects.has(id),"Practice inspection keeps selected label visible")
				check(rect.position.y > 152 and rect.end.y < practice_size.y-100,"Practice inspection clears controls")
			app.practice.select_shelter("E")
			await snapshot(str(practice_size.x)+"-practice-inspection-"+("zh" if chinese else "en"))
			check_layout("practice inspection")
			app.queue_free()
			await settle()
	FirstPlayText.chinese = false

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
