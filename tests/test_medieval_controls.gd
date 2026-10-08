extends "res://tests/test_presentation.gd"

func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://build/medieval-refinement/after")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	UIkit.reduced_motion = true
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_normal()
	app.session.start_private()
	app.session.open_private_form()
	await settle()
	var fields := descendants(app,"OptionButton")
	choose(fields[0],"E")
	choose(fields[1],"VERIFY")
	choose(fields[2],"E")
	choose(fields[3],"4")
	choose(fields[4],"prevent cascade")
	var draft_field: OptionButton = fields[0]
	await click("Motion:")
	check(descendants(app,"OptionButton")[0] == draft_field and draft_field.get_selected_metadata() == "E","Motion toggle preserves the actual private-form controls and draft")
	await snapshot("private-form-controls")
	app._start_dev("riverside_01_v2")
	app.session.set_dev_mode(false)
	app.session.begin_sandbox_actions()
	await settle()
	check_camera_input()
	var arrow := button_containing("End round")
	check(arrow._has_point(Vector2(arrow.size.x-4,arrow.size.y/2)),"Arrow tip is clickable")
	check(not arrow._has_point(Vector2(arrow.size.x-4,4)),"Invisible corners are not clickable")
	arrow.grab_focus()
	await snapshot("arrow-focus")
	var motion := InputEventMouseMotion.new()
	motion.position = arrow.global_position+arrow.size/2
	motion.global_position = motion.position
	root.push_input(motion,true)
	await snapshot("arrow-hover")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	press.global_position = motion.position
	press.pressed = true
	root.push_input(press,true)
	await snapshot("arrow-pressed")
	press.pressed = false
	root.push_input(press,true)
	await settle()
	check(app.modal != null and app.session.phase == GameManager.Phase.ACTIONS,"Arrow release opens original confirmation without resolving")
	await snapshot("end-round-confirmation")
	app._close_modal()
	arrow.disabled = true
	await snapshot("arrow-disabled")
	arrow.disabled = false
	UIkit.reduced_motion = false
	await settle(3) # Finish control redraws before measuring the existing timer.
	var delivery_started := Time.get_ticks_msec()
	var result: Dictionary = app.session.dispatch_action("VERIFY","H",["A"] as Array[String])
	check(result.ok,"Delivery accepted for motion timing check")
	await create_timer(0.25).timeout
	var original_board: NetworkView = app.board
	await click("Motion:")
	check(app.board == original_board and app.session.phase == GameManager.Phase.DELIVERY,"Mid-delivery motion toggle retains animation owner and delivery phase")
	await wait_delivery()
	print("Delivery wall time: %d ms" % (Time.get_ticks_msec()-delivery_started))
	check(Time.get_ticks_msec()-delivery_started >= 2000,"Long delivery retains original 1.5-second transit plus 0.55-second arrival timing")
	check(app.session.state.actions.size() == 1 and app.session.state.total_supply() == 5,"Motion toggle produces exactly one action and one supply deduction")
	app._select_shelter("G")
	await snapshot("action-controls")
	app._clear_selection()
	# A purely synthetic public-state fixture for the shared icon/light language.
	app.session.state.shelters.C.shielded_this_round = true
	app.session.state.shelters.G.is_monitored = true
	app.session.state.shelters.E.zombie_pressure = 2
	app.board.configure(app.session.scenario,app.session.state)
	await snapshot("public-states")
	var lighting: PackedVector3Array = app.board.terrain_surface.material.get_shader_parameter("beacons")
	check(lighting[4].z == 0 and lighting[2].z == 1,"Rendered forest receives only public Overrun light mask")
	check(not app.board.beacon_lit("E") and app.board.beacon_lit("C"),"Only the public Overrun beacon is extinguished")
	for depot in app.session.state.depots.values(): depot.supply_remaining = 0
	app.board.configure(app.session.scenario,app.session.state)
	check(app.board.beacon_lit("C") and app.board.beacon_lit("G"),"Functioning beacons stay lit with no stocked supply access")
	await snapshot("no-supply-still-lit")
	check(app.board.terrain_surface.material.get_shader_parameter("beacons") == lighting,"Supply loss does not change any forest illumination input")
	root.content_scale_size = Vector2i(1200,800)
	root.size = Vector2i(1200,800)
	app.session.phase = GameManager.Phase.INTERVENTION
	app.session.support_message = {"template_id":"visual.synthetic","version":"visual-only","text":"状态：这些地点的暴露情况仍然未知。请仔细比较当前公开信息，并检查已核实读数的轮次。\n建议："+"只有当前公开信息可以支持这次小组讨论。道路关闭之后，运送物资的路线可能改变；灯光不代表安全，也不会显示未知的暴露情况。".repeat(4)+"\n说明："+"This is a deliberately long synthetic layout fixture. It does not alter research text or provider behavior. ".repeat(4)}
	app._render()
	await settle(8)
	check_layout("long bilingual AI message")
	await snapshot("1200-long-bilingual-message")
	print("MEDIEVAL CONTROL TESTS: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await settle()
	quit(0 if failures == 0 else 1)

func check_camera_input() -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = app.board.size/2
	app.board._gui_input(down)
	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.relative = Vector2(55,30)
	move.position = down.position+move.relative
	app.board._gui_input(move)
	down.position = move.position
	down.pressed = false
	app.board._gui_input(down)
	check(app.board.pan != Vector2.ZERO,"Overview permits bounded dragging at base zoom")
	app.board._refresh_geometry()
	move.button_mask = 0
	move.position = app.board.positions["E"]
	app.board._gui_input(move)
	check(app.board.hover_target == "E","Interactive hover resumes after a drag")
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 10
	app.board._gui_input(pinch)
	check(app.board.zoom == 1.4,"Magnify gesture respects overview zoom limit")
	app.board.center_map(false)
