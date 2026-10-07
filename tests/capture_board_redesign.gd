extends "res://tests/test_presentation.gd"

# Visual QA capture for the light paper-board redesign (not a pass/fail suite).
#   CAPTURE_DIR=/tmp/cascade-board godot --path . --script res://tests/capture_board_redesign.gd -- --offline-tests
# Optional: CAPTURE_SIZES=1440x900,1200x800 and CAPTURE_SCALED=1 (shipped stretch).
# Piece states below are set directly on a sandbox state purely to inspect their
# drawing; they are never produced this way in play.

var sizes: Array[Vector2i] = [Vector2i(1440,900),Vector2i(1200,800)]

func shot(label: String) -> void:
	await settle(6)
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir+"/"+label+".png")

func mouse_to(point: Vector2, pressed: int = -1) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	if pressed >= 0:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = point
		button.global_position = point
		button.pressed = pressed == 1
		root.push_input(button)

func key(action_key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = action_key
	event.physical_keycode = action_key
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await settle()

func run() -> void:
	capture_dir = OS.get_environment("CAPTURE_DIR") if OS.get_environment("CAPTURE_DIR") != "" else "/tmp/cascade-board"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	if OS.get_environment("CAPTURE_SIZES") != "":
		sizes.clear()
		for part in OS.get_environment("CAPTURE_SIZES").split(","):
			var xy := part.split("x")
			sizes.append(Vector2i(int(xy[0]),int(xy[1])))
	var scaled := OS.get_environment("CAPTURE_SCALED") == "1"
	for viewport_size in sizes:
		root.content_scale_size = Vector2i(1440,900) if scaled else viewport_size
		root.size = viewport_size
		var tag := str(viewport_size.x)+"x"+str(viewport_size.y)+("-scaled" if scaled else "")
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		FirstPlayText.chinese = false
		app._show_main_menu()
		await shot(tag+"-menu-en")
		var play := button_containing("Play")
		mouse_to(play.get_global_rect().get_center())
		await create_timer(0.25).timeout
		await shot(tag+"-button-hover")
		mouse_to(play.get_global_rect().get_center(),1)
		await create_timer(0.2).timeout
		await shot(tag+"-button-pressed")
		mouse_to(play.get_global_rect().get_center(),0)
		mouse_to(Vector2(4,4))
		await create_timer(0.25).timeout
		FirstPlayText.chinese = true
		app._show_main_menu()
		await shot(tag+"-menu-zh")
		for language in ["zh","en"]:
			FirstPlayText.chinese = language == "zh"
			app._start_practice()
			await settle(8)
			await shot(tag+"-practice-"+language)
			app.practice.select_shelter("C")
			await create_timer(0.7).timeout
			await shot(tag+"-practice-selected-"+language)
		FirstPlayText.chinese = false
		for entry in ScenarioData.registry().scenarios:
			app._start_dev(entry.id)
			await settle(8)
			await shot(tag+"-overview-"+entry.id)
		# Piece and road states on Riverside.
		app._start_dev("riverside_01_v2")
		app.session.begin_sandbox_actions()
		await settle()
		var s: GameState = app.session.state
		s.shelters.B.zombie_pressure = 2
		s.shelters.C.is_monitored = true
		s.shelters.C.monitor_known_pressure = 1
		s.shelters.E.is_monitored = true
		s.shelters.D.shielded_this_round = true
		s.edges["E-F"].isolated = true
		app._render()
		await settle(8)
		await shot(tag+"-states-overview")
		app._select_shelter("E")
		await create_timer(0.7).timeout
		await shot(tag+"-states-close-E")
		app._clear_selection()
		await create_timer(0.7).timeout
		app.board.grab_focus()
		for i in 3: await key(KEY_RIGHT)
		await shot(tag+"-keyboard-focus")
		mouse_to(app.board.get_global_rect().position+app.board.positions["G"])
		await settle()
		await shot(tag+"-piece-hover")
		mouse_to(Vector2(4,4))
		# Reduced motion: route and destination are shown without a moving crate.
		UIkit.set_reduced_motion(true)
		app.session.dispatch_action("VERIFY","H",["H"] as Array[String])
		await create_timer(0.35).timeout
		await shot(tag+"-delivery-reduced-motion")
		await wait_delivery()
		UIkit.set_reduced_motion(false)
		app.session.dispatch_action("VERIFY","G",["H"] as Array[String])
		await create_timer(0.35).timeout
		await shot(tag+"-delivery-moving")
		await wait_delivery()
		app.queue_free()
		await settle()
	print("CAPTURED BOARD SCREENS in "+capture_dir)
	quit(0)
